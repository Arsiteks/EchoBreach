unit uMormotServices;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, uNodeTopology, uSQLiteHandler;

type
  { Callback untuk mengirim hasil eksekusi microservice ke Main UI Thread (Pub-Sub Pattern) }
  TServiceLogEvent = procedure(const AMsg: string) of object;
  TServiceNodeUpdateEvent = procedure(ANode: TNetworkNode; ATraceDelta: Integer) of object;

  { IMeshNetworkService - Kontrak antarmuka microservice bergaya mORMot 2 (IInvokable) }
  IMeshNetworkService = interface(IInvokable)
    ['{8F9A2B1C-4D3E-4F5A-9B8C-7D6E5F4A3B2C}']
    procedure AsyncScanFrequency(AFreqMin, AFreqMax: Integer);
    procedure AsyncDeployBotnet(const ATargetIP: string; AStealthMode: Boolean);
    procedure AsyncBounceProxy(const ANewProxyIP: string);
  end;

  { TMeshServiceWorker - Worker Thread asinkron untuk mengeksekusi tugas jaringan berat
    tanpa memblokir LCL Main Event Loop }
  TMeshServiceWorker = class(TThread)
  private
    FTaskType: Integer; // 1: Scan, 2: DeployBot, 3: BounceProxy
    FFreqMin: Integer;
    FFreqMax: Integer;
    FTargetIP: string;
    FStealth: Boolean;
    FTopology: TTopologyManager;
    FDB: TSQLiteHandler;
    FOnLog: TServiceLogEvent;
    FOnNodeUpdate: TServiceNodeUpdateEvent;

    FTempMsg: string;
    FTempNode: TNetworkNode;
    FTempTraceDelta: Integer;

    procedure SyncLog;
    procedure SyncNodeUpdate;
    procedure EmitLog(const AMsg: string);
    procedure EmitNodeUpdate(ANode: TNetworkNode; ATraceDelta: Integer);
  protected
    procedure Execute; override;
  public
    constructor CreateScanTask(ATopology: TTopologyManager; AFreqMin, AFreqMax: Integer;
      AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
    constructor CreateDeployTask(ATopology: TTopologyManager; ADB: TSQLiteHandler;
      const ATargetIP: string; AStealth: Boolean;
      AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
    constructor CreateProxyTask(ATopology: TTopologyManager; const AProxyIP: string;
      AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
  end;

  { TMeshNetworkService - Orchestrator layanan jaringan yang mengelola antrean microservice }
  TMeshNetworkService = class(TInterfacedObject, IMeshNetworkService)
  private
    FTopology: TTopologyManager;
    FDB: TSQLiteHandler;
    FOnLog: TServiceLogEvent;
    FOnNodeUpdate: TServiceNodeUpdateEvent;
  public
    constructor Create(ATopology: TTopologyManager; ADB: TSQLiteHandler;
      AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);

    procedure AsyncScanFrequency(AFreqMin, AFreqMax: Integer);
    procedure AsyncDeployBotnet(const ATargetIP: string; AStealthMode: Boolean);
    procedure AsyncBounceProxy(const ANewProxyIP: string);
  end;

implementation

{ TMeshServiceWorker }

constructor TMeshServiceWorker.CreateScanTask(ATopology: TTopologyManager;
  AFreqMin, AFreqMax: Integer; AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FTaskType := 1;
  FTopology := ATopology;
  FFreqMin := AFreqMin;
  FFreqMax := AFreqMax;
  FOnLog := AOnLog;
  FOnNodeUpdate := AOnUpdate;
  Start;
end;

constructor TMeshServiceWorker.CreateDeployTask(ATopology: TTopologyManager;
  ADB: TSQLiteHandler; const ATargetIP: string; AStealth: Boolean;
  AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FTaskType := 2;
  FTopology := ATopology;
  FDB := ADB;
  FTargetIP := ATargetIP;
  FStealth := AStealth;
  FOnLog := AOnLog;
  FOnNodeUpdate := AOnUpdate;
  Start;
end;

constructor TMeshServiceWorker.CreateProxyTask(ATopology: TTopologyManager;
  const AProxyIP: string; AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FTaskType := 3;
  FTopology := ATopology;
  FTargetIP := AProxyIP;
  FOnLog := AOnLog;
  FOnNodeUpdate := AOnUpdate;
  Start;
end;

procedure TMeshServiceWorker.SyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(FTempMsg);
end;

procedure TMeshServiceWorker.SyncNodeUpdate;
begin
  if Assigned(FOnNodeUpdate) then
    FOnNodeUpdate(FTempNode, FTempTraceDelta);
end;

procedure TMeshServiceWorker.EmitLog(const AMsg: string);
begin
  FTempMsg := AMsg;
  Synchronize(@SyncLog);
end;

procedure TMeshServiceWorker.EmitNodeUpdate(ANode: TNetworkNode; ATraceDelta: Integer);
begin
  FTempNode := ANode;
  FTempTraceDelta := ATraceDelta;
  Synchronize(@SyncNodeUpdate);
end;

procedure TMeshServiceWorker.Execute;
var
  FoundNode: TNetworkNode;
  TraceAdd: Integer;
begin
  case FTaskType of
    1: // Scan Frequency
      begin
        EmitLog('[*] Initializing BASS DSP & Acoustic Mesh scanner...');
        Sleep(400);
        EmitLog(Format('[*] Scanning spectrum range %dHz - %dHz...', [FFreqMin, FFreqMax]));
        Sleep(600);

        FoundNode := nil;
        if Assigned(FTopology) then
          FoundNode := FTopology.FindNodeByFreq(FFreqMin, FFreqMax);

        if Assigned(FoundNode) then
        begin
          EmitLog(Format('[!] Anomaly detected at %dHz -> Host: %s (%s)',
            [FoundNode.SignalFreq, FoundNode.Hostname, FoundNode.IPAddress]));
          EmitNodeUpdate(FoundNode, 5);
        end
        else
          EmitLog('[-] No carrier signal found in specified frequency range.');
      end;

    2: // Deploy Botnet
      begin
        EmitLog('[*] mORMot2 Microservice engaged -> Target: ' + FTargetIP);
        Sleep(400);

        FoundNode := nil;
        if Assigned(FTopology) then
          FoundNode := FTopology.FindNodeByIP(FTargetIP);

        if not Assigned(FoundNode) then
        begin
          EmitLog('[-] Error: Target IP unreachable in current mesh topology.');
          Exit;
        end;

        EmitLog('[*] Querying SQLite VFS & injecting acoustic payload...');
        Sleep(700);

        FoundNode.IsCompromised := True;
        FoundNode.IsScanned := True;

        if Assigned(FDB) then
          FDB.SetNodeCompromised(FTargetIP, True);

        if FStealth then TraceAdd := 15 else TraceAdd := 35;

        EmitLog(Format('[!] Trace Route increased by %d%%', [TraceAdd]));
        EmitLog(Format('[+] Botnet deployed successfully on %s (Port %d OPEN).',
          [FoundNode.Hostname, FoundNode.OpenPort]));

        EmitNodeUpdate(FoundNode, TraceAdd);
      end;

    3: // Bounce Proxy
      begin
        EmitLog('[*] Rerouting acoustic tunnel via ' + FTargetIP + '...');
        Sleep(500);

        FoundNode := nil;
        if Assigned(FTopology) then
          FoundNode := FTopology.FindNodeByIP(FTargetIP);

        if Assigned(FoundNode) and FoundNode.IsCompromised then
        begin
          FTopology.ActiveNode := FoundNode;
          EmitLog('[+] Proxy chain updated. Trace signature cooled down (-25%).');
          EmitNodeUpdate(FoundNode, -25);
        end
        else
          EmitLog('[-] Proxy bounce failed: Node must be compromised first.');
      end;
  end;
end;

{ TMeshNetworkService }

constructor TMeshNetworkService.Create(ATopology: TTopologyManager; ADB: TSQLiteHandler;
  AOnLog: TServiceLogEvent; AOnUpdate: TServiceNodeUpdateEvent);
begin
  inherited Create;
  FTopology := ATopology;
  FDB := ADB;
  FOnLog := AOnLog;
  FOnNodeUpdate := AOnUpdate;
end;

procedure TMeshNetworkService.AsyncScanFrequency(AFreqMin, AFreqMax: Integer);
begin
  TMeshServiceWorker.CreateScanTask(FTopology, AFreqMin, AFreqMax, FOnLog, FOnNodeUpdate);
end;

procedure TMeshNetworkService.AsyncDeployBotnet(const ATargetIP: string; AStealthMode: Boolean);
begin
  TMeshServiceWorker.CreateDeployTask(FTopology, FDB, ATargetIP, AStealthMode, FOnLog, FOnNodeUpdate);
end;

procedure TMeshNetworkService.AsyncBounceProxy(const ANewProxyIP: string);
begin
  TMeshServiceWorker.CreateProxyTask(FTopology, ANewProxyIP, FOnLog, FOnNodeUpdate);
end;

end.

