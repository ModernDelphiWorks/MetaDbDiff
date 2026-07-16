{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Shared test doubles.

  TFakeDBConnection: an in-memory IDBConnection double, originally defined in
  Test.MetaDbDiff.Sequencer. Moved here (frente-9) so both the sequencer/executor
  tests and the sequencer/executor INTEGRATION tests can drive the executor
  without a live database. Records executed scripts and transaction events, can
  be told to fail on the N-th ExecuteScript, and flags whether Disconnect was
  ever called.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Fakes;

interface

uses
  DB,
  SysUtils,
  Classes,
  DataEngine.FactoryInterfaces;

type
  { In-memory IDBConnection double: records executed scripts and transaction
    events, can be told to fail on the N-th ExecuteScript, and flags whether
    Disconnect was ever called. Only the members the executor touches carry
    behaviour; the rest satisfy the interface with harmless defaults. }
  TFakeDBConnection = class(TInterfacedObject, IDBConnection)
  private
    FDriver: TDriverName;
    FConnected: Boolean;
    FInTx: Boolean;
    FFailAt: Integer;      // 1-based ExecuteScript index to fail on (0 = never)
    FExecCount: Integer;
  public
    Executed: TStringList; // scripts actually sent to ExecuteScript
    TxLog: TStringList;    // 'START' / 'COMMIT' / 'ROLLBACK', in order
    DisconnectCalls: Integer;
    constructor Create(ADriver: TDriverName; AFailAt: Integer = 0);
    destructor Destroy; override;
    // --- IDBTransaction ---
    function _GetTransaction(const AKey: String): TComponent;
    procedure StartTransaction(const ALevel: TDBIsolationLevel = ilDefault);
    procedure Commit;
    procedure Rollback;
    procedure AddTransaction(const AKey: String; const ATransaction: TComponent);
    procedure UseTransaction(const AKey: String);
    function TransactionActive: TComponent;
    function InTransaction: Boolean;
    // --- IDBConnection ---
    procedure Connect;
    procedure Disconnect;
    procedure ExecuteDirect(const ASQL: String); overload;
    procedure ExecuteDirect(const ASQL: String; const AParams: TParams); overload;
    procedure ExecuteScript(const AScript: String);
    procedure AddScript(const AScript: String);
    procedure ExecuteScripts;
    procedure ApplyUpdates(const ADataSets: array of IDBDataSet);
    function IsConnected: Boolean;
    function CreateQuery: IDBQuery;
    function CreateDataSet(const ASQL: String = ''): IDBDataSet;
    function BulkLoader: IDBBulkLoader;
    function GetSQLScripts: String;
    function RowsAffected: UInt32;
    function GetDriver: TDriverName;
    function CommandMonitor: ICommandMonitor;
    function MonitorCallback: TMonitorProc;
    function Options: IOptions;
    function Cache: IDBCacheProvider;
    function MetadataCache: IDBMetadataCache;
    procedure SetCacheProvider(ACache: IDBCacheProvider);
    procedure SetMetadataCacheProvider(AMetadataCache: IDBMetadataCache);
    procedure SetCommandMonitor(AMonitor: ICommandMonitor);
    procedure RefreshMetadata(const ATableName: string);
    function IsAlive: Boolean;
    function ResiliencePolicy: IDBResiliencePolicy;
    procedure SetResiliencePolicy(APolicy: IDBResiliencePolicy);
    procedure AddObserver(const AObserver: IDBObserver);
    procedure RemoveObserver(const AObserver: IDBObserver);
    function SlowQueryThreshold: Integer;
    procedure SetSlowQueryThreshold(const AValue: Integer);
  end;

implementation

constructor TFakeDBConnection.Create(ADriver: TDriverName; AFailAt: Integer);
begin
  inherited Create;
  FDriver := ADriver;
  FFailAt := AFailAt;
  FConnected := True;
  Executed := TStringList.Create;
  TxLog := TStringList.Create;
end;

destructor TFakeDBConnection.Destroy;
begin
  Executed.Free;
  TxLog.Free;
  inherited;
end;

procedure TFakeDBConnection.StartTransaction(const ALevel: TDBIsolationLevel);
begin
  FInTx := True;
  TxLog.Add('START');
end;

procedure TFakeDBConnection.Commit;
begin
  FInTx := False;
  TxLog.Add('COMMIT');
end;

procedure TFakeDBConnection.Rollback;
begin
  FInTx := False;
  TxLog.Add('ROLLBACK');
end;

function TFakeDBConnection.InTransaction: Boolean;
begin
  Result := FInTx;
end;

procedure TFakeDBConnection.ExecuteScript(const AScript: String);
begin
  Inc(FExecCount);
  Executed.Add(AScript);
  if (FFailAt > 0) and (FExecCount = FFailAt) then
    raise Exception.CreateFmt('Fake failure at command #%d', [FExecCount]);
end;

procedure TFakeDBConnection.Connect;
begin
  FConnected := True;
end;

procedure TFakeDBConnection.Disconnect;
begin
  Inc(DisconnectCalls);
  FConnected := False;
end;

function TFakeDBConnection.IsConnected: Boolean;
begin
  Result := FConnected;
end;

function TFakeDBConnection.GetDriver: TDriverName;
begin
  Result := FDriver;
end;

// ---- remaining interface members: harmless defaults ------------------------
function TFakeDBConnection._GetTransaction(const AKey: String): TComponent; begin Result := nil; end;
procedure TFakeDBConnection.AddTransaction(const AKey: String; const ATransaction: TComponent); begin end;
procedure TFakeDBConnection.UseTransaction(const AKey: String); begin end;
function TFakeDBConnection.TransactionActive: TComponent; begin Result := nil; end;
procedure TFakeDBConnection.ExecuteDirect(const ASQL: String); begin end;
procedure TFakeDBConnection.ExecuteDirect(const ASQL: String; const AParams: TParams); begin end;
procedure TFakeDBConnection.AddScript(const AScript: String); begin end;
procedure TFakeDBConnection.ExecuteScripts; begin end;
procedure TFakeDBConnection.ApplyUpdates(const ADataSets: array of IDBDataSet); begin end;
function TFakeDBConnection.CreateQuery: IDBQuery; begin Result := nil; end;
function TFakeDBConnection.CreateDataSet(const ASQL: String): IDBDataSet; begin Result := nil; end;
function TFakeDBConnection.BulkLoader: IDBBulkLoader; begin Result := nil; end;
function TFakeDBConnection.GetSQLScripts: String; begin Result := ''; end;
function TFakeDBConnection.RowsAffected: UInt32; begin Result := 0; end;
function TFakeDBConnection.CommandMonitor: ICommandMonitor; begin Result := nil; end;
function TFakeDBConnection.MonitorCallback: TMonitorProc; begin Result := nil; end;
function TFakeDBConnection.Options: IOptions; begin Result := nil; end;
function TFakeDBConnection.Cache: IDBCacheProvider; begin Result := nil; end;
function TFakeDBConnection.MetadataCache: IDBMetadataCache; begin Result := nil; end;
procedure TFakeDBConnection.SetCacheProvider(ACache: IDBCacheProvider); begin end;
procedure TFakeDBConnection.SetMetadataCacheProvider(AMetadataCache: IDBMetadataCache); begin end;
procedure TFakeDBConnection.SetCommandMonitor(AMonitor: ICommandMonitor); begin end;
procedure TFakeDBConnection.RefreshMetadata(const ATableName: string); begin end;
function TFakeDBConnection.IsAlive: Boolean; begin Result := FConnected; end;
function TFakeDBConnection.ResiliencePolicy: IDBResiliencePolicy; begin Result := nil; end;
procedure TFakeDBConnection.SetResiliencePolicy(APolicy: IDBResiliencePolicy); begin end;
procedure TFakeDBConnection.AddObserver(const AObserver: IDBObserver); begin end;
procedure TFakeDBConnection.RemoveObserver(const AObserver: IDBObserver); begin end;
function TFakeDBConnection.SlowQueryThreshold: Integer; begin Result := 0; end;
procedure TFakeDBConnection.SetSlowQueryThreshold(const AValue: Integer); begin end;

end.
