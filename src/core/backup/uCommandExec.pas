unit uCommandExec;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, uTerminalLexer, uBassEngine,
  uMormotServices, uSQLiteHandler, uNodeTopology, uBGRAEffects;

type
  TCommandLogEvent = procedure(const AMsg: string) of object;
  TCommandActionEvent = procedure of object;
  { Event untuk memicu efek CPU spike selama proses dekripsi (di Game Manager) }
  TCommandCPUEvent = procedure(ALoadTarget, ADurationMS: Integer) of object;
  { Event untuk memberi tahu Game Manager bahwa progres misi tercapai }
  TCommandMissionEvent = procedure(const AEventType, ATarget: string) of object;

  { TCommandContext - Menyimpan referensi ke seluruh subsistem engine game
    agar dapat diakses oleh perintah terminal secara modular }
  TCommandContext = class
  public
    BassEngine: TBassEngine;
    MeshService: IMeshNetworkService;
    SQLiteDB: TSQLiteHandler;
    Topology: TTopologyManager;
    BGRAEffects: TBGRAEffects;
    CampaignStage: Integer;
    DataFragments: Integer;
    HasAutoAnalyzer: Boolean;
    OnLog: TCommandLogEvent;
    OnClearTerminal: TCommandActionEvent;
    OnShowAbout: TCommandActionEvent;
    OnCPUSpike: TCommandCPUEvent;
    OnMissionEvent: TCommandMissionEvent;
    procedure Log(const AMsg: string);
  end;

  { TCustomTerminalCommand - Base class untuk Command Pattern (GoF) }
  TCustomTerminalCommand = class
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); virtual; abstract;
    function GetHelpDescription: string; virtual; abstract;
  end;

  TCommandDictionary = specialize TObjectDictionary<string, TCustomTerminalCommand>;

  { TCommandExecutor - Registry dan dispatcher perintah terminal O(1) }
  TCommandExecutor = class
  private
    FCommands: TCommandDictionary;
    FContext: TCommandContext;
    FParsedCmd: TParsedCommand;
    procedure RegisterDefaultCommands;
  public
    constructor Create(AContext: TCommandContext);
    destructor Destroy; override;

    procedure RegisterCommand(const AName: string; ACommand: TCustomTerminalCommand);
    procedure ExecuteInput(const ARawInput: string);
  end;

implementation

type
  TCmdHelp = class(TCustomTerminalCommand)
  private
    FRegistry: TCommandDictionary;
  public
    constructor Create(ARegistry: TCommandDictionary);
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdClear = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdScanFreq = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdApplyFilter = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdModulatePhase = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdDeployBot = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdBounceIP = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdSQLInject = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdLsVFS = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdCatVFS = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdDecryptVFS = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  { PERINTAH CAMPAIGN: inbox }
  TCmdInbox = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  { PERINTAH CAMPAIGN: read_msg }
  TCmdReadMsg = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  { PERINTAH CAMPAIGN AKHIR: upload_evidence }
  TCmdUploadEvidence = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  { PERINTAH TOKO MODUL (Progression System) }
  TCmdBlackMarket = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdUpgrade = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  { PERINTAH PERTAHANAN (Active ICE) }
  TCmdBlockPort = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

  TCmdAbout = class(TCustomTerminalCommand)
  public
    procedure Execute(AParsed: TParsedCommand; AContext: TCommandContext); override;
    function GetHelpDescription: string; override;
  end;

{ TCommandContext }

procedure TCommandContext.Log(const AMsg: string);
begin
  if Assigned(OnLog) then
    OnLog(AMsg);
end;

{ TCmdHelp }

constructor TCmdHelp.Create(ARegistry: TCommandDictionary);
begin
  inherited Create;
  FRegistry := ARegistry;
end;

procedure TCmdHelp.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  Key: string;
begin
  AContext.Log('[*] ECHO-OS Available Commands:');
  for Key in FRegistry.Keys do
    AContext.Log(Format('  %-16s : %s', [Key, FRegistry[Key].GetHelpDescription]));
end;

function TCmdHelp.GetHelpDescription: string;
begin
  Result := 'Display this command reference list';
end;

{ TCmdClear }

procedure TCmdClear.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
begin
  if Assigned(AContext.OnClearTerminal) then
    AContext.OnClearTerminal();
end;

function TCmdClear.GetHelpDescription: string;
begin
  Result := 'Clear terminal screen stdout buffer';
end;

{ TCmdScanFreq }

procedure TCmdScanFreq.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  RangeStr: string;
  DashPos, FMin, FMax: Integer;
begin
  if AContext.HasAutoAnalyzer then
  begin
    AContext.Log('[+] AUTO-ANALYZER ACTIVE: Optimal scan range is 30 - 90');
  end;

  RangeStr := AParsed.GetFlagValue('r', AParsed.GetFlagValue('range', '20-500'));
  DashPos := Pos('-', RangeStr);
  if DashPos > 0 then
  begin
    FMin := StrToIntDef(Copy(RangeStr, 1, DashPos - 1), 20);
    FMax := StrToIntDef(Copy(RangeStr, DashPos + 1, MaxInt), 500);
    if (FMin < 100) and (FMax <= 100) then
    begin
      FMin := FMin * 10;
      FMax := FMax * 10;
    end;
  end
  else
  begin
    FMin := 100;
    FMax := 900;
  end;

  if Assigned(AContext.MeshService) then
    AContext.MeshService.AsyncScanFrequency(FMin, FMax)
  else
    AContext.Log('[-] Error: mORMot2 Mesh Service not initialized.');
end;

function TCmdScanFreq.GetHelpDescription: string;
begin
  Result := 'Scan acoustic spectrum (e.g., scan_freq -r 20-50)';
end;

{ TCmdApplyFilter }

procedure TCmdApplyFilter.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  EnableFilter: Boolean;
begin
  if not Assigned(AContext.BassEngine) then Exit;

  EnableFilter := AParsed.HasFlag('bp') or AParsed.HasFlag('bandpass');
  if AParsed.HasFlag('off') then EnableFilter := False;

  AContext.BassEngine.ApplyBandpassFilter(EnableFilter);
  if EnableFilter then
  begin
    AContext.Log('[*] Decimation Ring Buffer: OK');
    AContext.Log('[+] Bandpass filter engaged. Background noise suppressed.');
  end
  else
    AContext.Log('[*] Audio DSP filters deactivated.');
end;

function TCmdApplyFilter.GetHelpDescription: string;
begin
  Result := 'Engage DSP bandpass filter (apply_filter -bp | -off)';
end;

{ TCmdModulatePhase }

procedure TCmdModulatePhase.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  Invert: Boolean;
  ActiveTarget: TNetworkNode;
begin
  if not Assigned(AContext.BassEngine) then Exit;

  Invert := AParsed.HasFlag('invert') or AParsed.HasFlag('inv') or (not AContext.BassEngine.PhaseInverted);
  AContext.BassEngine.InvertPhase(Invert);
  AContext.Log('[+] Phase modulated (180 deg inversion: ' + BoolToStr(Invert, 'ACTIVE', 'OFF') + ')');

  if AContext.BassEngine.BandpassActive and Invert then
  begin
    AContext.Log('[+] Handshake key intercepted from carrier wave!');
    if Assigned(AContext.Topology) and Assigned(AContext.BGRAEffects) then
    begin
      { Gunakan node yang terakhir dipindai agar mendukung Target maupun Dead Drop }
      ActiveTarget := AContext.Topology.LastScannedNode;
      if not Assigned(ActiveTarget) then
        ActiveTarget := AContext.Topology.FindNodeByIP(AContext.Topology.TargetNodeIP);

      if Assigned(ActiveTarget) then
      begin
        AContext.Log(Format('[+] Target [%s] Key Extracted: %s',
          [ActiveTarget.IPAddress, ActiveTarget.HandshakeHash]));
        AContext.BGRAEffects.SetInterceptPopup(True,
          ':::: INTERCEPTED DATA (GLASSMORPH) ::::',
          ActiveTarget.OpenPort, ActiveTarget.HandshakeHash, 'DECRYPTED [||||||||]');
      end;
    end;
  end;
end;

function TCmdModulatePhase.GetHelpDescription: string;
begin
  Result := 'Invert signal phase to extract keys (modulate_phase -invert)';
end;

{ TCmdDeployBot }

procedure TCmdDeployBot.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  TargetIP: string;
  IsStealth: Boolean;
begin
  TargetIP := AParsed.GetFlagValue('tgt', AParsed.GetFlagValue('target', ''));
  if (TargetIP = '') and (AParsed.PositionalArgs.Count > 0) then
    TargetIP := AParsed.PositionalArgs[0];

  if TargetIP = '' then
  begin
    AContext.Log('[-] Usage: deploy_bot -tgt <ip_address> [-stealth]');
    Exit;
  end;

  IsStealth := AParsed.HasFlag('stealth') or AParsed.HasFlag('s');
  if Assigned(AContext.MeshService) then
    AContext.MeshService.AsyncDeployBotnet(TargetIP, IsStealth);
end;

function TCmdDeployBot.GetHelpDescription: string;
begin
  Result := 'Deploy exploit botnet (deploy_bot -tgt 192.168.0.4 -stealth)';
end;

{ TCmdBounceIP }

procedure TCmdBounceIP.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  ProxyIP: string;
begin
  ProxyIP := AParsed.GetFlagValue('ip', '');
  if (ProxyIP = '') and (AParsed.PositionalArgs.Count > 0) then
    ProxyIP := AParsed.PositionalArgs[0];

  if ProxyIP = '' then
    ProxyIP := '192.168.0.1';

  if Assigned(AContext.MeshService) then
    AContext.MeshService.AsyncBounceProxy(ProxyIP);
end;

function TCmdBounceIP.GetHelpDescription: string;
begin
  Result := 'Reroute proxy to reduce trace meter (bounce_ip <ip>)';
end;

{ TCmdSQLInject }

procedure TCmdSQLInject.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  QueryStr: string;
  OutList: TStringList;
  i: Integer;
begin
  if not Assigned(AContext.SQLiteDB) then Exit;

  QueryStr := AParsed.GetFlagValue('q', '');
  if (QueryStr = '') and (AParsed.PositionalArgs.Count > 0) then
    QueryStr := AParsed.PositionalArgs[0];

  if QueryStr = '' then
  begin
    AContext.Log('[-] Usage: sql_inject -q "SELECT * FROM target_nodes"');
    Exit;
  end;

  OutList := TStringList.Create;
  try
    AContext.Log('[*] Executing raw SQL payload on target VFS...');
    if AContext.SQLiteDB.ExecuteRawSelect(QueryStr, OutList) then
    begin
      for i := 0 to OutList.Count - 1 do
        AContext.Log('    ' + OutList[i]);
    end
    else if OutList.Count > 0 then
      AContext.Log(OutList[0]);
  finally
    OutList.Free;
  end;
end;

function TCmdSQLInject.GetHelpDescription: string;
begin
  Result := 'Execute SQL injection on VFS (sql_inject -q "SELECT...")';
end;

{ TCmdLsVFS }

procedure TCmdLsVFS.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  TargetIP: string;
  OutFiles: TStringList;
  i: Integer;
begin
  if not Assigned(AContext.SQLiteDB) then Exit;

  { Default ke Target Node yang di-generate prosedural }
  TargetIP := AParsed.GetFlagValue('ip', AContext.Topology.TargetNodeIP);

  if (AParsed.PositionalArgs.Count > 0) then
    TargetIP := AParsed.PositionalArgs[0];

  OutFiles := TStringList.Create;
  try
    AContext.SQLiteDB.GetNodeVFS(TargetIP, OutFiles);
    AContext.Log(Format('[*] VFS Directory Listing for [%s]:', [TargetIP]));
    if OutFiles.Count = 0 then
      AContext.Log('    (No accessible files found)')
    else
      for i := 0 to OutFiles.Count - 1 do
        AContext.Log('    ' + OutFiles[i]);
  finally
    OutFiles.Free;
  end;
end;

function TCmdLsVFS.GetHelpDescription: string;
begin
  Result := 'List virtual file system of node (ls_vfs <ip>)';
end;

{ TCmdCatVFS }

procedure TCmdCatVFS.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  TargetIP, FilePath, Content: string;
  IsEncrypted: Boolean;
begin
  if not Assigned(AContext.SQLiteDB) then Exit;

  TargetIP := AParsed.GetFlagValue('ip', AContext.Topology.TargetNodeIP);
  FilePath := '';
  if AParsed.PositionalArgs.Count > 0 then
    FilePath := AParsed.PositionalArgs[0];

  if FilePath = '' then
  begin
    AContext.Log('[-] Usage: cat <file_path> [-ip <target_ip>]');
    Exit;
  end;

  if AContext.SQLiteDB.ReadFileContent(TargetIP, FilePath, Content, IsEncrypted) then
  begin
    AContext.Log(Format('--- START OF FILE: %s ---', [FilePath]));
    if IsEncrypted then
    begin
      AContext.Log('// [ERROR] FILE ENCRYPTED: MILITARY GRADE AES-256');
      AContext.Log('// Use decrypt command with valid -key to extract.');
      AContext.Log(StringOfChar('X', 40) + '0xDEADBEEF');
    end
    else
    begin
      AContext.Log(Content);
      AContext.Log('--- END OF FILE ---');

      { Pemicu Misi }
      if Assigned(AContext.OnMissionEvent) then
        AContext.OnMissionEvent('CAT_FILE', FilePath);

      { REWARD SISTEM PROGRESSION: Berikan Fragmen Data ke Dompet }
      if Assigned(AContext.OnMissionEvent) then
      begin
        if Pos('.enc', FilePath) > 0 then
          AContext.OnMissionEvent('REWARD_FRAGMENTS', '50')
        else if Pos('.cfg', FilePath) > 0 then
          AContext.OnMissionEvent('REWARD_FRAGMENTS', '20')
        else
          AContext.OnMissionEvent('REWARD_FRAGMENTS', '10');
      end;

      Exit;
    end;
    AContext.Log('--- END OF FILE ---');
  end
  else
    AContext.Log(Format('[-] File "%s" not found on target %s.', [FilePath, TargetIP]));
end;

function TCmdCatVFS.GetHelpDescription: string;
begin
  Result := 'Read file content from VFS (cat /etc/passwd)';
end;

{ TCmdDecryptVFS }

procedure TCmdDecryptVFS.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  TargetIP, FilePath, KeyHash: string;
begin
  if not Assigned(AContext.SQLiteDB) then Exit;

  TargetIP := AParsed.GetFlagValue('ip', AContext.Topology.TargetNodeIP);
  KeyHash := AParsed.GetFlagValue('key', '');
  FilePath := '';

  if AParsed.PositionalArgs.Count > 0 then
    FilePath := AParsed.PositionalArgs[0];

  if (FilePath = '') or (KeyHash = '') then
  begin
    AContext.Log('[-] Usage: decrypt <file_path> -key <hash> [-ip <target_ip>]');
    Exit;
  end;

  AContext.Log('[*] Initializing decryption sequence...');

  { Memicu event CPU spike ke GameManager selama 1.5 detik }
  if Assigned(AContext.OnCPUSpike) then
    AContext.OnCPUSpike(99, 1500);

  if AContext.SQLiteDB.DecryptFile(TargetIP, FilePath, KeyHash) then
  begin
    AContext.Log('[+] Decryption successful! Access granted.');
    AContext.Log('[+] File is now readable using the "cat" command.');
  end
  else
    AContext.Log('[-] Decryption failed. Invalid hash key for target node.');
end;

function TCmdDecryptVFS.GetHelpDescription: string;
begin
  Result := 'Decrypt encrypted file (decrypt <file> -key <hash>)';
end;

{ TCmdInbox }

procedure TCmdInbox.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
begin
  AContext.Log('[*] ENCRYPTED OPERATOR INBOX (Handler: [ZERO]):');
  AContext.Log('  [1] [ZERO] - Operation: Acoustic Breach (Briefing)');
  if AContext.CampaignStage >= 3 then
    AContext.Log('  [2] [ZERO] - Mainframe Infiltrated: Find the Uplink');
  if AContext.CampaignStage >= 4 then
    AContext.Log('  [3] [ZERO] - Target Located: DEAD_DROP Server (10.0.0.99)');
  if AContext.CampaignStage >= 5 then
    AContext.Log('  [4] [ZERO] - DEBFRIEF: The Signal Cartel Exposed!');
  AContext.Log('[*] Type "read_msg <id>" to read a message (e.g., read_msg 1).');

  if Assigned(AContext.OnMissionEvent) then
    AContext.OnMissionEvent('READ_MSG', 'INBOX');
end;

function TCmdInbox.GetHelpDescription: string;
begin
  Result := 'Check encrypted mission messages from Handler';
end;

{ TCmdReadMsg }

procedure TCmdReadMsg.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  MsgID: Integer;
  IdStr: string;
  TargetNode: TNetworkNode;
begin
  IdStr := AParsed.GetFlagValue('id', '');
  if (IdStr = '') and (AParsed.PositionalArgs.Count > 0) then
    IdStr := AParsed.PositionalArgs[0];

  MsgID := StrToIntDef(IdStr, 0);
  if MsgID = 0 then
  begin
    AContext.Log('[-] Usage: read_msg <message_number> (e.g., read_msg 1)');
    Exit;
  end;

  { Ambil informasi target dinamis dari topologi }
  TargetNode := AContext.Topology.FindNodeByIP(AContext.Topology.TargetNodeIP);

  if (MsgID = 1) and Assigned(TargetNode) then
  begin
    AContext.Log('================ MESSAGE #1 FROM [ZERO] ================');
    AContext.Log('Operator, welcome to ECHO-OS. The Signal Cartel is hiding');
    AContext.Log('their network keys inside acoustic carrier waves.');
    AContext.Log(Format('1. Run "scan_freq -r %d-%d" to lock onto %s (%dHz).',
                 [(TargetNode.SignalFreq div 10) - 1, (TargetNode.SignalFreq div 10) + 1, TargetNode.IPAddress, TargetNode.SignalFreq]));
    AContext.Log('2. Run "apply_filter -bp" and "modulate_phase -invert".');
    AContext.Log(Format('3. Breach the node via "deploy_bot -tgt %s -stealth".', [TargetNode.IPAddress]));
    AContext.Log('========================================================');
    if Assigned(AContext.OnMissionEvent) then
      AContext.OnMissionEvent('READ_MSG', '1');
  end
  else if (MsgID = 2) and (AContext.CampaignStage >= 3) and Assigned(TargetNode) then
  begin
    AContext.Log('================ MESSAGE #2 FROM [ZERO] ================');
    AContext.Log(Format('Great work breaching TARGET_MAINFRAME (%s).', [TargetNode.IPAddress]));
    AContext.Log(Format('Now inspect its files using "ls_vfs %s".', [TargetNode.IPAddress]));
    AContext.Log(Format('Decrypt "/opt/cartel/uplink.cfg" using key %s:', [TargetNode.HandshakeHash]));
    AContext.Log(Format('  decrypt /opt/cartel/uplink.cfg -key %s', [TargetNode.HandshakeHash]));
    AContext.Log('Then read it with: cat /opt/cartel/uplink.cfg');
    AContext.Log('========================================================');
  end
  else if (MsgID = 3) and (AContext.CampaignStage >= 4) then
  begin
    AContext.Log('================ MESSAGE #3 FROM [ZERO] ================');
    AContext.Log('We found their hidden server! Node 10.0.0.99 (DEAD_DROP)');
    AContext.Log('is now visible on your CRT map, broadcasting at 880Hz.');
    AContext.Log('1. Scan it: "scan_freq -r 80-90" & extract its key.');
    AContext.Log('2. Breach it: "deploy_bot -tgt 10.0.0.99 -stealth".');
    AContext.Log('3. Decrypt & cat "/secret/cartel_manifest.enc" (-ip 10.0.0.99).');
    AContext.Log('========================================================');
  end
  else if (MsgID = 4) and (AContext.CampaignStage >= 5) then
  begin
    AContext.Log('================ MESSAGE #4 FROM [ZERO] ================');
    AContext.Log('Incredible job, Operator! The Signal Cartel manifest has');
    AContext.Log('been decrypted. We have enough evidence to bury them.');
    AContext.Log('Type "upload_evidence cartel_manifest.txt" to broadcast');
    AContext.Log('it to global agencies and finish this mission.');
    AContext.Log('========================================================');
  end
  else
    AContext.Log(Format('[-] Message #%d is locked or does not exist.', [MsgID]));
end;

function TCmdReadMsg.GetHelpDescription: string;
begin
  Result := 'Read specific mission message (read_msg <id>)';
end;

{ TCmdUploadEvidence }

procedure TCmdUploadEvidence.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  FileName: string;
begin
  if AParsed.PositionalArgs.Count > 0 then
    FileName := Trim(AParsed.PositionalArgs[0])
  else
    FileName := '';

  if not SameText(FileName, 'cartel_manifest.txt') then
  begin
    AContext.Log('[-] Error: Invalid file name. You must upload "cartel_manifest.txt"');
    Exit;
  end;

  AContext.Log('[*] Authenticating with global broadcast servers...');
  AContext.Log('[*] Uploading cartel_manifest.txt [||||||||||||] 100%');

  if Assigned(AContext.OnMissionEvent) then
    AContext.OnMissionEvent('UPLOAD_EVIDENCE', '');
end;

function TCmdUploadEvidence.GetHelpDescription: string;
begin
  Result := 'Upload decrypted evidence to end mission';
end;

{ TCmdBlackMarket }

procedure TCmdBlackMarket.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
begin
  AContext.Log(':::: THE DARK WEB MODULE SHOP ::::');
  AContext.Log(Format('Your Wallet: %d Data Fragments', [AContext.DataFragments]));
  AContext.Log('Available Hardware/Software Upgrades:');
  AContext.Log('  [qcpu]      - Quantum CPU (30 Fragments)');
  AContext.Log('                Reduces CPU lag duration during decryption by 60%.');
  AContext.Log('  [svpn]      - Stealth VPN (40 Fragments)');
  AContext.Log('                Reduces trace meter penalties by 30%.');
  AContext.Log('  [aanalyzer] - Auto-Analyzer (25 Fragments)');
  AContext.Log('                Displays optimal acoustic scan ranges automatically.');
  AContext.Log('-----------------------------------');
  AContext.Log('To purchase, type: upgrade <module_code> (e.g., upgrade qcpu)');
end;

function TCmdBlackMarket.GetHelpDescription: string;
begin
  Result := 'Open the Dark Web Module Shop';
end;

{ TCmdUpgrade }

procedure TCmdUpgrade.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  ModuleCode: string;
  Cost: Integer;
  IsBought: Boolean;
begin
  if AParsed.PositionalArgs.Count = 0 then
  begin
    AContext.Log('[-] Usage: upgrade <module_code> (check "blackmarket" for codes)');
    Exit;
  end;

  ModuleCode := LowerCase(Trim(AParsed.PositionalArgs[0]));
  Cost := 0;
  IsBought := False;

  if ModuleCode = 'qcpu' then Cost := 30
  else if ModuleCode = 'svpn' then Cost := 40
  else if ModuleCode = 'aanalyzer' then Cost := 25
  else
  begin
    AContext.Log(Format('[-] Unknown module "%s".', [ModuleCode]));
    Exit;
  end;

  if AContext.DataFragments < Cost then
  begin
    AContext.Log(Format('[-] Transaction Denied: Insufficient Data Fragments. (Need: %d, Have: %d)', [Cost, AContext.DataFragments]));
    Exit;
  end;

  AContext.Log(Format('[+] Processing transaction... %d fragments deducted.', [Cost]));
  AContext.Log(Format('[+] Success! Module "%s" installed and activated.', [UpperCase(ModuleCode)]));

  if Assigned(AContext.OnMissionEvent) then
  begin
    AContext.OnMissionEvent('DEDUCT_FRAGMENTS', IntToStr(Cost));
    AContext.OnMissionEvent('PURCHASE_MODULE', UpperCase(ModuleCode));
  end;
end;

function TCmdUpgrade.GetHelpDescription: string;
begin
  Result := 'Purchase and install a module (upgrade qcpu)';
end;

{ TCmdBlockPort }

procedure TCmdBlockPort.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
var
  PortStr: string;
begin
  if AParsed.PositionalArgs.Count > 0 then
    PortStr := Trim(AParsed.PositionalArgs[0])
  else
    PortStr := '';

  if PortStr = '' then
  begin
    AContext.Log('[-] Usage: block_port <port_number>');
    Exit;
  end;

  AContext.Log(Format('[*] Executing firewall rule: DENY INCOMING TCP/UDP ON PORT %s...', [PortStr]));

  if Assigned(AContext.OnMissionEvent) then
    AContext.OnMissionEvent('BLOCK_PORT', PortStr);
end;

function TCmdBlockPort.GetHelpDescription: string;
begin
  Result := 'Close a firewall port to block attacks (block_port 8080)';
end;

{ TCmdAbout }

procedure TCmdAbout.Execute(AParsed: TParsedCommand; AContext: TCommandContext);
begin
  if Assigned(AContext.OnShowAbout) then
    AContext.OnShowAbout();
end;

function TCmdAbout.GetHelpDescription: string;
begin
  Result := 'Display ECHO-OS system architecture & credits';
end;

{ TCommandExecutor }

constructor TCommandExecutor.Create(AContext: TCommandContext);
begin
  inherited Create;
  FContext := AContext;
  FCommands := TCommandDictionary.Create([doOwnsValues]);
  FParsedCmd := TParsedCommand.Create;
  RegisterDefaultCommands;
end;

destructor TCommandExecutor.Destroy;
begin
  FreeAndNil(FParsedCmd);
  FreeAndNil(FCommands);
  inherited Destroy;
end;

procedure TCommandExecutor.RegisterCommand(const AName: string; ACommand: TCustomTerminalCommand);
begin
  FCommands.AddOrSetValue(LowerCase(AName), ACommand);
end;

procedure TCommandExecutor.RegisterDefaultCommands;
begin
  RegisterCommand('help', TCmdHelp.Create(FCommands));
  RegisterCommand('clear', TCmdClear.Create);
  RegisterCommand('inbox', TCmdInbox.Create);
  RegisterCommand('read_msg', TCmdReadMsg.Create);
  RegisterCommand('upload_evidence', TCmdUploadEvidence.Create);
  RegisterCommand('blackmarket', TCmdBlackMarket.Create);
  RegisterCommand('upgrade', TCmdUpgrade.Create);
  RegisterCommand('block_port', TCmdBlockPort.Create);
  RegisterCommand('scan_freq', TCmdScanFreq.Create);
  RegisterCommand('apply_filter', TCmdApplyFilter.Create);
  RegisterCommand('modulate_phase', TCmdModulatePhase.Create);
  RegisterCommand('deploy_bot', TCmdDeployBot.Create);
  RegisterCommand('bounce_ip', TCmdBounceIP.Create);
  RegisterCommand('sql_inject', TCmdSQLInject.Create);
  RegisterCommand('ls_vfs', TCmdLsVFS.Create);
  RegisterCommand('cat', TCmdCatVFS.Create);
  RegisterCommand('decrypt', TCmdDecryptVFS.Create);
  RegisterCommand('about', TCmdAbout.Create);
end;

procedure TCommandExecutor.ExecuteInput(const ARawInput: string);
var
  CmdObj: TCustomTerminalCommand;
begin
  if not TTerminalLexer.Tokenize(ARawInput, FParsedCmd) then
    Exit;

  if FCommands.TryGetValue(FParsedCmd.CommandName, CmdObj) then
    CmdObj.Execute(FParsedCmd, FContext)
  else if Assigned(FContext) then
    FContext.Log(Format('[-] Unknown command "%s". Type "help" for available commands.', [FParsedCmd.CommandName]));
end;

end.
