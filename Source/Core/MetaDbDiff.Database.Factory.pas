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
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.Compare.Options;

type
  TDatabaseFactory = class(TDatabaseAbstract)
  private
    procedure CompareTables(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure CompareViews(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure CompareSequences(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure CompareTablesForeignKeys(AMasterDB, ATargetDB: TCatalogMetadataMIK);
    procedure CompareForeignKeys(AMasterTable, ATargetTable: TTableMIK);
    procedure CompareColumns(AMasterTable, ATargetTable: TTableMIK);
    procedure ComparePrimaryKey(AMasterTable, ATargetTable: TTableMIK);
    procedure CompareIndexes(AMasterTable, ATargetTable: TTableMIK);
    procedure CompareTriggers(AMasterTable, ATargetTable: TTableMIK);
    procedure CompareChecks(AMasterTable, ATargetTable: TTableMIK);
    procedure ActionCreateTable(ATable: TTableMIK);
    procedure ActionCreateIndexe(AIndexe: TIndexeKeyMIK);
    procedure ActionCreateCheck(ACheck: TCheckMIK);
    procedure ActionCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK);
    procedure ActionCreateColumn(AColumn: TColumnMIK);
    procedure ActionCreateSequence(ASequence: TSequenceMIK);
    procedure ActionCreateForeignKey(AForeignKey: TForeignKeyMIK);
    procedure ActionCreateView(AView: TViewMIK);
    procedure ActionCreateTrigger(ATrigger: TTriggerMIK);
    procedure ActionDropTable(ATable: TTableMIK);
    procedure ActionDropColumn(AColumn: TColumnMIK);
    procedure ActionDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK);
    procedure ActionDropSequence(ASequence: TSequenceMIK);
    procedure ActionDropIndexe(AIndexe: TIndexeKeyMIK);
    procedure ActionDropForeignKey(AForeignKey: TForeignKeyMIK);
    procedure ActionDropCheck(ACheck: TCheckMIK);
    procedure ActionDropView(AView: TViewMIK);
    procedure ActionDropTrigger(ATrigger: TTriggerMIK);
    procedure ActionAlterColumn(AColumn: TColumnMIK);
    procedure ActionAlterColumnPosition(AColumn: TColumnMIK);
    procedure ActionDropDefaultValue(AColumn: TColumnMIK);
    procedure ActionAlterDefaultValue(AColumn: TColumnMIK);
    procedure ActionAlterCheck(ACheck: TCheckMIK);
    /// <summary>
    /// Gera script que desabilita todas as ForeignKeys
    /// </summary>
    procedure ActionEnableForeignKeys(AEnable: Boolean);
    procedure ActionEnableTriggers(AEnable: Boolean);
    function DeepEqualsColumn(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function KeepEqualsPosition(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function DeepEqualsDefaultValue(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
    function DeepEqualsForeignKey(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function DeepEqualsForeignKeyFromColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function DeepEqualsForeignKeyToColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
    function DeepEqualsIndexe(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
    function DeepEqualsIndexeColumns(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
    function SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>;
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

function TDatabaseFactory.DeepEqualsColumn(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
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

function TDatabaseFactory.DeepEqualsDefaultValue(AMasterColumn, ATargetColumn: TColumnMIK): Boolean;
begin
  Result := True;
  if AMasterColumn.DefaultValue <> ATargetColumn.DefaultValue then
    Exit(False);
end;

function TDatabaseFactory.DeepEqualsForeignKey(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
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

function TDatabaseFactory.DeepEqualsIndexe(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
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
  ActionEnableForeignKeys(False);
  // Gera script que desabilita todas as Triggers
  ActionEnableTriggers(False);
  // Compara Tabelas
  CompareTables(AMasterDB, ATargetDB);
  // Compara Views
  CompareViews(AMasterDB, ATargetDB);
  // Compara Sequences
  CompareSequences(AMasterDB, ATargetDB);
  // Compara ForeingKeys
  CompareTablesForeignKeys(AMasterDB, ATargetDB);
  // Gera script que habilita todas as ForeignKeys
  ActionEnableForeignKeys(True);
  // Gera script que habilita todas as Triggers
  ActionEnableTriggers(True);
  // Build the command text right after generation so GetCommandList exposes
  // the SQL even when the commands are not executed (preview mode).
  // BuildCommand is deterministic, so rebuilding it again inside descendant
  // ExecuteDDLCommands overrides just reassigns the same text.
  for LDDLCommand in FDDLCommands do
    LDDLCommand.BuildCommand(FGeneratorCommand);
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

function TDatabaseFactory.KeepEqualsPosition(AMasterColumn,
  ATargetColumn: TColumnMIK): Boolean;
begin
  Result := True;
  if (AMasterColumn.Position <> ATargetColumn.Position) then
    Exit(False);
end;

function TDatabaseFactory.SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>;
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

procedure TDatabaseFactory.CompareTables(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LTableMaster: TPair<String, TTableMIK>;
  LTableTarget: TPair<String, TTableMIK>;
begin
  // Gera script de exclus�o de tabela, caso n�o exista um modelo para ela no banco.
  for LTableTarget in ATargetDB.TablesSort do
  begin
    if not AMasterDB.Tables.ContainsKey(LTableTarget.Key) then
      ActionDropTable(LTableTarget.Value);
  end;
  // Gera script de cria��o de tabela, caso a tabela do modelo n�o exista no banco.
  for LTableMaster in AMasterDB.TablesSort do
  begin
    if ATargetDB.Tables.ContainsKey(LTableMaster.Key) then
    begin
      // Table Columns
      CompareColumns(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table PrimaryKey
      if (LTableMaster.Value.PrimaryKey.Fields.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].PrimaryKey.Fields.Count > 0) then
        ComparePrimaryKey(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Indexes
      if (LTableMaster.Value.IndexeKeys.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].IndexeKeys.Count > 0) then
        CompareIndexes(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Checks
      if (LTableMaster.Value.Checks.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].Checks.Count > 0) then
        CompareChecks(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);

      // Table Triggers
      if (LTableMaster.Value.Triggers.Count > 0) or
         (ATargetDB.Tables.Items[LTableMaster.Key].Triggers.Count > 0) then
        CompareTriggers(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);
    end
    else
      ActionCreateTable(LTableMaster.Value);
  end;
end;

procedure TDatabaseFactory.CompareTriggers(AMasterTable, ATargetTable: TTableMIK);
var
  LTriggerMaster: TPair<String, TTriggerMIK>;
  LTriggerTarget: TPair<String, TTriggerMIK>;
  LTrigger: TTriggerMIK;
begin
  if TSupportedFeature.Triggers in FGeneratorCommand.SupportedFeatures then
  begin
    // Remove trigger que n�o existe no modelo.
    for LTriggerTarget in SortedPairs<TTriggerMIK>(ATargetTable.Triggers) do
    begin
      if not AMasterTable.Triggers.ContainsKey(LTriggerTarget.Key) then
        ActionDropTrigger(LTriggerTarget.Value);
    end;
    // Gera script de cria��o de trigger, caso a trigger do modelo n�o exista no banco.
    for LTriggerMaster in SortedPairs<TTriggerMIK>(AMasterTable.Triggers) do
    begin
      if ATargetTable.Triggers.ContainsKey(LTriggerMaster.Key) then
      begin
        LTrigger := ATargetTable.Triggers.Items[LTriggerMaster.Key];
        // Recreate the trigger when the script differs from the model.
        if CompareText(LTriggerMaster.Value.Script, LTrigger.Script) <> 0 then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas;
          // caso contr�rio suprime o par inteiro (nunca deixa drop �rf�o).
          if FPolicy.Allows(TDDLOperation.DropTrigger) and
             FPolicy.Allows(TDDLOperation.CreateTrigger) then
          begin
            ActionDropTrigger(LTrigger);
            ActionCreateTrigger(LTriggerMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE TRIGGER %s.%s suppressed by policy',
              [LTrigger.Table.Name, LTrigger.Name]));
        end;
      end
      else
        ActionCreateTrigger(LTriggerMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory.CompareViews(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LViewMaster: TPair<String, TViewMIK>;
  LViewTarget: TPair<String, TViewMIK>;
  LView: TViewMIK;
begin
  if TSupportedFeature.Views in FGeneratorCommand.SupportedFeatures then
  begin
    // Gera script de exclus�o da view, caso n�o exista um modelo para ela no banco.
    for LViewTarget in SortedPairs<TViewMIK>(ATargetDB.Views) do
    begin
      if not AMasterDB.Views.ContainsKey(LViewTarget.Key) then
        ActionDropView(LViewTarget.Value);
    end;
    // Gera script de cria��o da view, caso a view do modelo n�o exista no banco.
    for LViewMaster in SortedPairs<TViewMIK>(AMasterDB.Views) do
    begin
      if ATargetDB.Views.ContainsKey(LViewMaster.Key) then
      begin
        LView := ATargetDB.Views.Items[LViewMaster.Key];
        // Recreate the view when the script differs from the model.
        if CompareText(LViewMaster.Value.Script, LView.Script) <> 0 then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
          if FPolicy.Allows(TDDLOperation.DropView) and
             FPolicy.Allows(TDDLOperation.CreateView) then
          begin
            ActionDropView(LView);
            ActionCreateView(LViewMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE VIEW %s suppressed by policy',
              [LView.Name]));
        end;
      end
      else
        ActionCreateView(LViewMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory.CompareChecks(AMasterTable, ATargetTable: TTableMIK);
var
  LCheckMaster: TPair<String, TCheckMIK>;
  LCheckTarget: TPair<String, TCheckMIK>;
  LCheck: TCheckMIK;
begin
  if TSupportedFeature.Checks in FGeneratorCommand.SupportedFeatures then
  begin
    // Drop checks that exist in the database but not in the model.
    for LCheckTarget in SortedPairs<TCheckMIK>(ATargetTable.Checks) do
    begin
      if not AMasterTable.Checks.ContainsKey(LCheckTarget.Key) then
        ActionDropCheck(LCheckTarget.Value);
    end;
    // Create checks missing in the database; alter when the condition differs.
    for LCheckMaster in SortedPairs<TCheckMIK>(AMasterTable.Checks) do
    begin
      if ATargetTable.Checks.ContainsKey(LCheckMaster.Key) then
      begin
        LCheck := ATargetTable.Checks.Items[LCheckMaster.Key];
        if CompareText(LCheckMaster.Value.Condition, LCheck.Condition) <> 0 then
          ActionAlterCheck(LCheckMaster.Value);
      end
      else
        ActionCreateCheck(LCheckMaster.Value);
    end;
  end;
end;

procedure TDatabaseFactory.CompareColumns(AMasterTable, ATargetTable: TTableMIK);
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
      ActionDropColumn(LColumnTarget.Value);
  end;
  // Adiciona coluna do modelo que n�o exista no banco
  // Compara coluna que exista no modelo e no banco
  LReorderColumns := False;
  for LColumnMaster in AMasterTable.FieldsSort do
  begin
    LColumn := ExistTargetColumn(LColumnMaster.Value.Name);
    if LColumn = nil then
      ActionCreateColumn(LColumnMaster.Value)
    else
    begin
      if not DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        ActionAlterColumn(LColumnMaster.Value);

      if not KeepEqualsPosition(LColumnMaster.Value, LColumn) then
        LReorderColumns := True;

      // Compara DefaultValue
      if not DeepEqualsDefaultValue(LColumnMaster.Value, LColumn) then
      begin
        if Length(LColumnMaster.Value.DefaultValue) > 0 then
          ActionAlterDefaultValue(LColumnMaster.Value)
        else
          ActionDropDefaultValue(LColumn);
      end;
    end;
  end;
  if ComparerFieldPosition and LReorderColumns then
    for LColumnMaster in AMasterTable.FieldsSort do
    begin
      ActionAlterColumnPosition(LColumnMaster.Value);
    end;
end;

procedure TDatabaseFactory.CompareTablesForeignKeys(AMasterDB, ATargetDB: TCatalogMetadataMIK);
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
        CompareForeignKeys(LTableMaster.Value, ATargetDB.Tables.Items[LTableMaster.Key]);
    end
    else
    begin
      // Gera script de cria��o dos ForeignKey da nova tabela.
      if FDriverName <> dnSQLite then
        for LForeignKeyMaster in SortedPairs<TForeignKeyMIK>(LTableMaster.Value.ForeignKeys) do
          ActionCreateForeignKey(LForeignKeyMaster.Value);
    end;
  end;
end;

function TDatabaseFactory.DeepEqualsForeignKeyFromColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
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
      if not DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

procedure TDatabaseFactory.CompareForeignKeys(AMasterTable, ATargetTable: TTableMIK);
var
  LForeignKeyMaster: TPair<String, TForeignKeyMIK>;
  LForeignKeyTarget: TPair<String, TForeignKeyMIK>;
begin
  if TSupportedFeature.ForeignKeys in FGeneratorCommand.SupportedFeatures then
  begin
    // Remove indexe que n�o existe no modelo.
    for LForeignKeyTarget in SortedPairs<TForeignKeyMIK>(ATargetTable.ForeignKeys) do
    begin
      if not AMasterTable.ForeignKeys.ContainsKey(LForeignKeyTarget.Key) then
        ActionDropForeignKey(LForeignKeyTarget.Value);
    end;
    // Gera script de cria��o de indexe, caso a indexe do modelo n�o exista no banco.
    for LForeignKeyMaster in SortedPairs<TForeignKeyMIK>(AMasterTable.ForeignKeys) do
    begin
      if ATargetTable.ForeignKeys.ContainsKey(LForeignKeyMaster.Key) then
      begin
        // Checa diferen�a do ForeignKey
        LForeignKeyTarget.Value := ATargetTable.ForeignKeys.Items[LForeignKeyMaster.Key];

        if (not DeepEqualsForeignKey(LForeignKeyMaster.Value, LForeignKeyTarget.Value)) or
           (not DeepEqualsForeignKeyFromColumns(LForeignKeyMaster.Value, LForeignKeyTarget.Value)) or
           (not DeepEqualsForeignKeyToColumns  (LForeignKeyMaster.Value, LForeignKeyTarget.Value)) then
        begin
          // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
          if FPolicy.Allows(TDDLOperation.DropForeignKey) and
             FPolicy.Allows(TDDLOperation.CreateForeignKey) then
          begin
            ActionDropForeignKey(LForeignKeyTarget.Value);
            ActionCreateForeignKey(LForeignKeyMaster.Value);
          end
          else
            AddSuppressed(Format('RECREATE FOREIGNKEY %s.%s suppressed by policy',
              [LForeignKeyTarget.Value.Table.Name, LForeignKeyTarget.Value.Name]));
        end;
      end
      else
        ActionCreateForeignKey(LForeignKeyMaster.Value);
    end;
  end;
end;

function TDatabaseFactory.DeepEqualsForeignKeyToColumns(AMasterForeignKey, ATargetForeignKey: TForeignKeyMIK): Boolean;
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
      if not DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

function TDatabaseFactory.DeepEqualsIndexeColumns(AMasterIndexe, ATargetIndexe: TIndexeKeyMIK): Boolean;
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
      if not DeepEqualsColumn(LColumnMaster.Value, LColumn) then
        Exit(False);
    end;
  end;
end;

procedure TDatabaseFactory.CompareIndexes(AMasterTable, ATargetTable: TTableMIK);
var
  LIndexeMaster: TPair<String, TIndexeKeyMIK>;
  LIndexeTarget: TPair<String, TIndexeKeyMIK>;
begin
  // Remove indexe que n�o existe no modelo.
  for LIndexeTarget in SortedPairs<TIndexeKeyMIK>(ATargetTable.IndexeKeys) do
  begin
    if not AMasterTable.IndexeKeys.ContainsKey(LIndexeTarget.Key) then
      ActionDropIndexe(LIndexeTarget.Value);
  end;
  // Gera script de cria��o de indexe, caso a indexe do modelo n�o exista no banco.
  for LIndexeMaster in SortedPairs<TIndexeKeyMIK>(AMasterTable.IndexeKeys) do
  begin
    if ATargetTable.IndexeKeys.ContainsKey(LIndexeMaster.Key) then
    begin
      LIndexeTarget.Value := ATargetTable.IndexeKeys.Items[LIndexeMaster.Key];
      if (not DeepEqualsIndexe(LIndexeMaster.Value, LIndexeTarget.Value)) or
         (not DeepEqualsIndexeColumns(LIndexeMaster.Value, LIndexeTarget.Value)) then
      begin
        // Par DROP+CREATE: s� emite se AMBAS as opera��es forem permitidas.
        if FPolicy.Allows(TDDLOperation.DropIndexe) and
           FPolicy.Allows(TDDLOperation.CreateIndexe) then
        begin
          ActionDropIndexe(LIndexeTarget.Value);
          ActionCreateIndexe(LIndexeMaster.Value);
        end
        else
          AddSuppressed(Format('RECREATE INDEXE %s.%s suppressed by policy',
            [LIndexeTarget.Value.Table.Name, LIndexeTarget.Value.Name]));
      end;
    end
    else
      ActionCreateIndexe(LIndexeMaster.Value);
  end;
end;

procedure TDatabaseFactory.ComparePrimaryKey(AMasterTable, ATargetTable: TTableMIK);
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
    ActionDropPrimaryKey(ATargetTable.PrimaryKey);
  if LRecreatePK then
    ActionCreatePrimaryKey(AMasterTable.PrimaryKey);
end;

procedure TDatabaseFactory.CompareSequences(AMasterDB, ATargetDB: TCatalogMetadataMIK);
var
  LSequenceMaster: TPair<String, TSequenceMIK>;
  LSequenceTarget: TPair<String, TSequenceMIK>;
begin
  if TSupportedFeature.Sequences in FGeneratorCommand.SupportedFeatures then
  begin
    // Checa se existe alguma sequence no banco, da qual n�o exista nos modelos
    // para exclus�o da mesma.
    for LSequenceTarget in SortedPairs<TSequenceMIK>(ATargetDB.Sequences) do
    begin
      if not AMasterDB.Sequences.ContainsKey(LSequenceTarget.Key) then
        ActionDropSequence(LSequenceTarget.Value);
    end;
    // Checa se existe a sequence no banco, se n�o existir cria se existir.
    for LSequenceMaster in SortedPairs<TSequenceMIK>(AMasterDB.Sequences) do
    begin
      if not ATargetDB.Sequences.ContainsKey(LSequenceMaster.Key) then
        ActionCreateSequence(LSequenceMaster.Value);
    end;
  end;
end;

// Cada m�todo Action* � o ponto onde UMA muta��o passa individualmente. O gate
// por policy vive aqui (mesmo padr�o do gate por TSupportedFeature existente):
// quando a opera��o n�o � permitida, a muta��o N�O entra na lista e um registro
// descritivo � anexado ao relat�rio de auditoria (SuppressedCommands).

procedure TDatabaseFactory.ActionAlterColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterColumn) then
  begin
    AddSuppressed(Format('ALTER COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterColumn.Create(AColumn));
end;

procedure TDatabaseFactory.ActionAlterColumnPosition(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterColumnPosition) then
  begin
    AddSuppressed(Format('ALTER COLUMN POSITION %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterColumnPosition.Create(AColumn));
end;

procedure TDatabaseFactory.ActionAlterDefaultValue(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterDefaultValue) then
  begin
    AddSuppressed(Format('ALTER DEFAULT %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterDefaultValue.Create(AColumn));
end;

procedure TDatabaseFactory.ActionCreateCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateCheck) then
  begin
    AddSuppressed(Format('CREATE CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateCheck.Create(ACheck));
end;

procedure TDatabaseFactory.ActionAlterCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.AlterCheck) then
  begin
    AddSuppressed(Format('ALTER CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandAlterCheck.Create(ACheck));
end;

procedure TDatabaseFactory.ActionCreateColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateColumn) then
  begin
    AddSuppressed(Format('CREATE COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateColumn.Create(AColumn));
end;

procedure TDatabaseFactory.ActionCreateForeignKey(AForeignKey: TForeignKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateForeignKey) then
  begin
    AddSuppressed(Format('CREATE FOREIGNKEY %s.%s suppressed by policy',
      [AForeignKey.Table.Name, AForeignKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateForeignKey.Create(AForeignKey));
end;

procedure TDatabaseFactory.ActionCreateIndexe(AIndexe: TIndexeKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateIndexe) then
  begin
    AddSuppressed(Format('CREATE INDEXE %s.%s suppressed by policy',
      [AIndexe.Table.Name, AIndexe.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateIndexe.Create(AIndexe));
end;

procedure TDatabaseFactory.ActionCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreatePrimaryKey) then
  begin
    AddSuppressed(Format('CREATE PRIMARYKEY %s.%s suppressed by policy',
      [APrimaryKey.Table.Name, APrimaryKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreatePrimaryKey.Create(APrimaryKey));
end;

procedure TDatabaseFactory.ActionCreateSequence(ASequence: TSequenceMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateSequence) then
  begin
    AddSuppressed(Format('CREATE SEQUENCE %s suppressed by policy',
      [ASequence.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateSequence.Create(ASequence));
end;

procedure TDatabaseFactory.ActionCreateTable(ATable: TTableMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateTable) then
  begin
    AddSuppressed(Format('CREATE TABLE %s suppressed by policy', [ATable.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateTable.Create(ATable));
end;

procedure TDatabaseFactory.ActionCreateView(AView: TViewMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateView) then
  begin
    AddSuppressed(Format('CREATE VIEW %s suppressed by policy', [AView.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateView.Create(AView));
end;

procedure TDatabaseFactory.ActionCreateTrigger(ATrigger: TTriggerMIK);
begin
  if not FPolicy.Allows(TDDLOperation.CreateTrigger) then
  begin
    AddSuppressed(Format('CREATE TRIGGER %s.%s suppressed by policy',
      [ATrigger.Table.Name, ATrigger.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandCreateTrigger.Create(ATrigger));
end;

procedure TDatabaseFactory.ActionDropCheck(ACheck: TCheckMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropCheck) then
  begin
    AddSuppressed(Format('DROP CHECK %s.%s suppressed by policy',
      [ACheck.Table.Name, ACheck.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropCheck.Create(ACheck));
end;

procedure TDatabaseFactory.ActionDropColumn(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropColumn) then
  begin
    AddSuppressed(Format('DROP COLUMN %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropColumn.Create(AColumn));
end;

procedure TDatabaseFactory.ActionDropDefaultValue(AColumn: TColumnMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropDefaultValue) then
  begin
    AddSuppressed(Format('DROP DEFAULT %s.%s suppressed by policy',
      [AColumn.Table.Name, AColumn.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropDefaultValue.Create(AColumn));
end;

procedure TDatabaseFactory.ActionDropForeignKey(AForeignKey: TForeignKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropForeignKey) then
  begin
    AddSuppressed(Format('DROP FOREIGNKEY %s.%s suppressed by policy',
      [AForeignKey.Table.Name, AForeignKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropForeignKey.Create(AForeignKey));
end;

procedure TDatabaseFactory.ActionDropIndexe(AIndexe: TIndexeKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropIndexe) then
  begin
    AddSuppressed(Format('DROP INDEXE %s.%s suppressed by policy',
      [AIndexe.Table.Name, AIndexe.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropIndexe.Create(AIndexe));
end;

procedure TDatabaseFactory.ActionDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropPrimaryKey) then
  begin
    AddSuppressed(Format('DROP PRIMARYKEY %s.%s suppressed by policy',
      [APrimaryKey.Table.Name, APrimaryKey.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropPrimaryKey.Create(APrimaryKey));
end;

procedure TDatabaseFactory.ActionDropSequence(ASequence: TSequenceMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropSequence) then
  begin
    AddSuppressed(Format('DROP SEQUENCE %s suppressed by policy',
      [ASequence.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropSequence.Create(ASequence));
end;

procedure TDatabaseFactory.ActionDropTable(ATable: TTableMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropTable) then
  begin
    AddSuppressed(Format('DROP TABLE %s suppressed by policy', [ATable.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropTable.Create(ATable));
end;

procedure TDatabaseFactory.ActionDropView(AView: TViewMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropView) then
  begin
    AddSuppressed(Format('DROP VIEW %s suppressed by policy', [AView.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropView.Create(AView));
end;

procedure TDatabaseFactory.ActionDropTrigger(ATrigger: TTriggerMIK);
begin
  if not FPolicy.Allows(TDDLOperation.DropTrigger) then
  begin
    AddSuppressed(Format('DROP TRIGGER %s.%s suppressed by policy',
      [ATrigger.Table.Name, ATrigger.Name]));
    Exit;
  end;
  FDDLCommands.Add(TDDLCommandDropTrigger.Create(ATrigger));
end;

// EnableForeignKeys / EnableTriggers s�o comandos de GUARDA (n�o muta��es):
// sempre emitidos, independentemente da policy.
procedure TDatabaseFactory.ActionEnableForeignKeys(AEnable: Boolean);
begin
  FDDLCommands.Add(TDDLCommandEnableForeignKeys.Create(AEnable));
end;

procedure TDatabaseFactory.ActionEnableTriggers(AEnable: Boolean);
begin
  FDDLCommands.Add(TDDLCommandEnableTriggers.Create(AEnable));
end;

end.
