unit uNodeTopology;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Math;

type
  TNetworkNode = class;
  TNodeList = specialize TObjectList<TNetworkNode>;
  TNodeLinkList = specialize TList<TNetworkNode>;
  TNodeDictionary = specialize TDictionary<string, TNetworkNode>;

  { TNetworkNode - Merepresentasikan entitas server/target dalam topologi Acoustic Mesh }
  TNetworkNode = class
  private
    FIPAddress: string;
    FHostname: string;
    FOpenPort: Word;
    FSignalFreq: Integer;
    FHandshakeHash: string;
    FIsCompromised: Boolean;
    FIsScanned: Boolean;
    FPosX: Single;
    FPosY: Single;
    FLinks: TNodeLinkList;
  public
    constructor Create(const AIP, AHost: string; APort: Word; AFreq: Integer;
      const AHash: string; AX, AY: Single; ACompromised: Boolean = False);
    destructor Destroy; override;

    procedure AddLink(ATargetNode: TNetworkNode);

    property IPAddress: string read FIPAddress;
    property Hostname: string read FHostname;
    property OpenPort: Word read FOpenPort;
    property SignalFreq: Integer read FSignalFreq;
    property HandshakeHash: string read FHandshakeHash;
    property IsCompromised: Boolean read FIsCompromised write FIsCompromised;
    property IsScanned: Boolean read FIsScanned write FIsScanned;
    { Koordinat ternormalisasi (0.0 - 1.0) untuk adaptasi resolusi layar (Hi-DPI) }
    property PosX: Single read FPosX write FPosX;
    property PosY: Single read FPosY write FPosY;
    property Links: TNodeLinkList read FLinks;
  end;

  { TTopologyManager - Mengelola graf jaringan di memori dengan pencarian O(1) via Dictionary }
  TTopologyManager = class
  private
    FNodes: TNodeList;
    FNodeMap: TNodeDictionary;
    FActiveNode: TNetworkNode;
    FLastScannedNode: TNetworkNode;
    FTargetNodeIP: string;   { Menyimpan IP dari TARGET_MAINFRAME hasil generasi prosedural }

    function GenerateRandomIP: string;
    function GenerateRandomHash: string;
    function GenerateSafeFrequency: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure BuildDefaultTopology; { Sekarang merupakan generator prosedural acak }

    function AddNode(const AIP, AHost: string; APort: Word; AFreq: Integer;
      const AHash: string; AX, AY: Single; ACompromised: Boolean = False): TNetworkNode;
    procedure ConnectNodes(const AIP1, AIP2: string);

    { Membuka node rahasia DEAD_DROP (10.0.0.99) saat objektif misi terpenuhi }
    function UnlockDeadDropNode: TNetworkNode;

    function FindNodeByIP(const AIP: string): TNetworkNode;
    function FindNodeByFreq(AFreqMin, AFreqMax: Integer): TNetworkNode;

    property Nodes: TNodeList read FNodes;
    property ActiveNode: TNetworkNode read FActiveNode write FActiveNode;
    property LastScannedNode: TNetworkNode read FLastScannedNode write FLastScannedNode;
    property TargetNodeIP: string read FTargetNodeIP;
  end;

implementation

{ TNetworkNode }

constructor TNetworkNode.Create(const AIP, AHost: string; APort: Word;
  AFreq: Integer; const AHash: string; AX, AY: Single; ACompromised: Boolean);
begin
  inherited Create;
  FIPAddress := AIP;
  FHostname := AHost;
  FOpenPort := APort;
  FSignalFreq := AFreq;
  FHandshakeHash := AHash;
  FPosX := AX;
  FPosY := AY;
  FIsCompromised := ACompromised;
  FIsScanned := ACompromised;
  FLinks := TNodeLinkList.Create;
end;

destructor TNetworkNode.Destroy;
begin
  FreeAndNil(FLinks);
  inherited Destroy;
end;

procedure TNetworkNode.AddLink(ATargetNode: TNetworkNode);
begin
  if Assigned(ATargetNode) and (ATargetNode <> Self) and (not FLinks.Contains(ATargetNode)) then
    FLinks.Add(ATargetNode);
end;

{ TTopologyManager }

constructor TTopologyManager.Create;
begin
  inherited Create;
  { FNodes memiliki kepemilikan penuh (OwnsObjects = True) untuk membebaskan memori }
  FNodes := TNodeList.Create(True);
  FNodeMap := TNodeDictionary.Create;
  FActiveNode := nil;
  FLastScannedNode := nil;
  FTargetNodeIP := '';
  Randomize;
end;

destructor TTopologyManager.Destroy;
begin
  FreeAndNil(FNodeMap);
  FreeAndNil(FNodes);
  inherited Destroy;
end;

procedure TTopologyManager.Clear;
begin
  FActiveNode := nil;
  FLastScannedNode := nil;
  FTargetNodeIP := '';
  FNodeMap.Clear;
  FNodes.Clear;
end;

function TTopologyManager.GenerateRandomIP: string;
begin
  Result := Format('%d.%d.%d.%d', [
    10 + Random(200),
    Random(255),
    Random(255),
    1 + Random(254)
  ]);
end;

function TTopologyManager.GenerateRandomHash: string;
const
  HexChars = '0123456789ABCDEF';
var
  i: Integer;
begin
  Result := 'HASH_0x';
  for i := 1 to 4 do
    Result := Result + HexChars[Random(16) + 1];
end;

function TTopologyManager.GenerateSafeFrequency: Integer;
var
  Valid: Boolean;
begin
  { [QA FIX] Pastikan frekuensi acak Honeypot tidak berbenturan dengan frekuensi Target (450Hz) atau Dead Drop (880Hz) }
  Valid := False;
  Result := 100;
  while not Valid do
  begin
    Result := 100 + Random(700); // 100 - 799

    // Jangan izinkan frekuensi di sekitar 450 (Target Mainframe)
    if (Result >= 400) and (Result <= 500) then Continue;

    // Jangan izinkan frekuensi di sekitar 300 (Proxy A)
    if (Result >= 250) and (Result <= 350) then Continue;

    Valid := True;
  end;
end;

function TTopologyManager.AddNode(const AIP, AHost: string; APort: Word;
  AFreq: Integer; const AHash: string; AX, AY: Single; ACompromised: Boolean): TNetworkNode;
begin
  if FNodeMap.TryGetValue(AIP, Result) then
    Exit;

  Result := TNetworkNode.Create(AIP, AHost, APort, AFreq, AHash, AX, AY, ACompromised);
  FNodes.Add(Result);
  FNodeMap.Add(AIP, Result);
end;

procedure TTopologyManager.ConnectNodes(const AIP1, AIP2: string);
var
  N1, N2: TNetworkNode;
begin
  if FNodeMap.TryGetValue(AIP1, N1) and FNodeMap.TryGetValue(AIP2, N2) then
  begin
    N1.AddLink(N2);
    N2.AddLink(N1);
  end;
end;

function TTopologyManager.UnlockDeadDropNode: TNetworkNode;
begin
  Result := FindNodeByIP('10.0.0.99');
  if not Assigned(Result) then
  begin
    { Posisi Dead Drop acak di pinggir peta }
    Result := AddNode('10.0.0.99', 'DEAD_DROP', 443, 880, 'HASH_0xDEAD',
                      0.85 + (Random * 0.1), 0.1 + (Random * 0.8), False);
    { Hubungkan ke node aktif secara otomatis }
    if Assigned(FActiveNode) then
      ConnectNodes(FActiveNode.IPAddress, '10.0.0.99');
  end;
end;

function TTopologyManager.FindNodeByIP(const AIP: string): TNetworkNode;
begin
  if not FNodeMap.TryGetValue(AIP, Result) then
    Result := nil;
end;

function TTopologyManager.FindNodeByFreq(AFreqMin, AFreqMax: Integer): TNetworkNode;
var
  Node: TNetworkNode;
begin
  Result := nil;
  for Node in FNodes do
  begin
    if (Node.SignalFreq >= AFreqMin) and (Node.SignalFreq <= AFreqMax) then
    begin
      Node.IsScanned := True;
      FLastScannedNode := Node;
      Exit(Node);
    end;
  end;
end;

procedure TTopologyManager.BuildDefaultTopology;
var
  NodeCount, i: Integer;
  PrevIP, NewIP, HoneypotIP: string;
  RandX, RandY: Single;
begin
  Clear;

  { 1. Bikin Node Proxy Awal (Selalu sama untuk stabilitas cerita) }
  AddNode('14.1.2.9', 'PROXY_A', 3128, 300, 'HASH_0x55FF', 0.1, 0.5, True);
  FActiveNode := FindNodeByIP('14.1.2.9');
  PrevIP := '14.1.2.9';

  { 2. Generate 3-6 Node Pengalih Acak (Honeypots) }
  NodeCount := 3 + Random(4);
  for i := 1 to NodeCount do
  begin
    NewIP := GenerateRandomIP;
    RandX := 0.2 + (Random * 0.5); // Sebar di tengah (0.2 - 0.7)
    RandY := 0.1 + (Random * 0.8); // Sebar vertikal (0.1 - 0.9)

    AddNode(NewIP, Format('NODE_X%d', [i]),
            Word(20 + Random(8000)),
            GenerateSafeFrequency, // [QA FIX] Panggil fungsi pelindung bentrokan frekuensi
            GenerateRandomHash,
            RandX, RandY, False);

    ConnectNodes(PrevIP, NewIP); // Bentuk jalur tulang punggung (backbone)
    PrevIP := NewIP;

    { Beri percabangan acak agar topologi tidak garis lurus }
    if Random(2) = 0 then
    begin
      HoneypotIP := GenerateRandomIP;
      AddNode(HoneypotIP, Format('HONEYPOT_%d', [i]),
              Word(20 + Random(8000)),
              GenerateSafeFrequency, // [QA FIX]
              GenerateRandomHash,
              RandX, RandY + 0.15, False);
      ConnectNodes(NewIP, HoneypotIP);
    end;
  end;

  { 3. Bikin Node Target Mainframe (Selalu di ujung, tapi IP/Hash acak) }
  FTargetNodeIP := GenerateRandomIP; // IP Target tidak lagi 192.168.0.4 statis!
  AddNode(FTargetNodeIP, 'TARGET_MAINFRAME', 8080, 450,
          GenerateRandomHash, // Hash juga acak
          0.8, 0.5, False);
  ConnectNodes(PrevIP, FTargetNodeIP);

  FLastScannedNode := nil;
end;

end.
