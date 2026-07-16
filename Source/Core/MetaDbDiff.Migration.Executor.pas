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

{ @abstract(MetaDbDiff - First-class migration executor.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)

  Consumes a phase-ordered plan (TDDLSequenceReport from MetaDbDiff.DDL.Sequencer,
  or a raw TArray<TDDLCommand>) whose commands already carry their built SQL
  (front-line F1 guarantees BuildCommand at generation time) and runs it in one
  of three modes:

    * mmDryRun    - never touches the database; produces the consolidated script
                    (phase headers as SQL comments). IDBConnection may be nil.
    * mmScriptOut - writes that same script to a UTF-8 file. Connection optional.
    * mmExecute   - runs command-by-command against a live IDBConnection.

  Transaction honesty:
    Several RDBMS auto-COMMIT DDL implicitly (Oracle, MySQL/MariaDB, DB2, ...),
    so a phase rollback is a lie there. The executor takes the TDriverName and
    only opens a per-phase transaction for dialects with transactional DDL
    (Firebird / Firebird3 / PostgreSQL / MSSQL / SQLite / Interbase). For every
    other dialect it runs without a transaction and the report flags
    TransactionalDDL = False so callers know rollback was never on the table.

  Connection ownership:
    The executor USES but never OWNS the caller's connection - it never calls
    Disconnect (and never Connect; the caller must supply a connected instance
    for mmExecute).

  Future integration point (front-line F2 - policy): mmExecute has a marked
  pre-validation hook where a migration policy would gate the plan before any
  SQL runs. F2 is developed in parallel, so this unit has no dependency on it.
}

unit MetaDbDiff.Migration.Executor;

interface

uses
  SysUtils,
  StrUtils,
  Classes,
  IOUtils,
  Diagnostics,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Sequencer;

type
  TMigrationMode = (mmDryRun, mmScriptOut, mmExecute);

  TMigrationErrorPolicy = (mepStopOnError, mepContinueOnError);

  TMigrationItemStatus = (misPending, misSuccess, misFailed, misSkipped, misEmpty);

  /// <summary>Per-command execution outcome.</summary>
  TMigrationItemReport = record
    Sequence: Integer;              // 1-based position in the executed plan
    Phase: TDDLPhase;
    PhaseName: String;
    Warning: String;                // human description (TDDLCommand.Warning)
    SQL: String;                    // the built command text
    Status: TMigrationItemStatus;
    ErrorMessage: String;
    DurationMs: Int64;
  end;

  /// <summary>Aggregate result of a migration run.</summary>
  TMigrationReport = record
    Mode: TMigrationMode;
    Driver: TDriverName;
    DriverName: String;
    /// <summary>Whether the dialect supports rollback of DDL.</summary>
    TransactionalDDL: Boolean;
    /// <summary>True if any phase transaction was rolled back.</summary>
    RolledBack: Boolean;
    Total: Integer;
    Succeeded: Integer;
    Failed: Integer;
    Skipped: Integer;
    Empty: Integer;
    Items: TArray<TMigrationItemReport>;
    /// <summary>Cycles carried over from the sequencer (informational).</summary>
    Cycles: TArray<TDDLCycleInfo>;
    /// <summary>Consolidated script (mmDryRun / mmScriptOut; also filled for mmExecute).</summary>
    Script: String;
    function ToString: String;
  end;

  /// <summary>
  ///   Runs a DDL migration plan. One instance is bound to one driver dialect.
  /// </summary>
  TMigrationExecutor = class
  strict private
    FDriver: TDriverName;
    FErrorPolicy: TMigrationErrorPolicy;
    FUsePhaseTransactions: Boolean;
    function DriverText: String;
    function BuildConsolidatedScript(const AItems: TArray<TDDLPhaseItem>): String;
    function PlanFromCommands(const ACommands: TArray<TDDLCommand>): TArray<TDDLPhaseItem>;
    procedure InitReport(var AReport: TMigrationReport; AMode: TMigrationMode;
      const ACycles: TArray<TDDLCycleInfo>);
  public
    constructor Create(ADriver: TDriverName);
    /// <summary>Returns True for dialects where DDL participates in transactions.</summary>
    class function DialectHasTransactionalDDL(ADriver: TDriverName): Boolean; static;

    // ---- mode entry points (TDDLSequenceReport) ---------------------------
    /// <summary>Consolidated script only; never touches the DB (connection may be nil).</summary>
    function DryRun(const ASequence: TDDLSequenceReport): TMigrationReport; overload;
    /// <summary>Writes the consolidated script to AFileName as UTF-8.</summary>
    function ScriptOut(const ASequence: TDDLSequenceReport; const AFileName: String): TMigrationReport; overload;
    /// <summary>Runs command-by-command against a live, connected IDBConnection.</summary>
    function Execute(const ASequence: TDDLSequenceReport; const AConnection: IDBConnection): TMigrationReport; overload;

    // ---- mode entry points (raw command array) ---------------------------
    // The array is treated as a single implicit phase (dphUnknown). Prefer the
    // TDDLSequenceReport overloads so phase transactions and headers apply.
    function DryRun(const ACommands: TArray<TDDLCommand>): TMigrationReport; overload;
    function ScriptOut(const ACommands: TArray<TDDLCommand>; const AFileName: String): TMigrationReport; overload;
    function Execute(const ACommands: TArray<TDDLCommand>; const AConnection: IDBConnection): TMigrationReport; overload;

    property ErrorPolicy: TMigrationErrorPolicy read FErrorPolicy write FErrorPolicy;
    /// <summary>When True (default) mmExecute wraps each phase in a transaction
    ///   on transactional dialects. Set False to run flat (still no rollback).</summary>
    property UsePhaseTransactions: Boolean read FUsePhaseTransactions write FUsePhaseTransactions;
    property Driver: TDriverName read FDriver;
  end;

implementation

{ ---------------------------------------------------------------------------- }
{ TMigrationReport                                                               }
{ ---------------------------------------------------------------------------- }

function TMigrationReport.ToString: String;
const
  CMode: array[TMigrationMode] of String = ('DryRun', 'ScriptOut', 'Execute');
  CStatus: array[TMigrationItemStatus] of String =
    ('Pending', 'OK', 'FAIL', 'Skipped', 'Empty');
var
  LBuilder: TStringBuilder;
  LItem: TMigrationItemReport;
begin
  LBuilder := TStringBuilder.Create;
  try
    LBuilder
      .Append('Migration [').Append(CMode[Mode]).Append('] driver=')
      .Append(DriverName)
      .Append(' transactionalDDL=').Append(BoolToStr(TransactionalDDL, True))
      .Append(' rolledBack=').Append(BoolToStr(RolledBack, True))
      .AppendLine;
    LBuilder
      .Append('total=').Append(Total)
      .Append(' ok=').Append(Succeeded)
      .Append(' fail=').Append(Failed)
      .Append(' skipped=').Append(Skipped)
      .Append(' empty=').Append(Empty)
      .AppendLine;
    for LItem in Items do
      LBuilder
        .Append('  #').Append(LItem.Sequence)
        .Append(' [').Append(CStatus[LItem.Status]).Append('] ')
        .Append(LItem.PhaseName).Append(' | ')
        .Append(LItem.Warning)
        .Append(ifThen(LItem.ErrorMessage <> '', ' -> ' + LItem.ErrorMessage, ''))
        .AppendLine;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TMigrationExecutor                                                             }
{ ---------------------------------------------------------------------------- }

constructor TMigrationExecutor.Create(ADriver: TDriverName);
begin
  inherited Create;
  FDriver := ADriver;
  FErrorPolicy := mepStopOnError;
  FUsePhaseTransactions := True;
end;

class function TMigrationExecutor.DialectHasTransactionalDDL(
  ADriver: TDriverName): Boolean;
begin
  // Dialects whose DDL participates in the surrounding transaction (so a
  // rollback truly undoes it). Everything else auto-commits DDL implicitly.
  case ADriver of
    dnFirebird,
    dnFirebird3,
    dnPostgreSQL,
    dnMSSQL,
    dnSQLite,
    dnInterbase: Result := True;
  else
    Result := False;   // MySQL, MariaDB, Oracle, DB2, Informix, NoSQL, ...
  end;
end;

function TMigrationExecutor.DriverText: String;
begin
  if (Ord(FDriver) >= Ord(Low(TStrDriverName))) and
     (Ord(FDriver) <= Ord(High(TStrDriverName))) then
    Result := TStrDriverName[FDriver]
  else
    Result := 'Driver#' + IntToStr(Ord(FDriver));
end;

function TMigrationExecutor.PlanFromCommands(
  const ACommands: TArray<TDDLCommand>): TArray<TDDLPhaseItem>;
var
  LFor: Integer;
begin
  SetLength(Result, Length(ACommands));
  for LFor := 0 to High(ACommands) do
  begin
    Result[LFor].Command := ACommands[LFor];
    Result[LFor].Phase := dphUnknown;
    Result[LFor].ObjectName := '';
    Result[LFor].OriginalIndex := LFor;
  end;
end;

function TMigrationExecutor.BuildConsolidatedScript(
  const AItems: TArray<TDDLPhaseItem>): String;
var
  LBuilder: TStringBuilder;
  LItem: TDDLPhaseItem;
  LSQL: String;
  LLastPhase: TDDLPhase;
  LFirst: Boolean;
begin
  LBuilder := TStringBuilder.Create;
  try
    LBuilder.AppendLine('-- ============================================================');
    LBuilder.AppendLine('-- MetaDbDiff migration script');
    LBuilder.Append('-- Dialect: ').AppendLine(DriverText);
    LBuilder.Append('-- Transactional DDL: ')
            .AppendLine(BoolToStr(DialectHasTransactionalDDL(FDriver), True));
    LBuilder.AppendLine('-- ============================================================');

    LLastPhase := dphPre;
    LFirst := True;
    for LItem in AItems do
    begin
      LSQL := '';
      if Assigned(LItem.Command) then
        LSQL := LItem.Command.Command;
      if Trim(LSQL) = '' then
        Continue;                              // nothing to emit for this command

      if LFirst or (LItem.Phase <> LLastPhase) then
      begin
        LBuilder.AppendLine;
        LBuilder.Append('-- ---------- PHASE: ')
                .Append(TDDLSequencer.PhaseName(LItem.Phase))
                .AppendLine(' ----------');
        LLastPhase := LItem.Phase;
        LFirst := False;
      end;

      if Assigned(LItem.Command) and (LItem.Command.Warning <> '') then
        LBuilder.Append('-- ').AppendLine(LItem.Command.Warning);
      LBuilder.AppendLine(LSQL);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

procedure TMigrationExecutor.InitReport(var AReport: TMigrationReport;
  AMode: TMigrationMode; const ACycles: TArray<TDDLCycleInfo>);
begin
  AReport := Default(TMigrationReport);
  AReport.Mode := AMode;
  AReport.Driver := FDriver;
  AReport.DriverName := DriverText;
  AReport.TransactionalDDL := DialectHasTransactionalDDL(FDriver);
  AReport.Cycles := ACycles;
end;

{ ---- DryRun / ScriptOut ----------------------------------------------------- }

function TMigrationExecutor.DryRun(
  const ASequence: TDDLSequenceReport): TMigrationReport;
var
  LItem: TDDLPhaseItem;
  LSQL: String;
  LOut: TMigrationItemReport;
begin
  InitReport(Result, mmDryRun, ASequence.Cycles);
  Result.Script := BuildConsolidatedScript(ASequence.Items);
  for LItem in ASequence.Items do
  begin
    LSQL := '';
    if Assigned(LItem.Command) then
      LSQL := LItem.Command.Command;
    LOut := Default(TMigrationItemReport);
    LOut.Sequence := Result.Total + 1;
    LOut.Phase := LItem.Phase;
    LOut.PhaseName := TDDLSequencer.PhaseName(LItem.Phase);
    if Assigned(LItem.Command) then
      LOut.Warning := LItem.Command.Warning;
    LOut.SQL := LSQL;
    if Trim(LSQL) = '' then
    begin
      LOut.Status := misEmpty;
      Inc(Result.Empty);
    end
    else
      LOut.Status := misPending;             // dry-run: not executed
    Result.Items := Result.Items + [LOut];
    Inc(Result.Total);
  end;
end;

function TMigrationExecutor.ScriptOut(const ASequence: TDDLSequenceReport;
  const AFileName: String): TMigrationReport;
begin
  Result := DryRun(ASequence);
  Result.Mode := mmScriptOut;
  // UTF-8 file (no BOM would also do; TEncoding.UTF8 writes a BOM which most
  // SQL clients tolerate). The caller chose the path.
  TFile.WriteAllText(AFileName, Result.Script, TEncoding.UTF8);
end;

{ ---- Execute ---------------------------------------------------------------- }

function TMigrationExecutor.Execute(const ASequence: TDDLSequenceReport;
  const AConnection: IDBConnection): TMigrationReport;
var
  LItems: TArray<TDDLPhaseItem>;
  LFor: Integer;
  LItem: TDDLPhaseItem;
  LSQL: String;
  LOut: TMigrationItemReport;
  LWatch: TStopwatch;
  LTransactional: Boolean;
  LPhaseOpen: Boolean;
  LCurrentPhase: TDDLPhase;
  LStopped: Boolean;

  procedure CommitPhaseIfOpen;
  begin
    if LPhaseOpen and AConnection.InTransaction then
      AConnection.Commit;
    LPhaseOpen := False;
  end;

  procedure RollbackPhaseIfOpen;
  begin
    if LPhaseOpen and AConnection.InTransaction then
    begin
      AConnection.Rollback;
      Result.RolledBack := True;
    end;
    LPhaseOpen := False;
  end;

begin
  InitReport(Result, mmExecute, ASequence.Cycles);
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create(
      'TMigrationExecutor.Execute: a connected IDBConnection is required in mmExecute.');
  if not AConnection.IsConnected then
    raise EInvalidOpException.Create(
      'TMigrationExecutor.Execute: the supplied IDBConnection is not connected.');

  // --------------------------------------------------------------------------
  // FUTURE INTEGRATION POINT (F2 - migration policy):
  //   Here the plan would be handed to a policy for pre-validation (forbidden
  //   operations, destructive-change guards, environment gates). A rejection
  //   would abort before a single statement runs. F2 is a parallel front-line,
  //   so no dependency is wired yet.
  // --------------------------------------------------------------------------

  Result.Script := BuildConsolidatedScript(ASequence.Items);
  LItems := ASequence.Items;
  LTransactional := FUsePhaseTransactions and Result.TransactionalDDL;
  LPhaseOpen := False;
  LStopped := False;
  LCurrentPhase := dphPre;

  try
    for LFor := 0 to High(LItems) do
    begin
      LItem := LItems[LFor];
      LSQL := '';
      if Assigned(LItem.Command) then
        LSQL := LItem.Command.Command;

      LOut := Default(TMigrationItemReport);
      LOut.Sequence := LFor + 1;
      LOut.Phase := LItem.Phase;
      LOut.PhaseName := TDDLSequencer.PhaseName(LItem.Phase);
      if Assigned(LItem.Command) then
        LOut.Warning := LItem.Command.Warning;
      LOut.SQL := LSQL;

      // Phase boundary: close previous transaction, open the next one.
      if (LFor = 0) or (LItem.Phase <> LCurrentPhase) then
      begin
        CommitPhaseIfOpen;
        LCurrentPhase := LItem.Phase;
        if LTransactional then
        begin
          AConnection.StartTransaction;
          LPhaseOpen := True;
        end;
      end;

      if LStopped then
      begin
        LOut.Status := misSkipped;
        Inc(Result.Skipped);
        Result.Items := Result.Items + [LOut];
        Inc(Result.Total);
        Continue;
      end;

      if Trim(LSQL) = '' then
      begin
        LOut.Status := misEmpty;
        Inc(Result.Empty);
        Result.Items := Result.Items + [LOut];
        Inc(Result.Total);
        Continue;
      end;

      LWatch := TStopwatch.StartNew;
      try
        AConnection.ExecuteScript(LSQL);
        LWatch.Stop;
        LOut.DurationMs := LWatch.ElapsedMilliseconds;
        LOut.Status := misSuccess;
        Inc(Result.Succeeded);
      except
        on E: Exception do
        begin
          LWatch.Stop;
          LOut.DurationMs := LWatch.ElapsedMilliseconds;
          LOut.Status := misFailed;
          LOut.ErrorMessage := E.Message;
          Inc(Result.Failed);
          // Roll the whole phase back (transactional dialects only).
          RollbackPhaseIfOpen;
          if FErrorPolicy = mepStopOnError then
            LStopped := True;
          // ContinueOnError: next phase boundary re-opens a fresh transaction.
        end;
      end;

      Result.Items := Result.Items + [LOut];
      Inc(Result.Total);
    end;

    CommitPhaseIfOpen;
  except
    // Unexpected failure outside per-command handling: never leave a dangling
    // transaction on the caller's connection.
    RollbackPhaseIfOpen;
    raise;
  end;
  // NOTE: we deliberately never call AConnection.Disconnect - the connection
  // belongs to the caller.
end;

{ ---- raw-array overloads ---------------------------------------------------- }

function TMigrationExecutor.DryRun(
  const ACommands: TArray<TDDLCommand>): TMigrationReport;
var
  LSeq: TDDLSequenceReport;
begin
  LSeq := Default(TDDLSequenceReport);
  LSeq.Items := PlanFromCommands(ACommands);
  Result := DryRun(LSeq);
end;

function TMigrationExecutor.ScriptOut(const ACommands: TArray<TDDLCommand>;
  const AFileName: String): TMigrationReport;
var
  LSeq: TDDLSequenceReport;
begin
  LSeq := Default(TDDLSequenceReport);
  LSeq.Items := PlanFromCommands(ACommands);
  Result := ScriptOut(LSeq, AFileName);
end;

function TMigrationExecutor.Execute(const ACommands: TArray<TDDLCommand>;
  const AConnection: IDBConnection): TMigrationReport;
var
  LSeq: TDDLSequenceReport;
begin
  LSeq := Default(TDDLSequenceReport);
  LSeq.Items := PlanFromCommands(ACommands);
  Result := Execute(LSeq, AConnection);
end;

end.
