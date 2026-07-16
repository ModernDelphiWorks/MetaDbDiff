{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  FRENTE 10 - Sequence diff (ALTER SEQUENCE) + script/check normalization.

  Estes testes rodam SEM banco: montam os catalogos MIK master/target a mao e
  dirigem o GenerateDDLCommands real do TDatabaseFactory, exatamente como a
  Policy suite ja faz. Cobrem:
    * ALTER SEQUENCE emitido quando o Increment diverge (FullProfile) e suprimido
      no JanusOrmProfile;
    * InitialValue NAO comparado por default; comparado com a flag
      CompareSequenceInitialValue = True;
    * NormalizeScript: view/trigger com scripts equivalentes (so diferenca de
      whitespace/quebra de linha) NAO geram drop+create espurio;
    * CanonicalizeCheckCondition no lado master: '((AGE > 18))' (master cru) vs
      'AGE > 18' (target canonizado) -> sem ALTER CHECK;
    * o novo comando esta MAPEADO na policy (FullProfile permite AlterSequence,
      Janus nega) - o fail-closed continua negando SO o desconhecido.

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
  end;

  [TestFixture]
  TTestSequenceDiff = class
  private
    FFactory: TSeqTestableFactory;
    function AddTable(ACatalog: TCatalogMetadataMIK; const AName: String): TTableMIK;
    procedure AddSequence(ACatalog: TCatalogMetadataMIK; const AName: String;
      AInitialValue, AIncrement: Integer);
    procedure AddView(ACatalog: TCatalogMetadataMIK; const AName, AScript: String);
    procedure AddTrigger(ATable: TTableMIK; const AName, AScript: String);
    procedure AddCheck(ATable: TTableMIK; const AName, ACondition: String);
    function CountCommands(AClass: TClass): Integer;
    function HasCommand(AClass: TClass): Boolean;
    function SuppressedContains(const AText: String): Boolean;
  public
    [TearDown]
    procedure TearDown;
    // ---- pure helpers ----------------------------------------------------
    [Test]
    procedure NormalizeScript_CollapsesWhitespaceAndTrims;
    [Test]
    procedure CanonicalizeCheck_StripsKeywordAndBalancedParens;
    // ---- sequence: increment ---------------------------------------------
    [Test]
    procedure Sequence_IncrementDiffers_EmitsAlter_Full;
    [Test]
    procedure Sequence_IncrementDiffers_Suppressed_Janus;
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

{ TTestSequenceDiff }

procedure TTestSequenceDiff.TearDown;
begin
  FreeAndNil(FFactory);
end;

function TTestSequenceDiff.AddTable(ACatalog: TCatalogMetadataMIK;
  const AName: String): TTableMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  Result.Name := AName;
  ACatalog.Tables.Add(UpperCase(AName), Result);
end;

procedure TTestSequenceDiff.AddSequence(ACatalog: TCatalogMetadataMIK;
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

procedure TTestSequenceDiff.AddView(ACatalog: TCatalogMetadataMIK;
  const AName, AScript: String);
var
  LView: TViewMIK;
begin
  LView := TViewMIK.Create(ACatalog);
  LView.Name := AName;
  LView.Script := AScript;
  ACatalog.Views.Add(UpperCase(AName), LView);
end;

procedure TTestSequenceDiff.AddTrigger(ATable: TTableMIK;
  const AName, AScript: String);
var
  LTrigger: TTriggerMIK;
begin
  LTrigger := TTriggerMIK.Create(ATable);
  LTrigger.Name := AName;
  LTrigger.Script := AScript;
  ATable.Triggers.Add(UpperCase(AName), LTrigger);
end;

procedure TTestSequenceDiff.AddCheck(ATable: TTableMIK;
  const AName, ACondition: String);
var
  LCheck: TCheckMIK;
begin
  LCheck := TCheckMIK.Create(ATable);
  LCheck.Name := AName;
  LCheck.Condition := ACondition;
  ATable.Checks.Add(UpperCase(AName), LCheck);
end;

function TTestSequenceDiff.CountCommands(AClass: TClass): Integer;
var
  LCommand: TDDLCommand;
begin
  Result := 0;
  for LCommand in FFactory.GetCommandList do
    if LCommand is AClass then
      Inc(Result);
end;

function TTestSequenceDiff.HasCommand(AClass: TClass): Boolean;
begin
  Result := CountCommands(AClass) > 0;
end;

function TTestSequenceDiff.SuppressedContains(const AText: String): Boolean;
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
    NormalizeScript('  SELECT   A,'#13#10'  B'#9'FROM T  '),
    'runs de espaco/TAB/CRLF devem colapsar num unico espaco e Trim nas bordas');
  // Dois scripts equivalentes normalizam para o MESMO texto.
  Assert.AreEqual(NormalizeScript('SELECT A,  B'#13#10'FROM T'),
                  NormalizeScript('SELECT A, B FROM T'),
    'scripts equivalentes devem normalizar identicamente');
end;

procedure TTestSequenceDiff.CanonicalizeCheck_StripsKeywordAndBalancedParens;
begin
  Assert.AreEqual('AGE > 18', CanonicalizeCheckCondition('CHECK ((AGE > 18))'));
  Assert.AreEqual('AGE > 18', CanonicalizeCheckCondition('((AGE > 18))'));
  Assert.AreEqual('AGE > 18', CanonicalizeCheckCondition('AGE > 18'));
  // Nao descasca parenteses NAO externos (preserva "(A) OR (B)").
  Assert.AreEqual('(A) OR (B)', CanonicalizeCheckCondition('CHECK ((A) OR (B))'));
end;

{ ---- sequence: increment --------------------------------------------------- }

procedure TTestSequenceDiff.Sequence_IncrementDiffers_EmitsAlter_Full;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  AddSequence(LMaster, 'SEQ_PEDIDO', 1, 2);   // increment 2
  LTarget := TCatalogMetadataMIK.Create;
  AddSequence(LTarget, 'SEQ_PEDIDO', 1, 1);   // increment 1 -> diverge

  FFactory := TSeqTestableFactory.Create(dnFirebird); // Policy default = Full
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterSequence),
    'ALTER SEQUENCE deveria ser emitido quando o Increment diverge (FullProfile)');
  Assert.IsFalse(HasCommand(TDDLCommandCreateSequence),
    'nao deveria criar: a sequence existe nos dois lados');
  Assert.IsFalse(HasCommand(TDDLCommandDropSequence),
    'nao deveria dropar: a sequence existe nos dois lados');
end;

procedure TTestSequenceDiff.Sequence_IncrementDiffers_Suppressed_Janus;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  AddSequence(LMaster, 'SEQ_PEDIDO', 1, 2);
  LTarget := TCatalogMetadataMIK.Create;
  AddSequence(LTarget, 'SEQ_PEDIDO', 1, 1);

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Policy := TComparePolicy.JanusOrmProfile;
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandAlterSequence),
    'ALTER SEQUENCE nunca deve ser emitido no perfil Janus');
  Assert.IsTrue(SuppressedContains('ALTER SEQUENCE'),
    'a auditoria deveria registrar o ALTER SEQUENCE suprimido');
end;

{ ---- sequence: initial value (opt-in) -------------------------------------- }

procedure TTestSequenceDiff.Sequence_InitialValueDiffers_NotComparedByDefault;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  // Mesmo increment, InitialValue diferente. Por default NAO compara initial.
  LMaster := TCatalogMetadataMIK.Create;
  AddSequence(LMaster, 'SEQ_PEDIDO', 100, 1);
  LTarget := TCatalogMetadataMIK.Create;
  AddSequence(LTarget, 'SEQ_PEDIDO', 5, 1);

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  // CompareSequenceInitialValue default = False.
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandAlterSequence),
    'InitialValue NAO deve ser comparado por default (alvo movel em producao)');
end;

procedure TTestSequenceDiff.Sequence_InitialValueDiffers_ComparedWithFlag;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  AddSequence(LMaster, 'SEQ_PEDIDO', 100, 1);
  LTarget := TCatalogMetadataMIK.Create;
  AddSequence(LTarget, 'SEQ_PEDIDO', 5, 1);

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.CompareSequenceInitialValue := True;   // opt-in
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterSequence),
    'com a flag ligada, InitialValue divergente deve gerar ALTER SEQUENCE');
end;

{ ---- script normalization -------------------------------------------------- }

procedure TTestSequenceDiff.View_EquivalentScriptWhitespace_NoRecreate;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  AddView(LMaster, 'VW_ATIVO', 'SELECT ID,  NOME'#13#10'  FROM CLIENTE WHERE ATIVO = 1');
  LTarget := TCatalogMetadataMIK.Create;
  AddView(LTarget, 'VW_ATIVO', 'select id, nome from cliente where ativo = 1');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandDropView),
    'view equivalente (so whitespace/caixa) NAO deve gerar DROP');
  Assert.IsFalse(HasCommand(TDDLCommandCreateView),
    'view equivalente (so whitespace/caixa) NAO deve gerar CREATE');
end;

procedure TTestSequenceDiff.View_TrulyDifferentScript_Recreated;
var
  LMaster, LTarget: TCatalogMetadataMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  AddView(LMaster, 'VW_ATIVO', 'SELECT ID, NOME FROM CLIENTE WHERE ATIVO = 1');
  LTarget := TCatalogMetadataMIK.Create;
  AddView(LTarget, 'VW_ATIVO', 'SELECT ID FROM CLIENTE');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandDropView),
    'view realmente diferente deve gerar DROP');
  Assert.IsTrue(HasCommand(TDDLCommandCreateView),
    'view realmente diferente deve gerar CREATE');
end;

procedure TTestSequenceDiff.Trigger_EquivalentScriptWhitespace_NoRecreate;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTableM, LTableT: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTableM := AddTable(LMaster, 'CLIENTE');
  // Mesmos tokens nos dois lados; diferem SO em whitespace/quebra de linha/caixa.
  AddTrigger(LTableM, 'TRG_BI', 'BEGIN'#13#10'  NEW.ID = GEN_ID(SEQ,1);'#13#10'END');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := AddTable(LTarget, 'CLIENTE');
  AddTrigger(LTableT, 'TRG_BI', 'begin new.id = gen_id(seq,1); end');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandDropTrigger),
    'trigger equivalente (so whitespace/caixa) NAO deve gerar DROP');
  Assert.IsFalse(HasCommand(TDDLCommandCreateTrigger),
    'trigger equivalente (so whitespace/caixa) NAO deve gerar CREATE');
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
  LTableM := AddTable(LMaster, 'PESSOA');
  AddCheck(LTableM, 'CK_IDADE', '((AGE > 18))');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := AddTable(LTarget, 'PESSOA');
  AddCheck(LTableT, 'CK_IDADE', 'AGE > 18');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsFalse(HasCommand(TDDLCommandAlterCheck),
    'check canonicamente igual NAO deve gerar ALTER CHECK');
end;

procedure TTestSequenceDiff.Check_MasterDifferentCondition_Alter;
var
  LMaster, LTarget: TCatalogMetadataMIK;
  LTableM, LTableT: TTableMIK;
begin
  LMaster := TCatalogMetadataMIK.Create;
  LTableM := AddTable(LMaster, 'PESSOA');
  AddCheck(LTableM, 'CK_IDADE', 'AGE > 21');
  LTarget := TCatalogMetadataMIK.Create;
  LTableT := AddTable(LTarget, 'PESSOA');
  AddCheck(LTableT, 'CK_IDADE', 'AGE > 18');

  FFactory := TSeqTestableFactory.Create(dnFirebird);
  FFactory.Generate(LMaster, LTarget);

  Assert.IsTrue(HasCommand(TDDLCommandAlterCheck),
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
