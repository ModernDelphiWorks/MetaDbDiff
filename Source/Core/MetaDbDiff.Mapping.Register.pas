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
  // Returns a snapshot (copy) of the registered entities WITHOUT clearing the
  // internal list, so a second caller in the same process (e.g. a second
  // TMappingRepository/comparison) observes the same registrations instead of
  // an empty array. See MetaDbDiff.Mapping.Explorer.TMappingExplorer.GetRepositoryMapping,
  // the only in-repo caller, which already caches its own snapshot the first
  // time it runs - that caching is unaffected by this change.
  SetLength(Result, FEntitys.Count);
  for LFor := 0 to FEntitys.Count -1 do
    Result[LFor] := FEntitys[LFor];
end;

class function TRegisterClass.GetAllTriggerClass: TArray<TClass>;
var
  LFor: Integer;
begin
  // See the comment in GetAllEntityClass: no longer one-shot.
  SetLength(Result, FTriggers.Count);
  for LFor := 0 to FTriggers.Count -1 do
    Result[LFor] := FTriggers[LFor];
end;

class function TRegisterClass.GetAllViewClass: TArray<TClass>;
var
  LFor: Integer;
begin
  // See the comment in GetAllEntityClass: no longer one-shot.
  SetLength(Result, FViews.Count);
  for LFor := 0 to FViews.Count -1 do
    Result[LFor] := FViews[LFor];
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


