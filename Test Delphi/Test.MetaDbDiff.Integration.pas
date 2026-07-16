{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Integration tests for the sequencer + executor wiring (frente-9): the
  TDDLSequencer and TMigrationExecutor plugged into the generation/execution
  flow of TDatabaseAbstract / TDatabaseFactory.

  No live database is required. A testable TDatabaseFactory subclass builds the
  MIK catalogs by hand in ExtractDatabase and delegates execution to the shared
  TFakeDBConnection double via the real TDatabaseAbstract.ExecuteViaExecutor
  path (the same code the production TDatabaseCompare / TModelDatabaseCompare
  overrides call).

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Integration;

interface

uses
  DB,
  SysUtils,
  Classes,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Factory,
  MetaDbDiff.Database.Interfaces,
  MetaDbDiff.Compare.Options,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Sequencer,
  MetaDbDiff.Migration.Executor,
  Test.MetaDbDiff.Fakes,
  // driver registers itself in its initialization:
  MetaDbDiff.DDL.Generator.Firebird;

type
  /// <summary>Which hand-built catalog scenario ExtractDatabase should produce.</summary>
  TIntegrationScenario = (
    isFkChain,        // master: TAB_A (FK -> TAB_B) + TAB_B ; target: empty
    isObsoleteTable,  // master: TAB_A ; target: TAB_A + OBSOLETO (would DROP)
    isColumnDropAlter // master: CLIENTE(ID,NOME60) ; target: CLIENTE(ID,NOME30,OBSOLETO)
  );

  /// <summary>
  ///   Testable factory: fills the catalogs by hand (no DB) and routes
  ///   execution through TDatabaseAbstract.ExecuteViaExecutor onto a fake
  ///   connection - exercising the exact sequencer+executor integration.
  /// </summary>
  TIntegrationFactory = class(TDatabaseFactory)
  private
    FScenario: TIntegrationScenario;
    FFakeConn: IDBConnection;
    function NewTable(ACatalog: TCatalogMetadataMIK; const AName: String): TTableMIK;
    function NewColumn(ATable: TTableMIK; const AName, AType: String;
      ASize: Integer = 0): TColumnMIK;
    procedure NewFK(AChild: TTableMIK; const AParentName: String);
  protected
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(ADriverName: TDriverName); override;
    property Scenario: TIntegrationScenario read FScenario write FScenario;
    property FakeConn: IDBConnection read FFakeConn write FFakeConn;
  end;

  [TestFixture]
  TTestSequencerExecutorIntegration = class
  private
    FFactory: TIntegrationFactory;
    FFake: TFakeDBConnection;
    function IndexOfWarning(const AWarning: String): Integer;
    function DistinctPhaseCount(const AReport: TMigrationReport): Integer;
    function HasCommandClass(AClass: TClass): Boolean;
    function SuppressedContains(const AText: String): Boolean;
  public
    [TearDown]
    procedure TearDown;
    // ---- generation: sequencing plugged in ------------------------------
    [Test]
    procedure BuildWithSequencer_ProducesTopologicalOrder;
    [Test]
    procedure BuildWithoutSequencer_PreservesGenerationOrder;
    [Test]
    procedure BuildWithSequencer_FillsLastSequenceReport;
    // ---- execution: executor plugged in ---------------------------------
    [Test]
    procedure ExecuteCommands_ProducesMigrationReportWithPhases;
    [Test]
    procedure ExecuteCommands_NeverDisconnectsFakeConnection;
    // ---- fail-loud contract (RaiseOnError) ------------------------------
    [Test]
    procedure ExecuteCommands_Failure_RaisesWithSummary_ByDefault;
    [Test]
    procedure ExecuteCommands_Failure_NoRaiseWhenDisabled_ReportViaInterface;
    [Test]
    procedure BuildDatabaseAutoExec_Failure_Raises;
    // ---- convenience API ------------------------------------------------
    [Test]
    procedure GenerateScript_ReturnsTextWithCommandsAndPhases;
    // ---- policy still enforced on the new path --------------------------
    [Test]
    procedure PolicyJanus_SuppressesDrop_OnSequencedPath;
    [Test]
    procedure PolicyTightenedAfterGeneration_ExecuteCommandsRejected;
  end;

implementation

{ TIntegrationFactory }

constructor TIntegrationFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
  FScenario := isFkChain;
end;

function TIntegrationFactory.NewTable(ACatalog: TCatalogMetadataMIK;
  const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  ACatalog.Tables.Add(AName, Result);
end;

function TIntegrationFactory.NewColumn(ATable: TTableMIK; const AName,
  AType: String; ASize: Integer): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.TypeName := AType;
  Result.Size := ASize;
  Result.NotNull := True;
  ATable.Fields.Add(AName, Result);
end;

procedure TIntegrationFactory.NewFK(AChild: TTableMIK; const AParentName: String);
var
  LFK: TForeignKeyMIK;
begin
  LFK := TForeignKeyMIK.Create(AChild);
  LFK.Name := Format('FK_%s_%s', [AChild.Name, AParentName]);
  LFK.FromTable := AParentName;   // parent / referenced table
  AChild.ForeignKeys.Add(LFK.Name, LFK);
end;

procedure TIntegrationFactory.ExtractDatabase;
var
  LTableA, LTableB, LCliente: TTableMIK;
begin
  // BuildDatabase created empty catalogs; fill them by hand (no live DB).
  case FScenario of
    isFkChain:
      begin
        // TAB_A references TAB_B (parent) -> topological CREATE order: B before A.
        LTableB := NewTable(FCatalogMaster, 'TAB_B');
        NewColumn(LTableB, 'ID', 'INTEGER');
        LTableA := NewTable(FCatalogMaster, 'TAB_A');
        NewColumn(LTableA, 'ID', 'INTEGER');
        NewColumn(LTableA, 'B_ID', 'INTEGER');
        NewFK(LTableA, 'TAB_B');
        // target: empty -> every table is a CREATE.
      end;
    isObsoleteTable:
      begin
        LTableA := NewTable(FCatalogMaster, 'TAB_A');
        NewColumn(LTableA, 'ID', 'INTEGER');
        // target has TAB_A plus an obsolete table absent from the model -> DROP.
        LTableA := NewTable(FCatalogTarget, 'TAB_A');
        NewColumn(LTableA, 'ID', 'INTEGER');
        LTableA := NewTable(FCatalogTarget, 'OBSOLETO');
        NewColumn(LTableA, 'ID', 'INTEGER');
      end;
    isColumnDropAlter:
      begin
        // master CLIENTE(ID, NOME VARCHAR(60))
        LCliente := NewTable(FCatalogMaster, 'CLIENTE');
        NewColumn(LCliente, 'ID', 'INTEGER');
        NewColumn(LCliente, 'NOME', 'VARCHAR(%l)', 60);
        // target CLIENTE(ID, NOME VARCHAR(30) -> ALTER, OBSOLETO -> DROP)
        LCliente := NewTable(FCatalogTarget, 'CLIENTE');
        NewColumn(LCliente, 'ID', 'INTEGER');
        NewColumn(LCliente, 'NOME', 'VARCHAR(%l)', 30);
        NewColumn(LCliente, 'OBSOLETO', 'VARCHAR(%l)', 10);
      end;
  end;
end;

procedure TIntegrationFactory.ExecuteDDLCommands;
begin
  inherited;
  // Same wiring the production TDatabaseCompare / TModelDatabaseCompare use.
  if FCommandsAutoExecute then
    ExecuteViaExecutor(FFakeConn);
end;

{ TTestSequencerExecutorIntegration }

procedure TTestSequencerExecutorIntegration.TearDown;
begin
  FreeAndNil(FFactory);
  // FFake is owned by the interface reference held in FFactory.FakeConn; once
  // the factory is gone the last reference drops and the fake is freed. We only
  // keep FFake as a raw pointer for inspection, so do NOT free it here.
  FFake := nil;
end;

function TTestSequencerExecutorIntegration.IndexOfWarning(
  const AWarning: String): Integer;
var
  LList: TArray<TDDLCommand>;
  LFor: Integer;
begin
  Result := -1;
  LList := FFactory.GetCommandList;
  for LFor := 0 to High(LList) do
    if SameText(LList[LFor].Warning, AWarning) then
      Exit(LFor);
end;

function TTestSequencerExecutorIntegration.DistinctPhaseCount(
  const AReport: TMigrationReport): Integer;
var
  LSeen: array[TDDLPhase] of Boolean;
  LItem: TMigrationItemReport;
  LPhase: TDDLPhase;
begin
  for LPhase := Low(TDDLPhase) to High(TDDLPhase) do
    LSeen[LPhase] := False;
  for LItem in AReport.Items do
    LSeen[LItem.Phase] := True;
  Result := 0;
  for LPhase := Low(TDDLPhase) to High(TDDLPhase) do
    if LSeen[LPhase] then
      Inc(Result);
end;

function TTestSequencerExecutorIntegration.HasCommandClass(AClass: TClass): Boolean;
var
  LCommand: TDDLCommand;
begin
  Result := False;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Exit(True);
end;

function TTestSequencerExecutorIntegration.SuppressedContains(
  const AText: String): Boolean;
var
  LItem: String;
begin
  Result := False;
  for LItem in FFactory.SuppressedCommands do
    if Pos(AText, LItem) > 0 then
      Exit(True);
end;

procedure TTestSequencerExecutorIntegration.BuildWithSequencer_ProducesTopologicalOrder;
var
  LIdxA, LIdxB: Integer;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  // UseSequencer defaults to True.
  FFactory.Scenario := isFkChain;
  FFactory.BuildDatabase;

  LIdxB := IndexOfWarning('Create Table: TAB_B');
  LIdxA := IndexOfWarning('Create Table: TAB_A');
  Assert.IsTrue(LIdxB >= 0, 'CREATE TABLE TAB_B deve existir na lista');
  Assert.IsTrue(LIdxA >= 0, 'CREATE TABLE TAB_A deve existir na lista');
  // TAB_A references TAB_B, so B (parent) must be created before A (child).
  Assert.IsTrue(LIdxB < LIdxA,
    'com UseSequencer a tabela pai TAB_B deve vir antes da filha TAB_A');
end;

procedure TTestSequencerExecutorIntegration.BuildWithoutSequencer_PreservesGenerationOrder;
var
  LIdxA, LIdxB: Integer;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.UseSequencer := False;   // fallback: keep historical generation order
  FFactory.Scenario := isFkChain;
  FFactory.BuildDatabase;

  LIdxB := IndexOfWarning('Create Table: TAB_B');
  LIdxA := IndexOfWarning('Create Table: TAB_A');
  Assert.IsTrue((LIdxA >= 0) and (LIdxB >= 0), 'ambos os CREATE devem existir');
  // Historical generation order walks the master tables sorted by name
  // (TablesSort): TAB_A before TAB_B - i.e. NOT topological.
  Assert.IsTrue(LIdxA < LIdxB,
    'sem UseSequencer a ordem historica (TAB_A antes de TAB_B) deve ser preservada');
  Assert.AreEqual(0, Length(FFactory.LastSequenceReport.Items),
    'sem UseSequencer o LastSequenceReport fica vazio');
end;

procedure TTestSequencerExecutorIntegration.BuildWithSequencer_FillsLastSequenceReport;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  FFactory.BuildDatabase;

  Assert.IsTrue(Length(FFactory.LastSequenceReport.Items) > 0,
    'LastSequenceReport deve conter os itens sequenciados');
  Assert.AreEqual(Length(FFactory.GetCommandList),
    Length(FFactory.LastSequenceReport.Items),
    'a contagem de comandos deve ser preservada pelo sequenciamento');
  Assert.IsFalse(FFactory.LastSequenceReport.HasCycles,
    'cenario aciclico nao deve reportar ciclos');
end;

procedure TTestSequencerExecutorIntegration.ExecuteCommands_ProducesMigrationReportWithPhases;
var
  LReport: TMigrationReport;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  FFake := TFakeDBConnection.Create(dnFirebird);
  FFactory.FakeConn := FFake;
  FFactory.BuildDatabase;       // CommandsAutoExecute stays False: generation only
  FFactory.ExecuteCommands;     // now runs through the executor onto the fake conn

  LReport := FFactory.LastMigrationReport;
  Assert.AreEqual(Ord(mmExecute), Ord(LReport.Mode), 'modo de execucao');
  Assert.IsTrue(LReport.TransactionalDDL, 'Firebird tem DDL transacional');
  Assert.IsTrue(LReport.Total > 0, 'o relatorio deve ter itens');
  Assert.IsTrue(LReport.Succeeded > 0, 'comandos devem ter executado com sucesso');
  Assert.AreEqual(0, LReport.Failed, 'nenhuma falha esperada');
  Assert.IsTrue(DistinctPhaseCount(LReport) >= 2,
    'o relatorio deve abranger multiplas fases (PRE/CreateTables/.../POST)');
  Assert.IsTrue(FFake.Executed.Count > 0,
    'os comandos com SQL devem ter sido enviados a conexao');
end;

procedure TTestSequencerExecutorIntegration.ExecuteCommands_NeverDisconnectsFakeConnection;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  FFake := TFakeDBConnection.Create(dnFirebird);
  FFactory.FakeConn := FFake;
  FFactory.BuildDatabase;
  FFactory.ExecuteCommands;

  // The executor never disconnects; this factory (unlike TDatabaseCompare) adds
  // no Disconnect of its own, so the caller's connection is left untouched.
  Assert.AreEqual(0, FFake.DisconnectCalls,
    'o executor nunca desconecta a conexao do chamador');
end;

procedure TTestSequencerExecutorIntegration.ExecuteCommands_Failure_RaisesWithSummary_ByDefault;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  // Fail on the 1st script actually sent to the connection.
  FFake := TFakeDBConnection.Create(dnFirebird, 1);
  FFactory.FakeConn := FFake;
  FFactory.BuildDatabase;   // generation only (CommandsAutoExecute stays False)

  // RaiseOnError defaults True: the fail-loud contract must re-raise.
  Assert.WillRaise(
    procedure
    begin
      FFactory.ExecuteCommands;
    end,
    Exception,
    'com RaiseOnError=True uma falha de migracao deve re-levantar excecao');
  // The report is still populated (and mentions the failure) for inspection.
  Assert.IsTrue(FFactory.LastMigrationReport.Failed > 0,
    'o LastMigrationReport deve registrar a falha mesmo apos o raise');
end;

procedure TTestSequencerExecutorIntegration.ExecuteCommands_Failure_NoRaiseWhenDisabled_ReportViaInterface;
var
  LConcrete: TIntegrationFactory;
  LCompare: IDatabaseCompare;   // owns the lifetime via reference counting
  LReport: TMigrationReport;
begin
  // Built and driven purely through IDatabaseCompare to prove a consumer using
  // ONLY the interface can read the migration outcome (RaiseOnError=False path).
  LConcrete := TIntegrationFactory.Create(dnFirebird);
  LConcrete.Scenario := isFkChain;
  FFake := TFakeDBConnection.Create(dnFirebird, 1);   // fail on the 1st script
  LConcrete.FakeConn := FFake;
  LCompare := LConcrete;              // interface RC now owns LConcrete
  LCompare.RaiseOnError := False;     // opt out of fail-loud
  LCompare.BuildDatabase;
  // Must NOT raise even though a command fails.
  LCompare.ExecuteCommands;
  LReport := LCompare.LastMigrationReport;   // read VIA INTERFACE
  Assert.IsTrue(LReport.Failed > 0,
    'via interface o consumidor deve enxergar a falha em LastMigrationReport');
  Assert.IsTrue(FFake.Executed.Count > 0, 'ao menos um comando foi tentado');
  // FFactory stays nil; TearDown FreeAndNil(FFactory) is a no-op. LConcrete is
  // freed when LCompare is released at method exit (which also frees the fake).
end;

procedure TTestSequencerExecutorIntegration.BuildDatabaseAutoExec_Failure_Raises;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  FFake := TFakeDBConnection.Create(dnFirebird, 1);
  FFactory.FakeConn := FFake;
  FFactory.CommandsAutoExecute := True;   // BuildDatabase both generates AND runs

  // Auto-exec generation that fails must surface the failure (fail-loud default).
  Assert.WillRaise(
    procedure
    begin
      FFactory.BuildDatabase;
    end,
    Exception,
    'BuildDatabase com auto-exec e falha deve re-levantar excecao');
end;

procedure TTestSequencerExecutorIntegration.GenerateScript_ReturnsTextWithCommandsAndPhases;
var
  LScript: String;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isFkChain;
  FFactory.BuildDatabase;

  LScript := FFactory.GenerateScript;   // DryRun: never touches the DB
  Assert.IsTrue(LScript.Contains('MetaDbDiff migration script'),
    'o script deve conter o cabecalho');
  Assert.IsTrue(LScript.Contains('CREATE TABLE TAB_B'),
    'o script deve conter o SQL gerado');
  Assert.IsTrue(LScript.Contains('PHASE: Create Tables'),
    'o script deve conter os cabecalhos de fase em comentario');
end;

procedure TTestSequencerExecutorIntegration.PolicyJanus_SuppressesDrop_OnSequencedPath;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isObsoleteTable;
  FFactory.Policy := TComparePolicy.JanusOrmProfile;  // never DROP
  // UseSequencer stays True: the policy gate must still hold on the new path.
  FFactory.BuildDatabase;

  Assert.IsFalse(HasCommandClass(TDDLCommandDropTable),
    'DROP TABLE nunca deve ser emitido no perfil Janus, mesmo com sequenciador');
  Assert.IsTrue(SuppressedContains('DROP TABLE'),
    'a auditoria deve registrar o DROP TABLE suprimido');
end;

procedure TTestSequencerExecutorIntegration.PolicyTightenedAfterGeneration_ExecuteCommandsRejected;
begin
  FFactory := TIntegrationFactory.Create(dnFirebird);
  FFactory.Scenario := isColumnDropAlter;
  FFake := TFakeDBConnection.Create(dnFirebird);
  FFactory.FakeConn := FFake;
  // Generate with FullProfile: the list DOES contain a DROP COLUMN.
  FFactory.BuildDatabase;
  Assert.IsTrue(HasCommandClass(TDDLCommandDropColumn),
    'pre-condicao: a lista deveria conter um DROP COLUMN');

  // Tighten the policy, then try to execute: the defense-in-depth re-check in
  // ExecuteCommands must reject before the executor runs a single statement.
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  Assert.WillRaise(
    procedure
    begin
      FFactory.ExecuteCommands;
    end,
    Exception,
    'ExecuteCommands deve recusar comando nao permitido pela policy (caminho novo)');
  Assert.AreEqual(0, FFake.Executed.Count,
    'nada deve ser enviado a conexao quando a policy recusa');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSequencerExecutorIntegration);

end.
