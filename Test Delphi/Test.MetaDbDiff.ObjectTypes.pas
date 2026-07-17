{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  FRENTE 15 - Domains / Stored Procedures-Functions / Comments (Descriptions).

  Sem banco de dados vivo: os cenarios de compare montam catalogos MIK a mao e
  dirigem o GenerateDDLCommands real (mesmo padrao de Test.MetaDbDiff.Policy.pas),
  e os testes de gerador asseveram o TEXTO SQL produzido pelos generators reais
  (Firebird/PostgreSQL). O snapshot v1->v2 usa um JSON sintetico em arquivo.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.ObjectTypes;

interface

uses
  DB,
  SysUtils,
  Classes,
  System.IOUtils,
  System.JSON,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Factory,
  MetaDbDiff.Compare.Options,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.Metadata.Snapshot,
  MetaDbDiff.Metadata.Normalize,
  MetaDbDiff.DDL.Generator.Firebird,
  MetaDbDiff.DDL.Generator.Firebird3,
  MetaDbDiff.DDL.Generator.PostgreSQL;

type
  /// <summary>
  ///   Factory de teste: expoe GenerateDDLCommands sobre catalogos montados a
  ///   mao, fornece corpos vazios aos metodos abstratos e permite alternar o
  ///   modo model-vs-database (para provar o no-op de procedures/domains).
  /// </summary>
  TObjTypesFactory = class(TDatabaseFactory)
  protected
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(ADriverName: TDriverName); override;
    procedure SetModelMode(AValue: Boolean);
    procedure Generate(AMaster, ATarget: TCatalogMetadataMIK);
  end;

  [TestFixture]
  TTestObjectTypes = class
  private
    FFactory: TObjTypesFactory;
    function _Firebird: IDDLGeneratorCommand;
    function _PostgreSQL: IDDLGeneratorCommand;
    function _Norm(const ASQL: String): String;
    function _AddTable(ACatalog: TCatalogMetadataMIK; const AName: String;
      const ADescription: String = ''): TTableMIK;
    function _AddColumn(ATable: TTableMIK; const AName: String; APosition: Integer;
      const ADescription: String = ''): TColumnMIK;
    function _AddDomain(ACatalog: TCatalogMetadataMIK; const AName, ATypeName: String;
      ANotNull: Boolean = False; const ADefault: String = '';
      const ACheck: String = ''): TDomainMIK;
    function _AddProcedure(ACatalog: TCatalogMetadataMIK; const AName, AScript: String;
      AIsFunction: Boolean = False): TProcedureMIK;
    function _CountCommands(AClass: TClass): Integer;
    function _HasCommand(AClass: TClass): Boolean;
    function _SuppressedContains(const AText: String): Boolean;
  public
    [TearDown]
    procedure TearDown;
    // ---- generators: DDL text ------------------------------------------
    [Test]
    procedure Firebird_CreateDomain_WithDefaultNotNullCheck;
    [Test]
    procedure Firebird_DropDomain;
    [Test]
    procedure PostgreSQL_CreateDomain;
    // COSTURA extractor->generator: fontes CRUAS do catalogo Firebird passam pela
    // normalizacao (mesma que GetDomains usa) e produzem CREATE DOMAIN valido.
    [Test]
    procedure Firebird_DomainSeam_NormalizedSources_NoKeywordDuplication;
    // COSTURA PG: 2+ CHECKs agregados (crus) -> normalizacao por fragmento ->
    // CREATE DOMAIN valido, sem CHECK residual interno.
    [Test]
    procedure PostgreSQL_DomainSeam_MultiCheck_NoResidualKeyword;
    [Test]
    procedure CreateProcedure_PassesScriptThrough;
    [Test]
    procedure DropProcedure_UsesProcedureKeyword;
    [Test]
    procedure DropFunction_UsesFunctionKeyword;
    // PostgreSQL: DROP FUNCTION precisa da assinatura (overload).
    [Test]
    procedure PostgreSQL_DropFunction_WithSignature;
    [Test]
    procedure Procedure_CatalogKey_OverloadsDoNotCollapse;
    [Test]
    procedure SetComment_Table;
    [Test]
    procedure SetComment_Column;
    [Test]
    procedure SetComment_EmptyDescription_EmitsIsNull;
    // ---- policy record --------------------------------------------------
    [Test]
    procedure Policy_JanusOrm_DoesNotAllowNewOperations;
    [Test]
    procedure Policy_FullProfile_AllowsNewOperations;
    // ---- compare: domains ----------------------------------------------
    [Test]
    procedure Domain_CreatedWhenMissing;
    [Test]
    procedure Domain_Divergent_WarnsWithoutDropOrCreate;
    [Test]
    procedure Domain_ModelMode_NeverDropsOrphan;
    // ---- compare: procedures -------------------------------------------
    [Test]
    procedure Procedure_Divergent_AtomicDropCreatePair;
    [Test]
    procedure Procedure_ModelMode_IsNoOp_NeverDrops;
    [Test]
    procedure Procedure_Divergent_Janus_SuppressesPair;
    // ---- compare: comments ---------------------------------------------
    [Test]
    procedure Comments_FlagOff_SilentTotal;
    [Test]
    procedure Comments_FlagOn_EmitsSetComment;
    // ---- snapshot v1 -> v2 ---------------------------------------------
    [Test]
    procedure Snapshot_V1_LoadsWithEmptyNewCollections;
    [Test]
    procedure Snapshot_V2_RoundTripsDomainsAndProcedures;
  end;

implementation

{ TObjTypesFactory }

constructor TObjTypesFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
end;

procedure TObjTypesFactory.ExtractDatabase;
begin
  // Catalogos ja montados a mao.
end;

procedure TObjTypesFactory.ExecuteDDLCommands;
begin
  // Sem banco.
end;

procedure TObjTypesFactory.SetModelMode(AValue: Boolean);
begin
  FModelForDatabase := AValue;
end;

procedure TObjTypesFactory.Generate(AMaster, ATarget: TCatalogMetadataMIK);
begin
  FCatalogMaster := AMaster;
  FCatalogTarget := ATarget;
  GenerateDDLCommands(FCatalogMaster, FCatalogTarget);
end;

{ TTestObjectTypes }

procedure TTestObjectTypes.TearDown;
begin
  FreeAndNil(FFactory);
end;

function TTestObjectTypes._Firebird: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnFirebird);
end;

function TTestObjectTypes._PostgreSQL: IDDLGeneratorCommand;
begin
  Result := TSQLDriverRegister.GetInstance.GetDriver(dnPostgreSQL);
end;

function TTestObjectTypes._Norm(const ASQL: String): String;
begin
  Result := StringReplace(ASQL, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

function TTestObjectTypes._AddTable(ACatalog: TCatalogMetadataMIK;
  const AName, ADescription: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  Result.Description := ADescription;
  ACatalog.Tables.Add(UpperCase(AName), Result);
end;

function TTestObjectTypes._AddColumn(ATable: TTableMIK; const AName: String;
  APosition: Integer; const ADescription: String): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.Position := APosition;
  Result.FieldType := ftInteger;
  Result.TypeName := 'INTEGER';
  Result.Description := ADescription;
  ATable.Fields.Add(FormatFloat('000000', APosition), Result);
end;

function TTestObjectTypes._AddDomain(ACatalog: TCatalogMetadataMIK;
  const AName, ATypeName: String; ANotNull: Boolean; const ADefault, ACheck: String): TDomainMIK;
begin
  Result := TDomainMIK.Create(ACatalog);
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.NotNull := ANotNull;
  Result.DefaultValue := ADefault;
  Result.CheckCondition := ACheck;
  ACatalog.Domains.Add(UpperCase(AName), Result);
end;

function TTestObjectTypes._AddProcedure(ACatalog: TCatalogMetadataMIK;
  const AName, AScript: String; AIsFunction: Boolean): TProcedureMIK;
begin
  Result := TProcedureMIK.Create(ACatalog);
  Result.Name := AName;
  Result.Script := AScript;
  Result.IsFunction := AIsFunction;
  ACatalog.Procedures.Add(UpperCase(AName), Result);
end;

function TTestObjectTypes._CountCommands(AClass: TClass): Integer;
var
  LCommand: TDDLCommand;
begin
  Result := 0;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Inc(Result);
end;

function TTestObjectTypes._HasCommand(AClass: TClass): Boolean;
begin
  Result := _CountCommands(AClass) > 0;
end;

function TTestObjectTypes._SuppressedContains(const AText: String): Boolean;
var
  LItem: String;
begin
  Result := False;
  for LItem in FFactory.SuppressedCommands do
    if Pos(AText, LItem) > 0 then
      Exit(True);
end;

{ ---- generators: DDL text ---- }

procedure TTestObjectTypes.Firebird_CreateDomain_WithDefaultNotNullCheck;
var
  LCatalog: TCatalogMetadataMIK;
  LDomain: TDomainMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LDomain := _AddDomain(LCatalog, 'D_QTD', 'INTEGER', True, '0', 'VALUE >= 0');
    Assert.AreEqual(
      'CREATE DOMAIN D_QTD AS INTEGER DEFAULT 0 NOT NULL CHECK (VALUE >= 0);',
      _Norm(_Firebird.GenerateCreateDomain(LDomain)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.Firebird_DropDomain;
var
  LCatalog: TCatalogMetadataMIK;
  LDomain: TDomainMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LDomain := _AddDomain(LCatalog, 'D_EMAIL', 'VARCHAR(60)');
    Assert.AreEqual('DROP DOMAIN D_EMAIL;',
      _Norm(_Firebird.GenerateDropDomain(LDomain)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.PostgreSQL_CreateDomain;
var
  LCatalog: TCatalogMetadataMIK;
  LDomain: TDomainMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LDomain := _AddDomain(LCatalog, 'D_EMAIL', 'character varying(60)', False, '',
      'VALUE ~ ''@''');
    Assert.AreEqual(
      'CREATE DOMAIN D_EMAIL AS character varying(60) CHECK (VALUE ~ ''@'');',
      _Norm(_PostgreSQL.GenerateCreateDomain(LDomain)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.Firebird_DomainSeam_NormalizedSources_NoKeywordDuplication;
var
  LCatalog: TCatalogMetadataMIK;
  LDomain: TDomainMIK;
begin
  // Simula a saida CRUA do catalogo Firebird (rdb$default_source /
  // rdb$validation_source): "DEFAULT 0" e "CHECK (VALUE >= 0)". A COSTURA passa
  // pela MESMA normalizacao que TCatalogMetadataFirebird.GetDomains aplica.
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LDomain := TDomainMIK.Create(LCatalog);
    LDomain.Name := 'D_QTD';
    LDomain.TypeName := 'INTEGER';
    LDomain.NotNull := True;
    LDomain.DefaultValue := TMetadataNormalizer.StripDefaultKeyword('DEFAULT 0');
    LDomain.CheckCondition := TMetadataNormalizer.CanonicalizeCheckCondition('CHECK (VALUE >= 0)');
    LCatalog.Domains.Add('D_QTD', LDomain);
    // O gerador re-adiciona DEFAULT/CHECK UMA vez - sem "DEFAULT DEFAULT" nem
    // "CHECK (CHECK ...)".
    Assert.AreEqual(
      'CREATE DOMAIN D_QTD AS INTEGER DEFAULT 0 NOT NULL CHECK (VALUE >= 0);',
      _Norm(_Firebird.GenerateCreateDomain(LDomain)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.PostgreSQL_DomainSeam_MultiCheck_NoResidualKeyword;
var
  LCatalog: TCatalogMetadataMIK;
  LDomain: TDomainMIK;
  LRawAgg: String;
begin
  // Simula o agregado CRU do string_agg do extractor PG: DOIS constraintdefs
  // completos separados pelo delimitador improvavel '||CHK||'.
  LRawAgg := 'CHECK ((VALUE > 0))||CHK||CHECK ((VALUE < 100))';
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LDomain := TDomainMIK.Create(LCatalog);
    LDomain.Name := 'D_FAIXA';
    LDomain.TypeName := 'integer';
    // MESMA normalizacao que TCatalogMetadataPostgreSQL.GetDomains aplica.
    LDomain.CheckCondition := TMetadataNormalizer.CanonicalizeMultiCheck(LRawAgg, '||CHK||');
    LCatalog.Domains.Add('D_FAIXA', LDomain);
    // Sem nenhum "CHECK" residual DENTRO do CHECK externo.
    Assert.AreEqual(
      'CREATE DOMAIN D_FAIXA AS integer CHECK ((VALUE > 0) AND (VALUE < 100));',
      _Norm(_PostgreSQL.GenerateCreateDomain(LDomain)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.CreateProcedure_PassesScriptThrough;
var
  LCatalog: TCatalogMetadataMIK;
  LProc: TProcedureMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LProc := _AddProcedure(LCatalog, 'SP_FOO',
      'CREATE PROCEDURE SP_FOO AS BEGIN EXIT; END');
    // O generator apenas repassa o script COMPLETO extraido do banco.
    Assert.AreEqual('CREATE PROCEDURE SP_FOO AS BEGIN EXIT; END',
      _Firebird.GenerateCreateProcedure(LProc));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.DropProcedure_UsesProcedureKeyword;
var
  LCatalog: TCatalogMetadataMIK;
  LProc: TProcedureMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LProc := _AddProcedure(LCatalog, 'SP_FOO', 'x', False);
    Assert.AreEqual('DROP PROCEDURE SP_FOO;',
      _Norm(_Firebird.GenerateDropProcedure(LProc)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.DropFunction_UsesFunctionKeyword;
var
  LCatalog: TCatalogMetadataMIK;
  LProc: TProcedureMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LProc := _AddProcedure(LCatalog, 'FN_BAR', 'x', True);
    Assert.AreEqual('DROP FUNCTION FN_BAR;',
      _Norm(_PostgreSQL.GenerateDropProcedure(LProc)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.PostgreSQL_DropFunction_WithSignature;
var
  LCatalog: TCatalogMetadataMIK;
  LProc: TProcedureMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LProc := _AddProcedure(LCatalog, 'FN_SUM', 'x', True);
    LProc.Signature := 'integer, integer';
    // Sem a assinatura o PostgreSQL falharia com "function is not unique".
    Assert.AreEqual('DROP FUNCTION FN_SUM(integer, integer);',
      _Norm(_PostgreSQL.GenerateDropProcedure(LProc)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.Procedure_CatalogKey_OverloadsDoNotCollapse;
var
  LCatalog: TCatalogMetadataMIK;
  LP1, LP2: TProcedureMIK;
begin
  // Duas functions homonimas com assinaturas diferentes: CatalogKey as mantem
  // distintas (nao colapsa) - a chave inclui a assinatura.
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LP1 := TProcedureMIK.Create(LCatalog);
    LP1.Name := 'F';
    LP1.IsFunction := True;
    LP1.Signature := 'integer';
    LCatalog.Procedures.AddOrSetValue(LP1.CatalogKey, LP1);

    LP2 := TProcedureMIK.Create(LCatalog);
    LP2.Name := 'F';
    LP2.IsFunction := True;
    LP2.Signature := 'text';
    LCatalog.Procedures.AddOrSetValue(LP2.CatalogKey, LP2);

    Assert.AreEqual(2, LCatalog.Procedures.Count,
      'overloads com assinaturas distintas nao devem colapsar');
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.SetComment_Table;
var
  LCatalog: TCatalogMetadataMIK;
  LTable: TTableMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LTable := _AddTable(LCatalog, 'CLIENTE', 'Cadastro de clientes');
    Assert.AreEqual('COMMENT ON TABLE CLIENTE IS ''Cadastro de clientes'';',
      _Norm(_Firebird.GenerateSetComment(LTable, nil)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.SetComment_Column;
var
  LCatalog: TCatalogMetadataMIK;
  LTable: TTableMIK;
  LColumn: TColumnMIK;
begin
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LTable := _AddTable(LCatalog, 'CLIENTE');
    LColumn := _AddColumn(LTable, 'NOME', 0, 'Nome do cliente');
    Assert.AreEqual('COMMENT ON COLUMN CLIENTE.NOME IS ''Nome do cliente'';',
      _Norm(_PostgreSQL.GenerateSetComment(nil, LColumn)));
  finally
    LCatalog.Free;
  end;
end;

procedure TTestObjectTypes.SetComment_EmptyDescription_EmitsIsNull;
var
  LCatalog: TCatalogMetadataMIK;
  LTable: TTableMIK;
begin
  // Description vazia = remocao semantica: IS NULL (nao IS '').
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LTable := _AddTable(LCatalog, 'CLIENTE', '');
    Assert.AreEqual('COMMENT ON TABLE CLIENTE IS NULL;',
      _Norm(_Firebird.GenerateSetComment(LTable, nil)));
  finally
    LCatalog.Free;
  end;
end;

{ ---- policy ---- }

procedure TTestObjectTypes.Policy_JanusOrm_DoesNotAllowNewOperations;
var
  LPolicy: TComparePolicy;
begin
  // JanusOrmProfile permanece INTACTO: nenhuma das operacoes novas entra nele.
  LPolicy := TComparePolicy.JanusOrmProfile;
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.CreateDomain), 'CreateDomain');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropDomain), 'DropDomain');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.CreateProcedure), 'CreateProcedure');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropProcedure), 'DropProcedure');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.SetComment), 'SetComment');
end;

procedure TTestObjectTypes.Policy_FullProfile_AllowsNewOperations;
var
  LPolicy: TComparePolicy;
begin
  LPolicy := TComparePolicy.FullProfile;
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreateDomain), 'CreateDomain');
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreateProcedure), 'CreateProcedure');
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.SetComment), 'SetComment');
end;

{ ---- compare: domains ---- }

procedure TTestObjectTypes.Domain_CreatedWhenMissing;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddDomain(LMaster, 'D_EMAIL', 'VARCHAR(60)');
  LTarget := TCatalogMetadataMIK.Create;

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandCreateDomain),
    'CREATE DOMAIN deveria ser emitido (falta no target)');
end;

procedure TTestObjectTypes.Domain_Divergent_WarnsWithoutDropOrCreate;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Mesmo dominio nos dois lados com TIPO diferente: conservador - warning, sem
  // drop nem create automatico (dominio em uso nao dropa).
  LMaster := TCatalogMetadataMIK.Create;
  _AddDomain(LMaster, 'D_COD', 'VARCHAR(60)');
  LTarget := TCatalogMetadataMIK.Create;
  _AddDomain(LTarget, 'D_COD', 'VARCHAR(30)');

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandCreateDomain), 'nao deve criar');
  Assert.IsFalse(_HasCommand(TDDLCommandDropDomain), 'nao deve dropar');
  Assert.IsTrue(_SuppressedContains('DOMAIN D_COD diverge'),
    'a divergencia deveria ser registrada na auditoria');
end;

procedure TTestObjectTypes.Domain_ModelMode_NeverDropsOrphan;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Model-mode: o modelo (master) nao declara dominios; um dominio SO no banco
  // NUNCA e dropado (mesma protecao das views).
  LMaster := TCatalogMetadataMIK.Create;
  LTarget := TCatalogMetadataMIK.Create;
  _AddDomain(LTarget, 'D_ORFAO', 'VARCHAR(10)');

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.SetModelMode(True);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropDomain),
    'DROP DOMAIN nunca em model-mode');
end;

{ ---- compare: procedures ---- }

procedure TTestObjectTypes.Procedure_Divergent_AtomicDropCreatePair;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddProcedure(LMaster, 'SP_X', 'CREATE PROCEDURE SP_X AS BEGIN SELECT 1; END');
  LTarget := TCatalogMetadataMIK.Create;
  _AddProcedure(LTarget, 'SP_X', 'CREATE PROCEDURE SP_X AS BEGIN SELECT 2; END');

  // DB-vs-DB (model-mode OFF por padrao).
  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandDropProcedure), 'DROP do par');
  Assert.IsTrue(_HasCommand(TDDLCommandCreateProcedure), 'CREATE do par');
end;

procedure TTestObjectTypes.Procedure_ModelMode_IsNoOp_NeverDrops;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Model-mode: compare de procedures e NO-OP seguro - nunca dropa a procedure
  // que so existe no banco.
  LMaster := TCatalogMetadataMIK.Create;
  LTarget := TCatalogMetadataMIK.Create;
  _AddProcedure(LTarget, 'SP_ORFA', 'CREATE PROCEDURE SP_ORFA AS BEGIN END');

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.SetModelMode(True);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropProcedure),
    'DROP PROCEDURE nunca em model-mode');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateProcedure),
    'CREATE PROCEDURE nunca em model-mode');
end;

procedure TTestObjectTypes.Procedure_Divergent_Janus_SuppressesPair;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddProcedure(LMaster, 'SP_X', 'CREATE PROCEDURE SP_X AS BEGIN SELECT 1; END');
  LTarget := TCatalogMetadataMIK.Create;
  _AddProcedure(LTarget, 'SP_X', 'CREATE PROCEDURE SP_X AS BEGIN SELECT 2; END');

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropProcedure), 'sem drop sob Janus');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateProcedure), 'sem create sob Janus');
  Assert.IsTrue(_SuppressedContains('RECREATE PROCEDURE'),
    'o par suprimido deveria ser auditado');
end;

{ ---- compare: comments ---- }

procedure TTestObjectTypes.Comments_FlagOff_SilentTotal;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTable: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTable := _AddTable(LMaster, 'CLIENTE', 'descricao nova');
  _AddColumn(LTable, 'ID', 0);
  LTarget := TCatalogMetadataMIK.Create;
  LTable := _AddTable(LTarget, 'CLIENTE', 'descricao antiga');
  _AddColumn(LTable, 'ID', 0);

  FFactory := TObjTypesFactory.Create(dnFirebird);
  // CompareDescriptions default False.
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandSetComment),
    'flag OFF = silencio total (zero custo)');
end;

procedure TTestObjectTypes.Comments_FlagOn_EmitsSetComment;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTable: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTable := _AddTable(LMaster, 'CLIENTE', 'descricao nova');
  _AddColumn(LTable, 'ID', 0, 'id novo');
  LTarget := TCatalogMetadataMIK.Create;
  LTable := _AddTable(LTarget, 'CLIENTE', 'descricao antiga');
  _AddColumn(LTable, 'ID', 0, 'id antigo');

  FFactory := TObjTypesFactory.Create(dnFirebird);
  FFactory.CompareDescriptions := True;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandSetComment),
    'flag ON deveria emitir COMMENT ON para tabela/coluna divergente');
end;

{ ---- snapshot v1 -> v2 ---- }

procedure TTestObjectTypes.Snapshot_V1_LoadsWithEmptyNewCollections;
var
  LFile: String;
  LJson: String;
  LCatalog: TCatalogMetadataMIK;
begin
  // JSON v1 SINTETICO (sem as chaves Domains/Procedures): deve carregar
  // normalmente, com as colecoes novas VAZIAS (retrocompatibilidade).
  LJson :=
    '{' +
    '"FormatVersion":1,' +
    '"DriverName":"Firebird",' +
    '"GeneratedAt":"2026-07-16T10:00:00",' +
    '"SourceDescription":"v1 sintetico",' +
    '"Catalog":{"Name":"","Schema":"","Description":"",' +
    '"Tables":[],"Sequences":[],"Views":[]}' +
    '}';
  LFile := TPath.Combine(TPath.GetTempPath, 'mdbdiff_v1_' +
    IntToStr(Random(999999)) + '.json');
  TFile.WriteAllText(LFile, LJson, TEncoding.UTF8);
  try
    LCatalog := TMetadataSnapshot.LoadFromFile(LFile);
    try
      Assert.AreEqual(0, LCatalog.Domains.Count, 'Domains vazio num v1');
      Assert.AreEqual(0, LCatalog.Procedures.Count, 'Procedures vazio num v1');
    finally
      LCatalog.Free;
    end;
  finally
    if TFile.Exists(LFile) then
      TFile.Delete(LFile);
  end;
end;

procedure TTestObjectTypes.Snapshot_V2_RoundTripsDomainsAndProcedures;
var
  LFile: String;
  LSource, LLoaded: TCatalogMetadataMIK;
begin
  LSource := TCatalogMetadataMIK.Create;
  try
    _AddDomain(LSource, 'D_EMAIL', 'VARCHAR(60)', True, '', 'VALUE > 0');
    _AddProcedure(LSource, 'SP_X', 'CREATE PROCEDURE SP_X AS BEGIN END', False);
    _AddProcedure(LSource, 'FN_Y', 'CREATE FUNCTION FN_Y ...', True);

    LFile := TPath.Combine(TPath.GetTempPath, 'mdbdiff_v2_' +
      IntToStr(Random(999999)) + '.json');
    TMetadataSnapshot.SaveToFile(LSource, LFile, dnFirebird, 'v2 roundtrip');
    try
      LLoaded := TMetadataSnapshot.LoadFromFile(LFile);
      try
        Assert.AreEqual(1, LLoaded.Domains.Count, 'Domains preservado');
        Assert.AreEqual(2, LLoaded.Procedures.Count, 'Procedures preservado');
        Assert.IsTrue(LLoaded.Domains.ContainsKey('D_EMAIL'), 'D_EMAIL presente');
        Assert.IsTrue(LLoaded.Procedures.ContainsKey('FN_Y'), 'FN_Y presente');
        Assert.IsTrue(LLoaded.Procedures.Items['FN_Y'].IsFunction,
          'FN_Y deve manter IsFunction=True');
      finally
        LLoaded.Free;
      end;
    finally
      if TFile.Exists(LFile) then
        TFile.Delete(LFile);
    end;
  finally
    LSource.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestObjectTypes);

end.
