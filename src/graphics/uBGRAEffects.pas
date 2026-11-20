unit uBGRAEffects;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes, uNodeTopology, Math;

type
  { TBGRAEffects - Engine visual berbasis BGRABitmap untuk merender topologi jaringan,
    Cyber-HUD Header modern, pop-up Glassmorphism, dan efek layar tabung (CRT Scanlines) }
  TBGRAEffects = class
  private
    FShowPopup: Boolean;
    FPopupTitle: string;
    FPopupPort: Word;
    FPopupPayload: string;
    FPopupStatus: string;

    { Variabel untuk Efek Game Over (Peringatan Kritis) }
    FCriticalAlarmActive: Boolean;
    FAlarmStrobe: Boolean;
    FFrameCount: Integer;

    { Helper menggambar panel kartu HUD dengan sudut membulat }
    procedure DrawHudCard(ACanvas: TBGRABitmap; const ARect: TRect;
      ABorderColor, AFillColor: TBGRAPixel);

    { Helper menggambar progress bar bersegmen modern }
    procedure DrawSegmentedBar(ACanvas: TBGRABitmap; const ARect: TRect;
      APercent: Integer; AActiveColor: TBGRAPixel; ASegments: Integer = 10);

    { Helper menggambar chip status modul hardware dengan lampu LED }
    procedure DrawModuleChip(ACanvas: TBGRABitmap; const ARect: TRect;
      const ALabel: string; AActive: Boolean);
  public
    constructor Create;
    destructor Destroy; override;

    { [STUB] Dibiarkan untuk kompatibilitas referensi lama }
    procedure InvalidateBlurCache;

    { Mengatur visibilitas dan data pada pop-up Glassmorphism }
    procedure SetInterceptPopup(AShow: Boolean; const ATitle: string = '';
      APort: Word = 0; const APayload: string = ''; const AStatus: string = '');

    { Mengaktifkan efek kedipan merah pada layar (Game Over) }
    procedure SetCriticalAlarm(AActive: Boolean);

    { 0. Render Cyber-HUD Tactical Dashboard pada panel atas }
    procedure RenderModernHeader(ACanvas: TBGRABitmap; const AProxyIP: string;
      ACpuLoad, ARamLoad, ANetLoad, ATraceLevel, ADataFragments: Integer;
      AIsCpuSpiking, AHasQCPU, AHasSVPN, AHasAutoAnalyzer, ACampaignCompleted: Boolean;
      const AObjective: string);

    { 1. Render graf node jaringan (Anti-aliased vector & Phosphor Glow) }
    procedure RenderTopology(ACanvas: TBGRABitmap; ATopology: TTopologyManager);

    { 2. Render jendela pop-up dengan efek Fake Glassmorphism (Tanpa Blur Latar) }
    procedure RenderGlassPopup(ACanvas: TBGRABitmap; ARect: TRect);

    { 3. Post-processing: Scanlines & Vignette langsung via pointer memori }
    procedure ApplyCRTEffect(ACanvas: TBGRABitmap);

    property ShowPopup: Boolean read FShowPopup write FShowPopup;
  end;

implementation

{ TBGRAEffects }

constructor TBGRAEffects.Create;
begin
  inherited Create;
  FShowPopup := False;
  FPopupTitle := ':::: INTERCEPTED DATA (GLASSMORPH) ::::';
  FPopupPort := 8080;
  FPopupPayload := 'HASH_0x8F9A';
  FPopupStatus := 'DECRYPTING... [||||....]';

  FCriticalAlarmActive := False;
  FAlarmStrobe := False;
  FFrameCount := 0;
end;

destructor TBGRAEffects.Destroy;
begin
  inherited Destroy;
end;

procedure TBGRAEffects.InvalidateBlurCache;
begin
  { Efek blur latar telah dinonaktifkan karena popup berada di panel terpisah }
end;

procedure TBGRAEffects.SetInterceptPopup(AShow: Boolean; const ATitle: string;
  APort: Word; const APayload: string; const AStatus: string);
begin
  FShowPopup := AShow;
  if ATitle <> '' then FPopupTitle := ATitle;
  if APort <> 0 then FPopupPort := APort;
  if APayload <> '' then FPopupPayload := APayload;
  if AStatus <> '' then FPopupStatus := AStatus;
end;

procedure TBGRAEffects.SetCriticalAlarm(AActive: Boolean);
begin
  FCriticalAlarmActive := AActive;
end;

procedure TBGRAEffects.DrawHudCard(ACanvas: TBGRABitmap; const ARect: TRect;
  ABorderColor, AFillColor: TBGRAPixel);
begin
  if (ARect.Width <= 2) or (ARect.Height <= 2) then Exit;
  ACanvas.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    4, 4, AFillColor);
  ACanvas.RoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    4, 4, ABorderColor, 1.0);
end;

procedure TBGRAEffects.DrawSegmentedBar(ACanvas: TBGRABitmap; const ARect: TRect;
  APercent: Integer; AActiveColor: TBGRAPixel; ASegments: Integer);
var
  i, FilledCount, Gap: Integer;
  SegW, SegH, StartX, StartY, X1, X2: Single;
  DimColor, BgColor: TBGRAPixel;
begin
  if (ARect.Width <= 8) or (ARect.Height <= 4) or (ASegments <= 0) then Exit;

  BgColor := BGRA(6, 12, 10, 230);
  ACanvas.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    2, 2, BgColor);
  ACanvas.RoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    2, 2, BGRA(40, 85, 65, 160), 1.0);

  Gap := 2;
  StartX := ARect.Left + 3;
  StartY := ARect.Top + 3;
  SegH := ARect.Height - 6;
  SegW := ((ARect.Width - 6) - ((ASegments - 1) * Gap)) / ASegments;

  if SegW < 1.5 then SegW := 1.5;

  FilledCount := Round((EnsureRange(APercent, 0, 100) / 100.0) * ASegments);
  DimColor := BGRA(22, 42, 34, 180);

  for i := 1 to ASegments do
  begin
    X1 := StartX + (i - 1) * (SegW + Gap);
    X2 := X1 + SegW;
    if X2 > ARect.Right - 3 then Break;

    if i <= FilledCount then
      ACanvas.FillRectAntialias(X1, StartY, X2, StartY + SegH, AActiveColor)
    else
      ACanvas.FillRectAntialias(X1, StartY, X2, StartY + SegH, DimColor);
  end;
end;

procedure TBGRAEffects.DrawModuleChip(ACanvas: TBGRABitmap; const ARect: TRect;
  const ALabel: string; AActive: Boolean);
var
  BorderCol, FillCol, LedCol, GlowCol, TextCol: TBGRAPixel;
  LedX, LedY, TextY: Single;
  TextSz: TSize;
begin
  if (ARect.Width <= 10) or (ARect.Height <= 6) then Exit;

  if AActive then
  begin
    FillCol := BGRA(12, 48, 34, 240);
    BorderCol := BGRA(0, 235, 140, 220);
    LedCol := BGRA(50, 255, 160, 255);
    GlowCol := BGRA(0, 255, 130, 95);
    TextCol := BGRA(210, 255, 230, 255);
  end
  else
  begin
    FillCol := BGRA(12, 18, 16, 220);
    BorderCol := BGRA(45, 70, 60, 150);
    LedCol := BGRA(55, 75, 68, 200);
    GlowCol := BGRAPixelTransparent;
    TextCol := BGRA(105, 135, 122, 200);
  end;

  ACanvas.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    3, 3, FillCol);
  ACanvas.RoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    3, 3, BorderCol, 1.0);

  LedX := ARect.Left + 10;
  LedY := ARect.Top + (ARect.Height / 2);

  if AActive then
    ACanvas.FillEllipseAntialias(LedX, LedY, 5.5, 5.5, GlowCol);
  ACanvas.FillEllipseAntialias(LedX, LedY, 2.8, 2.8, LedCol);

  ACanvas.FontHeight := 11;
  TextSz := ACanvas.TextSize(ALabel);
  TextY := ARect.Top + ((ARect.Height - TextSz.cy) / 2);
  ACanvas.TextOut(ARect.Left + 18, TextY, ALabel, TextCol, taLeftJustify);
end;

procedure TBGRAEffects.RenderModernHeader(ACanvas: TBGRABitmap; const AProxyIP: string;
  ACpuLoad, ARamLoad, ANetLoad, ATraceLevel, ADataFragments: Integer;
  AIsCpuSpiking, AHasQCPU, AHasSVPN, AHasAutoAnalyzer, ACampaignCompleted: Boolean;
  const AObjective: string);
var
  W, H, Pad, Gap: Integer;
  Row1Y, Row2Y, Row3Y, RowH, Row3H: Integer;
  CardFill, CardBorder, AccentCol, TextMuted, TextBright: TBGRAPixel;
  RProxy, RCpu, RRam, RNet, RTrace, RWallet, RMods, RObj, RBar: TRect;
  WAvail, ChipW, ChipGap, CX, CY: Integer;
  PulseAlpha: Byte;
  StatusStr: string;
begin
  if not Assigned(ACanvas) then Exit;
  W := ACanvas.Width;
  H := ACanvas.Height;
  if (W < 200) or (H < 60) then Exit;

  { Latar belakang dasar Cyber-HUD }
  if FCriticalAlarmActive then
    ACanvas.Fill(BGRA(28, 6, 6, 255))
  else
    ACanvas.Fill(BGRA(9, 16, 14, 255));

  CardFill := BGRA(15, 26, 22, 245);
  if FCriticalAlarmActive then
    CardBorder := BGRA(180, 40, 40, 190)
  else
    CardBorder := BGRA(30, 110, 75, 175);

  TextMuted := BGRA(120, 175, 150, 230);
  TextBright := BGRA(220, 255, 235, 255);

  ACanvas.FontName := 'Consolas';
  ACanvas.FontStyle := [fsBold];
  ACanvas.FontQuality := fqFineAntialiasing;

  Pad := 6;
  Gap := 6;
  RowH := 27;
  Row3H := 25;

  Row1Y := Pad;
  Row2Y := Row1Y + RowH + 5;
  Row3Y := Row2Y + RowH + 5;

  WAvail := W - (Pad * 2);

  { =========================================================================
    BARIS 1: SYSTEM & PROXY PILL | CPU GAUGE | RAM GAUGE | NET BANDWIDTH
    ========================================================================= }
  RProxy := Rect(Pad, Row1Y, Pad + Round(WAvail * 0.32), Row1Y + RowH);
  RCpu   := Rect(RProxy.Right + Gap, Row1Y, RProxy.Right + Gap + Round(WAvail * 0.22), Row1Y + RowH);
  RRam   := Rect(RCpu.Right + Gap, Row1Y, RCpu.Right + Gap + Round(WAvail * 0.22), Row1Y + RowH);
  RNet   := Rect(RRam.Right + Gap, Row1Y, W - Pad, Row1Y + RowH);

  { 1A. Kartu Identitas OS & Proxy }
  DrawHudCard(ACanvas, RProxy, CardBorder, CardFill);
  ACanvas.FontHeight := 12;
  ACanvas.TextOut(RProxy.Left + 10, RProxy.Top + 7, 'ECHO-OS v1.99', BGRA(0, 240, 130, 255), taLeftJustify);

  { Garis pemisah vertikal kecil }
  ACanvas.DrawLineAntialias(RProxy.Left + 108, RProxy.Top + 6, RProxy.Left + 108, RProxy.Bottom - 6,
    BGRA(40, 110, 80, 150), 1.0);

  { LED Indikator Proxy Aktif }
  ACanvas.FillEllipseAntialias(RProxy.Left + 120, RProxy.Top + 13.5, 5.5, 5.5, BGRA(0, 255, 110, 85));
  ACanvas.FillEllipseAntialias(RProxy.Left + 120, RProxy.Top + 13.5, 2.8, 2.8, BGRA(60, 255, 140, 255));
  ACanvas.TextOut(RProxy.Left + 130, RProxy.Top + 7, 'PROXY ' + AProxyIP, TextBright, taLeftJustify);

  { 1B. Kartu CPU }
  DrawHudCard(ACanvas, RCpu, CardBorder, CardFill);
  ACanvas.FontHeight := 11;
  ACanvas.TextOut(RCpu.Left + 8, RCpu.Top + 8, 'CPU', TextMuted, taLeftJustify);
  if AIsCpuSpiking or (ACpuLoad >= 85) then
    AccentCol := BGRA(255, 65, 65, 255)
  else
    AccentCol := BGRA(0, 230, 110, 255);
  ACanvas.TextOut(RCpu.Right - 8, RCpu.Top + 8, Format('%d%%', [ACpuLoad]), AccentCol, taRightJustify);
  RBar := Rect(RCpu.Left + 34, RCpu.Top + 7, RCpu.Right - 40, RCpu.Bottom - 7);
  DrawSegmentedBar(ACanvas, RBar, ACpuLoad, AccentCol, 10);

  { 1C. Kartu RAM }
  DrawHudCard(ACanvas, RRam, CardBorder, CardFill);
  ACanvas.TextOut(RRam.Left + 8, RRam.Top + 8, 'RAM', TextMuted, taLeftJustify);
  if ARamLoad >= 85 then
    AccentCol := BGRA(255, 185, 40, 255)
  else
    AccentCol := BGRA(40, 215, 130, 255);
  ACanvas.TextOut(RRam.Right - 8, RRam.Top + 8, Format('%d%%', [ARamLoad]), AccentCol, taRightJustify);
  RBar := Rect(RRam.Left + 34, RRam.Top + 7, RRam.Right - 40, RRam.Bottom - 7);
  DrawSegmentedBar(ACanvas, RBar, ARamLoad, AccentCol, 10);

  { 1D. Kartu NET LOAD }
  DrawHudCard(ACanvas, RNet, CardBorder, CardFill);
  ACanvas.TextOut(RNet.Left + 8, RNet.Top + 8, 'NET', TextMuted, taLeftJustify);
  AccentCol := BGRA(0, 215, 245, 255);
  ACanvas.TextOut(RNet.Right - 8, RNet.Top + 8, Format('%d Kbps', [ANetLoad]), AccentCol, taRightJustify);
  RBar := Rect(RNet.Left + 34, RNet.Top + 7, RNet.Right - 64, RNet.Bottom - 7);
  DrawSegmentedBar(ACanvas, RBar, EnsureRange(ANetLoad div 10, 0, 100), AccentCol, 8);

  { =========================================================================
    BARIS 2: TRACE / STEALTH METER | CRYPTO WALLET | HARDWARE MODULE CHIPS
    ========================================================================= }
  RTrace  := Rect(Pad, Row2Y, Pad + Round(WAvail * 0.40), Row2Y + RowH);
  RWallet := Rect(RTrace.Right + Gap, Row2Y, RTrace.Right + Gap + Round(WAvail * 0.22), Row2Y + RowH);
  RMods   := Rect(RWallet.Right + Gap, Row2Y, W - Pad, Row2Y + RowH);

  { 2A. Kartu Stealth / Trace Meter }
  if ATraceLevel >= 50 then
  begin
    PulseAlpha := 160 + Round(85 * Sin(GetTickCount64 / 140.0));
    AccentCol := BGRA(255, 55, 55, PulseAlpha);
    StatusStr := Format('TRACE %d%%', [ATraceLevel]);
    DrawHudCard(ACanvas, RTrace, BGRA(220, 50, 50, 210), BGRA(32, 14, 14, 245));
  end
  else
  begin
    AccentCol := BGRA(0, 235, 115, 255);
    StatusStr := Format('STEALTH %d%%', [100 - ATraceLevel]);
    DrawHudCard(ACanvas, RTrace, CardBorder, CardFill);
  end;

  ACanvas.FontHeight := 11;
  ACanvas.TextOut(RTrace.Left + 10, RTrace.Top + 8, 'TRACE', TextMuted, taLeftJustify);
  ACanvas.TextOut(RTrace.Right - 10, RTrace.Top + 8, StatusStr, AccentCol, taRightJustify);
  RBar := Rect(RTrace.Left + 50, RTrace.Top + 7, RTrace.Right - 84, RTrace.Bottom - 7);
  DrawSegmentedBar(ACanvas, RBar, ATraceLevel, AccentCol, 14);

  { 2B. Kartu Wallet / Data Fragments }
  DrawHudCard(ACanvas, RWallet, CardBorder, CardFill);
  { Ikon Kristal Vektor (Polygon Diamond) }
  CX := RWallet.Left + 15;
  CY := RWallet.Top + (RowH div 2);
  ACanvas.FillPolyAntialias([
    PointF(CX, CY - 6),
    PointF(CX + 5.5, CY),
    PointF(CX, CY + 6),
    PointF(CX - 5.5, CY)
  ], BGRA(0, 225, 255, 255));
  ACanvas.TextOut(RWallet.Left + 26, RWallet.Top + 8, 'FRAGMENTS:', TextMuted, taLeftJustify);
  ACanvas.FontHeight := 13;
  ACanvas.TextOut(RWallet.Right - 10, RWallet.Top + 6, IntToStr(ADataFragments), BGRA(80, 245, 255, 255), taRightJustify);

  { 2C. Kartu Hardware Modules (Black Market Upgrades) }
  DrawHudCard(ACanvas, RMods, CardBorder, CardFill);
  ACanvas.FontHeight := 11;
  ACanvas.TextOut(RMods.Left + 10, RMods.Top + 8, 'MODULES', TextMuted, taLeftJustify);

  ChipGap := 5;
  ChipW := ((RMods.Width - 68) - (ChipGap * 2)) div 3;
  if ChipW < 45 then ChipW := 45;

  DrawModuleChip(ACanvas, Rect(RMods.Left + 62, RMods.Top + 4, RMods.Left + 62 + ChipW, RMods.Bottom - 4),
    'Q-CPU', AHasQCPU);
  DrawModuleChip(ACanvas, Rect(RMods.Left + 62 + ChipW + ChipGap, RMods.Top + 4, RMods.Left + 62 + (ChipW * 2) + ChipGap, RMods.Bottom - 4),
    'S-VPN', AHasSVPN);
  DrawModuleChip(ACanvas, Rect(RMods.Left + 62 + ((ChipW + ChipGap) * 2), RMods.Top + 4, RMods.Right - 6, RMods.Bottom - 4),
    'A-SCAN', AHasAutoAnalyzer);

  { =========================================================================
    BARIS 3: TACTICAL MISSION OBJECTIVE BANNER
    ========================================================================= }
  RObj := Rect(Pad, Row3Y, W - Pad, Row3Y + Row3H);

  if ACampaignCompleted then
  begin
    AccentCol := BGRA(0, 245, 120, 255);
    DrawHudCard(ACanvas, RObj, BGRA(0, 200, 100, 200), BGRA(12, 34, 24, 245));
    StatusStr := 'COMPLETE';
  end
  else
  begin
    AccentCol := BGRA(255, 210, 45, 255);
    DrawHudCard(ACanvas, RObj, BGRA(150, 130, 35, 190), BGRA(24, 24, 14, 245));
    StatusStr := 'OBJECTIVE';
  end;

  { Garis aksen vertikal tebal di sisi kiri banner objektif }
  ACanvas.FillRectAntialias(RObj.Left + 1, RObj.Top + 2, RObj.Left + 5, RObj.Bottom - 2, AccentCol);

  ACanvas.FontHeight := 11;
  ACanvas.TextOut(RObj.Left + 12, RObj.Top + 7, '[' + StatusStr + ']', AccentCol, taLeftJustify);

  ACanvas.FontHeight := 12;
  ACanvas.TextOut(RObj.Left + 88, RObj.Top + 6, AObjective, TextBright, taLeftJustify);

  { Garis pembatas neon tipis di tepi paling bawah header }
  if FCriticalAlarmActive then
    ACanvas.DrawLineAntialias(0, H - 1, W, H - 1, BGRA(220, 40, 40, 220), 1.0)
  else
    ACanvas.DrawLineAntialias(0, H - 1, W, H - 1, BGRA(0, 170, 75, 200), 1.0);
end;

procedure TBGRAEffects.RenderTopology(ACanvas: TBGRABitmap; ATopology: TTopologyManager);
var
  Node, LinkedNode: TNetworkNode;
  X1, Y1, X2, Y2, W, H: Single;
  NodeColor, GlowColor, LineColor: TBGRAPixel;
  TextLabel: string;
begin
  if not Assigned(ACanvas) or not Assigned(ATopology) then Exit;

  W := ACanvas.Width;
  H := ACanvas.Height;

  { Latar belakang dasar CRT hijau sangat gelap (atau merah jika alarm aktif) }
  if FCriticalAlarmActive then
    ACanvas.Fill(BGRA(25, 4, 4, 255))
  else
    ACanvas.Fill(BGRA(4, 12, 6, 255));

  { Pengaturan font vektor }
  ACanvas.FontName := 'Consolas';
  ACanvas.FontStyle := [fsBold];
  ACanvas.FontHeight := 14;
  ACanvas.FontQuality := fqFineAntialiasing;

  if FCriticalAlarmActive then
    LineColor := BGRA(140, 20, 20, 180)
  else
    LineColor := BGRA(0, 140, 40, 180);

  { Tahap 1: Gambar garis koneksi (Vector Lines) }
  for Node in ATopology.Nodes do
  begin
    X1 := Node.PosX * W;
    Y1 := Node.PosY * H;

    for LinkedNode in Node.Links do
    begin
      { Hindari menggambar garis dua kali }
      if PtrUInt(Node) < PtrUInt(LinkedNode) then
      begin
        X2 := LinkedNode.PosX * W;
        Y2 := LinkedNode.PosY * H;

        { Efek pendaran (glow) pada jalur kabel }
        if FCriticalAlarmActive then
          ACanvas.DrawLineAntialias(X1, Y1, X2, Y2, BGRA(255, 30, 30, 50), 5.0)
        else
          ACanvas.DrawLineAntialias(X1, Y1, X2, Y2, BGRA(0, 255, 65, 50), 5.0);

        ACanvas.DrawLineAntialias(X1, Y1, X2, Y2, LineColor, 1.5);
      end;
    end;
  end;

  { Tahap 2: Gambar Node dan Label Status }
  for Node in ATopology.Nodes do
  begin
    X1 := Node.PosX * W;
    Y1 := Node.PosY * H;

    if Node = ATopology.ActiveNode then
    begin
      NodeColor := BGRA(0, 255, 120, 255);
      GlowColor := BGRA(0, 255, 100, 90);
    end
    else if Node.IsCompromised then
    begin
      NodeColor := BGRA(0, 200, 60, 255);
      GlowColor := BGRA(0, 180, 50, 60);
    end
    else if Node.IsScanned then
    begin
      NodeColor := BGRA(255, 180, 0, 255); // Kuning/Amber untuk anomali terdeteksi
      GlowColor := BGRA(255, 140, 0, 70);
    end
    else
    begin
      NodeColor := BGRA(180, 40, 40, 255); // Merah untuk node terkunci
      GlowColor := BGRA(180, 20, 20, 50);
    end;

    { Timpa semua warna menjadi merah jika alarm kritis aktif }
    if FCriticalAlarmActive then
    begin
      NodeColor := BGRA(255, 40, 40, 255);
      GlowColor := BGRA(200, 20, 20, 100);
    end;

    { Gambar lingkaran luar (Glow) dan titik inti node }
    ACanvas.FillEllipseAntialias(X1, Y1, 18, 18, GlowColor);
    ACanvas.EllipseAntialias(X1, Y1, 10, 10, NodeColor, 2.0, BGRA(5, 20, 10, 255));

    { Teks Hostname & IP }
    TextLabel := Format('(%s)', [Node.Hostname]);
    ACanvas.TextOut(X1, Y1 - 28, TextLabel, NodeColor, taCenter);

    if FCriticalAlarmActive then
      ACanvas.TextOut(X1, Y1 + 14, Node.IPAddress, BGRA(220, 100, 100, 200), taCenter)
    else
      ACanvas.TextOut(X1, Y1 + 14, Node.IPAddress, BGRA(100, 220, 130, 200), taCenter);
  end;
end;

procedure TBGRAEffects.RenderGlassPopup(ACanvas: TBGRABitmap; ARect: TRect);
var
  BorderColor, TextColor: TBGRAPixel;
  PadX, PadY, LineH: Integer;
begin
  { Sembunyikan popup jika alarm aktif }
  if not FShowPopup or not Assigned(ACanvas) or FCriticalAlarmActive then Exit;

  { Pastikan koordinat potong berada di dalam batas kanvas }
  if ARect.Left < 0 then ARect.Left := 0;
  if ARect.Top < 0 then ARect.Top := 0;
  if ARect.Right > ACanvas.Width then ARect.Right := ACanvas.Width;
  if ARect.Bottom > ACanvas.Height then ARect.Bottom := ACanvas.Height;
  if (ARect.Width <= 10) or (ARect.Height <= 10) then Exit;

  { Gambar latar panel padat (tanpa blur) karena dirender di panel bawah terpisah }
  ACanvas.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom,
                   BGRA(10, 35, 18, 190), dmDrawWithTransparency);

  { Bingkai neon Glassmorphism }
  BorderColor := BGRA(80, 255, 120, 220);
  ACanvas.RectangleAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    BorderColor, 1.5);

  { Render informasi dekripsi data di dalam panel }
  TextColor := BGRA(180, 255, 190, 255);
  ACanvas.FontName := 'Consolas';
  ACanvas.FontStyle := [fsBold];
  ACanvas.FontHeight := 14;

  PadX := ARect.Left + 16;
  PadY := ARect.Top + 14;
  LineH := 22;

  ACanvas.TextOut(ARect.Left + (ARect.Width div 2), PadY, FPopupTitle,
    BGRA(255, 255, 150, 255), taCenter);

  ACanvas.TextOut(PadX, PadY + (LineH * 1) + 6, Format('> PORT    : %d (OPEN)', [FPopupPort]), TextColor);
  ACanvas.TextOut(PadX, PadY + (LineH * 2) + 6, Format('> PAYLOAD : %s', [FPopupPayload]), TextColor);
  ACanvas.TextOut(PadX, PadY + (LineH * 3) + 6, Format('> STATUS  : %s', [FPopupStatus]), BGRA(100, 255, 100, 255));

  { Post-Processing: Terapkan scanlines khusus pada panel informasi ini agar senada dengan CRT Map }
  ApplyCRTEffect(ACanvas);
end;

procedure TBGRAEffects.ApplyCRTEffect(ACanvas: TBGRABitmap);
var
  y, x, w, h: Integer;
  p: PBGRAPixel;
begin
  if not Assigned(ACanvas) then Exit;
  w := ACanvas.Width;
  h := ACanvas.Height;

  { Hitung siklus strobo untuk alarm (kedip setiap ~30 frame) }
  Inc(FFrameCount);
  if (FFrameCount mod 30) = 0 then
    FAlarmStrobe := not FAlarmStrobe;

  { Manipulasi Scanline langsung via pointer memori (Sangat cepat untuk 60 FPS) }
  for y := 0 to h - 1 do
  begin
    { Gelapkan setiap baris genap untuk menciptakan ilusi garis tabung CRT }
    if (y and 1) = 0 then
    begin
      p := ACanvas.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        p^.red   := (p^.red * 170) shr 8;   // Setara dikali ~0.66 menggunakan bitwise shift
        p^.green := (p^.green * 170) shr 8;
        p^.blue  := (p^.blue * 170) shr 8;

        { Jika alarm aktif dan sedang berkedip terang, siram warna merah darah }
        if FCriticalAlarmActive and FAlarmStrobe then
        begin
          p^.red := EnsureRange(p^.red + 100, 0, 255);
          p^.green := p^.green shr 1;
          p^.blue := p^.blue shr 1;
        end;

        Inc(p);
      end;
    end;
  end;

  { Garis bingkai pendaran dalam (Inner CRT Bezel) }
  if FCriticalAlarmActive then
    ACanvas.Rectangle(0, 0, w, h, BGRA(90, 0, 0, 200), dmDrawWithTransparency)
  else
    ACanvas.Rectangle(0, 0, w, h, BGRA(0, 90, 25, 200), dmDrawWithTransparency);
end;

end.
