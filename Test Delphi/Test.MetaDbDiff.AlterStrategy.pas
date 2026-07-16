{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Safe / configurable ALTER COLUMN strategy tests (FRENTE 11) WITHOUT a live
  database. Builds the master/target MIK catalogs by hand and drives the real
  GenerateDDLCommands (which runs ApplyAlterStrategy + the sequencer) so the
  transformation runs exactly as it does in production. The testable subclass
  only supplies empty ExtractDatabase / ExecuteDDLCommands bodies and hands the
  pre-built catalogs to GenerateDDLCommands.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.AlterStrategy;

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
  MetaDbDiff.DDL.AlterStrategy,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  // drivers register themselves in their initialization:
  MetaDbDiff.DDL.Generator.Firebird,
  MetaDbDiff.DDL.Generator.SQLite,
  MetaDbDiff.DDL.Generator.MySQL,
  MetaDbDiff.DDL.Generator.PostgreSQL;

type
  /// <summary>Testable factory: hand-built catalogs + empty abstract bodies.</summary>
  TTestableAlterFactory = class(TDatabaseFactory)
  protected
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(ADriverName: TDriverName); override;
    procedure Generate(AMaster, ATarget: TCatalogMetadataMIK);
  end;

  [TestFixture]
  TTestAlterStrategy = class
  private
    FFactory: TTestableAlterFactory;
    function AddTable(ACatalog: TCatalogMetadataMIK; const AName: String): TTableMIK;
    function AddColumn(ATable: TTableMIK; const AName: String; APosition: Integer;
      const ATypeName: String; ASize: Integer; ANotNull: Boolean;
      const ADefault: String = ''): TColumnMIK;
    function CountCommands(AClass: TClass): Integer;
    function HasCommand(AClass: TClass): Boolean;
    function IndexOfCommand(AClass: TClass): Integer;
    function IndexOfCommandWithSql(AClass: TClass; const ASub: String): Integer;
    function FirstCommand(AClass: TClass): TDDLCommand;
    function SuppressedContains(const AText: String): Boolean;
    /// <summary>CLIENTE: ID INTEGER, NOME VARCHAR(ASizeMaster/ASizeTarget) NULLABLE.</summary>
    procedure BuildTypeScenario(out AMaster, ATarget: TCatalogMetadataMIK;
      ASizeMaster, ASizeTarget: Integer);
    /// <summary>CLIENTE: NOME VARCHAR(ASizeMaster/ASizeTarget) NOT NULL both sides
    ///   (narrowing + NOT NULL), same DefaultValue on both.</summary>
    procedure BuildTypeNotNullScenario(out AMaster, ATarget: TCatalogMetadataMIK;
      ASizeMaster, ASizeTarget: Integer; const ADefault: String);
    /// <summary>CLIENTE: FLAG VARCHAR(1); master NOT NULL, target nullable.</summary>
    procedure BuildNotNullScenario(out AMaster, ATarget: TCatalogMetadataMIK;
      const AMasterDefault: String);
  public
    [TearDown]
    procedure TearDown;
    // ---- default strategy is a no-op (historical behavior intact) -------
    [Test]
    procedure Default_InPlace_KeepsSingleAlterColumn;
    // ---- rebuild: unsafe type change (narrowing) ------------------------
    [Test]
    procedure Rebuild_Narrowing_EmitsAddCopyDropRenameInOrderSamePhase;
    [Test]
    procedure Rebuild_Narrowing_TempColumnIsNullable;
    [Test]
    procedure Rebuild_NotNullNarrowing_FinalSetNotNullAfterRename;
    [Test]
    procedure Rebuild_Widening_StaysInPlace;
    // ---- rebuild: per-dialect cast / rename -----------------------------
    [Test]
    procedure Rebuild_MySQL_CastUsesCharNotVarchar;
    [Test]
    procedure Rebuild_PostgreSQL_RenameUsesRenameColumn;
    // ---- rebuild: NOT NULL on a populated column ------------------------
    [Test]
    procedure Rebuild_NotNullWithoutDefault_InPlaceWithWarning;
    [Test]
    procedure Rebuild_NotNullWithDefault_BackfillThenAlter;
    // ---- SQLite documented limitation -----------------------------------
    [Test]
    procedure Rebuild_SQLite_NarrowingStaysInPlace;
    // ---- policy: Janus never rebuilds; fail-closed mapping --------------
    [Test]
    procedure Janus_RebuildStrategy_EmitsNothing;
    [Test]
    procedure Policy_RebuildCommands_MappedNotUnknown;
    [Test]
    procedure Policy_FullProfile_IncludesRebuildColumn;
  end;

implementation

{ TTestableAlterFactory }

constructor TTestableAlterFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
end;

procedure TTestableAlterFactory.ExtractDatabase;
begin
  // Nada a extrair: os catalogos ja vem montados a mao.
end;

procedure TTestableAlterFactory.ExecuteDDLCommands;
begin
  // Sem banco: a execucao real nao e exercida aqui.
end;

procedure TTestableAlterFactory.Generate(AMaster, ATarget: TCatalogMetadataMIK);
begin
  // O ancestral libera FCatalogMaster/FCatalogTarget no destroy; passamos a posse.
  FCatalogMaster := AMaster;
  FCatalogTarget := ATarget;
  GenerateDDLCommands(FCatalogMaster, FCatalogTarget);
end;

{ TTestAlterStrategy }

procedure TTestAlterStrategy.TearDown;
begin
  FreeAndNil(FFactory);
end;

function TTestAlterStrategy.AddTable(ACatalog: TCatalogMetadataMIK;
  const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  ACatalog.Tables.Add(AName, Result);
end;

function TTestAlterStrategy.AddColumn(ATable: TTableMIK; const AName: String;
  APosition: Integer; const ATypeName: String; ASize: Integer; ANotNull: Boolean;
  const ADefault: String): TColumnMIK;
begin
  Result := TColumnMIK.Create(ATable);
  Result.Name := AName;
  Result.Position := APosition;
  Result.FieldType := ftUnknown;
  Result.TypeName := ATypeName;
  Result.Size := ASize;
  Result.NotNull := ANotNull;
  Result.DefaultValue := ADefault;
  ATable.Fields.Add(FormatFloat('000000', APosition), Result);
end;

function TTestAlterStrategy.CountCommands(AClass: TClass): Integer;
var
  LCommand: TDDLCommand;
begin
  Result := 0;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Inc(Result);
end;

function TTestAlterStrategy.HasCommand(AClass: TClass): Boolean;
begin
  Result := CountCommands(AClass) > 0;
end;

function TTestAlterStrategy.IndexOfCommand(AClass: TClass): Integer;
var
  LList: TArray<TDDLCommand>;
  LFor: Integer;
begin
  Result := -1;
  LList := FFactory.GetCommandList;
  for LFor := 0 to High(LList) do
    if LList[LFor] is AClass then
      Exit(LFor);
end;

function TTestAlterStrategy.IndexOfCommandWithSql(AClass: TClass;
  const ASub: String): Integer;
var
  LList: TArray<TDDLCommand>;
  LFor: Integer;
begin
  Result := -1;
  LList := FFactory.GetCommandList;
  for LFor := 0 to High(LList) do
    if (LList[LFor] is AClass) and
       (Pos(UpperCase(ASub), UpperCase(LList[LFor].Command)) > 0) then
      Exit(LFor);
end;

function TTestAlterStrategy.FirstCommand(AClass: TClass): TDDLCommand;
var
  LCommand: TDDLCommand;
begin
  Result := nil;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Exit(LCommand);
end;

function TTestAlterStrategy.SuppressedContains(const AText: String): Boolean;
var
  LItem: String;
begin
  Result := False;
  for LItem in FFactory.SuppressedCommands do
    if Pos(AText, LItem) > 0 then
      Exit(True);
end;

procedure TTestAlterStrategy.BuildTypeScenario(out AMaster,
  ATarget: TCatalogMetadataMIK; ASizeMaster, ASizeTarget: Integer);
var
  LTable: TTableMIK;
begin
  // NOME e NULLABLE dos dois lados: isola a divergencia de TIPO (size) do NOT NULL.
  AMaster := TCatalogMetadataMIK.Create;
  LTable := AddTable(AMaster, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', ASizeMaster, False);

  ATarget := TCatalogMetadataMIK.Create;
  LTable := AddTable(ATarget, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', ASizeTarget, False);
end;

procedure TTestAlterStrategy.BuildTypeNotNullScenario(out AMaster,
  ATarget: TCatalogMetadataMIK; ASizeMaster, ASizeTarget: Integer;
  const ADefault: String);
var
  LTable: TTableMIK;
begin
  // Narrowing (rebuild de tipo) COM NOT NULL dos dois lados e mesmo default:
  // exercita o passo final SET NOT NULL apos o rename.
  AMaster := TCatalogMetadataMIK.Create;
  LTable := AddTable(AMaster, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', ASizeMaster, True, ADefault);

  ATarget := TCatalogMetadataMIK.Create;
  LTable := AddTable(ATarget, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'NOME', 1, 'VARCHAR(%l)', ASizeTarget, True, ADefault);
end;

procedure TTestAlterStrategy.BuildNotNullScenario(out AMaster,
  ATarget: TCatalogMetadataMIK; const AMasterDefault: String);
var
  LTable: TTableMIK;
begin
  // Mesmo tipo/size dos dois lados: so o NOT NULL diverge (master NOT NULL,
  // target nullable), com o MESMO default nos dois lados (isola do AlterDefault).
  AMaster := TCatalogMetadataMIK.Create;
  LTable := AddTable(AMaster, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'FLAG', 1, 'VARCHAR(%l)', 1, True, AMasterDefault);

  ATarget := TCatalogMetadataMIK.Create;
  LTable := AddTable(ATarget, 'CLIENTE');
  AddColumn(LTable, 'ID', 0, 'INTEGER', 0, True);
  AddColumn(LTable, 'FLAG', 1, 'VARCHAR(%l)', 1, False, AMasterDefault);
end;

procedure TTestAlterStrategy.Default_InPlace_KeepsSingleAlterColumn;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Narrowing (30 < 60) that WOULD require a rebuild - but the default strategy
  // is acsInPlace, so nothing is transformed: the single ALTER COLUMN survives.
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  // AlterColumnStrategy default = acsInPlace.
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn),
    'ALTER COLUMN deve permanecer in-place no default acsInPlace');
  Assert.IsFalse(HasCommand(TDDLCommandCopyColumnData),
    'nenhum comando de copia deve ser emitido no default');
  Assert.IsFalse(HasCommand(TDDLCommandRenameColumn),
    'nenhum rename deve ser emitido no default');
  Assert.IsFalse(HasCommand(TDDLCommandDropColumnRebuild),
    'nenhum drop de rebuild deve ser emitido no default');
end;

procedure TTestAlterStrategy.Rebuild_Narrowing_EmitsAddCopyDropRenameInOrderSamePhase;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LiCreate, LiCopy, LiDrop, LiRename: Integer;
  LCopy: TDDLCommand;
begin
  // Narrowing VARCHAR(60)->VARCHAR(30) on Firebird: unsafe in-place -> rebuild.
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  // The single ALTER COLUMN is superseded by the 4-step sequence.
  Assert.IsFalse(HasCommand(TDDLCommandAlterColumn),
    'o ALTER COLUMN inseguro deve ser substituido pela sequencia de rebuild');
  Assert.AreEqual(1, CountCommands(TDDLCommandCreateColumnRebuild), 'CREATE tmp');
  Assert.AreEqual(1, CountCommands(TDDLCommandCopyColumnData), 'COPY data');
  Assert.AreEqual(1, CountCommands(TDDLCommandDropColumnRebuild), 'DROP original');
  Assert.AreEqual(1, CountCommands(TDDLCommandRenameColumn), 'RENAME tmp');

  // Order (same COLUMNS phase, consecutive): add -> copy -> drop -> rename.
  LiCreate := IndexOfCommand(TDDLCommandCreateColumnRebuild);
  LiCopy   := IndexOfCommand(TDDLCommandCopyColumnData);
  LiDrop   := IndexOfCommand(TDDLCommandDropColumnRebuild);
  LiRename := IndexOfCommand(TDDLCommandRenameColumn);
  Assert.AreEqual(LiCreate + 1, LiCopy, 'copy logo apos create');
  Assert.AreEqual(LiCreate + 2, LiDrop, 'drop logo apos copy');
  Assert.AreEqual(LiCreate + 3, LiRename, 'rename logo apos drop');

  // The copy really CASTs the original column into the temp column.
  LCopy := FirstCommand(TDDLCommandCopyColumnData);
  Assert.IsTrue(Pos('CAST', UpperCase(LCopy.Command)) > 0, 'copia deve usar CAST');
  Assert.IsTrue(Pos('NOME_MDBTMP', UpperCase(LCopy.Command)) > 0,
    'copia deve escrever na coluna temporaria');
  // The rename brings the temp name back to the original.
  Assert.IsTrue(Pos('NOME_MDBTMP TO NOME',
    UpperCase(FirstCommand(TDDLCommandRenameColumn).Command)) > 0,
    'rename Firebird deve ser ALTER COLUMN NOME_MDBTMP TO NOME');
end;

procedure TTestAlterStrategy.Rebuild_Narrowing_TempColumnIsNullable;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LCreateSql: String;
begin
  // Regressao do BLOQUEANTE: a coluna temporaria NUNCA pode ser criada NOT NULL
  // (um ADD NOT NULL falharia em tabela populada antes mesmo do CAST). O teste
  // asserta o TEXTO SQL do CREATE tmp - nao so a classe do comando.
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  LCreateSql := UpperCase(FirstCommand(TDDLCommandCreateColumnRebuild).Command);
  Assert.IsTrue(Pos('NOME_MDBTMP', LCreateSql) > 0, 'CREATE deve ser da coluna tmp');
  Assert.IsFalse(Pos('NOT NULL', LCreateSql) > 0,
    'a coluna temporaria DEVE ser criada NULLABLE (sem NOT NULL)');
end;

procedure TTestAlterStrategy.Rebuild_NotNullNarrowing_FinalSetNotNullAfterRename;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LiCreate, LiCast, LiDrop, LiRename, LiBackfill, LiAlter: Integer;
  LCreateSql: String;
begin
  // Narrowing + NOT NULL + default: tmp nullable, copy, drop, rename, backfill,
  // e por FIM o SET NOT NULL (ALTER original reusado) - nesta ordem, mesma fase.
  BuildTypeNotNullScenario(LMaster, LTarget, 30, 60, 'X');
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  // tmp ainda NULLABLE mesmo com master NOT NULL.
  LCreateSql := UpperCase(FirstCommand(TDDLCommandCreateColumnRebuild).Command);
  Assert.IsFalse(Pos('NOT NULL', LCreateSql) > 0,
    'tmp nullable mesmo quando o destino e NOT NULL');

  LiCreate   := IndexOfCommand(TDDLCommandCreateColumnRebuild);
  LiCast     := IndexOfCommandWithSql(TDDLCommandCopyColumnData, 'CAST');
  LiDrop     := IndexOfCommand(TDDLCommandDropColumnRebuild);
  LiRename   := IndexOfCommand(TDDLCommandRenameColumn);
  LiBackfill := IndexOfCommandWithSql(TDDLCommandCopyColumnData, 'IS NULL');
  LiAlter    := IndexOfCommand(TDDLCommandAlterColumn);

  Assert.IsTrue(LiCast > LiCreate, 'copy apos create');
  Assert.IsTrue(LiDrop > LiCast, 'drop apos copy');
  Assert.IsTrue(LiRename > LiDrop, 'rename apos drop');
  Assert.IsTrue(LiBackfill > LiRename, 'backfill apos rename');
  Assert.IsTrue(LiAlter > LiBackfill, 'SET NOT NULL (ALTER) por ultimo, apos o backfill');
  // O backfill preenche as linhas NULL com o default antes do SET NOT NULL.
  Assert.IsTrue(Pos('IS NULL',
    UpperCase(FFactory.GetCommandList[LiBackfill].Command)) > 0, 'backfill WHERE IS NULL');
end;

procedure TTestAlterStrategy.Rebuild_MySQL_CastUsesCharNotVarchar;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LCastSql: String;
begin
  // MySQL: CAST(x AS VARCHAR(n)) e ERRO; o override deve mapear para CHAR(n).
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnMySQL);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandCopyColumnData), 'MySQL narrowing deve gerar rebuild');
  LCastSql := UpperCase(FirstCommand(TDDLCommandCopyColumnData).Command);
  Assert.IsTrue(Pos('CAST', LCastSql) > 0, 'deve usar CAST');
  Assert.IsTrue(Pos('CHAR(30)', LCastSql) > 0, 'CAST do MySQL deve usar CHAR(30)');
  Assert.IsFalse(Pos('VARCHAR', LCastSql) > 0, 'CAST do MySQL nao pode usar VARCHAR');
  // MySQL 8.0+ RENAME COLUMN.
  Assert.IsTrue(Pos('RENAME COLUMN',
    UpperCase(FirstCommand(TDDLCommandRenameColumn).Command)) > 0,
    'rename MySQL deve usar RENAME COLUMN');
end;

procedure TTestAlterStrategy.Rebuild_PostgreSQL_RenameUsesRenameColumn;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnPostgreSQL);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandCopyColumnData), 'PG narrowing deve gerar rebuild');
  Assert.IsTrue(Pos('CAST',
    UpperCase(FirstCommand(TDDLCommandCopyColumnData).Command)) > 0, 'PG copy usa CAST');
  Assert.IsTrue(Pos('RENAME COLUMN NOME_MDBTMP TO NOME',
    UpperCase(FirstCommand(TDDLCommandRenameColumn).Command)) > 0,
    'rename PG deve ser RENAME COLUMN NOME_MDBTMP TO NOME');
end;

procedure TTestAlterStrategy.Rebuild_Widening_StaysInPlace;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Widening VARCHAR(30)->VARCHAR(60) is safe in-place on Firebird: no rebuild.
  BuildTypeScenario(LMaster, LTarget, 60, 30);
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn),
    'alargamento de VARCHAR e seguro: ALTER COLUMN in-place');
  Assert.IsFalse(HasCommand(TDDLCommandCopyColumnData),
    'alargamento nao deve gerar rebuild');
end;

procedure TTestAlterStrategy.Rebuild_NotNullWithoutDefault_InPlaceWithWarning;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LAlter: TDDLCommand;
begin
  BuildNotNullScenario(LMaster, LTarget, '');   // no default on either side
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn),
    'NOT NULL sem default: mantem ALTER in-place (nao ha como backfill)');
  Assert.IsFalse(HasCommand(TDDLCommandCopyColumnData),
    'sem default nao ha backfill');
  LAlter := FirstCommand(TDDLCommandAlterColumn);
  Assert.IsTrue(Pos('RISK', UpperCase(LAlter.Warning)) > 0,
    'o ALTER deve carregar um aviso de risco no Warning (nunca silencioso)');
end;

procedure TTestAlterStrategy.Rebuild_NotNullWithDefault_BackfillThenAlter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LiCopy, LiAlter: Integer;
  LBackfill: TDDLCommand;
begin
  BuildNotNullScenario(LMaster, LTarget, 'S');  // same default both sides
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandCopyColumnData),
    'NOT NULL com default: deve emitir o backfill');
  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn),
    'o ALTER (SET NOT NULL) e mantido apos o backfill');
  Assert.IsFalse(HasCommand(TDDLCommandCreateColumnRebuild),
    'NOT NULL com default nao faz rebuild de tipo');
  Assert.IsFalse(HasCommand(TDDLCommandRenameColumn),
    'NOT NULL com default nao renomeia');

  // Backfill runs BEFORE the ALTER (same phase, preserved order).
  LiCopy  := IndexOfCommand(TDDLCommandCopyColumnData);
  LiAlter := IndexOfCommand(TDDLCommandAlterColumn);
  Assert.IsTrue(LiCopy < LiAlter, 'backfill deve preceder o SET NOT NULL');

  LBackfill := FirstCommand(TDDLCommandCopyColumnData);
  Assert.IsTrue(Pos('IS NULL', UpperCase(LBackfill.Command)) > 0,
    'o backfill deve atualizar apenas as linhas NULL');
end;

procedure TTestAlterStrategy.Rebuild_SQLite_NarrowingStaysInPlace;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // SQLite cannot DROP COLUMN / ALTER TYPE pre-3.35 (needs a full TABLE rebuild,
  // out of scope): _RequiresRebuild returns False -> in-place ALTER preserved.
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnSQLite);
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterColumn),
    'SQLite: mantem ALTER in-place (rebuild de coluna nao basta)');
  Assert.IsFalse(HasCommand(TDDLCommandCopyColumnData),
    'SQLite: nao emite sequencia de rebuild');
  Assert.IsFalse(HasCommand(TDDLCommandDropColumnRebuild),
    'SQLite: nao dropa coluna');
end;

procedure TTestAlterStrategy.Janus_RebuildStrategy_EmitsNothing;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Perfil restrito + estrategia de rebuild: o ALTER e suprimido na origem
  // (ActionAlterColumn), entao o rebuilder nao tem o que transformar -> NADA.
  BuildTypeScenario(LMaster, LTarget, 30, 60);
  FFactory := TTestableAlterFactory.Create(dnFirebird);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.AlterColumnStrategy := acsRebuildWhenRequired;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandAlterColumn), 'nenhum ALTER no perfil Janus');
  Assert.IsFalse(HasCommand(TDDLCommandCreateColumnRebuild), 'nenhum rebuild no Janus');
  Assert.IsFalse(HasCommand(TDDLCommandCopyColumnData), 'nenhuma copia no Janus');
  Assert.IsFalse(HasCommand(TDDLCommandDropColumnRebuild), 'nenhum drop de rebuild no Janus');
  Assert.IsFalse(HasCommand(TDDLCommandRenameColumn), 'nenhum rename no Janus');
  Assert.IsTrue(SuppressedContains('ALTER COLUMN'),
    'a auditoria deve registrar o ALTER COLUMN suprimido');
end;

procedure TTestAlterStrategy.Policy_RebuildCommands_MappedNotUnknown;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LColumn: TColumnMIK;
  LCmd: TDDLCommand;
  LOp: TDDLOperation;
  LFull, LJanus: TComparePolicy;
begin
  // Um comando de rebuild NAO pode ser 'ckUnknown' (senao seria negado sempre,
  // ate no FullProfile). Deve ser ckMutation + RebuildColumn.
  LMaster := TCatalogMetadataMIK.Create;
  LTarget := TCatalogMetadataMIK.Create;
  try
    LColumn := TColumnMIK.Create(AddTable(LMaster, 'CLIENTE'));
    LColumn.Name := 'NOME_MDBTMP';
    LColumn.TypeName := 'VARCHAR(%l)';
    LColumn.Size := 30;
    LMaster.Tables['CLIENTE'].Fields.Add('000001', LColumn);

    LCmd := TDDLCommandRenameColumn.Create(LColumn, 'NOME');
    try
      Assert.AreEqual(Ord(ckMutation), Ord(ClassifyDDLCommand(LCmd, LOp)),
        'RenameColumn deve ser classificado como mutacao conhecida');
      Assert.AreEqual(Ord(TDDLOperation.RebuildColumn), Ord(LOp),
        'RenameColumn deve mapear para RebuildColumn');

      LFull := TComparePolicy.FullProfile;
      LJanus := TComparePolicy.JanusOrmProfile;
      Assert.IsTrue(LFull.Allows(LCmd), 'FullProfile deve permitir o rebuild');
      Assert.IsFalse(LJanus.Allows(LCmd), 'JanusOrmProfile deve negar o rebuild');
    finally
      LCmd.Free;
    end;
  finally
    LMaster.Free;
    LTarget.Free;
  end;
end;

procedure TTestAlterStrategy.Policy_FullProfile_IncludesRebuildColumn;
var
  LPolicy: TComparePolicy;
begin
  LPolicy := TComparePolicy.FullProfile;
  Assert.IsTrue(LPolicy.Allows(TDDLOperation.RebuildColumn),
    'FullProfile deve incluir a nova operacao RebuildColumn');
  LPolicy := TComparePolicy.JanusOrmProfile;
  Assert.IsFalse(LPolicy.Allows(TDDLOperation.RebuildColumn),
    'JanusOrmProfile NAO deve incluir RebuildColumn');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAlterStrategy);

end.
