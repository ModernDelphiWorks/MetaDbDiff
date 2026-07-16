{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Metadata snapshot tests (TMetadataSnapshot / TMetadataSnapshotFactory /
  TMetadataExporter) WITHOUT a live database, except for the shell FireDAC
  connection pattern already used by Test.MetaDbDiff.Metadata.Model.pas
  (an UNCONNECTED TFDConnection just to report a dialect).

  The most important test here is the round-trip fidelity one: a rich MIK
  catalog is built BY HAND (multiple column types with precision/scale/
  default/notnull, composite PK, FK with rules, unique composite index,
  checks, a trigger, a view and a sequence), saved to a snapshot file,
  reloaded, compared field-by-field against the original with a deep-compare
  helper, and then diffed against the original via the real
  TDatabaseFactory.GenerateDDLCommands expecting ZERO commands - proving the
  snapshot round-trips with no information loss that would affect the diff.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Snapshot;

interface

uses
  DB,
  SysUtils,
  Classes,
  Generics.Collections,
  System.IOUtils,
  System.JSON,
  DUnitX.TestFramework,
  FireDAC.Comp.Client,
  DataEngine.FactoryInterfaces,
  DataEngine.FactoryFireDac,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Factory,
  MetaDbDiff.Metadata.Model,
  MetaDbDiff.Metadata.Snapshot,
  MetaDbDiff.Metadata.Snapshot.Factory,
  MetaDbDiff.Metadata.Snapshot.Export,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.Compare.Options,
  MetaDbDiff.DDL.Generator.Firebird,
  Test.MetaDbDiff.Entities;

type
  /// <summary>
  ///   Minimal concrete TDatabaseFactory descendant used ONLY to drive the
  ///   real GenerateDDLCommands over two already-built catalogs, without
  ///   taking ownership of them (unlike Test.MetaDbDiff.Policy.pas's
  ///   TTestableFactory.Generate, which DOES take ownership - here the
  ///   catalogs are freed by the test itself, since they are also used for
  ///   the field-by-field deep-compare). ExtractDatabase/ExecuteDDLCommands
  ///   are both abstract on TDatabaseFactory and are never exercised.
  /// </summary>
  TDiffOnlyFactory = class(TDatabaseFactory)
  public
    constructor Create(ADriverName: TDriverName); override;
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
    procedure Diff(AMaster, ATarget: TCatalogMetadataMIK);
  end;

  [TestFixture]
  TTestMetadataSnapshot = class
  private
    FSnapshotFile: String;
    function _BuildRichCatalog: TCatalogMetadataMIK;
    procedure _AssertColumnsEqual(AExpected, AActual: TColumnMIK; const AContext: String);
    procedure _AssertColumnDictEqual(AExpected, AActual: TObjectDictionary<String, TColumnMIK>;
      const AContext: String);
    procedure _AssertPrimaryKeyEqual(AExpected, AActual: TPrimaryKeyMIK; const AContext: String);
    procedure _AssertForeignKeysEqual(AExpected, AActual: TTableMIK; const AContext: String);
    procedure _AssertIndexesEqual(AExpected, AActual: TTableMIK; const AContext: String);
    procedure _AssertChecksEqual(AExpected, AActual: TTableMIK; const AContext: String);
    procedure _AssertTriggersEqual(AExpected, AActual: TTableMIK; const AContext: String);
    procedure _AssertTablesEqual(AExpected, AActual: TCatalogMetadataMIK);
    procedure _AssertSequencesEqual(AExpected, AActual: TCatalogMetadataMIK);
    procedure _AssertViewsEqual(AExpected, AActual: TCatalogMetadataMIK);
    procedure _AssertCatalogsEqual(AExpected, AActual: TCatalogMetadataMIK);
    function _DiffCommandCount(AMaster, ATarget: TCatalogMetadataMIK): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure RoundTrip_FieldByField_IsFaithful;
    [Test]
    procedure RoundTrip_DiffAgainstOriginal_ProducesZeroCommands;
    [Test]
    procedure Snapshot_FutureFormatVersion_RaisesClearError;
    [Test]
    procedure Snapshot_CorruptedJson_RaisesClearError;
    [Test]
    procedure Snapshot_EmptyFile_RaisesClearError;
    [Test]
    procedure Snapshot_MissingFile_RaisesClearError;
    [Test]
    procedure Snapshot_EnumsAreSerializedByName;
    [Test]
    procedure Snapshot_DriverNameIsSerializedByName;
    [Test]
    procedure SnapshotFactory_ExtractMetadata_PopulatesCallerCatalog;
    [Test]
    procedure ModelSnapshot_ExportThenLoad_DiffAgainstFreshModelExtractionIsZero;
  end;

implementation

{ TDiffOnlyFactory }

constructor TDiffOnlyFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
end;

procedure TDiffOnlyFactory.ExtractDatabase;
begin
  // Not exercised: catalogs are handed directly to Diff/GenerateDDLCommands.
end;

procedure TDiffOnlyFactory.ExecuteDDLCommands;
begin
  // Not exercised: no live connection in these tests.
end;

procedure TDiffOnlyFactory.Diff(AMaster, ATarget: TCatalogMetadataMIK);
begin
  // Deliberately does NOT assign FCatalogMaster/FCatalogTarget - the caller
  // keeps ownership of both catalogs (needed for the deep-compare helper).
  GenerateDDLCommands(AMaster, ATarget);
end;

{ TTestMetadataSnapshot }

procedure TTestMetadataSnapshot.Setup;
begin
  FSnapshotFile := TPath.Combine(TPath.GetTempPath,
    'metadbdiff_snapshot_test_' + IntToStr(Random(MaxInt)) + '.json');
end;

procedure TTestMetadataSnapshot.TearDown;
begin
  if (FSnapshotFile <> '') and FileExists(FSnapshotFile) then
    TFile.Delete(FSnapshotFile);
end;

function TTestMetadataSnapshot._BuildRichCatalog: TCatalogMetadataMIK;
var
  LCliente, LPedido: TTableMIK;
  LColumn: TColumnMIK;
  LFk: TForeignKeyMIK;
  LIdx: TIndexeKeyMIK;
  LChk: TCheckMIK;
  LTrg: TTriggerMIK;
  LSeq: TSequenceMIK;
  LView: TViewMIK;
begin
  Result := TCatalogMetadataMIK.Create;
  Result.Name := 'TESTDB';
  Result.Schema := 'PUBLIC';
  Result.Description := 'Catalogo de teste do round-trip de snapshot';

  // ---------------- CLIENTE ----------------
  LCliente := TTableMIK.Create(Result);
  LCliente.Name := 'CLIENTE';
  LCliente.Description := 'Tabela de clientes';
  Result.Tables.Add(UpperCase(LCliente.Name), LCliente);

  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'ID';
  LColumn.Description := 'Chave primaria';
  LColumn.Position := 0;
  LColumn.FieldType := ftInteger;
  LColumn.TypeName := 'INTEGER';
  LColumn.NotNull := True;
  LColumn.AutoIncrement := True;
  LColumn.IsPrimaryKey := True;
  LCliente.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'NOME';
  LColumn.Position := 1;
  LColumn.FieldType := ftString;
  LColumn.TypeName := 'VARCHAR(%l)';
  LColumn.Size := 60;
  LColumn.NotNull := True;
  LColumn.DefaultValue := 'SEM NOME';
  LCliente.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'SALDO';
  LColumn.Position := 2;
  LColumn.FieldType := ftBCD;
  LColumn.TypeName := 'DECIMAL(%p,%s)';
  LColumn.Precision := 18;
  LColumn.Scale := 2;
  LColumn.DefaultValue := '0';
  LCliente.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'CRIADO_EM';
  LColumn.Position := 3;
  LColumn.FieldType := ftDateTime;
  LColumn.TypeName := 'TIMESTAMP';
  LColumn.DefaultValue := 'CURRENT_TIMESTAMP';
  LCliente.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'CODIGO_EXTERNO';
  LColumn.Position := 4;
  LColumn.FieldType := ftGuid;
  LColumn.TypeName := 'CHAR(%l)';
  LColumn.Size := 16;
  LColumn.CharSet := 'OCTETS';
  LCliente.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LCliente.PrimaryKey.Name := 'PK_CLIENTE';
  LCliente.PrimaryKey.AutoIncrement := True;
  LCliente.PrimaryKey.Description := 'PK de cliente';
  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'ID';
  LColumn.Position := 0;
  LColumn.SortingOrder := TSortingOrder.Ascending;
  LCliente.PrimaryKey.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LIdx := TIndexeKeyMIK.Create(LCliente);
  LIdx.Name := 'IDX_CLIENTE_NOME';
  LIdx.Unique := False;
  LIdx.Description := 'Indice por nome';
  LColumn := TColumnMIK.Create(LCliente);
  LColumn.Name := 'NOME';
  LColumn.Position := 0;
  LIdx.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LCliente.IndexeKeys.Add(UpperCase(LIdx.Name), LIdx);

  LChk := TCheckMIK.Create(LCliente);
  LChk.Name := 'CK_CLIENTE_SALDO';
  LChk.Condition := 'SALDO >= 0';
  LChk.Description := 'Saldo nao pode ser negativo';
  LCliente.Checks.Add(UpperCase(LChk.Name), LChk);

  LTrg := TTriggerMIK.Create(LCliente);
  LTrg.Name := 'TRG_CLIENTE_BI';
  LTrg.Script := 'BEFORE INSERT AS BEGIN NEW.CRIADO_EM = CURRENT_TIMESTAMP; END';
  LTrg.Description := 'Preenche CRIADO_EM automaticamente';
  LCliente.Triggers.Add(UpperCase(LTrg.Name), LTrg);

  // ---------------- PEDIDO ----------------
  LPedido := TTableMIK.Create(Result);
  LPedido.Name := 'PEDIDO';
  LPedido.Description := 'Tabela de pedidos';
  Result.Tables.Add(UpperCase(LPedido.Name), LPedido);

  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_EMPRESA';
  LColumn.Position := 0;
  LColumn.FieldType := ftInteger;
  LColumn.TypeName := 'INTEGER';
  LColumn.NotNull := True;
  LColumn.IsPrimaryKey := True;
  LPedido.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_PEDIDO';
  LColumn.Position := 1;
  LColumn.FieldType := ftInteger;
  LColumn.TypeName := 'INTEGER';
  LColumn.NotNull := True;
  LColumn.IsPrimaryKey := True;
  LPedido.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_CLIENTE';
  LColumn.Position := 2;
  LColumn.FieldType := ftInteger;
  LColumn.TypeName := 'INTEGER';
  LPedido.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'VALOR_TOTAL';
  LColumn.Position := 3;
  LColumn.FieldType := ftCurrency;
  LColumn.TypeName := 'NUMERIC(%p,%s)';
  LColumn.Precision := 15;
  LColumn.Scale := 2;
  LPedido.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LPedido.PrimaryKey.Name := 'PK_PEDIDO';
  LPedido.PrimaryKey.AutoIncrement := False;
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_EMPRESA';
  LColumn.Position := 0;
  LPedido.PrimaryKey.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_PEDIDO';
  LColumn.Position := 1;
  LPedido.PrimaryKey.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);

  LFk := TForeignKeyMIK.Create(LPedido);
  LFk.Name := 'FK_PEDIDO_CLIENTE';
  LFk.FromTable := 'CLIENTE';
  LFk.OnUpdate := TRuleAction.SetNull;
  LFk.OnDelete := TRuleAction.Cascade;
  LFk.Description := 'FK para cliente';
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_CLIENTE';
  LColumn.Position := 0;
  LFk.FromFields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID';
  LColumn.Position := 0;
  LFk.ToFields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LPedido.ForeignKeys.Add(UpperCase(LFk.Name), LFk);

  LIdx := TIndexeKeyMIK.Create(LPedido);
  LIdx.Name := 'IDX_PEDIDO_UNQ';
  LIdx.Unique := True;
  LIdx.Description := 'Indice unico da chave composta';
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_EMPRESA';
  LColumn.Position := 0;
  LIdx.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LColumn := TColumnMIK.Create(LPedido);
  LColumn.Name := 'ID_PEDIDO';
  LColumn.Position := 1;
  LIdx.Fields.Add(FormatFloat('000000', LColumn.Position), LColumn);
  LPedido.IndexeKeys.Add(UpperCase(LIdx.Name), LIdx);

  // ---------------- Sequence ----------------
  LSeq := TSequenceMIK.Create(Result);
  LSeq.Name := 'SEQ_CLIENTE';
  LSeq.TableName := 'CLIENTE';
  LSeq.InitialValue := 1;
  LSeq.Increment := 1;
  LSeq.Description := 'Sequence de cliente';
  Result.Sequences.Add(UpperCase(LSeq.Name), LSeq);

  // ---------------- View ----------------
  LView := TViewMIK.Create(Result);
  LView.Name := 'VW_CLIENTE_RESUMO';
  LView.Script := 'CREATE VIEW VW_CLIENTE_RESUMO AS SELECT ID, NOME FROM CLIENTE';
  LView.Description := 'View resumo de clientes';
  LColumn := TColumnMIK.Create(nil);
  LColumn.Name := 'ID';
  LView.Fields.Add(UpperCase(LColumn.Name), LColumn);
  LColumn := TColumnMIK.Create(nil);
  LColumn.Name := 'NOME';
  LView.Fields.Add(UpperCase(LColumn.Name), LColumn);
  Result.Views.Add(UpperCase(LView.Name), LView);
end;

procedure TTestMetadataSnapshot._AssertColumnsEqual(AExpected, AActual: TColumnMIK; const AContext: String);
begin
  Assert.AreEqual(AExpected.Name, AActual.Name, AContext + '.Name');
  Assert.AreEqual(AExpected.Description, AActual.Description, AContext + '.Description');
  Assert.AreEqual(AExpected.Position, AActual.Position, AContext + '.Position');
  Assert.IsTrue(AExpected.FieldType = AActual.FieldType, AContext + '.FieldType');
  Assert.AreEqual(AExpected.TypeName, AActual.TypeName, AContext + '.TypeName');
  Assert.AreEqual(AExpected.Size, AActual.Size, AContext + '.Size');
  Assert.AreEqual(AExpected.Precision, AActual.Precision, AContext + '.Precision');
  Assert.AreEqual(AExpected.Scale, AActual.Scale, AContext + '.Scale');
  Assert.AreEqual(AExpected.NotNull, AActual.NotNull, AContext + '.NotNull');
  Assert.AreEqual(AExpected.AutoIncrement, AActual.AutoIncrement, AContext + '.AutoIncrement');
  Assert.IsTrue(AExpected.SortingOrder = AActual.SortingOrder, AContext + '.SortingOrder');
  Assert.AreEqual(AExpected.DefaultValue, AActual.DefaultValue, AContext + '.DefaultValue');
  Assert.AreEqual(AExpected.IsPrimaryKey, AActual.IsPrimaryKey, AContext + '.IsPrimaryKey');
  Assert.AreEqual(AExpected.CharSet, AActual.CharSet, AContext + '.CharSet');
end;

procedure TTestMetadataSnapshot._AssertColumnDictEqual(AExpected, AActual: TObjectDictionary<String, TColumnMIK>;
  const AContext: String);
var
  LPair: TPair<String, TColumnMIK>;
begin
  Assert.AreEqual(AExpected.Count, AActual.Count, AContext + '.Count');
  for LPair in AExpected do
  begin
    Assert.IsTrue(AActual.ContainsKey(LPair.Key),
      AContext + ': chave "' + LPair.Key + '" ausente apos o round-trip');
    _AssertColumnsEqual(LPair.Value, AActual[LPair.Key], AContext + '[' + LPair.Key + ']');
  end;
end;

procedure TTestMetadataSnapshot._AssertPrimaryKeyEqual(AExpected, AActual: TPrimaryKeyMIK; const AContext: String);
begin
  Assert.AreEqual(AExpected.Name, AActual.Name, AContext + '.PrimaryKey.Name');
  Assert.AreEqual(AExpected.Description, AActual.Description, AContext + '.PrimaryKey.Description');
  Assert.AreEqual(AExpected.AutoIncrement, AActual.AutoIncrement, AContext + '.PrimaryKey.AutoIncrement');
  _AssertColumnDictEqual(AExpected.Fields, AActual.Fields, AContext + '.PrimaryKey.Fields');
end;

procedure TTestMetadataSnapshot._AssertForeignKeysEqual(AExpected, AActual: TTableMIK; const AContext: String);
var
  LPair: TPair<String, TForeignKeyMIK>;
  LOther: TForeignKeyMIK;
begin
  Assert.AreEqual(AExpected.ForeignKeys.Count, AActual.ForeignKeys.Count, AContext + '.ForeignKeys.Count');
  for LPair in AExpected.ForeignKeys do
  begin
    Assert.IsTrue(AActual.ForeignKeys.ContainsKey(LPair.Key),
      AContext + '.ForeignKeys: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.ForeignKeys[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, AContext + '.ForeignKeys.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, AContext + '.ForeignKeys.Description');
    Assert.AreEqual(LPair.Value.FromTable, LOther.FromTable, AContext + '.ForeignKeys.FromTable');
    Assert.IsTrue(LPair.Value.OnUpdate = LOther.OnUpdate, AContext + '.ForeignKeys.OnUpdate');
    Assert.IsTrue(LPair.Value.OnDelete = LOther.OnDelete, AContext + '.ForeignKeys.OnDelete');
    _AssertColumnDictEqual(LPair.Value.FromFields, LOther.FromFields, AContext + '.ForeignKeys.FromFields');
    _AssertColumnDictEqual(LPair.Value.ToFields, LOther.ToFields, AContext + '.ForeignKeys.ToFields');
  end;
end;

procedure TTestMetadataSnapshot._AssertIndexesEqual(AExpected, AActual: TTableMIK; const AContext: String);
var
  LPair: TPair<String, TIndexeKeyMIK>;
  LOther: TIndexeKeyMIK;
begin
  Assert.AreEqual(AExpected.IndexeKeys.Count, AActual.IndexeKeys.Count, AContext + '.IndexeKeys.Count');
  for LPair in AExpected.IndexeKeys do
  begin
    Assert.IsTrue(AActual.IndexeKeys.ContainsKey(LPair.Key),
      AContext + '.IndexeKeys: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.IndexeKeys[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, AContext + '.IndexeKeys.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, AContext + '.IndexeKeys.Description');
    Assert.AreEqual(LPair.Value.Unique, LOther.Unique, AContext + '.IndexeKeys.Unique');
    _AssertColumnDictEqual(LPair.Value.Fields, LOther.Fields, AContext + '.IndexeKeys.Fields');
  end;
end;

procedure TTestMetadataSnapshot._AssertChecksEqual(AExpected, AActual: TTableMIK; const AContext: String);
var
  LPair: TPair<String, TCheckMIK>;
  LOther: TCheckMIK;
begin
  Assert.AreEqual(AExpected.Checks.Count, AActual.Checks.Count, AContext + '.Checks.Count');
  for LPair in AExpected.Checks do
  begin
    Assert.IsTrue(AActual.Checks.ContainsKey(LPair.Key),
      AContext + '.Checks: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.Checks[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, AContext + '.Checks.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, AContext + '.Checks.Description');
    Assert.AreEqual(LPair.Value.Condition, LOther.Condition, AContext + '.Checks.Condition');
  end;
end;

procedure TTestMetadataSnapshot._AssertTriggersEqual(AExpected, AActual: TTableMIK; const AContext: String);
var
  LPair: TPair<String, TTriggerMIK>;
  LOther: TTriggerMIK;
begin
  Assert.AreEqual(AExpected.Triggers.Count, AActual.Triggers.Count, AContext + '.Triggers.Count');
  for LPair in AExpected.Triggers do
  begin
    Assert.IsTrue(AActual.Triggers.ContainsKey(LPair.Key),
      AContext + '.Triggers: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.Triggers[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, AContext + '.Triggers.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, AContext + '.Triggers.Description');
    Assert.AreEqual(LPair.Value.Script, LOther.Script, AContext + '.Triggers.Script');
  end;
end;

procedure TTestMetadataSnapshot._AssertTablesEqual(AExpected, AActual: TCatalogMetadataMIK);
var
  LPair: TPair<String, TTableMIK>;
  LOther: TTableMIK;
  LContext: String;
begin
  Assert.AreEqual(AExpected.Tables.Count, AActual.Tables.Count, 'Tables.Count');
  for LPair in AExpected.Tables do
  begin
    Assert.IsTrue(AActual.Tables.ContainsKey(LPair.Key),
      'Tables: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.Tables[LPair.Key];
    LContext := 'Tables[' + LPair.Key + ']';
    Assert.AreEqual(LPair.Value.Name, LOther.Name, LContext + '.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, LContext + '.Description');
    _AssertColumnDictEqual(LPair.Value.Fields, LOther.Fields, LContext + '.Fields');
    _AssertPrimaryKeyEqual(LPair.Value.PrimaryKey, LOther.PrimaryKey, LContext);
    _AssertIndexesEqual(LPair.Value, LOther, LContext);
    _AssertForeignKeysEqual(LPair.Value, LOther, LContext);
    _AssertChecksEqual(LPair.Value, LOther, LContext);
    _AssertTriggersEqual(LPair.Value, LOther, LContext);
  end;
end;

procedure TTestMetadataSnapshot._AssertSequencesEqual(AExpected, AActual: TCatalogMetadataMIK);
var
  LPair: TPair<String, TSequenceMIK>;
  LOther: TSequenceMIK;
begin
  Assert.AreEqual(AExpected.Sequences.Count, AActual.Sequences.Count, 'Sequences.Count');
  for LPair in AExpected.Sequences do
  begin
    Assert.IsTrue(AActual.Sequences.ContainsKey(LPair.Key),
      'Sequences: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.Sequences[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, 'Sequences.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, 'Sequences.Description');
    Assert.AreEqual(LPair.Value.TableName, LOther.TableName, 'Sequences.TableName');
    Assert.AreEqual(LPair.Value.InitialValue, LOther.InitialValue, 'Sequences.InitialValue');
    Assert.AreEqual(LPair.Value.Increment, LOther.Increment, 'Sequences.Increment');
  end;
end;

procedure TTestMetadataSnapshot._AssertViewsEqual(AExpected, AActual: TCatalogMetadataMIK);
var
  LPair: TPair<String, TViewMIK>;
  LOther: TViewMIK;
begin
  Assert.AreEqual(AExpected.Views.Count, AActual.Views.Count, 'Views.Count');
  for LPair in AExpected.Views do
  begin
    Assert.IsTrue(AActual.Views.ContainsKey(LPair.Key),
      'Views: chave "' + LPair.Key + '" ausente apos o round-trip');
    LOther := AActual.Views[LPair.Key];
    Assert.AreEqual(LPair.Value.Name, LOther.Name, 'Views.Name');
    Assert.AreEqual(LPair.Value.Description, LOther.Description, 'Views.Description');
    Assert.AreEqual(LPair.Value.Script, LOther.Script, 'Views.Script');
    _AssertColumnDictEqual(LPair.Value.Fields, LOther.Fields, 'Views.Fields');
  end;
end;

procedure TTestMetadataSnapshot._AssertCatalogsEqual(AExpected, AActual: TCatalogMetadataMIK);
begin
  Assert.AreEqual(AExpected.Name, AActual.Name, 'Catalog.Name');
  Assert.AreEqual(AExpected.Schema, AActual.Schema, 'Catalog.Schema');
  Assert.AreEqual(AExpected.Description, AActual.Description, 'Catalog.Description');
  _AssertTablesEqual(AExpected, AActual);
  _AssertSequencesEqual(AExpected, AActual);
  _AssertViewsEqual(AExpected, AActual);
end;

function TTestMetadataSnapshot._DiffCommandCount(AMaster, ATarget: TCatalogMetadataMIK): Integer;
var
  LFactory: TDiffOnlyFactory;
  LCommand: TDDLCommand;
  LOperation: TDDLOperation;
begin
  // GenerateDDLCommands ALWAYS emits 4 unconditional "guard" commands
  // (EnableForeignKeys(False)/EnableTriggers(False) before the comparison,
  // EnableForeignKeys(True)/EnableTriggers(True) after it) regardless of
  // whether any actual schema difference was found - see the "GUARDA" note
  // in MetaDbDiff.Database.Factory.pas / MetaDbDiff.Compare.Options.pas
  // (ClassifyDDLCommand: ckGuard vs ckMutation). So "zero commands" for a
  // faithful round-trip means zero MUTATION commands, not a literally empty
  // GetCommandList.
  LFactory := TDiffOnlyFactory.Create(dnFirebird);
  try
    LFactory.Diff(AMaster, ATarget);
    Result := 0;
    for LCommand in LFactory.GetCommandList do
      if ClassifyDDLCommand(LCommand, LOperation) = ckMutation then
        Inc(Result);
  finally
    LFactory.Free;
  end;
end;

procedure TTestMetadataSnapshot.RoundTrip_FieldByField_IsFaithful;
var
  LOriginal, LLoaded: TCatalogMetadataMIK;
begin
  LOriginal := _BuildRichCatalog;
  try
    TMetadataSnapshot.SaveToFile(LOriginal, FSnapshotFile, dnFirebird, 'teste de round-trip');
    Assert.IsTrue(FileExists(FSnapshotFile), 'SaveToFile deveria ter criado o arquivo');

    LLoaded := TMetadataSnapshot.LoadFromFile(FSnapshotFile);
    try
      _AssertCatalogsEqual(LOriginal, LLoaded);
    finally
      LLoaded.Free;
    end;
  finally
    LOriginal.Free;
  end;
end;

procedure TTestMetadataSnapshot.RoundTrip_DiffAgainstOriginal_ProducesZeroCommands;
var
  LOriginal, LLoaded: TCatalogMetadataMIK;
begin
  LOriginal := _BuildRichCatalog;
  try
    TMetadataSnapshot.SaveToFile(LOriginal, FSnapshotFile, dnFirebird, 'teste de diff zero');
    LLoaded := TMetadataSnapshot.LoadFromFile(FSnapshotFile);
    try
      Assert.AreEqual(0, _DiffCommandCount(LOriginal, LLoaded),
        'Diff entre o catalogo original e o catalogo recarregado do snapshot ' +
        'deveria gerar ZERO comandos DDL');
    finally
      LLoaded.Free;
    end;
  finally
    LOriginal.Free;
  end;
end;

procedure TTestMetadataSnapshot.Snapshot_FutureFormatVersion_RaisesClearError;
var
  LCatalog: TCatalogMetadataMIK;
  LJson: TJSONObject;
  LText: String;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LCatalog.Name := 'X';
    LJson := TMetadataSnapshot.ToJson(LCatalog, dnFirebird, '');
    try
      // Simulates a snapshot produced by a FUTURE MetaDbDiff version whose
      // FormatVersion this build does not know how to read.
      LJson.RemovePair('FormatVersion').Free;
      LJson.AddPair('FormatVersion', MetadataSnapshotFormatVersion + 1);
      LText := LJson.ToJSON;
    finally
      LJson.Free;
    end;
  finally
    LCatalog.Free;
  end;
  TFile.WriteAllText(FSnapshotFile, LText, TEncoding.UTF8);

  Assert.WillRaise(
    procedure
    begin
      TMetadataSnapshot.LoadFromFile(FSnapshotFile).Free;
    end,
    EMetadataSnapshotError,
    'FormatVersion maior que o suportado deveria ser rejeitado com erro claro');

  // FormatVersion 0 (or negative) is not "an old but supported version" -
  // it is not a version this library ever wrote, so it must be rejected just
  // as clearly as a future one (tampered/hand-edited file - see
  // TMetadataSnapshot.LoadInto, MetaDbDiff.Metadata.Snapshot.pas).
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LCatalog.Name := 'X';
    LJson := TMetadataSnapshot.ToJson(LCatalog, dnFirebird, '');
    try
      LJson.RemovePair('FormatVersion').Free;
      LJson.AddPair('FormatVersion', 0);
      LText := LJson.ToJSON;
    finally
      LJson.Free;
    end;
  finally
    LCatalog.Free;
  end;
  TFile.WriteAllText(FSnapshotFile, LText, TEncoding.UTF8);

  Assert.WillRaise(
    procedure
    begin
      TMetadataSnapshot.LoadFromFile(FSnapshotFile).Free;
    end,
    EMetadataSnapshotError,
    'FormatVersion 0 deveria ser rejeitado com erro claro');
end;

procedure TTestMetadataSnapshot.Snapshot_CorruptedJson_RaisesClearError;
begin
  TFile.WriteAllText(FSnapshotFile, '{ this is not valid json ]]', TEncoding.UTF8);
  Assert.WillRaise(
    procedure
    begin
      TMetadataSnapshot.LoadFromFile(FSnapshotFile).Free;
    end,
    EMetadataSnapshotError,
    'JSON invalido deveria ser rejeitado com erro claro');
end;

procedure TTestMetadataSnapshot.Snapshot_EmptyFile_RaisesClearError;
begin
  TFile.WriteAllText(FSnapshotFile, '', TEncoding.UTF8);
  Assert.WillRaise(
    procedure
    begin
      TMetadataSnapshot.LoadFromFile(FSnapshotFile).Free;
    end,
    EMetadataSnapshotError,
    'Arquivo vazio deveria ser rejeitado com erro claro');
end;

procedure TTestMetadataSnapshot.Snapshot_MissingFile_RaisesClearError;
begin
  Assert.WillRaise(
    procedure
    begin
      TMetadataSnapshot.LoadFromFile(FSnapshotFile + '.does.not.exist').Free;
    end,
    EMetadataSnapshotError,
    'Arquivo inexistente deveria ser rejeitado com erro claro');
end;

procedure TTestMetadataSnapshot.Snapshot_EnumsAreSerializedByName;
var
  LCatalog: TCatalogMetadataMIK;
  LTable: TTableMIK;
  LColumn: TColumnMIK;
  LJson: TJSONObject;
  LText: String;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LTable := TTableMIK.Create(LCatalog);
    LTable.Name := 'T1';
    LCatalog.Tables.Add('T1', LTable);
    LColumn := TColumnMIK.Create(LTable);
    LColumn.Name := 'C1';
    LColumn.Position := 0;
    LColumn.FieldType := ftInteger;
    LColumn.TypeName := 'INTEGER';
    LColumn.SortingOrder := TSortingOrder.Ascending;
    LTable.Fields.Add('000000', LColumn);

    LJson := TMetadataSnapshot.ToJson(LCatalog, dnFirebird, '');
    try
      LText := LJson.ToJSON;
    finally
      LJson.Free;
    end;
  finally
    LCatalog.Free;
  end;

  // Enums must be serialized by NAME, not by ordinal - resilient to future
  // reorders/additions of TFieldType/TSortingOrder.
  Assert.IsTrue(Pos('"ftInteger"', LText) > 0,
    'FieldType deveria ser serializado pelo NOME ("ftInteger"): ' + LText);
  Assert.IsTrue(Pos('"Ascending"', LText) > 0,
    'SortingOrder deveria ser serializado pelo NOME ("Ascending"): ' + LText);
end;

procedure TTestMetadataSnapshot.Snapshot_DriverNameIsSerializedByName;
var
  LCatalog: TCatalogMetadataMIK;
  LJson: TJSONObject;
  LText: String;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LJson := TMetadataSnapshot.ToJson(LCatalog, dnFirebird, '');
    try
      LText := LJson.ToJSON;
    finally
      LJson.Free;
    end;
  finally
    LCatalog.Free;
  end;
  Assert.IsTrue(Pos('"DriverName":"Firebird"', LText) > 0,
    'DriverName deveria ser serializado pelo nome amigavel (TStrDriverName): ' + LText);
end;

procedure TTestMetadataSnapshot.SnapshotFactory_ExtractMetadata_PopulatesCallerCatalog;
var
  LOriginal, LCatalog: TCatalogMetadataMIK;
  LFactory: TMetadataSnapshotFactory;
begin
  LOriginal := _BuildRichCatalog;
  try
    TMetadataSnapshot.SaveToFile(LOriginal, FSnapshotFile, dnFirebird, '');
  finally
    LOriginal.Free;
  end;

  // TMetadataSnapshotFactory follows the same shape as TMetadataDBFactory/
  // TMetadataModelFactory: it populates a CALLER-OWNED, already instantiated
  // catalog in place (exactly what TDatabaseFactory.BuildDatabase does).
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LFactory := TMetadataSnapshotFactory.Create(nil, FSnapshotFile);
    try
      LFactory.ExtractMetadata(LCatalog);
    finally
      LFactory.Free;
    end;
    Assert.AreEqual(2, LCatalog.Tables.Count, 'CLIENTE e PEDIDO deveriam ter sido carregados');
    Assert.IsTrue(LCatalog.Tables.ContainsKey('CLIENTE'));
    Assert.IsTrue(LCatalog.Tables.ContainsKey('PEDIDO'));
    Assert.AreEqual(1, LCatalog.Sequences.Count);
    Assert.AreEqual(1, LCatalog.Views.Count);
  finally
    LCatalog.Free;
  end;
end;

procedure TTestMetadataSnapshot.ModelSnapshot_ExportThenLoad_DiffAgainstFreshModelExtractionIsZero;
var
  LFDConnection: TFDConnection;
  LConnection: IDBConnection;
  LFreshCatalog, LLoadedCatalog: TCatalogMetadataMIK;
  LModel: TModelMetadata;
begin
  // Unconnected "shell" FireDAC connection, same pattern already used by
  // Test.MetaDbDiff.Metadata.Model.pas: TModelMetadata only needs
  // Connection.GetDriver to resolve dialect-specific TypeNames, it never
  // opens the connection.
  LFDConnection := TFDConnection.Create(nil);
  try
    LConnection := TFactoryFireDAC.Create(LFDConnection, dnFirebird);

    // 1) Export the decorated model (Test.MetaDbDiff.Entities.pas: CLIENTE/
    //    PEDIDO) straight to a snapshot file.
    TMetadataExporter.ExportModel(LConnection, FSnapshotFile, 'model snapshot');

    // 2) Load it back.
    LLoadedCatalog := TMetadataSnapshot.LoadFromFile(FSnapshotFile);
    try
      // 3) Extract the SAME decorated model directly (no snapshot involved)
      //    for comparison.
      LFreshCatalog := TCatalogMetadataMIK.Create;
      try
        LModel := TModelMetadata.Create;
        try
          LModel.Connection := LConnection;
          LModel.CatalogMetadata := LFreshCatalog;
          // Must match TMetadataExporter.ExportModel's ModelForDatabase = True
          // (see MetaDbDiff.Metadata.Snapshot.Export.pas / TSnapshotModelOwner)
          // so both extractions apply the same generic-size zeroing rules in
          // GetFieldTypeDefinition - otherwise this would compare apples to
          // oranges and could show a spurious diff unrelated to the snapshot
          // round-trip itself.
          LModel.ModelForDatabase := True;
          LModel.GetModelMetadata;
        finally
          LModel.Free;
        end;

        Assert.AreEqual(0, _DiffCommandCount(LFreshCatalog, LLoadedCatalog),
          'Diff entre o modelo extraido direto e o modelo recarregado do ' +
          'snapshot deveria gerar ZERO comandos DDL');
      finally
        LFreshCatalog.Free;
      end;
    finally
      LLoadedCatalog.Free;
    end;
  finally
    LConnection := nil;
    LFDConnection.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMetadataSnapshot);

end.
