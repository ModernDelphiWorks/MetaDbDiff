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
  MetaDbDiff.DDL.Commands;

type
  TDatabaseAbstract = class abstract(TInterfacedObject, IDatabaseCompare)
  private
    function GetCommandsAutoExecute: Boolean;
    procedure SetCommandsAutoExecute(const Value: Boolean);
    function GetComparerFieldPosition: Boolean;
    procedure SetComparerFieldPosition(const Value: Boolean);
  protected
    FDriverName: TDriverName;
    FGeneratorCommand: IDDLGeneratorCommand;
    FDDLCommands: TList<TDDLCommand>;
    FCatalogMaster: TCatalogMetadataMIK;
    FCatalogTarget: TCatalogMetadataMIK;
    FCommandsAutoExecute: Boolean;
    FComparerFieldPosition: Boolean;
    FModelForDatabase: Boolean;
    function GetFieldTypeValid(AFieldType: TFieldType): TFieldType; virtual; abstract;
    procedure GenerateDDLCommands(AMasterDB, ATargetDB: TCatalogMetadataMIK); virtual; abstract;
    procedure ExecuteDDLCommands; virtual; abstract;
    procedure ExtractDatabase; virtual; abstract;
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
end;

destructor TDatabaseAbstract.Destroy;
begin
  // The commands are freed before the catalogs because they reference the
  // metadata objects owned by the catalogs (see TDatabaseFactory.BuildDatabase).
  FDDLCommands.Free;
  FCatalogMaster.Free;
  FCatalogTarget.Free;
  inherited;
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

end.

