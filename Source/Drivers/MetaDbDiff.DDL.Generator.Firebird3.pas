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
  public
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
  end;

implementation

function TDDLSQLGeneratorFirebird3.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  // Firebird 3+ torna as tabelas de sistema READ-ONLY: o UPDATE RDB$TRIGGERS
  // herdado do gerador 2.5 falharia em tempo de execucao. Desligar/ligar todas
  // as triggers exigiria "ALTER TRIGGER <nome> ACTIVE/INACTIVE" por trigger, o
  // que esta assinatura (apenas um Boolean) nao permite enumerar. Retorna vazio
  // -- o pipeline descarta comandos vazios (MetaDbDiff.Database.Compare exige
  // Length(LCommand) > 0), preservando o comportamento sem gerar SQL invalido.
  Result := '';
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnFirebird3, TDDLSQLGeneratorFirebird3.Create);

end.
