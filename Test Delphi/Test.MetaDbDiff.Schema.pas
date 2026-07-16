{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Schema-aware compare tests (FRENTE 14). Pure string tests - no database
  connection. Covers:
    - default Schema='' keeps the extraction SQL and generated DDL IDENTICAL to
      the historical behavior (no schema filter, no qualification);
    - a configured Schema ('vendas') makes the PostgreSQL/MSSQL GetSelect*
      include the schema filter (asserted on the SQL text) and makes the
      PostgreSQL/MSSQL generators qualify the table name per dialect
      ("vendas"."CLIENTE" / [vendas].[CLIENTE]);
    - snapshot JSON round-trip preserves Catalog.Schema;
    - the schema identifier validator rejects malicious input ('x; DROP').

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Schema;

interface

uses
  DB,
  SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Metadata.Extract,
  MetaDbDiff.Metadata.Snapshot,
  MetaDbDiff.Metadata.PostgreSQL,
  MetaDbDiff.Metadata.MSSQL,
  // Os generators se registram no initialization destas units:
  MetaDbDiff.DDL.Generator.PostgreSQL,
  MetaDbDiff.DDL.Generator.MSSQL;

type
  /// <summary>Expoe os GetSelect* + CatalogSchema protegidos do extractor PostgreSQL.</summary>
  TPGSchemaProbe = class(TCatalogMetadataPostgreSQL)
  public
    function SelTables: String;
    function SelColumns(const ATable: String): String;
    function SelPrimaryKey(const ATable: String): String;
    function SelForeignKey(const ATable: String): String;
    function SelSequences: String;
    function SelViews: String;
    function SelChecks(const ATable: String): String;
    function SelIndexe(const ATable: String): String;
    function CatSchema: String;
  end;

  /// <summary>Expoe os GetSelect* + CatalogSchema protegidos do extractor MSSQL.</summary>
  TMSSQLSchemaProbe = class(TCatalogMetadataMSSQL)
  public
    function SelTables: String;
    function SelColumns(const ATable: String): String;
    function SelPrimaryKey(const ATable: String): String;
    function SelForeignKey(const ATable: String): String;
    function SelSequences: String;
    function SelViews: String;
    function SelIndexe(const ATable: String): String;
    function CatSchema: String;
  end;

  [TestFixture]
  TTestSchemaAware = class
  private
    FCatalog: TCatalogMetadataMIK;
    function _PG: IDDLGeneratorCommand;
    function _MSSQL: IDDLGeneratorCommand;
    function _NormalizeSQL(const ASQL: String): String;
    /// <summary>CLIENTE (ID INT NOT NULL, NOME VARCHAR(60), PK(ID)) no FCatalog.</summary>
    function _BuildClienteTable(const AIntTypeName: String): TTableMIK;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    // -------------------------------------------- Validacao do identificador
    [Test]
    procedure Validate_EmptyIsValid;
    [Test]
    procedure Validate_SimpleNameIsValid;
    [Test]
    procedure Validate_RejectsSqlInjection;
    [Test]
    procedure Validate_RejectsQuote;
    [Test]
    procedure Validate_RejectsLeadingDigit;
    [Test]
    procedure Validate_RejectsDot;
    // -------------------------------------------- Extracao PostgreSQL - default
    [Test]
    procedure PG_DefaultSchema_NoFilter;
    [Test]
    procedure PG_DefaultCatalogSchema_IsPublic;
    // -------------------------------------------- Extracao PostgreSQL - schema
    [Test]
    procedure PG_ConfiguredSchema_FiltersEverySelect;
    [Test]
    procedure PG_ConfiguredCatalogSchema_IsConfigured;
    // -------------------------------------------- Extracao MSSQL - default
    [Test]
    procedure MSSQL_DefaultSchema_NoFilter;
    [Test]
    procedure MSSQL_DefaultCatalogSchema_IsEmpty;
    // -------------------------------------------- Extracao MSSQL - schema
    [Test]
    procedure MSSQL_ConfiguredSchema_FiltersEverySelect;
    // -------------------------------------------- DDL - default por dialeto
    [Test]
    procedure PG_DDL_DefaultSchema_PublicQualified;
    [Test]
    procedure MSSQL_DDL_DefaultSchema_Unqualified;
    // -------------------------------------------- DDL - qualificado por dialeto
    [Test]
    procedure PG_DDL_Qualified_CreateTable;
    [Test]
    procedure PG_DDL_Qualified_AlterColumn;
    [Test]
    procedure PG_DDL_Qualified_CreateColumn;
    [Test]
    procedure MSSQL_DDL_Qualified_CreateTable;
    [Test]
    procedure MSSQL_DDL_Qualified_DropTable;
    [Test]
    procedure MSSQL_DDL_Qualified_RenameColumn;
    // -------------------------------------------- Snapshot round-trip
    [Test]
    procedure Snapshot_RoundTrip_PreservesSchema;
  end;

implementation

{ TPGSchemaProbe }

function TPGSchemaProbe.SelTables: String;
begin
  Result := GetSelectTables;
end;

function TPGSchemaProbe.SelColumns(const ATable: String): String;
begin
  Result := GetSelectTableColumns(ATable);
end;

function TPGSchemaProbe.SelPrimaryKey(const ATable: String): String;
begin
  Result := GetSelectPrimaryKey(ATable);
end;

function TPGSchemaProbe.SelForeignKey(const ATable: String): String;
begin
  Result := GetSelectForeignKey(ATable);
end;

function TPGSchemaProbe.SelSequences: String;
begin
  Result := GetSelectSequences;
end;

function TPGSchemaProbe.SelViews: String;
begin
  Result := GetSelectViews;
end;

function TPGSchemaProbe.SelChecks(const ATable: String): String;
begin
  Result := GetSelectChecks(ATable);
end;

function TPGSchemaProbe.SelIndexe(const ATable: String): String;
begin
  Result := GetSelectIndexe(ATable);
end;

function TPGSchemaProbe.CatSchema: String;
begin
  Result := CatalogSchema;
end;

{ TMSSQLSchemaProbe }

function TMSSQLSchemaProbe.SelTables: String;
begin
  Result := GetSelectTables;
end;

function TMSSQLSchemaProbe.SelColumns(const ATable: String): String;
begin
  Result := GetSelectTableColumns(ATable);
end;

function TMSSQLSchemaProbe.SelPrimaryKey(const ATable: String): String;
begin
  Result := GetSelectPrimaryKey(ATable);
end;

function TMSSQLSchemaProbe.SelForeignKey(const ATable: String): String;
begin
  Result := GetSelectForeignKey(ATable);
end;

function TMSSQLSchemaProbe.SelSequences: String;
begin
  Result := GetSelectSequences;
end;

function TMSSQLSchemaProbe.SelViews: String;
begin
  Result := GetSelectViews;
end;

function TMSSQLSchemaProbe.SelIndexe(const ATable: String): String;
begin
  Result := GetSelectIndexe(ATable);
end;

function TMSSQLSchemaProbe.CatSchema: String;
begin
  Result := CatalogSchema;
end;

{ TTestSchemaAware }

procedure TTestSchemaAware.Setup;
begin
  FCatalog := TCatalogMetadataMIK.Create;
  FCatalog.Name := '';
  FCatalog.Schema := '';
end;

procedure TTestSchemaAware.TearDown;
begin
  FCatalog.Free;
end;

function TTestSchemaAware._PG: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnPostgreSQL);
end;

function TTestSchemaAware._MSSQL: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnMSSQL);
end;

function TTestSchemaAware._NormalizeSQL(const ASQL: String): String;
begin
  Result := StringReplace(ASQL, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

function TTestSchemaAware._BuildClienteTable(const AIntTypeName: String): TTableMIK;
var
  LColumn: TColumnMIK;
  LPkColumn: TColumnMIK;
begin
  Result := TTableMIK.Create(FCatalog);
  Result.Name := 'CLIENTE';

  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'ID';
  LColumn.TypeName := AIntTypeName;
  LColumn.Position := 0;
  LColumn.NotNull := True;
  Result.Fields.Add(FormatFloat('000000', 0), LColumn);

  LColumn := TColumnMIK.Create(Result);
  LColumn.Name := 'NOME';
  LColumn.TypeName := 'VARCHAR(%l)';
  LColumn.Position := 1;
  LColumn.Size := 60;
  Result.Fields.Add(FormatFloat('000000', 1), LColumn);

  Result.PrimaryKey.Name := 'PK_CLIENTE';
  LPkColumn := TColumnMIK.Create(Result);
  LPkColumn.Name := 'ID';
  Result.PrimaryKey.Fields.Add('000000', LPkColumn);

  FCatalog.Tables.Add(Result.Name, Result);
end;

// ------------------------------------------------------ Validacao identificador

procedure TTestSchemaAware.Validate_EmptyIsValid;
begin
  Assert.AreEqual('', TCatalogMetadataAbstract.ValidateSchemaName(''));
end;

procedure TTestSchemaAware.Validate_SimpleNameIsValid;
begin
  Assert.AreEqual('vendas', TCatalogMetadataAbstract.ValidateSchemaName('vendas'));
  Assert.AreEqual('_stg2', TCatalogMetadataAbstract.ValidateSchemaName('_stg2'));
end;

procedure TTestSchemaAware.Validate_RejectsSqlInjection;
begin
  Assert.WillRaise(
    procedure
    begin
      TCatalogMetadataAbstract.ValidateSchemaName('x; DROP');
    end,
    EMetaDbDiffSchema);
end;

procedure TTestSchemaAware.Validate_RejectsQuote;
begin
  Assert.WillRaise(
    procedure
    begin
      TCatalogMetadataAbstract.ValidateSchemaName('ven"das');
    end,
    EMetaDbDiffSchema);
end;

procedure TTestSchemaAware.Validate_RejectsLeadingDigit;
begin
  Assert.WillRaise(
    procedure
    begin
      TCatalogMetadataAbstract.ValidateSchemaName('1schema');
    end,
    EMetaDbDiffSchema);
end;

procedure TTestSchemaAware.Validate_RejectsDot;
begin
  // Um ponto permitiria "schema.tabela" arbitrario - rejeitado.
  Assert.WillRaise(
    procedure
    begin
      TCatalogMetadataAbstract.ValidateSchemaName('ven.das');
    end,
    EMetaDbDiffSchema);
end;

// ----------------------------------------------------- Extracao PostgreSQL

procedure TTestSchemaAware.PG_DefaultSchema_NoFilter;
var
  LProbe: TPGSchemaProbe;
begin
  LProbe := TPGSchemaProbe.Create;
  try
    LProbe.Schema := '';
    // Comportamento historico preservado: mantem o "not in (...)" e NAO
    // acrescenta o filtro de igualdade de schema.
    Assert.Contains(LProbe.SelTables, 'not in (''pg_catalog''');
    Assert.IsFalse(LProbe.SelTables.Contains('table_schema = '),
      'Default nao deve acrescentar filtro de igualdade de schema');
    Assert.IsFalse(LProbe.SelColumns('CLIENTE').Contains('table_schema = '));
    Assert.IsFalse(LProbe.SelSequences.Contains('schemaname = '));
  finally
    LProbe.Free;
  end;
end;

procedure TTestSchemaAware.PG_DefaultCatalogSchema_IsPublic;
var
  LProbe: TPGSchemaProbe;
begin
  // Comportamento historico restaurado: sem schema configurado, o catalogo
  // PostgreSQL e carimbado com 'public' (DDL sai public-qualificado como sempre).
  LProbe := TPGSchemaProbe.Create;
  try
    LProbe.Schema := '';
    Assert.AreEqual('public', LProbe.CatSchema);
  finally
    LProbe.Free;
  end;
end;

procedure TTestSchemaAware.PG_ConfiguredCatalogSchema_IsConfigured;
var
  LProbe: TPGSchemaProbe;
begin
  LProbe := TPGSchemaProbe.Create;
  try
    LProbe.Schema := 'vendas';
    Assert.AreEqual('vendas', LProbe.CatSchema);
  finally
    LProbe.Free;
  end;
end;

procedure TTestSchemaAware.PG_ConfiguredSchema_FiltersEverySelect;
var
  LProbe: TPGSchemaProbe;
begin
  LProbe := TPGSchemaProbe.Create;
  try
    LProbe.Schema := 'vendas';
    Assert.Contains(LProbe.SelTables, 'table_schema = ''vendas''');
    Assert.Contains(LProbe.SelColumns('CLIENTE'), 'table_schema = ''vendas''');
    Assert.Contains(LProbe.SelPrimaryKey('CLIENTE'), 'rc.table_schema = ''vendas''');
    Assert.Contains(LProbe.SelForeignKey('CLIENTE'), 'kc.table_schema = ''vendas''');
    Assert.Contains(LProbe.SelSequences, 'schemaname = ''vendas''');
    Assert.Contains(LProbe.SelViews, 'v.table_schema = ''vendas''');
    Assert.Contains(LProbe.SelChecks('CLIENTE'), 'n.nspname = ''vendas''');
    Assert.Contains(LProbe.SelIndexe('CLIENTE'), 'n.nspname = ''vendas''');
  finally
    LProbe.Free;
  end;
end;

// ----------------------------------------------------------- Extracao MSSQL

procedure TTestSchemaAware.MSSQL_DefaultSchema_NoFilter;
var
  LProbe: TMSSQLSchemaProbe;
begin
  LProbe := TMSSQLSchemaProbe.Create;
  try
    LProbe.Schema := '';
    Assert.IsFalse(LProbe.SelTables.Contains('ss.name = '),
      'Default MSSQL nao deve acrescentar filtro de schema');
    Assert.IsFalse(LProbe.SelColumns('CLIENTE').Contains('schema_id('));
    Assert.IsFalse(LProbe.SelSequences.Contains('schema_id('));
  finally
    LProbe.Free;
  end;
end;

procedure TTestSchemaAware.MSSQL_DefaultCatalogSchema_IsEmpty;
var
  LProbe: TMSSQLSchemaProbe;
begin
  // MSSQL nao tem default 'public': sem schema configurado o catalogo fica ''
  // (DDL sem qualificacao, comportamento historico).
  LProbe := TMSSQLSchemaProbe.Create;
  try
    LProbe.Schema := '';
    Assert.AreEqual('', LProbe.CatSchema);
  finally
    LProbe.Free;
  end;
end;

procedure TTestSchemaAware.MSSQL_ConfiguredSchema_FiltersEverySelect;
var
  LProbe: TMSSQLSchemaProbe;
begin
  LProbe := TMSSQLSchemaProbe.Create;
  try
    LProbe.Schema := 'vendas';
    Assert.Contains(LProbe.SelTables, 'ss.name = ''vendas''');
    Assert.Contains(LProbe.SelColumns('CLIENTE'), 'ao.schema_id = schema_id(''vendas'')');
    Assert.Contains(LProbe.SelPrimaryKey('CLIENTE'), 'ss.name = ''vendas''');
    Assert.Contains(LProbe.SelForeignKey('CLIENTE'), 'ft.schema_id = schema_id(''vendas'')');
    Assert.Contains(LProbe.SelSequences, 'schema_id = schema_id(''vendas'')');
    Assert.Contains(LProbe.SelViews, 'sv.schema_id = schema_id(''vendas'')');
    Assert.Contains(LProbe.SelIndexe('CLIENTE'), 'ss.name = ''vendas''');
  finally
    LProbe.Free;
  end;
end;

// ------------------------------------------------------------ DDL - default

procedure TTestSchemaAware.PG_DDL_DefaultSchema_PublicQualified;
var
  LTable: TTableMIK;
begin
  // Comportamento historico do PostgreSQL: o extractor carimba o catalogo com
  // 'public' no default (ver PG_DefaultCatalogSchema_IsPublic), entao o DDL sai
  // public-qualificado como sempre foi. Aqui simulamos esse carimbo.
  FCatalog.Schema := 'public';
  LTable := _BuildClienteTable('INTEGER');
  Assert.StartsWith('CREATE TABLE "public"."CLIENTE" (',
    _NormalizeSQL(_PG.GenerateCreateTable(LTable)));
end;

procedure TTestSchemaAware.MSSQL_DDL_DefaultSchema_Unqualified;
var
  LTable: TTableMIK;
begin
  LTable := _BuildClienteTable('INT');
  Assert.StartsWith('CREATE TABLE CLIENTE (',
    _NormalizeSQL(_MSSQL.GenerateCreateTable(LTable)));
end;

// -------------------------------------------------- DDL - qualificado dialeto

procedure TTestSchemaAware.PG_DDL_Qualified_CreateTable;
var
  LTable: TTableMIK;
begin
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INTEGER');
  Assert.StartsWith('CREATE TABLE "vendas"."CLIENTE" (',
    _NormalizeSQL(_PG.GenerateCreateTable(LTable)));
end;

procedure TTestSchemaAware.PG_DDL_Qualified_AlterColumn;
var
  LTable: TTableMIK;
begin
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INTEGER');
  // Corrige tambem o bug historico (".CLIENTE" quando sem schema): agora
  // qualifica corretamente "vendas"."CLIENTE".
  Assert.Contains(_PG.GenerateAlterColumn(LTable.Fields['000001']),
    'ALTER TABLE "vendas"."CLIENTE" ALTER COLUMN NOME');
end;

procedure TTestSchemaAware.PG_DDL_Qualified_CreateColumn;
var
  LTable: TTableMIK;
begin
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INTEGER');
  Assert.AreEqual('ALTER TABLE "vendas"."CLIENTE" ADD NOME VARCHAR(60);',
    _NormalizeSQL(_PG.GenerateCreateColumn(LTable.Fields['000001'])));
end;

procedure TTestSchemaAware.MSSQL_DDL_Qualified_CreateTable;
var
  LTable: TTableMIK;
begin
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INT');
  Assert.StartsWith('CREATE TABLE [vendas].[CLIENTE] (',
    _NormalizeSQL(_MSSQL.GenerateCreateTable(LTable)));
end;

procedure TTestSchemaAware.MSSQL_DDL_Qualified_DropTable;
var
  LTable: TTableMIK;
begin
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INT');
  Assert.AreEqual('DROP TABLE [vendas].[CLIENTE];',
    _NormalizeSQL(_MSSQL.GenerateDropTable(LTable)));
end;

procedure TTestSchemaAware.MSSQL_DDL_Qualified_RenameColumn;
var
  LTable: TTableMIK;
begin
  // sp_rename: a tabela vira [vendas].[CLIENTE]; a COLUNA no primeiro argumento
  // permanece SEM colchetes (parte do literal 'objeto.coluna').
  FCatalog.Schema := 'vendas';
  LTable := _BuildClienteTable('INT');
  Assert.AreEqual('EXEC sp_rename ''[vendas].[CLIENTE].NOME'', ''novo'', ''COLUMN'';',
    _NormalizeSQL(_MSSQL.GenerateRenameColumn(LTable.Fields['000001'], 'novo')));
end;

// -------------------------------------------------------- Snapshot round-trip

procedure TTestSchemaAware.Snapshot_RoundTrip_PreservesSchema;
var
  LJson: TJSONObject;
  LLoaded: TCatalogMetadataMIK;
begin
  FCatalog.Schema := 'vendas';
  _BuildClienteTable('INTEGER');
  LJson := TMetadataSnapshot.ToJson(FCatalog, dnPostgreSQL, 'schema-test');
  try
    LLoaded := TMetadataSnapshot.FromJson(LJson);
    try
      Assert.AreEqual('vendas', LLoaded.Schema);
      Assert.IsTrue(LLoaded.Tables.ContainsKey('CLIENTE'));
    finally
      LLoaded.Free;
    end;
  finally
    LJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSchemaAware);

end.
