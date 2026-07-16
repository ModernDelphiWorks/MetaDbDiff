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

  Native port of Janus.ModelDB.Compare.pas (Janus\Source\Metadata), bringing
  the "decorated classes vs database" orchestrator INTO MetaDbDiff. Until now
  this class lived in Janus and depended on MetaDbDiff, which is a conceptually
  inverted dependency for a class that only compares MetaDbDiff catalogs; it
  now lives where the comparison logic (TDatabaseFactory) already lives.

  Deliberate differences from the Janus original (Janus.ModelDB.Compare.pas):
    - Class/unit renamed to avoid colliding with the Janus original, which is
      left untouched (a Janus-side PR pointing Janus.ModelDB.Compare at this
      unit is a separate, later change - see the frente-3 mission notes):
        Janus.ModelDB.Compare -> MetaDbDiff.Database.ModelCompare
        TModelDbCompare       -> TModelDatabaseCompare
    - Single connection field renamed FConnMaster -> FConnection: in both the
      original and this port there is only ONE physical connection (the
      target database's), reused both as the database-side connection and as
      the connection handed to the model-side metadata extractor
      (FMetadataMaster.ModelMetadata.Connection) to resolve driver-specific
      type mapping. "FConnMaster" was misleading (nothing about it is the
      "master" side of the comparison - the decorated classes are the master).
    - Connection lifecycle: this class connects FConnection in the constructor
      (like the original) but NEVER calls Disconnect on it, anywhere - not in
      ExecuteDDLCommands, not in the destructor. The connection is owned by
      the CALLER, who is responsible for connecting/disconnecting it as it see
      fits (e.g. reusing it for a later ExecuteCommands call, or for unrelated
      work after the comparison). This mirrors the Janus original, which
      likewise never disconnects FConnMaster anywhere in Janus.ModelDB.Compare.pas
      - the difference here is that the non-disconnection is now a documented,
      deliberate design decision instead of an implicit fact one has to read
      the whole unit to notice. Contrast with the sibling
      MetaDbDiff.Database.Compare.TDatabaseCompare (DB vs DB), whose
      ExecuteDDLCommands DOES disconnect both connections in a finally block -
      that class is out of scope for this change (frente F2) and is only
      referenced here for context.
    - ExecuteDDLCommands keeps the original Janus pattern of executing each
      generated command immediately via ExecuteScript inside a single
      transaction (StartTransaction/Commit/Rollback), NOT the AddScript +
      ExecuteScripts batching pattern used by TDatabaseCompare.
    - Built against the post-frente-1 TDatabaseFactory.BuildDatabase, which
      now frees the previous catalogs, extracts, generates DDL commands (and
      builds their command text) unconditionally, and only executes them when
      CommandsAutoExecute is True. No change was needed here since
      ExtractDatabase/ExecuteDDLCommands are still the two extension points
      BuildDatabase calls into.

  WARNING - Core/Drivers dependency direction: even though this unit lives in
  Source\Core, it depends (via MetaDbDiff.Metadata.Model.Factory.pas) on
  MetaDbDiff.Metadata.Model.pas from Source\Drivers (for TModelMetadata) -
  unlike the rest of Source\Core, which only reaches driver code indirectly
  through the TMetadataRegister/TSQLDriverRegister registries. DO NOT add this
  unit (or MetaDbDiff.Metadata.Model.Factory.pas) to
  Components\Packages\Delphi\MetaDbDiffCore.dpk's "contains" clause without
  also bringing MetaDbDiff.Metadata.Model.pas (and whatever it needs) into
  that package - MetaDbDiffCore.dpk currently contains NO Source\Drivers
  units at all, so doing so naively will fail to link.
}

unit MetaDbDiff.Database.ModelCompare;

interface

uses
  SysUtils,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Model.Factory,
  MetaDbDiff.Metadata.DB.Factory,
  MetaDbDiff.Database.Factory;

type
  TModelDatabaseCompare = class(TDatabaseFactory)
  protected
    // Single physical connection: owned by the caller, never disconnected by
    // this class (see the unit header comment above).
    FConnection: IDBConnection;
    FMetadataMaster: TMetadataModelAbstract;
    FMetadataTarget: TMetadataDBAbstract;
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(AConnection: IDBConnection); overload;
    destructor Destroy; override;
  end;

implementation

uses
  MetaDbDiff.DDL.Commands;

{ TModelDatabaseCompare }

constructor TModelDatabaseCompare.Create(AConnection: IDBConnection);
begin
  FConnection := AConnection;
  FConnection.Connect;
  if not FConnection.IsConnected then
    raise Exception.Create('Was not possible to connect to the Target database');

  inherited Create(AConnection.GetDriver);
  FModelForDatabase := True;
  // Metadata from the decorated classes (the "model")
  FMetadataMaster := TMetadataModelFactory.Create(Self);
  FMetadataMaster.ModelMetadata.Connection := AConnection;
  // Metadata from the accessed database (the "target")
  FMetadataTarget := TMetadataDBFactory.Create(Self, FConnection);
end;

destructor TModelDatabaseCompare.Destroy;
begin
  FMetadataTarget.Free;
  FMetadataMaster.Free;
  inherited;
end;

procedure TModelDatabaseCompare.ExecuteDDLCommands;
var
  LCommand: TDDLCommand;
  LCommandText: String;
begin
  inherited;
  if FCommandsAutoExecute then
    FConnection.StartTransaction;
  try
    for LCommand in FDDLCommands do
    begin
      LCommandText := LCommand.BuildCommand(FGeneratorCommand);
      if Length(LCommandText) > 0 then
        if FCommandsAutoExecute then
          FConnection.ExecuteScript(LCommandText);
    end;
    if FConnection.InTransaction then
      FConnection.Commit;
  except
    on E: Exception do
    begin
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise Exception.Create('MetaDbDiff Command : [' + LCommand.Warning + '] - ' + E.Message + sLineBreak +
                             'Script : "' + LCommandText + '"');
    end;
  end;
  // Deliberately no Disconnect here - the connection belongs to the caller.
  // See the unit header comment for the full rationale.
end;

procedure TModelDatabaseCompare.ExtractDatabase;
begin
  inherited;
  // Extracts all metadata based on the existing decorated classes
  FMetadataMaster.ExtractMetadata(FCatalogMaster);
  // Extracts all metadata based on the accessed database
  FMetadataTarget.ExtractMetadata(FCatalogTarget);
end;

end.
