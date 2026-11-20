unit uRingBuffer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Array dinamis untuk menampung sampel spektrum FFT }
  TFFTDataArray = array of Single;

  { TRingBuffer - Lock-free Single-Producer Single-Consumer (SPSC) Ring Buffer
    Digunakan untuk menjembatani thread BASS Audio DSP dan LCL Main Thread (TAChart)
    tanpa menyebabkan bottleneck atau deadlock akibat penggunaan CriticalSection }
  TRingBuffer = class
  private
    FBuffer: array of Single;
    FCapacity: Cardinal;
    FMask: Cardinal;
    FWriteIdx: Cardinal;
    FReadIdx: Cardinal;
  public
    { ACapacityPowerOfTwo harus kelipatan pangkat 2 (misal: 10, menghasilkan kapasitas 2^10 = 1024)
      untuk mengoptimalkan operasi modulo menjadi operasi bitwise AND yang jauh lebih cepat }
    constructor Create(ACapacityPowerOfTwo: Byte = 10);
    destructor Destroy; override;

    { Dipanggil oleh Audio Thread (Producer) }
    function Write(const AData: array of Single; ACount: Cardinal): Cardinal;

    { Dipanggil oleh UI Thread / TAChart (Consumer) }
    function Read(out AData: TFFTDataArray; ACount: Cardinal): Cardinal;

    procedure Clear;
    function AvailableToRead: Cardinal;
    function AvailableToWrite: Cardinal;
    property Capacity: Cardinal read FCapacity;
  end;

implementation

{ TRingBuffer }

constructor TRingBuffer.Create(ACapacityPowerOfTwo: Byte);
begin
  inherited Create;
  // Batasi ukuran eksponen antara 2^8 (256) hingga 2^16 (65536)
  if ACapacityPowerOfTwo < 8 then ACapacityPowerOfTwo := 8;
  if ACapacityPowerOfTwo > 16 then ACapacityPowerOfTwo := 16;

  FCapacity := 1 shl ACapacityPowerOfTwo;
  FMask := FCapacity - 1;
  SetLength(FBuffer, FCapacity);
  Clear;
end;

destructor TRingBuffer.Destroy;
begin
  SetLength(FBuffer, 0);
  inherited Destroy;
end;

procedure TRingBuffer.Clear;
begin
  FWriteIdx := 0;
  FReadIdx := 0;
  if FCapacity > 0 then
    FillChar(FBuffer[0], FCapacity * SizeOf(Single), 0);
end;

function TRingBuffer.AvailableToRead: Cardinal;
begin
  Result := FWriteIdx - FReadIdx;
end;

function TRingBuffer.AvailableToWrite: Cardinal;
begin
  Result := FCapacity - (FWriteIdx - FReadIdx);
end;

function TRingBuffer.Write(const AData: array of Single; ACount: Cardinal): Cardinal;
var
  Avail, FirstChunk, SecondChunk, Offset: Cardinal;
begin
  Avail := AvailableToWrite;
  if ACount > Avail then
    Result := Avail
  else
    Result := ACount;

  if Result = 0 then Exit;

  // Hitung posisi indeks dengan bitwise AND (jauh lebih cepat daripada 'mod')
  Offset := FWriteIdx and FMask;
  FirstChunk := FCapacity - Offset;

  if Result <= FirstChunk then
  begin
    Move(AData[0], FBuffer[Offset], Result * SizeOf(Single));
  end
  else
  begin
    // Jika mencapai ujung array, bagi menjadi dua blok memori (wrap-around)
    SecondChunk := Result - FirstChunk;
    Move(AData[0], FBuffer[Offset], FirstChunk * SizeOf(Single));
    Move(AData[FirstChunk], FBuffer[0], SecondChunk * SizeOf(Single));
  end;

  // Memory barrier untuk memastikan data tertulis sepenuhnya di RAM sebelum pointer diupdate
  WriteBarrier;
  Inc(FWriteIdx, Result);
end;

function TRingBuffer.Read(out AData: TFFTDataArray; ACount: Cardinal): Cardinal;
var
  Avail, FirstChunk, SecondChunk, Offset: Cardinal;
begin
  Avail := AvailableToRead;
  if ACount > Avail then
    Result := Avail
  else
    Result := ACount;

  SetLength(AData, Result);
  if Result = 0 then Exit;

  // Memory barrier untuk memastikan pembacaan pointer yang paling mutakhir
  ReadBarrier;
  Offset := FReadIdx and FMask;
  FirstChunk := FCapacity - Offset;

  if Result <= FirstChunk then
  begin
    Move(FBuffer[Offset], AData[0], Result * SizeOf(Single));
  end
  else
  begin
    // Wrap-around pembacaan memori
    SecondChunk := Result - FirstChunk;
    Move(FBuffer[Offset], AData[0], FirstChunk * SizeOf(Single));
    Move(FBuffer[0], AData[FirstChunk], SecondChunk * SizeOf(Single));
  end;

  WriteBarrier;
  Inc(FReadIdx, Result);
end;

end.

