unit uSQLiteHandler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sqldb, sqlite3conn, db;

type
  { TSQLiteHandler - Mengelola koneksi dan query ke file SQLite VFS }
  TSQLiteHandler = class
  private
    FConnection: TSQLite3Connection;
    FTransaction: TSQLTransaction;
    FQuery: TSQLQuery;
    FDatabasePath: string;
    FLastError: string;
    function CheckAndSeedDatabase: Boolean;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;

    function Connect: Boolean;
    procedure GetNodeVFS(const ATargetIP: string; OutList: TStringList);
    procedure SetNodeCompromised(const ATargetIP: string; AState: Boolean);
    function ExecuteRawSelect(const AQuery: string; OutList: TStringList): Boolean;

    property LastError: string read FLastError;
  end;

implementation

constructor TSQLiteHandler.Create(const APath: string);
begin
  inherited Create;
  FDatabasePath := APath;
  FLastError := '';

  FConnection := TSQLite3Connection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);
  FQuery := TSQLQuery.Create(nil);

  FConnection.Transaction := FTransaction;
  FQuery.DataBase := FConnection;
  FQuery.Transaction := FTransaction;
end;

destructor TSQLiteHandler.Destroy;
begin
  if Assigned(FQuery) then FreeAndNil(FQuery);
  if Assigned(FTransaction) then FreeAndNil(FTransaction);
  if Assigned(FConnection) then FreeAndNil(FConnection);
  inherited Destroy;
end;

function TSQLiteHandler.CheckAndSeedDatabase: Boolean;
var
  HasTables: Boolean;
begin
  Result := False;
  try
    { 1. Cek langsung ke katalog internal SQLite apakah tabel sudah ada }
    FQuery.Close;
    FQuery.SQL.Text := 'SELECT name FROM sqlite_master WHERE type=''table'' AND name=''target_nodes'';';
    FQuery.Open;
    HasTables := not FQuery.EOF;
    FQuery.Close;

    if HasTables then
      Exit(True); // Tabel sudah ada dan berisi data

    { 2. Buat Skema Tabel (Menggunakan transaksi aktif dari FTransaction) }
    FConnection.ExecuteDirect(
      'CREATE TABLE IF NOT EXISTS target_nodes (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'ip_address VARCHAR(15) UNIQUE, ' +
      'hostname VARCHAR(50), ' +
      'open_port INTEGER, ' +
      'signal_freq INTEGER, ' +
      'handshake_hash VARCHAR(64), ' +
      'is_compromised INTEGER);'
    );

    FConnection.ExecuteDirect(
      'CREATE TABLE IF NOT EXISTS vfs_files (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'node_ip VARCHAR(15), ' +
      'file_path VARCHAR(255), ' +
      'file_content TEXT, ' +
      'is_encrypted INTEGER);'
    );

    FConnection.ExecuteDirect(
      'CREATE TABLE IF NOT EXISTS cartel_credentials (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'node_ip VARCHAR(15), ' +
      'username VARCHAR(50), ' +
      'access_token VARCHAR(128), ' +
      'clearance_level INTEGER);'
    );

    { 3. Seed Data Target Nodes }
    FConnection.ExecuteDirect('INSERT INTO target_nodes (ip_address, hostname, open_port, signal_freq, handshake_hash, is_compromised) VALUES (''192.168.0.1'', ''NODE_01_GATEWAY'', 22, 120, ''HASH_0x1A2B'', 1);');
    FConnection.ExecuteDirect('INSERT INTO target_nodes (ip_address, hostname, open_port, signal_freq, handshake_hash, is_compromised) VALUES (''14.1.2.9'', ''PROXY_A_RELAY'', 3128, 300, ''HASH_0x55FF'', 1);');
    FConnection.ExecuteDirect('INSERT INTO target_nodes (ip_address, hostname, open_port, signal_freq, handshake_hash, is_compromised) VALUES (''192.168.0.4'', ''TARGET_MAINFRAME'', 8080, 450, ''HASH_0x8F9A'', 0);');
    FConnection.ExecuteDirect('INSERT INTO target_nodes (ip_address, hostname, open_port, signal_freq, handshake_hash, is_compromised) VALUES (''10.0.0.99'', ''DEAD_DROP_SRV'', 443, 880, ''HASH_0xDEAD'', 0);');

    { 4. Seed Data Virtual File System (VFS) }
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''192.168.0.1'', ''/etc/hosts'', ''127.0.0.1 localhost'', 0);');
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''14.1.2.9'', ''/etc/squid/proxy.conf'', ''http_port 3128'', 0);');
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''192.168.0.4'', ''/etc/passwd'', ''root:x:0:0:root:/root:/bin/bash'', 0);');
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''192.168.0.4'', ''/var/log/acoustic.log'', ''Carrier wave modulated at 450Hz. Key: HASH_0x8F9A'', 0);');
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''192.168.0.4'', ''/opt/cartel/uplink.cfg'', ''DEAD_DROP_IP=10.0.0.99'', 1);');
    FConnection.ExecuteDirect('INSERT INTO vfs_files (node_ip, file_path, file_content, is_encrypted) VALUES (''10.0.0.99'', ''/secret/cartel_manifest.enc'', ''01000101 01000011 01001000 01001111'', 1);');

    { 5. Seed Data Cartel Credentials }
    FConnection.ExecuteDirect('INSERT INTO cartel_credentials (node_ip, username, access_token, clearance_level) VALUES (''192.168.0.1'', ''guest_op'', ''TKN_LOCAL_001'', 1);');
    FConnection.ExecuteDirect('INSERT INTO cartel_credentials (node_ip, username, access_token, clearance_level) VALUES (''192.168.0.4'', ''sysadmin'', ''TKN_MAIN_8F9A_ROOT'', 4);');
    FConnection.ExecuteDirect('INSERT INTO cartel_credentials (node_ip, username, access_token, clearance_level) VALUES (''10.0.0.99'', ''zero_cool'', ''TKN_OMEGA_DEAD_99'', 5);');

    { 6. Simpan permanen ke disk (Flush dari memori ke file .db) }
    FTransaction.Commit;
    FTransaction.StartTransaction;
    Result := True;
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      if FTransaction.Active then
        FTransaction.RollBack;
    end;
  end;
end;

function TSQLiteHandler.Connect: Boolean;
begin
  Result := False;
  try
    ForceDirectories(ExtractFilePath(FDatabasePath));
    FConnection.DatabaseName := FDatabasePath;
    FConnection.Open;
    if not FTransaction.Active then
      FTransaction.StartTransaction;

    Result := CheckAndSeedDatabase;
  except
    on E: Exception do
      FLastError := E.Message;
  end;
end;

procedure TSQLiteHandler.GetNodeVFS(const ATargetIP: string; OutList: TStringList);
begin
  if not Assigned(OutList) or not FConnection.Connected then Exit;
  try
    FQuery.Close;
    FQuery.SQL.Text := 'SELECT file_path, is_encrypted FROM vfs_files WHERE node_ip = :ip';
    FQuery.ParamByName('ip').AsString := ATargetIP;
    FQuery.Open;
    while not FQuery.EOF do
    begin
      if FQuery.FieldByName('is_encrypted').AsInteger = 1 then
        OutList.Add(FQuery.FieldByName('file_path').AsString + ' [ENCRYPTED]')
      else
        OutList.Add(FQuery.FieldByName('file_path').AsString);
      FQuery.Next;
    end;
    FQuery.Close;
  except
  end;
end;

procedure TSQLiteHandler.SetNodeCompromised(const ATargetIP: string; AState: Boolean);
begin
  if not FConnection.Connected then Exit;
  try
    if not FTransaction.Active then
      FTransaction.StartTransaction;
    FQuery.Close;
    FQuery.SQL.Text := 'UPDATE target_nodes SET is_compromised = :st WHERE ip_address = :ip';
    FQuery.ParamByName('st').AsInteger := Ord(AState);
    FQuery.ParamByName('ip').AsString := ATargetIP;
    FQuery.ExecSQL;
    FTransaction.CommitRetaining;
  except
  end;
end;

function TSQLiteHandler.ExecuteRawSelect(const AQuery: string; OutList: TStringList): Boolean;
var
  i: Integer;
  RowStr: string;
begin
  Result := False;
  if not Assigned(OutList) or not FConnection.Connected then Exit;
  try
    FQuery.Close;
    FQuery.SQL.Text := AQuery;
    FQuery.Open;
    Result := True;

    RowStr := '';
    for i := 0 to FQuery.FieldCount - 1 do
      RowStr := RowStr + FQuery.Fields[i].FieldName + ' | ';
    OutList.Add(RowStr);
    OutList.Add(StringOfChar('-', 45));

    while not FQuery.EOF do
    begin
      RowStr := '';
      for i := 0 to FQuery.FieldCount - 1 do
        RowStr := RowStr + FQuery.Fields[i].AsString + ' | ';
      OutList.Add(RowStr);
      FQuery.Next;
    end;
    FQuery.Close;
  except
    on E: Exception do
      OutList.Add('SQL ERROR: ' + E.Message);
  end;
end;

end.
