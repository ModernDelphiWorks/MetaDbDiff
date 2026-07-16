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

unit MetaDbDiff.Database.Interfaces;

interface

uses
  Classes,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Commands;

type
  IDatabaseCompare = interface
    ['{039B968F-B99A-40CF-B4FA-FEEC4F9856FA}']
  {$REGION 'Property Getters & Setters'}
    function GetCommandsAutoExecute: Boolean;
    procedure SetCommandsAutoExecute(const Value: Boolean);
    function GetComparerFieldPosition:Boolean;
    procedure SetComparerFieldPosition(const Value: Boolean = False);
  {$ENDREGION}
    procedure BuildDatabase;
    procedure ExecuteCommands;
    function GetCommandList: TArray<TDDLCommand>;
    function GeneratorCommand: IDDLGeneratorCommand;
    property CommandsAutoExecute: Boolean read GetCommandsAutoExecute write SetCommandsAutoExecute;
    property ComparerFieldPosition: Boolean read GetComparerFieldPosition write SetComparerFieldPosition;
  end;

implementation

end.

