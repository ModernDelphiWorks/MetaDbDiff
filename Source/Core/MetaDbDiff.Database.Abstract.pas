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

unit MetaDbDiff.Database.Abstract;

interface

uses
  DB,
  Classes,
  SysUtils,
  Generics.Collections,
  /// ormbr
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Database.Interfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Commands,
  MetaDbDiff.DDL.Sequencer,
  MetaDbDiff.Migration.Executor,
  MetaDbDiff.Compare.Options;

type
  TDatabaseAbstract = class abstract(TInterfacedObject, IDatabaseCompare)
  private
    function GetCommandsAutoExecute: Boolean;
    procedure SetCommandsAutoExecute(const Value: Boolean);
    function GetComparerFieldPosition: Boolean;
    procedure SetComparerFieldPosition(const Value: Boolean);
    function GetCompareSequenceInitialValue: Boolean;
    procedure SetCompareSequenceInitialValue(const Value: Boolean);
    function GetPolicy: TComparePolicy;
    procedure SetPolicy(const Value: TComparePolicy);
    function GetSuppressedCommands: TArray<String>;
    function GetErrorPolicy: TMigrationErrorPolicy;
    procedure SetErrorPolicy(const Value: TMigrationErrorPolicy);
    function GetUseSequencer: Boolean;
    procedure SetUseSequencer(const Value: Boolean);
    function GetRaiseOnError: Boolean;
    procedure SetRaiseOnError(const Value: Boolean);
    function GetLastMigrationReport: TMigrationReport;
    function GetLastSequenceReport: TDDLSequenceReport;
    /// <summary>
    ///   Monta o resumo textual de uma execu��o que falhou (n� de falhas,
    ///   primeira mensagem + fase, ponteiro para LastMigrationReport).
    /// </summary>
    function BuildFailureSummary: String;
    /// <summary>
    ///   Reordena FDDLCommands IN-PLACE segundo AOrdered, preservando as MESMAS
    ///   inst�ncias (nenhum free/double-free): a TObjectList tem OwnsObjects
    ///   temporariamente desligado enquanto as refer�ncias s�o reinseridas na
    ///   nova ordem. Exige mesmo tamanho (o sequenciador preserva a contagem).
    /// </summary>
    procedure ReorderCommandsInPlace(const AOrdered: TArray<TDDLCommand>);
  protected
    FDriverName: TDriverName;
    FGeneratorCommand: IDDLGeneratorCommand;
    FDDLCommands: TList<TDDLCommand>;
    FCatalogMaster: TCatalogMetadataMIK;
    FCatalogTarget: TCatalogMetadataMIK;
    FCommandsAutoExecute: Boolean;
    FComparerFieldPosition: Boolean;
    FCompareSequenceInitialValue: Boolean;
    FModelForDatabase: Boolean;
    FPolicy: TComparePolicy;
    FSuppressedCommands: TList<String>;
    FUseSequencer: Boolean;
    FErrorPolicy: TMigrationErrorPolicy;
    FRaiseOnError: Boolean;
    FLastMigrationReport: TMigrationReport;
    FLastSequenceReport: TDDLSequenceReport;
    function GetFieldTypeValid(AFieldType: TFieldType): TFieldType; virtual; abstract;
    procedure GenerateDDLCommands(AMasterDB, ATargetDB: TCatalogMetadataMIK); virtual; abstract;
    procedure ExecuteDDLCommands; virtual; abstract;
    procedure ExtractDatabase; virtual; abstract;
    /// <summary>
    ///   Passa a lista atual de comandos pelo TDDLSequencer (usando
    ///   FCatalogMaster/FCatalogTarget), guarda o TDDLSequenceReport em
    ///   FLastSequenceReport e reordena FDDLCommands in-place para a ordem
    ///   topol�gica por fase. No-op quando UseSequencer=False ou sem cat�logo
    ///   (fallback de compatibilidade: preserva a ordem hist�rica).
    /// </summary>
    procedure ApplySequencer;
    /// <summary>
    ///   Monta o plano de execu��o (TDDLSequenceReport) a partir dos comandos
    ///   atuais: sequenciado por fase quando UseSequencer + cat�logo dispon�vel;
    ///   caso contr�rio, um plano plano (fase �nica dphUnknown) preservando a
    ///   ordem corrente de FDDLCommands. Usado por GenerateScript,
    ///   SaveScriptToFile e ExecuteViaExecutor.
    /// </summary>
    function BuildPlanReport: TDDLSequenceReport;
    /// <summary>
    ///   Executa o plano corrente via TMigrationExecutor sobre AConnection
    ///   (driver da pr�pria conex�o), aplicando ErrorPolicy e gravando o
    ///   resultado em LastMigrationReport. N�O conecta nem desconecta a conex�o
    ///   (o executor rejeita conex�o j� em transa��o) - o ciclo de vida da
    ///   conex�o � responsabilidade do chamador/descendente.
    /// </summary>
    procedure ExecuteViaExecutor(const AConnection: IDBConnection);
    /// <summary>
    ///   Registra no relat�rio de auditoria uma opera��o suprimida pela policy.
    ///   O diff N�O falha silenciosamente: o dono do framework consegue auditar
    ///   o que o diff QUERIA fazer e foi bloqueado.
    /// </summary>
    procedure AddSuppressed(const ADescription: String);
    /// <summary>
    ///   Dupla checagem (defesa em profundidade): recusa a execu��o caso a lista
    ///   de comandos contenha alguma muta��o n�o permitida pela policy vigente.
    /// </summary>
    procedure ValidateCommandsPolicy;
    constructor Create(ADriverName: TDriverName); overload; virtual;
  public
    destructor Destroy; override;
    procedure BuildDatabase; virtual; abstract;
    procedure ExecuteCommands; virtual;
    function GetCommandList: TArray<TDDLCommand>; virtual;
    function GeneratorCommand: IDDLGeneratorCommand; virtual;
    function GenerateScript: String; virtual;
    procedure SaveScriptToFile(const AFileName: String); virtual;
    property ModelForDatabase: Boolean read FModelForDatabase;
    property CommandsAutoExecute: Boolean read GetCommandsAutoExecute write SetCommandsAutoExecute;
    property ComparerFieldPosition: Boolean read GetComparerFieldPosition write SetComparerFieldPosition;
    /// <summary>
    ///   Opt-in (default False): compara tambem o InitialValue das sequences.
    ///   Desligado por padrao porque o valor corrente avanca com o uso (alvo movel
    ///   em producao) e geraria ALTER SEQUENCE ... RESTART eterno. Por default so o
    ///   Increment e comparado.
    /// </summary>
    property CompareSequenceInitialValue: Boolean read GetCompareSequenceInitialValue write SetCompareSequenceInitialValue;
    property Policy: TComparePolicy read GetPolicy write SetPolicy;
    property SuppressedCommands: TArray<String> read GetSuppressedCommands;
    /// <summary>
    ///   Liga (default) o sequenciamento topol�gico por fase na gera��o. Quando
    ///   False, GetCommandList preserva a ordem hist�rica de gera��o.
    /// </summary>
    property UseSequencer: Boolean read GetUseSequencer write SetUseSequencer;
    /// <summary>
    ///   Pol�tica de erro do executor de migra��o: StopOnError (default) ou
    ///   ContinueOnError. Consumida no caminho de execu��o via TMigrationExecutor.
    /// </summary>
    property ErrorPolicy: TMigrationErrorPolicy read GetErrorPolicy write SetErrorPolicy;
    /// <summary>
    ///   Preserva o contrato hist�rico "fail-loud": quando True (default), uma
    ///   execu��o que registre qualquer falha (ou rollback) RE-LEVANTA uma
    ///   exce��o com o resumo (ver LastMigrationReport para o detalhe). Isso vale
    ///   inclusive com ErrorPolicy=ContinueOnError - o agregado � levantado ao
    ///   FINAL, pois o chamador precisa saber que o banco ficou meio-migrado.
    ///   Com False, nenhuma exce��o � levantada e o resultado fica apenas em
    ///   LastMigrationReport (semantica opt-in de inspe��o program�tica).
    /// </summary>
    property RaiseOnError: Boolean read GetRaiseOnError write SetRaiseOnError;
    /// <summary>
    ///   Resultado da �ltima execu��o via executor (fases, por-comando, rollback).
    ///   Zerado a cada nova execu��o e finalizado no Destroy.
    /// </summary>
    property LastMigrationReport: TMigrationReport read GetLastMigrationReport;
    /// <summary>
    ///   �ltimo relat�rio de sequenciamento produzido na gera��o (fases, ciclos).
    ///   Vazio quando UseSequencer=False.
    /// </summary>
    property LastSequenceReport: TDDLSequenceReport read GetLastSequenceReport;
  end;

implementation

{ TAbstractDatabase }

constructor TDatabaseAbstract.Create(ADriverName: TDriverName);
begin
  FDriverName := ADriverName;
  FCommandsAutoExecute := False;
  FGeneratorCommand := TSQLDriverRegister.GetInstance.GetDriver(ADriverName);
  FDDLCommands := TObjectList<TDDLCommand>.Create;
  FComparerFieldPosition := False;
  // Default False: nao compara InitialValue de sequence (evita falso-positivo
  // eterno em banco vivo, onde o valor corrente avanca com o uso).
  FCompareSequenceInitialValue := False;
  // Vari�vel de controle para identificar se a compara��o est� sendo feita
  // Model vs Database ou Database vs Database.
  FModelForDatabase := False;
  // Default liberado: preserva o comportamento hist�rico de quem j� usa o diff.
  FPolicy := TComparePolicy.FullProfile;
  FSuppressedCommands := TList<String>.Create;
  // Sequenciamento topol�gico ligado por padr�o (palavra de ordem do dono);
  // False mant�m a ordem hist�rica (fallback de compatibilidade).
  FUseSequencer := True;
  FErrorPolicy := mepStopOnError;
  // Contrato hist�rico: falha de migra��o RE-LEVANTA (fail-loud) por padr�o.
  FRaiseOnError := True;
  FLastMigrationReport := Default(TMigrationReport);
  FLastSequenceReport := Default(TDDLSequenceReport);
end;

destructor TDatabaseAbstract.Destroy;
begin
  // The commands are freed before the catalogs because they reference the
  // metadata objects owned by the catalogs (see TDatabaseFactory.BuildDatabase).
  FDDLCommands.Free;
  FCatalogMaster.Free;
  FCatalogTarget.Free;
  FSuppressedCommands.Free;
  // TMigrationReport / TDDLSequenceReport s�o records com arrays gerenciados:
  // zer�-los libera as refer�ncias antes de o objeto sair de escopo.
  FLastMigrationReport := Default(TMigrationReport);
  FLastSequenceReport := Default(TDDLSequenceReport);
  inherited;
end;

procedure TDatabaseAbstract.AddSuppressed(const ADescription: String);
begin
  FSuppressedCommands.Add(ADescription);
end;

procedure TDatabaseAbstract.ValidateCommandsPolicy;
var
  LDDLCommand: TDDLCommand;
  LOperation: TDDLOperation;
  LDenied: Boolean;
begin
  // Percorre a lista final e recusa qualquer comando n�o liberado pela policy -
  // protege contra comandos injetados na lista e contra classes n�o mapeadas.
  // Toda recusa � registrada na auditoria; se houver ao menos uma, a execu��o �
  // bloqueada (fail-closed) com uma exce��o clara.
  LDenied := False;
  for LDDLCommand in FDDLCommands do
  begin
    case ClassifyDDLCommand(LDDLCommand, LOperation) of
      ckGuard: ; // guarda: sempre permitida
      ckMutation:
        if not FPolicy.Allows(LOperation) then
        begin
          AddSuppressed(Format('%s denied by policy at execution',
            [LDDLCommand.Warning]));
          LDenied := True;
        end;
      ckUnknown:
        begin
          // Fail-closed: classe desconhecida � negada e auditada.
          AddSuppressed(Format(
            'unknown command class %s denied by fail-closed policy',
            [LDDLCommand.ClassName]));
          LDenied := True;
        end;
    end;
  end;
  if LDenied then
    raise Exception.Create('MetaDbDiff: execu��o recusada - h� comandos n�o ' +
      'permitidos pela policy vigente (ver SuppressedCommands).');
end;

procedure TDatabaseAbstract.ExecuteCommands;
var
  LCommandsAutoExecute: Boolean;
begin
  // Executes the previously generated commands without re-extracting the
  // metadata. The auto-execute flag is temporarily forced on so descendant
  // overrides of ExecuteDDLCommands actually run the commands, and it is
  // restored afterwards.
  LCommandsAutoExecute := FCommandsAutoExecute;
  FCommandsAutoExecute := True;
  // Nova execu��o: zera o relat�rio anterior.
  FLastMigrationReport := Default(TMigrationReport);
  try
    // Dupla checagem antes de executar (defesa em profundidade).
    ValidateCommandsPolicy;
    ExecuteDDLCommands;
  finally
    FCommandsAutoExecute := LCommandsAutoExecute;
  end;
end;

function TDatabaseAbstract.GeneratorCommand: IDDLGeneratorCommand;
begin
  Result := FGeneratorCommand;
end;

function TDatabaseAbstract.GetCommandList: TArray<TDDLCommand>;
var
  LFor: Integer;
begin
  LFor := 0;
  SetLength(Result, FDDLCommands.Count);
  for LFor := 0 to FDDLCommands.Count - 1 do
    Result[LFor] := FDDLCommands[LFor];
end;

function TDatabaseAbstract.GetCommandsAutoExecute: Boolean;
begin
  Result := FCommandsAutoExecute;
end;

function TDatabaseAbstract.GetComparerFieldPosition: Boolean;
begin
  Result := FComparerFieldPosition;
end;

procedure TDatabaseAbstract.SetCommandsAutoExecute(const Value: Boolean);
begin
  FCommandsAutoExecute := Value;
end;

procedure TDatabaseAbstract.SetComparerFieldPosition(const Value: Boolean);
begin
  FComparerFieldPosition := Value;
end;

function TDatabaseAbstract.GetCompareSequenceInitialValue: Boolean;
begin
  Result := FCompareSequenceInitialValue;
end;

procedure TDatabaseAbstract.SetCompareSequenceInitialValue(const Value: Boolean);
begin
  FCompareSequenceInitialValue := Value;
end;

function TDatabaseAbstract.GetPolicy: TComparePolicy;
begin
  Result := FPolicy;
end;

procedure TDatabaseAbstract.SetPolicy(const Value: TComparePolicy);
begin
  FPolicy := Value;
end;

function TDatabaseAbstract.GetSuppressedCommands: TArray<String>;
begin
  Result := FSuppressedCommands.ToArray;
end;

function TDatabaseAbstract.GetErrorPolicy: TMigrationErrorPolicy;
begin
  Result := FErrorPolicy;
end;

procedure TDatabaseAbstract.SetErrorPolicy(const Value: TMigrationErrorPolicy);
begin
  FErrorPolicy := Value;
end;

function TDatabaseAbstract.GetUseSequencer: Boolean;
begin
  Result := FUseSequencer;
end;

procedure TDatabaseAbstract.SetUseSequencer(const Value: Boolean);
begin
  FUseSequencer := Value;
end;

function TDatabaseAbstract.GetRaiseOnError: Boolean;
begin
  Result := FRaiseOnError;
end;

procedure TDatabaseAbstract.SetRaiseOnError(const Value: Boolean);
begin
  FRaiseOnError := Value;
end;

function TDatabaseAbstract.GetLastMigrationReport: TMigrationReport;
begin
  Result := FLastMigrationReport;
end;

function TDatabaseAbstract.GetLastSequenceReport: TDDLSequenceReport;
begin
  Result := FLastSequenceReport;
end;

procedure TDatabaseAbstract.ReorderCommandsInPlace(
  const AOrdered: TArray<TDDLCommand>);
var
  LObjList: TObjectList<TDDLCommand>;
  LOwned: Boolean;
  LCommand: TDDLCommand;
begin
  // O sequenciador preserva cada comando exatamente uma vez; se por qualquer
  // motivo a contagem divergir, N�O reordena (mant�m a lista intacta) para
  // jamais perder/vazar uma inst�ncia.
  if Length(AOrdered) <> FDDLCommands.Count then
    Exit;
  if FDDLCommands is TObjectList<TDDLCommand> then
  begin
    LObjList := TObjectList<TDDLCommand>(FDDLCommands);
    LOwned := LObjList.OwnsObjects;
    // Desliga a posse: Clear + Add s� mexem nas REFER�NCIAS, sem free algum.
    LObjList.OwnsObjects := False;
    try
      LObjList.Clear;
      for LCommand in AOrdered do
        LObjList.Add(LCommand);
    finally
      LObjList.OwnsObjects := LOwned;
    end;
  end
  else
  begin
    FDDLCommands.Clear;
    for LCommand in AOrdered do
      FDDLCommands.Add(LCommand);
  end;
end;

procedure TDatabaseAbstract.ApplySequencer;
var
  LSequencer: TDDLSequencer;
begin
  FLastSequenceReport := Default(TDDLSequenceReport);
  // Fallback de compatibilidade: sem sequenciador ou sem cat�logo mestre,
  // mant�m a ordem hist�rica de gera��o.
  if (not FUseSequencer) or (not Assigned(FCatalogMaster)) then
    Exit;
  LSequencer := TDDLSequencer.Create(FCatalogMaster, FCatalogTarget);
  try
    FLastSequenceReport := LSequencer.Sequence(FDDLCommands.ToArray);
  finally
    LSequencer.Free;
  end;
  // A lista final continua sendo a MESMA cole��o gerenciada por FDDLCommands -
  // apenas reordenada in-place a partir do resultado (mesmas inst�ncias).
  ReorderCommandsInPlace(FLastSequenceReport.Commands);
end;

function TDatabaseAbstract.BuildPlanReport: TDDLSequenceReport;
var
  LSequencer: TDDLSequencer;
  LItems: TArray<TDDLPhaseItem>;
  LFor: Integer;
begin
  if FUseSequencer and Assigned(FCatalogMaster) then
  begin
    // Reaproveita o relat�rio produzido na gera��o (ApplySequencer) quando ele
    // ainda corresponde � lista atual - o sequenciamento � determin�stico, ent�o
    // re-rodar Kahn/Tarjan daria o MESMO resultado. A contagem serve de guarda de
    // invalida��o: qualquer altera��o em FDDLCommands (nova gera��o, inje��o de
    // comando) muda o tamanho e for�a o re-sequenciamento abaixo.
    if (FDDLCommands.Count > 0) and
       (Length(FLastSequenceReport.Items) = FDDLCommands.Count) then
      Exit(FLastSequenceReport);
    LSequencer := TDDLSequencer.Create(FCatalogMaster, FCatalogTarget);
    try
      Result := LSequencer.Sequence(FDDLCommands.ToArray);
    finally
      LSequencer.Free;
    end;
  end
  else
  begin
    // Sem sequenciamento: plano plano, fase �nica (dphUnknown), ordem corrente.
    Result := Default(TDDLSequenceReport);
    SetLength(LItems, FDDLCommands.Count);
    for LFor := 0 to FDDLCommands.Count - 1 do
    begin
      LItems[LFor].Command := FDDLCommands[LFor];
      LItems[LFor].Phase := dphUnknown;
      LItems[LFor].ObjectName := '';
      LItems[LFor].OriginalIndex := LFor;
    end;
    Result.Items := LItems;
  end;
end;

function TDatabaseAbstract.BuildFailureSummary: String;
var
  LItem: TMigrationItemReport;
  LFirstMsg, LFirstPhase: String;
  LHasFirst: Boolean;
begin
  LHasFirst := False;
  LFirstMsg := '';
  LFirstPhase := '';
  for LItem in FLastMigrationReport.Items do
    if LItem.Status = misFailed then
    begin
      LFirstMsg := LItem.ErrorMessage;
      LFirstPhase := LItem.PhaseName;
      LHasFirst := True;
      Break;
    end;
  Result := Format(
    'MetaDbDiff: a migra��o falhou (%d falha(s), %d executada(s), %d ignorada(s)).',
    [FLastMigrationReport.Failed, FLastMigrationReport.Succeeded,
     FLastMigrationReport.Skipped]);
  if LHasFirst then
    Result := Result + sLineBreak +
      Format('Primeira falha [fase %s]: %s', [LFirstPhase, LFirstMsg]);
  if FLastMigrationReport.RolledBack then
    Result := Result + sLineBreak +
      'Ao menos uma fase sofreu rollback (dialeto transacional).';
  Result := Result + sLineBreak +
    'Detalhe completo (por-comando/fase) dispon�vel em LastMigrationReport.';
end;

procedure TDatabaseAbstract.ExecuteViaExecutor(const AConnection: IDBConnection);
var
  LExecutor: TMigrationExecutor;
begin
  // Nova execu��o: zera o relat�rio anterior antes de rodar.
  FLastMigrationReport := Default(TMigrationReport);
  LExecutor := TMigrationExecutor.Create(AConnection.GetDriver);
  try
    LExecutor.ErrorPolicy := FErrorPolicy;
    // O executor gere suas pr�prias transa��es por fase e rejeita conex�o j�
    // em transa��o; nunca conecta nem desconecta - isso � do chamador.
    FLastMigrationReport := LExecutor.Execute(BuildPlanReport, AConnection);
  finally
    LExecutor.Free;
  end;
  // Contrato fail-loud (restaurado): o executor N�O levanta em falha de comando
  // (grava misFailed e segue conforme ErrorPolicy). Para n�o deixar o chamador
  // cego a um banco meio-migrado, re-levantamos aqui o AGREGADO quando houve
  // qualquer falha ou rollback - inclusive sob ContinueOnError (o agregado � a
  // �nica forma de o chamador saber que nem tudo passou). RaiseOnError=False
  // desliga isso e deixa o resultado apenas em LastMigrationReport.
  if FRaiseOnError and
     ((FLastMigrationReport.Failed > 0) or FLastMigrationReport.RolledBack) then
    raise Exception.Create(BuildFailureSummary);
end;

function TDatabaseAbstract.GenerateScript: String;
var
  LExecutor: TMigrationExecutor;
begin
  LExecutor := TMigrationExecutor.Create(FDriverName);
  try
    LExecutor.ErrorPolicy := FErrorPolicy;
    // DryRun: nunca toca no banco (conex�o pode ser nil).
    Result := LExecutor.DryRun(BuildPlanReport).Script;
  finally
    LExecutor.Free;
  end;
end;

procedure TDatabaseAbstract.SaveScriptToFile(const AFileName: String);
var
  LExecutor: TMigrationExecutor;
begin
  LExecutor := TMigrationExecutor.Create(FDriverName);
  try
    LExecutor.ErrorPolicy := FErrorPolicy;
    // ScriptOut: grava o script consolidado como UTF-8, sem tocar no banco.
    LExecutor.ScriptOut(BuildPlanReport, AFileName);
  finally
    LExecutor.Free;
  end;
end;

end.

