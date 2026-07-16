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

unit MetaDbDiff.DDL.Generator.MSSQL;

interface

uses
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorMSSQL = class(TDDLSQLGenerator)
  protected
    /// <summary>
    ///   Qualificacao SQL Server: [schema].[nome] quando ha schema; caso
    ///   contrario apenas o nome cru (default '' preserva o SQL historico).
    /// </summary>
    class function _QualifyName(const ASchema, AName: String): String; override;
  public
    // FRENTE 15: SQL Server suporta PROCEDURES/FUNCTIONS (sys.objects P/FN +
    // sys.sql_modules). Sem DOMAINS. COMMENT ON (extended properties) fica FORA.
    function GetSupportedFeatures: TSupportedFeatures; override;
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String; override;
  end;

implementation

{ TDDLSQLGeneratorMSSQL }

class function TDDLSQLGeneratorMSSQL._QualifyName(const ASchema, AName: String): String;
begin
  if ASchema <> '' then
    Result := '[' + ASchema + '].[' + AName + ']'
  else
    Result := AName;
end;

function TDDLSQLGeneratorMSSQL.GetSupportedFeatures: TSupportedFeatures;
begin
  Result := inherited GetSupportedFeatures + [TSupportedFeature.Procedures];
end;

function TDDLSQLGeneratorMSSQL.GenerateCreateSequence(ASequence: TSequenceMIK): String;
begin
  Result := 'CREATE SEQUENCE %s AS int START WITH %s INCREMENT BY %s;';
  Result := Format(Result, [ASequence.Name,
                           IntToStr(ASequence.InitialValue),
                           IntToStr(ASequence.Increment)]);
end;

function TDDLSQLGeneratorMSSQL.GenerateCreateTable(ATable: TTableMIK): String;
var
  oSQL: TStringBuilder;
  oColumn: TPair<String,TColumnMIK>;
begin
  oSQL := TStringBuilder.Create;
  Result := inherited GenerateCreateTable(ATable);
  try
    oSQL.Append(Format(Result, [_QualifyTable(ATable)]));
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
    /// Add ForeignKey
    /// </summary>
//    if ATable.ForeignKeys.Count > 0 then
//    begin
//      oSQL.Append(',');
//      oSQL.Append(BuilderForeignKeyDefinition(ATable));
//    end;
    /// <summary>
    /// Add Checks
    /// </summary>
    if ATable.Checks.Count > 0 then
    begin
      oSQL.Append(',');
      oSQL.Append(BuilderCheckDefinition(ATable));
    end;
    oSQL.AppendLine;
    oSQL.Append(');');
    /// <summary>
    /// Add Indexe
    /// </summary>
    if ATable.IndexeKeys.Count > 0 then
      oSQL.Append(BuilderIndexeDefinition(ATable));
    oSQL.AppendLine;
    Result := oSQL.ToString;
  finally
    oSQL.Free;
  end;
end;

function TDDLSQLGeneratorMSSQL.GenerateEnableForeignKeys(AEnable: Boolean): String;
begin
  if AEnable then
    Result := 'EXEC sp_MSforeachtable "ALTER TABLE ? WITH CHECK CHECK CONSTRAINT all";'
  else
    Result := 'EXEC sp_MSforeachtable "ALTER TABLE ? NOCHECK CONSTRAINT all";';
end;

function TDDLSQLGeneratorMSSQL.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  if AEnable then
    Result := 'EXEC sp_MSforeachtable "ALTER TABLE ? ENABLE TRIGGER ALL";'
  else
    Result := 'EXEC sp_MSforeachtable "ALTER TABLE ? DISABLE TRIGGER ALL";';
end;

function TDDLSQLGeneratorMSSQL.GenerateRenameColumn(AColumn: TColumnMIK;
  const ANewName: String): String;
begin
  // SQL Server nao tem RENAME COLUMN; usa a stored procedure sp_rename com o
  // qualificador 'COLUMN' e o alvo no formato 'tabela.coluna' ([schema].[tabela]
  // .coluna quando ha schema; default '' preserva 'tabela.coluna').
  Result := 'EXEC sp_rename ''%s.%s'', ''%s'', ''COLUMN'';';
  Result := Format(Result, [_QualifyTable(AColumn.Table), AColumn.Name, ANewName]);
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnMSSQL, TDDLSQLGeneratorMSSQL.Create);

end.
