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

unit MetaDbDiff.DDL.Generator.MySQL;

interface

uses
  SysUtils,
  StrUtils,
  Variants,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorMySQL = class(TDDLSQLGenerator)
  protected
    /// <summary>
    ///   Mapeia o tipo da coluna para um tipo de destino VALIDO no CAST do MySQL.
    ///   O MySQL so aceita um conjunto restrito no CAST (CHAR, SIGNED, UNSIGNED,
    ///   DECIMAL, DATE, DATETIME, TIME, ...) - CAST(x AS VARCHAR(n)) e ERRO de
    ///   sintaxe. VARCHAR/CHAR -> CHAR(n); inteiros -> SIGNED; numericos -> DECIMAL.
    /// </summary>
    function _MySQLCastType(AColumn: TColumnMIK): String;
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateCopyColumnData(AColumn: TColumnMIK; const ASourceColumn: String;
      ABackfillNull: Boolean): String; override;
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String; override;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
    function GetSupportedFeatures: TSupportedFeatures; override;
  end;

implementation

{ TDDLSQLGeneratorMySQL }

function TDDLSQLGeneratorMySQL.GenerateAlterColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s MODIFY COLUMN %s;';
  Result := Format(Result, [AColumn.Table.Name, BuilderAlterFieldDefinition(AColumn)]);
end;

function TDDLSQLGeneratorMySQL._MySQLCastType(AColumn: TColumnMIK): String;
var
  LBase: String;
  LFor, LCut: Integer;
begin
  LBase := UpperCase(Trim(AColumn.TypeName));
  LCut := Length(LBase);
  for LFor := 1 to Length(LBase) do
    if CharInSet(LBase[LFor], ['(', ' ', '[']) then
    begin
      LCut := LFor - 1;
      Break;
    end;
  LBase := Copy(LBase, 1, LCut);

  if (Pos('CHAR', LBase) > 0) or (LBase = 'TEXT') or (LBase = 'STRING') or
     (LBase = 'CLOB') or (LBase = 'MEMO') then
  begin
    if AColumn.Size > 0 then
      Result := Format('CHAR(%d)', [AColumn.Size])
    else
      Result := 'CHAR';
  end
  else if (LBase = 'INTEGER') or (LBase = 'INT') or (LBase = 'SMALLINT') or
          (LBase = 'BIGINT') or (LBase = 'TINYINT') or (LBase = 'INT64') then
    Result := 'SIGNED'
  else if (LBase = 'NUMERIC') or (LBase = 'DECIMAL') or (LBase = 'NUMBER') or
          (LBase = 'DEC') or (LBase = 'FLOAT') or (LBase = 'DOUBLE') or (LBase = 'REAL') then
  begin
    if AColumn.Precision > 0 then
      Result := Format('DECIMAL(%d,%d)', [AColumn.Precision, AColumn.Scale])
    else
      Result := 'DECIMAL';
  end
  else if LBase = 'DATE' then
    Result := 'DATE'
  else if (LBase = 'DATETIME') or (LBase = 'TIMESTAMP') or (LBase = 'SMALLDATETIME') then
    Result := 'DATETIME'
  else if LBase = 'TIME' then
    Result := 'TIME'
  else
    Result := 'CHAR';   // fallback seguro (evita CAST invalido)
end;

function TDDLSQLGeneratorMySQL.GenerateCopyColumnData(AColumn: TColumnMIK;
  const ASourceColumn: String; ABackfillNull: Boolean): String;
begin
  // Backfill e SQL padrao (UPDATE ... WHERE ... IS NULL): reaproveita a base.
  if ABackfillNull then
    Exit(inherited GenerateCopyColumnData(AColumn, ASourceColumn, ABackfillNull));
  // Copia com CAST usando o tipo de destino VALIDO no MySQL (CHAR/SIGNED/DECIMAL...).
  Result := 'UPDATE %s SET %s = CAST(%s AS %s);';
  Result := Format(Result, [AColumn.Table.Name,
                            AColumn.Name,
                            ASourceColumn,
                            _MySQLCastType(AColumn)]);
end;

function TDDLSQLGeneratorMySQL.GenerateRenameColumn(AColumn: TColumnMIK;
  const ANewName: String): String;
begin
  // MySQL 8.0.0+ suporta ALTER TABLE ... RENAME COLUMN (padrao em 2026). Em
  // versoes < 8.0 seria necessario CHANGE <old> <new> <definicao completa>, que
  // exigiria repetir toda a definicao da coluna; por isso adotamos RENAME COLUMN.
  Result := 'ALTER TABLE %s RENAME COLUMN %s TO %s;';
  Result := Format(Result, [AColumn.Table.Name, AColumn.Name, ANewName]);
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
    Result := 'SET FOREIGN_KEY_CHECKS = 1;'
  else
    Result := 'SET FOREIGN_KEY_CHECKS = 0;';
end;

function TDDLSQLGeneratorMySQL.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  // MySQL nao possui comando para habilitar/desabilitar triggers em bloco nem
  // por sessao (a unica alternativa seria DROP/CREATE de cada trigger).
  // Retorna vazio; comandos vazios sao descartados pelo pipeline
  // (MetaDbDiff.Database.Compare -> Length(LCommand) > 0).
  Result := '';
end;

function TDDLSQLGeneratorMySQL.GetSupportedFeatures: TSupportedFeatures;
begin
  // MySQL nao possui objetos SEQUENCE (usa AUTO_INCREMENT por coluna). O
  // extractor agora retorna zero sequences; sem este gate, um modelo com
  // [Sequence] geraria CREATE SEQUENCE invalido (Database.Factory.CompareSequences
  // so roda com TSupportedFeature.Sequences no set). Remove Sequences do herdado.
  // FRENTE 15: adiciona Procedures (information_schema.ROUTINES). Sem DOMAINS.
  Result := inherited GetSupportedFeatures - [TSupportedFeature.Sequences] +
            [TSupportedFeature.Procedures];
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnMySQL, TDDLSQLGeneratorMySQL.Create);

end.
