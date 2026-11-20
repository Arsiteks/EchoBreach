unit uBGRAEffects;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes, uNodeTopology,Math;

type
  { TBGRAEffects - Engine visual berbasis BGRABitmap untuk merender topologi jaringan,
    jendela pop-up Glassmorphism (Pre-rendered blur), dan efek layar tabung (CRT Scanlines) }
  TBGRAEffects = class
  private
    FBlurCache: TBGRABitmap;
    FCacheValid: Boolean;
    FShowPopup: Boolean;
    FPopupTitle: string;
    FPopupPort: Word;
    FPopupPayload: string;
    FPopupStatus: string;

    { Variabel untuk Efek Game Over (Peringatan Kritis) }
    FCriticalAlarmActive: Boolean;
    FAlarmStrobe: Boolean;
    FFrameCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    { Memaksa pengambilan ulang snapshot blur saat topologi berubah }
    procedure InvalidateBlurCache;

    { Mengatur visibilitas dan data pada pop-up Glassmorphism }
    procedure SetInterceptPopup(AShow: Boolean; const ATitle: string = '';
      APort: Word = 0; const APayload: string = ''; const AStatus: string = '');

    { Mengaktifkan efek kedipan merah pada layar (Game Over) }
    procedure SetCriticalAlarm(AActive: Boolean);

    { 1. Render graf node jaringan (Anti-aliased vector & Phosphor Glow) }
    procedure RenderTopology(ACanvas: TBGRABitmap; ATopology: TTopologyManager);

    { 2. Render jendela pop-up dengan efek Fake Glassmorphism (hemat CPU) }
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
  FBlurCache := nil;
  FCacheValid := False;
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
  if Assigned(FBlurCache) then
    FreeAndNil(FBlurCache);
  inherited Destroy;
end;

procedure TBGRAEffects.InvalidateBlurCache;
begin
  FCacheValid := False;
end;

procedure TBGRAEffects.SetInterceptPopup(AShow: Boolean; const ATitle: string;
  APort: Word; const APayload: string; const AStatus: string);
begin
  if FShowPopup <> AShow then
    InvalidateBlurCache;

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
  SubBmp: TBGRABitmap;
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

  { Optimasi Fake Glassmorphism: Lakukan FastBlur sekali saja dan simpan di FBlurCache }
  if (not FCacheValid) or (not Assigned(FBlurCache)) or
     (FBlurCache.Width <> ARect.Width) or (FBlurCache.Height <> ARect.Height) then
  begin
    if Assigned(FBlurCache) then
      FreeAndNil(FBlurCache);

    SubBmp := ACanvas.GetPart(ARect) as TBGRABitmap;
    try
      FBlurCache := SubBmp.FilterBlurRadial(6, rbBox) as TBGRABitmap;
      { Lapisi dengan warna kaca hijau gelap semi-transparan }
      FBlurCache.FillRect(0, 0, FBlurCache.Width, FBlurCache.Height,
        BGRA(10, 35, 18, 190), dmDrawWithTransparency);
      FCacheValid := True;
    finally
      SubBmp.Free;
    end;
  end;

  { Tempelkan cache kaca buram ke kanvas utama }
  ACanvas.PutImage(ARect.Left, ARect.Top, FBlurCache, dmSet);

  { Bingkai neon Glassmorphism }
  BorderColor := BGRA(80, 255, 120, 220);
  ACanvas.RectangleAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1,
    BorderColor, 1.5);

  { Render informasi dekripsi data di dalam kaca }
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
