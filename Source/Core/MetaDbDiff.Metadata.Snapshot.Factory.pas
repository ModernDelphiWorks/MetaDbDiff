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

  Same "metadata factory" shape as MetaDbDiff.Metadata.DB.Factory.pas
  (TMetadataDBFactory, extracts FROM a live database connection) and
  MetaDbDiff.Metadata.Model.Factory.pas (TMetadataModelFactory, extracts FROM
  the decorated model classes) - this one extracts FROM a metadata snapshot
  FILE instead (MetaDbDiff.Metadata.Snapshot.pas). It is the piece
  MetaDbDiff.Database.SnapshotCompare.pas plugs into TDatabaseFactory as the
  MASTER-side metadata source.
}

unit MetaDbDiff.Metadata.Snapshot.Factory;

interface

uses
  Classes,
  SysUtils,
  System.JSON,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Snapshot,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract;

type
  TMetadataSnapshotAbstract = class abstract
  protected
    FOwner: TDatabaseAbstract;
    FSnapshotFile: String;
  public
    constructor Create(AOwner: TDatabaseAbstract; const ASnapshotFile: String); virtual;
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); virtual; abstract;
    property SnapshotFile: String read FSnapshotFile;
  end;

  TMetadataSnapshotFactory = class(TMetadataSnapshotAbstract)
  public
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); override;
  end;

implementation

{ TMetadataSnapshotAbstract }

constructor TMetadataSnapshotAbstract.Create(AOwner: TDatabaseAbstract; const ASnapshotFile: String);
begin
  FOwner := AOwner;
  FSnapshotFile := ASnapshotFile;
end;

{ TMetadataSnapshotFactory }

procedure TMetadataSnapshotFactory.ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK);
var
  LStream: TFileStream;
  LBytes: TBytes;
  LText: String;
  LJsonValue: TJSONValue;
  LDriverName: TDriverName;
  LDescription, LGeneratedAt: String;
  LFormatVersion: Integer;
begin
  if ACatalogMetadata = nil then
    raise Exception.Create('MetaDbDiff.Metadata.Snapshot.Factory: antes de executar a ' +
      'extracao do snapshot, atribua um catalogo (TCatalogMetadataMIK) ja instanciado.');
  if Trim(FSnapshotFile) = '' then
    raise Exception.Create('MetaDbDiff.Metadata.Snapshot.Factory: SnapshotFile nao informado.');
  if not FileExists(FSnapshotFile) then
    raise EMetadataSnapshotError.CreateFmt(
      'MetaDbDiff snapshot: arquivo nao encontrado: "%s".', [FSnapshotFile]);

  LStream := TFileStream.Create(FSnapshotFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(LBytes, LStream.Size);
    if Length(LBytes) > 0 then
      LStream.ReadBuffer(LBytes[0], Length(LBytes));
  finally
    LStream.Free;
  end;
  LText := TEncoding.UTF8.GetString(LBytes);

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

  try
    // Populates ACatalogMetadata (the catalog owned/created by
    // TDatabaseFactory.BuildDatabase, exactly like TMetadataDBFactory and
    // TMetadataModelFactory do) directly IN PLACE - TMetadataSnapshot.LoadInto
    // clears its Tables/Sequences/Views before repopulating them, so this is
    // safe even if the catalog is reused across calls.
    TMetadataSnapshot.LoadInto(TJSONObject(LJsonValue), ACatalogMetadata,
      LDriverName, LDescription, LGeneratedAt, LFormatVersion);
  finally
    LJsonValue.Free;
  end;
end;

end.
