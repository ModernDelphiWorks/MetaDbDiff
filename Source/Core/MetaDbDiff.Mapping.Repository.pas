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

unit MetaDbDiff.Mapping.Repository;

interface

uses
  Rtti,
  SysUtils,
  Generics.Collections,
  MetaDbDiff.Mapping.Exceptions;

type
  TRepository = class
  private
    FEntitys: TObjectDictionary<TClass, TList<TClass>>;
    FViews: TObjectDictionary<TClass, TList<TClass>>;
    FTriggers: TObjectDictionary<TClass, TList<TClass>>;
    function _GetEntity: TEnumerable<TClass>;
    function _GetView: TEnumerable<TClass>;
    function _GetTrigger: TEnumerable<TClass>;
  protected
    property EntityList: TObjectDictionary<TClass, TList<TClass>> read FEntitys;
    property ViewList: TObjectDictionary<TClass, TList<TClass>> read FViews;
    property TriggerList: TObjectDictionary<TClass, TList<TClass>> read FTriggers;
  public
    constructor Create;
    destructor Destroy; override;
    property Entitys: TEnumerable<TClass> read _GetEntity;
    property Views: TEnumerable<TClass> read _GetView;
    property Trigger: TEnumerable<TClass> read _GetTrigger;
  end;

  TMappingRepository = class
  private
    FRepository: TRepository;
//    function FindEntity(AClass: TClass): TList<TClass>;
  public
    constructor Create(AEntity, AView: TArray<TClass>);
    destructor Destroy; override;
    function GetEntity(AClass: TClass): TEnumerable<TClass>;
    function FindEntityByName(const ClassName: String): TClass;
    property List: TRepository read FRepository;
  end;

implementation

{ TMappingRepository }

constructor TMappingRepository.Create(AEntity, AView: TArray<TClass>);
var
  LClass: TClass;
begin
  FRepository := TRepository.Create;
  // Entitys
  if AEntity <> nil then
    for LClass in AEntity do
      if not FRepository.EntityList.ContainsKey(LClass) then
        FRepository.EntityList.Add(LClass, TList<TClass>.Create);

  for LClass in FRepository.Entitys do
    if FRepository.EntityList.ContainsKey(LClass.ClassParent) then
      FRepository.EntityList[LClass.ClassParent].Add(LClass);

  // Views
  if AView <> nil then
    for LClass in AView do
      if not FRepository.ViewList.ContainsKey(LClass) then
        FRepository.ViewList.Add(LClass, TList<TClass>.Create);

  for LClass in FRepository.Views do
    if FRepository.ViewList.ContainsKey(LClass.ClassParent) then
      FRepository.ViewList[LClass.ClassParent].Add(LClass);
end;

destructor TMappingRepository.Destroy;
begin
  FRepository.Free;
  inherited;
end;

function TMappingRepository.FindEntityByName(const ClassName: String): TClass;
var
  LClass: TClass;
begin
  Result := nil;
  for LClass in FRepository.Entitys do
    if SameText(LClass.ClassName, ClassName) then
      Exit(LClass);
end;

//function TMappingRepository.FindEntity(AClass: TClass): TList<TClass>;
//var
//  LClass: TClass;
//  LListClass: TList<TClass>;
//begin
//  Result := TList<TClass>.Create;
//  Result.AddRange(GetEntity(AClass));
//
//  for LClass in GetEntity(AClass) do
//  begin
//    LListClass := FindEntity(LClass);
//    try
//      Result.AddRange(LListClass);
//    finally
//      LListClass.Free;
//    end;
//  end;
//end;

function TMappingRepository.GetEntity(AClass: TClass): TEnumerable<TClass>;
begin
  if not FRepository.EntityList.ContainsKey(AClass) then
     EClassNotRegistered.Create(AClass);

  Result := FRepository.EntityList[AClass];
end;

{ TRepository }

constructor TRepository.Create;
begin
  FEntitys := TObjectDictionary<TClass, TList<TClass>>.Create([doOwnsValues]);
  FViews := TObjectDictionary<TClass, TList<TClass>>.Create([doOwnsValues]);
end;

destructor TRepository.Destroy;
begin
  FEntitys.Free;
  FViews.Free;
  inherited;
end;

function TRepository._GetEntity: TEnumerable<TClass>;
begin
  Result := FEntitys.Keys;
end;

function TRepository._GetTrigger: TEnumerable<TClass>;
begin
  Result := FTriggers.Keys;
end;

function TRepository._GetView: TEnumerable<TClass>;
begin
  Result := FViews.Keys;
end;

end.

