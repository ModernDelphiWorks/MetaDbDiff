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
  @created(12 Out 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.
}

unit MetaDbDiff.DDL.Generator.MySQL;

interface

uses
  SysUtils,
  StrUtils,
  Variants,
  Generics.Collections,
  DataEngine.Factory.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorMySQL = class(TDDLSQLGenerator)
  protected
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
  end;

implementation

{ TDDLSQLGeneratorMySQL }

function TDDLSQLGeneratorMySQL.GenerateAlterColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s MODIFY COLUMN %s;';
  Result := Format(Result, [AColumn.Table.Name, BuilderAlterFieldDefinition(AColumn)]);
end;

function TDDLSQLGeneratorMySQL.GenerateCreateTable(ATable: TTableMIK): String;
var
  LSQL: TStringBuilder;
  LColumn: TPair<String,TColumnMIK>;
begin
  LSQL := TStringBuilder.Create;
  Result := inherited GenerateCreateTable(ATable);
  try
    if ATable.Database.Schema <> '' then
      LSQL.Append(Format(Result, [ATable.Database.Schema + '.' + ATable.Name]))
    else
      LSQL.Append(Format(Result, [ATable.Name]));
    /// <summary>
    ///   Add Colunas
    /// </summary>
    for LColumn in ATable.FieldsSort do
    begin
      LSQL.AppendLine;
      LSQL.Append('  ' + BuilderCreateFieldDefinition(LColumn.Value));
      LSQL.Append(',');
    end;
    /// <summary>
    ///   Add PrimariKey
    /// </summary>
    if ATable.PrimaryKey.Fields.Count > 0 then
    begin
      LSQL.AppendLine;
      LSQL.Append(BuilderPrimayKeyDefinition(ATable));
    end;
    /// <summary>
    ///   Add ForeignKey
    /// </summary>
//    if ATable.ForeignKeys.Count > 0 then
//    begin
//      LSQL.Append(',');
//      LSQL.Append(BuilderForeignKeyDefinition(ATable));
//    end;
    /// <summary>
    ///   Add Checks
    /// </summary>
    if ATable.Checks.Count > 0 then
    begin
      LSQL.Append(',');
      LSQL.Append(BuilderCheckDefinition(ATable));
    end;
    LSQL.AppendLine;
    LSQL.Append(');');
    /// <summary>
    ///   Add Indexe
    /// </summary>
    if ATable.IndexeKeys.Count > 0 then
      LSQL.Append(BuilderIndexeDefinition(ATable));
    LSQL.AppendLine;
    Result := LSQL.ToString;
  finally
    LSQL.Free;
  end;
end;

function TDDLSQLGeneratorMySQL.GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP INDEX %s;';
  Result := Format(Result, [AIndexe.Table.Name, AIndexe.Name]);
end;

function TDDLSQLGeneratorMySQL.GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP PRIMARY KEY;';
  Result := Format(Result, [APrimaryKey.Table.Name]);
end;

function TDDLSQLGeneratorMySQL.GenerateEnableForeignKeys(AEnable: Boolean): String;
begin
  if AEnable then
    Result := ''
  else
    Result := '';
end;

function TDDLSQLGeneratorMySQL.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  if AEnable then
    Result := ''
  else
    Result := '';
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnMySQL, TDDLSQLGeneratorMySQL.Create);

end.
