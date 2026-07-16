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

  One-shot convenience exporters on top of MetaDbDiff.Metadata.Snapshot.pas:
  extract metadata (from a live database, or from the decorated model
  classes) and save it straight to a snapshot file, in a single call.

  WARNING - Core/Drivers dependency direction: TMetadataExporter.ExportModel
  depends (via MetaDbDiff.Metadata.Model.Factory.pas) on
  MetaDbDiff.Metadata.Model.pas from Source\Drivers (for TModelMetadata) -
  unlike MetaDbDiff.Metadata.Snapshot.pas itself (kept dependency-free of
  Source\Drivers on purpose) and unlike TMetadataExporter.ExportDatabase
  (which only needs MetaDbDiff.Metadata.DB.Factory.pas, a Core unit whose
  TMetadataRegister is populated by driver units through their own
  `initialization` sections at RUNTIME, not through a compile-time Core->
  Drivers link). This split - ExportModel pulled into its OWN unit instead of
  living inside MetaDbDiff.Metadata.Snapshot.pas - is exactly why: it lets
  code that only needs ExportDatabase (or ToJson/FromJson/SaveToFile/
  LoadFromFile in general) depend on MetaDbDiff.Metadata.Snapshot.pas alone,
  without dragging Source\Drivers in. See the identical warning already on
  MetaDbDiff.Metadata.Model.Factory.pas and MetaDbDiff.Database.ModelCompare.pas
  for the established precedent. DO NOT add this unit to
  Components\Packages\Delphi\MetaDbDiffCore.dpk's "contains" clause without
  also bringing MetaDbDiff.Metadata.Model.pas (and whatever it needs) into
  that package - MetaDbDiffCore.dpk currently contains NO Source\Drivers
  units at all.
}

unit MetaDbDiff.Metadata.Snapshot.Export;

interface

uses
  SysUtils,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract,
  MetaDbDiff.Database.Factory,
  MetaDbDiff.Metadata.Snapshot,
  MetaDbDiff.Metadata.DB.Factory,
  MetaDbDiff.Metadata.Model.Factory;

type
  /// <summary>
  ///   Extracts metadata (from a live database connection, or from the
  ///   decorated model classes registered for MetaDbDiff's own ORM-lite
  ///   mapping - see MetaDbDiff.Mapping.Attributes.pas) and saves it straight
  ///   to a snapshot file via TMetadataSnapshot.SaveToFile, in one call.
  /// </summary>
  TMetadataExporter = class
  public
    /// <summary>
    ///   Extracts the catalog from AConn's live database (via
    ///   TMetadataDBFactory, the same extractor MetaDbDiff.Database.Compare.pas
    ///   and MetaDbDiff.Database.SnapshotCompare.pas use for their target
    ///   side) and saves it to AFileName. AConn does not need to already be
    ///   connected - the underlying extractor connects/queries as needed
    ///   through the standard IDBConnection contract.
    /// </summary>
    class procedure ExportDatabase(AConn: IDBConnection; const AFileName: String;
      const ADescription: String = ''); static;

    /// <summary>
    ///   Extracts the catalog from the decorated model classes (via
    ///   TMetadataModelFactory - the same extractor
    ///   MetaDbDiff.Database.ModelCompare.pas uses for its master side) and
    ///   saves it to AFileName. AConn is required even though its data is
    ///   never touched: the model extractor still needs a driver to resolve
    ///   each column's dialect-specific TypeName (see
    ///   MetaDbDiff.Metadata.Extract.pas, GetFieldTypeDefinition) - an
    ///   unconnected "shell" connection is enough, exactly like the pattern
    ///   already used in Test.MetaDbDiff.Metadata.Model.pas
    ///   (TFactoryFireDAC.Create(FDConn, dnFirebird) over an unopened
    ///   TFDConnection).
    /// </summary>
    class procedure ExportModel(AConn: IDBConnection; const AFileName: String;
      const ADescription: String = ''); static;
  end;

implementation

type
  /// <summary>
  ///   Minimal concrete TDatabaseFactory descendant that exists ONLY to carry
  ///   ModelForDatabase = True for TMetadataModelFactory.ExtractMetadata (it
  ///   reads FOwner.ModelForDatabase - see
  ///   MetaDbDiff.Metadata.Model.Factory.pas), the same way
  ///   MetaDbDiff.Database.ModelCompare.pas's TModelDatabaseCompare does when
  ///   comparing decorated classes against a live database. It never builds
  ///   or executes an actual diff - ExecuteDDLCommands/ExtractDatabase are
  ///   no-ops, deliberately unreachable from ExportModel below (which calls
  ///   TMetadataModelFactory.ExtractMetadata directly, not BuildDatabase).
  /// </summary>
  TSnapshotModelOwner = class(TDatabaseFactory)
  public
    constructor Create(ADriverName: TDriverName); override;
  protected
    procedure ExecuteDDLCommands; override;
    procedure ExtractDatabase; override;
  end;

{ TSnapshotModelOwner }

constructor TSnapshotModelOwner.Create(ADriverName: TDriverName);
begin
  inherited Create(ADriverName);
  FModelForDatabase := True;
end;

procedure TSnapshotModelOwner.ExecuteDDLCommands;
begin
  // No-op: this owner only exists to carry ModelForDatabase for
  // TMetadataModelFactory.ExtractMetadata - see the class comment above.
end;

procedure TSnapshotModelOwner.ExtractDatabase;
begin
  // No-op (see above).
end;

{ TMetadataExporter }

class procedure TMetadataExporter.ExportDatabase(AConn: IDBConnection; const AFileName: String;
  const ADescription: String);
var
  LFactory: TMetadataDBFactory;
  LCatalog: TCatalogMetadataMIK;
begin
  if AConn = nil then
    raise Exception.Create('TMetadataExporter.ExportDatabase: AConn nao pode ser nil.');

  LCatalog := TCatalogMetadataMIK.Create;
  try
    LFactory := TMetadataDBFactory.Create(nil, AConn);
    try
      LFactory.ExtractMetadata(LCatalog);
    finally
      LFactory.Free;
    end;
    TMetadataSnapshot.SaveToFile(LCatalog, AFileName, AConn.GetDriver, ADescription);
  finally
    LCatalog.Free;
  end;
end;

class procedure TMetadataExporter.ExportModel(AConn: IDBConnection; const AFileName: String;
  const ADescription: String);
var
  LOwner: TSnapshotModelOwner;
  LFactory: TMetadataModelFactory;
  LCatalog: TCatalogMetadataMIK;
begin
  if AConn = nil then
    raise Exception.Create('TMetadataExporter.ExportModel: AConn nao pode ser nil ' +
      '(necessaria para resolver o TypeName de cada coluna pelo dialeto do driver).');

  LCatalog := TCatalogMetadataMIK.Create;
  try
    LOwner := TSnapshotModelOwner.Create(AConn.GetDriver);
    try
      LFactory := TMetadataModelFactory.Create(LOwner);
      try
        LFactory.ModelMetadata.Connection := AConn;
        LFactory.ExtractMetadata(LCatalog);
      finally
        LFactory.Free;
      end;
    finally
      LOwner.Free;
    end;
    TMetadataSnapshot.SaveToFile(LCatalog, AFileName, AConn.GetDriver, ADescription);
  finally
    LCatalog.Free;
  end;
end;

end.
