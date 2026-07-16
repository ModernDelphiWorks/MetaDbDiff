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
    ///   (Enable*) s�o sempre permitidos por n�o serem muta��es.
    /// </summary>
    function Allows(ACommand: TDDLCommand): Boolean; overload;
    property Operations: TDDLOperations read FOperations write FOperations;
  end;

/// <summary>
///   Mapeia a classe concreta de um TDDLCommand para a opera��o correspondente.
///   Retorna False quando o comando � de guarda (EnableForeignKeys /
///   EnableTriggers), caso em que AOperation n�o deve ser considerado.
/// </summary>
function TryGetDDLOperation(ACommand: TDDLCommand;
  out AOperation: TDDLOperation): Boolean;

implementation

function TryGetDDLOperation(ACommand: TDDLCommand;
  out AOperation: TDDLOperation): Boolean;
begin
  Result := True;
  // Dispatch por classe do comando (o mapeamento vive aqui para n�o precisar
  // editar MetaDbDiff.DDL.Commands.pas).
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
    // TDDLCommandEnableForeignKeys / TDDLCommandEnableTriggers: guardas.
    Result := False;
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
  // Comandos de guarda (Enable*) n�o s�o muta��es: sempre permitidos.
  if not TryGetDDLOperation(ACommand, LOperation) then
    Exit(True);
  Result := LOperation in FOperations;
end;

end.
