unit uGameManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Graphics, Math, TAGraph, TASeries, BGRABitmap,
  uRingBuffer, uBassEngine, uFFTProcessor, uSQLiteHandler, uNodeTopology,
  uMormotServices, uBGRAEffects, uChartRenderer, uCommandExec;

type
  { TGameManager - Facade & Orchestrator utama yang mengintegrasikan seluruh
    subsistem (Audio DSP, Database VFS, Microservices, Graphics, dan Terminal) }
  TGameManager = class
  private
    FRingBuffer: TRingBuffer;
    FBassEngine: TBassEngine;
    FFFTProcessor: TFFTProcessor;
    FSQLiteDB: TSQLiteHandler;
    FTopology: TTopologyManager;
    FMeshService: IMeshNetworkService;
    FBGRAEffects: TBGRAEffects;
    FChartRenderer: TChartRenderer;
    FCmdContext: TCommandContext;
    FCmdExecutor: TCommandExecutor;

    FTraceLevel: Integer;
    FCpuLoad: Integer;
    FRamLoad: Integer;
    FNetLoad: Integer;
    FBasePath: string;

    { Variabel untuk mengelola event CPU Spike saat proses dekripsi }
    FIsCpuSpiking: Boolean;
    FCpuSpikeTarget: Integer;
    FCpuSpikeEndTime: QWord;

    { Variabel untuk mengelola Sistem Misi & Cerita Utama (Campaign) }
    FCampaignStage: Integer;
    FCampaignCompleted: Boolean;
    FCurrentObjective: string;

    { Variabel untuk Kondisi Menang/Kalah }
    FIsGameOver: Boolean;
    FIsGameWon: Boolean;

    { Variabel untuk Sistem Peningkatan Alat (Progression & Upgrades) }
    FDataFragments: Integer;
    FHasQuantumCPU: Boolean;
    FHasStealthVPN: Boolean;
    FHasAutoAnalyzer: Boolean;

    { Variabel untuk Serangan Balik Aktif (Active ICE) }
    FICEAttackActive: Boolean;
    FICETimer: QWord;         { Menyimpan waktu habis dalam milidetik }
    FICETargetPort: Word;     { Port acak yang sedang diserang }
    FLastICETick: QWord;      { Waktu serangan terakhir agar tidak spam }

    FOnLog: TCommandLogEvent;
    FOnClearTerminal: TCommandActionEvent;
    FOnShowAbout: TCommandActionEvent;

    procedure HandleServiceLog(const AMsg: string);
    procedure HandleNodeUpdate(ANode: TNetworkNode; ATraceDelta: Integer);
    procedure HandleCPUSpike(ALoadTarget, ADurationMS: Integer);
    procedure HandleMissionEvent(const AEventType, ATarget: string);
    procedure AdvanceCampaign(ANewStage: Integer);

    procedure ResolveICEAttack(AIsDefended: Boolean);
    function MakeBarMeter(APercent, ATotalBars: Integer; AAlert: Boolean = False): string;
  public
    constructor Create(AChart: TChart; APrimarySeries, ASecondarySeries: TLineSeries;
      AOnLog: TCommandLogEvent; AOnClear: TCommandActionEvent; AOnAbout: TCommandActionEvent);
    destructor Destroy; override;

    { Menginisialisasi seluruh engine, database, dan aset eksternal }
    procedure InitializeGame(AWindowHandle: THandle);

    { Dipanggil oleh Timer UI utama untuk memproses siklus frame (Audio -> FFT -> Chart) }
    procedure UpdateTick;

    { Merender visualisasi topologi dan efek CRT ke kanvas utama }
    procedure RenderCRT(ACanvas: TBGRABitmap);

    { Merender pop-up glassmorphism ke kanvas terpisah (InfoBox) di sebelah chart }
    procedure RenderAuxiliaryUI(ACanvas: TBGRABitmap);

    { Meneruskan string input dari TEdit ke Lexer & Command Executor }
    procedure ProcessCommand(const ACmdText: string);

    { Memicu kondisi akhir permainan secara manual (dipanggil oleh Command Exec) }
    procedure TriggerGameWon;
    procedure TriggerGameOver;

    { Menghasilkan string status berformat ASCII untuk Panel Header }
    function GetHeaderStatsText: string;
    function GetHeaderStealthText: string;
    function GetHeaderCryptoText: string;
    function GetHeaderObjectiveText: string;

    property TraceLevel: Integer read FTraceLevel;
    property CampaignCompleted: Boolean read FCampaignCompleted;
    property IsGameOver: Boolean read FIsGameOver;
    property IsGameWon: Boolean read FIsGameWon;

    { Properti untuk membaca status serangan ICE oleh antarmuka pengguna }
    property IsICEAttackActive: Boolean read FICEAttackActive;
    function ICEAttackTimeLeft: Integer;

    property BGRAEffects: TBGRAEffects read FBGRAEffects;
    property Topology: TTopologyManager read FTopology;
  end;

implementation

{ TGameManager }

constructor TGameManager.Create(AChart: TChart; APrimarySeries, ASecondarySeries: TLineSeries;
  AOnLog: TCommandLogEvent; AOnClear: TCommandActionEvent; AOnAbout: TCommandActionEvent);
begin
  inherited Create;
  FBasePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  FOnLog := AOnLog;
  FOnClearTerminal := AOnClear;
  FOnShowAbout := AOnAbout;

  FTraceLevel := 15;
  FCpuLoad := 42;
  FRamLoad := 78;
  FNetLoad := 320;

  FIsCpuSpiking := False;
  FCpuSpikeTarget := 99;
  FCpuSpikeEndTime := 0;

  FCampaignStage := 1;
  FCampaignCompleted := False;
  FCurrentObjective := '[STAGE 1/4] Check operator messages via "inbox" or "read_msg 1"';

  FIsGameOver := False;
  FIsGameWon := False;

  FDataFragments := 0;
  FHasQuantumCPU := False;
  FHasStealthVPN := False;
  FHasAutoAnalyzer := False;

  FICEAttackActive := False;
  FICETimer := 0;
  FICETargetPort := 0;
  FLastICETick := GetTickCount64;

  { 1. Inisialisasi Core Data & Audio DSP }
  FRingBuffer := TRingBuffer.Create(10); // Kapasitas 1024 sampel
  FBassEngine := TBassEngine.Create;
  FFFTProcessor := TFFTProcessor.Create(128);

  { 2. Inisialisasi Database VFS & Topologi Jaringan }
  FSQLiteDB := TSQLiteHandler.Create(FBasePath + 'asset\data\vfs_target.db');
  FTopology := TTopologyManager.Create;
  FTopology.BuildDefaultTopology;

  { 3. Inisialisasi Visual Renderer (BGRABitmap & TAChart) }
  FBGRAEffects := TBGRAEffects.Create;
  FChartRenderer := TChartRenderer.Create(AChart, APrimarySeries, ASecondarySeries, 128);

  { 4. Inisialisasi Asynchronous Microservice (mORMot 2 style) }
  FMeshService := TMeshNetworkService.Create(FTopology, FSQLiteDB,
    @HandleServiceLog, @HandleNodeUpdate);

  { 5. Inisialisasi Konteks dan Eksekutor Perintah Terminal }
  FCmdContext := TCommandContext.Create;
  FCmdContext.BassEngine := FBassEngine;
  FCmdContext.MeshService := FMeshService;
  FCmdContext.SQLiteDB := FSQLiteDB;
  FCmdContext.Topology := FTopology;
  FCmdContext.BGRAEffects := FBGRAEffects;
  FCmdContext.CampaignStage := FCampaignStage;
  FCmdContext.OnLog := FOnLog;
  FCmdContext.OnClearTerminal := FOnClearTerminal;
  FCmdContext.OnShowAbout := FOnShowAbout;
  FCmdContext.OnCPUSpike := @HandleCPUSpike;
  FCmdContext.OnMissionEvent := @HandleMissionEvent;

  FCmdExecutor := TCommandExecutor.Create(FCmdContext);
end;

destructor TGameManager.Destroy;
begin
  FreeAndNil(FCmdExecutor);
  FreeAndNil(FCmdContext);
  FMeshService := nil; // Dilepas otomatis via Reference Counting (IInvokable)
  FreeAndNil(FChartRenderer);
  FreeAndNil(FBGRAEffects);
  FreeAndNil(FTopology);
  FreeAndNil(FSQLiteDB);
  FreeAndNil(FFFTProcessor);
  FreeAndNil(FBassEngine);
  FreeAndNil(FRingBuffer);
  inherited Destroy;
end;

procedure TGameManager.InitializeGame(AWindowHandle: THandle);
var
  TargetNode: TNetworkNode;
begin
  { Hubungkan ke SQLite VFS }
  if FSQLiteDB.Connect then
    HandleServiceLog('[*] SQLite3 Virtual File System mounted successfully.')
  else
    HandleServiceLog('[!] Warning: SQLite3 VFS running in fallback memory mode.');

  { Inisialisasi BASS Audio Engine }
  if FBassEngine.Initialize(FBasePath + 'bass.dll', AWindowHandle) then
  begin
    HandleServiceLog('[*] BASS Audio DSP Engine initialized (44.1kHz).');
    FBassEngine.PlayBGM(FBasePath + 'asset\audio\bgm_ambient.wav');

    { Memutar sinyal audio awal dari proxy pertama }
    if Assigned(FTopology.ActiveNode) then
      FBassEngine.PlaySignal(FBasePath + 'asset\audio\signal_450hz.wav', FTopology.ActiveNode.SignalFreq);
  end
  else
    HandleServiceLog('[*] BASS DLL/Audio not found. Engaging Synthetic DSP Wave Generator.');

  { Tampilkan pop-up target awal sesuai desain }
  TargetNode := FTopology.FindNodeByIP(FTopology.TargetNodeIP);
  if Assigned(TargetNode) then
  begin
    FBGRAEffects.SetInterceptPopup(True,
      ':::: INTERCEPTED DATA (GLASSMORPH) ::::',
      TargetNode.OpenPort, TargetNode.HandshakeHash, 'DECRYPTING... [||||....]');
  end;

  HandleServiceLog('[!] INCOMING TRANSMISSION: 1 unread message from Handler [ZERO]. Type "inbox" to view.');
end;

procedure TGameManager.UpdateTick;
var
  CurrentTime: QWord;
begin
  { Jangan update logic jika game sudah selesai }
  if FIsGameOver or FIsGameWon then Exit;

  CurrentTime := GetTickCount64;

  { 1. Manajemen Serangan Active ICE }
  if FICEAttackActive then
  begin
    { Jika pemain gagal merespons tepat waktu }
    if CurrentTime > FICETimer then
      ResolveICEAttack(False);
  end
  else
  begin
    { Pastikan pemain minimal berada di Stage 2 (tahu cara main)
      dan kurangi probabilitas (dari Random(200) menjadi Random(1500))
      agar serangan terasa adil dan dapat dikelola oleh manusia. }
    if (not FCampaignCompleted) and (FCampaignStage > 1) and (CurrentTime > FLastICETick + 20000) then
    begin
      { Peluang 1/1500 setiap frame/tick (~4% peluang setiap detik jika 60fps) }
      if Random(1500) = 0 then
      begin
        FICEAttackActive := True;
        FICETargetPort := Word(EnsureRange(Random(9999), 1024, 8080));
        FICETimer := CurrentTime + 10000; // Beri pemain waktu 10 detik

        if Assigned(FBassEngine) then
          FBassEngine.PlaySignal(FBasePath + 'asset\audio\alarm_beep.wav', 600);

        HandleServiceLog('');
        HandleServiceLog(Format('>>>>> SYSTEM ALERT: INCOMING CONNECTION DETECTED ON PORT %d <<<<<', [FICETargetPort]));
        HandleServiceLog(Format('>>>>> QUICK! Type "block_port %d" to defend! <<<<<', [FICETargetPort]));
        HandleServiceLog('');
      end;
    end;
  end;

  { 2. Tarik data spektrum dari BASS / Synthetic Generator ke RingBuffer }
  FBassEngine.CaptureFFTToRingBuffer(FRingBuffer);

  { 3. Olah sampel di FFTProcessor dan perbarui grafik TAChart }
  if FFFTProcessor.ProcessBuffer(FRingBuffer) then
    FChartRenderer.RenderSpectrum(FFFTProcessor);

  { 4. Fluktuasi metrik sistem secara dinamis }
  if FIsCpuSpiking then
  begin
    if CurrentTime > FCpuSpikeEndTime then
      FIsCpuSpiking := False
    else
    begin
      FCpuLoad := EnsureRange(FCpuSpikeTarget - Random(5), 90, 100);
      FRamLoad := EnsureRange(FRamLoad + (Random(5) - 1), 85, 99);
    end;
  end
  else
  begin
    FCpuLoad := EnsureRange(FCpuLoad + (Random(7) - 3), 25, 68);
    FRamLoad := EnsureRange(FRamLoad + (Random(3) - 1), 60, 85);
  end;

  FNetLoad := EnsureRange(FNetLoad + (Random(41) - 20), 120, 980);
end;

procedure TGameManager.ResolveICEAttack(AIsDefended: Boolean);
var
  Penalty: Integer;
begin
  FICEAttackActive := False;
  FLastICETick := GetTickCount64; // Reset timer istirahat

  if AIsDefended then
  begin
    HandleServiceLog('[+] ICE ATTACK BLOCKED! Port secured successfully.');
  end
  else
  begin
    HandleServiceLog('[-] ICE ATTACK FAILED TO BLOCK! Counter-measure engaged by enemy admin!');
    Penalty := 30;

    if FHasStealthVPN then
      Penalty := 20; // Diskon penalti jika punya VPN

    HandleNodeUpdate(nil, Penalty);
    HandleServiceLog(Format('[-] WARNING: Trace meter spiked by %d%%!', [Penalty]));
  end;
end;

procedure TGameManager.RenderCRT(ACanvas: TBGRABitmap);
begin
  if not Assigned(ACanvas) then Exit;

  { 1. Gambar peta topologi jaringan di kanvas utama }
  FBGRAEffects.RenderTopology(ACanvas, FTopology);

  { 2. Terapkan post-processing CRT scanlines ke seluruh kanvas utama }
  FBGRAEffects.ApplyCRTEffect(ACanvas);

  { Catatan: RenderGlassPopup dipindahkan ke RenderAuxiliaryUI }
end;

procedure TGameManager.RenderAuxiliaryUI(ACanvas: TBGRABitmap);
var
  PopupRect: TRect;
begin
  if not Assigned(ACanvas) then Exit;

  { Menyesuaikan kotak popup agar memenuhi area PaintBox yang baru (pbInfoBox) }
  { Menyisakan sedikit margin (10 pixel) di sekelilingnya }
  PopupRect := Rect(10, 10, ACanvas.Width - 10, ACanvas.Height - 10);

  { Gambar pop-up Glassmorphism ke kanvas terpisah }
  FBGRAEffects.RenderGlassPopup(ACanvas, PopupRect);
end;

procedure TGameManager.ProcessCommand(const ACmdText: string);
begin
  if FIsGameOver or FIsGameWon then Exit;

  if Assigned(FCmdExecutor) then
    FCmdExecutor.ExecuteInput(ACmdText);
end;

procedure TGameManager.TriggerGameWon;
begin
  if FIsGameOver then Exit;
  FIsGameWon := True;
  FICEAttackActive := False; // Hentikan serangan yang sedang berjalan jika ada

  if Assigned(FBassEngine) then
  begin
    FBassEngine.StopAll;
  end;

  HandleServiceLog('================================================================');
  HandleServiceLog('[+] MISSION ACCOMPLISHED: The Signal Cartel network has been purged.');
  HandleServiceLog('[+] Initiating secure disconnect sequence...');
  HandleServiceLog('================================================================');
end;

procedure TGameManager.TriggerGameOver;
begin
  if FIsGameWon then Exit;
  FIsGameOver := True;
  FICEAttackActive := False;

  if Assigned(FBassEngine) then
  begin
    FBassEngine.StopAll;
    { Mainkan suara sirene / alarm }
    FBassEngine.PlaySignal(FBasePath + 'asset\audio\alarm_siren.wav', 1000);
  end;

  if Assigned(FBGRAEffects) then
    FBGRAEffects.SetCriticalAlarm(True);

  HandleServiceLog('================================================================');
  HandleServiceLog('[!] CRITICAL FAILURE: PHYSICAL LOCATION TRACED. SYSTEM PURGED.');
  HandleServiceLog('[!] Cartel hitmen dispatched to your location. Disconnecting...');
  HandleServiceLog('================================================================');
end;

procedure TGameManager.HandleServiceLog(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

procedure TGameManager.HandleCPUSpike(ALoadTarget, ADurationMS: Integer);
begin
  FIsCpuSpiking := True;
  FCpuSpikeTarget := ALoadTarget;

  { Quantum CPU Upgrade: Mempersingkat durasi efek lag/spike CPU secara drastis }
  if FHasQuantumCPU then
    ADurationMS := ADurationMS div 3;

  FCpuSpikeEndTime := GetTickCount64 + QWord(ADurationMS);
end;

procedure TGameManager.AdvanceCampaign(ANewStage: Integer);
var
  DeadDropNode, TargetNode: TNetworkNode;
begin
  if ANewStage <= FCampaignStage then Exit;

  FCampaignStage := ANewStage;
  if Assigned(FCmdContext) then
    FCmdContext.CampaignStage := FCampaignStage;

  case FCampaignStage of
    2:
      begin
        TargetNode := FTopology.FindNodeByIP(FTopology.TargetNodeIP);
        FCurrentObjective := Format('[STAGE 2/4] Scan %dHz, extract key, & deploy_bot to %s',
                                    [TargetNode.SignalFreq, TargetNode.IPAddress]);
        HandleServiceLog(Format('[*] OBJECTIVE UPDATED: Breach TARGET_MAINFRAME (%s).', [TargetNode.IPAddress]));
      end;
    3:
      begin
        FCurrentObjective := Format('[STAGE 3/4] Decrypt & read /opt/cartel/uplink.cfg on %s',
                                    [FTopology.TargetNodeIP]);
        HandleServiceLog('[!] NEW MESSAGE RECEIVED: Msg #2 from [ZERO]. Type "read_msg 2".');
      end;
    4:
      begin
        DeadDropNode := FTopology.UnlockDeadDropNode;
        FBGRAEffects.InvalidateBlurCache;
        if Assigned(DeadDropNode) then
        begin
          FFFTProcessor.TargetFreq := DeadDropNode.SignalFreq;
          FBassEngine.ActiveFreq := DeadDropNode.SignalFreq;
        end;
        FCurrentObjective := '[STAGE 4/4] Breach DEAD_DROP (10.0.0.99) & read /secret/cartel_manifest.enc';
        HandleServiceLog('[+] TOPOLOGY UPDATED: Hidden node DEAD_DROP (10.0.0.99) unlocked on CRT!');
        HandleServiceLog('[!] NEW MESSAGE RECEIVED: Msg #3 from [ZERO]. Type "read_msg 3".');
      end;
    5:
      begin
        FCampaignCompleted := True;
        FCurrentObjective := '[STAGE 5/5] Type "upload_evidence cartel_manifest.txt" to end mission!';
        HandleServiceLog('================================================================');
        HandleServiceLog('[+] MANIFEST EXTRACTED! The cartel''s secrets are in your hands.');
        HandleServiceLog('[!] NEW MESSAGE RECEIVED: Msg #4 from [ZERO]. Type "read_msg 4".');
        HandleServiceLog('================================================================');
      end;
  end;
end;

procedure TGameManager.HandleMissionEvent(const AEventType, ATarget: string);
var
  BonusFragments: Integer;
  DefendedPort: Word;
begin
  if SameText(AEventType, 'READ_MSG') then
  begin
    if (FCampaignStage = 1) and ((ATarget = '1') or SameText(ATarget, 'INBOX')) then
      AdvanceCampaign(2);
  end
  else if SameText(AEventType, 'CAT_FILE') then
  begin
    if (FCampaignStage <= 3) and SameText(ATarget, '/opt/cartel/uplink.cfg') then
      AdvanceCampaign(4)
    else if (FCampaignStage <= 4) and SameText(ATarget, '/secret/cartel_manifest.enc') then
      AdvanceCampaign(5);
  end
  else if SameText(AEventType, 'UPLOAD_EVIDENCE') then
  begin
    if FCampaignCompleted then
      TriggerGameWon
    else
      HandleServiceLog('[-] Error: You do not have the complete cartel manifest yet.');
  end
  else if SameText(AEventType, 'REWARD_FRAGMENTS') then
  begin
    BonusFragments := StrToIntDef(ATarget, 10);
    Inc(FDataFragments, BonusFragments);
    HandleServiceLog(Format('[+] WALLET UPDATED: Acquired %d Data Fragments from node extraction.', [BonusFragments]));
  end
  else if SameText(AEventType, 'PURCHASE_MODULE') then
  begin
    if SameText(ATarget, 'QCPU') then FHasQuantumCPU := True
    else if SameText(ATarget, 'SVPN') then FHasStealthVPN := True
    else if SameText(ATarget, 'AANALYZER') then
    begin
      FHasAutoAnalyzer := True;
      if Assigned(FCmdContext) then FCmdContext.HasAutoAnalyzer := True;
    end;
  end
  else if SameText(AEventType, 'DEDUCT_FRAGMENTS') then
  begin
    Dec(FDataFragments, StrToIntDef(ATarget, 0));
  end
  else if SameText(AEventType, 'BLOCK_PORT') then
  begin
    DefendedPort := StrToIntDef(ATarget, 0);
    if FICEAttackActive then
    begin
      if DefendedPort = FICETargetPort then
        ResolveICEAttack(True)
      else
        HandleServiceLog(Format('[-] WRONG PORT! The enemy is attacking on port %d, not %d.', [FICETargetPort, DefendedPort]));
    end
    else
      HandleServiceLog('[*] Port blocked successfully, but no active ICE attack was detected.');
  end;

  if Assigned(FCmdContext) then
    FCmdContext.DataFragments := FDataFragments;
end;

procedure TGameManager.HandleNodeUpdate(ANode: TNetworkNode; ATraceDelta: Integer);
begin
  if FIsGameOver or FIsGameWon then Exit;

  { Stealth VPN Upgrade: Mengurangi tingkat keparahan saat terlacak (bounce/deploy) sebesar 30% }
  if FHasStealthVPN and (ATraceDelta > 0) then
    ATraceDelta := Round(ATraceDelta * 0.7);

  FTraceLevel := EnsureRange(FTraceLevel + ATraceDelta, 0, 100);
  FBGRAEffects.InvalidateBlurCache;

  if Assigned(ANode) then
  begin
    FFFTProcessor.TargetFreq := ANode.SignalFreq;
    FBassEngine.ActiveFreq := ANode.SignalFreq;

    if ANode.IsCompromised then
    begin
      FBGRAEffects.SetInterceptPopup(True,
        ':::: TARGET COMPROMISED (ROOT) ::::',
        ANode.OpenPort, ANode.HandshakeHash, 'ACCESS GRANTED [++++++++]');

      if (FCampaignStage <= 2) and SameText(ANode.IPAddress, FTopology.TargetNodeIP) then
        AdvanceCampaign(3);
    end
    else if ANode.IsScanned then
      FBGRAEffects.SetInterceptPopup(True,
        ':::: INTERCEPTED DATA (GLASSMORPH) ::::',
        ANode.OpenPort, ANode.HandshakeHash, 'DECRYPTING... [||||....]');
  end;

  if FTraceLevel >= 100 then
    TriggerGameOver;
end;

function TGameManager.ICEAttackTimeLeft: Integer;
begin
  if not FICEAttackActive then
    Result := 0
  else
    Result := EnsureRange(Integer(FICETimer - GetTickCount64), 0, 10000);
end;

function TGameManager.MakeBarMeter(APercent, ATotalBars: Integer; AAlert: Boolean): string;
var
  Filled, i: Integer;
begin
  Filled := Round((EnsureRange(APercent, 0, 100) / 100) * ATotalBars);
  Result := '[';
  for i := 1 to ATotalBars do
  begin
    if i <= Filled then
    begin
      if AAlert and (i = ATotalBars) then
        Result := Result + '!'
      else
        Result := Result + '|';
    end
    else
      Result := Result + '.';
  end;
  Result := Result + ']';
end;

function TGameManager.GetHeaderStatsText: string;
var
  ProxyIP: string;
begin
  if Assigned(FTopology.ActiveNode) then
    ProxyIP := FTopology.ActiveNode.IPAddress
  else
    ProxyIP := '14.1.2.9';

  Result := Format('[::] ECHO-OS v1.99 | CPU: %s %d%% | RAM: %s %d%% | PROXY: %s [ACTIVE] [::]',
    [MakeBarMeter(FCpuLoad, 10, FIsCpuSpiking), FCpuLoad,
     MakeBarMeter(FRamLoad, 10, FIsCpuSpiking), FRamLoad,
     ProxyIP]);
end;

function TGameManager.GetHeaderStealthText: string;
var
  WarnStr: string;
begin
  if FTraceLevel >= 50 then
    WarnStr := 'WARNING: TRACE DETECTED'
  else
    WarnStr := 'STATUS: STEALTH NOMINAL';

  Result := Format('[::] STEALTH METER: %s %s | NET LOAD: %s %d Kbps    [::]',
    [MakeBarMeter(FTraceLevel, 10, FTraceLevel >= 50),
     WarnStr,
     MakeBarMeter(FNetLoad div 10, 10),
     FNetLoad]);
end;

function TGameManager.GetHeaderCryptoText: string;
var
  M1, M2, M3: string;
begin
  if FHasQuantumCPU then M1 := 'X' else M1 := ' ';
  if FHasStealthVPN then M2 := 'X' else M2 := ' ';
  if FHasAutoAnalyzer then M3 := 'X' else M3 := ' ';

  Result := Format('[::] WALLET: %-3d DATA FRAGMENTS | MODULES: [%s] Q-CPU  [%s] S-VPN  [%s] A-ANALYZER             [::]',
    [FDataFragments, M1, M2, M3]);
end;

function TGameManager.GetHeaderObjectiveText: string;
begin
  Result := Format('[::] CURRENT OBJECTIVE: %-72s [::]', [FCurrentObjective]);
end;

end.
