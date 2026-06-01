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
  @created(12 Out 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.
}

unit MetaDbDiff.DDL.Generator.AbsoluteDB;

interface

uses
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.Factory.Interfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorAbsoluteDB = class(TDDLSQLGenerator)
  protected
    function BuilderPrimayKeyDefinition(ATable: TTableMIK): String; override;
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateDropTable(ATable: TTableMIK): String; override;
    function GenerateDropSequence(ASequence: TSequenceMIK): String; override;
    function GetSupportedFeatures: TSupportedFeatures; override;
  end;

implementation

{ TDDLSQLGeneratorAbsoluteDB }

function TDDLSQLGeneratorAbsoluteDB.BuilderPrimayKeyDefinition(ATable: TTableMIK): String;

  function GetPrimaryKeyColumns: String;
  var
    oColumn: TPair<String,TColumnMIK>;
  begin
    for oColumn in ATable.PrimaryKey.FieldsSort do
      Result := Result + oColumn.Value.Name + ', ';
    Result := Trim(Result);
    Delete(Result, Length(Result), 1);
  end;

begin
//  Result := 'PRIMARY KEY(%s) %s';
//  Result := Format(Result, [GetPrimaryKeyColumns, IfThen(ATable.PrimaryKey.AutoIncrement,'AUTOINCREMENT','')]);
  Result := 'PRIMARY KEY(%s) ';
  Result := Format(Result, [GetPrimaryKeyColumns]);
  Result := '  ' + Result;
end;

function TDDLSQLGeneratorAbsoluteDB.GenerateCreateSequence(ASequence: TSequenceMIK): String;
begin
  inherited;
  Result := 'INSERT INTO SQLITE_SEQUENCE (NAME, SEQ) VALUES (%s, %s);';
  Result := Format(Result, [QuotedStr(ASequence.Name), IntToStr(0)]);
end;

function TDDLSQLGeneratorAbsoluteDB.GenerateCreateTable(ATable: TTableMIK): String;
var
  oSQL: TStringBuilder;
  oColumn: TPair<String,TColumnMIK>;
begin
  oSQL := TStringBuilder.Create;
  Result := inherited GenerateCreateTable(ATable);
  try
    if ATable.Database.Schema <> '' then
      oSQL.Append(Format(Result, [ATable.Database.Schema + '.' + ATable.Name]))
    else
      oSQL.Append(Format(Result, [ATable.Name]));
    /// <summary>
    /// Add Colunas
    /// </summary>
    for oColumn in ATable.FieldsSort do
    begin
      oSQL.AppendLine;
      oSQL.Append('  ' + BuilderCreateFieldDefinition(oColumn.Value));
      oSQL.Append(',');
    end;
    /// <summary>
    /// Add PrimariKey
    /// </summary>
    if ATable.PrimaryKey.Fields.Count > 0 then
    begin
      oSQL.AppendLine;
      oSQL.Append(BuilderPrimayKeyDefinition(ATable));
    end;
    /// <summary>
    /// Add Indexe
    /// </summary>
    if ATable.IndexeKeys.Count > 0 then
    begin
      oSQL.AppendLine;
      oSQL.Append(BuilderIndexeDefinition(ATable));
    end;
    oSQL.AppendLine;
    Result := oSQL.ToString;
  finally
    oSQL.Free;
  end;
end;

function TDDLSQLGeneratorAbsoluteDB.GenerateDropSequence(ASequence: TSequenceMIK): String;
begin
  inherited;
  Result := 'DELETE FROM SQLITE_SEQUENCE WHERE NAME = %s;';
  Result := Format(Result, [QuotedStr(ASequence.Name)]);
end;

function TDDLSQLGeneratorAbsoluteDB.GenerateDropTable(ATable: TTableMIK): String;
begin
  Result := inherited GenerateDropTable(ATable);
end;

function TDDLSQLGeneratorAbsoluteDB.GetSupportedFeatures: TSupportedFeatures;
begin
  Result := inherited GetSupportedFeatures - [TSupportedFeature.ForeignKeys,
                                              TSupportedFeature.Checks,
                                              TSupportedFeature.Views,
                                              TSupportedFeature.Triggers];
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnAbsoluteDB, TDDLSQLGeneratorAbsoluteDB.Create);

end.

