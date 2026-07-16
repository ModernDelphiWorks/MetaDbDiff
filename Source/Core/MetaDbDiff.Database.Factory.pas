{
  ------------------------------------------------------------------------------
  MetaDbDiff
  Database metadata comparison and DDL migration script generation engine for Delphi and Lazarus.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro

  Licensed under the MIT License.
  See the LICENSE file in the project root for full license information.
  ------------------------------------------------------------------------------
}

{ @abstract(ORMBr Framework.)
  @created(20 Jul 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)
}

unit MetaDbDiff.Database.Factory;

interface

uses
  DB,
  Classes,
  SysUtils,
  Generics.Collections,
  Generics.Defaults,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Metadata.Normalize,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.Compare.Options;

type
  TDatabaseFactory = class(TDatabaseAbstract)
  private
    procedure _CompareTables(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareViews(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareSequences(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    // FRENTE 15.
    procedure _CompareDomains(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareProcedures(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareDescriptions(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareTablesForeignKeys(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure _CompareForeignKeys(AMasterTable, ATargetTable: TTableMIK);
    procedure _CompareColumns(AMasterTable, ATargetTable: TTableMIK);
    procedure _ComparePrimaryKey(AMasterTable, ATargetTable: TTableMIK);
    procedure _CompareIndexes(AMasterTable, ATargetTable: TTableMIK);
    procedure _CompareTriggers(AMasterTable, ATargetTable: TTableMIK);
    procedure _CompareChecks(AMasterTable, ATargetTable: TTableMIK);
    procedure _ActionCreateTable(ATable: TTableMIK);
    procedure _ActionCreateIndexe(AIndexe: TIndexeKeyMIK);
    procedure _ActionCreateCheck(ACheck: TCheckMIK);
    procedure _ActionCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK);
    procedure _ActionCreateColumn(AColumn: TColumnMIK);
    procedure _ActionCreateSequence(ASequence: TSequenceMIK);
    // Estilo do dono: metodo private novo desta frente leva prefixo '_'.
    procedure _ActionAlterSequence(ASequence: TSequenceMIK);
    procedure _ActionCreateForeignKey(AForeignKey: TForeignKeyMIK);
    procedure _ActionCreateView(AView: TViewMIK);
    procedure _ActionCreateTrigger(ATrigger: TTriggerMIK);
    // FRENTE 15.
    procedure _ActionCreateDomain(ADomain: TDomainMIK);
    procedure _ActionDropDomain(ADomain: TDomainMIK);
    procedure _ActionCreateProcedure(AProcedure: TProcedureMIK);
    procedure _ActionDropProcedure(AProcedure: TProcedureMIK);
    procedure _ActionSetTableComment(ATable: TTableMIK);
    procedure _ActionSetColumnComment(AColumn: TColumnMIK);
    procedure _ActionDropTable(ATable: TTableMIK);
    procedure _ActionDropColumn(AColumn: TColumnMIK);
    procedure _ActionDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK);
    procedure _ActionDropSequence(ASequence: TSequenceMIK);
    procedure _ActionDropIndexe(AIndexe: TIndexeKeyMIK);
    procedure _ActionDropForeignKey(AForeignKey: TForeignKeyMIK);
    procedure _ActionDropCheck(ACheck: TCheckMIK);
    procedure _ActionDropView(AView: TViewMIK);
    procedure _ActionDropTrigger(ATrigger: TTriggerMIK);
    procedure _ActionAlterColumn(AColumn: TColumnMIK);
    procedure _ActionAlterColumnPosition(AColumn: TColumnMIK);
    procedure _ActionDropDefaultValue(AColumn: TColumnMIK);
    procedure _ActionAlterDefaultValue(AColumn: TColumnMIK);
    procedure _ActionAlterCheck(ACheck: TCheckMIK);
    /// <summary>
    /// Gera script que desabilita todas as ForeignKeys
    /// </summary>
    procedure _ActionEnableForeignKeys(AEnable: Boolean);
    procedure _ActionEnableTriggers(AEnable: Boolean);
    function _DeepEqualsColumn(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function _KeepEqualsPosition(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function _DeepEqualsDefaultValue(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function _DeepEqualsForeignKey(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function _DeepEqualsForeignKeyFromColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function _DeepEqualsForeignKeyToColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function _DeepEqualsIndexe(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
    function _DeepEqualsIndexeColumns(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
    function _SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>;
  protected
    function GetFieldTypeValid(AFieldType: TFieldType): TFieldType; override;
    procedure GenerateDDLCommands(AMasterDB, ATargetDB: TCatalogMetadataMIK); override;
  public
    procedure BuildDatabase; override;
  end;

implementation

{ TDatabaseFactory }

procedure TDatabaseFactory.BuildDatabase;
begin
  inherited;
  // The catalogs are kept alive after BuildDatabase (released on the next
  // call or on destroy) because the generated DDL commands hold references
  // to their metadata objects, which descendant ExecuteDDLCommands overrides
  // still dereference when ExecuteCommands rebuilds the command text later.
  FreeAndNil(FCatalogMaster);
  FreeAndNil(FCatalogTarget);
  FCatalogMaster := TCatalogMetadataMIK.Create;
  FCatalogTarget := TCatalogMetadataMIK.Create;
  // Extrai o metadata com base nos modelos existentes e no banco de dados
  ExtractDatabase;
  // Generates the DDL commands to update the target database.
  GenerateDDLCommands(FCatalogMaster, FCatalogTarget);
  // Execute the generated commands only when auto execution is enabled.
  if FCommandsAutoExecute then
  begin
    // Dupla checagem antes de executar (defesa em profundidade).
    ValidateCommandsPolicy;
    ExecuteDDLCommands;
  end;
end;

function TDatabaseFactory._DeepEqualsColumn(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
begin
  Result := True;
  if AMasterColumn.TypeName <> ATargetColumn.TypeName then
    Exit(False);
  if AMasterColumn.Size <> ATargetColumn.Size then
    Exit(False);
  if AMasterColumn.Precision <> ATargetColumn.Precision then
    Exit(False);
  if AMasterColumn.Scale <> ATargetColumn.Scale then
    Exit(False);
  if AMasterColumn.NotNull <> ATargetColumn.NotNull then
    Exit(False);
  if AMasterColumn.AutoIncrement <> ATargetColumn.AutoIncrement then
    Exit(False);
  if AMasterColumn.SortingOrder <> ATargetColumn.SortingOrder then
    Exit(False);
  if AMasterColumn.DefaultValue <> ATargetColumn.DefaultValue then
    Exit(False);
  if GetFieldTypeValid(AMasterColumn.FieldType) <> GetFieldTypeValid(ATargetColumn.FieldType) then
    Exit(False);
  if (AMasterColumn.CharSet <> EmptyStr) and (AMasterColumn.CharSet <> ATargetColumn.CharSet) then
    Exit(False);
//  if AMasterColumn.Description <> ATargetColumn.Description then
//    Exit(False);
end;

function TDatabaseFactory._DeepEqualsDefaultValue(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
begin
  Result := True;
  if AMasterColumn.DefaultValue <> ATargetColumn.DefaultValue then
    Exit(False);
end;

function TDatabaseFactory._DeepEqualsForeignKey(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
begin
  Result := True;
  if not SameText(AMasterForeignKey.FromTable, ATargetForeignKey.FromTable) then
    Exit(False);
  if AMasterForeignKey.OnDelete <> ATargetForeignKey.OnDelete then
    Exit(False);
  if AMasterForeignKey.OnUpdate <> ATargetForeignKey.OnUpdate then
    Exit(False);
//  if AMasterForeignKey.Description <> ATargetForeignKey.Description then
//    Exit(False);
end;

function TDatabaseFactory._DeepEqualsIndexe(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
begin
  Result := True;
  if AMasterIndexe.Unique <> ATargetIndexe.Unique then
    Exit(False);
//  if AMasterIndexe.Description <> ATargetIndexe.Description then
//    Exit(False);
end;

procedure TDatabaseFactory.GenerateDDLCommands(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LDDLCommand: TDDLCommand;
begin
  inherited;
  FDDLCommands.Clear;
  // Zera o relat�rio de auditoria: cada gera��o parte de um estado limpo.
  FSuppressedCommands.Clear;
  // Gera script que desabilita todas as ForeignKeys
  _ActionEnableForeignKeys(False);
  // Gera script que desabilita todas as Triggers
  _ActionEnableTriggers(False);
  // FRENTE 15: Domains antes das tabelas (colunas podem usar domains). O
  // sequenciador coloca CREATE DOMAIN na fase certa; aqui so importa a geracao.
  _CompareDomains(AMasterDB, ATargetDB);
  // Compara Tabelas
  _CompareTables(AMasterDB, ATargetDB);
  // Compara Views
  _CompareViews(AMasterDB, ATargetDB);
  // Compara Sequences
  _CompareSequences(AMasterDB, ATargetDB);
  // FRENTE 15: Procedures/Functions (DB-vs-DB/snapshot APENAS; no-op em model-mode).
  _CompareProcedures(AMasterDB, ATargetDB);
  // FRENTE 15: Descriptions/COMMENT ON (opt-in via CompareDescriptions).
  _CompareDescriptions(AMasterDB, ATargetDB);
  // Compara ForeingKeys
  _CompareTablesForeignKeys(AMasterDB, ATargetDB);
  // Gera script que habilita todas as ForeignKeys
  _ActionEnableForeignKeys(True);
  // Gera script que habilita todas as Triggers
  _ActionEnableTriggers(True);
  // Build the command text right after generation so GetCommandList exposes
  // the SQL even when the commands are not executed (preview mode).
  // BuildCommand is deterministic, so rebuilding it again inside descendant
  // ExecuteDDLCommands overrides just reassigns the same text.
  for LDDLCommand in FDDLCommands do
    LDDLCommand.BuildCommand(FGeneratorCommand);
  // Estrat�gia de ALTER COLUMN (FRENTE 11): quando acsRebuildWhenRequired,
  // substitui ALTER COLUMN inseguros pela sequ�ncia segura (add/copy/drop/rename)
  // ou backfill+SET NOT NULL. No-op no default acsInPlace. Roda AP�S BuildCommand
  // (para os comandos mantidos) e ANTES do sequenciador (para agrupar por fase).
  ApplyAlterStrategy;
  // Reordena a lista final em ordem topol�gica por fase (dependency-safe) e
  // guarda o TDDLSequenceReport (fases/ciclos). No-op quando UseSequencer=False
  // (mant�m a ordem hist�rica de gera��o - fallback de compatibilidade).
  ApplySequencer;
end;

function TDatabaseFactory.GetFieldTypeValid(AFieldType: TFieldType): TFieldType;
begin
  if AFieldType in [ftCurrency, ftFloat, ftBCD, ftExtended, ftSingle, ftFMTBcd] then
    Result := ftCurrency
  else
  if AFieldType in [ftString, ftFixedChar, ftWideString, ftFixedWideChar, ftGuid] then
    Result := ftString
  else
  if AFieldType in [ftInteger, ftShortint, ftSmallint, ftLargeint] then
    Result := ftInteger
  else
  if AFieldType in [ftMemo, ftFmtMemo, ftWideMemo] then
    Result := ftMemo
  else
    Result := AFieldType;
end;

function TDatabaseFactory._KeepEqualsPosition(AMasterColumn,
  ATargetColumn: TColumnMIK): Boolean;
begin
  Result := True;
  if (AMasterColumn.Position <> ATargetColumn.Position) then
    Exit(False);
end;

function TDatabaseFactory._SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>;
begin
  // Returns the dictionary pairs sorted by key so the generated script
  // keeps a stable, deterministic order between executions.
  Result := ADictionary.ToArray;
  TArray.Sort<TPair<String, T>>(Result,
    TComparer<TPair<String, T>>.Construct(
      function (const Left, Right: TPair<String, T>): Integer
      begin
        Result := CompareStr(Left.Key, Right.Key);
      end)
    );
end;

procedure TDatabaseFactory._CompareTables(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LTableMaster: TPair<String, TTableMIK>;
  LTableTarget: TPair<String, TTableMIK>;
begin
  // Gera script de exclus�o de tabela, caso n�o exista um modelo para ela no banco.
  for LTableTarget in ATargetDB.TablesSort do
  begin
    if not AMasterDB.Tables.ContainsKey(LTableTarget.Key) then
      _ActionDropTable(LTableTarget.Value);
  end;
  // Gera script de cria��o de tabela, caso a tabela do modelo n�o exista no banco.
  for LTableMaster in AMasterDB.TablesSort do
  begin
    if ATargetDB.Tables.ContainsKey(LTableMaster.Key) then
    begin
      // Table Columns
      _CompareColumns(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table PrimaryKey
      if (LTableMaster.Value.PrimaryKey.Fields.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].PrimaryKey.Fields.Count > 0) then
        _ComparePrimaryKey(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Indexes
      if (LTableMaster.Value.IndexeKeys.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].IndexeKeys.Count > 0) then
        _CompareIndexes(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Checks
      if (LTableMaster.Value.Checks.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].Checks.Count > 0) then
        _CompareChecks(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Triggers
      if (LTableMaster.Value.Triggers.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].Triggers.Count > 0) then
        _CompareTriggers(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);
    end
    else
      _ActionCreateTable(LTableMaster.Value);
  end;
end;

procedure TDatabaseFactory._CompareTriggers(AMasterTable, ATargetTable: TTableMIK);
var
  LTriggerMaster: TPair<String, TTriggerMIK>;
  LTriggerTarget: TPair<String, TTriggerMIK>;
  LTrigger: TTriggerMIK;
begin
  if TSupportedFeature.Triggers in FGeneratorCommand.SupportedFeatures then
  begin
    // Remove trigger que n�o existe no modelo.
    for LTriggerTarget in _SortedPairs<TTriggerMIK>(ATargetTable.Triggers) do
    begin
      if not AMasterTable.Triggers.ContainsKey(LTriggerTarget.Key) then
        _ActionDropTrigger(LTriggerTarget.Value);
    end;
    // Gera script de cria��o de trigger, caso a trigger do modelo n�o exista no banco.
    for LTriggerMaster in _SortedPairs<TTriggerMIK>(AMasterTable.Triggers) do
    begin
      if ATargetTable.Triggers.ContainsKey(LTriggerMaster.Key) then
      begin
        LTrigger := ATargetTable.Triggers.Items[LTriggerMaster.Key];
        // Recreate the trigger when the script differs from the model. Compara o
        // script NORMALIZADO (whitespace/quebras colapsados) para nao gerar
        // drop+create espurio so por diferenca de formatacao; o script ORIGINAL
        // continua sendo usado no CREATE.
        if CompareText(TMetadataNormalizer.NormalizeScript(LTriggerMaster.Value.Script),
                       TMetadataNormalizer.NormalizeScript(LTrigger.Script)) <> 0 then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas;
          // caso contr�rio suprime o par inteiro (nunca deixa drop �rf�o).
          if FPolicy.Allows(TDDLOperation.DropTrigger) and
             FPolicy.Allows(TDDLOperation.CreateTrigger) then
          begin
            _ActionDropTrigger(LTrigger);
            _ActionCreateTrigger(LTriggerMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE TRIGGER %s.%s suppressed by policy',
              [LTrigger.Table.Name, LTrigger.Name]));
        end;
      end
      else
        _ActionCreateTrigger(LTriggerMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory._CompareViews(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LViewMaster: TPair<String, TViewMIK>;
  LViewTarget: TPair<String, TViewMIK>;
  LView: TViewMIK;
begin
  if TSupportedFeature.Views in FGeneratorCommand.SupportedFeatures then
  begin
    // Gera script de exclus�o da view, caso n�o exista um modelo para ela no banco.
    // EXCECAO (F10) - modo Model-vs-Database: o modelo (atributos [View]) NAO
    // conhece todas as views do banco, entao NUNCA dropamos uma view do target so
    // porque nao esta mapeada - senao um FullProfile em model-mode faria DROP em
    // massa das views nao modeladas. O diff completo de views (drop de orfas) fica
    // para DB-vs-DB/snapshot, onde ambos os lados tem o catalogo real.
    if not FModelForDatabase then
      for LViewTarget in _SortedPairs<TViewMIK>(ATargetDB.Views) do
      begin
        if not AMasterDB.Views.ContainsKey(LViewTarget.Key) then
          _ActionDropView(LViewTarget.Value);
      end;
    // Gera script de cria��o da view, caso a view do modelo n�o exista no banco.
    for LViewMaster in _SortedPairs<TViewMIK>(AMasterDB.Views) do
    begin
      // Em model-mode o atributo [View] NAO carrega Script (Popular forca ''):
      // sem corpo nao da para comparar nem (re)criar (CREATE VIEW AS <vazio> e
      // invalido). Pula estas views - o corpo so existe no caminho DB-vs-DB.
      if FModelForDatabase and (Trim(LViewMaster.Value.Script) = '') then
        Continue;
      if ATargetDB.Views.ContainsKey(LViewMaster.Key) then
      begin
        LView := ATargetDB.Views.Items[LViewMaster.Key];
        // Recreate the view when the script differs from the model. Compara o
        // script NORMALIZADO (whitespace/quebras colapsados) para nao gerar
        // drop+create espurio so por diferenca de formatacao; o script ORIGINAL
        // continua sendo usado no CREATE.
        if CompareText(TMetadataNormalizer.NormalizeScript(LViewMaster.Value.Script),
                       TMetadataNormalizer.NormalizeScript(LView.Script)) <> 0 then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
          if FPolicy.Allows(TDDLOperation.DropView) and
             FPolicy.Allows(TDDLOperation.CreateView) then
          begin
            _ActionDropView(LView);
            _ActionCreateView(LViewMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE VIEW %s suppressed by policy',
              [LView.Name]));
        end;
      end
      else
        _ActionCreateView(LViewMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory._CompareChecks(AMasterTable, ATargetTable: TTableMIK);
var
  LCheckMaster: TPair<String, TCheckMIK>;
  LCheckTarget: TPair<String, TCheckMIK>;
  LCheck: TCheckMIK;
begin
  if TSupportedFeature.Checks in FGeneratorCommand.SupportedFeatures then
  begin
    // Drop checks that exist in the database but not in the model.
    for LCheckTarget in _SortedPairs<TCheckMIK>(ATargetTable.Checks) do
    begin
      if not AMasterTable.Checks.ContainsKey(LCheckTarget.Key) then
        _ActionDropCheck(LCheckTarget.Value);
    end;
    // Create checks missing in the database; alter when the condition differs.
    for LCheckMaster in _SortedPairs<TCheckMIK>(AMasterTable.Checks) do
    begin
      if ATargetTable.Checks.ContainsKey(LCheckMaster.Key) then
      begin
        LCheck := ATargetTable.Checks.Items[LCheckMaster.Key];
        // O lado TARGET ja vem canonizado pelo extractor (strip CHECK + parens
        // externos balanceados). O lado MASTER traz o Condition CRU do atributo
        // [Check] (ex.: 'AGE > 18' ou '((AGE > 18))'): aplica a MESMA canonizacao
        // aqui para que 'AGE > 18' (master) == '((AGE > 18))' (target) NAO gere um
        // ALTER CHECK espurio. Canonizar o target de novo e idempotente.
        if CompareText(TMetadataNormalizer.CanonicalizeCheckCondition(LCheckMaster.Value.Condition),
                       TMetadataNormalizer.CanonicalizeCheckCondition(LCheck.Condition)) <> 0 then
          _ActionAlterCheck(LCheckMaster.Value);
      end
      else
        _ActionCreateCheck(LCheckMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory._CompareColumns(AMasterTable, ATargetTable: TTableMIK);
var
  LColumnMaster: TPair<String, TColumnMIK>;
  LColumnTarget: TPair<String, TColumnMIK>;
  LColumn: TColumnMIK;
  LReorderColumns: Boolean;

  function ExistMasterColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TColumnMIK;
  begin
    Result := nil;
    for LColumn in AMasterTable.Fields.Values do
      if SameText(LColumn.Name, AColumnName) then
        Exit(LColumn);
  end;

  function ExistTargetColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TColumnMIK;
  begin
    Result := nil;
    for LColumn in ATargetTable.Fields.Values do
      if SameText(LColumn.Name, AColumnName) then
        Exit(LColumn);
  end;

begin
  // Remove coluna que n�o existe no modelo.
  for LColumnTarget in ATargetTable.FieldsSort do
  begin
    LColumn := ExistMasterColumn(LColumnTarget.Value.Name);
    if LColumn = nil then
      _ActionDropColumn(LColumnTarget.Value);
  end;
  // Adiciona coluna do modelo que n�o exista no banco
  // Compara coluna que exista no modelo e no banco
  LReorderColumns := False;
  for LColumnMaster in AMasterTable.FieldsSort do
  begin
    LColumn := ExistTargetColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
      _ActionCreateColumn(LColumnMaster.Value)
    else
    begin
      if not _DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        _ActionAlterColumn(LColumnMaster.Value);

      if not _KeepEqualsPosition(LColumnMaster.Value, LColumn) then
        LReorderColumns := True;

      // Compara DefaultValue
      if not _DeepEqualsDefaultValue(LColumnMaster.Value, LColumn) then
      begin
        if Length(LColumnMaster.Value.DefaultValue) > 0 then
          _ActionAlterDefaultValue(LColumnMaster.Value)
        else
          _ActionDropDefaultValue(LColumn);
      end;
    end;
  end;
  if ComparerFieldPosition and LReorderColumns then
    for LColumnMaster in AMasterTable.FieldsSort do
    begin
      _ActionAlterColumnPosition(LColumnMaster.Value);
    end;
end;

procedure TDatabaseFactory._CompareTablesForeignKeys(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LTableMaster: TPair<String, TTableMIK>;
  LForeignKeyMaster: TPair<String, TForeignKeyMIK>;
begin
  // Gera script de cria��o das ForeingnKeys, caso n�o exista no banco.
  for LTableMaster in AMasterDB.TablesSort do
  begin
    if ATargetDB.Tables.ContainsKey(LTableMaster.Key) then
    begin
      // Table ForeignKeys
      if (LTableMaster.Value.ForeignKeys.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].ForeignKeys.Count > 0) then
        _CompareForeignKeys(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);
    end
    else
    begin
      // Gera script de cria��o dos ForeignKey da nova tabela.
      if FDriverName <> dnSQLite then
        for LForeignKeyMaster in _SortedPairs<TForeignKeyMIK>(LTableMaster.Value.ForeignKeys) do
          _ActionCreateForeignKey(LForeignKeyMaster.Value);
    end;
  end;
end;

function TDatabaseFactory._DeepEqualsForeignKeyFromColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
var
  LColumnMaster: TPair<String, TColumnMIK>;
  LColumnTarget: TPair<String, TColumnMIK>;
  LColumn: TColumnMIK;

  function ExistMasterFromColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in AMasterForeignKey.FromFields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

  function ExistTargetFromColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in ATargetForeignKey.FromFields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

begin
  Result := True;
  // Compara��o dos campos dos indexes banco/modelo
  for LColumnTarget in ATargetForeignKey.FromFieldsSort do
  begin
    LColumn := ExistMasterFromColumn(LColumnTarget.Value.Name);
    if LColumn = nil then
      Exit(False)
  end;
  // Compara��o dos campos dos indexes modelo/banco
  for LColumnMaster in AMasterForeignKey.FromFieldsSort do
  begin
    LColumn := ExistTargetFromColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
      Exit(False)
    else
    begin
      if not _DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

procedure TDatabaseFactory._CompareForeignKeys(AMasterTable, ATargetTable: TTableMIK);
var
  LForeignKeyMaster: TPair<String, TForeignKeyMIK>;
  LForeignKeyTarget: TPair<String, TForeignKeyMIK>;
begin
  if TSupportedFeature.ForeignKeys in FGeneratorCommand.SupportedFeatures then
  begin
    // Remove indexe que n�o existe no modelo.
    for LForeignKeyTarget in _SortedPairs<TForeignKeyMIK>(ATargetTable.ForeignKeys) do
    begin
      if not AMasterTable.ForeignKeys.ContainsKey(LForeignKeyTarget.Key) then
        _ActionDropForeignKey(LForeignKeyTarget.Value);
    end;
    // Gera script de cria��o de indexe, caso a indexe do modelo n�o exista no banco.
    for LForeignKeyMaster in _SortedPairs<TForeignKeyMIK>(AMasterTable.ForeignKeys) do
    begin
      if ATargetTable.ForeignKeys.ContainsKey(LForeignKeyMaster.Key) then
      begin
        // Checa diferen�a do ForeignKey
        LForeignKeyTarget.Value := ATargetTable.ForeignKeys.Items[LForeignKeyMaster.Key];

        if (not _DeepEqualsForeignKey(LForeignKeyMaster.Value, LForeignKeyTarget.Value)) or
           (not _DeepEqualsForeignKeyFromColumns(LForeignKeyMaster.Value, LForeignKeyTarget.Value)) or
           (not _DeepEqualsForeignKeyToColumns  (LForeignKeyMaster.Value, LForeignKeyTarget.Value)) then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
          if FPolicy.Allows(TDDLOperation.DropForeignKey) and
             FPolicy.Allows(TDDLOperation.CreateForeignKey) then
          begin
            _ActionDropForeignKey(LForeignKeyTarget.Value);
            _ActionCreateForeignKey(LForeignKeyMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE FOREIGNKEY %s.%s suppressed by policy',
              [LForeignKeyTarget.Value.Table.Name, LForeignKeyTarget.Value.Name]));
        end;
      end
      else
        _ActionCreateForeignKey(LForeignKeyMaster.Value);
    end;
  end;
end;

function TDatabaseFactory._DeepEqualsForeignKeyToColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
var
  LColumnMaster: TPair<String, TColumnMIK>;
  LColumnTarget: TPair<String, TColumnMIK>;
  LColumn: TColumnMIK;

  function ExistMasterToColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in AMasterForeignKey.ToFields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

  function ExistTargetFromColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in ATargetForeignKey.ToFields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

begin
  Result := True;
  // Compara��o dos campos dos indexes banco/modelo
  for LColumnTarget in ATargetForeignKey.ToFieldsSort do
  begin
    LColumn := ExistMasterToColumn(LColumnTarget.Value.Name);
    if LColumn = nil then
      Exit(False)
  end;
  // Compara��o dos campos dos indexes modelo/banco
  for LColumnMaster in AMasterForeignKey.ToFieldsSort do
  begin
    LColumn := ExistTargetFromColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
      Exit(False)
    else
    begin
      if not _DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

function TDatabaseFactory._DeepEqualsIndexeColumns(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
var
  LColumnMaster: TPair<String, TColumnMIK>;
  LColumnTarget: TPair<String, TColumnMIK>;
  LColumn: TColumnMIK;

  function ExistMasterColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in AMasterIndexe.Fields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

  function ExistTargetColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in ATargetIndexe.Fields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

begin
  Result := True;
  // Compara��o dos campos dos indexes banco/modelo
  for LColumnTarget in ATargetIndexe.FieldsSort do
  begin
    LColumn := ExistMasterColumn(LColumnTarget.Value.Name);
    if LColumn = nil then
      Exit(False)
  end;
  // Compara��o dos campos dos indexes modelo/banco
  for LColumnMaster in AMasterIndexe.FieldsSort do
  begin
    LColumn := ExistTargetColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
      Exit(False)
    else
    begin
      if not _DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

procedure TDatabaseFactory._CompareIndexes(AMasterTable, ATargetTable: TTableMIK);
var
  LIndexeMaster: TPair<String, TIndexeKeyMIK>;
  LIndexeTarget: TPair<String, TIndexeKeyMIK>;
begin
  // Remove indexe que n�o existe no modelo.
  for LIndexeTarget in _SortedPairs<TIndexeKeyMIK>(ATargetTable.IndexeKeys) do
  begin
    if not AMasterTable.IndexeKeys.ContainsKey(LIndexeTarget.Key) then
      _ActionDropIndexe(LIndexeTarget.Value);
  end;
  // Gera script de cria��o de indexe, caso a indexe do modelo n�o exista no banco.
  for LIndexeMaster in _SortedPairs<TIndexeKeyMIK>(AMasterTable.IndexeKeys) do
  begin
    if ATargetTable.IndexeKeys.ContainsKey(LIndexeMaster.Key) then
    begin
      LIndexeTarget.Value := ATargetTable.IndexeKeys.Items[LIndexeMaster.Key];
      if (not _DeepEqualsIndexe(LIndexeMaster.Value, LIndexeTarget.Value)) or
         (not _DeepEqualsIndexeColumns(LIndexeMaster.Value, LIndexeTarget.Value)) then
      begin
        // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
        if FPolicy.Allows(TDDLOperation.DropIndexe) and
           FPolicy.Allows(TDDLOperation.CreateIndexe) then
        begin
          _ActionDropIndexe(LIndexeTarget.Value);
          _ActionCreateIndexe(LIndexeMaster.Value);
        end
        else
          AddSuppressed(Format('RECREATE INDEXE %s.%s suppressed by policy',
            [LIndexeTarget.Value.Table.Name, LIndexeTarget.Value.Name]));
      end;
    end
    else
      _ActionCreateIndexe(LIndexeMaster.Value);
  end;
end;

procedure TDatabaseFactory._ComparePrimaryKey(AMasterTable, ATargetTable: TTableMIK);
var
  LColumnMaster: TPair<String, TColumnMIK>;
  LColumn: TColumnMIK;
  LDropPK: Boolean;
  LRecreatePK: Boolean;

  function ExistTargetColumn(AColumnName: String): TColumnMIK;
  var
    LColumn: TPair<String, TColumnMIK>;
  begin
    Result := nil;
    for LColumn in ATargetTable.PrimaryKey.Fields do
      if SameText(LColumn.Value.Name, AColumnName) then
        Exit(LColumn.Value);
  end;

begin
  LDropPK := False;
  if not SameText(AMasterTable.PrimaryKey.Name, ATargetTable.PrimaryKey.Name) and
    (Trim(ATargetTable.PrimaryKey.Name) <> EmptyStr) then
  begin
  	LDropPK := True;
  end;

  // Se alguma coluna n�o existir na PrimaryKey do banco recria a PrimaryKey.
  LRecreatePK := False;
  for LColumnMaster in AMasterTable.PrimaryKey.FieldsSort do
  begin
    LColumn := ExistTargetColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
    begin
      LRecreatePK := True;
      Break;
    end;
  end;
  // A primary key recreated by column divergence must drop the existing one first.
  if LRecreatePK and (Trim(ATargetTable.PrimaryKey.Name) <> EmptyStr) then
    LDropPK := True;
  // Every primary key dropped by divergence must be recreated from the model.
  if LDropPK and (AMasterTable.PrimaryKey.Fields.Count > 0) then
    LRecreatePK := True;
  // Par DROP+CREATE (recreate de PK divergente): s� emite se AMBAS as opera��es
  // forem permitidas; caso contr�rio suprime o par inteiro (nunca dropa a PK
  // existente deixando a tabela sem chave). Um create isolado (target sem PK) ou
  // um drop isolado (model sem PK) seguem para o gate individual do Action*.
  if LDropPK and LRecreatePK and
     (not (FPolicy.Allows(TDDLOperation.DropPrimaryKey) and
           FPolicy.Allows(TDDLOperation.CreatePrimaryKey))) then
  begin
    AddSuppressed(Format('RECREATE PRIMARYKEY %s.%s suppressed by policy',
      [ATargetTable.Name, ATargetTable.PrimaryKey.Name]));
    LDropPK := False;
    LRecreatePK := False;
  end;
  if LDropPK then
    _ActionDropPrimaryKey(ATargetTable.PrimaryKey);
  if LRecreatePK then
    _ActionCreatePrimaryKey(AMasterTable.PrimaryKey);
end;

procedure TDatabaseFactory._CompareSequences(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LSequenceMaster: TPair<String, TSequenceMIK>;
  LSequenceTarget: TPair<String, TSequenceMIK>;
  LTarget: TSequenceMIK;
  LDiverges: Boolean;

  // As familias sqlite_sequence (SQLite/AbsoluteDB) NAO possuem objeto SEQUENCE
  // real: o "contador" e uma linha em sqlite_sequence e nao ha INCREMENT/RESTART
  // alteravel por DDL. Nesses dialetos nunca emitimos ALTER SEQUENCE (o proprio
  // generator retorna vazio, mas evitamos ate criar o comando).
  function _DialectSupportsAlterSequence: Boolean;
  begin
    Result := not (FDriverName in [dnSQLite, dnAbsoluteDB]);
  end;

begin
  if TSupportedFeature.Sequences in FGeneratorCommand.SupportedFeatures then
  begin
    // Checa se existe alguma sequence no banco, da qual n�o exista nos modelos
    // para exclus�o da mesma.
    for LSequenceTarget in _SortedPairs<TSequenceMIK>(ATargetDB.Sequences) do
    begin
      if not AMasterDB.Sequences.ContainsKey(LSequenceTarget.Key) then
        _ActionDropSequence(LSequenceTarget.Value);
    end;
    // Checa se existe a sequence no banco: cria se faltar, senao compara.
    for LSequenceMaster in _SortedPairs<TSequenceMIK>(AMasterDB.Sequences) do
    begin
      if not ATargetDB.Sequences.ContainsKey(LSequenceMaster.Key) then
        _ActionCreateSequence(LSequenceMaster.Value)
      else if _DialectSupportsAlterSequence then
      begin
        // Sequence existe nos dois lados: compara os atributos alteraveis.
        LTarget := ATargetDB.Sequences.Items[LSequenceMaster.Key];
        LDiverges := False;
        // REGRA DE SEGURANCA (F10): Increment 0 e ILEGAL em qualquer SGBD, logo
        // aqui o zero significa "nao extraido/desconhecido" (Firebird 2.5 nao tem
        // increment em RDB$GENERATORS; o passo e do GEN_ID por chamada). Quando o
        // target nao trouxe o increment, PULAMOS a comparacao do passo - senao o
        // increment do modelo divergiria SEMPRE de 0 e dispararia um ALTER
        // SEQUENCE ... RESTART perpetuo que reseta a sequence viva a cada diff.
        if (LTarget.Increment <> 0) and
           (LSequenceMaster.Value.Increment <> LTarget.Increment) then
          LDiverges := True;
        // InitialValue so entra na comparacao sob a flag opt-in (o valor corrente
        // e alvo movel em producao). No Firebird 2.5 essa e a UNICA via possivel
        // de AlterSequence (o override so emite RESTART WITH) e apenas quando o
        // usuario liga explicitamente a flag - documentado no gerador.
        if FCompareSequenceInitialValue and
           (LSequenceMaster.Value.InitialValue <> LTarget.InitialValue) then
          LDiverges := True;
        if LDiverges then
          _ActionAlterSequence(LSequenceMaster.Value);
      end;
    end;
  end;
end;

procedure TDatabaseFactory._CompareDomains(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LDomainMaster: TPair<String, TDomainMIK>;
  LDomainTarget: TPair<String, TDomainMIK>;
  LTarget: TDomainMIK;

  function _DomainDiverges(AMaster, ATarget: TDomainMIK): Boolean;
  begin
    Result := (not SameText(AMaster.TypeName, ATarget.TypeName)) or
              (AMaster.NotNull <> ATarget.NotNull) or
              (not SameText(Trim(AMaster.DefaultValue), Trim(ATarget.DefaultValue))) or
              (CompareText(TMetadataNormalizer.CanonicalizeCheckCondition(AMaster.CheckCondition),
                           TMetadataNormalizer.CanonicalizeCheckCondition(ATarget.CheckCondition)) <> 0);
  end;

begin
  if not (TSupportedFeature.Domains in FGeneratorCommand.SupportedFeatures) then
    Exit;
  // DROP de dominio orfao: mesma excecao das Views - em model-mode o modelo NAO
  // declara dominios, entao nunca dropamos um dominio do banco so por ele nao
  // estar mapeado (senao um FullProfile em model-mode dropava dominios em massa).
  if not FModelForDatabase then
    for LDomainTarget in _SortedPairs<TDomainMIK>(ATargetDB.Domains) do
      if not AMasterDB.Domains.ContainsKey(LDomainTarget.Key) then
        _ActionDropDomain(LDomainTarget.Value);
  // CREATE quando falta; DIVERGENCIA de definicao = CONSERVADOR: NAO emitimos
  // drop+create automatico (um dominio em uso nao dropa sem reescrever todas as
  // colunas que o referenciam). Registramos a divergencia na auditoria; o ALTER
  // DOMAIN incremental fica como evolucao futura.
  for LDomainMaster in _SortedPairs<TDomainMIK>(AMasterDB.Domains) do
  begin
    if ATargetDB.Domains.ContainsKey(LDomainMaster.Key) then
    begin
      LTarget := ATargetDB.Domains.Items[LDomainMaster.Key];
      if _DomainDiverges(LDomainMaster.Value, LTarget) then
        AddSuppressed(Format('DOMAIN %s diverge (tipo/default/notnull/check) - ' +
          'nao alterado automaticamente (dominio em uso nao dropa; ALTER DOMAIN ' +
          'fica como evolucao). Ajuste manual necessario.', [LTarget.Name]));
    end
    else
      _ActionCreateDomain(LDomainMaster.Value);
  end;
end;

procedure TDatabaseFactory._CompareProcedures(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LProcMaster: TPair<String, TProcedureMIK>;
  LProcTarget: TPair<String, TProcedureMIK>;
  LProc: TProcedureMIK;
begin
  if not (TSupportedFeature.Procedures in FGeneratorCommand.SupportedFeatures) then
    Exit;
  // v1: DB-vs-DB / snapshot APENAS. O modelo decorado NAO declara procedures;
  // em model-mode o compare e NO-OP seguro (mesmo padrao das views) - jamais
  // dropa uma procedure do banco so porque o modelo nao a conhece.
  if FModelForDatabase then
    Exit;
  // DROP de procedure orfa (existe no banco, nao no master).
  for LProcTarget in _SortedPairs<TProcedureMIK>(ATargetDB.Procedures) do
    if not AMasterDB.Procedures.ContainsKey(LProcTarget.Key) then
      _ActionDropProcedure(LProcTarget.Value);
  // CREATE quando falta; DROP+CREATE em par atomico quando o script NORMALIZADO
  // difere (o script extraido ja e o CREATE completo).
  for LProcMaster in _SortedPairs<TProcedureMIK>(AMasterDB.Procedures) do
  begin
    if ATargetDB.Procedures.ContainsKey(LProcMaster.Key) then
    begin
      LProc := ATargetDB.Procedures.Items[LProcMaster.Key];
      if CompareText(TMetadataNormalizer.NormalizeScript(LProcMaster.Value.Script),
                     TMetadataNormalizer.NormalizeScript(LProc.Script)) <> 0 then
      begin
        // Par DROP+CREATE: so emite se AMBAS as operacoes forem permitidas.
        if FPolicy.Allows(TDDLOperation.DropProcedure) and
           FPolicy.Allows(TDDLOperation.CreateProcedure) then
        begin
          _ActionDropProcedure(LProc);
          _ActionCreateProcedure(LProcMaster.Value);
        end
        else
          AddSuppressed(Format('RECREATE PROCEDURE %s suppressed by policy',
            [LProc.Name]));
      end;
    end
    else
      _ActionCreateProcedure(LProcMaster.Value);
  end;
end;

procedure TDatabaseFactory._CompareDescriptions(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LTablePair: TPair<String, TTableMIK>;
  LMasterTable, LTargetTable: TTableMIK;
  LColMaster: TPair<String, TColumnMIK>;
  LTargetColumn: TColumnMIK;

  function _FindColumn(ATable: TTableMIK; const AName: String): TColumnMIK;
  var
    LColumn: TColumnMIK;
  begin
    Result := nil;
    for LColumn in ATable.Fields.Values do
      if SameText(LColumn.Name, AName) then
        Exit(LColumn);
  end;

begin
  // Custo ZERO no caminho existente: com a flag OFF, divergencia de descricao e
  // silencio total.
  if not FCompareDescriptions then
    Exit;
  // COMMENT ON e emitido apenas nos dialetos onde e trivial/padrao e onde a
  // Description e extraida (PostgreSQL/Firebird) ou trivialmente comentavel
  // (Oracle). MSSQL (extended properties) fica FORA desta frente.
  if not (FDriverName in [dnPostgreSQL, dnFirebird, dnInterbase, dnOracle]) then
    Exit;
  // Compara Description de TABELAS e COLUNAS que existem nos DOIS lados (comentar
  // exige o objeto ja existir - a fase COMMENTS roda por ultimo, apos criar).
  for LTablePair in AMasterDB.TablesSort do
  begin
    if not ATargetDB.Tables.ContainsKey(LTablePair.Key) then
      Continue;
    LMasterTable := LTablePair.Value;
    LTargetTable := ATargetDB.Tables.Items[LTablePair.Key];
    if not SameText(Trim(LMasterTable.Description), Trim(LTargetTable.Description)) then
      _ActionSetTableComment(LMasterTable);
    for LColMaster in LMasterTable.FieldsSort do
    begin
      LTargetColumn := _FindColumn(LTargetTable, LColMaster.Value.Name);
      if LTargetColumn = nil then
        Continue;
      if not SameText(Trim(LColMaster.Value.Description), Trim(LTargetColumn.Description)) then
        _ActionSetColumnComment(LColMaster.Value);
    end;
  end;
end;

// Cada m�todo Action* � o ponto onde UMA muta��o passa individualmente. O gate
// por policy vive aqui (mesmo padr�o do gate por TSupportedFeature existente):
// quando a opera��o n�o � permitida, a muta��o N�O entra na lista e um registro
// descritivo � anexado ao relat�rio de auditoria (SuppressedCommands).

procedure TDatabaseFactory._ActionAlterColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterColumn) then
  begin
    AddSuppressed(Format('ALTER COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterColumn.Create(AColumn));
end;

procedure TDatabaseFactory._ActionAlterColumnPosition(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterColumnPosition) then
  begin
    AddSuppressed(Format('ALTER COLUMN POSITION %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterColumnPosition.Create(AColumn));
end;

procedure TDatabaseFactory._ActionAlterDefaultValue(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterDefaultValue) then
  begin
    AddSuppressed(Format('ALTER DEFAULT %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterDefaultValue.Create(AColumn));
end;

procedure TDatabaseFactory._ActionCreateCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateCheck) then
  begin
    AddSuppressed(Format('CREATE CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateCheck.Create(ACheck));
end;

procedure TDatabaseFactory._ActionAlterCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterCheck) then
  begin
    AddSuppressed(Format('ALTER CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterCheck.Create(ACheck));
end;

procedure TDatabaseFactory._ActionCreateColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateColumn) then
  begin
    AddSuppressed(Format('CREATE COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateColumn.Create(AColumn));
end;

procedure TDatabaseFactory._ActionCreateForeignKey(AForeignKey: TForeignKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateForeignKey) then
  begin
    AddSuppressed(Format('CREATE FOREIGNKEY %s.%s suppressed by policy',
      [AForeignKey.Table.Name, AForeignKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateForeignKey.Create(AForeignKey));
end;

procedure TDatabaseFactory._ActionCreateIndexe(AIndexe: TIndexeKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateIndexe) then
  begin
    AddSuppressed(Format('CREATE INDEXE %s.%s suppressed by policy',
      [AIndexe.Table.Name, AIndexe.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateIndexe.Create(AIndexe));
end;

procedure TDatabaseFactory._ActionCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreatePrimaryKey) then
  begin
    AddSuppressed(Format('CREATE PRIMARYKEY %s.%s suppressed by policy',
      [APrimaryKey.Table.Name, APrimaryKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreatePrimaryKey.Create(APrimaryKey));
end;

procedure TDatabaseFactory._ActionCreateSequence(ASequence: TSequenceMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateSequence) then
  begin
    AddSuppressed(Format('CREATE SEQUENCE %s suppressed by policy',
      [ASequence.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateSequence.Create(ASequence));
end;

procedure TDatabaseFactory._ActionAlterSequence(ASequence: TSequenceMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterSequence) then
  begin
    AddSuppressed(Format('ALTER SEQUENCE %s suppressed by policy',
      [ASequence.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterSequence.Create(ASequence));
end;

procedure TDatabaseFactory._ActionCreateTable(ATable: TTableMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateTable) then
  begin
    AddSuppressed(Format('CREATE TABLE %s suppressed by policy', [ATable.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateTable.Create(ATable));
end;

procedure TDatabaseFactory._ActionCreateView(AView: TViewMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateView) then
  begin
    AddSuppressed(Format('CREATE VIEW %s suppressed by policy', [AView.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateView.Create(AView));
end;

procedure TDatabaseFactory._ActionCreateTrigger(ATrigger: TTriggerMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateTrigger) then
  begin
    AddSuppressed(Format('CREATE TRIGGER %s.%s suppressed by policy',
      [ATrigger.Table.Name, ATrigger.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateTrigger.Create(ATrigger));
end;

procedure TDatabaseFactory._ActionDropCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropCheck) then
  begin
    AddSuppressed(Format('DROP CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropCheck.Create(ACheck));
end;

procedure TDatabaseFactory._ActionDropColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropColumn) then
  begin
    AddSuppressed(Format('DROP COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropColumn.Create(AColumn));
end;

procedure TDatabaseFactory._ActionDropDefaultValue(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropDefaultValue) then
  begin
    AddSuppressed(Format('DROP DEFAULT %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropDefaultValue.Create(AColumn));
end;

procedure TDatabaseFactory._ActionDropForeignKey(AForeignKey: TForeignKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropForeignKey) then
  begin
    AddSuppressed(Format('DROP FOREIGNKEY %s.%s suppressed by policy',
      [AForeignKey.Table.Name, AForeignKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropForeignKey.Create(AForeignKey));
end;

procedure TDatabaseFactory._ActionDropIndexe(AIndexe: TIndexeKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropIndexe) then
  begin
    AddSuppressed(Format('DROP INDEXE %s.%s suppressed by policy',
      [AIndexe.Table.Name, AIndexe.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropIndexe.Create(AIndexe));
end;

procedure TDatabaseFactory._ActionDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropPrimaryKey) then
  begin
    AddSuppressed(Format('DROP PRIMARYKEY %s.%s suppressed by policy',
      [APrimaryKey.Table.Name, APrimaryKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropPrimaryKey.Create(APrimaryKey));
end;

procedure TDatabaseFactory._ActionDropSequence(ASequence: TSequenceMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropSequence) then
  begin
    AddSuppressed(Format('DROP SEQUENCE %s suppressed by policy',
      [ASequence.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropSequence.Create(ASequence));
end;

procedure TDatabaseFactory._ActionDropTable(ATable: TTableMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropTable) then
  begin
    AddSuppressed(Format('DROP TABLE %s suppressed by policy', [ATable.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropTable.Create(ATable));
end;

procedure TDatabaseFactory._ActionDropView(AView: TViewMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropView) then
  begin
    AddSuppressed(Format('DROP VIEW %s suppressed by policy', [AView.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropView.Create(AView));
end;

procedure TDatabaseFactory._ActionDropTrigger(ATrigger: TTriggerMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropTrigger) then
  begin
    AddSuppressed(Format('DROP TRIGGER %s.%s suppressed by policy',
      [ATrigger.Table.Name, ATrigger.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropTrigger.Create(ATrigger));
end;

procedure TDatabaseFactory._ActionCreateDomain(ADomain: TDomainMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateDomain) then
  begin
    AddSuppressed(Format('CREATE DOMAIN %s suppressed by policy', [ADomain.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateDomain.Create(ADomain));
end;

procedure TDatabaseFactory._ActionDropDomain(ADomain: TDomainMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropDomain) then
  begin
    AddSuppressed(Format('DROP DOMAIN %s suppressed by policy', [ADomain.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropDomain.Create(ADomain));
end;

procedure TDatabaseFactory._ActionCreateProcedure(AProcedure: TProcedureMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateProcedure) then
  begin
    AddSuppressed(Format('CREATE PROCEDURE %s suppressed by policy', [AProcedure.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateProcedure.Create(AProcedure));
end;

procedure TDatabaseFactory._ActionDropProcedure(AProcedure: TProcedureMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropProcedure) then
  begin
    AddSuppressed(Format('DROP PROCEDURE %s suppressed by policy', [AProcedure.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropProcedure.Create(AProcedure));
end;

procedure TDatabaseFactory._ActionSetTableComment(ATable: TTableMIK);
begin
  if not FPolicy.Allows(TDDLOperation.SetComment) then
  begin
    AddSuppressed(Format('COMMENT ON TABLE %s suppressed by policy', [ATable.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandSetComment.Create(ATable, nil));
end;

procedure TDatabaseFactory._ActionSetColumnComment(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.SetComment) then
  begin
    AddSuppressed(Format('COMMENT ON COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandSetComment.Create(nil, AColumn));
end;

// EnableForeignKeys / EnableTriggers s�o comandos de GUARDA (n�o muta��es):
// sempre emitidos, independentemente da policy.
procedure TDatabaseFactory._ActionEnableForeignKeys(AEnable: Boolean);
begin
  FDDLCommands.Add(TDDLCommandEnableForeignKeys.Create(AEnable));
end;

procedure TDatabaseFactory._ActionEnableTriggers(AEnable: Boolean);
begin
  FDDLCommands.Add(TDDLCommandEnableTriggers.Create(AEnable));
end;

end.
