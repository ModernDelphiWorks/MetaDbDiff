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
  MetaDbDiff.Compare.Options;

type
  TDatabaseAbstract = class abstract(TInterfacedObject, IDatabaseCompare)
  private
    function GetCommandsAutoExecute: Boolean;
    procedure SetCommandsAutoExecute(const Value: Boolean);
    function GetComparerFieldPosition: Boolean;
    procedure SetComparerFieldPosition(const Value: Boolean);
    function GetPolicy: TComparePolicy;
    procedure SetPolicy(const Value: TComparePolicy);
    function GetSuppressedCommands: TArray<String>;
  protected
    FDriverName: TDriverName;
    FGeneratorCommand: IDDLGeneratorCommand;
    FDDLCommands: TList<TDDLCommand>;
    FCatalogMaster: TCatalogMetadataMIK;
    FCatalogTarget: TCatalogMetadataMIK;
    FCommandsAutoExecute: Boolean;
    FComparerFieldPosition: Boolean;
    FModelForDatabase: Boolean;
    FPolicy: TComparePolicy;
    FSuppressedCommands: TList<String>;
    function GetFieldTypeValid(AFieldType: TFieldType): TFieldType; virtual; abstract;
    procedure GenerateDDLCommands(AMasterDB, ATargetDB: TCatalogMetadataMIK); virtual; abstract;
    procedure ExecuteDDLCommands; virtual; abstract;
    procedure ExtractDatabase; virtual; abstract;
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
    property ModelForDatabase: Boolean read FModelForDatabase;
    property CommandsAutoExecute: Boolean read GetCommandsAutoExecute write SetCommandsAutoExecute;
    property ComparerFieldPosition: Boolean read GetComparerFieldPosition write SetComparerFieldPosition;
    property Policy: TComparePolicy read GetPolicy write SetPolicy;
    property SuppressedCommands: TArray<String> read GetSuppressedCommands;
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
  // Vari�vel de controle para identificar se a compara��o est� sendo feita
  // Model vs Database ou Database vs Database.
  FModelForDatabase := False;
  // Default liberado: preserva o comportamento hist�rico de quem j� usa o diff.
  FPolicy := TComparePolicy.FullProfile;
  FSuppressedCommands := TList<String>.Create;
end;

destructor TDatabaseAbstract.Destroy;
begin
  // The commands are freed before the catalogs because they reference the
  // metadata objects owned by the catalogs (see TDatabaseFactory.BuildDatabase).
  FDDLCommands.Free;
  FCatalogMaster.Free;
  FCatalogTarget.Free;
  FSuppressedCommands.Free;
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

end.

