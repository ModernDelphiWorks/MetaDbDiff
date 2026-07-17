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

{ @abstract(MetaDbDiff - DDL topological sequencer.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)

  Reorders a flat list of TDDLCommand into explicit, dependency-safe execution
  PHASES (PRE -> SEQUENCES -> CREATE TABLES [topological] -> COLUMNS -> PKs ->
  INDEXES -> CHECKS -> FKs -> VIEWS -> TRIGGERS -> POST), and mirrors DROPs in
  the inverse dependency order (referencer before referenced).

  Design note (why we read Warning):
    The concrete TDDLCommand subclasses keep their payload (TTableMIK, FK, ...)
    in strict-private fields with no public accessor. Since this front-line is
    forbidden from touching existing Source\ units, the sequencer classifies a
    command by its RTTI class type and, when it needs the target table name
    (topological ordering of CREATE/DROP TABLE) or the enable/disable direction,
    it parses the public, deterministic TDDLCommand.Warning string produced by
    the command's own constructor (e.g. 'Create Table: CLIENTE'). A future
    refactor could expose typed read-only accessors on TDDLCommand and drop the
    string parsing - see the reviewer notes in the PR description.

  The sequencer NEVER mutates the commands - it only reorders references to them.
}

unit MetaDbDiff.DDL.Sequencer;

interface

uses
  SysUtils,
  Classes,
  Math,
  Generics.Collections,
  Generics.Defaults,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.DDL.Commands;

type
  /// <summary>
  ///   Ordered execution phases. The declaration order IS the execution order.
  /// </summary>
  TDDLPhase = (
    dphPre,             // disable FKs / triggers (Enable*: Off)
    dphDropProcedures,  // FRENTE 15 - drop procs first (they reference tables)
    dphDropTriggers,
    dphDropViews,
    dphDropForeignKeys,
    dphDropChecks,
    dphDropIndexes,
    dphDropPrimaryKeys,
    dphDropColumns,     // drop column + drop default value
    dphDropTables,      // inverse topological order (referencer before referenced)
    dphDropSequences,
    dphDropDomains,     // FRENTE 15 - domains dropped LAST (columns/tables using them are gone)
    dphCreateSequences, // sequences exist before the tables that use them
    dphCreateDomains,   // FRENTE 15 - domains BEFORE tables (columns may use domains)
    dphCreateTables,    // topological order (referenced before referencer)
    dphColumns,         // create column / alter column / alter position / alter default
    dphPrimaryKeys,
    dphIndexes,
    dphChecks,          // create check / alter check
    dphForeignKeys,     // added last, when every table already exists
    dphViews,
    dphTriggers,
    dphProcedures,      // FRENTE 15 - after views/triggers
    dphUnknown,         // unrecognized command classes - preserved, run near the end
    dphComments,        // FRENTE 15 - COMMENT ON last, right before POST
    dphPost);           // re-enable FKs / triggers (Enable*: On)

  /// <summary>One command placed into a phase, with diagnostics.</summary>
  TDDLPhaseItem = record
    Command: TDDLCommand;
    Phase: TDDLPhase;
    ObjectName: String;    // name parsed from Warning (best effort, may be empty)
    OriginalIndex: Integer;
  end;

  /// <summary>A dependency cycle detected among CREATE (or DROP) TABLE commands.</summary>
  TDDLCycleInfo = record
    /// <summary>Table names that form the strongly-connected component (sorted).</summary>
    Tables: TArray<String>;
    /// <summary>True when the cycle was found while ordering DROP TABLEs.</summary>
    IsDrop: Boolean;
    function ToString: String;
  end;

  /// <summary>Full result of a sequencing pass.</summary>
  TDDLSequenceReport = record
    /// <summary>Commands in their final, dependency-safe execution order.</summary>
    Items: TArray<TDDLPhaseItem>;
    /// <summary>Cycles detected during topological ordering (create and drop).</summary>
    Cycles: TArray<TDDLCycleInfo>;
    /// <summary>Number of commands classified into each phase.</summary>
    PhaseCounts: array[TDDLPhase] of Integer;
    function HasCycles: Boolean;
    /// <summary>Reordered command references only (no phase metadata).</summary>
    function Commands: TArray<TDDLCommand>;
    /// <summary>Human readable phase-by-phase dump (used by tests / diagnostics).</summary>
    function ToDebugString: String;
  end;

  /// <summary>
  ///   Reorders TDDLCommand lists into dependency-safe phases. Stateless across
  ///   calls; keeps only references to the supplied catalogs.
  /// </summary>
  TDDLSequencer = class
  strict private
    FMaster: TCatalogMetadataMIK;   // desired end-state (drives CREATE ordering)
    FTarget: TCatalogMetadataMIK;   // current DB state (drives DROP ordering)
    function ExtractName(ACommand: TDDLCommand): String;
    function ClassifyPhase(ACommand: TDDLCommand; const AName: String): TDDLPhase;
    /// <summary>
    ///   Returns the table names ordered so that a referenced (parent) table
    ///   comes before its referencer. When AInverse is True the order is
    ///   reversed (drop order). Cyclic tables keep their original input order
    ///   and are reported through ACycles.
    /// </summary>
    function OrderTables(const ANames: TArray<String>; ACatalog: TCatalogMetadataMIK;
      AInverse: Boolean; var ACycles: TArray<TDDLCycleInfo>): TArray<String>;
  public
    /// <param name="AMaster">Catalog describing the desired end-state (CREATE side).</param>
    /// <param name="ATarget">Catalog describing the current DB (DROP side). May be nil,
    ///   in which case AMaster is used for both.</param>
    constructor Create(AMaster: TCatalogMetadataMIK; ATarget: TCatalogMetadataMIK = nil);
    /// <summary>Full sequencing with report (phases + cycles).</summary>
    function Sequence(const ACommands: TArray<TDDLCommand>): TDDLSequenceReport;
    /// <summary>Convenience: just the reordered command references.</summary>
    function Reorder(const ACommands: TArray<TDDLCommand>): TArray<TDDLCommand>;
    class function PhaseName(APhase: TDDLPhase): String; static;
  end;

implementation

const
  CPhaseNames: array[TDDLPhase] of String = (
    'Pre (disable FKs/triggers)',
    'Drop Procedures',
    'Drop Triggers',
    'Drop Views',
    'Drop ForeignKeys',
    'Drop Checks',
    'Drop Indexes',
    'Drop PrimaryKeys',
    'Drop Columns',
    'Drop Tables',
    'Drop Sequences',
    'Drop Domains',
    'Create Sequences',
    'Create Domains',
    'Create Tables',
    'Columns',
    'PrimaryKeys',
    'Indexes',
    'Checks',
    'ForeignKeys',
    'Views',
    'Triggers',
    'Procedures',
    'Unknown',
    'Comments',
    'Post (re-enable FKs/triggers)');

{ ---------------------------------------------------------------------------- }
{ Local helpers                                                                 }
{ ---------------------------------------------------------------------------- }

function SortedNames(const ANames: TArray<String>): TArray<String>;
begin
  Result := Copy(ANames, 0, Length(ANames));
  TArray.Sort<String>(Result, TComparer<String>.Construct(
    function(const L, R: String): Integer
    begin
      Result := CompareStr(L, R);
    end));
end;

{ ---------------------------------------------------------------------------- }
{ TDDLCycleInfo                                                                  }
{ ---------------------------------------------------------------------------- }

function TDDLCycleInfo.ToString: String;
begin
  if IsDrop then
    Result := 'DROP cycle: '
  else
    Result := 'CREATE cycle: ';
  Result := Result + String.Join(' -> ', Tables);
end;

{ ---------------------------------------------------------------------------- }
{ TDDLSequenceReport                                                             }
{ ---------------------------------------------------------------------------- }

function TDDLSequenceReport.HasCycles: Boolean;
begin
  Result := Length(Cycles) > 0;
end;

function TDDLSequenceReport.Commands: TArray<TDDLCommand>;
var
  LFor: Integer;
begin
  SetLength(Result, Length(Items));
  for LFor := 0 to High(Items) do
    Result[LFor] := Items[LFor].Command;
end;

function TDDLSequenceReport.ToDebugString: String;
var
  LBuilder: TStringBuilder;
  LItem: TDDLPhaseItem;
  LLastPhase: TDDLPhase;
  LFirst: Boolean;
  LCycle: TDDLCycleInfo;
begin
  LBuilder := TStringBuilder.Create;
  try
    LLastPhase := dphPre;
    LFirst := True;
    for LItem in Items do
    begin
      if LFirst or (LItem.Phase <> LLastPhase) then
      begin
        LBuilder.AppendLine('== ' + CPhaseNames[LItem.Phase] + ' ==');
        LLastPhase := LItem.Phase;
        LFirst := False;
      end;
      LBuilder.Append('  - ').Append(LItem.Command.Warning);
      if LItem.ObjectName <> '' then
        LBuilder.Append(' [').Append(LItem.ObjectName).Append(']');
      LBuilder.AppendLine;
    end;
    for LCycle in Cycles do
      LBuilder.AppendLine('!! ' + LCycle.ToString);
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TDDLSequencer                                                                  }
{ ---------------------------------------------------------------------------- }

constructor TDDLSequencer.Create(AMaster: TCatalogMetadataMIK;
  ATarget: TCatalogMetadataMIK);
begin
  inherited Create;
  FMaster := AMaster;
  if Assigned(ATarget) then
    FTarget := ATarget
  else
    FTarget := AMaster;
end;

class function TDDLSequencer.PhaseName(APhase: TDDLPhase): String;
begin
  Result := CPhaseNames[APhase];
end;

function TDDLSequencer.ExtractName(ACommand: TDDLCommand): String;
var
  LWarning: String;
  LPos: Integer;
begin
  // Warning is always 'Something: value' (see TDDLCommand*.Create). Everything
  // after the first ': ' is the object name (or 'On'/'Off' for Enable* commands).
  LWarning := ACommand.Warning;
  LPos := Pos(': ', LWarning);
  if LPos > 0 then
    Result := Trim(Copy(LWarning, LPos + 2, MaxInt))
  else
    Result := '';
end;

function TDDLSequencer.ClassifyPhase(ACommand: TDDLCommand;
  const AName: String): TDDLPhase;
begin
  // Enable* commands share one class; the direction lives in the Warning suffix.
  if (ACommand is TDDLCommandEnableForeignKeys) or
     (ACommand is TDDLCommandEnableTriggers) then
  begin
    if SameText(AName, 'On') then
      Exit(dphPost)
    else
      Exit(dphPre);
  end;

  // Safe alter-column REBUILD steps (FRENTE 11) devem ficar JUNTOS e NA ORDEM na
  // fase COLUMNS. Checados ANTES de TDDLCommandDropColumn/CreateColumn porque as
  // subclasses de rebuild casam com o `is` da base; o drop de rebuild NAO pode
  // cair na fase 'Drop Columns' (que roda antes de COLUMNS e destruiria a coluna
  // antes da copia). A ordem relativa dentro da fase e preservada por OriginalIndex.
  if ACommand is TDDLCommandCreateColumnRebuild then Exit(dphColumns);
  if ACommand is TDDLCommandDropColumnRebuild then Exit(dphColumns);
  if ACommand is TDDLCommandCopyColumnData then Exit(dphColumns);
  if ACommand is TDDLCommandRenameColumn then Exit(dphColumns);

  // FRENTE 15: Comments por ultimo (antes do POST).
  if ACommand is TDDLCommandSetComment then Exit(dphComments);

  // Drops (inverse dependency order for tables handled later).
  if ACommand is TDDLCommandDropProcedure then Exit(dphDropProcedures);
  if ACommand is TDDLCommandDropDomain then Exit(dphDropDomains);
  if ACommand is TDDLCommandDropTrigger then Exit(dphDropTriggers);
  if ACommand is TDDLCommandDropView then Exit(dphDropViews);
  if ACommand is TDDLCommandDropForeignKey then Exit(dphDropForeignKeys);
  if ACommand is TDDLCommandDropCheck then Exit(dphDropChecks);
  if ACommand is TDDLCommandDropIndexe then Exit(dphDropIndexes);
  if ACommand is TDDLCommandDropPrimaryKey then Exit(dphDropPrimaryKeys);
  if ACommand is TDDLCommandDropColumn then Exit(dphDropColumns);
  if ACommand is TDDLCommandDropDefaultValue then Exit(dphDropColumns);
  if ACommand is TDDLCommandDropTable then Exit(dphDropTables);
  if ACommand is TDDLCommandDropSequence then Exit(dphDropSequences);

  // Creates / alters.
  if ACommand is TDDLCommandCreateProcedure then Exit(dphProcedures);
  if ACommand is TDDLCommandCreateDomain then Exit(dphCreateDomains);
  if ACommand is TDDLCommandCreateSequence then Exit(dphCreateSequences);
  // ALTER SEQUENCE roda na mesma fase de SEQUENCES: a sequence ja existe (create
  // nao ocorre) e o alter apenas ajusta InitialValue/Increment antes das tabelas.
  if ACommand is TDDLCommandAlterSequence then Exit(dphCreateSequences);
  if ACommand is TDDLCommandCreateTable then Exit(dphCreateTables);
  if ACommand is TDDLCommandCreateColumn then Exit(dphColumns);
  if ACommand is TDDLCommandAlterColumnPosition then Exit(dphColumns);
  if ACommand is TDDLCommandAlterColumn then Exit(dphColumns);
  if ACommand is TDDLCommandAlterDefaultValue then Exit(dphColumns);
  if ACommand is TDDLCommandCreatePrimaryKey then Exit(dphPrimaryKeys);
  if ACommand is TDDLCommandCreateIndexe then Exit(dphIndexes);
  if ACommand is TDDLCommandAlterCheck then Exit(dphChecks);
  if ACommand is TDDLCommandCreateCheck then Exit(dphChecks);
  if ACommand is TDDLCommandCreateForeignKey then Exit(dphForeignKeys);
  if ACommand is TDDLCommandCreateView then Exit(dphViews);
  if ACommand is TDDLCommandCreateTrigger then Exit(dphTriggers);

  Result := dphUnknown;
end;

function TDDLSequencer.OrderTables(const ANames: TArray<String>;
  ACatalog: TCatalogMetadataMIK; AInverse: Boolean;
  var ACycles: TArray<TDDLCycleInfo>): TArray<String>;
var
  // All graph structures are keyed by the UPPER-CASE (normalized) table name so
  // that a FK whose FromTable differs only in casing still matches its parent
  // node. LDisplay maps each normalized key back to the first-seen original
  // spelling, which is what we emit (and what the caller ranks commands by).
  LNodes: TList<String>;                            // normalized keys, input order
  LNodeSet: TDictionary<String, Integer>;           // normKey -> first input index
  LDisplay: TDictionary<String, String>;            // normKey -> original spelling
  LDeps: TObjectDictionary<String, TList<String>>;  // node -> parents (in set)
  LDependents: TObjectDictionary<String, TList<String>>; // parent -> children
  LIndeg: TDictionary<String, Integer>;
  LName, LKey, LParent, LChild, LNode: String;
  LTable: TTableMIK;
  LFK: TPair<String, TForeignKeyMIK>;
  LReady: TList<String>;
  LEmitted: TList<String>;
  LFor: Integer;

  procedure InsertSorted(AList: TList<String>; const AValue: String);
  var
    I: Integer;
  begin
    for I := 0 to AList.Count - 1 do
      if CompareStr(AValue, AList[I]) < 0 then
      begin
        AList.Insert(I, AValue);
        Exit;
      end;
    AList.Add(AValue);
  end;

  // Tarjan strongly-connected components, purely to REPORT cycles; the ordering
  // itself is the deterministic Kahn pass below.
  procedure DetectCycles;
  var
    LIndexCounter: Integer;
    LStack: TList<String>;
    LOnStack: TDictionary<String, Boolean>;
    LIndex: TDictionary<String, Integer>;
    LLowLink: TDictionary<String, Integer>;
    LRoot: String;

    procedure StrongConnect(const AV: String);
    var
      LW, LPopped: String;
      LComp: TList<String>;
      LCycle: TDDLCycleInfo;
      LIdx: Integer;
    begin
      LIndex.AddOrSetValue(AV, LIndexCounter);
      LLowLink.AddOrSetValue(AV, LIndexCounter);
      Inc(LIndexCounter);
      LStack.Add(AV);
      LOnStack.AddOrSetValue(AV, True);

      for LW in SortedNames(LDeps[AV].ToArray) do
      begin
        if not LIndex.ContainsKey(LW) then
        begin
          StrongConnect(LW);
          if LLowLink[LW] < LLowLink[AV] then
            LLowLink[AV] := LLowLink[LW];
        end
        else if LOnStack.ContainsKey(LW) and LOnStack[LW] then
        begin
          if LIndex[LW] < LLowLink[AV] then
            LLowLink[AV] := LIndex[LW];
        end;
      end;

      if LLowLink[AV] = LIndex[AV] then
      begin
        LComp := TList<String>.Create;
        try
          repeat
            LPopped := LStack[LStack.Count - 1];
            LStack.Delete(LStack.Count - 1);
            LOnStack[LPopped] := False;
            LComp.Add(LPopped);
          until LPopped = AV;
          if LComp.Count > 1 then
          begin
            // Map normalized keys back to their display spelling for the report.
            for LIdx := 0 to LComp.Count - 1 do
              LComp[LIdx] := LDisplay[LComp[LIdx]];
            LCycle.Tables := SortedNames(LComp.ToArray);
            LCycle.IsDrop := AInverse;
            ACycles := ACycles + [LCycle];
          end;
        finally
          LComp.Free;
        end;
      end;
    end;

  begin
    LIndexCounter := 0;
    LStack := TList<String>.Create;
    LOnStack := TDictionary<String, Boolean>.Create;
    LIndex := TDictionary<String, Integer>.Create;
    LLowLink := TDictionary<String, Integer>.Create;
    try
      for LRoot in SortedNames(LNodes.ToArray) do
        if not LIndex.ContainsKey(LRoot) then
          StrongConnect(LRoot);
    finally
      LLowLink.Free;
      LIndex.Free;
      LOnStack.Free;
      LStack.Free;
    end;
  end;

begin
  LNodes := TList<String>.Create;
  LNodeSet := TDictionary<String, Integer>.Create;
  LDisplay := TDictionary<String, String>.Create;
  LDeps := TObjectDictionary<String, TList<String>>.Create([doOwnsValues]);
  LDependents := TObjectDictionary<String, TList<String>>.Create([doOwnsValues]);
  LIndeg := TDictionary<String, Integer>.Create;
  LReady := TList<String>.Create;
  LEmitted := TList<String>.Create;
  try
    // 1) node set (normalized key, de-dup, keep first-seen input spelling)
    for LName in ANames do
    begin
      if LName = '' then
        Continue;
      LKey := UpperCase(LName);
      if not LNodeSet.ContainsKey(LKey) then
      begin
        LNodeSet.Add(LKey, LNodes.Count);
        LNodes.Add(LKey);
        LDisplay.Add(LKey, LName);
        LDeps.Add(LKey, TList<String>.Create);
        LDependents.Add(LKey, TList<String>.Create);
        LIndeg.Add(LKey, 0);
      end;
    end;

    // 2) edges from FK metadata: child depends on parent (FK.FromTable).
    //    Both node keys and FromTable are upper-cased so casing never drops
    //    an edge silently.
    for LKey in LNodes do
    begin
      if not ACatalog.Tables.TryGetValue(LDisplay[LKey], LTable) then
        Continue;
      for LFK in LTable.ForeignKeys do
      begin
        LParent := UpperCase(LFK.Value.FromTable);
        if (LParent = '') or SameStr(LParent, LKey) then
          Continue;                       // ignore self references
        if not LNodeSet.ContainsKey(LParent) then
          Continue;                       // parent not part of this batch
        if LDeps[LKey].IndexOf(LParent) < 0 then
        begin
          LDeps[LKey].Add(LParent);
          LDependents[LParent].Add(LKey);
          LIndeg[LKey] := LIndeg[LKey] + 1;
        end;
      end;
    end;

    // 3) report cycles (independent of ordering)
    DetectCycles;

    // 4) deterministic Kahn: emit parents before children, ties by name
    for LNode in SortedNames(LNodes.ToArray) do
      if LIndeg[LNode] = 0 then
        InsertSorted(LReady, LNode);

    while LReady.Count > 0 do
    begin
      LNode := LReady[0];
      LReady.Delete(0);
      LEmitted.Add(LNode);
      for LChild in SortedNames(LDependents[LNode].ToArray) do
      begin
        LIndeg[LChild] := LIndeg[LChild] - 1;
        if LIndeg[LChild] = 0 then
          InsertSorted(LReady, LChild);
      end;
    end;

    // 5) cyclic remainder (never reached in-degree 0): keep original input order
    if LEmitted.Count < LNodes.Count then
      for LName in LNodes do
        if LEmitted.IndexOf(LName) < 0 then
          LEmitted.Add(LName);

    // 6) create order = parents first; drop order = inverse. Emit the display
    //    spelling (the caller ranks its commands by ObjectName == this string).
    SetLength(Result, LEmitted.Count);
    if AInverse then
      for LFor := 0 to LEmitted.Count - 1 do
        Result[LFor] := LDisplay[LEmitted[LEmitted.Count - 1 - LFor]]
    else
      for LFor := 0 to LEmitted.Count - 1 do
        Result[LFor] := LDisplay[LEmitted[LFor]];
  finally
    LEmitted.Free;
    LReady.Free;
    LIndeg.Free;
    LDependents.Free;
    LDeps.Free;
    LDisplay.Free;
    LNodeSet.Free;
    LNodes.Free;
  end;
end;

function TDDLSequencer.Sequence(
  const ACommands: TArray<TDDLCommand>): TDDLSequenceReport;
var
  LItems: TArray<TDDLPhaseItem>;
  LFor, LOut: Integer;
  LPhase: TDDLPhase;
  LCreateNames, LDropNames: TArray<String>;
  LCreateOrder, LDropOrder: TArray<String>;
  LTableRank: TDictionary<String, Integer>;
  LPhaseList: TObjectList<TList<Integer>>; // phase -> item indices
  LList: TList<Integer>;
  LResult: TArray<TDDLPhaseItem>;

  procedure OrderTablePhase(APhase: TDDLPhase; const ARank: TDictionary<String, Integer>);
  begin
    LPhaseList[Ord(APhase)].Sort(TComparer<Integer>.Construct(
      function(const L, R: Integer): Integer
      var
        LRankL, LRankR: Integer;
      begin
        // Rank by table topological position; unknown names keep input order.
        if not ARank.TryGetValue(LItems[L].ObjectName, LRankL) then
          LRankL := MaxInt;
        if not ARank.TryGetValue(LItems[R].ObjectName, LRankR) then
          LRankR := MaxInt;
        Result := CompareValue(LRankL, LRankR);
        if Result = 0 then
          Result := CompareValue(LItems[L].OriginalIndex, LItems[R].OriginalIndex);
      end));
  end;

begin
  Result := Default(TDDLSequenceReport);

  // ---- classify ------------------------------------------------------------
  SetLength(LItems, Length(ACommands));
  for LFor := 0 to High(ACommands) do
  begin
    LItems[LFor].Command := ACommands[LFor];
    LItems[LFor].OriginalIndex := LFor;
    LItems[LFor].ObjectName := ExtractName(ACommands[LFor]);
    LItems[LFor].Phase := ClassifyPhase(ACommands[LFor], LItems[LFor].ObjectName);
    Result.PhaseCounts[LItems[LFor].Phase] := Result.PhaseCounts[LItems[LFor].Phase] + 1;
  end;

  // ---- bucket per phase (stable: input order) ------------------------------
  LPhaseList := TObjectList<TList<Integer>>.Create(True);
  LTableRank := TDictionary<String, Integer>.Create;
  try
    for LPhase := Low(TDDLPhase) to High(TDDLPhase) do
      LPhaseList.Add(TList<Integer>.Create);
    for LFor := 0 to High(LItems) do
      LPhaseList[Ord(LItems[LFor].Phase)].Add(LFor);

    // ---- CREATE TABLE: topological order ----------------------------------
    LList := LPhaseList[Ord(dphCreateTables)];
    if LList.Count > 0 then
    begin
      SetLength(LCreateNames, LList.Count);
      for LFor := 0 to LList.Count - 1 do
        LCreateNames[LFor] := LItems[LList[LFor]].ObjectName;
      LCreateOrder := OrderTables(LCreateNames, FMaster, False, Result.Cycles);
      LTableRank.Clear;
      for LFor := 0 to High(LCreateOrder) do
        LTableRank.AddOrSetValue(LCreateOrder[LFor], LFor);
      OrderTablePhase(dphCreateTables, LTableRank);
    end;

    // ---- DROP TABLE: inverse topological order ----------------------------
    LList := LPhaseList[Ord(dphDropTables)];
    if LList.Count > 0 then
    begin
      SetLength(LDropNames, LList.Count);
      for LFor := 0 to LList.Count - 1 do
        LDropNames[LFor] := LItems[LList[LFor]].ObjectName;
      LDropOrder := OrderTables(LDropNames, FTarget, True, Result.Cycles);
      LTableRank.Clear;
      for LFor := 0 to High(LDropOrder) do
        LTableRank.AddOrSetValue(LDropOrder[LFor], LFor);
      OrderTablePhase(dphDropTables, LTableRank);
    end;

    // ---- flatten in phase order -------------------------------------------
    SetLength(LResult, Length(LItems));
    LOut := 0;
    for LPhase := Low(TDDLPhase) to High(TDDLPhase) do
    begin
      LList := LPhaseList[Ord(LPhase)];
      for LFor := 0 to LList.Count - 1 do
      begin
        LResult[LOut] := LItems[LList[LFor]];
        Inc(LOut);
      end;
    end;
    Result.Items := LResult;
  finally
    LTableRank.Free;
    LPhaseList.Free;
  end;
end;

function TDDLSequencer.Reorder(
  const ACommands: TArray<TDDLCommand>): TArray<TDDLCommand>;
begin
  Result := Sequence(ACommands).Commands;
end;

end.
