unit uBassEngine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, dynlibs, Math, uRingBuffer;

const
  BASS_SAMPLE_LOOP  = 4;
  BASS_SAMPLE_FLOAT = 256;
  BASS_DATA_FFT512  = $80000001; // 256 bin FFT spectrum

type
  HSTREAM = DWORD;
  HCHANNEL = DWORD;

  { Signature pointer fungsi untuk Dynamic Loading bass.dll di Windows }
  TBASS_Init = function(device: LongInt; freq, flags: DWORD; win: Pointer; clsid: Pointer): LongBool; stdcall;
  TBASS_Free = function: LongBool; stdcall;
  TBASS_StreamCreateFile = function(mem: LongBool; f: Pointer; offset, length: QWord; flags: DWORD): HSTREAM; stdcall;
  TBASS_StreamFree = function(handle: HSTREAM): LongBool; stdcall;
  TBASS_ChannelPlay = function(handle: DWORD; restart: LongBool): LongBool; stdcall;
  TBASS_ChannelStop = function(handle: DWORD): LongBool; stdcall;
  TBASS_ChannelGetData = function(handle: DWORD; buffer: Pointer; length: DWORD): DWORD; stdcall;

  { TBassEngine - Mengelola pemutaran audio, ekstraksi FFT real-time,
    dan fallback generator gelombang sintetis jika file/dll tidak ditemukan }
  TBassEngine = class
  private
    FLibHandle: TLibHandle;
    FInitialized: Boolean;
    FBGMStream: HSTREAM;
    FSignalStream: HSTREAM;
    FActiveFreq: Integer;
    FBandpassActive: Boolean;
    FPhaseInverted: Boolean;
    FSynthPhase: Single;

    BASS_Init: TBASS_Init;
    BASS_Free: TBASS_Free;
    BASS_StreamCreateFile: TBASS_StreamCreateFile;
    BASS_StreamFree: TBASS_StreamFree;
    BASS_ChannelPlay: TBASS_ChannelPlay;
    BASS_ChannelStop: TBASS_ChannelStop;
    BASS_ChannelGetData: TBASS_ChannelGetData;

    function LoadBassDLL(const ADLLPath: string): Boolean;
    procedure GenerateSyntheticFFT(out ABuffer: array of Single; ACount: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    function Initialize(const ADLLPath: string; AWindowHandle: THandle = 0): Boolean;
    procedure Shutdown;

    function PlayBGM(const AFilePath: string): Boolean;
    function PlaySignal(const AFilePath: string; AFreq: Integer): Boolean;
    procedure StopSignal;

    { Menerapkan modulasi DSP dari perintah terminal (apply_filter / modulate_phase) }
    procedure ApplyBandpassFilter(AEnable: Boolean);
    procedure InvertPhase(AEnable: Boolean);

    { Menarik sampel FFT (256 titik) dan mendorongnya ke Lock-Free RingBuffer }
    procedure CaptureFFTToRingBuffer(ARingBuffer: TRingBuffer);

    property IsInitialized: Boolean read FInitialized;
    property ActiveFreq: Integer read FActiveFreq write FActiveFreq;
    property BandpassActive: Boolean read FBandpassActive;
    property PhaseInverted: Boolean read FPhaseInverted;
  end;

implementation

{ TBassEngine }

constructor TBassEngine.Create;
begin
  inherited Create;
  FLibHandle := NilHandle;
  FInitialized := False;
  FBGMStream := 0;
  FSignalStream := 0;
  FActiveFreq := 450;
  FBandpassActive := False;
  FPhaseInverted := False;
  FSynthPhase := 0.0;
end;

destructor TBassEngine.Destroy;
begin
  Shutdown;
  inherited Destroy;
end;

function TBassEngine.LoadBassDLL(const ADLLPath: string): Boolean;
begin
  Result := False;
  if not FileExists(ADLLPath) then Exit;

  FLibHandle := LoadLibrary(PChar(ADLLPath));
  if FLibHandle = NilHandle then Exit;

  Pointer(BASS_Init) := GetProcAddress(FLibHandle, 'BASS_Init');
  Pointer(BASS_Free) := GetProcAddress(FLibHandle, 'BASS_Free');
  Pointer(BASS_StreamCreateFile) := GetProcAddress(FLibHandle, 'BASS_StreamCreateFile');
  Pointer(BASS_StreamFree) := GetProcAddress(FLibHandle, 'BASS_StreamFree');
  Pointer(BASS_ChannelPlay) := GetProcAddress(FLibHandle, 'BASS_ChannelPlay');
  Pointer(BASS_ChannelStop) := GetProcAddress(FLibHandle, 'BASS_ChannelStop');
  Pointer(BASS_ChannelGetData) := GetProcAddress(FLibHandle, 'BASS_ChannelGetData');

  Result := Assigned(BASS_Init) and Assigned(BASS_Free) and
            Assigned(BASS_StreamCreateFile) and Assigned(BASS_ChannelPlay) and
            Assigned(BASS_ChannelGetData);
end;

function TBassEngine.Initialize(const ADLLPath: string; AWindowHandle: THandle): Boolean;
begin
  if FInitialized then Exit(True);

  if LoadBassDLL(ADLLPath) then
    FInitialized := BASS_Init(-1, 44100, 0, Pointer(AWindowHandle), nil)
  else
    FInitialized := False;

  Result := FInitialized;
end;

procedure TBassEngine.Shutdown;
begin
  if FInitialized then
  begin
    if FBGMStream <> 0 then BASS_StreamFree(FBGMStream);
    if FSignalStream <> 0 then BASS_StreamFree(FSignalStream);
    BASS_Free();
    FInitialized := False;
  end;

  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
end;

function TBassEngine.PlayBGM(const AFilePath: string): Boolean;
begin
  Result := False;
  if not FInitialized or not FileExists(AFilePath) then Exit;

  if FBGMStream <> 0 then
    BASS_StreamFree(FBGMStream);

  FBGMStream := BASS_StreamCreateFile(False, PChar(AFilePath), 0, 0, BASS_SAMPLE_LOOP);
  if FBGMStream <> 0 then
    Result := BASS_ChannelPlay(FBGMStream, False);
end;

function TBassEngine.PlaySignal(const AFilePath: string; AFreq: Integer): Boolean;
begin
  FActiveFreq := AFreq;
  Result := False;
  if not FInitialized or not FileExists(AFilePath) then Exit;

  if FSignalStream <> 0 then
    BASS_StreamFree(FSignalStream);

  FSignalStream := BASS_StreamCreateFile(False, PChar(AFilePath), 0, 0, BASS_SAMPLE_LOOP or BASS_SAMPLE_FLOAT);
  if FSignalStream <> 0 then
    Result := BASS_ChannelPlay(FSignalStream, True);
end;

procedure TBassEngine.StopSignal;
begin
  if FInitialized and (FSignalStream <> 0) then
    BASS_ChannelStop(FSignalStream);
end;

procedure TBassEngine.ApplyBandpassFilter(AEnable: Boolean);
begin
  FBandpassActive := AEnable;
end;

procedure TBassEngine.InvertPhase(AEnable: Boolean);
begin
  FPhaseInverted := AEnable;
end;

procedure TBassEngine.GenerateSyntheticFFT(out ABuffer: array of Single; ACount: Integer);
var
  i, TargetBin: Integer;
  NoiseVal, SignalVal: Single;
begin
  { Fallback generator: Memastikan game tetap berjalan dan menampilkan spektrum
    gelombang yang responsif meskipun file .wav atau bass.dll kosong (0 byte) }
  FSynthPhase := FSynthPhase + 0.15;
  if FSynthPhase > (2 * Pi) then
    FSynthPhase := FSynthPhase - (2 * Pi);

  TargetBin := EnsureRange(FActiveFreq div 10, 5, ACount - 5);

  for i := 0 to ACount - 1 do
  begin
    if FBandpassActive then
      NoiseVal := Random * 0.04 // Redam noise secara drastis saat filter bandpass aktif
    else
      NoiseVal := Random * 0.35;

    // Bentuk puncak frekuensi (Spike) pada sekitar frekuensi target
    if Abs(i - TargetBin) <= 3 then
      SignalVal := (0.85 - (Abs(i - TargetBin) * 0.2)) * abs(Sin(FSynthPhase + i))
    else
      SignalVal := 0.05 * Sin((i * 0.1) + FSynthPhase);

    ABuffer[i] := NoiseVal + SignalVal;
    if FPhaseInverted then
      ABuffer[i] := -ABuffer[i];
  end;
end;

procedure TBassEngine.CaptureFFTToRingBuffer(ARingBuffer: TRingBuffer);
var
  RawFFT: array[0..255] of Single;
  BytesRead: DWORD;
  i: Integer;
begin
  if not Assigned(ARingBuffer) then Exit;

  BytesRead := 0;
  if FInitialized and (FSignalStream <> 0) then
    BytesRead := BASS_ChannelGetData(FSignalStream, @RawFFT[0], BASS_DATA_FFT512);

  // Jika stream audio tidak aktif atau membaca 0 byte, gunakan sinyal sintetis
  if (BytesRead = 0) or (BytesRead = DWORD(-1)) then
    GenerateSyntheticFFT(RawFFT, 128)
  else
  begin
    // Terapkan efek filter DSP secara langsung pada array FFT
    for i := 0 to 127 do
    begin
      if FBandpassActive and ((i < 20) or (i > 60)) then
        RawFFT[i] := RawFFT[i] * 0.1;
      if FPhaseInverted then
        RawFFT[i] := -RawFFT[i];
    end;
  end;

  // Dorong 128 titik sampel yang telah didekimasi ke RingBuffer
  ARingBuffer.Write(RawFFT, 128);
end;

end.

