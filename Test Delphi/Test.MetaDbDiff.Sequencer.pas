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
  // driver registers itself in its initialization:
  MetaDbDiff.DDL.Generator.Firebird;

type
  [TestFixture]
  TTestDDLSequencer = class
  private
    FCatalog: TCatalogMetadataMIK;
    FCommands: TObjectList<TDDLCommand>;
    function AddTable(const AName: String): TTableMIK;
    /// <summary>Adds a FK on AChild referencing AParentName (AParentName is the
    ///   parent/referenced table = TForeignKeyMIK.FromTable).</summary>
    procedure AddFK(AChild: TTableMIK; const AParentName: String);
    function AddColumn(ATable: TTableMIK; const AName: String): TColumnMIK;
    function NewCreateTable(ATable: TTableMIK): TDDLCommand;
    function NewDropTable(ATable: TTableMIK): TDDLCommand;
    function Add(ACommand: TDDLCommand): TDDLCommand;
    /// <summary>ObjectNames of the items classified into APhase, in final order.</summary>
    function PhaseNames(const AReport: TDDLSequenceReport; APhase: TDDLPhase): TArray<String>;
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
    procedure Drops_AreInverted;
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

function TTestDDLSequencer.AddTable(const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(FCatalog);
  Result.Name := AName;
  FCatalog.Tables.Add(AName, Result);
end;

function TTestDDLSequencer.AddColumn(ATable: TTableMIK;
  const AName: String): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.TypeName := 'INTEGER';
  Result.NotNull := True;
  ATable.Fields.Add(AName, Result);
end;

procedure TTestDDLSequencer.AddFK(AChild: TTableMIK; const AParentName: String);
var
  LFK: TForeignKeyMIK;
begin
  LFK := TForeignKeyMIK.Create(AChild);
  LFK.Name := Format('FK_%s_%s', [AChild.Name, AParentName]);
  LFK.FromTable := AParentName;   // parent / referenced table
  AChild.ForeignKeys.Add(LFK.Name, LFK);
end;

function TTestDDLSequencer.Add(ACommand: TDDLCommand): TDDLCommand;
begin
  FCommands.Add(ACommand);
  Result := ACommand;
end;

function TTestDDLSequencer.NewCreateTable(ATable: TTableMIK): TDDLCommand;
begin
  Result := Add(TDDLCommandCreateTable.Create(ATable));
end;

function TTestDDLSequencer.NewDropTable(ATable: TTableMIK): TDDLCommand;
begin
  Result := Add(TDDLCommandDropTable.Create(ATable));
end;

function TTestDDLSequencer.PhaseNames(const AReport: TDDLSequenceReport;
  APhase: TDDLPhase): TArray<String>;
var
  LItem: TDDLPhaseItem;
begin
  Result := [];
  for LItem in AReport.Items do
    if LItem.Phase = APhase then
      Result := Result + [LItem.ObjectName];
end;

procedure TTestDDLSequencer.TopologicalOrder_A_B_C;
var
  LA, LB, LC: TTableMIK;
  LSeq: TDDLSequencer;
  LReport: TDDLSequenceReport;
  LOrder: TArray<String>;
begin
  // C references B, B references A  ->  create A, then B, then C.
  LA := AddTable('A');
  LB := AddTable('B');
  LC := AddTable('C');
  AddFK(LB, 'A');
  AddFK(LC, 'B');

  // Feed the commands scrambled on purpose.
  NewCreateTable(LC);
  NewCreateTable(LA);
  NewCreateTable(LB);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  LOrder := PhaseNames(LReport, dphCreateTables);
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
  LY := AddTable('Y');
  LX := AddTable('X');
  NewCreateTable(LY);
  NewCreateTable(LX);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LOrder1 := PhaseNames(LSeq.Sequence(FCommands.ToArray), dphCreateTables);
    LOrder2 := PhaseNames(LSeq.Sequence(FCommands.ToArray), dphCreateTables);
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
  LA := AddTable('A');
  LB := AddTable('B');
  AddFK(LA, 'B');
  AddFK(LB, 'A');
  NewCreateTable(LA);
  NewCreateTable(LB);

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
  LOrder := PhaseNames(LReport, dphCreateTables);
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
  LA := AddTable('A');
  LB := AddTable('B');
  LC := AddTable('C');
  AddFK(LB, 'A');
  AddFK(LC, 'B');

  NewDropTable(LA);
  NewDropTable(LB);
  NewDropTable(LC);

  LSeq := TDDLSequencer.Create(FCatalog);
  try
    LReport := LSeq.Sequence(FCommands.ToArray);
  finally
    LSeq.Free;
  end;

  LOrder := PhaseNames(LReport, dphDropTables);
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
  LTable := AddTable('T');
  AddColumn(LTable, 'ID');
  // MIK objects registered in their table dictionaries so the catalog frees them.
  LTrigger := TTriggerMIK.Create(LTable);
  LTrigger.Name := 'TRG';
  LTable.Triggers.Add('TRG', LTrigger);
  LFK := TForeignKeyMIK.Create(LTable);
  LFK.Name := 'FK1';
  LTable.ForeignKeys.Add('FK1', LFK);

  // Feed commands intentionally out of phase order.
  Add(TDDLCommandEnableForeignKeys.Create(True));    // POST
  Add(TDDLCommandCreateTrigger.Create(LTrigger));
  Add(TDDLCommandCreateForeignKey.Create(LFK));
  Add(TDDLCommandCreateTable.Create(LTable));
  Add(TDDLCommandEnableForeignKeys.Create(False));   // PRE
  Add(TDDLCommandCreateColumn.Create(LTable.Fields['ID']));

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
  LTable := AddTable('T');
  LFK := TForeignKeyMIK.Create(LTable);
  LFK.Name := 'FK1';
  LTable.ForeignKeys.Add('FK1', LFK);
  Add(TDDLCommandCreateForeignKey.Create(LFK));
  Add(TDDLCommandCreateTable.Create(LTable));

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
  LTable := AddTable('CLIENTE');
  AddColumn(LTable, 'ID');

  // F1 guarantees BuildCommand at generation; emulate it here.
  LGen := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
  LCmd := Add(TDDLCommandCreateTable.Create(LTable));
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

initialization
  TDUnitX.RegisterTestFixture(TTestDDLSequencer);

end.
