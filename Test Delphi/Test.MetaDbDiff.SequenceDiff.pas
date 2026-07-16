{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  FRENTE 10 - Sequence diff (ALTER SEQUENCE) + script/check normalization.

  Rodam SEM banco: montam os catalogos MIK master/target a mao e dirigem o
  GenerateDDLCommands real do TDatabaseFactory. Os cenarios de ASSIMETRIA
  replicam fielmente as formas produzidas pelos dois caminhos reais:
    * TARGET como o extractor Firebird 2.5 entrega (so name+description; Increment
      NAO extraido => 0, o sentinela de "desconhecido");
    * MASTER como o modelo (TModelMetadata) entrega (Increment do atributo
      [Sequence]; view do atributo [View] com Script vazio).
  Cobrem: sentinela de increment (0 => nunca ALTER); AlterSequence quando o target
  TEM increment e difere; InitialValue opt-in; NormalizeScript (inclusive
  whitespace preservado dentro de literais); StripCreateViewPrefix; CHECK master
  canonizado; views em model-mode (sem DROP de orfa, sem recreate de corpo vazio);
  policy mapeando AlterSequence.

  Estilo (regra do dono): fachada TMetadataNormalizer (class functions); metodos
  private com prefixo '_'; sem variavel de loop 'I'.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.SequenceDiff;

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
  MetaDbDiff.Metadata.Normalize,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator.Firebird;

type
  /// <summary>
  ///   Subclasse de teste: expoe GenerateDDLCommands sobre catalogos montados a
  ///   mao e fornece corpos vazios para os metodos abstratos herdados.
  /// </summary>
  TSeqTestableFactory = class(TDatabaseFactory)
  protected
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(ADriverName: TDriverName); override;
    procedure Generate(AMaster, ATarget: TCatalogMetadataMIK);
    /// <summary> Liga o modo Model-vs-Database (FModelForDatabase protegido). </summary>
    procedure SetModelForDatabase(AValue: Boolean);
  end;

  [TestFixture]
  TTestSequenceDiff = class
  private
    FFactory: TSeqTestableFactory;
    function _AddTable(ACatalog: TCatalogMetadataMIK; const AName: String): TTableMIK;
    procedure _AddSequence(ACatalog: TCatalogMetadataMIK; const AName: String;
      AInitialValue, AIncrement: Integer);
    procedure _AddView(ACatalog: TCatalogMetadataMIK; const AName, AScript: String);
    procedure _AddTrigger(ATable: TTableMIK; const AName, AScript: String);
    procedure _AddCheck(ATable: TTableMIK; const AName, ACondition: String);
    function _CountCommands(AClass: TClass): Integer;
    function _HasCommand(AClass: TClass): Boolean;
    function _SuppressedContains(const AText: String): Boolean;
  public
    [TearDown]
    procedure TearDown;
    // ---- pure helpers (fachada TMetadataNormalizer) ----------------------
    [Test]
    procedure NormalizeScript_CollapsesWhitespaceAndTrims;
    [Test]
    procedure NormalizeScript_PreservesWhitespaceInsideStringLiteral;
    [Test]
    procedure CanonicalizeCheck_StripsKeywordAndBalancedParens;
    [Test]
    procedure StripCreateViewPrefix_ReturnsBodyOnly;
    // ---- sequence: increment ---------------------------------------------
    [Test]
    procedure Sequence_IncrementDiffers_EmitsAlter_Full;
    [Test]
    procedure Sequence_IncrementDiffers_Suppressed_Janus;
    // ---- sequence: asymmetry / sentinel (increment 0 = unknown) ----------
    [Test]
    procedure Sequence_TargetIncrementUnknown_NoAlter;
    [Test]
    procedure Sequence_TargetIncrementKnownDiffers_EmitsAlter;
    // ---- sequence: initial value (opt-in) --------------------------------
    [Test]
    procedure Sequence_InitialValueDiffers_NotComparedByDefault;
    [Test]
    procedure Sequence_InitialValueDiffers_ComparedWithFlag;
    // ---- script normalization --------------------------------------------
    [Test]
    procedure View_EquivalentScriptWhitespace_NoRecreate;
    [Test]
    procedure View_TrulyDifferentScript_Recreated;
    [Test]
    procedure Trigger_EquivalentScriptWhitespace_NoRecreate;
    // ---- views in Model-vs-Database mode ---------------------------------
    [Test]
    procedure View_ModelMode_DoesNotDropUnmappedView;
    [Test]
    procedure View_ModelMode_EmptyScriptView_Skipped;
    // ---- check master canonicalization -----------------------------------
    [Test]
    procedure Check_MasterExtraParens_CanonicalMatch_NoAlter;
    [Test]
    procedure Check_MasterDifferentCondition_Alter;
    // ---- policy mapping (fail-closed keeps rejecting only the unknown) ----
    [Test]
    procedure Policy_AlterSequence_MappedFullAllowsJanusDenies;
  end;

implementation

{ TSeqTestableFactory }

constructor TSeqTestableFactory.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
end;

procedure TSeqTestableFactory.ExtractDatabase;
begin
  // Nada a extrair: catalogos ja vem montados a mao.
end;

procedure TSeqTestableFactory.ExecuteDDLCommands;
begin
  // Sem banco: execucao real nao e exercida aqui.
end;

procedure TSeqTestableFactory.Generate(AMaster, ATarget: TCatalogMetadataMIK);
begin
  FCatalogMaster := AMaster;
  FCatalogTarget := ATarget;
  GenerateDDLCommands(FCatalogMaster, FCatalogTarget);
end;

procedure TSeqTestableFactory.SetModelForDatabase(AValue: Boolean);
begin
  FModelForDatabase := AValue;
end;

{ TTestSequenceDiff }

procedure TTestSequenceDiff.TearDown;
begin
  FreeAndNil(FFactory);
end;

function TTestSequenceDiff._AddTable(ACatalog: TCatalogMetadataMIK;
  const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  ACatalog.Tables.Add(UpperCase(AName), Result);
end;

procedure TTestSequenceDiff._AddSequence(ACatalog: TCatalogMetadataMIK;
  const AName: String; AInitialValue, AIncrement: Integer);
var
  LSequence: TSequenceMIK;
begin
  LSequence := TSequenceMIK.Create(ACatalog);
  LSequence.Name := AName;
  LSequence.InitialValue := AInitialValue;
  LSequence.Increment := AIncrement;
  ACatalog.Sequences.Add(UpperCase(AName), LSequence);
end;

procedure TTestSequenceDiff._AddView(ACatalog: TCatalogMetadataMIK;
  const AName, AScript: String);
var
  LView: TViewMIK;
begin
  LView := TViewMIK.Create(ACatalog);
  LView.Name := AName;
  LView.Script := AScript;
  ACatalog.Views.Add(UpperCase(AName), LView);
end;

procedure TTestSequenceDiff._AddTrigger(ATable: TTableMIK;
  const AName, AScript: String);
var
  LTrigger: TTriggerMIK;
begin
  LTrigger := TTriggerMIK.Create(ATable);
  LTrigger.Name := AName;
  LTrigger.Script := AScript;
  ATable.Triggers.Add(UpperCase(AName), LTrigger);
end;

procedure TTestSequenceDiff._AddCheck(ATable: TTableMIK;
  const AName, ACondition: String);
var
  LCheck: TCheckMIK;
begin
  LCheck := TCheckMIK.Create(ATable);
  LCheck.Name := AName;
  LCheck.Condition := ACondition;
  ATable.Checks.Add(UpperCase(AName), LCheck);
end;

function TTestSequenceDiff._CountCommands(AClass: TClass): Integer;
var
  LCommand: TDDLCommand;
begin
  Result := 0;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Inc(Result);
end;

function TTestSequenceDiff._HasCommand(AClass: TClass): Boolean;
begin
  Result := _CountCommands(AClass) > 0;
end;

function TTestSequenceDiff._SuppressedContains(const AText: String): Boolean;
var
  LItem: String;
begin
  Result := False;
  for LItem in FFactory.SuppressedCommands do
    if Pos(AText, LItem) > 0 then
      Exit(True);
end;

{ ---- pure helpers ---------------------------------------------------------- }

procedure TTestSequenceDiff.NormalizeScript_CollapsesWhitespaceAndTrims;
begin
  Assert.AreEqual('SELECT A, B FROM T',
    TMetadataNormalizer.NormalizeScript('  SELECT   A,'#13#10'  B'#9'FROM T  '),
    'runs de espaco/TAB/CRLF devem colapsar num unico espaco e Trim nas bordas');
  Assert.AreEqual(TMetadataNormalizer.NormalizeScript('SELECT A,  B'#13#10'FROM T'),
                  TMetadataNormalizer.NormalizeScript('SELECT A, B FROM T'),
    'scripts equivalentes devem normalizar identicamente');
end;

procedure TTestSequenceDiff.NormalizeScript_PreservesWhitespaceInsideStringLiteral;
begin
  // Fora do literal colapsa; DENTRO das aspas os 3 espacos de 'a   b' ficam.
  Assert.AreEqual('SELECT ''a   b'' , c',
    TMetadataNormalizer.NormalizeScript('SELECT   ''a   b''  ,   c'),
    'whitespace dentro de literal de string deve ser preservado verbatim');
end;

procedure TTestSequenceDiff.CanonicalizeCheck_StripsKeywordAndBalancedParens;
begin
  Assert.AreEqual('AGE > 18', TMetadataNormalizer.CanonicalizeCheckCondition('CHECK ((AGE > 18))'));
  Assert.AreEqual('AGE > 18', TMetadataNormalizer.CanonicalizeCheckCondition('((AGE > 18))'));
  Assert.AreEqual('AGE > 18', TMetadataNormalizer.CanonicalizeCheckCondition('AGE > 18'));
  // Nao descasca parenteses NAO externos (preserva "(A) OR (B)").
  Assert.AreEqual('(A) OR (B)', TMetadataNormalizer.CanonicalizeCheckCondition('CHECK ((A) OR (B))'));
end;

procedure TTestSequenceDiff.StripCreateViewPrefix_ReturnsBodyOnly;
begin
  Assert.AreEqual('SELECT ID, NOME FROM CLIENTE',
    TMetadataNormalizer.StripCreateViewPrefix('CREATE VIEW VW_X AS SELECT ID, NOME FROM CLIENTE'),
    'deve remover "CREATE VIEW <nome> AS" deixando so o corpo');
  Assert.AreEqual('SELECT 1',
    TMetadataNormalizer.StripCreateViewPrefix('CREATE VIEW [dbo].[VW_X] AS SELECT 1'),
    'tolerante a schema/brackets no nome');
  Assert.AreEqual('SELECT 2',
    TMetadataNormalizer.StripCreateViewPrefix('CREATE OR ALTER VIEW VW AS SELECT 2'),
    'tolerante a CREATE OR ALTER VIEW');
  Assert.AreEqual('SELECT 3',
    TMetadataNormalizer.StripCreateViewPrefix('SELECT 3'),
    'sem cabecalho reconhecivel, devolve o corpo intacto');
end;

{ ---- sequence: increment --------------------------------------------------- }

procedure TTestSequenceDiff.Sequence_IncrementDiffers_EmitsAlter_Full;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 1, 2);   // increment 2
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 1, 1);   // increment 1 (extraido) -> diverge

  FFactory := TSeqTestableFactory.Create(dnPostgreSQL); // Policy default = Full
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandAlterSequence),
    'ALTER SEQUENCE deveria ser emitido quando o Increment (extraido) diverge');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateSequence), 'nao deveria criar');
  Assert.IsFalse(_HasCommand(TDDLCommandDropSequence), 'nao deveria dropar');
end;

procedure TTestSequenceDiff.Sequence_IncrementDiffers_Suppressed_Janus;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 1, 2);
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 1, 1);

  FFactory := TSeqTestableFactory.Create(dnPostgreSQL);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandAlterSequence),
    'ALTER SEQUENCE nunca deve ser emitido no perfil Janus');
  Assert.IsTrue(_SuppressedContains('ALTER SEQUENCE'),
    'a auditoria deveria registrar o ALTER SEQUENCE suprimido');
end;

{ ---- sequence: asymmetry / sentinel ---------------------------------------- }

procedure TTestSequenceDiff.Sequence_TargetIncrementUnknown_NoAlter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Cenario real Firebird 2.5: o extractor NAO popula Increment (fica 0), mas o
  // modelo tem Increment=1 do atributo. 1 <> 0 NAO pode disparar ALTER (0 = passo
  // desconhecido). Sem o sentinela isto resetaria a sequence viva a cada diff.
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 1, 1);   // modelo: increment 1
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 0, 0);   // extractor FB2.5: increment "0" (nao extraido)

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandAlterSequence),
    'increment 0 no target = desconhecido: NUNCA deve gerar ALTER (sentinela F10)');
end;

procedure TTestSequenceDiff.Sequence_TargetIncrementKnownDiffers_EmitsAlter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Quando o target TEM o increment extraido (nao-zero) e ele difere, o ALTER e
  // legitimo (ex.: MSSQL/Oracle/PG que populam increment).
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 1, 1);
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 1, 5);   // increment 5 extraido -> diverge de 1

  FFactory := TSeqTestableFactory.Create(dnPostgreSQL);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandAlterSequence),
    'increment extraido (nao-zero) divergente deve gerar ALTER SEQUENCE');
end;

{ ---- sequence: initial value (opt-in) -------------------------------------- }

procedure TTestSequenceDiff.Sequence_InitialValueDiffers_NotComparedByDefault;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Mesmo increment (extraido, nao-zero), InitialValue diferente. Default: nao compara.
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 100, 1);
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 5, 1);

  FFactory := TSeqTestableFactory.Create(dnPostgreSQL);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandAlterSequence),
    'InitialValue NAO deve ser comparado por default (alvo movel em producao)');
end;

procedure TTestSequenceDiff.Sequence_InitialValueDiffers_ComparedWithFlag;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddSequence(LMaster, 'SEQ_PEDIDO', 100, 1);
  LTarget := TCatalogMetadataMIK.Create;
  _AddSequence(LTarget, 'SEQ_PEDIDO', 5, 1);

  FFactory := TSeqTestableFactory.Create(dnPostgreSQL);
  FFactory.CompareSequenceInitialValue := True;   // opt-in
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandAlterSequence),
    'com a flag ligada, InitialValue divergente deve gerar ALTER SEQUENCE');
end;

{ ---- script normalization -------------------------------------------------- }

procedure TTestSequenceDiff.View_EquivalentScriptWhitespace_NoRecreate;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddView(LMaster, 'VW_ATIVO', 'SELECT ID,  NOME'#13#10'  FROM CLIENTE WHERE ATIVO = 1');
  LTarget := TCatalogMetadataMIK.Create;
  _AddView(LTarget, 'VW_ATIVO', 'select id, nome from cliente where ativo = 1');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropView),
    'view equivalente (so whitespace/caixa) NAO deve gerar DROP');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateView),
    'view equivalente (so whitespace/caixa) NAO deve gerar CREATE');
end;

procedure TTestSequenceDiff.View_TrulyDifferentScript_Recreated;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  _AddView(LMaster, 'VW_ATIVO', 'SELECT ID, NOME FROM CLIENTE WHERE ATIVO = 1');
  LTarget := TCatalogMetadataMIK.Create;
  _AddView(LTarget, 'VW_ATIVO', 'SELECT ID FROM CLIENTE');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandDropView),
    'view realmente diferente deve gerar DROP');
  Assert.IsTrue(_HasCommand(TDDLCommandCreateView),
    'view realmente diferente deve gerar CREATE');
end;

procedure TTestSequenceDiff.Trigger_EquivalentScriptWhitespace_NoRecreate;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTableM, LTableT: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTableM := _AddTable(LMaster, 'CLIENTE');
  // Mesmos tokens nos dois lados; diferem SO em whitespace/quebra de linha/caixa.
  _AddTrigger(LTableM, 'TRG_BI', 'BEGIN'#13#10'  NEW.ID = GEN_ID(SEQ,1);'#13#10'END');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := _AddTable(LTarget, 'CLIENTE');
  _AddTrigger(LTableT, 'TRG_BI', 'begin new.id = gen_id(seq,1); end');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropTrigger),
    'trigger equivalente (so whitespace/caixa) NAO deve gerar DROP');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateTrigger),
    'trigger equivalente (so whitespace/caixa) NAO deve gerar CREATE');
end;

{ ---- views in Model-vs-Database mode --------------------------------------- }

procedure TTestSequenceDiff.View_ModelMode_DoesNotDropUnmappedView;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Model-mode: o modelo nao conhece a view orfa do banco; NAO pode dropa-la.
  LMaster := TCatalogMetadataMIK.Create;                   // modelo sem views
  LTarget := TCatalogMetadataMIK.Create;
  _AddView(LTarget, 'VW_ORFA', 'select 1 from dual');       // so no banco

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.SetModelForDatabase(True);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropView),
    'em model-mode nunca dropar view do banco nao mapeada pelo modelo');
end;

procedure TTestSequenceDiff.View_ModelMode_EmptyScriptView_Skipped;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Model-mode: o atributo [View] nao carrega Script (fica ''); a view mapeada
  // com corpo vazio nao pode ser comparada/recriada -> pulada.
  LMaster := TCatalogMetadataMIK.Create;
  _AddView(LMaster, 'VW_CLIENTE', '');                      // corpo vazio (modelo)
  LTarget := TCatalogMetadataMIK.Create;
  _AddView(LTarget, 'VW_CLIENTE', 'select id, nome from cliente');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.SetModelForDatabase(True);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandDropView),
    'view de corpo vazio (model-mode) NAO deve gerar DROP');
  Assert.IsFalse(_HasCommand(TDDLCommandCreateView),
    'view de corpo vazio (model-mode) NAO deve gerar CREATE (evita CREATE VIEW AS vazio)');
end;

{ ---- check master canonicalization ----------------------------------------- }

procedure TTestSequenceDiff.Check_MasterExtraParens_CanonicalMatch_NoAlter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTableM, LTableT: TTableMIK;
begin
  // Master traz o Condition CRU do atributo [Check] com parenteses extras; o
  // target ja vem canonizado pelo extractor. Apos canonizar os DOIS, sao iguais.
  LMaster := TCatalogMetadataMIK.Create;
  LTableM := _AddTable(LMaster, 'PESSOA');
  _AddCheck(LTableM, 'CK_IDADE', '((AGE > 18))');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := _AddTable(LTarget, 'PESSOA');
  _AddCheck(LTableT, 'CK_IDADE', 'AGE > 18');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(_HasCommand(TDDLCommandAlterCheck),
    'check canonicamente igual NAO deve gerar ALTER CHECK');
end;

procedure TTestSequenceDiff.Check_MasterDifferentCondition_Alter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTableM, LTableT: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTableM := _AddTable(LMaster, 'PESSOA');
  _AddCheck(LTableM, 'CK_IDADE', 'AGE > 21');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := _AddTable(LTarget, 'PESSOA');
  _AddCheck(LTableT, 'CK_IDADE', 'AGE > 18');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(_HasCommand(TDDLCommandAlterCheck),
    'check realmente diferente deve gerar ALTER CHECK');
end;

{ ---- policy mapping -------------------------------------------------------- }

procedure TTestSequenceDiff.Policy_AlterSequence_MappedFullAllowsJanusDenies;
var
  LCatalog: TCatalogMetadataMIK;
  LSequence: TSequenceMIK;
  LCommand: TDDLCommandAlterSequence;
begin
  // O novo comando esta MAPEADO no dispatch da policy (nao e ckUnknown): o
  // FullProfile o permite e o Janus o nega - sem cair no fail-closed.
  LCatalog := TCatalogMetadataMIK.Create;
  try
    LSequence := TSequenceMIK.Create(LCatalog);
    LSequence.Name := 'SEQ_X';
    LCatalog.Sequences.Add('SEQ_X', LSequence);
    LCommand := TDDLCommandAlterSequence.Create(LSequence);
    try
      Assert.IsTrue(TComparePolicy.FullProfile.Allows(LCommand),
        'FullProfile deveria PERMITIR AlterSequence (mapeado, nao fail-closed)');
      Assert.IsFalse(TComparePolicy.JanusOrmProfile.Allows(LCommand),
        'JanusOrmProfile deveria NEGAR AlterSequence');
      Assert.IsTrue(TComparePolicy.FullProfile.Allows(TDDLOperation.AlterSequence),
        'AlterSequence deveria estar no conjunto do FullProfile');
    finally
      LCommand.Free;
    end;
  finally
    LCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSequenceDiff);

end.
