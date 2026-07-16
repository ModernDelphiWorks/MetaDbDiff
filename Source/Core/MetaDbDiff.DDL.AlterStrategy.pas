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

{ @abstract(MetaDbDiff - Safe / configurable ALTER COLUMN strategy.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)

  Post-generation transformation of the DDL command list - SAME architectural
  pattern as the TDDLSequencer: it never touches the Source\ generators; it only
  rewrites the flat command list AFTER GenerateDDLCommands has produced it.

  Problem it solves
  -----------------
  Today the diff emits a single in-place ALTER COLUMN whenever a column's
  type/size/not-null diverges. That is destructive or plainly invalid in several
  cases: narrowing a populated column, type conversions the dialect cannot do
  in-place (Firebird 2.5 has hard restrictions on ALTER ... TYPE), or adding
  NOT NULL to a populated table without a default.

  Strategy (opt-in, default preserves history)
  ---------------------------------------------
    acsInPlace            - historical behavior: keep the single ALTER COLUMN.
    acsRebuildWhenRequired- when an alteration is UNSAFE for the dialect, replace
                            the ALTER COLUMN by a data-preserving SEQUENCE.

  Sequence emitted for an unsafe TYPE change (all in the COLUMNS phase, in order):
    (a) CREATE temp column  <name>_MDBTMP  ALWAYS NULLABLE (a NOT NULL ADD would
        fail on a populated table before the copy even runs)
        (reuses TDDLCommandCreateColumn via the marker subclass
         TDDLCommandCreateColumnRebuild so the sequencer/policy can tell it apart)
    (b) COPY  UPDATE <table> SET <tmp> = CAST(<orig> AS <newtype>)  (per-dialect)
    (c) DROP  the original column
        (reuses TDDLCommandDropColumn via TDDLCommandDropColumnRebuild so it stays
         in the COLUMNS phase instead of migrating to the earlier Drop Columns phase)
    (d) RENAME  <tmp> back to <orig>  (per-dialect)
    (e) [only when the target column is NOT NULL] re-assert NOT NULL as the FINAL
        step (the tmp was nullable): backfill NULLs with the DefaultValue first when
        one exists, then reuse the original in-place ALTER to apply SET NOT NULL.
        Without a default the SET NOT NULL is still emitted but its Warning carries
        an aggregated RISK note (it fails if the column has NULL rows) - never silent.

  Adding NOT NULL to a populated column:
    * WITH a default -> backfill (UPDATE <col> = <default> WHERE <col> IS NULL)
                        FOLLOWED BY the original ALTER (which carries SET NOT NULL).
    * WITHOUT a default -> we CANNOT make it safe automatically: keep the in-place
                        ALTER and append a RISK note to its Warning (never silent).

  SQLite / AbsoluteDB (documented limitation - candidate for a future front)
  -------------------------------------------------------------------------
  SQLite pre-3.35 cannot DROP COLUMN and cannot ALTER a column's type; a real fix
  requires rebuilding the WHOLE table (create new table, copy, drop, rename),
  which is out of scope here. For these dialects _RequiresRebuild returns FALSE
  and the historical in-place ALTER is preserved unchanged.

  Ownership of cloned metadata
  ----------------------------
  The rebuilder allocates the <name>_MDBTMP TColumnMIK clones into an OWNING list
  (FOwnedColumns). The command instances only REFERENCE those clones. Because the
  clones must outlive the transient rebuilder (the command list is read/executed
  later), ownership is EXPLICITLY transferred to the caller via ExtractOwnedColumns
  (which releases this list's ownership). If the caller never extracts (e.g. an
  exception), the destructor frees them - so there is never a leak nor a double free.
}

unit MetaDbDiff.DDL.AlterStrategy;

interface

uses
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.Compare.Options;

const
  /// <summary> Suffix of the temporary column created during a rebuild. </summary>
  CRebuildTempSuffix = '_MDBTMP';

type
  /// <summary>
  ///   Configurable ALTER COLUMN strategy. Default (acsInPlace) reproduces the
  ///   historical behavior; acsRebuildWhenRequired turns on the safe rebuild.
  /// </summary>
  TAlterColumnStrategy = (acsInPlace, acsRebuildWhenRequired);

  /// <summary>Decision taken for one diverging column (internal).</summary>
  TAlterColumnAction = (
    acaInPlace,            // safe: keep the historical single ALTER COLUMN
    acaTypeRebuild,        // unsafe type change: add/copy/drop/rename sequence
    acaBackfillNotNull,    // add NOT NULL with default: backfill then ALTER
    acaInPlaceWithWarning);// add NOT NULL without default: keep ALTER + risk note

  /// <summary>
  ///   Rewrites a flat TDDLCommand list, replacing unsafe in-place ALTER COLUMN
  ///   commands by data-preserving sequences. Transient (one pass, like the
  ///   sequencer); keeps only references to the supplied catalogs/generator.
  /// </summary>
  TAlterColumnRebuilder = class
  strict private
    FDriver: TDriverName;
    FStrategy: TAlterColumnStrategy;
    FMaster: TCatalogMetadataMIK;
    FTarget: TCatalogMetadataMIK;
    FPolicy: TComparePolicy;
    FGenerator: IDDLGeneratorCommand;
    FOwnedColumns: TObjectList<TColumnMIK>;   // owns the _MDBTMP clones (until transferred)
    FReplaced: TObjectList<TDDLCommand>;      // ALTERs removed by a rebuild (caller frees)
    FSuppressed: TList<String>;               // audit notes for the caller to merge
    /// <summary>Deep clone of a column into the owned list, with a new name.</summary>
    function _CloneColumn(ASource: TColumnMIK; const ANewName: String): TColumnMIK;
    /// <summary>Case-insensitive lookup of the diverging column on the TARGET side.</summary>
    function _FindTargetColumn(AMaster: TColumnMIK): TColumnMIK;
    /// <summary>Decides what to do with one diverging column.</summary>
    function _ClassifyAction(AMaster, ATarget: TColumnMIK): TAlterColumnAction;
    /// <summary>Builds the SQL of a freshly created command (F1 contract).</summary>
    function _Built(ACommand: TDDLCommand): TDDLCommand;
    /// <summary>Appends the add/copy/drop/rename sequence for AMaster to AList.</summary>
    procedure _EmitTypeRebuild(AList: TList<TDDLCommand>; AMaster: TColumnMIK);
    /// <summary>Appends the backfill UPDATE for AMaster to AList.</summary>
    procedure _EmitBackfill(AList: TList<TDDLCommand>; AMaster: TColumnMIK);
  public
    constructor Create(ADriver: TDriverName; AStrategy: TAlterColumnStrategy;
      AMaster, ATarget: TCatalogMetadataMIK; const APolicy: TComparePolicy;
      const AGenerator: IDDLGeneratorCommand);
    destructor Destroy; override;
    /// <summary>
    ///   TRUE when an in-place type change is unsafe/impossible for the dialect:
    ///   incompatible category change, narrowing (size/precision shrink), or -
    ///   on Firebird 2.5 / Interbase - ANY type change except a VARCHAR/CHAR
    ///   WIDENING. SQLite / AbsoluteDB always return FALSE (documented limitation).
    ///   NOT NULL handling is decided separately (see _ClassifyAction).
    /// </summary>
    class function _RequiresRebuild(ADriver: TDriverName;
      AMaster, ATarget: TColumnMIK): Boolean; static;
    /// <summary>
    ///   Returns the rewritten command list. No-op copy when strategy = acsInPlace.
    ///   New commands already carry their built SQL. ALTERs replaced by a rebuild
    ///   are moved to Replaced (the caller frees them after swapping the list).
    /// </summary>
    function Rebuild(const ACommands: TArray<TDDLCommand>): TArray<TDDLCommand>;
    /// <summary>
    ///   Releases ownership of the _MDBTMP clones to the caller (which becomes the
    ///   sole owner for the clones' whole lifetime). Call AFTER Rebuild.
    /// </summary>
    function ExtractOwnedColumns: TArray<TColumnMIK>;
    /// <summary>Audit notes produced during the pass (e.g. rebuild suppressed by policy).</summary>
    function SuppressedNotes: TArray<String>;
    /// <summary>ALTER COLUMN commands removed by a rebuild - the caller must free them.</summary>
    function ReplacedCommands: TArray<TDDLCommand>;
  end;

implementation

{ ---------------------------------------------------------------------------- }
{ Local type helpers                                                            }
{ ---------------------------------------------------------------------------- }

type
  TTypeCategory = (tcChar, tcInteger, tcNumeric, tcDateTime, tcBlob, tcOther);

/// <summary>Base type name: UPPER-CASE, stripped of size/precision and charset.</summary>
function BaseTypeName(const ATypeName: String): String;
var
  LCut: Integer;
  LFor: Integer;
begin
  Result := UpperCase(Trim(ATypeName));
  LCut := Length(Result);
  for LFor := 1 to Length(Result) do
    if CharInSet(Result[LFor], ['(', ' ', '[']) then
    begin
      LCut := LFor - 1;
      Break;
    end;
  Result := Copy(Result, 1, LCut);
end;

function IsCharTypeName(const ABaseName: String): Boolean;
begin
  Result := (Pos('CHAR', ABaseName) > 0) or   // CHAR/VARCHAR/NVARCHAR/VARCHAR2/NCHAR
            (ABaseName = 'TEXT') or
            (ABaseName = 'STRING') or
            (ABaseName = 'CLOB') or
            (ABaseName = 'MEMO');
end;

function TypeCategory(const ABaseName: String): TTypeCategory;
begin
  if IsCharTypeName(ABaseName) then
    Exit(tcChar);
  if (ABaseName = 'INTEGER') or (ABaseName = 'INT') or (ABaseName = 'SMALLINT') or
     (ABaseName = 'BIGINT') or (ABaseName = 'TINYINT') or (ABaseName = 'INT64') or
     (ABaseName = 'SERIAL') or (ABaseName = 'BIGSERIAL') then
    Exit(tcInteger);
  if (ABaseName = 'NUMERIC') or (ABaseName = 'DECIMAL') or (ABaseName = 'NUMBER') or
     (ABaseName = 'FLOAT') or (ABaseName = 'DOUBLE') or (ABaseName = 'REAL') or
     (ABaseName = 'MONEY') or (ABaseName = 'CURRENCY') or (ABaseName = 'DEC') then
    Exit(tcNumeric);
  if (ABaseName = 'DATE') or (ABaseName = 'TIME') or (ABaseName = 'TIMESTAMP') or
     (ABaseName = 'DATETIME') or (ABaseName = 'DATETIME2') or (ABaseName = 'SMALLDATETIME') then
    Exit(tcDateTime);
  if (ABaseName = 'BLOB') or (ABaseName = 'BYTEA') or (ABaseName = 'IMAGE') or
     (ABaseName = 'VARBINARY') or (ABaseName = 'BINARY') or (ABaseName = 'BYTES') then
    Exit(tcBlob);
  Result := tcOther;
end;

{ ---------------------------------------------------------------------------- }
{ TAlterColumnRebuilder                                                         }
{ ---------------------------------------------------------------------------- }

constructor TAlterColumnRebuilder.Create(ADriver: TDriverName;
  AStrategy: TAlterColumnStrategy; AMaster, ATarget: TCatalogMetadataMIK;
  const APolicy: TComparePolicy; const AGenerator: IDDLGeneratorCommand);
begin
  inherited Create;
  FDriver := ADriver;
  FStrategy := AStrategy;
  FMaster := AMaster;
  FTarget := ATarget;
  FPolicy := APolicy;
  FGenerator := AGenerator;
  FOwnedColumns := TObjectList<TColumnMIK>.Create(True);
  FReplaced := TObjectList<TDDLCommand>.Create(False); // references only; caller frees
  FSuppressed := TList<String>.Create;
end;

destructor TAlterColumnRebuilder.Destroy;
begin
  // FOwnedColumns still owns any clone NOT transferred by ExtractOwnedColumns.
  FSuppressed.Free;
  FReplaced.Free;
  FOwnedColumns.Free;
  inherited;
end;

class function TAlterColumnRebuilder._RequiresRebuild(ADriver: TDriverName;
  AMaster, ATarget: TColumnMIK): Boolean;
var
  LMasterBase, LTargetBase: String;
  LSameType: Boolean;
begin
  // SQLite family: a column rebuild is not enough (needs a full TABLE rebuild),
  // which is out of scope here. Keep the historical in-place ALTER.
  if ADriver in [dnSQLite, dnAbsoluteDB] then
    Exit(False);

  LMasterBase := BaseTypeName(AMaster.TypeName);
  LTargetBase := BaseTypeName(ATarget.TypeName);
  LSameType := SameText(LMasterBase, LTargetBase) and
               (AMaster.Size = ATarget.Size) and
               (AMaster.Precision = ATarget.Precision) and
               (AMaster.Scale = ATarget.Scale);

  // Firebird 2.5 / Interbase: ALTER ... TYPE is heavily restricted. The ONLY
  // safe in-place change is WIDENING a CHAR/VARCHAR (same base type, larger size).
  // Everything else (narrowing, any cross-type change, numeric changes) needs a
  // rebuild. (Firebird 3+ is more permissive but is a separate driver/dialect;
  // this conservative rule stays correct for it too - a rebuild is always valid.)
  if ADriver in [dnFirebird, dnInterbase, dnFirebird3] then
  begin
    if SameText(LMasterBase, LTargetBase) and IsCharTypeName(LMasterBase) then
      Exit(AMaster.Size < ATarget.Size)   // narrowing a CHAR/VARCHAR -> rebuild
    else
      Exit(not LSameType);                 // any real type change -> rebuild
  end;

  // Other dialects (PostgreSQL, MSSQL, MySQL, Oracle, ...): rebuild on an
  // incompatible category change OR a narrowing within the same category.
  if TypeCategory(LMasterBase) <> TypeCategory(LTargetBase) then
    Exit(True);                            // incompatible category -> rebuild
  // Narrowing a character column.
  if IsCharTypeName(LMasterBase) and (AMaster.Size < ATarget.Size) then
    Exit(True);
  // Narrowing numeric precision.
  if (AMaster.Precision > 0) and (ATarget.Precision > 0) and
     (AMaster.Precision < ATarget.Precision) then
    Exit(True);
  // Same/compatible/widening type: safe in-place.
  Result := False;
end;

function TAlterColumnRebuilder._FindTargetColumn(AMaster: TColumnMIK): TColumnMIK;
var
  LTable: TTableMIK;
  LTablePair: TPair<String, TTableMIK>;
  LColumn: TColumnMIK;
begin
  Result := nil;
  if (FTarget = nil) or (AMaster.Table = nil) then
    Exit;
  LTable := nil;
  for LTablePair in FTarget.Tables do
    if SameText(LTablePair.Value.Name, AMaster.Table.Name) then
    begin
      LTable := LTablePair.Value;
      Break;
    end;
  if LTable = nil then
    Exit;
  for LColumn in LTable.Fields.Values do
    if SameText(LColumn.Name, AMaster.Name) then
      Exit(LColumn);
end;

function TAlterColumnRebuilder._ClassifyAction(AMaster,
  ATarget: TColumnMIK): TAlterColumnAction;
begin
  // Unsafe type change wins: the rebuild recreates the column with the new type
  // and preserves the data via CAST.
  if _RequiresRebuild(FDriver, AMaster, ATarget) then
    Exit(acaTypeRebuild);
  // Adding NOT NULL to an existing (assumed populated) column.
  if AMaster.NotNull and (not ATarget.NotNull) then
  begin
    if Trim(AMaster.DefaultValue) <> '' then
      Exit(acaBackfillNotNull)          // backfill NULLs with the default, then SET NOT NULL
    else
      Exit(acaInPlaceWithWarning);      // no default: cannot be made safe automatically
  end;
  Result := acaInPlace;
end;

function TAlterColumnRebuilder._CloneColumn(ASource: TColumnMIK;
  const ANewName: String): TColumnMIK;
begin
  // The clone REFERENCES the same table as the source (it never owns it). It is
  // added to the owning list so its lifetime is managed explicitly.
  Result := TColumnMIK.Create(ASource.Table);
  Result.Name := ANewName;
  Result.Position := ASource.Position;
  Result.FieldType := ASource.FieldType;
  Result.TypeName := ASource.TypeName;
  Result.Size := ASource.Size;
  Result.Precision := ASource.Precision;
  Result.Scale := ASource.Scale;
  // A coluna temporaria e SEMPRE criada NULLABLE: um ADD COLUMN NOT NULL falharia
  // em tabela populada (FB/PG/MSSQL/Oracle) ANTES mesmo do CAST, e o CAST de uma
  // origem com NULLs violaria o NOT NULL. O NOT NULL, quando desejado, e reafirmado
  // como PASSO FINAL da sequencia (apos rename), precedido de backfill quando ha
  // DefaultValue - ver _EmitTypeRebuild / Rebuild.
  Result.NotNull := False;
  Result.AutoIncrement := ASource.AutoIncrement;
  Result.SortingOrder := ASource.SortingOrder;
  Result.DefaultValue := ASource.DefaultValue;
  Result.IsPrimaryKey := ASource.IsPrimaryKey;
  Result.CharSet := ASource.CharSet;
  Result.Description := ASource.Description;
  FOwnedColumns.Add(Result);
end;

function TAlterColumnRebuilder._Built(ACommand: TDDLCommand): TDDLCommand;
begin
  ACommand.BuildCommand(FGenerator);   // F1 contract: SQL is built at generation time
  Result := ACommand;
end;

procedure TAlterColumnRebuilder._EmitTypeRebuild(AList: TList<TDDLCommand>;
  AMaster: TColumnMIK);
var
  LTemp: TColumnMIK;
  LTempName: String;
begin
  LTempName := AMaster.Name + CRebuildTempSuffix;
  LTemp := _CloneColumn(AMaster, LTempName);
  // (a) CREATE the temp column with the NEW type.
  AList.Add(_Built(TDDLCommandCreateColumnRebuild.Create(LTemp)));
  // (b) COPY data across, casting from the original column to the new type.
  AList.Add(_Built(TDDLCommandCopyColumnData.Create(LTemp, AMaster.Name, False)));
  // (c) DROP the original column (stays in the COLUMNS phase via the subclass).
  AList.Add(_Built(TDDLCommandDropColumnRebuild.Create(AMaster)));
  // (d) RENAME the temp column back to the original name.
  AList.Add(_Built(TDDLCommandRenameColumn.Create(LTemp, AMaster.Name)));
end;

procedure TAlterColumnRebuilder._EmitBackfill(AList: TList<TDDLCommand>;
  AMaster: TColumnMIK);
begin
  // UPDATE <table> SET <col> = <default> WHERE <col> IS NULL (backfill existing
  // rows before the ALTER that applies SET NOT NULL).
  AList.Add(_Built(TDDLCommandCopyColumnData.Create(AMaster, '', True)));
end;

function TAlterColumnRebuilder.Rebuild(
  const ACommands: TArray<TDDLCommand>): TArray<TDDLCommand>;
var
  LOut: TList<TDDLCommand>;
  LCommand: TDDLCommand;
  LAlter: TDDLCommandAlterColumn;
  LMaster, LTarget: TColumnMIK;
  LAction: TAlterColumnAction;
  LRebuildAllowed: Boolean;
begin
  // Fast path: acsInPlace keeps the list byte-for-byte identical (no transform).
  if FStrategy = acsInPlace then
    Exit(Copy(ACommands, 0, Length(ACommands)));

  LRebuildAllowed := FPolicy.Allows(TDDLOperation.RebuildColumn);
  LOut := TList<TDDLCommand>.Create;
  try
    for LCommand in ACommands do
    begin
      if not (LCommand is TDDLCommandAlterColumn) then
      begin
        LOut.Add(LCommand);
        Continue;
      end;
      LAlter := TDDLCommandAlterColumn(LCommand);
      LMaster := LAlter.Column;
      LTarget := _FindTargetColumn(LMaster);
      // Cannot resolve the target column (DB-vs-model gaps, injected commands):
      // never guess - keep the historical in-place ALTER.
      if (LMaster = nil) or (LTarget = nil) then
      begin
        LOut.Add(LCommand);
        Continue;
      end;

      LAction := _ClassifyAction(LMaster, LTarget);

      // Fail-closed friendliness: a rebuild introduces RebuildColumn-op commands.
      // If the policy forbids that operation, do NOT produce an un-executable plan;
      // keep the in-place ALTER and record the reason in the audit.
      if (LAction in [acaTypeRebuild, acaBackfillNotNull]) and (not LRebuildAllowed) then
      begin
        FSuppressed.Add(Format(
          'REBUILD COLUMN %s.%s suppressed by policy (kept in-place ALTER)',
          [LMaster.Table.Name, LMaster.Name]));
        LOut.Add(LCommand);
        Continue;
      end;

      case LAction of
        acaTypeRebuild:
          begin
            // (a)-(d): tmp NULLABLE, copy-cast, drop original, rename.
            _EmitTypeRebuild(LOut, LMaster);
            if LMaster.NotNull then
            begin
              // A coluna foi recriada via tmp NULLABLE, entao o NOT NULL desejado
              // precisa ser REAFIRMADO como passo final. (e-pre) backfill quando ha
              // default (evita falha por NULLs vindos do CAST de origem nullable);
              // (e/f) reusa o ALTER original como o SET NOT NULL final.
              if Trim(LMaster.DefaultValue) <> '' then
                _EmitBackfill(LOut, LMaster)
              else
                LCommand.AppendWarning(
                  'RISK: SET NOT NULL final (rebuild) falhara se a coluna tiver ' +
                  'linhas NULL e nao houver DefaultValue para backfill.');
              LOut.Add(LCommand);        // ALTER original reusado como SET NOT NULL
            end
            else
              FReplaced.Add(LCommand);   // sem NOT NULL: ALTER original superado - caller frees it
          end;
        acaBackfillNotNull:
          begin
            _EmitBackfill(LOut, LMaster);
            LOut.Add(LCommand);        // keep the ALTER (it carries SET NOT NULL)
          end;
        acaInPlaceWithWarning:
          begin
            LCommand.AppendWarning(
              'RISK: NOT NULL adicionado a coluna existente SEM default; ' +
              'linhas com NULL farao a alteracao falhar. Rebuild nao aplicado ' +
              '(defina um DefaultValue para backfill automatico).');
            LOut.Add(LCommand);
          end;
      else
        LOut.Add(LCommand);            // acaInPlace
      end;
    end;
    Result := LOut.ToArray;
  finally
    LOut.Free;
  end;
end;

function TAlterColumnRebuilder.ExtractOwnedColumns: TArray<TColumnMIK>;
begin
  Result := FOwnedColumns.ToArray;
  // Release ownership to the caller (sole owner from here on). Clearing a list
  // whose OwnsObjects is now False does NOT free the instances.
  FOwnedColumns.OwnsObjects := False;
  FOwnedColumns.Clear;
end;

function TAlterColumnRebuilder.SuppressedNotes: TArray<String>;
begin
  Result := FSuppressed.ToArray;
end;

function TAlterColumnRebuilder.ReplacedCommands: TArray<TDDLCommand>;
begin
  Result := FReplaced.ToArray;
end;

end.
