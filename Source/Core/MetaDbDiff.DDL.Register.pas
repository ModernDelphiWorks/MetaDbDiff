{
      ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi

                   Copyright (c) 2016, Isaque Pinheiro
                          All rights reserved.

                    GNU Lesser General Public License
                      Vers�o 3, 29 de junho de 2007

       Copyright (C) 2007 Free Software Foundation, Inc. <http://fsf.org/>
       A todos � permitido copiar e distribuir c�pias deste documento de
       licen�a, mas mud�-lo n�o � permitido.

       Esta vers�o da GNU Lesser General Public License incorpora
       os termos e condi��es da vers�o 3 da GNU General Public License
       Licen�a, complementado pelas permiss�es adicionais listadas no
       arquivo LICENSE na pasta principal.
}

{ @abstract(ORMBr Framework.)
  @created(20 Jul 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.
}

unit MetaDbDiff.DDL.Register;

interface

uses
  SysUtils,
  Generics.Collections,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Generator,
  DataEngine.Factory.Interfaces;

type
  TSQLDriverRegister = class
  private
  class var
    FInstance: TSQLDriverRegister;
  private
    FDriver: TDictionary<TDriverName, IDDLGeneratorCommand>;
    constructor CreatePrivate;
  public
    { Public declarations }
    constructor Create;
    destructor Destroy; override;
    class function GetInstance: TSQLDriverRegister;
    procedure RegisterDriver(const ADriverName: TDriverName; const ADriverSQL: IDDLGeneratorCommand);
    function GetDriver(const ADriverName: TDriverName): IDDLGeneratorCommand;
  end;

implementation

constructor TSQLDriverRegister.Create;
begin
  raise Exception.Create('Para usar o SQLDriverRegister. use o m�todo TSQLDriverRegister.GetInstance()');
end;

constructor TSQLDriverRegister.CreatePrivate;
begin
  inherited;
  FDriver := TDictionary<TDriverName, IDDLGeneratorCommand>.Create;
end;

destructor TSQLDriverRegister.Destroy;
begin
  FDriver.Free;
  inherited;
end;

function TSQLDriverRegister.GetDriver(const ADriverName: TDriverName): IDDLGeneratorCommand;
begin
  if not FDriver.ContainsKey(ADriverName) then
    raise Exception.Create('O driver ' + TStrDriverName[ADriverName] + ' n�o est� registrado, adicione a unit "ormbr.ddl.generator.???.pas" onde ??? nome do driver, na cl�usula USES do seu projeto!');

  Result := FDriver[ADriverName];
end;

procedure TSQLDriverRegister.RegisterDriver(const ADriverName: TDriverName; const ADriverSQL: IDDLGeneratorCommand);
begin
  FDriver.AddOrSetValue(ADriverName, ADriverSQL);
end;

class function TSQLDriverRegister.GetInstance: TSQLDriverRegister;
begin
   if not Assigned(FInstance) then
      FInstance := TSQLDriverRegister.CreatePrivate;

   Result := FInstance;
end;

initialization

finalization
   if Assigned(TSQLDriverRegister.FInstance) then
   begin
      TSQLDriverRegister.FInstance.Free;
   end;
end.

