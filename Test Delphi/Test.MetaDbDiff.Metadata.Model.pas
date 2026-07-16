{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Model -> MIK extraction tests (TModelMetadata) WITHOUT a live database.

  TModelMetadata only touches the connection through FConnection.GetDriver
  (MetaDbDiff.Metadata.Extract.pas, GetFieldTypeDefinition) - it never opens
  the connection. So a "shell" IDBConnection built over an UNCONNECTED
  TFDConnection (TFactoryFireDAC.Create(FDConn, dnFirebird)) is enough to
  resolve the dialect-specific type names. ftGuid columns are avoided in the
  test entities because they would additionally require Options.StoreGUIDAsOctet.

  One-shot warning: TMappingExplorer.GetRepositoryMapping snapshots (and the
  underlying TRegisterClass list drains) the registered entities on its FIRST
  call; the entities are registered in the initialization of
  Test.MetaDbDiff.Entities.pas, so extraction works regardless of fixture order.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Metadata.Model;

interface

uses
  DB,
  SysUtils,
  DUnitX.TestFramework,
  FireDAC.Comp.Client,
  DataEngine.FactoryInterfaces,
  DataEngine.FactoryFireDac,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Metadata.Model,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator.Firebird,
  Test.MetaDbDiff.Entities;

type
  [TestFixture]
  TTestMetadataModel = class
  private
    FFDConnection: TFDConnection;
    FConnection: IDBConnection;
    FCatalog: TCatalogMetadataMIK;
    FModel: TModelMetadata;
    function _Cliente: TTableMIK;
    function _Pedido: TTableMIK;
    function _NormalizeSQL(const ASQL: String): String;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Connection_ShellReportsDriverWithoutConnecting;
    [Test]
    procedure Model_ExtractsAllRegisteredTables;
    [Test]
    procedure Model_Columns_TypesResolvedForFirebird;
    [Test]
    procedure Model_Columns_DateTime_OracleKeepsDATE;
    [Test]
    procedure Model_Columns_NotNullAndDefault;
    [Test]
    procedure Model_PrimaryKey_SimpleAndComposite;
    [Test]
    procedure Model_ForeignKey_FromModel;
    [Test]
    procedure Model_Checks_FromModel;
    [Test]
    procedure Model_Indexes_FromModel;
    [Test]
    procedure Model_Sequences_FromModel;
    [Test]
    procedure Model_EndToEnd_FirebirdCreateTableFromExtractedModel;
    [Test]
    procedure Model_DefaultValue_QuotingEdgeCases;
  end;

implementation

{ TTestMetadataModel }

procedure TTestMetadataModel.Setup;
begin
  FFDConnection := TFDConnection.Create(nil);
  // Conexao "casca": nunca e aberta; so informa o dialeto (dnFirebird).
  FConnection := TFactoryFireDAC.Create(FFDConnection, dnFirebird);
  FCatalog := TCatalogMetadataMIK.Create;
  FModel := TModelMetadata.Create;
  FModel.Connection := FConnection;
  FModel.CatalogMetadata := FCatalog;
  FModel.ModelForDatabase := False;
  FModel.GetModelMetadata;
end;

procedure TTestMetadataModel.TearDown;
begin
  FModel.Free;
  FCatalog.Free;
  FConnection := nil;
  FFDConnection.Free;
end;

function TTestMetadataModel._Cliente: TTableMIK;
begin
  Result := FCatalog.Tables['CLIENTE'];
end;

function TTestMetadataModel._Pedido: TTableMIK;
begin
  Result := FCatalog.Tables['PEDIDO'];
end;

function TTestMetadataModel._NormalizeSQL(const ASQL: String): String;
begin
  Result := StringReplace(ASQL, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

procedure TTestMetadataModel.Connection_ShellReportsDriverWithoutConnecting;
begin
  Assert.IsTrue(FConnection.GetDriver = dnFirebird);
  Assert.IsFalse(FConnection.IsConnected,
    'A conexao casca nunca deve ter sido aberta');
end;

procedure TTestMetadataModel.Model_ExtractsAllRegisteredTables;
begin
  Assert.AreEqual(2, FCatalog.Tables.Count);
  Assert.IsTrue(FCatalog.Tables.ContainsKey('CLIENTE'), 'CLIENTE nao extraida');
  Assert.IsTrue(FCatalog.Tables.ContainsKey('PEDIDO'), 'PEDIDO nao extraida');
  Assert.AreEqual('Tabela de clientes', _Cliente.Description);
end;

procedure TTestMetadataModel.Model_Columns_TypesResolvedForFirebird;
begin
  Assert.AreEqual(5, _Cliente.Fields.Count);
  // Chave = FormatFloat('000000', Position)
  Assert.AreEqual('ID', _Cliente.Fields['000000'].Name);
  Assert.AreEqual('INTEGER', _Cliente.Fields['000000'].TypeName);
  Assert.AreEqual('NOME', _Cliente.Fields['000001'].Name);
  // O placeholder %l so e substituido na geracao do DDL, nao na extracao.
  Assert.AreEqual('VARCHAR(%l)', _Cliente.Fields['000001'].TypeName);
  Assert.AreEqual(60, _Cliente.Fields['000001'].Size);
  Assert.AreEqual('SALDO', _Cliente.Fields['000003'].Name);
  Assert.AreEqual('DECIMAL(%p,%s)', _Cliente.Fields['000003'].TypeName);
  Assert.AreEqual(18, _Cliente.Fields['000003'].Precision);
  Assert.AreEqual(2, _Cliente.Fields['000003'].Scale);
  // ftDateTime carries date+time, so on Firebird (dialect 3+) it must resolve
  // to TIMESTAMP, not DATE (DATE is date-only since dialect 3). Fixed in
  // Metadata.Extract.pas, GetFieldTypeDefinition.
  Assert.AreEqual('CRIADO_EM', _Cliente.Fields['000004'].Name);
  Assert.AreEqual('TIMESTAMP', _Cliente.Fields['000004'].TypeName);
end;

procedure TTestMetadataModel.Model_Columns_DateTime_OracleKeepsDATE;
var
  LFDConnection: TFDConnection;
  LConnection: IDBConnection;
  LCatalog: TCatalogMetadataMIK;
  LModel: TModelMetadata;
begin
  // Not a bug: Oracle's DATE type stores date+time down to the second, so
  // ftDateTime must keep mapping to DATE on Oracle (unlike Firebird/
  // Interbase/PostgreSQL, whose DATE is date-only).
  LFDConnection := TFDConnection.Create(nil);
  try
    LConnection := TFactoryFireDAC.Create(LFDConnection, dnOracle);
    LCatalog := TCatalogMetadataMIK.Create;
    try
      LModel := TModelMetadata.Create;
      try
        LModel.Connection := LConnection;
        LModel.CatalogMetadata := LCatalog;
        LModel.ModelForDatabase := False;
        LModel.GetModelMetadata;
        Assert.AreEqual('CRIADO_EM', LCatalog.Tables['CLIENTE'].Fields['000004'].Name);
        Assert.AreEqual('DATE', LCatalog.Tables['CLIENTE'].Fields['000004'].TypeName,
          'Oracle DATE deveria ser mantido para ftDateTime');
      finally
        LModel.Free;
      end;
    finally
      LCatalog.Free;
    end;
  finally
    LConnection := nil;
    LFDConnection.Free;
  end;
end;

procedure TTestMetadataModel.Model_Columns_NotNullAndDefault;
begin
  Assert.IsTrue(_Cliente.Fields['000000'].NotNull, 'ID deveria ser NOT NULL');
  Assert.IsTrue(_Cliente.Fields['000001'].NotNull, 'NOME deveria ser NOT NULL');
  Assert.IsFalse(_Cliente.Fields['000002'].NotNull, 'IDADE nao tem [Restrictions]');
  // Default vem do [Dictionary] (DefaultExpression)
  Assert.AreEqual('SEM NOME', _Cliente.Fields['000001'].DefaultValue);
  Assert.AreEqual('', _Cliente.Fields['000002'].DefaultValue);
end;

procedure TTestMetadataModel.Model_PrimaryKey_SimpleAndComposite;
begin
  Assert.AreEqual('PK_CLIENTE', _Cliente.PrimaryKey.Name);
  Assert.IsTrue(_Cliente.PrimaryKey.AutoIncrement);
  Assert.AreEqual(1, _Cliente.PrimaryKey.Fields.Count);
  Assert.AreEqual('ID', _Cliente.PrimaryKey.Fields['000000'].Name);

  Assert.AreEqual('PK_PEDIDO', _Pedido.PrimaryKey.Name);
  Assert.IsFalse(_Pedido.PrimaryKey.AutoIncrement);
  Assert.AreEqual(2, _Pedido.PrimaryKey.Fields.Count);
  Assert.AreEqual('ID_EMPRESA', _Pedido.PrimaryKey.Fields['000000'].Name);
  Assert.AreEqual('ID_PEDIDO', _Pedido.PrimaryKey.Fields['000001'].Name);
end;

procedure TTestMetadataModel.Model_ForeignKey_FromModel;
var
  LForeignKey: TForeignKeyMIK;
begin
  Assert.AreEqual(1, _Pedido.ForeignKeys.Count);
  Assert.IsTrue(_Pedido.ForeignKeys.ContainsKey('FK_PEDIDO_CLIENTE'));
  LForeignKey := _Pedido.ForeignKeys['FK_PEDIDO_CLIENTE'];
  Assert.AreEqual('CLIENTE', LForeignKey.FromTable);
  Assert.IsTrue(LForeignKey.OnDelete = TRuleAction.Cascade);
  Assert.IsTrue(LForeignKey.OnUpdate = TRuleAction.SetNull);
  Assert.AreEqual(1, LForeignKey.FromFields.Count);
  Assert.AreEqual('ID_CLIENTE', LForeignKey.FromFields['000000'].Name);
  Assert.AreEqual(1, LForeignKey.ToFields.Count);
  Assert.AreEqual('ID', LForeignKey.ToFields['000000'].Name);
  Assert.AreEqual(0, _Cliente.ForeignKeys.Count);
end;

procedure TTestMetadataModel.Model_Checks_FromModel;
begin
  Assert.AreEqual(1, _Cliente.Checks.Count);
  Assert.IsTrue(_Cliente.Checks.ContainsKey('CK_CLIENTE_IDADE'));
  Assert.AreEqual('IDADE >= 0', _Cliente.Checks['CK_CLIENTE_IDADE'].Condition);
  Assert.AreEqual(0, _Pedido.Checks.Count);
end;

procedure TTestMetadataModel.Model_Indexes_FromModel;
begin
  Assert.AreEqual(1, _Cliente.IndexeKeys.Count);
  Assert.IsTrue(_Cliente.IndexeKeys.ContainsKey('IDX_CLIENTE_NOME'));
  Assert.IsFalse(_Cliente.IndexeKeys['IDX_CLIENTE_NOME'].Unique);
  Assert.AreEqual('NOME', _Cliente.IndexeKeys['IDX_CLIENTE_NOME'].Fields['000000'].Name);

  Assert.AreEqual(1, _Pedido.IndexeKeys.Count);
  Assert.IsTrue(_Pedido.IndexeKeys['IDX_PEDIDO_UNQ'].Unique);
  Assert.AreEqual(2, _Pedido.IndexeKeys['IDX_PEDIDO_UNQ'].Fields.Count);
end;

procedure TTestMetadataModel.Model_Sequences_FromModel;
begin
  Assert.AreEqual(1, FCatalog.Sequences.Count);
  Assert.IsTrue(FCatalog.Sequences.ContainsKey('SEQ_CLIENTE'));
  Assert.AreEqual('CLIENTE', FCatalog.Sequences['SEQ_CLIENTE'].TableName);
end;

procedure TTestMetadataModel.Model_EndToEnd_FirebirdCreateTableFromExtractedModel;
var
  LGenerator: IDDLGeneratorCommand;
  LSQL: String;
begin
  // Integracao: entidade decorada -> extracao MIK -> DDL Firebird.
  LGenerator := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
  LSQL := _NormalizeSQL(LGenerator.GenerateCreateTable(_Cliente));
  Assert.IsTrue(Pos('CREATE TABLE CLIENTE', LSQL) > 0, 'CREATE TABLE ausente: ' + LSQL);
  Assert.IsTrue(Pos('VARCHAR(60)', LSQL) > 0, 'VARCHAR(60) ausente: ' + LSQL);
  // O DefaultExpression string do [Dictionary] deve ir para o DDL COM aspas
  // simples ("DEFAULT 'SEM NOME'"), pois NOME e uma coluna textual (ftString).
  // Fixed em TDDLSQLGenerator.GetCreateFieldDefaultDefinition (DDL.Generator.pas).
  Assert.IsTrue(Pos('DEFAULT ''SEM NOME''', LSQL) > 0, 'DEFAULT ausente ou sem aspas: ' + LSQL);
  Assert.IsTrue(Pos('DECIMAL(18,2)', LSQL) > 0, 'DECIMAL(18,2) ausente: ' + LSQL);
  Assert.IsTrue(Pos('CONSTRAINT PK_CLIENTE PRIMARY KEY (ID)', LSQL) > 0,
    'PK ausente: ' + LSQL);
  Assert.IsTrue(Pos('CREATE INDEX IDX_CLIENTE_NOME ON CLIENTE (NOME);', LSQL) > 0,
    'Indice ausente: ' + LSQL);
  Assert.IsTrue(Pos('CONSTRAINT CK_CLIENTE_IDADE CHECK (IDADE >= 0)', LSQL) > 0,
    'Check ausente: ' + LSQL);
end;

procedure TTestMetadataModel.Model_DefaultValue_QuotingEdgeCases;
var
  LGenerator: IDDLGeneratorCommand;
  LColumn: TColumnMIK;
  LSQL: String;
begin
  LGenerator := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);

  // Textual default already quoted by the caller: must not be re-quoted.
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'APELIDO';
    LColumn.FieldType := ftString;
    LColumn.TypeName := 'VARCHAR(%l)';
    LColumn.Size := 30;
    LColumn.DefaultValue := '''JA QUOTADO''';
    LSQL := _NormalizeSQL(LGenerator.GenerateCreateColumn(LColumn));
    Assert.IsTrue(Pos('DEFAULT ''JA QUOTADO''', LSQL) > 0,
      'Valor ja quotado deveria permanecer intacto: ' + LSQL);
    Assert.IsFalse(Pos('DEFAULT ''''JA QUOTADO', LSQL) > 0,
      'Valor ja quotado nao deveria ser re-quotado: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // Known function/keyword: must not be quoted (case-insensitive).
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'ATUALIZADO_EM';
    LColumn.FieldType := ftDateTime;
    LColumn.TypeName := 'TIMESTAMP';
    LColumn.DefaultValue := 'current_timestamp';
    LSQL := _NormalizeSQL(LGenerator.GenerateCreateColumn(LColumn));
    Assert.IsTrue(Pos('DEFAULT current_timestamp', LSQL) > 0,
      'CURRENT_TIMESTAMP ausente: ' + LSQL);
    Assert.IsFalse(Pos('''current_timestamp''', LSQL) > 0,
      'CURRENT_TIMESTAMP nao deveria ser quotado: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // Internal single quote must be escaped by doubling (SQL standard).
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'OBS';
    LColumn.FieldType := ftString;
    LColumn.TypeName := 'VARCHAR(%l)';
    LColumn.Size := 50;
    LColumn.DefaultValue := 'O''Brien';
    LSQL := _NormalizeSQL(LGenerator.GenerateCreateColumn(LColumn));
    Assert.IsTrue(Pos('DEFAULT ' + QuotedStr('O''Brien'), LSQL) > 0,
      'Aspas internas nao escapadas corretamente: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // Numeric column: default must remain unquoted (behavior unchanged).
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'QTD';
    LColumn.FieldType := ftInteger;
    LColumn.TypeName := 'INTEGER';
    LColumn.DefaultValue := '0';
    LSQL := _NormalizeSQL(LGenerator.GenerateCreateColumn(LColumn));
    Assert.IsTrue(Pos('DEFAULT 0', LSQL) > 0, 'Default numerico ausente: ' + LSQL);
    Assert.IsFalse(Pos('DEFAULT ''0''', LSQL) > 0,
      'Default numerico nao deveria ser quotado: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // Lone apostrophe: length-1 value equal to ' must NOT be treated as
  // "already quoted" (IsAlreadyQuoted requires Length >= 2), otherwise it
  // would be emitted unescaped and break the generated SQL.
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'X';
    LColumn.FieldType := ftString;
    LColumn.TypeName := 'VARCHAR(%l)';
    LColumn.Size := 1;
    LColumn.DefaultValue := '''';
    LSQL := _NormalizeSQL(LGenerator.GenerateCreateColumn(LColumn));
    Assert.IsTrue(Pos('DEFAULT ' + QuotedStr(''''), LSQL) > 0,
      'Apostrofo solitario deveria ser escapado corretamente: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // ALTER path (GenerateAlterDefaultValue / GetAlterFieldDefaultDefinition):
  // textual default must be quoted, same as the CREATE path.
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'APELIDO';
    LColumn.FieldType := ftString;
    LColumn.TypeName := 'VARCHAR(%l)';
    LColumn.Size := 30;
    LColumn.DefaultValue := 'SEM APELIDO';
    LSQL := _NormalizeSQL(LGenerator.GenerateAlterDefaultValue(LColumn));
    Assert.IsTrue(Pos('SET DEFAULT ''SEM APELIDO''', LSQL) > 0,
      'ALTER com default textual deveria vir quotado: ' + LSQL);
  finally
    LColumn.Free;
  end;

  // ALTER path: known function/keyword must not be quoted.
  LColumn := TColumnMIK.Create(_Cliente);
  try
    LColumn.Name := 'ATUALIZADO_EM';
    LColumn.FieldType := ftDateTime;
    LColumn.TypeName := 'TIMESTAMP';
    LColumn.DefaultValue := 'CURRENT_TIMESTAMP';
    LSQL := _NormalizeSQL(LGenerator.GenerateAlterDefaultValue(LColumn));
    Assert.IsTrue(Pos('SET DEFAULT CURRENT_TIMESTAMP;', LSQL) > 0,
      'ALTER com CURRENT_TIMESTAMP nao deveria ser quotado: ' + LSQL);
  finally
    LColumn.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMetadataModel);

end.
