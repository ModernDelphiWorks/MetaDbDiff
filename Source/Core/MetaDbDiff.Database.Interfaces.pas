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
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.Compare.Options;

type
  IDatabaseCompare = interface
    ['{039B968F-B99A-40CF-B4FA-FEEC4F9856FA}']
  {$REGION 'Property Getters & Setters'}
    function GetCommandsAutoExecute: Boolean;
    procedure SetCommandsAutoExecute(const Value: Boolean);
    function GetComparerFieldPosition:Boolean;
    procedure SetComparerFieldPosition(const Value: Boolean = False);
    function GetPolicy: TComparePolicy;
    procedure SetPolicy(const Value: TComparePolicy);
    function GetSuppressedCommands: TArray<String>;
  {$ENDREGION}
    procedure BuildDatabase;
    procedure ExecuteCommands;
    function GetCommandList: TArray<TDDLCommand>;
    function GeneratorCommand: IDDLGeneratorCommand;
    /// <summary>
    ///   Gera o script consolidado da migra��o (DryRun do executor) sem tocar
    ///   no banco: fases anotadas como coment�rio SQL, ordem topol�gica quando
    ///   UseSequencer est� ligado. N�o abre transa��o nem executa nada.
    /// </summary>
    function GenerateScript: String;
    /// <summary>
    ///   Grava o script consolidado (mesmo conte�do de GenerateScript) em
    ///   AFileName como UTF-8 (ScriptOut do executor). N�o toca no banco.
    /// </summary>
    procedure SaveScriptToFile(const AFileName: String);
    property CommandsAutoExecute: Boolean read GetCommandsAutoExecute write SetCommandsAutoExecute;
    property ComparerFieldPosition: Boolean read GetComparerFieldPosition write SetComparerFieldPosition;
    /// <summary>
    ///   Policy que limita quais opera��es DDL o diff pode gerar/executar.
    ///   Default: TComparePolicy.FullProfile (comportamento hist�rico).
    /// </summary>
    property Policy: TComparePolicy read GetPolicy write SetPolicy;
    /// <summary>
    ///   Relat�rio de auditoria: descri��o de cada opera��o que o diff QUERIA
    ///   emitir mas foi bloqueada pela policy vigente.
    /// </summary>
    property SuppressedCommands: TArray<String> read GetSuppressedCommands;
  end;

implementation

end.

