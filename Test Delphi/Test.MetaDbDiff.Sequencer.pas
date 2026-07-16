{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Tests for the DDL topological sequencer (MetaDbDiff.DDL.Sequencer) and the
  DryRun path of the migration executor (MetaDbDiff.Migration.Executor).

  All fixtures build MIK catalogs by hand - no live database is required. The
  executor DryRun mode never needs a connection; the transactional matrix is a
  pure lookup.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Sequencer;

interface

uses
  DB,
  SysUtils,
  Classes,
  Generics.Collections,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Sequencer,
  MetaDbDiff.Migration.Executor,
  // shared IDBConnection double (moved out of this unit, frente-9):
  Test.MetaDbDiff.Fakes,
  // driver registers itself in its initialization:
  MetaDbDiff.DDL.Generator.Firebird;

type
  [TestFixture]
  TTestDDLSequencer = class
  private
    FCatalog: TCatalogMetadataMIK;
    FCommands: TObjectList<TDDLCommand>;
    function _AddTable(const AName: String): TTableMIK;
    /// <summary>Adds a FK on AChild referencing AParentName (AParentName is the
    ///   parent/referenced table = TForeignKeyMIK.FromTable).</summary>
    procedure _AddFK(AChild: TTableMIK; const AParentName: String);
    function _AddColumn(ATable: TTableMIK; const AName: String): TColumnMIK;
    function _NewCreateTable(ATable: TTableMIK): TDDLCommand;
    function _NewDropTable(ATable: TTableMIK): TDDLCommand;
    function _Add(ACommand: TDDLCommand): TDDLCommand;
    /// <summary>ObjectNames of the items classified into APhase, in final order.</summary>
    function _PhaseNames(const AReport: TDDLSequenceReport; APhase: TDDLPhase): TArray<String>;
    function _Firebird: IDDLGeneratorCommand;
    /// <summary>Builds a CREATE TABLE command (with SQL) for a table with 1 column.</summary>
    function _BuiltCreateTable(const AName: String): TDDLCommand;
    /// <summary>Builds a CREATE SEQUENCE command (with SQL).</summary>
    function _BuiltCreateSequence(const AName: String): TDDLCommand;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // ------------------------------------------------------------ topological
    [Test]
    procedure TopologicalOrder_A_B_C;
    [Test]
    procedure Determinism_TiesByName;
    [Test]
    procedure Cycle_IsDetectedAndReported;
    [Test]
    procedure MixedWithCycle_AllCommandsPreserved;
    [Test]
    procedure Drops_AreInverted;
    [Test]
    procedure FkEdge_CaseInsensitive;
    // ----------------------------------------------------------------- phases
    [Test]
    procedure Phases_AreInCanonicalOrder;
    [Test]
    procedure Phases_ForeignKeysAfterAllTables;
    // -------------------------------------------------------- executor DryRun
    [Test]
    procedure DryRun_ScriptHasPhaseHeadersAndSql;
    [Test]
    procedure DryRun_AcceptsNoConnection;
    [Test]
    procedure Dialect_TransactionalMatrix;
    // ------------------------------------------------------- executor Execute
    [Test]
    procedure Execute_TransactionalDialect_CommitsPerPhase;
    [Test]
    procedure Execute_StopOnError_RollsBackAndSkips;
    [Test]
    procedure Execute_ContinueOnError_SkipsRestOfPhaseThenNextPhaseFresh;
    [Test]
    procedure Execute_NonTransactionalDialect_NoTransactionCalls;
    [Test]
    procedure Execute_EmptyCommandIsSkipped;
    [Test]
    procedure Execute_RejectsConnectionAlreadyInTransaction;
  end;

implementation

{ TTestDDLSequencer }

procedure TTestDDLSequencer.Setup;
begin
  FCatalog := TCatalogMetadataMIK.Create;
  FCommands := TObjectList<TDDLCommand>.Create(True);
end;

procedure TTestDDLSequencer.TearDown;
begin
  FCommands.Free;    // owns the TDDLCommand instances
  FCatalog.Free;     // owns the MIK objects (doOwnsValues)
end;

function TTestDDLSequencer._AddTable(const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(FCatalog);
  Result.Name := AName;
  FCatalog.Tables.Add(AName, Result);
end;

function TTestDDLSequencer._AddColumn(ATable: TTableMIK;
  const AName: String): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.TypeName := 'INTEGER';
  Result.NotNull := True;
  ATable.Fields.Add(AName, Result);
end;

procedure TTestDDLSequencer._AddFK(AChild: TTableMIK; const AParentName: String);
var
  LFK: TForeignKeyMIK;
begin
  LFK := TForeignKeyMIK.Create(AChild);
  LFK.Name := Format('FK_%s_%s', [AChild.Name, AParentName]);
  LFK.FromTable := AParentName;   // parent / referenced table
  AChild.ForeignKeys.Add(LFK.Name, LFK);
end;

function TTestDDLSequencer._Add(ACommand: TDDLCommand): TDDLCommand;
begin
  FCommands.Add(ACommand);
  Result := ACommand;
end;

function TTestDDLSequencer._NewCreateTable(ATable: TTableMIK): TDDLCommand;
begin
  Result := _Add(TDDLCommandCreateTable.Create(ATable));
end;

function TTestDDLSequencer._NewDropTable(ATable: TTableMIK): TDDLCommand;
begin
  Result := _Add(TDDLCommandDropTable.Create(ATable));
end;

function TTestDDLSequencer._PhaseNames(const AReport: TDDLSequenceReport;
  APhase: TDDLPhase): TArray<String>;
var
  LItem: TDDLPhaseItem;
begin
  Result := [];
  for LItem in AReport.Items do
    if LItem.Phase = APhase then
      Result := Result + [LItem.ObjectName];
end;

function TTestDDLSequencer._Firebird: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
end;

function TTestDDLSequencer._BuiltCreateTable(const AName: String): TDDLCommand;
var
  LTable: TTableMIK;
begin
  LTable := _AddTable(AName);
  _AddColumn(LTable, 'ID');
  Result := _Add(TDDLCommandCreateTable.Create(LTable));
  Result.BuildCommand(_Firebird);   // F1 guarantees the SQL is built
end;

function TTestDDLSequencer._BuiltCreateSequence(const AName: String): TDDLCommand;
var
  LSeq: TSequenceMIK;
begin
  LSeq := TSequenceMIK.Create(FCatalog);
  LSeq.Name := AName;
  LSeq.InitialValue := 1;
  LSeq.Increment := 1;
  FCatalog.Sequences.Add(AName, LSeq);
  Result := _Add(TDDLCommandCreateSequence.Create(LSeq));
  Result.BuildCommand(_Firebird);
end;

procedure TTestDDLSequencer.TopologicalOrder_A_B_C;
var
  LA, LB, LC: TTableMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LOrder: TArray<String>;
begin
  // C references B, B references A  ->  create A, then B, then C.
  LA := _AddTable('A');
  LB := _AddTable('B');
  LC := _AddTable('C');
  _AddFK(LB, 'A');
  _AddFK(LC, 'B');

  // Feed the commands scrambled on purpose.
  _NewCreateTable(LC);
  _NewCreateTable(LA);
  _NewCreateTable(LB);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  LOrder := _PhaseNames(LReport, dphCreateTables);
  Assert.AreEqual(3, Length(LOrder));
  Assert.AreEqual('A', LOrder[0]);
  Assert.AreEqual('B', LOrder[1]);
  Assert.AreEqual('C', LOrder[2]);
  Assert.IsFalse(LReport.HasCycles, 'Grafo aciclico nao deve reportar ciclo');
end;

procedure TTestDDLSequencer.Determinism_TiesByName;
var
  LX, LY: TTableMIK;
  LSeq: TDDLSequencer;
  LOrder1, LOrder2: TArray<String>;
begin
  // Two independent tables: ties broken deterministically by CompareStr (X < Y).
  LY := _AddTable('Y');
  LX := _AddTable('X');
  _NewCreateTable(LY);
  _NewCreateTable(LX);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LOrder1 := _PhaseNames(LSeq.Sequence(FCommands.ToArray), dphCreateTables);
    LOrder2 := _PhaseNames(LSeq.Sequence(FCommands.ToArray), dphCreateTables);
  finally
    LSeq.Free;
  end;

  Assert.AreEqual('X', LOrder1[0]);
  Assert.AreEqual('Y', LOrder1[1]);
  // Same input -> same output.
  Assert.AreEqual(LOrder1[0], LOrder2[0]);
  Assert.AreEqual(LOrder1[1], LOrder2[1]);
end;

procedure TTestDDLSequencer.Cycle_IsDetectedAndReported;
var
  LA, LB: TTableMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LOrder: TArray<String>;
begin
  // A <-> B mutual references form a cycle.
  LA := _AddTable('A');
  LB := _AddTable('B');
  _AddFK(LA, 'B');
  _AddFK(LB, 'A');
  _NewCreateTable(LA);
  _NewCreateTable(LB);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  Assert.IsTrue(LReport.HasCycles, 'Ciclo A<->B deve ser detectado');
  Assert.AreEqual(1, Length(LReport.Cycles));
  Assert.AreEqual(2, Length(LReport.Cycles[0].Tables));
  Assert.AreEqual('A', LReport.Cycles[0].Tables[0]);
  Assert.AreEqual('B', LReport.Cycles[0].Tables[1]);
  Assert.IsFalse(LReport.Cycles[0].IsDrop);
  // Both tables are still emitted (original order preserved for cyclic ones).
  LOrder := _PhaseNames(LReport, dphCreateTables);
  Assert.AreEqual(2, Length(LOrder));
end;

procedure TTestDDLSequencer.Drops_AreInverted;
var
  LA, LB, LC: TTableMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LOrder: TArray<String>;
begin
  // Same dependency chain C->B->A. Drop order must be reversed: C, B, A.
  LA := _AddTable('A');
  LB := _AddTable('B');
  LC := _AddTable('C');
  _AddFK(LB, 'A');
  _AddFK(LC, 'B');

  _NewDropTable(LA);
  _NewDropTable(LB);
  _NewDropTable(LC);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  LOrder := _PhaseNames(LReport, dphDropTables);
  Assert.AreEqual(3, Length(LOrder));
  Assert.AreEqual('C', LOrder[0]);
  Assert.AreEqual('B', LOrder[1]);
  Assert.AreEqual('A', LOrder[2]);
end;

procedure TTestDDLSequencer.Phases_AreInCanonicalOrder;
var
  LTable: TTableMIK;
  LTrigger: TTriggerMIK;
  LFK: TForeignKeyMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LFor: Integer;
begin
  LTable := _AddTable('T');
  _AddColumn(LTable, 'ID');
  // MIK objects registered in their table dictionaries so the catalog frees them.
  LTrigger := TTriggerMIK.Create(LTable);
  LTrigger.Name := 'TRG';
  LTable.Triggers.Add('TRG', LTrigger);
  LFK := TForeignKeyMIK.Create(LTable);
  LFK.Name := 'FK1';
  LTable.ForeignKeys.Add('FK1', LFK);

  // Feed commands intentionally out of phase order.
  _Add(TDDLCommandEnableForeignKeys.Create(True));    // POST
  _Add(TDDLCommandCreateTrigger.Create(LTrigger));
  _Add(TDDLCommandCreateForeignKey.Create(LFK));
  _Add(TDDLCommandCreateTable.Create(LTable));
  _Add(TDDLCommandEnableForeignKeys.Create(False));   // PRE
  _Add(TDDLCommandCreateColumn.Create(LTable.Fields['ID']));

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  // Phases must be non-decreasing across the reordered list.
  for LFor := 1 to High(LReport.Items) do
    Assert.IsTrue(Ord(LReport.Items[LFor].Phase) >= Ord(LReport.Items[LFor - 1].Phase),
      'Fases devem estar em ordem canonica nao-decrescente');

  Assert.AreEqual(Ord(dphPre), Ord(LReport.Items[0].Phase), 'Primeiro item deve ser PRE');
  Assert.AreEqual(Ord(dphPost), Ord(LReport.Items[High(LReport.Items)].Phase),
    'Ultimo item deve ser POST');
end;

procedure TTestDDLSequencer.Phases_ForeignKeysAfterAllTables;
var
  LTable: TTableMIK;
  LFK: TForeignKeyMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LFor, LLastTable, LFirstFK: Integer;
begin
  LTable := _AddTable('T');
  LFK := TForeignKeyMIK.Create(LTable);
  LFK.Name := 'FK1';
  LTable.ForeignKeys.Add('FK1', LFK);
  _Add(TDDLCommandCreateForeignKey.Create(LFK));
  _Add(TDDLCommandCreateTable.Create(LTable));

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  LLastTable := -1;
  LFirstFK := MaxInt;
  for LFor := 0 to High(LReport.Items) do
  begin
    if LReport.Items[LFor].Phase = dphCreateTables then
      LLastTable := LFor;
    if (LReport.Items[LFor].Phase = dphForeignKeys) and (LFor < LFirstFK) then
      LFirstFK := LFor;
  end;
  Assert.IsTrue(LFirstFK > LLastTable, 'FK deve vir depois de todas as CREATE TABLE');
end;

procedure TTestDDLSequencer.DryRun_ScriptHasPhaseHeadersAndSql;
var
  LTable: TTableMIK;
  LGen: IDDLGeneratorCommand;
  LCmd: TDDLCommand;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LExec: TMigrationExecutor;
  LMig: TMigrationReport;
begin
  LTable := _AddTable('CLIENTE');
  _AddColumn(LTable, 'ID');

  // F1 guarantees BuildCommand at generation; emulate it here.
  LGen := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
  LCmd := _Add(TDDLCommandCreateTable.Create(LTable));
  LCmd.BuildCommand(LGen);

  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
    LMig := LExec.DryRun(LReport);       // no connection at all
  finally
    LExec.Free;
    LSeq.Free;
  end;

  Assert.AreEqual(Ord(mmDryRun), Ord(LMig.Mode));
  Assert.AreEqual(1, LMig.Total);
  Assert.IsTrue(LMig.TransactionalDDL, 'Firebird tem DDL transacional');
  Assert.IsTrue(LMig.Script.Contains('PHASE: Create Tables'),
    'Script deve conter cabecalho de fase');
  Assert.IsTrue(LMig.Script.Contains('CREATE TABLE CLIENTE'),
    'Script deve conter o SQL gerado');
  Assert.IsTrue(LMig.Script.Contains('-- Dialect: Firebird'),
    'Script deve conter o cabecalho de dialeto');
end;

procedure TTestDDLSequencer.DryRun_AcceptsNoConnection;
var
  LExec: TMigrationExecutor;
  LSeqRep: TDDLSequenceReport;
  LMig: TMigrationReport;
begin
  // Empty plan, no connection: DryRun must succeed and produce a header script.
  LSeqRep := Default(TDDLSequenceReport);
  LExec := TMigrationExecutor.Create(dnOracle);
  try
    LMig := LExec.DryRun(LSeqRep);
  finally
    LExec.Free;
  end;
  Assert.AreEqual(0, LMig.Total);
  Assert.IsFalse(LMig.TransactionalDDL, 'Oracle nao promete rollback de DDL');
  Assert.IsTrue(LMig.Script.Contains('MetaDbDiff migration script'));
end;

procedure TTestDDLSequencer.Dialect_TransactionalMatrix;
begin
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnFirebird));
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnFirebird3));
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnPostgreSQL));
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnMSSQL));
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnSQLite));
  Assert.IsTrue(TMigrationExecutor.DialectHasTransactionalDDL(dnInterbase));
  // Implicit-commit dialects:
  Assert.IsFalse(TMigrationExecutor.DialectHasTransactionalDDL(dnOracle));
  Assert.IsFalse(TMigrationExecutor.DialectHasTransactionalDDL(dnMySQL));
  Assert.IsFalse(TMigrationExecutor.DialectHasTransactionalDDL(dnMariaDB));
  Assert.IsFalse(TMigrationExecutor.DialectHasTransactionalDDL(dnDB2));
end;

procedure TTestDDLSequencer.Execute_TransactionalDialect_CommitsPerPhase;
var
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LMig: TMigrationReport;
begin
  _BuiltCreateSequence('S1');   // phase: Create Sequences
  _BuiltCreateTable('T1');      // phase: Create Tables

  LFake := TFakeDBConnection.Create(dnFirebird);
  LConn := LFake;
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);
  try
    LMig := LExec.Execute(LSeq.Sequence(FCommands.ToArray), LConn);
  finally
    LExec.Free;
    LSeq.Free;
  end;

  Assert.AreEqual(2, LMig.Succeeded);
  Assert.AreEqual(0, LMig.Failed);
  Assert.IsFalse(LMig.RolledBack);
  Assert.AreEqual(2, LFake.Executed.Count, 'ambos os comandos executados');
  // One transaction per phase: START/COMMIT, START/COMMIT.
  Assert.AreEqual('START;COMMIT;START;COMMIT', LFake.TxLog.CommaText.Replace(',', ';'));
  Assert.AreEqual(0, LFake.DisconnectCalls, 'nunca desconecta o chamador');
end;

procedure TTestDDLSequencer.Execute_StopOnError_RollsBackAndSkips;
var
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LMig: TMigrationReport;
begin
  _BuiltCreateTable('T1');
  _BuiltCreateTable('T2');
  _BuiltCreateTable('T3');      // all in the same phase (Create Tables), order T1,T2,T3

  LFake := TFakeDBConnection.Create(dnFirebird, 2);  // fail on the 2nd script
  LConn := LFake;
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);     // default = StopOnError
  try
    LMig := LExec.Execute(LSeq.Sequence(FCommands.ToArray), LConn);
  finally
    LExec.Free;
    LSeq.Free;
  end;

  Assert.AreEqual(3, Length(LMig.Items));
  Assert.AreEqual(1, LMig.Succeeded);
  Assert.AreEqual(1, LMig.Failed);
  Assert.AreEqual(1, LMig.Skipped);
  Assert.IsTrue(LMig.RolledBack, 'fase deve ter rollback');
  Assert.AreEqual('START;ROLLBACK', LFake.TxLog.CommaText.Replace(',', ';'));
  Assert.AreEqual(Ord(misSuccess), Ord(LMig.Items[0].Status));
  Assert.AreEqual(Ord(misFailed), Ord(LMig.Items[1].Status));
  Assert.AreEqual(Ord(misSkipped), Ord(LMig.Items[2].Status));
end;

procedure TTestDDLSequencer.Execute_ContinueOnError_SkipsRestOfPhaseThenNextPhaseFresh;
var
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LMig: TMigrationReport;
begin
  _BuiltCreateSequence('S1');   // phase Create Sequences (S1, S2)
  _BuiltCreateSequence('S2');
  _BuiltCreateTable('T1');      // phase Create Tables

  LFake := TFakeDBConnection.Create(dnFirebird, 1);   // S1 (first script) fails
  LConn := LFake;
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);
  LExec.ErrorPolicy := mepContinueOnError;
  try
    LMig := LExec.Execute(LSeq.Sequence(FCommands.ToArray), LConn);
  finally
    LExec.Free;
    LSeq.Free;
  end;

  // S1 fails -> phase rolled back, S2 (rest of phase) Skipped, next phase (T1)
  // runs in a FRESH transaction and commits.
  Assert.AreEqual(1, LMig.Failed);
  Assert.AreEqual(1, LMig.Skipped);
  Assert.AreEqual(1, LMig.Succeeded);
  Assert.IsTrue(LMig.RolledBack);
  Assert.AreEqual('START;ROLLBACK;START;COMMIT', LFake.TxLog.CommaText.Replace(',', ';'));
  // S2 was skipped => never executed; only S1 (failed attempt) and T1 ran.
  Assert.AreEqual(2, LFake.Executed.Count);
  Assert.AreEqual(Ord(misFailed), Ord(LMig.Items[0].Status));
  Assert.AreEqual(Ord(misSkipped), Ord(LMig.Items[1].Status));
  Assert.AreEqual(Ord(misSuccess), Ord(LMig.Items[2].Status));
end;

procedure TTestDDLSequencer.Execute_NonTransactionalDialect_NoTransactionCalls;
var
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LMig: TMigrationReport;
begin
  _BuiltCreateTable('T1');
  _BuiltCreateTable('T2');

  LFake := TFakeDBConnection.Create(dnMySQL);
  LConn := LFake;
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnMySQL);   // implicit-commit DDL
  try
    LMig := LExec.Execute(LSeq.Sequence(FCommands.ToArray), LConn);
  finally
    LExec.Free;
    LSeq.Free;
  end;

  Assert.IsFalse(LMig.TransactionalDDL);
  Assert.AreEqual(2, LMig.Succeeded);
  Assert.IsFalse(LMig.RolledBack);
  Assert.AreEqual(0, LFake.TxLog.Count, 'nenhum Start/Commit/Rollback em dialeto nao-transacional');
  Assert.AreEqual(2, LFake.Executed.Count);
end;

procedure TTestDDLSequencer.Execute_EmptyCommandIsSkipped;
var
  LTable: TTableMIK;
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LMig: TMigrationReport;
begin
  _BuiltCreateTable('T1');      // has SQL
  LTable := _AddTable('T2');    // command WITHOUT BuildCommand -> empty SQL
  _Add(TDDLCommandCreateTable.Create(LTable));

  LFake := TFakeDBConnection.Create(dnFirebird);
  LConn := LFake;
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);
  try
    LMig := LExec.Execute(LSeq.Sequence(FCommands.ToArray), LConn);
  finally
    LExec.Free;
    LSeq.Free;
  end;

  Assert.AreEqual(2, Length(LMig.Items));
  Assert.AreEqual(1, LMig.Succeeded);
  Assert.AreEqual(1, LMig.Empty, 'comando vazio contabilizado como Empty');
  Assert.AreEqual(1, LFake.Executed.Count, 'comando vazio nao e enviado ao banco');
end;

procedure TTestDDLSequencer.Execute_RejectsConnectionAlreadyInTransaction;
var
  LFake: TFakeDBConnection;
  LConn: IDBConnection;
  LExec: TMigrationExecutor;
  LSeq: TDDLSequencer;
  LRep: TDDLSequenceReport;
begin
  _BuiltCreateTable('T1');
  LFake := TFakeDBConnection.Create(dnFirebird);
  LConn := LFake;
  LConn.StartTransaction;     // caller left a transaction open
  LSeq := TDDLSequencer.Create(FCatalog);
  LExec := TMigrationExecutor.Create(dnFirebird);
  try
    LRep := LSeq.Sequence(FCommands.ToArray);
    Assert.WillRaise(
      procedure
      begin
        LExec.Execute(LRep, LConn);
      end,
      EInvalidOpException);
  finally
    LExec.Free;
    LSeq.Free;
  end;
end;

procedure TTestDDLSequencer.MixedWithCycle_AllCommandsPreserved;
var
  LA, LB: TTableMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
begin
  // Mixed batch (PRE + two cyclic CREATE TABLEs + POST) with a A<->B cycle.
  LA := _AddTable('A');
  LB := _AddTable('B');
  _AddFK(LA, 'B');
  _AddFK(LB, 'A');

  _Add(TDDLCommandEnableForeignKeys.Create(False));   // PRE
  _NewCreateTable(LA);
  _NewCreateTable(LB);
  _Add(TDDLCommandEnableForeignKeys.Create(True));    // POST

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  Assert.IsTrue(LReport.HasCycles);
  // Every command is preserved exactly once - none dropped by cycle handling.
  Assert.AreEqual(FCommands.Count, Length(LReport.Items));
  Assert.AreEqual(4, Length(LReport.Items));
  Assert.AreEqual(2, Length(_PhaseNames(LReport, dphCreateTables)));
end;

procedure TTestDDLSequencer.FkEdge_CaseInsensitive;
var
  LSeq: TDDLSequencer;
  LOrder: TArray<String>;
begin
  // Parent 'Z' sorts AFTER child 'A'; only the FK edge can force Z before A.
  // The child's FromTable is lower-case 'z' - normalization must still match it.
  _AddTable('Z');
  _AddTable('A');
  _AddFK(FCatalog.Tables['A'], 'z');     // divergent casing on purpose
  _NewCreateTable(FCatalog.Tables['Z']);
  _NewCreateTable(FCatalog.Tables['A']);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LOrder := _PhaseNames(LSeq.Sequence(FCommands.ToArray), dphCreateTables);
  finally
    LSeq.Free;
  end;

  Assert.AreEqual(2, Length(LOrder));
  Assert.AreEqual('Z', LOrder[0], 'pai Z deve preceder filho A apesar do casing');
  Assert.AreEqual('A', LOrder[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDDLSequencer);

end.
