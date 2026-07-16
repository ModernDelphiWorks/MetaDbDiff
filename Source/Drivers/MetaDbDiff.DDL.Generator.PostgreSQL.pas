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

unit MetaDbDiff.DDL.Generator.PostgreSQL;

interface

uses
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorPostgreSQL = class(TDDLSQLGenerator)
  protected
    /// <summary>
    ///   Qualificacao PostgreSQL: "schema"."nome" quando ha schema; caso
    ///   contrario apenas o nome cru (default '' preserva o SQL historico).
    /// </summary>
    class function _QualifyName(const ASchema, AName: String): String; override;
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
  end;

implementation

{ TDDLSQLGeneratorPostgreSQL }

class function TDDLSQLGeneratorPostgreSQL._QualifyName(const ASchema, AName: String): String;
begin
  if ASchema <> '' then
    Result := '"' + ASchema + '"."' + AName + '"'
  else
    Result := AName;
end;

function TDDLSQLGeneratorPostgreSQL.GenerateAlterColumn(AColumn: TColumnMIK): String;
var
  LQualifiedTable: String;
  LBuilder: TStringBuilder;
begin
  // Antes qualificava sempre como "<schema>.<tabela>", produzindo ".<tabela>"
  // (SQL invalido) quando nao havia schema. Agora usa _QualifyTable: com schema
  // vira "schema"."tabela"; sem schema, apenas a tabela.
  LQualifiedTable := _QualifyTable(AColumn.Table);
  Result := Format('ALTER TABLE %s ALTER COLUMN %s', [LQualifiedTable, AColumn.Name]);
  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append(Result + Format(' TYPE %s;', [GetFieldTypeDefinition(AColumn)]));

    if Length(AColumn.DefaultValue) > 0 then
      LBuilder.Append(Result + Format(' SET DEFAULT %s;', [AColumn.DefaultValue]))
    else
      LBuilder.Append(Result + ' DROP DEFAULT;');

    if AColumn.NotNull then
      LBuilder.Append(Result + ' SET NOT NULL;')
    else
      LBuilder.Append(Result + ' DROP NOT NULL;');

    LBuilder.Append(Format('COMMENT ON COLUMN %s.%s IS %s', [LQualifiedTable,
                                                             AColumn.Name,
                                                             QuoTedStr(AColumn.Description)]));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TDDLSQLGeneratorPostgreSQL.GenerateCreateSequence(ASequence: TSequenceMIK): String;
begin
  Result := 'CREATE SEQUENCE "%s" INCREMENT %s START %s;';
  Result := Format(Result, [ASequence.Name,
                            IntToStr(ASequence.Increment),
                            IntToStr(ASequence.InitialValue)]);
end;

function TDDLSQLGeneratorPostgreSQL.GenerateCreateTable(ATable: TTableMIK): String;
var
  LSQL: TStringBuilder;
  LColumn: TPair<String,TColumnMIK>;
begin
  LSQL := TStringBuilder.Create;
  Result := inherited GenerateCreateTable(ATable);
  try
    LSQL.Append(Format(Result, [_QualifyTable(ATable)]));
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

function TDDLSQLGeneratorPostgreSQL.GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  Result := 'DROP INDEX %s;';
  Result := Format(Result, [AIndexe.Name]);
end;

function TDDLSQLGeneratorPostgreSQL.GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP PRIMARY KEY;';
  Result := Format(Result, [_QualifyTable(APrimaryKey.Table)]);
end;

function TDDLSQLGeneratorPostgreSQL.GenerateEnableForeignKeys(AEnable: Boolean): String;
begin
  // SET session_replication_role = replica desativa, na sessao corrente, o
  // disparo das triggers de usuario e das triggers internas que validam FKs;
  // por isso o mesmo comando atende GenerateEnableForeignKeys e
  // GenerateEnableTriggers. Requer superusuario (ou permissao equivalente).
  if AEnable then
    Result := 'SET session_replication_role = DEFAULT;'
  else
    Result := 'SET session_replication_role = replica;';
end;

function TDDLSQLGeneratorPostgreSQL.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  // Mesmo mecanismo de GenerateEnableForeignKeys: session_replication_role
  // suspende triggers de usuario e a validacao de FKs na sessao corrente.
  if AEnable then
    Result := 'SET session_replication_role = DEFAULT;'
  else
    Result := 'SET session_replication_role = replica;';
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnPostgreSQL, TDDLSQLGeneratorPostgreSQL.Create);

end.
