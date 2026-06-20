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

unit MetaDbDiff.Metadata.Register;

interface

uses
  SysUtils,
  Generics.Collections,
  MetaDbDiff.Metadata.Extract,
  DataEngine.FactoryInterfaces;

type
  TMetadataRegister = class
  private
  class var
    FInstance: TMetadataRegister;
  private
    FDriver: TDictionary<TDriverName, TCatalogMetadataAbstract>;
    constructor CreatePrivate;
  public
    { Public declarations }
    constructor Create;
    destructor Destroy; override;
    class function GetInstance: TMetadataRegister;
    procedure RegisterMetadata(const ADriverName: TDriverName; const ACatalogMetadata: TCatalogMetadataAbstract);
    function GetMetadata(const ADriverName: TDriverName): TCatalogMetadataAbstract;
  end;

implementation

constructor TMetadataRegister.Create;
begin
  raise Exception.Create('Para usar o MetadataRegister use o m�todo TMetadataRegister.GetInstance()');
end;

constructor TMetadataRegister.CreatePrivate;
begin
  FDriver := TObjectDictionary<TDriverName, TCatalogMetadataAbstract>.Create([doOwnsValues]);
end;

destructor TMetadataRegister.Destroy;
begin
  FDriver.Free;
  inherited;
end;

class function TMetadataRegister.GetInstance: TMetadataRegister;
begin
   if not Assigned(FInstance) then
      FInstance := TMetadataRegister.CreatePrivate;

   Result := FInstance;
end;

function TMetadataRegister.GetMetadata(const ADriverName: TDriverName): TCatalogMetadataAbstract;
begin
  if not FDriver.ContainsKey(ADriverName) then
    raise Exception.Create('O driver ' + TStrDriverName[ADriverName] + ' n�o est� registrado, adicione a unit "ormbr.metadata.???.pas" onde ??? nome do driver, na cl�usula USES do seu projeto!');

  Result := FDriver[ADriverName];
end;

procedure TMetadataRegister.RegisterMetadata(const ADriverName: TDriverName; const ACatalogMetadata: TCatalogMetadataAbstract);
begin
  FDriver.AddOrSetValue(ADriverName, ACatalogMetadata);
end;

initialization

finalization
   if Assigned(TMetadataRegister.FInstance) then
     TMetadataRegister.FInstance.Free;

end.

