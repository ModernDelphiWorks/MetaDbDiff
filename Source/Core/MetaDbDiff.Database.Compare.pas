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
}

unit MetaDbDiff.Database.Compare;

interface

uses
  SysUtils,
  Classes,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.DB.Factory,
  MetaDbDiff.Database.Factory;

type
  TDatabaseCompare = class(TDatabaseFactory)
  protected
    FAutoManager: Boolean;
    FConnMaster: IDBConnection;
    FConnTarget: IDBConnection;
    FMetadataMaster: TMetadataDBAbstract;
    FMetadataTarget: TMetadataDBAbstract;
    procedure ExtractDatabase; override;
    procedure ExecuteDDLCommands; override;
  public
    constructor Create(AConnMaster, AConnTarget: IDBConnection); overload;
    destructor Destroy; override;
  end;

implementation

{ TDatabaseCompare }

constructor TDatabaseCompare.Create(AConnMaster, AConnTarget: IDBConnection);
begin
  FModelForDatabase := False;
  FConnMaster := AConnMaster;
  FConnMaster.Connect;
  if not FConnMaster.IsConnected then
    raise Exception.Create('N�o foi possivel fazer conex�o com o banco de dados Master');

  FConnTarget := AConnTarget;
  FConnTarget.Connect;
  if not FConnTarget.IsConnected then
    raise Exception.Create('N�o foi possivel fazer conex�o com o banco de dados Target');

  inherited Create(AConnMaster.GetDriver);
  FMetadataMaster := TMetadataDBFactory.Create(Self, AConnMaster);
  FMetadataTarget := TMetadataDBFactory.Create(Self, AConnTarget);
end;

destructor TDatabaseCompare.Destroy;
begin
  FMetadataMaster.Free;
  FMetadataTarget.Free;
  inherited;
end;

// NOTE: When CommandsAutoExecute is False, BuildDatabase never reaches this
// method, so both connections remain connected afterwards - this is what
// allows a later ExecuteCommands call to run the generated commands.
// Execution is single-shot: the finally block below disconnects both
// connections, so ExecuteCommands cannot be called again without a new
// BuildDatabase.
//
// INTEGRA��O (frente-9): a execu��o passa a ser delegada ao TMigrationExecutor
// (via TDatabaseAbstract.ExecuteViaExecutor), que gere as pr�prias transa��es
// POR FASE. Por isso a transa��o local (StartTransaction/Commit/Rollback) foi
// REMOVIDA - o executor rejeita uma conex�o que j� esteja em transa��o, e �
// exatamente ele quem passa a controlar a transacionalidade. O resultado
// detalhado (fases, por-comando, rollback) fica em LastMigrationReport. O
// contrato hist�rico desta classe � preservado: o finally desconecta AMBAS as
// conex�es (comportamento documentado/single-shot).
procedure TDatabaseCompare.ExecuteDDLCommands;
begin
  inherited;
  try
    if FCommandsAutoExecute then
      ExecuteViaExecutor(FConnTarget);
  finally
    FConnMaster.Disconnect;
    FConnTarget.Disconnect;
  end;
end;

procedure TDatabaseCompare.ExtractDatabase;
begin
  inherited;
  // Extrai todo metadata com base nos modelos existentes
  FMetadataMaster.ExtractMetadata(FCatalogMaster);
  // Extrai todo metadata com base banco de dados acessado
  FMetadataTarget.ExtractMetadata(FCatalogTarget);
end;

end.
