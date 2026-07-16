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

{ @abstract(MetaDbDiff Framework.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  Policy que limita quais opera��es DDL o diff pode gerar/executar. Cada muta��o
  emitida pelo TDatabaseFactory passa por um "gate" que consulta esta policy;
  opera��es suprimidas s�o registradas no relat�rio de auditoria da compara��o.

  IMPORTANTE (uso correto): TComparePolicy � um RECORD. Para trocar a policy,
  atribua o RECORD INTEIRO � property (`X.Policy := TComparePolicy.JanusOrmProfile`
  ou monte um TComparePolicy local e atribua). O conjunto Operations � somente
  leitura de prop�sito: `X.Policy.Operations := [...]` mutaria apenas o
  tempor�rio devolvido pelo getter (no-op silencioso) e por isso � imposs�vel.

  Seguran�a (fail-closed): a classifica��o comando->opera��o usa uma allowlist
  expl�cita das guardas; QUALQUER TDDLCommand desconhecido (n�o mapeado) �
  NEGADO por padr�o e registrado na auditoria, jamais tratado como guarda.
}

unit MetaDbDiff.Compare.Options;

interface

uses
  MetaDbDiff.DDL.Commands;

{$SCOPEDENUMS ON}

type
  /// <summary>
  ///   Enumera TODAS as muta��es de schema que o TDatabaseFactory emite atrav�s
  ///   dos m�todos Action*. Os comandos de guarda (EnableForeignKeys /
  ///   EnableTriggers) N�O s�o muta��es e por isso n�o t�m um valor aqui:
  ///   permanecem sempre permitidos, independentemente da policy.
  /// </summary>
  TDDLOperation = (
    CreateTable,
    DropTable,
    CreateColumn,
    AlterColumn,
    AlterColumnPosition,
    DropColumn,
    AlterDefaultValue,
    DropDefaultValue,
    CreatePrimaryKey,
    DropPrimaryKey,
    CreateForeignKey,
    DropForeignKey,
    CreateIndexe,
    DropIndexe,
    CreateCheck,
    AlterCheck,
    DropCheck,
    CreateView,
    DropView,
    CreateTrigger,
    DropTrigger,
    CreateSequence,
    DropSequence);

  TDDLOperations = set of TDDLOperation;

{$SCOPEDENUMS OFF}
  /// <summary>
  ///   Classifica��o de um TDDLCommand quanto � policy:
  ///   ckMutation - muta��o de schema mapeada (sujeita � policy);
  ///   ckGuard    - comando de guarda (Enable*), sempre permitido;
  ///   ckUnknown  - classe n�o mapeada: NEGADA por fail-closed.
  /// </summary>
  TDDLCommandKind = (ckMutation, ckGuard, ckUnknown);

const
  /// <summary> Conjunto com todas as opera��es de muta��o conhecidas. </summary>
  AllDDLOperations: TDDLOperations =
    [Low(TDDLOperation) .. High(TDDLOperation)];

type
  /// <summary>
  ///   Define o conjunto de opera��es DDL permitidas numa compara��o.
  ///   Perfis prontos: FullProfile (comportamento hist�rico, tudo liberado) e
  ///   JanusOrmProfile (embarcado no Janus ORM: s� cria��es aditivas, nunca
  ///   dropa nem altera coluna, para preservar os dados do usu�rio).
  /// </summary>
  TComparePolicy = record
  private
    FOperations: TDDLOperations;
  public
    /// <summary> Todas as opera��es permitidas (comportamento atual). </summary>
    class function FullProfile: TComparePolicy; static;
    /// <summary>
    ///   Perfil seguro para uso embarcado no Janus ORM: permite SOMENTE criar
    ///   tabela nova, criar coluna nova, criar PK e criar FK. Nunca dropa nada
    ///   nem altera coluna.
    /// </summary>
    class function JanusOrmProfile: TComparePolicy; static;
    /// <summary> Cria uma policy a partir de um conjunto arbitr�rio. </summary>
    class function Create(const AOperations: TDDLOperations): TComparePolicy; static;
    /// <summary> Indica se a opera��o informada � permitida por esta policy. </summary>
    function Allows(AOperation: TDDLOperation): Boolean; overload;
    /// <summary>
    ///   Indica se o comando DDL informado � permitido. Comandos de guarda
    ///   (Enable*) s�o sempre permitidos; comandos desconhecidos (n�o mapeados)
    ///   s�o NEGADOS por fail-closed.
    /// </summary>
    function Allows(ACommand: TDDLCommand): Boolean; overload;
    /// <summary>
    ///   Somente leitura de prop�sito (ver cabe�alho da unit): trocar a policy
    ///   se faz atribuindo o record inteiro � property, nunca mutando este set.
    /// </summary>
    property Operations: TDDLOperations read FOperations;
  end;

/// <summary>
///   Classifica a classe concreta de um TDDLCommand. Allowlist expl�cita das
///   guardas (Enable*); muta��es conhecidas devolvem ckMutation + AOperation;
///   QUALQUER outra classe devolve ckUnknown (fail-closed). O mapeamento vive
///   aqui para n�o precisar editar MetaDbDiff.DDL.Commands.pas.
/// </summary>
function ClassifyDDLCommand(ACommand: TDDLCommand;
  out AOperation: TDDLOperation): TDDLCommandKind;

implementation

function ClassifyDDLCommand(ACommand: TDDLCommand;
  out AOperation: TDDLOperation): TDDLCommandKind;
begin
  // 1) Allowlist EXPL�CITA das guardas (n�o s�o muta��es): sempre liberadas.
  if (ACommand is TDDLCommandEnableForeignKeys) or
     (ACommand is TDDLCommandEnableTriggers) then
    Exit(ckGuard);
  // 2) Muta��es conhecidas.
  if ACommand is TDDLCommandCreateTable then
    AOperation := TDDLOperation.CreateTable
  else if ACommand is TDDLCommandDropTable then
    AOperation := TDDLOperation.DropTable
  else if ACommand is TDDLCommandCreateColumn then
    AOperation := TDDLOperation.CreateColumn
  else if ACommand is TDDLCommandAlterColumnPosition then
    AOperation := TDDLOperation.AlterColumnPosition
  else if ACommand is TDDLCommandAlterColumn then
    AOperation := TDDLOperation.AlterColumn
  else if ACommand is TDDLCommandDropColumn then
    AOperation := TDDLOperation.DropColumn
  else if ACommand is TDDLCommandAlterDefaultValue then
    AOperation := TDDLOperation.AlterDefaultValue
  else if ACommand is TDDLCommandDropDefaultValue then
    AOperation := TDDLOperation.DropDefaultValue
  else if ACommand is TDDLCommandCreatePrimaryKey then
    AOperation := TDDLOperation.CreatePrimaryKey
  else if ACommand is TDDLCommandDropPrimaryKey then
    AOperation := TDDLOperation.DropPrimaryKey
  else if ACommand is TDDLCommandCreateForeignKey then
    AOperation := TDDLOperation.CreateForeignKey
  else if ACommand is TDDLCommandDropForeignKey then
    AOperation := TDDLOperation.DropForeignKey
  else if ACommand is TDDLCommandCreateIndexe then
    AOperation := TDDLOperation.CreateIndexe
  else if ACommand is TDDLCommandDropIndexe then
    AOperation := TDDLOperation.DropIndexe
  else if ACommand is TDDLCommandCreateCheck then
    AOperation := TDDLOperation.CreateCheck
  else if ACommand is TDDLCommandAlterCheck then
    AOperation := TDDLOperation.AlterCheck
  else if ACommand is TDDLCommandDropCheck then
    AOperation := TDDLOperation.DropCheck
  else if ACommand is TDDLCommandCreateView then
    AOperation := TDDLOperation.CreateView
  else if ACommand is TDDLCommandDropView then
    AOperation := TDDLOperation.DropView
  else if ACommand is TDDLCommandCreateTrigger then
    AOperation := TDDLOperation.CreateTrigger
  else if ACommand is TDDLCommandDropTrigger then
    AOperation := TDDLOperation.DropTrigger
  else if ACommand is TDDLCommandCreateSequence then
    AOperation := TDDLOperation.CreateSequence
  else if ACommand is TDDLCommandDropSequence then
    AOperation := TDDLOperation.DropSequence
  else
    // 3) Classe n�o mapeada: NEGA por fail-closed (jamais tratada como guarda).
    Exit(ckUnknown);
  Result := ckMutation;
end;

{ TComparePolicy }

class function TComparePolicy.Create(const AOperations: TDDLOperations): TComparePolicy;
begin
  Result.FOperations := AOperations;
end;

class function TComparePolicy.FullProfile: TComparePolicy;
begin
  Result.FOperations := AllDDLOperations;
end;

class function TComparePolicy.JanusOrmProfile: TComparePolicy;
begin
  // Somente cria��es aditivas seguras; nunca dropa nem altera.
  Result.FOperations := [
    TDDLOperation.CreateTable,
    TDDLOperation.CreateColumn,
    TDDLOperation.CreatePrimaryKey,
    TDDLOperation.CreateForeignKey];
end;

function TComparePolicy.Allows(AOperation: TDDLOperation): Boolean;
begin
  Result := AOperation in FOperations;
end;

function TComparePolicy.Allows(ACommand: TDDLCommand): Boolean;
var
  LOperation: TDDLOperation;
begin
  case ClassifyDDLCommand(ACommand, LOperation) of
    ckGuard:
      Result := True;                     // guarda: sempre permitida
    ckMutation:
      Result := LOperation in FOperations; // muta��o: sujeita � policy
  else
    Result := False;                       // ckUnknown: fail-closed
  end;
end;

end.
