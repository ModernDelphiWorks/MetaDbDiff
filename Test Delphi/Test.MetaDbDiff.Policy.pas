{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Compare policy tests (TComparePolicy) WITHOUT a live database.

  The policy gate lives in the Action* methods and in the drop+create pair
  handling of the Compare* methods of TDatabaseFactory. These tests build the
  master/target MIK catalogs by hand and drive the real GenerateDDLCommands so
  the gates run exactly as they do in production. A tiny testable subclass only
  supplies empty ExtractDatabase / ExecuteDDLCommands bodies (both abstract in
  TDatabaseFactory) and hands the pre-built catalogs to GenerateDDLCommands.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Policy;

interface

uses
  DB,
  SysUtils,
  DUnitX.TestFramework,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Factory,
  MetaDbDiff.Compare.Options,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator.Firebird;

type
  /// <summary>
  ///   Subclasse de teste: exp�e GenerateDDLCommands sobre cat�logos montados �
  ///   m�o e fornece corpos vazios para os m�todos abstratos herdados.
  /// </summary>
  TTestableFactory = class(TDatabaseFactory)
  protected
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    // Reexp�e como p�blico o construtor herdado (protegido no ancestral).
    constructor Create(ADriverName: TDriverName); override;
    /// <summary> Assume a posse dos cat�logos e roda o diff real. </summary>
    procedure Generate(AMaster, ATarget: TCatalogMetadataMIK);
  end;

  [TestFixture]
  TTestComparePolicy = class
  private
    FFactory: TTestableFactory;
    function AddTable(ACatalog: TCatalogMetadataMIK; const AName: String): TTableMIK;
    function AddColumn(ATable: TTableMIK; const AName: String; APosition: Integer;
      const ATypeName: String; ASize: Integer = 0; ANotNull: Boolean = False): TColumnMIK;
    procedure SetPrimaryKey(ATable: TTableMIK; const AName, AColumnName: String);
    procedure AddIndexe(ATable: TTableMIK; const AName, AColumnName: String;
      AUnique: Boolean);
    function CountCommands(AClass: TClass): Integer;
    function HasCommand(AClass: TClass): Boolean;
    function SuppressedContains(const AText: String): Boolean;
    // Cen�rio "coluna": CLIENTE com create/alter/drop de coluna e create de PK.
    procedure BuildColumnScenario(out AMaster, ATarget: TCatalogMetadataMIK);
    // Cen�rio "par": PEDIDO com �ndice divergente (recreate = drop+create).
    procedure BuildIndexRecreateScenario(out AMaster, ATarget: TCatalogMetadataMIK);
  public
    [TearDown]
    procedure TearDown;
    // ---- policy record --------------------------------------------------
    [Test]
    procedure Policy_FullProfile_AllowsEverything;
    [Test]
    procedure Policy_JanusOrmProfile_AllowsOnlyAdditiveCreates;
    // ---- generation gates -----------------------------------------------
    [Test]
    procedure Janus_SuppressesDropAndAlter_EmitsCreates;
    [Test]
    procedure Janus_DropCreatePair_SuppressedEntirely;
    [Test]
    procedure Full_DropCreatePair_BothEmitted;
    [Test]
    procedure Full_MatchesCurrentBehavior_NoSuppression;
    // ---- defense in depth on execution ----------------------------------
    [Test]
    procedure Execute_RejectsCommandNotAllowedByPolicy;
  end;

implementation

{ TTestableFactory }

constructor TTestableFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
end;

procedure TTestableFactory.ExtractDatabase;
begin
  // Nada a extrair: os cat�logos j� v�m montados � m�o.
end;

procedure TTestableFactory.ExecuteDDLCommands;
begin
  // Sem banco: a execu��o real n�o � exercida aqui.
end;

procedure TTestableFactory.Generate(AMaster, ATarget: TCatalogMetadataMIK);
begin
  // O ancestral libera FCatalogMaster/FCatalogTarget no destroy; passamos a
  // posse dos cat�logos montados no teste.
  FCatalogMaster := AMaster;
  FCatalogTarget := ATarget;
  GenerateDDLCommands(FCatalogMaster, FCatalogTarget);
end;

{ TTestComparePolicy }

procedure TTestComparePolicy.TearDown;
begin
  FreeAndNil(FFactory);
end;

function TTestComparePolicy.AddTable(ACatalog: TCatalogMetadataMIK;
  const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  ACatalog.Tables.Add(AName, Result);
end;

function TTestComparePolicy.AddColumn(ATable: TTableMIK; const AName: String;
  APosition: Integer; const ATypeName: String; ASize: Integer;
  ANotNull: Boolean): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.Position := APosition;
  Result.FieldType := ftUnknown;
  Result.TypeName := ATypeName;
  Result.Size := ASize;
  Result.NotNull := ANotNull;
  ATable.Fields.Add(FormatFloat('000000', APosition), Result);
end;

procedure TTestComparePolicy.SetPrimaryKey(ATable: TTableMIK;
  const AName, AColumnName: String);
var
  LColumn: TColumnMIK;
begin
  ATable.PrimaryKey.Name := AName;
  // A PK � dona das suas pr�prias colunas (dicion�rio doOwnsValues), por isso
  // criamos uma inst�ncia dedicada em vez de reaproveitar a de Fields.
  LColumn := TColumnMIK.Create(ATable);
  LColumn.Name := AColumnName;
  LColumn.Position := 0;
  ATable.PrimaryKey.Fields.Add('000000', LColumn);
end;

procedure TTestComparePolicy.AddIndexe(ATable: TTableMIK;
  const AName, AColumnName: String; AUnique: Boolean);
var
  LIndexe: TIndexeKeyMIK;
  LColumn: TColumnMIK;
begin
  LIndexe := TIndexeKeyMIK.Create(ATable);
  LIndexe.Name := AName;
  LIndexe.Unique := AUnique;
  LColumn := TColumnMIK.Create(ATable);
  LColumn.Name := AColumnName;
  LColumn.Position := 0;
  LIndexe.Fields.Add('000000', LColumn);
  ATable.IndexeKeys.Add(AName, LIndexe);
end;

function TTestComparePolicy.CountCommands(AClass: TClass): Integer;
var
  LCommand: TDDLCommand;
begin
  Result := 0;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Inc(Result);
end;

function TTestComparePolicy.HasCommand(AClass: TClass): Boolean;
begin
  Result := CountCommands(AClass) > 0;
end;

function TTestComparePolicy.SuppressedContains(const AText: String): Boolean;
var
  LItem: String;
begin
  Result := False;
  for LItem in FFactory.SuppressedCommands do
    if Pos(AText, LItem) > 0 then
      Exit(True);
end;

procedure TTestComparePolicy.BuildColumnScenario(out AMaster,
  ATarget: TCatalogMetadataMIK);
var
  LTable: TTableMIK;
begin
  // MASTER: CLIENTE(ID, NOME(60), EMAIL(100)) + PK_CLIENTE(ID).
  AMaster := TCatalogMetadataMIK.Create;
  LTable := AddTable(AMaster, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', 60, True);
  AddColumn(LTable, 'EMAIL', 2, 'VARCHAR(%l)', 100, False);
  SetPrimaryKey(LTable, 'PK_CLIENTE', 'ID');

  // TARGET: CLIENTE(ID, NOME(30 -> ALTER), OBSOLETO(10 -> DROP)) e SEM PK.
  ATarget := TCatalogMetadataMIK.Create;
  LTable := AddTable(ATarget, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', 30, True);
  AddColumn(LTable, 'OBSOLETO', 2, 'VARCHAR(%l)', 10, False);
end;

procedure TTestComparePolicy.BuildIndexRecreateScenario(out AMaster,
  ATarget: TCatalogMetadataMIK);
var
  LTable: TTableMIK;
begin
  // MASTER: PEDIDO(ID) + IDX_PEDIDO UNIQUE.
  AMaster := TCatalogMetadataMIK.Create;
  LTable := AddTable(AMaster, 'PEDIDO');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddIndexe(LTable, 'IDX_PEDIDO', 'ID', True);

  // TARGET: PEDIDO(ID) + IDX_PEDIDO N�O UNIQUE -> diverge -> recreate (par).
  ATarget := TCatalogMetadataMIK.Create;
  LTable := AddTable(ATarget, 'PEDIDO');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddIndexe(LTable, 'IDX_PEDIDO', 'ID', False);
end;

procedure TTestComparePolicy.Policy_FullProfile_AllowsEverything;
var
  LPolicy: TComparePolicy;
  LOperation: TDDLOperation;
begin
  LPolicy := TComparePolicy.FullProfile;
  for LOperation := Low(TDDLOperation) to High(TDDLOperation) do
    Assert.IsTrue(LPolicy.Allows(LOperation),
      'FullProfile deveria permitir toda opera��o');
end;

procedure TTestComparePolicy.Policy_JanusOrmProfile_AllowsOnlyAdditiveCreates;
var
  LPolicy: TComparePolicy;
begin
  LPolicy := TComparePolicy.JanusOrmProfile;
  // Permitidas: as quatro cria��es aditivas.
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreateTable), 'CreateTable');
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreateColumn), 'CreateColumn');
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreatePrimaryKey), 'CreatePrimaryKey');
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.CreateForeignKey), 'CreateForeignKey');
  // Bloqueadas: drops e alters.
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropTable), 'DropTable');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropColumn), 'DropColumn');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.AlterColumn), 'AlterColumn');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropPrimaryKey), 'DropPrimaryKey');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.DropForeignKey), 'DropForeignKey');
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.CreateIndexe), 'CreateIndexe');
end;

procedure TTestComparePolicy.Janus_SuppressesDropAndAlter_EmitsCreates;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  BuildColumnScenario(LMaster, LTarget);
  FFactory := TTestableFactory.Create(dnFirebird);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.Generate(LMaster, LTarget);

  // Cria��es aditivas s�o emitidas.
  Assert.IsTrue(HasCommand(TDDLCommandCreateColumn),
    'CREATE COLUMN EMAIL deveria ser emitido');
  Assert.IsTrue(HasCommand(TDDLCommandCreatePrimaryKey),
    'CREATE PRIMARY KEY deveria ser emitido (target sem PK)');
  // Muta��es destrutivas s�o suprimidas.
  Assert.IsFalse(HasCommand(TDDLCommandDropColumn),
    'DROP COLUMN nunca deve ser emitido no perfil Janus');
  Assert.IsFalse(HasCommand(TDDLCommandAlterColumn),
    'ALTER COLUMN nunca deve ser emitido no perfil Janus');
  // Relat�rio de auditoria registra o que foi bloqueado.
  Assert.IsTrue(SuppressedContains('DROP COLUMN'),
    'SuppressedCommands deveria relatar o DROP COLUMN');
  Assert.IsTrue(SuppressedContains('ALTER COLUMN'),
    'SuppressedCommands deveria relatar o ALTER COLUMN');
end;

procedure TTestComparePolicy.Janus_DropCreatePair_SuppressedEntirely;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  BuildIndexRecreateScenario(LMaster, LTarget);
  FFactory := TTestableFactory.Create(dnFirebird);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.Generate(LMaster, LTarget);

  // O par inteiro � suprimido: nem drop nem create do �ndice.
  Assert.IsFalse(HasCommand(TDDLCommandDropIndexe),
    'DROP INDEXE do par n�o deveria ser emitido');
  Assert.IsFalse(HasCommand(TDDLCommandCreateIndexe),
    'CREATE INDEXE do par n�o deveria ser emitido (sem create �rf�o)');
  Assert.IsTrue(SuppressedContains('RECREATE INDEXE'),
    'SuppressedCommands deveria relatar o par suprimido');
end;

procedure TTestComparePolicy.Full_DropCreatePair_BothEmitted;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  BuildIndexRecreateScenario(LMaster, LTarget);
  FFactory := TTestableFactory.Create(dnFirebird);
  // Policy default = FullProfile.
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandDropIndexe),
    'FullProfile deveria emitir o DROP INDEXE do par');
  Assert.IsTrue(HasCommand(TDDLCommandCreateIndexe),
    'FullProfile deveria emitir o CREATE INDEXE do par');
  Assert.AreEqual(0, Length(FFactory.SuppressedCommands),
    'FullProfile n�o deveria suprimir nada');
end;

procedure TTestComparePolicy.Full_MatchesCurrentBehavior_NoSuppression;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  BuildColumnScenario(LMaster, LTarget);
  FFactory := TTestableFactory.Create(dnFirebird);
  // Policy default = FullProfile (comportamento hist�rico).
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandCreateColumn), 'CREATE COLUMN');
  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn), 'ALTER COLUMN');
  Assert.IsTrue(HasCommand(TDDLCommandDropColumn), 'DROP COLUMN');
  Assert.IsTrue(HasCommand(TDDLCommandCreatePrimaryKey), 'CREATE PRIMARY KEY');
  Assert.AreEqual(0, Length(FFactory.SuppressedCommands),
    'FullProfile n�o deveria suprimir nada');
end;

procedure TTestComparePolicy.Execute_RejectsCommandNotAllowedByPolicy;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Gera com FullProfile (lista cont�m DROP/ALTER COLUMN)...
  BuildColumnScenario(LMaster, LTarget);
  FFactory := TTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);
  Assert.IsTrue(HasCommand(TDDLCommandDropColumn),
    'pr�-condi��o: a lista deveria conter um DROP COLUMN');

  // ...depois aperta a policy e tenta executar: dupla checagem deve recusar.
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  Assert.WillRaise(
    procedure
    begin
      FFactory.ExecuteCommands;
    end,
    Exception,
    'ExecuteCommands deveria recusar comando n�o permitido pela policy');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestComparePolicy);

end.
