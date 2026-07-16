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
  MetaDbDiff.DDL.AlterStrategy,
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
    function GetCompareSequenceInitialValue: Boolean;
    procedure SetCompareSequenceInitialValue(const Value: Boolean);
    function GetPolicy: TComparePolicy;
    procedure SetPolicy(const Value: TComparePolicy);
    function GetSuppressedCommands: TArray<String>;
    function GetUseSequencer: Boolean;
    procedure SetUseSequencer(const Value: Boolean);
    function GetAlterColumnStrategy: TAlterColumnStrategy;
    procedure SetAlterColumnStrategy(const Value: TAlterColumnStrategy);
    function GetErrorPolicy: TMigrationErrorPolicy;
    procedure SetErrorPolicy(const Value: TMigrationErrorPolicy);
    function GetRaiseOnError: Boolean;
    procedure SetRaiseOnError(const Value: Boolean);
    function GetLastMigrationReport: TMigrationReport;
    function GetSchema: String;
    procedure SetSchema(const Value: String);
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
    ///   Opt-in (default False): compara tambem o InitialValue das sequences que
    ///   existem nos dois lados. Desligado por padrao PORQUE o valor corrente de
    ///   uma sequence e um ALVO MOVEL em producao (avanca a cada uso): compara-lo
    ///   geraria um ALTER SEQUENCE ... RESTART eterno (falso-positivo) toda vez que
    ///   o diff roda contra um banco vivo. Por default so o Increment (o "passo",
    ///   que e estavel) e comparado.
    /// </summary>
    property CompareSequenceInitialValue: Boolean read GetCompareSequenceInitialValue write SetCompareSequenceInitialValue;
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
    ///   Estrat�gia de ALTER COLUMN (FRENTE 11): acsInPlace (default, hist�rico)
    ///   ou acsRebuildWhenRequired (rebuild seguro com preserva��o de dados).
    /// </summary>
    property AlterColumnStrategy: TAlterColumnStrategy read GetAlterColumnStrategy write SetAlterColumnStrategy;
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
    /// <summary>
    ///   Schema-aware compare (single-schema, configuravel). Default '' preserva
    ///   o comportamento HISTORICO POR DIALETO:
    ///     - PostgreSQL: o catalogo/DDL saem qualificados com 'public' (como
    ///       sempre foi - o codigo historico gravava Schema:='public'); a
    ///       extracao NAO filtra por schema no default.
    ///     - MSSQL: sem qualificacao (DDL cru), extracao sem filtro.
    ///     - demais (Firebird/SQLite/MySQL): sem schema (ignoram a property).
    ///   Com um valor nao-vazio (ex.: 'vendas'), os extractors PostgreSQL/MSSQL
    ///   restringem a extracao a esse schema e os generators qualificam os nomes
    ///   de tabela ("schema"."tabela" / [schema].[tabela]).
    ///
    ///   O nome e validado como identificador SQL (ver
    ///   TCatalogMetadataAbstract.ValidateSchemaName): nomes com aspas, espacos,
    ///   ";" etc. sao rejeitados ja na atribuicao.
    ///
    ///   CAVEAT case-sensitivity cross-dialeto: o nome e usado VERBATIM. No
    ///   PostgreSQL identificadores nao-citados sao dobrados para minusculas pelo
    ///   servidor, entao um schema fisico 'vendas' NAO casa com Schema:='Vendas'
    ///   (o filtro "table_schema = 'Vendas'" vem vazio e o DDL geraria
    ///   "Vendas".tabela inexistente) - use o nome exatamente como gravado no
    ///   catalogo do banco. O SQL Server e tipicamente case-insensitive (depende
    ///   do collation), tolerando divergencia de caixa.
    ///
    ///   Ao migrar entre schemas distintos (master X vs target Y), o DDL usa
    ///   sempre o schema do TARGET.
    /// </summary>
    property Schema: String read GetSchema write SetSchema;
  end;

implementation

end.

