{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  DDL generator tests (pure string generation, no database connection).
  Builds MIK objects (MetaDbDiff.Database.Mapping.pas) by hand and asserts the
  SQL produced by the Firebird and MSSQL generators, normalizing whitespace.

  Out of scope on purpose (F5 is reworking them):
    GenerateEnableForeignKeys / GenerateEnableTriggers / Firebird GenerateCreateView.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.DDL.Generator;

interface

uses
  DB,
  SysUtils,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.Database.Mapping,
  // Os drivers se registram no initialization destas units:
  MetaDbDiff.DDL.Generator.Firebird,
  MetaDbDiff.DDL.Generator.MSSQL;

type
  [TestFixture]
  TTestDDLGenerator = class
  private
    FCatalog: TCatalogMetadataMIK;
    function Firebird: IDDLGeneratorCommand;
    function MSSQL: IDDLGeneratorCommand;
    /// <summary>Colapsa CR/LF e espacos repetidos num unico espaco e faz Trim.</summary>
    function NormalizeSQL(const ASQL: String): String;
    function AddColumn(ATable: TTableMIK; const AName, ATypeName: String;
      APosition: Integer; ANotNull: Boolean = False; ASize: Integer = 0;
      APrecision: Integer = 0; AScale: Integer = 0;
      const ADefaultValue: String = ''): TColumnMIK;
    /// <summary>CLIENTE: ID <inttype> NOT NULL, NOME VARCHAR(60), PK(ID).</summary>
    function BuildClienteTable(const AIntTypeName: String): TTableMIK;
    /// <summary>PEDIDO com PK composta e FK para CLIENTE.</summary>
    function BuildPedidoTable(ARuleDelete, ARuleUpdate: TRuleAction): TTableMIK;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    // ---------------------------------------------------------------- Registro
    [Test]
    procedure Register_ReturnsSingletonPerDriver;
    [Test]
    procedure Register_UnregisteredDriverRaises;
    // ---------------------------------------------------------------- Firebird
    [Test]
    procedure Firebird_CreateTable;
    [Test]
    procedure Firebird_CreateTable_WithCheckAndIndex;
    [Test]
    procedure Firebird_CreateColumn;
    [Test]
    procedure Firebird_CreateColumn_WithDefaultAndNotNull;
    [Test]
    procedure Firebird_CreatePrimaryKey_Simple;
    [Test]
    procedure Firebird_CreatePrimaryKey_Composite;
    [Test]
    procedure Firebird_CreateForeignKey_WithRules;
    [Test]
    procedure Firebird_CreateSequence_UsesGenerator;
    // ------------------------------------------------------------------- MSSQL
    [Test]
    procedure MSSQL_CreateTable;
    [Test]
    procedure MSSQL_CreateColumn;
    [Test]
    procedure MSSQL_CreatePrimaryKey_Composite;
    [Test]
    procedure MSSQL_CreateForeignKey_NoRules;
    [Test]
    procedure MSSQL_CreateSequence;
  end;

implementation

{ TTestDDLGenerator }

procedure TTestDDLGenerator.Setup;
begin
  // O catalogo e dono (doOwnsValues) das tabelas/sequences adicionadas.
  FCatalog := TCatalogMetadataMIK.Create;
  FCatalog.Name := '';
  FCatalog.Schema := '';
end;

procedure TTestDDLGenerator.TearDown;
begin
  FCatalog.Free;
end;

function TTestDDLGenerator.Firebird: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
end;

function TTestDDLGenerator.MSSQL: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnMSSQL);
end;

function TTestDDLGenerator.NormalizeSQL(const ASQL: String): String;
begin
  Result := StringReplace(ASQL, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

function TTestDDLGenerator.AddColumn(ATable: TTableMIK; const AName,
  ATypeName: String; APosition: Integer; ANotNull: Boolean; ASize: Integer;
  APrecision: Integer; AScale: Integer; const ADefaultValue: String): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Position := APosition;
  Result.NotNull := ANotNull;
  Result.Size := ASize;
  Result.Precision := APrecision;
  Result.Scale := AScale;
  Result.DefaultValue := ADefaultValue;
  ATable.Fields.Add(FormatFloat('000000', APosition), Result);
end;

function TTestDDLGenerator.BuildClienteTable(const AIntTypeName: String): TTableMIK;
var
  LPkColumn: TColumnMIK;
begin
  Result := TTableMIK.Create(FCatalog);
  Result.Name := 'CLIENTE';
  AddColumn(Result, 'ID', AIntTypeName, 0, True);
  AddColumn(Result, 'NOME', 'VARCHAR(%l)', 1, False, 60);
  Result.PrimaryKey.Name := 'PK_CLIENTE';
  LPkColumn := TColumnMIK.Create(Result);
  LPkColumn.Name := 'ID';
  Result.PrimaryKey.Fields.Add('000000', LPkColumn);
  FCatalog.Tables.Add(Result.Name, Result);
end;

function TTestDDLGenerator.BuildPedidoTable(ARuleDelete,
  ARuleUpdate: TRuleAction): TTableMIK;
var
  LColumn: TColumnMIK;
  LForeignKey: TForeignKeyMIK;
begin
  Result := TTableMIK.Create(FCatalog);
  Result.Name := 'PEDIDO';
  AddColumn(Result, 'ID_EMPRESA', 'INTEGER', 0, True);
  AddColumn(Result, 'ID_PEDIDO', 'INTEGER', 1, True);
  AddColumn(Result, 'ID_CLIENTE', 'INTEGER', 2);
  // PK composta
  Result.PrimaryKey.Name := 'PK_PEDIDO';
  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'ID_EMPRESA';
  Result.PrimaryKey.Fields.Add('000000', LColumn);
  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'ID_PEDIDO';
  Result.PrimaryKey.Fields.Add('000001', LColumn);
  // FK
  LForeignKey := TForeignKeyMIK.Create(Result);
  LForeignKey.Name := 'FK_PEDIDO_CLIENTE';
  LForeignKey.FromTable := 'CLIENTE';
  LForeignKey.OnDelete := ARuleDelete;
  LForeignKey.OnUpdate := ARuleUpdate;
  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'ID_CLIENTE';
  LForeignKey.FromFields.Add('000000', LColumn);
  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'ID';
  LForeignKey.ToFields.Add('000000', LColumn);
  Result.ForeignKeys.Add(LForeignKey.Name, LForeignKey);
  FCatalog.Tables.Add(Result.Name, Result);
end;

procedure TTestDDLGenerator.Register_ReturnsSingletonPerDriver;
var
  LFirst, LSecond: IDDLGeneratorCommand;
begin
  LFirst := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
  LSecond := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
  Assert.IsNotNull(LFirst);
  Assert.IsTrue(LFirst = LSecond, 'GetDriver deve devolver a mesma instancia');
end;

procedure TTestDDLGenerator.Register_UnregisteredDriverRaises;
begin
  // dnDB2 nao tem generator registrado neste projeto de teste.
  Assert.WillRaise(
    procedure
    begin
      TSQLDriverRegister.GetInstance.GetDriver(dnDB2);
    end,
    Exception);
end;

procedure TTestDDLGenerator.Firebird_CreateTable;
var
  LTable: TTableMIK;
begin
  LTable := BuildClienteTable('INTEGER');
  Assert.AreEqual(
    'CREATE TABLE CLIENTE ( ID INTEGER NOT NULL, NOME VARCHAR(60), ' +
    'CONSTRAINT PK_CLIENTE PRIMARY KEY (ID) );',
    NormalizeSQL(Firebird.GenerateCreateTable(LTable)));
end;

procedure TTestDDLGenerator.Firebird_CreateTable_WithCheckAndIndex;
var
  LTable: TTableMIK;
  LCheck: TCheckMIK;
  LIndexe: TIndexeKeyMIK;
  LColumn: TColumnMIK;
begin
  LTable := BuildClienteTable('INTEGER');
  LCheck := TCheckMIK.Create(LTable);
  LCheck.Name := 'CK_CLIENTE_NOME';
  LCheck.Condition := 'NOME <> ''''';
  LTable.Checks.Add(LCheck.Name, LCheck);
  LIndexe := TIndexeKeyMIK.Create(LTable);
  LIndexe.Name := 'IDX_CLIENTE_NOME';
  LIndexe.Unique := False;
  LColumn := TColumnMIK.Create(LTable);
  LColumn.Name := 'NOME';
  LIndexe.Fields.Add('000000', LColumn);
  LTable.IndexeKeys.Add(LIndexe.Name, LIndexe);

  Assert.AreEqual(
    'CREATE TABLE CLIENTE ( ID INTEGER NOT NULL, NOME VARCHAR(60), ' +
    'CONSTRAINT PK_CLIENTE PRIMARY KEY (ID), ' +
    'CONSTRAINT CK_CLIENTE_NOME CHECK (NOME <> '''') ); ' +
    'CREATE INDEX IDX_CLIENTE_NOME ON CLIENTE (NOME);',
    NormalizeSQL(Firebird.GenerateCreateTable(LTable)));
end;

procedure TTestDDLGenerator.Firebird_CreateColumn;
var
  LTable: TTableMIK;
begin
  LTable := BuildClienteTable('INTEGER');
  Assert.AreEqual(
    'ALTER TABLE CLIENTE ADD NOME VARCHAR(60);',
    NormalizeSQL(Firebird.GenerateCreateColumn(LTable.Fields['000001'])));
end;

procedure TTestDDLGenerator.Firebird_CreateColumn_WithDefaultAndNotNull;
var
  LTable: TTableMIK;
  LColumn: TColumnMIK;
begin
  LTable := BuildClienteTable('INTEGER');
  LColumn := AddColumn(LTable, 'SALDO', 'NUMERIC(%p,%s)', 2, True, 0, 18, 2, '0');
  Assert.AreEqual(
    'ALTER TABLE CLIENTE ADD SALDO NUMERIC(18,2) DEFAULT 0 NOT NULL;',
    NormalizeSQL(Firebird.GenerateCreateColumn(LColumn)));
end;

procedure TTestDDLGenerator.Firebird_CreatePrimaryKey_Simple;
var
  LTable: TTableMIK;
begin
  LTable := BuildClienteTable('INTEGER');
  // Fragmento usado dentro do CREATE TABLE (sem ponto e virgula final).
  Assert.AreEqual(
    'CONSTRAINT PK_CLIENTE PRIMARY KEY (ID)',
    NormalizeSQL(Firebird.GenerateCreatePrimaryKey(LTable.PrimaryKey)));
end;

procedure TTestDDLGenerator.Firebird_CreatePrimaryKey_Composite;
var
  LTable: TTableMIK;
begin
  LTable := BuildPedidoTable(TRuleAction.None, TRuleAction.None);
  Assert.AreEqual(
    'CONSTRAINT PK_PEDIDO PRIMARY KEY (ID_EMPRESA, ID_PEDIDO)',
    NormalizeSQL(Firebird.GenerateCreatePrimaryKey(LTable.PrimaryKey)));
end;

procedure TTestDDLGenerator.Firebird_CreateForeignKey_WithRules;
var
  LTable: TTableMIK;
  LForeignKey: TForeignKeyMIK;
begin
  LTable := BuildPedidoTable(TRuleAction.Cascade, TRuleAction.SetNull);
  LForeignKey := LTable.ForeignKeys['FK_PEDIDO_CLIENTE'];
  Assert.AreEqual(
    'ALTER TABLE PEDIDO ADD CONSTRAINT FK_PEDIDO_CLIENTE FOREIGN KEY (ID_CLIENTE) ' +
    'REFERENCES CLIENTE(ID) ON DELETE CASCADE ON UPDATE SET NULL;',
    NormalizeSQL(Firebird.GenerateCreateForeignKey(LForeignKey)));
end;

procedure TTestDDLGenerator.Firebird_CreateSequence_UsesGenerator;
var
  LSequence: TSequenceMIK;
begin
  LSequence := TSequenceMIK.Create(FCatalog);
  LSequence.Name := 'SEQ_CLIENTE';
  LSequence.InitialValue := 1;
  LSequence.Increment := 1;
  FCatalog.Sequences.Add(LSequence.Name, LSequence);
  Assert.AreEqual('CREATE GENERATOR SEQ_CLIENTE;',
    NormalizeSQL(Firebird.GenerateCreateSequence(LSequence)));
end;

procedure TTestDDLGenerator.MSSQL_CreateTable;
var
  LTable: TTableMIK;
begin
  LTable := BuildClienteTable('INT');
  Assert.AreEqual(
    'CREATE TABLE CLIENTE ( ID INT NOT NULL, NOME VARCHAR(60), ' +
    'CONSTRAINT PK_CLIENTE PRIMARY KEY (ID) );',
    NormalizeSQL(MSSQL.GenerateCreateTable(LTable)));
end;

procedure TTestDDLGenerator.MSSQL_CreateColumn;
var
  LTable: TTableMIK;
begin
  LTable := BuildClienteTable('INT');
  Assert.AreEqual(
    'ALTER TABLE CLIENTE ADD ID INT NOT NULL;',
    NormalizeSQL(MSSQL.GenerateCreateColumn(LTable.Fields['000000'])));
end;

procedure TTestDDLGenerator.MSSQL_CreatePrimaryKey_Composite;
var
  LTable: TTableMIK;
begin
  LTable := BuildPedidoTable(TRuleAction.None, TRuleAction.None);
  Assert.AreEqual(
    'CONSTRAINT PK_PEDIDO PRIMARY KEY (ID_EMPRESA, ID_PEDIDO)',
    NormalizeSQL(MSSQL.GenerateCreatePrimaryKey(LTable.PrimaryKey)));
end;

procedure TTestDDLGenerator.MSSQL_CreateForeignKey_NoRules;
var
  LTable: TTableMIK;
begin
  LTable := BuildPedidoTable(TRuleAction.None, TRuleAction.None);
  // Implementacao base (TDDLSQLGenerator) - com regras None o SQL termina
  // logo apos a lista de colunas referenciadas.
  Assert.AreEqual(
    'ALTER TABLE PEDIDO ADD CONSTRAINT FK_PEDIDO_CLIENTE FOREIGN KEY (ID_CLIENTE) ' +
    'REFERENCES CLIENTE(ID);',
    NormalizeSQL(MSSQL.GenerateCreateForeignKey(LTable.ForeignKeys['FK_PEDIDO_CLIENTE'])));
end;

procedure TTestDDLGenerator.MSSQL_CreateSequence;
var
  LSequence: TSequenceMIK;
begin
  LSequence := TSequenceMIK.Create(FCatalog);
  LSequence.Name := 'SEQ_PEDIDO';
  LSequence.InitialValue := 10;
  LSequence.Increment := 5;
  FCatalog.Sequences.Add(LSequence.Name, LSequence);
  Assert.AreEqual('CREATE SEQUENCE SEQ_PEDIDO AS int START WITH 10 INCREMENT BY 5;',
    NormalizeSQL(MSSQL.GenerateCreateSequence(LSequence)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDDLGenerator);

end.
