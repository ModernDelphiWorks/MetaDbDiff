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

unit MetaDbDiff.Mapping.Register;

interface

uses
  SysUtils,
  Rtti,
  Generics.Collections;

type
  TRegisterClass = class
  strict private
    class var
    FEntitys: TList<TClass>;
    FViews: TList<TClass>;
    FTriggers: TList<TClass>;
  public
    class constructor Create;
    class destructor Destroy;
    ///
    class function GetAllEntityClass: TArray<TClass>;
    class function GetAllViewClass: TArray<TClass>;
    class function GetAllTriggerClass: TArray<TClass>;
    ///
    class procedure RegisterEntity(AClass: TClass);
    class procedure RegisterView(AClass: TClass);
    class procedure RegisterTrigger(AClass: TClass);
    ///
    class property EntityList: TList<TClass> read FEntitys;
    class property ViewList: TList<TClass> read FViews;
    class property TriggerList: TList<TClass> read FTriggers;
  end;

implementation

{ TRegisterClass }

class constructor TRegisterClass.Create;
begin
  FEntitys := TList<TClass>.Create;
  FViews := TList<TClass>.Create;
  FTriggers := TList<TClass>.Create;
end;

class destructor TRegisterClass.Destroy;
begin
  FEntitys.Free;
  FViews.Free;
  FTriggers.Free;
end;

class function TRegisterClass.GetAllEntityClass: TArray<TClass>;
var
  LFor: Integer;
begin
  try
    SetLength(Result, FEntitys.Count);
    for LFor := 0 to FEntitys.Count -1 do
      Result[LFor] := FEntitys[LFor];
  finally
    FEntitys.Clear;
  end;
end;

class function TRegisterClass.GetAllTriggerClass: TArray<TClass>;
var
  LFor: Integer;
begin
  try
    SetLength(Result, FTriggers.Count);
    for LFor := 0 to FTriggers.Count -1 do
      Result[LFor] := FTriggers[LFor];
  finally
    FTriggers.Clear;
  end;
end;

class function TRegisterClass.GetAllViewClass: TArray<TClass>;
var
  LFor: Integer;
begin
  try
    SetLength(Result, FViews.Count);
    for LFor := 0 to FViews.Count -1 do
      Result[LFor] := FViews[LFor];
  finally
    FViews.Clear;
  end;
end;

class procedure TRegisterClass.RegisterEntity(AClass: TClass);
begin
  if not FEntitys.Contains(AClass) then
    FEntitys.Add(AClass);
end;

class procedure TRegisterClass.RegisterTrigger(AClass: TClass);
begin
  if not FTriggers.Contains(AClass) then
    FTriggers.Add(AClass);
end;

class procedure TRegisterClass.RegisterView(AClass: TClass);
begin
  if not FViews.Contains(AClass) then
    FViews.Add(AClass);
end;

end.


