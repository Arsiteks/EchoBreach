unit uFFTProcessor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, uRingBuffer;

type
  { TSignalAnalysis - Menyimpan hasil ekstraksi metrik dari spektrum gelombang }
  TSignalAnalysis = record
    PeakFrequency: Integer;
    PeakAmplitude: Single;
    NoiseFloor: Single;
    SNR: Single; // Signal-to-Noise Ratio (Penentu keberhasilan sadap data)
    AnomalyDetected: Boolean;
  end;

  { TFFTProcessor - Mengolah data mentah dari RingBuffer (Decimation, Smoothing, & Peak Detection)
    sebelum di-render oleh TAChart untuk menjaga frame-rate tetap tinggi (60 FPS) }
  TFFTProcessor = class
  private
    FSampleSize: Integer;
    FSmoothingFactor: Single;
    FSmoothedData: TFFTDataArray;
    FModulatedWave: TFFTDataArray;
    FTargetFreq: Integer;
    FLastAnalysis: TSignalAnalysis;
  public
    constructor Create(ASampleSize: Integer = 128);
    destructor Destroy; override;

    { Memproses antrean data dari RingBuffer dan menghasilkan metrik analisis sinyal }
    function ProcessBuffer(ARingBuffer: TRingBuffer): Boolean;

    { Mereset akumulator grafik ketika frekuensi atau target diganti }
    procedure ResetProcessor;

    property SampleSize: Integer read FSampleSize;
    property SmoothingFactor: Single read FSmoothingFactor write FSmoothingFactor;
    property TargetFreq: Integer read FTargetFreq write FTargetFreq;
    property SmoothedData: TFFTDataArray read FSmoothedData;
    property ModulatedWave: TFFTDataArray read FModulatedWave;
    property LastAnalysis: TSignalAnalysis read FLastAnalysis;
  end;

implementation

{ TFFTProcessor }

constructor TFFTProcessor.Create(ASampleSize: Integer);
begin
  inherited Create;
  if ASampleSize < 32 then ASampleSize := 32;
  if ASampleSize > 512 then ASampleSize := 512;

  FSampleSize := ASampleSize;
  FSmoothingFactor := 0.35; // Exponential Moving Average (EMA) alpha
  FTargetFreq := 450;

  SetLength(FSmoothedData, FSampleSize);
  SetLength(FModulatedWave, FSampleSize);
  ResetProcessor;
end;

destructor TFFTProcessor.Destroy;
begin
  SetLength(FSmoothedData, 0);
  SetLength(FModulatedWave, 0);
  inherited Destroy;
end;

procedure TFFTProcessor.ResetProcessor;
begin
  if FSampleSize > 0 then
  begin
    FillChar(FSmoothedData[0], FSampleSize * SizeOf(Single), 0);
    FillChar(FModulatedWave[0], FSampleSize * SizeOf(Single), 0);
  end;
  FillChar(FLastAnalysis, SizeOf(TSignalAnalysis), 0);
end;

function TFFTProcessor.ProcessBuffer(ARingBuffer: TRingBuffer): Boolean;
var
  RawData: TFFTDataArray;
  ReadCount: Cardinal;
  i, MaxIdx: Integer;
  Val, MaxAmp, SumNoise, PhaseShift: Single;
begin
  Result := False;
  if not Assigned(ARingBuffer) then Exit;

  { Tarik sampel sebanyak FSampleSize dari Lock-Free RingBuffer }
  ReadCount := ARingBuffer.Read(RawData, FSampleSize);
  if ReadCount = 0 then Exit;

  MaxAmp := -1.0;
  MaxIdx := 0;
  SumNoise := 0.0;
  PhaseShift := GetTickCount64 * 0.005;

  for i := 0 to ReadCount - 1 do
  begin
    Val := RawData[i];

    { 1. Exponential Moving Average (EMA) untuk meredam jitter visual di TAChart }
    FSmoothedData[i] := (Val * FSmoothingFactor) + (FSmoothedData[i] * (1.0 - FSmoothingFactor));

    { 2. Bangkitkan gelombang sekunder (Harmonic Carrier Wave) untuk LineSeries2 }
    FModulatedWave[i] := FSmoothedData[i] * Cos((i * 0.25) + PhaseShift);

    { 3. Deteksi Puncak (Peak Finder) & Akumulasi Noise }
    if Abs(FSmoothedData[i]) > MaxAmp then
    begin
      MaxAmp := Abs(FSmoothedData[i]);
      MaxIdx := i;
    end;
    SumNoise := SumNoise + Abs(FSmoothedData[i]);
  end;

  { Kalkulasi Noise Floor rata-rata dengan mengecualikan titik puncak }
  if ReadCount > 1 then
    FLastAnalysis.NoiseFloor := (SumNoise - MaxAmp) / (ReadCount - 1)
  else
    FLastAnalysis.NoiseFloor := 0.001;

  if FLastAnalysis.NoiseFloor < 0.0001 then
    FLastAnalysis.NoiseFloor := 0.0001;

  FLastAnalysis.PeakAmplitude := MaxAmp;
  FLastAnalysis.PeakFrequency := MaxIdx * 10; // Skala indeks bin ke frekuensi (Hz)
  FLastAnalysis.SNR := MaxAmp / FLastAnalysis.NoiseFloor;

  { Anomali terdeteksi jika SNR cukup bersih (Filter aktif) dan berada di sekitar frekuensi target }
  FLastAnalysis.AnomalyDetected := (FLastAnalysis.SNR > 3.5) and
                                   (Abs(FLastAnalysis.PeakFrequency - FTargetFreq) <= 40);

  Result := True;
end;

end.

