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

{ @abstract(ORMBr Framework.)
  @created(20 Jul 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.
}

unit MetaDbDiff.Metadata.DB.Factory;

interface

uses
  SysUtils,
  Rtti,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Register,
  MetaDbDiff.Metadata.Extract,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Abstract;
type
  TMetadataDBAbstract = class abstract
  protected
    FOwner: TDatabaseAbstract;
    FConnection: IDBConnection;
    FDatabaseMetadata: TCatalogMetadataAbstract;
    procedure ExtractCatalogs; virtual; abstract;
    procedure ExtractSchemas; virtual; abstract;
    procedure ExtractTables; virtual; abstract;
  public
    constructor Create(AOwner: TDatabaseAbstract; AConnection: IDBConnection); virtual;
    destructor Destroy; override;
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); virtual; abstract;
    property DatabaseMetadata: TCatalogMetadataAbstract read FDatabaseMetadata;
  end;

  TMetadataDBFactory = class(TMetadataDBAbstract)
  public
    procedure ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK); override;
  end;

implementation

{ TMetadataDBAbstract }

constructor TMetadataDBAbstract.Create(AOwner: TDatabaseAbstract;
  AConnection: IDBConnection);
begin
  FOwner := AOwner;
  FConnection := AConnection;
end;

destructor TMetadataDBAbstract.Destroy;
begin
  inherited;
end;

{ TMetadataFactory }

procedure TMetadataDBFactory.ExtractMetadata(ACatalogMetadata: TCatalogMetadataMIK);
begin
  inherited;
  if ACatalogMetadata = nil then
    raise Exception.Create('Antes de executar a extra��o do metadata, atribua a propriedade o catalogue a set preenchido em "DatabaseMetadata.CatalogMetadata"');

  // Extrair database metadata
  FDatabaseMetadata := TMetadataRegister.GetInstance.GetMetadata(FConnection.GetDriver);
  FDatabaseMetadata.Connection := FConnection;
  FDatabaseMetadata.CatalogMetadata := ACatalogMetadata;
  // Schema-aware compare (FRENTE 14): propaga o schema configurado no compare
  // (FOwner) para o extractor. O registro devolve uma instancia SINGLETON, entao
  // sempre reatribuimos (inclusive '' quando nao ha owner) para nunca vazar o
  // schema de uma extracao anterior.
  if FOwner <> nil then
  begin
    FDatabaseMetadata.ModelForDatabase := FOwner.ModelForDatabase;
    FDatabaseMetadata.Schema := FOwner.Schema;
  end
  else
    FDatabaseMetadata.Schema := '';
  try
    FDatabaseMetadata.GetDatabaseMetadata;
  finally
    FDatabaseMetadata.CatalogMetadata := nil;
    FDatabaseMetadata.Connection := nil;
    FDatabaseMetadata.Schema := '';
  end;
end;

end.
