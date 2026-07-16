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

unit MetaDbDiff.DDL.Generator.Interbase;

interface

uses
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.DDL.Generator.Firebird;

type
  TDDLSQLGeneratorInterbase = class(TDDLSQLGeneratorFirebird)
  public
    // FRENTE 15: Interbase anuncia DOMAINS (herdado do Firebird) mas NAO
    // Procedures (extracao nao implementada nesta frente - matriz de suporte).
    function GetSupportedFeatures: TSupportedFeatures; override;
  end;

implementation

function TDDLSQLGeneratorInterbase.GetSupportedFeatures: TSupportedFeatures;
begin
  Result := inherited GetSupportedFeatures - [TSupportedFeature.Procedures];
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnInterbase, TDDLSQLGeneratorInterbase.Create);

end.
