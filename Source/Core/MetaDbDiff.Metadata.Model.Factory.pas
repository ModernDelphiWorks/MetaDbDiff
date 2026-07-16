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

  Native port of Janus.Metadata.Classe.Factory.pas (Janus\Source\Metadata),
  bringing the "decorated-class metadata factory" half of the model-vs-database
  comparison INTO MetaDbDiff, so the orchestration no longer depends on Janus.

  Deliberate differences from the Janus original:
    - Unit/class names changed to avoid any collision with the Janus units and
      to match MetaDbDiff's own vocabulary ("Model" instead of "Classe"):
        Janus.Metadata.Classe.Factory   -> MetaDbDiff.Metadata.Model.Factory
        TMetadataClasseAbstract         -> TMetadataModelAbstract
        TMetadataClasseFactory          -> TMetadataModelFactory
    - Everything else (fields, constructor/destructor logic, ExtractMetadata
      behaviour) is a faithful port of Janus.Metadata.Classe.Factory.pas.
}

unit MetaDbDiff.Metadata.Model.Factory;

interface

uses
  SysUtils,
  Rtti,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Model,
  MetaDbDiff.Metadata.Extract,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract;

type
  TMetadataModelAbstract = class abstract
  protected
    FOwner: TDatabaseAbstract;
    FModelMetadata: TModelMetadataAbstract;
  public
    constructor Create(AOwner: TDatabaseAbstract); virtual;
    destructor Destroy; override;
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); virtual; abstract;
    property ModelMetadata: TModelMetadataAbstract read FModelMetadata;
  end;

  TMetadataModelFactory = class(TMetadataModelAbstract)
  public
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); override;
  end;

implementation

{ TMetadataModelAbstract }

constructor TMetadataModelAbstract.Create(AOwner: TDatabaseAbstract);
begin
  FOwner := AOwner;
  FModelMetadata := TModelMetadata.Create;
end;

destructor TMetadataModelAbstract.Destroy;
begin
  FModelMetadata.Free;
  inherited;
end;

{ TMetadataModelFactory }

procedure TMetadataModelFactory.ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK);
begin
  inherited;
  if ACatalogMetadata = nil then
    raise Exception.Create('Before extracting the metadata, assign the catalog to be filled in "ModelMetadata.CatalogMetadata"');

  FModelMetadata.CatalogMetadata := ACatalogMetadata;
  FModelMetadata.ModelForDatabase := FOwner.ModelForDatabase;
  FModelMetadata.GetModelMetadata;
end;

end.
