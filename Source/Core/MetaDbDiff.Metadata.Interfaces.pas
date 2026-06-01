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

unit MetaDbDiff.Metadata.Interfaces;

interface

uses
  DataEngine.Factory.Interfaces,
  MetaDbDiff.Database.Mapping;

type
  IMetadata = interface
    ['{A172B920-E18C-45FE-8038-8690C4FBFFEE}']
  {$REGION 'Property Getters & Setters'}
    function GetConnection: IDBConnection;
    procedure SetConnection(const Value: IDBConnection);
    function GetCatalogMetadata: TCatalogMetadataMIK;
    procedure SetCatalogMetadata(const Value: TCatalogMetadataMIK);
  {$ENDREGION}
    property Connection: IDBConnection read GetConnection write SetConnection;
    property CatalogMetadata: TCatalogMetadataMIK read GetCatalogMetadata write SetCatalogMetadata;
  end;

  IModelMetadata = interface(IMetadata)
    ['{C3113546-1187-400C-9CAB-3D2AEA9B2640}']
  end;

  IDatabaseMetadata = interface(IMetadata)
    ['{CFBB96D4-8191-499B-BD68-CCFC22839DB4}']
  {$REGION 'Property Getters & Setters'}
  {$ENDREGION}
    procedure GetCatalogs;
    procedure GetSchemas;
    procedure GetTables;
  end;

implementation

end.
