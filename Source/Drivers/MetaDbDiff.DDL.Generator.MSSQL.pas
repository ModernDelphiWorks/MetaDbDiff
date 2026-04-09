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

unit MetaDbDiff.DDL.Generator.MSSQL;

interface

uses
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.Factory.Interfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorMSSQL = class(TDDLSQLGenerator)
  protected
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
  end;

implementation

{ TDDLSQLGeneratorMSSQL }

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

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnMSSQL, TDDLSQLGeneratorMSSQL.Create);

end.
