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
  @created(12 Out 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.
}

unit MetaDbDiff.DDL.Generator.Firebird3;

interface

uses
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.DDL.Generator.Firebird;

type
  TDDLSQLGeneratorFirebird3 = class(TDDLSQLGeneratorFirebird)
  end;

implementation

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnFirebird3, TDDLSQLGeneratorFirebird3.Create);

end.
