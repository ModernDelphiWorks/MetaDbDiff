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

{ @abstract(MetaDbDiff Framework.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)

  Full, faithful serialization of TCatalogMetadataMIK (MetaDbDiff.Database.Mapping.pas)
  to/from a self-contained JSON file, using ONLY System.JSON from the RTL (no
  external dependency). This is what makes the "metadata snapshot" feature
  possible: extract the catalog on a machine that has access to the source
  database (or to the decorated model classes), save it to a file, ship the
  file to the client machine, and load it back there as the MASTER side of a
  diff (MetaDbDiff.Database.SnapshotCompare.pas) - without the client ever
  needing network access to the source database.

  Envelope shape (see ToJson/FromJson) - a JSON object with these top-level
  members (deliberately NOT shown with literal JSON brace characters here:
  this doc comment is itself a brace-delimited Object Pascal comment, and
  those do not nest, so embedding literal JSON braces would truncate the
  comment early):
    - FormatVersion:      integer, see MetadataSnapshotFormatVersion below.
    - DriverName:         string, e.g. "Firebird" (see TStrDriverName).
    - GeneratedAt:        string, e.g. "2026-07-16T10:00:00" (ISO 8601).
    - SourceDescription:  string, free text set by the caller.
    - Catalog:            object, the serialized TCatalogMetadataMIK - see
                           _CatalogToJson for its own shape.

  Serialization decisions:
    - Enums (TFieldType, TRuleAction, TSortingOrder) are stored by NAME (via
      TypInfo.GetEnumName/GetEnumValue), never by ordinal, so a snapshot
      survives additions/reorders of these enums across MetaDbDiff versions -
      an ordinal-based encoding would silently corrupt on such a change.
    - TDriverName is stored via the existing TStrDriverName lookup table (e.g.
      "Firebird"), for the same reason plus consistency with error messages
      elsewhere in the codebase that already print TStrDriverName[...].
    - Dictionary KEYS are never stored (they are derived, not source data): on
      load every TObjectDictionary is rebuilt using the EXACT SAME convention
      the live extractors already use (see MetaDbDiff.Metadata.Firebird.pas
      and MetaDbDiff.Metadata.Model.pas) - UpperCase(Name) for
      Tables/ForeignKeys/IndexeKeys/Checks/Triggers/Sequences/Views, and
      FormatFloat('000000', Position) for the column collections that are
      keyed by position (Table.Fields, PrimaryKey.Fields,
      ForeignKey.From/ToFields, IndexeKey.Fields) - EXCEPT TViewMIK.Fields,
      which the extractors key by UpperCase(ColumnName) because view columns
      never carry a meaningful Position. Reproducing these conventions exactly
      is what makes TDatabaseFactory's ContainsKey/Items[key] lookups (used to
      compare Tables/ForeignKeys/IndexeKeys/Checks/Triggers/Sequences/Views by
      name) work correctly between a loaded snapshot and a freshly extracted
      live catalog - see MetaDbDiff.Database.Factory.pas, e.g. CompareTables.
    - JSON arrays are written in a deterministic (key-sorted) order, mirroring
      TDatabaseFactory._SortedPairs / TTableMIK.FieldsSort, so re-saving an
      unchanged catalog produces byte-identical output - useful for diffing
      snapshot files under version control.

  Cross-dialect limitation (documented here and repeated in
  MetaDbDiff.Database.SnapshotCompare.pas, the class that actually consumes a
  snapshot as the master side of a diff): TColumnMIK.TypeName is stored
  VERBATIM, exactly as the driver that produced the snapshot generated it
  (e.g. Firebird's 'VARCHAR(%l)', Oracle's 'VARCHAR2(%l)'). If a snapshot
  produced by one dialect is later diffed against a TARGET database of a
  DIFFERENT dialect, TDatabaseFactory.DeepEqualsColumn compares TypeName as
  plain text and will very likely flag a mismatch even for semantically
  equal types, generating false ALTER COLUMN commands. Recommendation: keep
  the snapshot's origin dialect and the target database's dialect the same.
}

unit MetaDbDiff.Metadata.Snapshot;

interface

uses
  DB,
  TypInfo,
  Classes,
  SysUtils,
  System.JSON,
  System.DateUtils,
  Generics.Collections,
  Generics.Defaults,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping;

const
  /// <summary>
  ///   Current snapshot JSON envelope format version. Bump this - and extend
  ///   TMetadataSnapshot.LoadInto with a migration path for the older shape -
  ///   whenever the envelope or the catalog JSON shape changes in a way older
  ///   readers cannot parse. A snapshot whose FormatVersion is greater than
  ///   this constant is rejected with a clear error (see LoadInto): this
  ///   library refuses to guess the shape of a format from the future.
  /// </summary>
  // FRENTE 15: v2 acrescenta as colecoes Domains e Procedures ao Catalog. A
  // RETROCOMPATIBILIDADE e total: um envelope v1 (sem essas chaves) carrega
  // normalmente - _JsonArrayOrNil devolve nil para chaves ausentes e as colecoes
  // ficam vazias. A rejeicao continua identica para FormatVersion > 2 (futuro) e
  // < 1 (arquivo adulterado).
  MetadataSnapshotFormatVersion = 2;

type
  /// <summary>
  ///   Raised for every snapshot-specific failure (unsupported/future format
  ///   version, corrupted/invalid JSON, unknown enum or driver name found in
  ///   the file) so callers can tell a snapshot problem apart from any other
  ///   Exception with a simple "on E: EMetadataSnapshotError" handler.
  /// </summary>
  EMetadataSnapshotError = class(Exception);

  /// <summary>
  ///   Serializes/deserializes a TCatalogMetadataMIK catalog to/from a
  ///   self-contained JSON snapshot. See the unit header comment for the
  ///   envelope shape and every serialization decision.
  /// </summary>
  TMetadataSnapshot = class
  private
    { --- enum/driver name <-> string helpers --- }
    class function _FieldTypeToName(AValue: TFieldType): String; static;
    class function _NameToFieldType(const AName: String): TFieldType; static;
    class function _RuleActionToName(AValue: TRuleAction): String; static;
    class function _NameToRuleAction(const AName: String): TRuleAction; static;
    class function _SortingOrderToName(AValue: TSortingOrder): String; static;
    class function _NameToSortingOrder(const AName: String): TSortingOrder; static;
    class function _DriverNameToStr(ADriverName: TDriverName): String; static;
    class function _StrToDriverNameChecked(const AValue: String): TDriverName; static;

    class function _PosKey(APosition: Integer): String; static;
    class function _JsonArrayOrNil(AJson: TJSONObject; const AKey: String): TJSONArray; static;
    class function _JsonObjectOrNil(AJson: TJSONObject; const AKey: String): TJSONObject; static;
    class function _SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>; static;

    { --- MIK -> JSON --- }
    class function _ColumnToJson(AColumn: TColumnMIK): TJSONObject; static;
    class function _PrimaryKeyToJson(APrimaryKey: TPrimaryKeyMIK): TJSONObject; static;
    class function _ForeignKeyToJson(AForeignKey: TForeignKeyMIK): TJSONObject; static;
    class function _IndexeKeyToJson(AIndexeKey: TIndexeKeyMIK): TJSONObject; static;
    class function _CheckToJson(ACheck: TCheckMIK): TJSONObject; static;
    class function _TriggerToJson(ATrigger: TTriggerMIK): TJSONObject; static;
    class function _TableToJson(ATable: TTableMIK): TJSONObject; static;
    class function _ViewToJson(AView: TViewMIK): TJSONObject; static;
    class function _SequenceToJson(ASequence: TSequenceMIK): TJSONObject; static;
    class function _DomainToJson(ADomain: TDomainMIK): TJSONObject; static;
    class function _ProcedureToJson(AProcedure: TProcedureMIK): TJSONObject; static;
    class function _CatalogToJson(ACatalog: TCatalogMetadataMIK): TJSONObject; static;

    { --- JSON -> MIK --- }
    class function _JsonToColumn(AJson: TJSONObject; AOwnerTable: TTableMIK): TColumnMIK; static;
    class procedure _JsonToPrimaryKey(AJson: TJSONObject; ATable: TTableMIK); static;
    class function _JsonToForeignKey(AJson: TJSONObject; ATable: TTableMIK): TForeignKeyMIK; static;
    class function _JsonToIndexeKey(AJson: TJSONObject; ATable: TTableMIK): TIndexeKeyMIK; static;
    class function _JsonToCheck(AJson: TJSONObject; ATable: TTableMIK): TCheckMIK; static;
    class function _JsonToTrigger(AJson: TJSONObject; ATable: TTableMIK): TTriggerMIK; static;
    class function _JsonToTable(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TTableMIK; static;
    class function _JsonToView(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TViewMIK; static;
    class function _JsonToSequence(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TSequenceMIK; static;
    class function _JsonToDomain(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TDomainMIK; static;
    class function _JsonToProcedure(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TProcedureMIK; static;
    class procedure _JsonToCatalog(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK); static;
  public
    /// <summary>
    ///   Builds the full envelope (FormatVersion + DriverName + GeneratedAt +
    ///   SourceDescription + Catalog) for ACatalog. The caller owns the
    ///   returned TJSONObject and must free it.
    /// </summary>
    class function ToJson(ACatalog: TCatalogMetadataMIK; ADriverName: TDriverName;
      const ADescription: String = ''): TJSONObject; static;

    /// <summary>
    ///   Parses an envelope previously produced by ToJson and populates
    ///   ACatalogMetadata (an ALREADY EXISTING, caller-owned catalog) in
    ///   place - clearing it first. Used both by FromJson/LoadFromStream/
    ///   LoadFromFile (which create a fresh catalog first) and directly by
    ///   MetaDbDiff.Metadata.Snapshot.Factory.pas's TMetadataSnapshotFactory
    ///   (which receives the catalog to populate from TDatabaseFactory).
    ///   Raises EMetadataSnapshotError with a clear message when
    ///   AJson.FormatVersion is greater than MetadataSnapshotFormatVersion, or
    ///   when the envelope/catalog structure is missing required fields.
    /// </summary>
    class procedure LoadInto(AJson: TJSONObject; ACatalogMetadata: TCatalogMetadataMIK;
      out ADriverName: TDriverName; out ADescription, AGeneratedAt: String;
      out AFormatVersion: Integer); static;

    /// <summary>
    ///   Parses an envelope and returns a NEW catalog (ownership transferred
    ///   to the caller). Convenience overload of LoadInto for tests/callers
    ///   that do not need the envelope's DriverName/SourceDescription/
    ///   GeneratedAt/FormatVersion.
    /// </summary>
    class function FromJson(AJson: TJSONObject): TCatalogMetadataMIK; static;

    class procedure SaveToStream(ACatalog: TCatalogMetadataMIK; AStream: TStream;
      ADriverName: TDriverName; const ADescription: String = ''); static;
    class function LoadFromStream(AStream: TStream): TCatalogMetadataMIK; overload; static;
    class function LoadFromStream(AStream: TStream; out ADriverName: TDriverName;
      out ADescription, AGeneratedAt: String; out AFormatVersion: Integer): TCatalogMetadataMIK; overload; static;

    class procedure SaveToFile(ACatalog: TCatalogMetadataMIK; const AFileName: String;
      ADriverName: TDriverName; const ADescription: String = ''); static;
    class function LoadFromFile(const AFileName: String): TCatalogMetadataMIK; overload; static;
    class function LoadFromFile(const AFileName: String; out ADriverName: TDriverName;
      out ADescription, AGeneratedAt: String; out AFormatVersion: Integer): TCatalogMetadataMIK; overload; static;
  end;

implementation

{ Enum <-> name helpers. TFieldType/TRuleAction/TSortingOrder are plain
  (non-scoped) Delphi enums, so GetEnumName/GetEnumValue work directly off
  their TypeInfo. Serializing by NAME (not Ord) is deliberate - see the unit
  header comment. }

class function TMetadataSnapshot._FieldTypeToName(AValue: TFieldType): String;
begin
  Result := GetEnumName(TypeInfo(TFieldType), Ord(AValue));
end;

class function TMetadataSnapshot._NameToFieldType(const AName: String): TFieldType;
var
  LOrdinal: Integer;
begin
  LOrdinal := GetEnumValue(TypeInfo(TFieldType), AName);
  if LOrdinal < 0 then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: TFieldType desconhecido "%s".', [AName]);
  Result := TFieldType(LOrdinal);
end;

class function TMetadataSnapshot._RuleActionToName(AValue: TRuleAction): String;
begin
  Result := GetEnumName(TypeInfo(TRuleAction), Ord(AValue));
end;

class function TMetadataSnapshot._NameToRuleAction(const AName: String): TRuleAction;
var
  LOrdinal: Integer;
begin
  LOrdinal := GetEnumValue(TypeInfo(TRuleAction), AName);
  if LOrdinal < 0 then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: TRuleAction desconhecido "%s".', [AName]);
  Result := TRuleAction(LOrdinal);
end;

class function TMetadataSnapshot._SortingOrderToName(AValue: TSortingOrder): String;
begin
  Result := GetEnumName(TypeInfo(TSortingOrder), Ord(AValue));
end;

class function TMetadataSnapshot._NameToSortingOrder(const AName: String): TSortingOrder;
var
  LOrdinal: Integer;
begin
  LOrdinal := GetEnumValue(TypeInfo(TSortingOrder), AName);
  if LOrdinal < 0 then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: TSortingOrder desconhecido "%s".', [AName]);
  Result := TSortingOrder(LOrdinal);
end;

class function TMetadataSnapshot._DriverNameToStr(ADriverName: TDriverName): String;
begin
  Result := TStrDriverName[ADriverName];
end;

class function TMetadataSnapshot._StrToDriverNameChecked(const AValue: String): TDriverName;
var
  LDriver: TDriverName;
begin
  for LDriver := Low(TStrDriverName) to High(TStrDriverName) do
    if SameText(TStrDriverName[LDriver], AValue) then
      Exit(LDriver);
  raise EMetadataSnapshotError.CreateFmt(
    'MetaDbDiff snapshot: DriverName desconhecido "%s".', [AValue]);
end;

{ TMetadataSnapshot }

class function TMetadataSnapshot._PosKey(APosition: Integer): String;
begin
  Result := FormatFloat('000000', APosition);
end;

class function TMetadataSnapshot._JsonArrayOrNil(AJson: TJSONObject; const AKey: String): TJSONArray;
var
  LValue: TJSONValue;
begin
  LValue := AJson.FindValue(AKey);
  if (LValue <> nil) and (LValue is TJSONArray) then
    Result := TJSONArray(LValue)
  else
    Result := nil;
end;

class function TMetadataSnapshot._JsonObjectOrNil(AJson: TJSONObject; const AKey: String): TJSONObject;
var
  LValue: TJSONValue;
begin
  LValue := AJson.FindValue(AKey);
  if (LValue <> nil) and (LValue is TJSONObject) then
    Result := TJSONObject(LValue)
  else
    Result := nil;
end;

class function TMetadataSnapshot._SortedPairs<T>(ADictionary: TObjectDictionary<String, T>): TArray<TPair<String, T>>;
var
  LPair: TPair<String, T>;
  LIndex: Integer;
begin
  // Deterministic (key-sorted) order - mirrors TDatabaseFactory._SortedPairs,
  // so re-saving an unchanged catalog yields byte-identical JSON.
  SetLength(Result, ADictionary.Count);
  LIndex := 0;
  for LPair in ADictionary do
  begin
    Result[LIndex] := LPair;
    Inc(LIndex);
  end;
  TArray.Sort<TPair<String, T>>(Result,
    TComparer<TPair<String, T>>.Construct(
      function (const Left, Right: TPair<String, T>): Integer
      begin
        Result := CompareStr(Left.Key, Right.Key);
      end)
    );
end;

{ --- MIK -> JSON --- }

class function TMetadataSnapshot._ColumnToJson(AColumn: TColumnMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', AColumn.Name);
  Result.AddPair('Description', AColumn.Description);
  Result.AddPair('Position', AColumn.Position);
  Result.AddPair('FieldType', _FieldTypeToName(AColumn.FieldType));
  Result.AddPair('TypeName', AColumn.TypeName);
  Result.AddPair('Size', AColumn.Size);
  Result.AddPair('Precision', AColumn.Precision);
  Result.AddPair('Scale', AColumn.Scale);
  Result.AddPair('NotNull', AColumn.NotNull);
  Result.AddPair('AutoIncrement', AColumn.AutoIncrement);
  Result.AddPair('SortingOrder', _SortingOrderToName(AColumn.SortingOrder));
  Result.AddPair('DefaultValue', AColumn.DefaultValue);
  Result.AddPair('IsPrimaryKey', AColumn.IsPrimaryKey);
  Result.AddPair('CharSet', AColumn.CharSet);
end;

class function TMetadataSnapshot._PrimaryKeyToJson(APrimaryKey: TPrimaryKeyMIK): TJSONObject;
var
  LArr: TJSONArray;
  LPair: TPair<String, TColumnMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', APrimaryKey.Name);
  Result.AddPair('Description', APrimaryKey.Description);
  Result.AddPair('AutoIncrement', APrimaryKey.AutoIncrement);
  LArr := TJSONArray.Create;
  for LPair in APrimaryKey.FieldsSort do
    LArr.Add(_ColumnToJson(LPair.Value));
  Result.AddPair('Fields', LArr);
end;

class function TMetadataSnapshot._ForeignKeyToJson(AForeignKey: TForeignKeyMIK): TJSONObject;
var
  LArr: TJSONArray;
  LPair: TPair<String, TColumnMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', AForeignKey.Name);
  Result.AddPair('Description', AForeignKey.Description);
  Result.AddPair('FromTable', AForeignKey.FromTable);
  Result.AddPair('OnUpdate', _RuleActionToName(AForeignKey.OnUpdate));
  Result.AddPair('OnDelete', _RuleActionToName(AForeignKey.OnDelete));
  LArr := TJSONArray.Create;
  for LPair in AForeignKey.FromFieldsSort do
    LArr.Add(_ColumnToJson(LPair.Value));
  Result.AddPair('FromFields', LArr);
  LArr := TJSONArray.Create;
  for LPair in AForeignKey.ToFieldsSort do
    LArr.Add(_ColumnToJson(LPair.Value));
  Result.AddPair('ToFields', LArr);
end;

class function TMetadataSnapshot._IndexeKeyToJson(AIndexeKey: TIndexeKeyMIK): TJSONObject;
var
  LArr: TJSONArray;
  LPair: TPair<String, TColumnMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', AIndexeKey.Name);
  Result.AddPair('Description', AIndexeKey.Description);
  Result.AddPair('Unique', AIndexeKey.Unique);
  LArr := TJSONArray.Create;
  for LPair in AIndexeKey.FieldsSort do
    LArr.Add(_ColumnToJson(LPair.Value));
  Result.AddPair('Fields', LArr);
end;

class function TMetadataSnapshot._CheckToJson(ACheck: TCheckMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ACheck.Name);
  Result.AddPair('Description', ACheck.Description);
  Result.AddPair('Condition', ACheck.Condition);
end;

class function TMetadataSnapshot._TriggerToJson(ATrigger: TTriggerMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ATrigger.Name);
  Result.AddPair('Description', ATrigger.Description);
  Result.AddPair('Script', ATrigger.Script);
end;

class function TMetadataSnapshot._TableToJson(ATable: TTableMIK): TJSONObject;
var
  LArr: TJSONArray;
  LColPair: TPair<String, TColumnMIK>;
  LIdxPair: TPair<String, TIndexeKeyMIK>;
  LFkPair: TPair<String, TForeignKeyMIK>;
  LChkPair: TPair<String, TCheckMIK>;
  LTrgPair: TPair<String, TTriggerMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ATable.Name);
  Result.AddPair('Description', ATable.Description);
  Result.AddPair('PrimaryKey', _PrimaryKeyToJson(ATable.PrimaryKey));

  LArr := TJSONArray.Create;
  for LColPair in ATable.FieldsSort do
    LArr.Add(_ColumnToJson(LColPair.Value));
  Result.AddPair('Fields', LArr);

  LArr := TJSONArray.Create;
  for LIdxPair in _SortedPairs<TIndexeKeyMIK>(ATable.IndexeKeys) do
    LArr.Add(_IndexeKeyToJson(LIdxPair.Value));
  Result.AddPair('IndexeKeys', LArr);

  LArr := TJSONArray.Create;
  for LFkPair in _SortedPairs<TForeignKeyMIK>(ATable.ForeignKeys) do
    LArr.Add(_ForeignKeyToJson(LFkPair.Value));
  Result.AddPair('ForeignKeys', LArr);

  LArr := TJSONArray.Create;
  for LChkPair in _SortedPairs<TCheckMIK>(ATable.Checks) do
    LArr.Add(_CheckToJson(LChkPair.Value));
  Result.AddPair('Checks', LArr);

  LArr := TJSONArray.Create;
  for LTrgPair in _SortedPairs<TTriggerMIK>(ATable.Triggers) do
    LArr.Add(_TriggerToJson(LTrgPair.Value));
  Result.AddPair('Triggers', LArr);
end;

class function TMetadataSnapshot._ViewToJson(AView: TViewMIK): TJSONObject;
var
  LArr: TJSONArray;
  LPair: TPair<String, TColumnMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', AView.Name);
  Result.AddPair('Description', AView.Description);
  Result.AddPair('Script', AView.Script);
  LArr := TJSONArray.Create;
  for LPair in _SortedPairs<TColumnMIK>(AView.Fields) do
    LArr.Add(_ColumnToJson(LPair.Value));
  Result.AddPair('Fields', LArr);
end;

class function TMetadataSnapshot._SequenceToJson(ASequence: TSequenceMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ASequence.Name);
  Result.AddPair('Description', ASequence.Description);
  Result.AddPair('TableName', ASequence.TableName);
  Result.AddPair('InitialValue', ASequence.InitialValue);
  Result.AddPair('Increment', ASequence.Increment);
end;

class function TMetadataSnapshot._DomainToJson(ADomain: TDomainMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ADomain.Name);
  Result.AddPair('Description', ADomain.Description);
  Result.AddPair('TypeName', ADomain.TypeName);
  Result.AddPair('NotNull', ADomain.NotNull);
  Result.AddPair('DefaultValue', ADomain.DefaultValue);
  Result.AddPair('CheckCondition', ADomain.CheckCondition);
end;

class function TMetadataSnapshot._ProcedureToJson(AProcedure: TProcedureMIK): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', AProcedure.Name);
  Result.AddPair('Description', AProcedure.Description);
  Result.AddPair('Script', AProcedure.Script);
  Result.AddPair('IsFunction', AProcedure.IsFunction);
  Result.AddPair('Signature', AProcedure.Signature);
end;

class function TMetadataSnapshot._CatalogToJson(ACatalog: TCatalogMetadataMIK): TJSONObject;
var
  LArr: TJSONArray;
  LTablePair: TPair<String, TTableMIK>;
  LSeqPair: TPair<String, TSequenceMIK>;
  LViewPair: TPair<String, TViewMIK>;
  LDomPair: TPair<String, TDomainMIK>;
  LProcPair: TPair<String, TProcedureMIK>;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Name', ACatalog.Name);
  Result.AddPair('Schema', ACatalog.Schema);
  Result.AddPair('Description', ACatalog.Description);

  LArr := TJSONArray.Create;
  for LTablePair in ACatalog.TablesSort do
    LArr.Add(_TableToJson(LTablePair.Value));
  Result.AddPair('Tables', LArr);

  LArr := TJSONArray.Create;
  for LSeqPair in _SortedPairs<TSequenceMIK>(ACatalog.Sequences) do
    LArr.Add(_SequenceToJson(LSeqPair.Value));
  Result.AddPair('Sequences', LArr);

  LArr := TJSONArray.Create;
  for LViewPair in _SortedPairs<TViewMIK>(ACatalog.Views) do
    LArr.Add(_ViewToJson(LViewPair.Value));
  Result.AddPair('Views', LArr);

  // FRENTE 15 (v2).
  LArr := TJSONArray.Create;
  for LDomPair in _SortedPairs<TDomainMIK>(ACatalog.Domains) do
    LArr.Add(_DomainToJson(LDomPair.Value));
  Result.AddPair('Domains', LArr);

  LArr := TJSONArray.Create;
  for LProcPair in _SortedPairs<TProcedureMIK>(ACatalog.Procedures) do
    LArr.Add(_ProcedureToJson(LProcPair.Value));
  Result.AddPair('Procedures', LArr);
end;

{ --- JSON -> MIK --- }

class function TMetadataSnapshot._JsonToColumn(AJson: TJSONObject; AOwnerTable: TTableMIK): TColumnMIK;
begin
  Result := TColumnMIK.Create(AOwnerTable);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Position := AJson.GetValue<Integer>('Position', 0);
    Result.FieldType := _NameToFieldType(AJson.GetValue<String>('FieldType'));
    Result.TypeName := AJson.GetValue<String>('TypeName', '');
    Result.Size := AJson.GetValue<Integer>('Size', 0);
    Result.Precision := AJson.GetValue<Integer>('Precision', 0);
    Result.Scale := AJson.GetValue<Integer>('Scale', 0);
    Result.NotNull := AJson.GetValue<Boolean>('NotNull', False);
    Result.AutoIncrement := AJson.GetValue<Boolean>('AutoIncrement', False);
    Result.SortingOrder := _NameToSortingOrder(AJson.GetValue<String>('SortingOrder', 'NoSort'));
    Result.DefaultValue := AJson.GetValue<String>('DefaultValue', '');
    Result.IsPrimaryKey := AJson.GetValue<Boolean>('IsPrimaryKey', False);
    Result.CharSet := AJson.GetValue<String>('CharSet', '');
  except
    Result.Free;
    raise;
  end;
end;

class procedure TMetadataSnapshot._JsonToPrimaryKey(AJson: TJSONObject; ATable: TTableMIK);
var
  LPkJson: TJSONObject;
  LArr: TJSONArray;
  LFor: Integer;
  LColumn: TColumnMIK;
begin
  // ATable.PrimaryKey already exists (auto-created by TTableMIK.Create) -
  // populate it in place instead of replacing the reference.
  LPkJson := _JsonObjectOrNil(AJson, 'PrimaryKey');
  if LPkJson = nil then
    Exit;
  ATable.PrimaryKey.Name := LPkJson.GetValue<String>('Name', '');
  ATable.PrimaryKey.Description := LPkJson.GetValue<String>('Description', '');
  ATable.PrimaryKey.AutoIncrement := LPkJson.GetValue<Boolean>('AutoIncrement', False);
  LArr := _JsonArrayOrNil(LPkJson, 'Fields');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), ATable);
      ATable.PrimaryKey.Fields.AddOrSetValue(_PosKey(LColumn.Position), LColumn);
    end;
end;

class function TMetadataSnapshot._JsonToForeignKey(AJson: TJSONObject; ATable: TTableMIK): TForeignKeyMIK;
var
  LArr: TJSONArray;
  LFor: Integer;
  LColumn: TColumnMIK;
begin
  Result := TForeignKeyMIK.Create(ATable);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.FromTable := AJson.GetValue<String>('FromTable', '');
    Result.OnUpdate := _NameToRuleAction(AJson.GetValue<String>('OnUpdate', 'None'));
    Result.OnDelete := _NameToRuleAction(AJson.GetValue<String>('OnDelete', 'None'));

    LArr := _JsonArrayOrNil(AJson, 'FromFields');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), ATable);
        Result.FromFields.AddOrSetValue(_PosKey(LColumn.Position), LColumn);
      end;

    LArr := _JsonArrayOrNil(AJson, 'ToFields');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), ATable);
        Result.ToFields.AddOrSetValue(_PosKey(LColumn.Position), LColumn);
      end;
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToIndexeKey(AJson: TJSONObject; ATable: TTableMIK): TIndexeKeyMIK;
var
  LArr: TJSONArray;
  LFor: Integer;
  LColumn: TColumnMIK;
begin
  Result := TIndexeKeyMIK.Create(ATable);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Unique := AJson.GetValue<Boolean>('Unique', False);
    LArr := _JsonArrayOrNil(AJson, 'Fields');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), ATable);
        Result.Fields.AddOrSetValue(_PosKey(LColumn.Position), LColumn);
      end;
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToCheck(AJson: TJSONObject; ATable: TTableMIK): TCheckMIK;
begin
  Result := TCheckMIK.Create(ATable);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Condition := AJson.GetValue<String>('Condition', '');
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToTrigger(AJson: TJSONObject; ATable: TTableMIK): TTriggerMIK;
begin
  Result := TTriggerMIK.Create(ATable);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Script := AJson.GetValue<String>('Script', '');
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToTable(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TTableMIK;
var
  LArr: TJSONArray;
  LFor: Integer;
  LColumn: TColumnMIK;
  LIndexeKey: TIndexeKeyMIK;
  LForeignKey: TForeignKeyMIK;
  LCheck: TCheckMIK;
  LTrigger: TTriggerMIK;
begin
  Result := TTableMIK.Create(ACatalog);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');

    _JsonToPrimaryKey(AJson, Result);

    LArr := _JsonArrayOrNil(AJson, 'Fields');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), Result);
        Result.Fields.AddOrSetValue(_PosKey(LColumn.Position), LColumn);
      end;

    LArr := _JsonArrayOrNil(AJson, 'IndexeKeys');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LIndexeKey := _JsonToIndexeKey(TJSONObject(LArr.Items[LFor]), Result);
        Result.IndexeKeys.AddOrSetValue(UpperCase(LIndexeKey.Name), LIndexeKey);
      end;

    LArr := _JsonArrayOrNil(AJson, 'ForeignKeys');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LForeignKey := _JsonToForeignKey(TJSONObject(LArr.Items[LFor]), Result);
        Result.ForeignKeys.AddOrSetValue(UpperCase(LForeignKey.Name), LForeignKey);
      end;

    LArr := _JsonArrayOrNil(AJson, 'Checks');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LCheck := _JsonToCheck(TJSONObject(LArr.Items[LFor]), Result);
        Result.Checks.AddOrSetValue(UpperCase(LCheck.Name), LCheck);
      end;

    LArr := _JsonArrayOrNil(AJson, 'Triggers');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        LTrigger := _JsonToTrigger(TJSONObject(LArr.Items[LFor]), Result);
        Result.Triggers.AddOrSetValue(UpperCase(LTrigger.Name), LTrigger);
      end;
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToView(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TViewMIK;
var
  LArr: TJSONArray;
  LFor: Integer;
  LColumn: TColumnMIK;
begin
  Result := TViewMIK.Create(ACatalog);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Script := AJson.GetValue<String>('Script', '');
    LArr := _JsonArrayOrNil(AJson, 'Fields');
    if LArr <> nil then
      for LFor := 0 to LArr.Count - 1 do
      begin
        // View columns carry no owning table, matching the live extractors
        // (MetaDbDiff.Metadata.Firebird.pas: TColumnMIK.Create with no arg).
        LColumn := _JsonToColumn(TJSONObject(LArr.Items[LFor]), nil);
        Result.Fields.AddOrSetValue(UpperCase(LColumn.Name), LColumn);
      end;
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToSequence(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TSequenceMIK;
begin
  Result := TSequenceMIK.Create(ACatalog);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.TableName := AJson.GetValue<String>('TableName', '');
    Result.InitialValue := AJson.GetValue<Integer>('InitialValue', 0);
    Result.Increment := AJson.GetValue<Integer>('Increment', 0);
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToDomain(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TDomainMIK;
begin
  Result := TDomainMIK.Create(ACatalog);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.TypeName := AJson.GetValue<String>('TypeName', '');
    Result.NotNull := AJson.GetValue<Boolean>('NotNull', False);
    Result.DefaultValue := AJson.GetValue<String>('DefaultValue', '');
    Result.CheckCondition := AJson.GetValue<String>('CheckCondition', '');
  except
    Result.Free;
    raise;
  end;
end;

class function TMetadataSnapshot._JsonToProcedure(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK): TProcedureMIK;
begin
  Result := TProcedureMIK.Create(ACatalog);
  try
    Result.Name := AJson.GetValue<String>('Name');
    Result.Description := AJson.GetValue<String>('Description', '');
    Result.Script := AJson.GetValue<String>('Script', '');
    Result.IsFunction := AJson.GetValue<Boolean>('IsFunction', False);
    // Signature ausente num snapshot v2 antigo (ou de dialeto sem overload) -> ''.
    Result.Signature := AJson.GetValue<String>('Signature', '');
  except
    Result.Free;
    raise;
  end;
end;

class procedure TMetadataSnapshot._JsonToCatalog(AJson: TJSONObject; ACatalog: TCatalogMetadataMIK);
var
  LArr: TJSONArray;
  LFor: Integer;
  LTable: TTableMIK;
  LSequence: TSequenceMIK;
  LView: TViewMIK;
  LDomain: TDomainMIK;
  LProcedure: TProcedureMIK;
begin
  ACatalog.Tables.Clear;
  ACatalog.Sequences.Clear;
  ACatalog.Views.Clear;
  // FRENTE 15: limpa tambem as colecoes v2 (armadilha das Views).
  ACatalog.Domains.Clear;
  ACatalog.Procedures.Clear;
  ACatalog.Name := AJson.GetValue<String>('Name', '');
  ACatalog.Schema := AJson.GetValue<String>('Schema', '');
  ACatalog.Description := AJson.GetValue<String>('Description', '');

  LArr := _JsonArrayOrNil(AJson, 'Tables');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LTable := _JsonToTable(TJSONObject(LArr.Items[LFor]), ACatalog);
      ACatalog.Tables.AddOrSetValue(UpperCase(LTable.Name), LTable);
    end;

  LArr := _JsonArrayOrNil(AJson, 'Sequences');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LSequence := _JsonToSequence(TJSONObject(LArr.Items[LFor]), ACatalog);
      ACatalog.Sequences.AddOrSetValue(UpperCase(LSequence.Name), LSequence);
    end;

  LArr := _JsonArrayOrNil(AJson, 'Views');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LView := _JsonToView(TJSONObject(LArr.Items[LFor]), ACatalog);
      ACatalog.Views.AddOrSetValue(UpperCase(LView.Name), LView);
    end;

  // FRENTE 15 (v2): ausentes num snapshot v1 -> _JsonArrayOrNil devolve nil e as
  // colecoes ficam vazias (retrocompatibilidade transparente).
  LArr := _JsonArrayOrNil(AJson, 'Domains');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LDomain := _JsonToDomain(TJSONObject(LArr.Items[LFor]), ACatalog);
      ACatalog.Domains.AddOrSetValue(UpperCase(LDomain.Name), LDomain);
    end;

  LArr := _JsonArrayOrNil(AJson, 'Procedures');
  if LArr <> nil then
    for LFor := 0 to LArr.Count - 1 do
    begin
      LProcedure := _JsonToProcedure(TJSONObject(LArr.Items[LFor]), ACatalog);
      // CatalogKey (nome + assinatura) reproduz EXATAMENTE a convencao do extractor
      // - sem isto, overloads PostgreSQL colapsariam ao recarregar o snapshot.
      ACatalog.Procedures.AddOrSetValue(LProcedure.CatalogKey, LProcedure);
    end;
end;

{ --- Public API --- }

class function TMetadataSnapshot.ToJson(ACatalog: TCatalogMetadataMIK; ADriverName: TDriverName;
  const ADescription: String): TJSONObject;
begin
  if ACatalog = nil then
    raise Exception.Create('TMetadataSnapshot.ToJson: ACatalog nao pode ser nil.');
  Result := TJSONObject.Create;
  try
    Result.AddPair('FormatVersion', MetadataSnapshotFormatVersion);
    Result.AddPair('DriverName', _DriverNameToStr(ADriverName));
    Result.AddPair('GeneratedAt', DateToISO8601(Now, False));
    Result.AddPair('SourceDescription', ADescription);
    Result.AddPair('Catalog', _CatalogToJson(ACatalog));
  except
    Result.Free;
    raise;
  end;
end;

class procedure TMetadataSnapshot.LoadInto(AJson: TJSONObject; ACatalogMetadata: TCatalogMetadataMIK;
  out ADriverName: TDriverName; out ADescription, AGeneratedAt: String; out AFormatVersion: Integer);
var
  LCatalogJson: TJSONObject;
begin
  if AJson = nil then
    raise EMetadataSnapshotError.Create('MetaDbDiff snapshot: envelope JSON nao pode ser nil.');
  if ACatalogMetadata = nil then
    raise Exception.Create('TMetadataSnapshot.LoadInto: ACatalogMetadata nao pode ser nil.');

  try
    AFormatVersion := AJson.GetValue<Integer>('FormatVersion');
  except
    on E: Exception do
      raise EMetadataSnapshotError.CreateFmt(
        'MetaDbDiff snapshot: campo "FormatVersion" ausente ou invalido (%s).', [E.Message]);
  end;

  if AFormatVersion > MetadataSnapshotFormatVersion then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: FormatVersion %d e mais novo que o suportado por ' +
      'esta versao do MetaDbDiff (maximo suportado: %d). Atualize o MetaDbDiff ' +
      'para conseguir carregar este snapshot.', [AFormatVersion, MetadataSnapshotFormatVersion]);

  // Guards against a tampered/hand-edited file (this is external, untrusted
  // input - see the unit header): FormatVersion 0 or negative is not "an old
  // version we happen to support", it is not a version this library ever
  // wrote. Silently treating it as v1 would let a corrupted or malicious
  // envelope slide through undetected.
  if AFormatVersion < 1 then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: invalid snapshot FormatVersion %d (must be >= 1).',
      [AFormatVersion]);

  try
    ADriverName := _StrToDriverNameChecked(AJson.GetValue<String>('DriverName'));
    ADescription := AJson.GetValue<String>('SourceDescription', '');
    AGeneratedAt := AJson.GetValue<String>('GeneratedAt', '');
    LCatalogJson := _JsonObjectOrNil(AJson, 'Catalog');
    if LCatalogJson = nil then
      raise EMetadataSnapshotError.Create('MetaDbDiff snapshot: campo "Catalog" ausente.');
    _JsonToCatalog(LCatalogJson, ACatalogMetadata);
  except
    on E: EMetadataSnapshotError do
      raise;
    on E: Exception do
      raise EMetadataSnapshotError.CreateFmt(
        'MetaDbDiff snapshot: arquivo corrompido ou com estrutura invalida (%s).', [E.Message]);
  end;
end;

class function TMetadataSnapshot.FromJson(AJson: TJSONObject): TCatalogMetadataMIK;
var
  LDriverName: TDriverName;
  LDescription, LGeneratedAt: String;
  LFormatVersion: Integer;
begin
  Result := TCatalogMetadataMIK.Create;
  try
    LoadInto(AJson, Result, LDriverName, LDescription, LGeneratedAt, LFormatVersion);
  except
    Result.Free;
    raise;
  end;
end;

class procedure TMetadataSnapshot.SaveToStream(ACatalog: TCatalogMetadataMIK; AStream: TStream;
  ADriverName: TDriverName; const ADescription: String);
var
  LJson: TJSONObject;
  LBytes: TBytes;
begin
  LJson := ToJson(ACatalog, ADriverName, ADescription);
  try
    LBytes := TEncoding.UTF8.GetBytes(LJson.Format(2));
    if Length(LBytes) > 0 then
      AStream.WriteBuffer(LBytes[0], Length(LBytes));
  finally
    LJson.Free;
  end;
end;

class function TMetadataSnapshot.LoadFromStream(AStream: TStream): TCatalogMetadataMIK;
var
  LDriverName: TDriverName;
  LDescription, LGeneratedAt: String;
  LFormatVersion: Integer;
begin
  Result := LoadFromStream(AStream, LDriverName, LDescription, LGeneratedAt, LFormatVersion);
end;

class function TMetadataSnapshot.LoadFromStream(AStream: TStream; out ADriverName: TDriverName;
  out ADescription, AGeneratedAt: String; out AFormatVersion: Integer): TCatalogMetadataMIK;
var
  LBytes: TBytes;
  LText: String;
  LJsonValue: TJSONValue;
  LJson: TJSONObject;
begin
  SetLength(LBytes, AStream.Size - AStream.Position);
  if Length(LBytes) > 0 then
    AStream.ReadBuffer(LBytes[0], Length(LBytes));
  LText := TEncoding.UTF8.GetString(LBytes);

  LJsonValue := nil;
  try
    LJsonValue := TJSONObject.ParseJSONValue(LText, False, True);
  except
    on E: Exception do
      raise EMetadataSnapshotError.CreateFmt('MetaDbDiff snapshot: JSON invalido (%s).', [E.Message]);
  end;

  if LJsonValue = nil then
    raise EMetadataSnapshotError.Create('MetaDbDiff snapshot: JSON invalido ou vazio.');
  if not (LJsonValue is TJSONObject) then
  begin
    LJsonValue.Free;
    raise EMetadataSnapshotError.Create('MetaDbDiff snapshot: a raiz do JSON deveria ser um objeto.');
  end;

  LJson := TJSONObject(LJsonValue);
  try
    Result := TCatalogMetadataMIK.Create;
    try
      LoadInto(LJson, Result, ADriverName, ADescription, AGeneratedAt, AFormatVersion);
    except
      Result.Free;
      raise;
    end;
  finally
    LJson.Free;
  end;
end;

class procedure TMetadataSnapshot.SaveToFile(ACatalog: TCatalogMetadataMIK; const AFileName: String;
  ADriverName: TDriverName; const ADescription: String);
var
  LStream: TFileStream;
begin
  LStream := TFileStream.Create(AFileName, fmCreate);
  try
    SaveToStream(ACatalog, LStream, ADriverName, ADescription);
  finally
    LStream.Free;
  end;
end;

class function TMetadataSnapshot.LoadFromFile(const AFileName: String): TCatalogMetadataMIK;
var
  LDriverName: TDriverName;
  LDescription, LGeneratedAt: String;
  LFormatVersion: Integer;
begin
  Result := LoadFromFile(AFileName, LDriverName, LDescription, LGeneratedAt, LFormatVersion);
end;

class function TMetadataSnapshot.LoadFromFile(const AFileName: String; out ADriverName: TDriverName;
  out ADescription, AGeneratedAt: String; out AFormatVersion: Integer): TCatalogMetadataMIK;
var
  LStream: TFileStream;
begin
  if not FileExists(AFileName) then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: arquivo nao encontrado: "%s".', [AFileName]);
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := LoadFromStream(LStream, ADriverName, ADescription, AGeneratedAt, AFormatVersion);
  finally
    LStream.Free;
  end;
end;

end.
