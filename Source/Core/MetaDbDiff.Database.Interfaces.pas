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
  MetaDbDiff.Migration.Executor,
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
    function GetUseSequencer: Boolean;
    procedure SetUseSequencer(const Value: Boolean);
    function GetErrorPolicy: TMigrationErrorPolicy;
    procedure SetErrorPolicy(const Value: TMigrationErrorPolicy);
    function GetRaiseOnError: Boolean;
    procedure SetRaiseOnError(const Value: Boolean);
    function GetLastMigrationReport: TMigrationReport;
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
    /// <summary>
    ///   Liga (default) o sequenciamento topol�gico por fase na gera��o. Quando
    ///   False, GetCommandList preserva a ordem hist�rica de gera��o.
    /// </summary>
    property UseSequencer: Boolean read GetUseSequencer write SetUseSequencer;
    /// <summary>
    ///   Pol�tica de erro do executor de migra��o: StopOnError (default) ou
    ///   ContinueOnError.
    /// </summary>
    property ErrorPolicy: TMigrationErrorPolicy read GetErrorPolicy write SetErrorPolicy;
    /// <summary>
    ///   Fail-loud (default True): re-levanta exce��o quando a execu��o registra
    ///   falha/rollback. False deixa o resultado apenas em LastMigrationReport.
    /// </summary>
    property RaiseOnError: Boolean read GetRaiseOnError write SetRaiseOnError;
    /// <summary>
    ///   Resultado detalhado da �ltima execu��o via executor (fases, por-comando,
    ///   rollback). Permite ao consumidor via interface inspecionar um banco
    ///   meio-migrado mesmo com RaiseOnError=False.
    /// </summary>
    property LastMigrationReport: TMigrationReport read GetLastMigrationReport;
  end;

implementation

end.

