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
  @abstract(Website : http://www.ormbr.com.br)
  @abstract(Telagram : https://t.me/ormbr)
}

unit MetaDbDiff.Mapping.Explorer;

interface

uses
  DB,
  Rtti,
  Classes,
  TypInfo,
  SysUtils,
  SyncObjs,
  Generics.Collections,
  /// DBCBr
  MetaDbDiff.RTTI.Helper,
  MetaDbDiff.Mapping.Attributes,
  MetaDbDiff.Mapping.Classes,
  MetaDbDiff.Mapping.Popular,
  MetaDbDiff.Mapping.Repository,
  MetaDbDiff.Mapping.Register;

type
  TMappingExplorer = class
  strict private
  class var
    // Serializes every lazy getter below. The cache dictionaries are populated
    // on demand (ContainsKey -> Add) and share a single TRttiContext; without
    // this lock, concurrent readers race on the TOCTOU (both miss, both Add =>
    // duplicate-key EListError) and on TDictionary Grow/Rehash and the RTL RTTI
    // pool (nil-deref AV "Read of address 0x00000000"). See PR: thread-safety.
    FLock: TCriticalSection;
    FContext: TRttiContext;
    FRepositoryMapping: TMappingRepository;
    FPopularMapping: TMappingPopular;
    FTableMapping: TDictionary<String, TTableMapping>;
    FOrderByMapping: TDictionary<String, TOrderByMapping>;
    FSequenceMapping: TDictionary<String, TSequenceMapping>;
    FPrimaryKeyMapping: TDictionary<String, TPrimaryKeyMapping>;
    FForeingnKeyMapping: TDictionary<String, TForeignKeyMappingList>;
    FIndexeMapping: TDictionary<String, TIndexeMappingList>;
    FCheckMapping: TDictionary<String, TCheckMappingList>;
    FColumnMapping: TDictionary<String, TColumnMappingList>;
    FCalcFieldMapping: TDictionary<String, TCalcFieldMappingList>;
    FAssociationMapping: TDictionary<String, TAssociationMappingList>;
    FJoinColumnMapping: TDictionary<String, TJoinColumnMappingList>;
    FTriggerMapping: TDictionary<String, TTriggerMappingList>;
    FViewMapping: TDictionary<String, TViewMapping>;
    FEnumerationMapping: TDictionary<String, TEnumerationMappingList>;
    FFieldEventsMapping: TDictionary<String, TFieldEventsMappingList>;
    FPrimaryKeyColumnsMapping: TDictionary<String, TPrimaryKeyColumnsMapping>;
//    FLazyLoadMapping: TDictionary<String, TLazyMapping>;
    FNotServerUse: TDictionary<String, Boolean>;
    FRESTReadOnly: TDictionary<String, Boolean>;
    FRESTAllowVerbs: TDictionary<String, TRESTAllowVerbCache>;
  public
    { Public declarations }
    class procedure ExecuteCreate;
    class procedure ExecuteDestroy;
    class function GetMappingTable(const AClass: TClass): TTableMapping;
    class function GetMappingOrderBy(const AClass: TClass): TOrderByMapping;
    class function GetMappingSequence(const AClass: TClass): TSequenceMapping;
    class function GetMappingPrimaryKey(const AClass: TClass): TPrimaryKeyMapping;
    class function GetMappingForeignKey(const AClass: TClass): TForeignKeyMappingList;
    class function GetMappingColumn(const AClass: TClass): TColumnMappingList;
    class function GetMappingCalcField(const AClass: TClass): TCalcFieldMappingList;
    class function GetMappingAssociation(const AClass: TClass): TAssociationMappingList;
    class function GetMappingJoinColumn(const AClass: TClass): TJoinColumnMappingList;
    class function GetMappingIndexe(const AClass: TClass): TIndexeMappingList;
    class function GetMappingCheck(const AClass: TClass): TCheckMappingList;
    class function GetMappingTrigger(const AClass: TClass): TTriggerMappingList;
    class function GetMappingView(const AClass: TClass): TViewMapping;
    class function GetMappingFieldEvents(const AClass: TClass): TFieldEventsMappingList;
    class function GetMappingEnumeration(const AClass: TClass): TEnumerationMappingList;
    class function GetMappingPrimaryKeyColumns(const AClass: TClass): TPrimaryKeyColumnsMapping;
    class function GetNotServerUse(const AClass: TClass): Boolean;
    class function GetRESTReadOnly(const AClass: TClass): Boolean;
    class function GetRESTAllowVerbs(const AClass: TClass): TRESTAllowVerbCache;
    class function GetRepositoryMapping: TMappingRepository;
//    class procedure GetMappingLazy(const AClass: TClass);
  end;

implementation

{ TMappingExplorer }

class procedure TMappingExplorer.ExecuteCreate;
begin
  FLock := TCriticalSection.Create;
  FContext := TRttiContext.Create;
  FPopularMapping     := TMappingPopular.Create;
  FTableMapping       := TObjectDictionary<String, TTableMapping>.Create([doOwnsValues]);
  FOrderByMapping     := TObjectDictionary<String, TOrderByMapping>.Create([doOwnsValues]);
  FSequenceMapping    := TObjectDictionary<String, TSequenceMapping>.Create([doOwnsValues]);
  FPrimaryKeyMapping  := TObjectDictionary<String, TPrimaryKeyMapping>.Create([doOwnsValues]);
  FForeingnKeyMapping := TObjectDictionary<String, TForeignKeyMappingList>.Create([doOwnsValues]);
  FColumnMapping      := TObjectDictionary<String, TColumnMappingList>.Create([doOwnsValues]);
  FCalcFieldMapping   := TObjectDictionary<String, TCalcFieldMappingList>.Create([doOwnsValues]);
  FAssociationMapping := TObjectDictionary<String, TAssociationMappingList>.Create([doOwnsValues]);
  FJoinColumnMapping  := TObjectDictionary<String, TJoinColumnMappingList>.Create([doOwnsValues]);
  FIndexeMapping      := TObjectDictionary<String, TIndexeMappingList>.Create([doOwnsValues]);
  FCheckMapping       := TObjectDictionary<String, TCheckMappingList>.Create([doOwnsValues]);
  FTriggerMapping     := TObjectDictionary<String, TTriggerMappingList>.Create([doOwnsValues]);
  FViewMapping        := TObjectDictionary<String, TViewMapping>.Create([doOwnsValues]);
  FFieldEventsMapping := TObjectDictionary<String, TFieldEventsMappingList>.Create([doOwnsValues]);
  FEnumerationMapping := TObjectDictionary<String, TEnumerationMappingList>.Create([doOwnsValues]);
  FPrimaryKeyColumnsMapping := TObjectDictionary<String, TPrimaryKeyColumnsMapping>.Create([doOwnsValues]);
  FNotServerUse := TDictionary<String, Boolean>.Create();
  FRESTReadOnly := TDictionary<String, Boolean>.Create();
  FRESTAllowVerbs := TDictionary<String, TRESTAllowVerbCache>.Create();
//  FLazyLoadMapping    := TObjectDictionary<String, TLazyMapping>.Create([doOwnsValues]);
end;

class procedure TMappingExplorer.ExecuteDestroy;
begin
  FContext.Free;
  FPopularMapping.Free;
  FTableMapping.Free;
  FOrderByMapping.Free;
  FSequenceMapping.Free;
  FPrimaryKeyMapping.Free;
  FForeingnKeyMapping.Free;
  FColumnMapping.Free;
  FCalcFieldMapping.Free;
  FAssociationMapping.Free;
  FJoinColumnMapping.Free;
  FIndexeMapping.Free;
  FTriggerMapping.Free;
  FCheckMapping.Free;
  FViewMapping.Free;
  FFieldEventsMapping.Free;
  FEnumerationMapping.Free;
//  FLazyLoadMapping.Free;
  FPrimaryKeyColumnsMapping.Free;
  FNotServerUse.Free;
  FRESTReadOnly.Free;
  FRESTAllowVerbs.Free;
  if Assigned(FRepositoryMapping) then
     FRepositoryMapping.Free;
  FLock.Free;
end;

class function TMappingExplorer.GetMappingPrimaryKey(
  const AClass: TClass): TPrimaryKeyMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FPrimaryKeyMapping.ContainsKey(AClass.ClassName) then
       Exit(FPrimaryKeyMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularPrimaryKey(LRttiType);
    // Add List
    FPrimaryKeyMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingPrimaryKeyColumns(
  const AClass: TClass): TPrimaryKeyColumnsMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FPrimaryKeyColumnsMapping.ContainsKey(AClass.ClassName) then
       Exit(FPrimaryKeyColumnsMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularPrimaryKeyColumns(LRttiType, AClass);
    // Add List
    FPrimaryKeyColumnsMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingSequence(
  const AClass: TClass): TSequenceMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FSequenceMapping.ContainsKey(AClass.ClassName) then
       Exit(FSequenceMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularSequence(LRttiType);
    // Add List
    FSequenceMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingCalcField(
  const AClass: TClass): TCalcFieldMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FCalcFieldMapping.ContainsKey(AClass.ClassName) then
       Exit(FCalcFieldMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularCalcField(LRttiType);
    // Add List
    FCalcFieldMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingCheck(
  const AClass: TClass): TCheckMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FCheckMapping.ContainsKey(AClass.ClassName) then
       Exit(FCheckMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularCheck(LRttiType);
    // Add List
    FCheckMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingColumn(const AClass: TClass): TColumnMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FColumnMapping.ContainsKey(AClass.ClassName) then
       Exit(FColumnMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularColumn(LRttiType, AClass);
    // Add List
    FColumnMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingEnumeration(
  const AClass: TClass): TEnumerationMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FEnumerationMapping.ContainsKey(AClass.ClassName) then
       Exit(FEnumerationMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result := FPopularMapping.PopularEnumeration(LRttiType);
    // Add List
    FEnumerationMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingFieldEvents(
  const AClass: TClass): TFieldEventsMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FFieldEventsMapping.ContainsKey(AClass.ClassName) then
       Exit(FFieldEventsMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularFieldEvents(LRttiType);
    // Add List
    FFieldEventsMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingForeignKey(
  const AClass: TClass): TForeignKeyMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FForeingnKeyMapping.ContainsKey(AClass.ClassName) then
       Exit(FForeingnKeyMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularForeignKey(LRttiType);
    // Add List
    FForeingnKeyMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingIndexe(
  const AClass: TClass): TIndexeMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FIndexeMapping.ContainsKey(AClass.ClassName) then
       Exit(FIndexeMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularIndexe(LRttiType);
    // Add List
    FIndexeMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingJoinColumn(
  const AClass: TClass): TJoinColumnMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FJoinColumnMapping.ContainsKey(AClass.ClassName) then
       Exit(FJoinColumnMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularJoinColumn(LRttiType);
    // Add List
    FJoinColumnMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

//class procedure TMappingExplorer.GetMappingLazy(const AClass: TClass);
//var
//  LRttiType: TRttiType;
//  LFieldName: String;
//  LField: TRttiField;
//begin
//  LRttiType := FContext.GetType(AClass);
//  for LField in LRttiType.GetFields do
//  begin
//    if LField.IsLazy then
//      GetMappingLazy(LField.GetLazyValue.AsInstance.MetaclassType)
//    else
//    if LField.FieldType.TypeKind = tkClass then
//      GetMappingLazy(LField.GetTypeValue.AsInstance.MetaclassType)
//    else
//      Continue;
//    LFieldName := 'T' + LField.FieldType.Handle.NameFld.ToString;
//    FLazyLoadMapping.Add(LFieldName, TLazyMapping.Create(LField));
//  end;
//end;

class function TMappingExplorer.GetMappingOrderBy(
  const AClass: TClass): TOrderByMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FOrderByMapping.ContainsKey(AClass.ClassName) then
       Exit(FOrderByMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularOrderBy(LRttiType);
    // Add List
    FOrderByMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingAssociation(
  const AClass: TClass): TAssociationMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FAssociationMapping.ContainsKey(AClass.ClassName) then
       Exit(FAssociationMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularAssociation(LRttiType);
    // Add List
    FAssociationMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingTable(
  const AClass: TClass): TTableMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FTableMapping.ContainsKey(AClass.ClassName) then
       Exit(FTableMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularTable(LRttiType);
    // Add List
    FTableMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingTrigger(
  const AClass: TClass): TTriggerMappingList;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FTriggerMapping.ContainsKey(AClass.ClassName) then
       Exit(FTriggerMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularTrigger(LRttiType);
    // Add List
    FTriggerMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetMappingView(
  const AClass: TClass): TViewMapping;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FViewMapping.ContainsKey(AClass.ClassName) then
       Exit(FViewMapping[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularView(LRttiType);
    // Add List
    FViewMapping.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetNotServerUse(const AClass: TClass): Boolean;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FNotServerUse.ContainsKey(AClass.ClassName) then
       Exit(FNotServerUse[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularNotServerUse(LRttiType);
    FNotServerUse.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetRESTReadOnly(const AClass: TClass): Boolean;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FRESTReadOnly.ContainsKey(AClass.ClassName) then
      Exit(FRESTReadOnly[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularRESTReadOnly(LRttiType);
    FRESTReadOnly.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetRESTAllowVerbs(const AClass: TClass): TRESTAllowVerbCache;
var
  LRttiType: TRttiType;
begin
  FLock.Enter;
  try
    if FRESTAllowVerbs.ContainsKey(AClass.ClassName) then
      Exit(FRESTAllowVerbs[AClass.ClassName]);

    LRttiType := FContext.GetType(AClass);
    Result    := FPopularMapping.PopularRESTAllowVerbs(LRttiType);
    FRESTAllowVerbs.Add(AClass.ClassName, Result);
  finally
    FLock.Leave;
  end;
end;

class function TMappingExplorer.GetRepositoryMapping: TMappingRepository;
begin
  FLock.Enter;
  try
    if not Assigned(FRepositoryMapping) then
      FRepositoryMapping := TMappingRepository.Create(TRegisterClass.GetAllEntityClass,
                                                      TRegisterClass.GetAllViewClass);
    Result := FRepositoryMapping;
  finally
    FLock.Leave;
  end;
end;

initialization
  TMappingExplorer.ExecuteCreate;

finalization
  TMappingExplorer.ExecuteDestroy;

end.

