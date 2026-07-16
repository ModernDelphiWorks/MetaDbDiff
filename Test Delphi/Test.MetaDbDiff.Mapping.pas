{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Mapping/RTTI tests: asserts that TMappingExplorer reads back exactly what was
  decorated on the test entities (Test.MetaDbDiff.Entities.pas).

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Mapping;

interface

uses
  DB,
  SysUtils,
  DUnitX.TestFramework,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Mapping.Classes,
  MetaDbDiff.Mapping.Explorer,
  MetaDbDiff.Mapping.Register,
  Test.MetaDbDiff.Entities;

type
  [TestFixture]
  TTestMapping = class
  private
    function FindColumn(AList: TColumnMappingList;
      const AName: String): TColumnMapping;
  public
    // ------------------------------------------------------------------ Table
    [Test]
    procedure Table_NameAndDescription;
    [Test]
    procedure Table_IsCachedPerClassName;
    // ---------------------------------------------------------------- Columns
    [Test]
    procedure Columns_AllMappedInDeclarationOrder;
    [Test]
    procedure Column_OverloadNameType;
    [Test]
    procedure Column_OverloadWithSize;
    [Test]
    procedure Column_OverloadWithPrecisionScale;
    [Test]
    procedure Column_Restrictions_NotNull;
    [Test]
    procedure Column_Dictionary_DefaultExpression;
    [Test]
    procedure Column_IsPrimaryKeyFlag;
    // ------------------------------------------------------------- PrimaryKey
    [Test]
    procedure PrimaryKey_Simple_AutoIncSequence;
    [Test]
    procedure PrimaryKey_Composite;
    // ------------------------------------------------------------- ForeignKey
    [Test]
    procedure ForeignKey_AllDecoratedValues;
    // ----------------------------------------------------------------- Indexe
    [Test]
    procedure Indexe_Simple;
    [Test]
    procedure Indexe_UniqueComposite;
    // ------------------------------------------------------------------ Check
    [Test]
    procedure Check_NameAndCondition;
    // --------------------------------------------------------------- Sequence
    [Test]
    procedure Sequence_NameAndTable;
    // --------------------------------------------------------------- Register
    [Test]
    procedure Register_GetAllIsOneShot;
    [Test]
    procedure Register_GetAllReturnsSameContentOnConsecutiveReads;
  end;

implementation

{ TTestMapping }

function TTestMapping.FindColumn(AList: TColumnMappingList;
  const AName: String): TColumnMapping;
var
  LColumn: TColumnMapping;
begin
  Result := nil;
  for LColumn in AList do
    if SameText(LColumn.ColumnName, AName) then
      Exit(LColumn);
end;

procedure TTestMapping.Table_NameAndDescription;
var
  LTable: TTableMapping;
begin
  LTable := TMappingExplorer.GetMappingTable(TClienteTest);
  Assert.IsNotNull(LTable);
  Assert.AreEqual('CLIENTE', LTable.Name);
  Assert.AreEqual('Tabela de clientes', LTable.Description);
  Assert.AreEqual('', LTable.Schema);
end;

procedure TTestMapping.Table_IsCachedPerClassName;
var
  LFirst, LSecond: TTableMapping;
begin
  // TMappingExplorer caches per ClassName: two calls return the SAME instance.
  LFirst := TMappingExplorer.GetMappingTable(TClienteTest);
  LSecond := TMappingExplorer.GetMappingTable(TClienteTest);
  Assert.AreSame(LFirst, LSecond);
end;

procedure TTestMapping.Columns_AllMappedInDeclarationOrder;
var
  LColumns: TColumnMappingList;
begin
  LColumns := TMappingExplorer.GetMappingColumn(TClienteTest);
  Assert.IsNotNull(LColumns);
  Assert.AreEqual(5, LColumns.Count);
  Assert.AreEqual('ID', LColumns[0].ColumnName);
  Assert.AreEqual('NOME', LColumns[1].ColumnName);
  Assert.AreEqual('IDADE', LColumns[2].ColumnName);
  Assert.AreEqual('SALDO', LColumns[3].ColumnName);
  Assert.AreEqual('CRIADO_EM', LColumns[4].ColumnName);
  Assert.AreEqual(0, LColumns[0].FieldIndex);
  Assert.AreEqual(4, LColumns[4].FieldIndex);
end;

procedure TTestMapping.Column_OverloadNameType;
var
  LColumn: TColumnMapping;
begin
  LColumn := FindColumn(TMappingExplorer.GetMappingColumn(TClienteTest), 'ID');
  Assert.IsNotNull(LColumn);
  Assert.IsTrue(LColumn.FieldType = ftInteger, 'FieldType de ID deveria ser ftInteger');
  Assert.AreEqual(0, LColumn.Size);
  Assert.AreEqual(0, LColumn.Precision);
  Assert.AreEqual(0, LColumn.Scale);
end;

procedure TTestMapping.Column_OverloadWithSize;
var
  LColumn: TColumnMapping;
begin
  LColumn := FindColumn(TMappingExplorer.GetMappingColumn(TClienteTest), 'NOME');
  Assert.IsNotNull(LColumn);
  Assert.IsTrue(LColumn.FieldType = ftString, 'FieldType de NOME deveria ser ftString');
  Assert.AreEqual(60, LColumn.Size);
end;

procedure TTestMapping.Column_OverloadWithPrecisionScale;
var
  LColumn: TColumnMapping;
begin
  LColumn := FindColumn(TMappingExplorer.GetMappingColumn(TClienteTest), 'SALDO');
  Assert.IsNotNull(LColumn);
  Assert.IsTrue(LColumn.FieldType = ftBCD, 'FieldType de SALDO deveria ser ftBCD');
  Assert.AreEqual(18, LColumn.Precision);
  Assert.AreEqual(2, LColumn.Scale);
  // -- documenta comportamento atual, bug conhecido:
  // Column.Create(name, type, precision, scale) faz "FSize := AScale"
  // (MetaDbDiff.Mapping.Attributes.pas, construtor de 4 argumentos), logo
  // Size retorna o SCALE (2) e nao 0/precision como seria esperado.
  Assert.AreEqual(2, LColumn.Size);
end;

procedure TTestMapping.Column_Restrictions_NotNull;
var
  LColumns: TColumnMappingList;
begin
  LColumns := TMappingExplorer.GetMappingColumn(TClienteTest);
  Assert.IsTrue(FindColumn(LColumns, 'ID').IsNotNull, 'ID deveria ser NotNull');
  Assert.IsTrue(FindColumn(LColumns, 'NOME').IsNotNull, 'NOME deveria ser NotNull');
  Assert.IsFalse(FindColumn(LColumns, 'IDADE').IsNotNull, 'IDADE nao tem [Restrictions]');
end;

procedure TTestMapping.Column_Dictionary_DefaultExpression;
var
  LColumn: TColumnMapping;
begin
  LColumn := FindColumn(TMappingExplorer.GetMappingColumn(TClienteTest), 'NOME');
  Assert.IsNotNull(LColumn.ColumnDictionary);
  Assert.AreEqual('Nome', LColumn.ColumnDictionary.DisplayLabel);
  Assert.AreEqual('Nome invalido', LColumn.ColumnDictionary.ConstraintErrorMessage);
  Assert.AreEqual('SEM NOME', String(LColumn.ColumnDictionary.DefaultExpression));
  // O popular copia o DefaultExpression do Dictionary para DefaultValue
  Assert.AreEqual('SEM NOME', LColumn.DefaultValue);
  // Coluna sem [Dictionary] com default -> DefaultValue vazio
  Assert.AreEqual('', FindColumn(TMappingExplorer.GetMappingColumn(TClienteTest),
    'IDADE').DefaultValue);
end;

procedure TTestMapping.Column_IsPrimaryKeyFlag;
var
  LColumns: TColumnMappingList;
begin
  LColumns := TMappingExplorer.GetMappingColumn(TClienteTest);
  Assert.IsTrue(FindColumn(LColumns, 'ID').IsPrimaryKey);
  Assert.IsFalse(FindColumn(LColumns, 'NOME').IsPrimaryKey);

  LColumns := TMappingExplorer.GetMappingColumn(TPedidoTest);
  Assert.IsTrue(FindColumn(LColumns, 'ID_EMPRESA').IsPrimaryKey);
  Assert.IsTrue(FindColumn(LColumns, 'ID_PEDIDO').IsPrimaryKey);
  Assert.IsFalse(FindColumn(LColumns, 'ID_CLIENTE').IsPrimaryKey);
end;

procedure TTestMapping.PrimaryKey_Simple_AutoIncSequence;
var
  LPk: TPrimaryKeyMapping;
begin
  LPk := TMappingExplorer.GetMappingPrimaryKey(TClienteTest);
  Assert.IsNotNull(LPk);
  Assert.AreEqual(1, LPk.Columns.Count);
  Assert.AreEqual('ID', LPk.Columns[0]);
  Assert.IsTrue(LPk.AutoIncrement);
  Assert.IsTrue(LPk.GeneratorType = TGeneratorType.SequenceInc);
  Assert.IsFalse(LPk.Unique);
  Assert.AreEqual('Chave primaria do cliente', LPk.Description);
  // O nome do PK no nivel de mapeamento e sempre o prefixo fixo 'PK_'
  // (TPrimaryKeyMapping.Create); o nome final PK_<TABELA> so e montado
  // na extracao do modelo (TModelMetadata.GetPrimaryKey).
  Assert.AreEqual('PK_', LPk.Name);
end;

procedure TTestMapping.PrimaryKey_Composite;
var
  LPk: TPrimaryKeyMapping;
begin
  LPk := TMappingExplorer.GetMappingPrimaryKey(TPedidoTest);
  Assert.IsNotNull(LPk);
  Assert.AreEqual(2, LPk.Columns.Count);
  Assert.AreEqual('ID_EMPRESA', LPk.Columns[0]);
  Assert.AreEqual('ID_PEDIDO', LPk.Columns[1]);
  Assert.IsFalse(LPk.AutoIncrement);
  // O overload PrimaryKey.Create(AColumns, ADescription) delega com
  // TGeneratorType.SequenceInc fixo (MetaDbDiff.Mapping.Attributes.pas).
  Assert.IsTrue(LPk.GeneratorType = TGeneratorType.SequenceInc);
  Assert.AreEqual('Chave composta do pedido', LPk.Description);
end;

procedure TTestMapping.ForeignKey_AllDecoratedValues;
var
  LFks: TForeignKeyMappingList;
begin
  LFks := TMappingExplorer.GetMappingForeignKey(TPedidoTest);
  Assert.IsNotNull(LFks);
  Assert.AreEqual(1, LFks.Count);
  Assert.AreEqual('FK_PEDIDO_CLIENTE', LFks[0].Name);
  Assert.AreEqual('CLIENTE', LFks[0].TableNameRef);
  Assert.AreEqual(1, LFks[0].FromColumns.Count);
  Assert.AreEqual('ID_CLIENTE', LFks[0].FromColumns[0]);
  Assert.AreEqual(1, LFks[0].ToColumns.Count);
  Assert.AreEqual('ID', LFks[0].ToColumns[0]);
  Assert.IsTrue(LFks[0].RuleDelete = TRuleAction.Cascade);
  Assert.IsTrue(LFks[0].RuleUpdate = TRuleAction.SetNull);
  Assert.AreEqual('FK para cliente', LFks[0].Description);
  // Entidade sem [ForeignKey] retorna nil (nao lista vazia)
  Assert.IsNull(TMappingExplorer.GetMappingForeignKey(TClienteTest));
end;

procedure TTestMapping.Indexe_Simple;
var
  LIndexes: TIndexeMappingList;
begin
  LIndexes := TMappingExplorer.GetMappingIndexe(TClienteTest);
  Assert.IsNotNull(LIndexes);
  Assert.AreEqual(1, LIndexes.Count);
  Assert.AreEqual('IDX_CLIENTE_NOME', LIndexes[0].Name);
  Assert.AreEqual(1, LIndexes[0].Columns.Count);
  Assert.AreEqual('NOME', LIndexes[0].Columns[0]);
  Assert.IsFalse(LIndexes[0].Unique);
  Assert.AreEqual('Indice por nome', LIndexes[0].Description);
end;

procedure TTestMapping.Indexe_UniqueComposite;
var
  LIndexes: TIndexeMappingList;
begin
  LIndexes := TMappingExplorer.GetMappingIndexe(TPedidoTest);
  Assert.IsNotNull(LIndexes);
  Assert.AreEqual(1, LIndexes.Count);
  Assert.AreEqual('IDX_PEDIDO_UNQ', LIndexes[0].Name);
  Assert.AreEqual(2, LIndexes[0].Columns.Count);
  Assert.AreEqual('ID_EMPRESA', LIndexes[0].Columns[0]);
  Assert.AreEqual('ID_PEDIDO', LIndexes[0].Columns[1]);
  Assert.IsTrue(LIndexes[0].Unique);
end;

procedure TTestMapping.Check_NameAndCondition;
var
  LChecks: TCheckMappingList;
begin
  LChecks := TMappingExplorer.GetMappingCheck(TClienteTest);
  Assert.IsNotNull(LChecks);
  Assert.AreEqual(1, LChecks.Count);
  Assert.AreEqual('CK_CLIENTE_IDADE', LChecks[0].Name);
  Assert.AreEqual('IDADE >= 0', LChecks[0].Condition);
  Assert.AreEqual('Idade nao pode ser negativa', LChecks[0].Description);
  Assert.IsNull(TMappingExplorer.GetMappingCheck(TPedidoTest));
end;

procedure TTestMapping.Sequence_NameAndTable;
var
  LSequence: TSequenceMapping;
begin
  LSequence := TMappingExplorer.GetMappingSequence(TClienteTest);
  Assert.IsNotNull(LSequence);
  Assert.AreEqual('SEQ_CLIENTE', LSequence.Name);
  Assert.AreEqual('CLIENTE', LSequence.TableName);
  Assert.AreEqual(0, LSequence.Initial);
  Assert.AreEqual(1, LSequence.Increment);
end;

procedure TTestMapping.Register_GetAllIsOneShot;
begin
  // Documents the CURRENT (fixed) behaviour of TRegisterClass: GetAll*Class
  // returns a snapshot copy of the internal list WITHOUT clearing it, so
  // repeated calls keep returning the same content. This used to be one-shot
  // (the list was cleared on the first read - see MetaDbDiff.Mapping.Register.pas
  // history), which meant a second TMappingRepository/comparison in the same
  // process silently got an empty catalog. We use the TRIGGERS list (not
  // consumed by GetRepositoryMapping) so we don't interfere with the entity
  // list used by the model extraction test.
  TRegisterClass.RegisterTrigger(TClienteTest);
  Assert.AreEqual(1, Length(TRegisterClass.GetAllTriggerClass));
  Assert.AreEqual(1, Length(TRegisterClass.GetAllTriggerClass),
    'GetAllTriggerClass must NOT empty the list anymore - a second read must keep returning the registered class');
end;

procedure TTestMapping.Register_GetAllReturnsSameContentOnConsecutiveReads;
var
  LFirst, LSecond: TArray<TClass>;
begin
  // Two consecutive reads must return the same content (not just the same
  // length): this is the actual behaviour a second TMappingRepository /
  // second comparison in the same process relies on.
  TRegisterClass.RegisterTrigger(TPedidoTest);
  LFirst := TRegisterClass.GetAllTriggerClass;
  LSecond := TRegisterClass.GetAllTriggerClass;
  Assert.AreEqual(Length(LFirst), Length(LSecond));
  Assert.IsTrue(Length(LFirst) > 0);
  Assert.IsTrue(LFirst[High(LFirst)] = LSecond[High(LSecond)],
    'Consecutive reads must return the same class reference for the last registered trigger');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMapping);

end.
