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

  WARNING - Core/Drivers dependency direction: even though this unit lives in
  Source\Core, it (and MetaDbDiff.Database.ModelCompare.pas, which uses it)
  depends on MetaDbDiff.Metadata.Model.pas from Source\Drivers (for
  TModelMetadata) - unlike the rest of Source\Core, which only reaches driver
  code indirectly through the TMetadataRegister/TSQLDriverRegister registries.
  DO NOT add this unit (or MetaDbDiff.Database.ModelCompare.pas) to
  Components\Packages\Delphi\MetaDbDiffCore.dpk's "contains" clause without
  also bringing MetaDbDiff.Metadata.Model.pas (and whatever it needs) into
  that package - MetaDbDiffCore.dpk currently contains NO Source\Drivers
  units at all, so doing so naively will fail to link.
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
  // Schema-aware compare (FRENTE 14): o modelo (classes decoradas) nao carrega
  // schema proprio - GetModelMetadata sempre grava Schema=''. Quando o compare
  // esta configurado com um schema, carimba-o aqui para que o DDL gerado a
  // partir do modelo (master) saia qualificado no dialeto do target. Default ''
  // preserva o comportamento historico (sem qualificacao).
  if (FOwner <> nil) and (FOwner.Schema <> '') then
    ACatalogMetadata.Schema := FOwner.Schema;
end;

end.
