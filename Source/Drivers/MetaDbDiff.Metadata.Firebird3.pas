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

unit MetaDbDiff.Metadata.Firebird3;

interface

uses
  MetaDbDiff.Metadata.Firebird,
  MetaDbDiff.Metadata.Register,
  MetaDbDiff.Metadata.Extract,
  DataEngine.Factory.Interfaces;

type
  TCatalogMetadataFirebird3 = class(TCatalogMetadataFirebird)
  end;

implementation

initialization
  TMetadataRegister.GetInstance.RegisterMetadata(dnFirebird3, TCatalogMetadataFirebird3.Create);

end.
