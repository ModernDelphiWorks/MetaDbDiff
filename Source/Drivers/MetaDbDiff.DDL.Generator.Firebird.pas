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

unit MetaDbDiff.DDL.Generator.Firebird;

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
  TDDLSQLGeneratorFirebird = class(TDDLSQLGenerator)
  protected
    function BuilderAlterFieldDefinition(AColumn: TColumnMIK): String; override;
  public
    // FRENTE 15: Firebird suporta DOMAINS e PROCEDURES/FUNCTIONS (RDB$). A
    // sintaxe CREATE/DROP DOMAIN e o repasse de script da base ja atendem.
    // Firebird3 e Interbase herdam este set (Interbase remove Procedures).
    function GetSupportedFeatures: TSupportedFeatures; override;
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateAlterSequence(ASequence: TSequenceMIK): String; override;
    function GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String; override;
    function GenerateDropSequence(ASequence: TSequenceMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
    function GenerateDropColumn(AColumn: TColumnMIK): String; override;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; override;
    function GenerateEnableTriggers(AEnable: Boolean): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateAlterColumnPosition(AColumn: TColumnMIK): String; override;
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String; override;
    function GenerateAlterDefaultValue(AColumn: TColumnMIK): String; override;
    function GenerateDropDefaultValue(AColumn: TColumnMIK): String; override;
    function GenerateCreateView(AView: TViewMIK): String; override;
  end;

implementation

{ TDDLSQLGeneratorFirebird }

function TDDLSQLGeneratorFirebird.GenerateAlterDefaultValue(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ALTER COLUMN %s SET DEFAULT %s;';
  Result := Format(Result, [AColumn.Table.Name,
                            AColumn.Name,
                            GetAlterFieldDefaultDefinition(AColumn)]);
end;

function TDDLSQLGeneratorFirebird.GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String;
begin
  Result := 'ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s) %s %s;';

  Result := Format(Result, [AForeignKey.Table.Name,
                            AForeignKey.Name,
                            GetForeignKeyFromColumnsDefinition(AForeignKey),
                            AForeignKey.FromTable,
                            GetForeignKeyToColumnsDefinition(AForeignKey),
                            GetRuleDeleteActionDefinition(AForeignKey.OnDelete),
                            GetRuleUpdateActionDefinition(AForeignKey.OnUpdate)]);
end;

function TDDLSQLGeneratorFirebird.GenerateCreateSequence(ASequence: TSequenceMIK): String;
begin
  Result := 'CREATE GENERATOR %s;';
  Result := Format(Result, [ASequence.Name]);
end;

function TDDLSQLGeneratorFirebird.GenerateAlterSequence(ASequence: TSequenceMIK): String;
begin
  // Firebird 2.5: apenas o VALOR CORRENTE do generator/sequence e alteravel
  // (ALTER SEQUENCE ... RESTART WITH == SET GENERATOR ... TO). O passo
  // (INCREMENT) NAO existe em 2.5 - so foi introduzido no Firebird 3
  // (ver TDDLSQLGeneratorFirebird3.GenerateAlterSequence). Por isso este override
  // emite somente RESTART WITH; uma divergencia apenas de Increment num alvo 2.5
  // nao pode ser corrigida por DDL (documentado; recriar o generator perderia o
  // valor corrente).
  Result := 'ALTER SEQUENCE %s RESTART WITH %d;';
  Result := Format(Result, [ASequence.Name, ASequence.InitialValue]);
end;

function TDDLSQLGeneratorFirebird.GenerateCreateTable(ATable: TTableMIK): String;
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
      LSQL.Append(BuilderCreateFieldDefinition(LColumn.Value));
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
    /// Add Indexe
    /// </summary>
    if ATable.IndexeKeys.Count > 0 then
      LSQL.Append(BuilderIndexeDefinition(ATable));
    LSQL.AppendLine;
    Result := LSQL.ToString;
  finally
    LSQL.Free;
  end;
end;

function TDDLSQLGeneratorFirebird.GenerateCreateView(AView: TViewMIK): String;
begin
  Result := 'CREATE VIEW %s AS %s;';
  Result := Format(Result, [AView.Name, AView.Script]);
end;

function TDDLSQLGeneratorFirebird.GenerateDropColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s DROP %s;';
  Result := Format(Result, [AColumn.Table.Name, AColumn.Name]);
end;

function TDDLSQLGeneratorFirebird.GenerateDropDefaultValue(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ALTER COLUMN %s DROP DEFAULT;';
  Result := Format(Result, [aColumn.Table.Name, AColumn.Name]);
end;

function TDDLSQLGeneratorFirebird.GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  Result := 'DROP INDEX %s ;';
  Result := Format(Result, [AIndexe.Name]);
end;

function TDDLSQLGeneratorFirebird.GenerateDropSequence(ASequence: TSequenceMIK): String;
begin
  Result := 'DROP GENERATOR %s;';
  Result := Format(Result, [ASequence.Name]);
end;

function TDDLSQLGeneratorFirebird.BuilderAlterFieldDefinition(AColumn: TColumnMIK): String;
begin
  Result := AColumn.Name + ' TYPE ' +
            GetFieldTypeDefinition(AColumn)    +
            GetFieldNotNullDefinition(AColumn);
end;

function TDDLSQLGeneratorFirebird.GenerateAlterColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ALTER COLUMN %s;';
  Result := Format(Result, [AColumn.Table.Name,
                            BuilderAlterFieldDefinition(AColumn)]);
end;

function TDDLSQLGeneratorFirebird.GenerateAlterColumnPosition(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ALTER COLUMN %s POSITION %D;';
  Result := Format(Result, [AColumn.Table.Name,
                            AColumn.Name,
                            AColumn.Position + 1]);
end;

function TDDLSQLGeneratorFirebird.GenerateRenameColumn(AColumn: TColumnMIK;
  const ANewName: String): String;
begin
  // Firebird/Interbase renomeiam coluna com ALTER COLUMN <atual> TO <novo>
  // (nao suportam a sintaxe RENAME COLUMN do padrao usada na base).
  Result := 'ALTER TABLE %s ALTER COLUMN %s TO %s;';
  Result := Format(Result, [AColumn.Table.Name, AColumn.Name, ANewName]);
end;

function TDDLSQLGeneratorFirebird.GetSupportedFeatures: TSupportedFeatures;
begin
  Result := inherited GetSupportedFeatures +
            [TSupportedFeature.Domains, TSupportedFeature.Procedures];
end;

function TDDLSQLGeneratorFirebird.GenerateEnableForeignKeys(AEnable: Boolean): String;
begin
  // Firebird nao possui comando para habilitar/desabilitar FKs em bloco nem
  // por sessao (a unica alternativa seria DROP/CREATE de cada constraint).
  // Retorna vazio; comandos vazios sao descartados pelo pipeline
  // (MetaDbDiff.Database.Compare -> Length(LCommand) > 0).
  Result := '';
end;

function TDDLSQLGeneratorFirebird.GenerateEnableTriggers(AEnable: Boolean): String;
begin
  // Atualiza somente triggers de usuario: RDB$SYSTEM_FLAG = 0/NULL exclui as
  // triggers de sistema e o NOT EXISTS em RDB$CHECK_CONSTRAINTS garante que as
  // triggers internas de constraint (CHECK) nunca sejam desativadas.
  if AEnable then
    Result := 'UPDATE RDB$TRIGGERS SET RDB$TRIGGER_INACTIVE = 0 ' +
              'WHERE RDB$TRIGGER_SOURCE IS NOT NULL AND ((RDB$SYSTEM_FLAG = 0) OR (RDB$SYSTEM_FLAG IS NULL)) ' +
              'AND NOT EXISTS (SELECT 1 FROM RDB$CHECK_CONSTRAINTS CK WHERE CK.RDB$TRIGGER_NAME = RDB$TRIGGERS.RDB$TRIGGER_NAME);'
  else
    Result := 'UPDATE RDB$TRIGGERS SET RDB$TRIGGER_INACTIVE = 1 ' +
              'WHERE RDB$TRIGGER_SOURCE IS NOT NULL AND ((RDB$SYSTEM_FLAG = 0) OR (RDB$SYSTEM_FLAG IS NULL)) ' +
              'AND NOT EXISTS (SELECT 1 FROM RDB$CHECK_CONSTRAINTS CK WHERE CK.RDB$TRIGGER_NAME = RDB$TRIGGERS.RDB$TRIGGER_NAME);';
end;

initialization
  TSQLDriverRegister.GetInstance.RegisterDriver(dnFirebird, TDDLSQLGeneratorFirebird.Create);

end.
