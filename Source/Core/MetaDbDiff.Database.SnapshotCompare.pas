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

  "Metadata snapshot" feature: compares a catalog previously exported to a
  FILE (MetaDbDiff.Metadata.Snapshot.pas / TMetadataExporter, see
  MetaDbDiff.Metadata.Snapshot.Export.pas) against a LIVE target database,
  and generates the DDL script that brings the target in line with whatever
  the snapshot describes - WITHOUT the machine running this comparison ever
  needing network access to the original source database. Typical flow:
  the owner extracts metadata from the source database (or from the
  decorated model classes) on a machine that CAN reach it, ships the
  resulting file to the client, and the client runs
  TSnapshotDatabaseCompare(SnapshotFile, LocalConnection) locally.

  This is a straight sibling of MetaDbDiff.Database.ModelCompare.pas
  (TModelDatabaseCompare, "decorated classes vs database") and
  MetaDbDiff.Database.Compare.pas (TDatabaseCompare, "database vs database"):
  same TDatabaseFactory-based orchestration, only the MASTER-side metadata
  source changes - TMetadataSnapshotFactory (reads a file) instead of
  TMetadataModelFactory (reads decorated classes) or TMetadataDBFactory
  (reads another live connection).

  Master = snapshot (file, no connection). Target = the live connection
  passed by the caller (AConnTarget) - this is the connection whose driver
  decides the DDL dialect used to build the migration script, because that
  script is meant to run AGAINST the target. Deliberate differences from
  MetaDbDiff.Database.ModelCompare.pas:
    - There is no "single physical connection reused on both sides" here: the
      snapshot side has NO connection at all (it is a file), so there is
      exactly one IDBConnection in play, AConnTarget, and it is used ONLY for
      the target side.
    - Connection lifecycle mirrors TModelDatabaseCompare exactly: this class
      connects AConnTarget in the constructor (raising if it fails) but NEVER
      calls Disconnect on it anywhere - not in ExecuteDDLCommands, not in the
      destructor. AConnTarget is owned by the CALLER, who decides when to
      disconnect it (e.g. to reuse it afterwards, or because it manages a
      connection pool). Contrast with MetaDbDiff.Database.Compare.pas's
      TDatabaseCompare, whose ExecuteDDLCommands DOES disconnect both
      connections in a finally block - that class is out of scope here and is
      only referenced for context (see the TModelDatabaseCompare header for
      the same contrast).
    - ExecuteDDLCommands follows the immediate-execute-inside-one-transaction
      pattern (StartTransaction/Commit/Rollback via ExecuteScript per command),
      exactly like TModelDatabaseCompare - NOT the AddScript+ExecuteScripts
      batching pattern TDatabaseCompare uses.

  CROSS-DIALECT LIMITATION (v1, documented - see also the header comment of
  MetaDbDiff.Metadata.Snapshot.pas): a snapshot stores TColumnMIK.TypeName
  VERBATIM, exactly as produced by whichever driver extracted it (e.g.
  Firebird's 'VARCHAR(%l)', MSSQL's 'INT'). This class always drives DDL
  generation off the TARGET connection's driver (FGeneratorCommand comes from
  AConnTarget.GetDriver, via the inherited TDatabaseFactory constructor),
  because the generated script has to run on the target. If the snapshot was
  produced against a DIFFERENT dialect than AConnTarget's, DeepEqualsColumn
  (MetaDbDiff.Database.Factory.pas) compares TypeName as plain text and will
  very likely flag semantically-identical columns as different, generating
  FALSE ALTER COLUMN commands (and possibly other false positives wherever a
  dialect-specific string is compared verbatim, e.g. DEFAULT expressions).
  RECOMMENDATION: only diff a snapshot against a target of the SAME dialect
  it was extracted from. Cross-dialect snapshot diffing is not supported in
  v1 - it would require translating TypeName between dialects, which is out
  of scope for this feature.
}

unit MetaDbDiff.Database.SnapshotCompare;

interface

uses
  SysUtils,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Snapshot.Factory,
  MetaDbDiff.Metadata.DB.Factory,
  MetaDbDiff.Database.Factory;

type
  TSnapshotDatabaseCompare = class(TDatabaseFactory)
  protected
    // The only physical connection in play: the live TARGET database. Owned
    // by the caller, never disconnected by this class (see the unit header
    // comment above).
    FConnTarget: IDBConnection;
    FMetadataMaster: TMetadataSnapshotAbstract;
    FMetadataTarget: TMetadataDBAbstract;
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(const ASnapshotFile: String; AConnTarget: IDBConnection); overload;
    destructor Destroy; override;
  end;

implementation

uses
  MetaDbDiff.DDL.Commands;

{ TSnapshotDatabaseCompare }

constructor TSnapshotDatabaseCompare.Create(const ASnapshotFile: String; AConnTarget: IDBConnection);
begin
  if Trim(ASnapshotFile) = '' then
    raise Exception.Create('TSnapshotDatabaseCompare: ASnapshotFile nao informado.');
  if AConnTarget = nil then
    raise Exception.Create('TSnapshotDatabaseCompare: AConnTarget nao pode ser nil.');

  FConnTarget := AConnTarget;
  FConnTarget.Connect;
  if not FConnTarget.IsConnected then
    raise Exception.Create('Nao foi possivel conectar ao banco de dados Target');

  // The DDL dialect comes from the TARGET connection's driver - the script
  // is meant to run there. See the unit header comment for the cross-dialect
  // limitation this implies when the snapshot was produced by a different
  // dialect than AConnTarget's.
  inherited Create(AConnTarget.GetDriver);
  FModelForDatabase := False;
  // Metadata from the snapshot file (the "master")
  FMetadataMaster := TMetadataSnapshotFactory.Create(Self, ASnapshotFile);
  // Metadata from the live target database
  FMetadataTarget := TMetadataDBFactory.Create(Self, FConnTarget);
end;

destructor TSnapshotDatabaseCompare.Destroy;
begin
  FMetadataTarget.Free;
  FMetadataMaster.Free;
  inherited;
end;

procedure TSnapshotDatabaseCompare.ExecuteDDLCommands;
var
  LCommand: TDDLCommand;
  LCommandText: String;
begin
  inherited;
  if FCommandsAutoExecute then
    FConnTarget.StartTransaction;
  try
    for LCommand in FDDLCommands do
    begin
      LCommandText := LCommand.BuildCommand(FGeneratorCommand);
      if Length(LCommandText) > 0 then
        if FCommandsAutoExecute then
          FConnTarget.ExecuteScript(LCommandText);
    end;
    if FConnTarget.InTransaction then
      FConnTarget.Commit;
  except
    on E: Exception do
    begin
      if FConnTarget.InTransaction then
        FConnTarget.Rollback;
      raise Exception.Create('MetaDbDiff Command : [' + LCommand.Warning + '] - ' + E.Message + sLineBreak +
                             'Script : "' + LCommandText + '"');
    end;
  end;
  // Deliberately no Disconnect here - AConnTarget belongs to the caller.
  // See the unit header comment for the full rationale.
end;

procedure TSnapshotDatabaseCompare.ExtractDatabase;
begin
  inherited;
  // Extracts all metadata from the snapshot file (master)
  FMetadataMaster.ExtractMetadata(FCatalogMaster);
  // Extracts all metadata from the live target database
  FMetadataTarget.ExtractMetadata(FCatalogTarget);
end;

end.
