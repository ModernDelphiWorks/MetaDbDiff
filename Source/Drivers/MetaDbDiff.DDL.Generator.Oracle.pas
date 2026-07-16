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

unit MetaDbDiff.DDL.Generator.Oracle;

interface

uses
  SysUtils,
  StrUtils,
  Variants,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.DDL.Register,
  MetaDbDiff.DDL.Generator,
  MetaDbDiff.Database.Mapping;

type
  TDDLSQLGeneratorOracle = class(TDDLSQLGenerator)
  protected
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
  end;

implementation

{ TDDLSQLGeneratorOracle }

function TDDLSQLGeneratorOracle.GenerateAlterColumn(AColumn: TColumnMIK): String;
begin
  // Oracle usa MODIFY (sem a palavra COLUMN): ALTER TABLE <tabela> MODIFY (<coluna> <definicao>);
  Result := 'ALTER TABLE %s MODIFY (%s);';
  Result := Format(Result, [AColumn.Table.Name, BuilderAlterFieldDefinition(AColumn)]);
end;

function TDDLSQLGeneratorOracle.GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String;
begin
  Result := 'ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s) %s ENABLE VALIDATE;';
  Result := Format(Result, [AForeignKey.Table.Name,
                            AForeignKey.Name,
                            GetForeignKeyFromColumnsDefinition(AForeignKey),
                            AForeignKey.FromTable,
                            GetForeignKeyToColumnsDefinition(AForeignKey),
                            GetRuleDeleteActionDefinition(AForeignKey.OnDelete)]);
end;

function TDDLSQLGeneratorOracle.GenerateCreateSequence(
  ASequence: TSequenceMIK): String;
begin
  Result := 'CREATE SEQUENCE %s MINVALUE 1 START WITH %s INCREMENT BY %s NOCACHE;'; // MAXVALUE ????? CACHE ??
  Result := Format(Result, [ASequence.Name,
                            IntToStr(ASequence.InitialValue),
                            IntToStr(ASequence.Increment)]);
end;

function TDDLSQLGeneratorOracle.GenerateCreateTable(ATable: TTableMIK): String;
var
  oSQL: TStringBuilder;
  oColumn: TPair<String, TColumnMIK>;
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

function TDDLSQLGeneratorOracle.GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  // No Oracle o indice e um objeto de schema; nao existe ALTER TABLE ... DROP INDEX.
  Result := 'DROP INDEX %s;';
  Result := Format(Result, [AIndexe.Name]);
end;

function TDDLSQLGeneratorOracle.GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP PRIMARY KEY;';
  Result := Format(Result, [APrimaryKey.Table.Name]);
end;

function TDDLSQLGeneratorOracle.GenerateEnableForeignKeys(AEnable: Boolean): String;
begin
  // Oracle nao possui comando global para habilitar/desabilitar FKs; gera um
  // bloco PL/SQL anonimo que itera USER_CONSTRAINTS (tipo 'R' = referential)
  // executando ENABLE/DISABLE CONSTRAINT em cada uma.
  if AEnable then
    Result := 'BEGIN' + sLineBreak +
              '  FOR c IN (SELECT table_name, constraint_name FROM user_constraints WHERE constraint_type = ''R'') LOOP' + sLineBreak +
              '    EXECUTE IMMEDIATE ''ALTER TABLE "'' || c.table_name || ''" ENABLE CONSTRAINT "'' || c.constraint_name || ''"'';' + sLineBreak +
              '  END LOOP;' + sLineBreak +
              'END;'
  else
    Result := 'BEGIN' + sLineBreak +
              '  FOR c IN (SELECT table_name, constraint_name FROM user_constraints WHERE constraint_type = ''R'') LOOP' + sLineBreak +
              '    EXECUTE IMMEDIATE ''ALTER TABLE "'' || c.table_name || ''" DISABLE CONSTRAINT "'' || c.constraint_name || ''"'';' + sLineBreak +
              '  END LOOP;' + sLineBreak +
              'END;';
end;

function TDDLSQLGeneratorOracle.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  // Oracle nao possui comando global para habilitar/desabilitar triggers; gera
  // um bloco PL/SQL anonimo que itera USER_TRIGGERS executando
  // ALTER TRIGGER ... ENABLE/DISABLE em cada uma.
  if AEnable then
    Result := 'BEGIN' + sLineBreak +
              '  FOR t IN (SELECT trigger_name FROM user_triggers) LOOP' + sLineBreak +
              '    EXECUTE IMMEDIATE ''ALTER TRIGGER "'' || t.trigger_name || ''" ENABLE'';' + sLineBreak +
              '  END LOOP;' + sLineBreak +
              'END;'
  else
    Result := 'BEGIN' + sLineBreak +
              '  FOR t IN (SELECT trigger_name FROM user_triggers) LOOP' + sLineBreak +
              '    EXECUTE IMMEDIATE ''ALTER TRIGGER "'' || t.trigger_name || ''" DISABLE'';' + sLineBreak +
              '  END LOOP;' + sLineBreak +
              'END;';
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnOracle, TDDLSQLGeneratorOracle.Create);

end.
