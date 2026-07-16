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

unit MetaDbDiff.DDL.Generator;

interface

uses
  DB,
  SysUtils,
  Generics.Collections,
  MetaDbDiff.DDL.Interfaces,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Types.Mapping;

type
  TDDLSQLGeneratorAbstract = class abstract(TInterfacedObject, IDDLGeneratorCommand)
  protected
    FConnection: IDBConnection;
  public
    function GenerateCreateTable(ATable: TTableMIK): String; virtual; abstract;
    function GenerateCreateColumn(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; virtual; abstract;
    function GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String; virtual; abstract;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; virtual; abstract;
    function GenerateCreateIndexe(AIndexe: TIndexeKeyMIK): String; virtual; abstract;
    function GenerateCreateCheck(ACheck: TCheckMIK): String; virtual; abstract;
    function GenerateCreateView(AView: TViewMIK): String; virtual; abstract;
    function GenerateCreateTrigger(ATrigger: TTriggerMIK): String; virtual; abstract;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateAlterColumnPosition(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateCopyColumnData(AColumn: TColumnMIK; const ASourceColumn: String;
      ABackfillNull: Boolean): String; virtual; abstract;
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String; virtual; abstract;
    function GenerateAlterDefaultValue(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateAlterCheck(ACheck: TCheckMIK): String; virtual; abstract;
    function GenerateAlterSequence(ASequence: TSequenceMIK): String; virtual; abstract;
    function GenerateAddPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; virtual; abstract;
    function GenerateDropTable(ATable: TTableMIK): String; virtual; abstract;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; virtual; abstract;
    function GenerateDropForeignKey(AForeignKey: TForeignKeyMIK): String; virtual; abstract;
    function GenerateDropSequence(ASequence: TSequenceMIK): String; virtual; abstract;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; virtual; abstract;
    function GenerateDropCheck(ACheck: TCheckMIK): String; virtual; abstract;
    function GenerateDropColumn(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateDropDefaultValue(AColumn: TColumnMIK): String; virtual; abstract;
    function GenerateDropView(AView: TViewMIK): String; virtual; abstract;
    function GenerateDropTrigger(ATrigger: TTriggerMIK): String; virtual; abstract;
    function GenerateEnableForeignKeys(AEnable: Boolean): String; virtual; abstract;
    function GenerateEnableTriggers(AEnable: Boolean): String; virtual; abstract;
    function GenerateCreateDomain(ADomain: TDomainMIK): String; virtual; abstract;
    function GenerateDropDomain(ADomain: TDomainMIK): String; virtual; abstract;
    function GenerateCreateProcedure(AProcedure: TProcedureMIK): String; virtual; abstract;
    function GenerateDropProcedure(AProcedure: TProcedureMIK): String; virtual; abstract;
    function GenerateSetComment(ATable: TTableMIK; AColumn: TColumnMIK): String; virtual; abstract;
    /// <summary>
    /// Propriedade para identificar os recursos de diferentes banco de dados
    /// usando o mesmo modelo.
    /// </summary>
    function GetSupportedFeatures: TSupportedFeatures; virtual; abstract;
    property SupportedFeatures: TSupportedFeatures read GetSupportedFeatures;
  end;

  TDDLSQLGenerator = class(TDDLSQLGeneratorAbstract)
  protected
    /// <summary>
    ///   Schema-aware compare (FRENTE 14). Qualifica um nome de objeto com o
    ///   schema quando este e nao-vazio. Implementacao base (dialetos sem schema
    ///   - Firebird/SQLite/MySQL): retorna o nome cru (ignora o schema como
    ///   documentado). Os generators PostgreSQL/MSSQL sobrescrevem para aplicar
    ///   o quoting proprio ("schema"."nome" / [schema].[nome]). Com ASchema=''
    ///   (default) TODOS retornam apenas AName, preservando o SQL historico.
    /// </summary>
    class function _QualifyName(const ASchema, AName: String): String; virtual;
    /// <summary>
    ///   Conveniencia: qualifica o nome da tabela com o schema do proprio
    ///   catalogo (ATable.Database.Schema), via _QualifyName (despacho virtual
    ///   pelo dialeto concreto).
    /// </summary>
    function _QualifyTable(ATable: TTableMIK): String;
    function GetRuleDeleteActionDefinition(ARuleAction: TRuleAction): String;
    function GetRuleUpdateActionDefinition(ARuleAction: TRuleAction): String;
    function GetPrimaryKeyColumnsDefinition(APrimaryKey: TPrimaryKeyMIK): String;
    function GetForeignKeyFromColumnsDefinition(AForeignKey: TForeignKeyMIK): String;
    function GetForeignKeyToColumnsDefinition(AForeignKey: TForeignKeyMIK): String;
    function GetIndexeKeyColumnsDefinition(AIndexeKey: TIndexeKeyMIK): String;
    function GetUniqueColumnDefinition(AUnique: Boolean): String;
    function GetFieldTypeDefinition(AColumn: TColumnMIK): String;
    function GetFieldNotNullDefinition(AColumn: TColumnMIK): String;
    function GetCreateFieldDefaultDefinition(AColumn: TColumnMIK): String;
    function GetAlterFieldDefaultDefinition(AColumn: TColumnMIK): String;
    // Shared helpers for GetCreateFieldDefaultDefinition/GetAlterFieldDefaultDefinition:
    // quote a textual DEFAULT value's literal so it produces valid SQL, without
    // touching values that are already quoted or known functions/keywords.
    function IsTextualFieldType(const AFieldType: TFieldType): Boolean;
    function IsAlreadyQuoted(const AValue: String): Boolean;
    function IsKnownFunctionOrKeyword(const AValue: String): Boolean;
    function QuoteDefaultValueIfNeeded(AColumn: TColumnMIK; const AValue: String): String;
    function BuilderCreateFieldDefinition(AColumn: TColumnMIK): String; virtual;
    function BuilderAlterFieldDefinition(AColumn: TColumnMIK): String; virtual;
    function BuilderPrimayKeyDefinition(ATable: TTableMIK): String; virtual;
    function BuilderIndexeDefinition(ATable: TTableMIK): String; virtual;
    function BuilderForeignKeyDefinition(ATable: TTableMIK): String; virtual;
    function BuilderCheckDefinition(ATable: TTableMIK): String; virtual;
  public
    function GenerateCreateTable(ATable: TTableMIK): String; override;
    function GenerateCreateColumn(AColumn: TColumnMIK): String; override;
    function GenerateCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String; override;
    function GenerateCreateView(AView: TViewMIK): String; override;
    function GenerateCreateTrigger(ATrigger: TTriggerMIK): String; override;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String; override;
    function GenerateCreateIndexe(AIndexe: TIndexeKeyMIK): String; override;
    function GenerateCreateCheck(ACheck: TCheckMIK): String; override;
    function GenerateAlterColumn(AColumn: TColumnMIK): String; override;
    function GenerateCopyColumnData(AColumn: TColumnMIK; const ASourceColumn: String;
      ABackfillNull: Boolean): String; override;
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String; override;
    function GenerateAlterCheck(ACheck: TCheckMIK): String; override;
    function GenerateAlterSequence(ASequence: TSequenceMIK): String; override;
    function GenerateAddPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropTable(ATable: TTableMIK): String; override;
    function GenerateDropColumn(AColumn: TColumnMIK): String; override;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String; override;
    function GenerateDropForeignKey(AForeignKey: TForeignKeyMIK): String; override;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String; override;
    function GenerateDropCheck(ACheck: TCheckMIK): String; override;
    function GenerateDropView(AView: TViewMIK): String; override;
    function GenerateDropTrigger(ATrigger: TTriggerMIK): String; override;
    function GenerateDropSequence(ASequence: TSequenceMIK): String; override;
    // FRENTE 15. Sintaxe ANSI/comum (CREATE DOMAIN ... AS ...; DROP DOMAIN ...;
    // COMMENT ON ...) - dialetos que divergem sobrescrevem. Procedimentos apenas
    // repassam o Script COMPLETO ja extraido do banco; o DROP escolhe PROCEDURE ou
    // FUNCTION conforme AProcedure.IsFunction.
    function GenerateCreateDomain(ADomain: TDomainMIK): String; override;
    function GenerateDropDomain(ADomain: TDomainMIK): String; override;
    function GenerateCreateProcedure(AProcedure: TProcedureMIK): String; override;
    function GenerateDropProcedure(AProcedure: TProcedureMIK): String; override;
    function GenerateSetComment(ATable: TTableMIK; AColumn: TColumnMIK): String; override;
    /// <summary>
    /// Propriedade para identificar os recursos de diferentes banco de dados
    /// usando o mesmo modelo.
    /// </summary>
    function GetSupportedFeatures: TSupportedFeatures; override;
    property SupportedFeatures: TSupportedFeatures read GetSupportedFeatures;
  end;

implementation

uses
  StrUtils;

{ TDDLSQLGenerator }

class function TDDLSQLGenerator._QualifyName(const ASchema, AName: String): String;
begin
  // Base (dialetos sem schema): schema.nome generico quando ha schema; caso
  // contrario apenas o nome. Na pratica esses dialetos sempre chegam com
  // ASchema='' (o extractor nao preenche schema), entao retorna o nome cru.
  if ASchema <> '' then
    Result := ASchema + '.' + AName
  else
    Result := AName;
end;

function TDDLSQLGenerator._QualifyTable(ATable: TTableMIK): String;
begin
  Result := _QualifyName(ATable.Database.Schema, ATable.Name);
end;

function TDDLSQLGenerator.GenerateCreateTable(ATable: TTableMIK): String;
begin
  Result := 'CREATE TABLE %s (';
end;

function TDDLSQLGenerator.GenerateCreateTrigger(ATrigger: TTriggerMIK): String;
begin
  Result := 'CREATE TRIGGER %s AS %s;';
  Result := Format(Result, [ATrigger.Name, ATrigger.Script]);
end;

function TDDLSQLGenerator.GenerateCreateView(AView: TViewMIK): String;
begin
  Result := 'CREATE VIEW %s AS %s;';
  Result := Format(Result, [AView.Name, AView.Script]);
end;

function TDDLSQLGenerator.GenerateDropTable(ATable: TTableMIK): String;
begin
  Result := 'DROP TABLE %s;';
  Result := Format(Result, [_QualifyTable(ATable)]);
end;

function TDDLSQLGenerator.GenerateDropTrigger(ATrigger: TTriggerMIK): String;
begin
  Result := 'DROP TRIGGER %s;';
  Result := Format(Result, [ATrigger.Name]);
end;

function TDDLSQLGenerator.GenerateDropView(AView: TViewMIK): String;
begin
  Result := 'DROP VIEW %s;';
  Result := Format(Result, [AView.Name]);
end;

function TDDLSQLGenerator.GenerateAddPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'ALTER TABLE %s ADD PRIMARY KEY (%s);';
  Result := Format(Result, [_QualifyTable(APrimaryKey.Table),
                            GetPrimaryKeyColumnsDefinition(APrimaryKey)]);
end;

function TDDLSQLGenerator.GenerateAlterColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ALTER COLUMN %s;';
  Result := Format(Result, [_QualifyTable(AColumn.Table), BuilderAlterFieldDefinition(AColumn)]);
end;

function TDDLSQLGenerator.GenerateCopyColumnData(AColumn: TColumnMIK;
  const ASourceColumn: String; ABackfillNull: Boolean): String;
begin
  // Backfill: preenche linhas NULL com o DefaultValue antes de aplicar NOT NULL.
  if ABackfillNull then
  begin
    Result := 'UPDATE %s SET %s = %s WHERE %s IS NULL;';
    Result := Format(Result, [_QualifyTable(AColumn.Table),
                              AColumn.Name,
                              QuoteDefaultValueIfNeeded(AColumn, AColumn.DefaultValue),
                              AColumn.Name]);
  end
  else
  begin
    // Copia com CAST da coluna de origem para o novo tipo. CAST(x AS <tipo>) e
    // ANSI e funciona em Firebird/PostgreSQL/Oracle/MySQL/MSSQL; dialetos cuja
    // sintaxe de cast difira sobrescrevem este metodo.
    Result := 'UPDATE %s SET %s = CAST(%s AS %s);';
    Result := Format(Result, [_QualifyTable(AColumn.Table),
                              AColumn.Name,
                              ASourceColumn,
                              Trim(GetFieldTypeDefinition(AColumn))]);
  end;
end;

function TDDLSQLGenerator.GenerateRenameColumn(AColumn: TColumnMIK;
  const ANewName: String): String;
begin
  // Sintaxe ANSI/portavel: PostgreSQL, Oracle, MySQL 8.0+, SQLite 3.25+.
  // Firebird usa "ALTER COLUMN ... TO" e MSSQL usa sp_rename (overrides).
  Result := 'ALTER TABLE %s RENAME COLUMN %s TO %s;';
  Result := Format(Result, [_QualifyTable(AColumn.Table), AColumn.Name, ANewName]);
end;

function TDDLSQLGenerator.GenerateCreateCheck(ACheck: TCheckMIK): String;
begin
  Result := 'CONSTRAINT %s CHECK (%s)';
  Result := Format(Result, [ACheck.Name, ACheck.Condition]);
end;

function TDDLSQLGenerator.GenerateAlterCheck(ACheck: TCheckMIK): String;
begin
  Result := 'ALTER TABLE %s ADD CONSTRAINT %s CHECK (%s);';
  Result := Format(Result, [_QualifyTable(ACheck.Table),  ACheck.Name, ACheck.Condition]);
end;

function TDDLSQLGenerator.GenerateAlterSequence(ASequence: TSequenceMIK): String;
begin
  // Sintaxe SQL:2003 (ANSI) suportada por PostgreSQL, SQL Server 2012+ e
  // Firebird 3+: reinicia o valor corrente e ajusta o passo. Dialetos que
  // divergem (Firebird 2.5 sem INCREMENT, Oracle sem RESTART) sobrescrevem.
  Result := 'ALTER SEQUENCE %s RESTART WITH %d INCREMENT BY %d;';
  Result := Format(Result, [ASequence.Name,
                            ASequence.InitialValue,
                            ASequence.Increment]);
end;

function TDDLSQLGenerator.GenerateCreateColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s ADD %s;';
  Result := Format(Result, [_QualifyTable(AColumn.Table), BuilderCreateFieldDefinition(AColumn)]);
end;

function TDDLSQLGenerator.GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String;
begin
  Result := 'ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s) %s %s';
  Result := Format(Result, [_QualifyTable(AForeignKey.Table),
                            AForeignKey.Name,
                            GetForeignKeyFromColumnsDefinition(AForeignKey),
                            // Tabela referenciada esta no mesmo schema (compare
                            // single-schema) - qualifica-a tambem.
                            _QualifyName(AForeignKey.Table.Database.Schema, AForeignKey.FromTable),
                            GetForeignKeyToColumnsDefinition(AForeignKey),
                            GetRuleDeleteActionDefinition(AForeignKey.OnDelete),
                            GetRuleUpdateActionDefinition(AForeignKey.OnUpdate)]);
  Result := Trim(Result) + ';';
end;

function TDDLSQLGenerator.GenerateCreateIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  Result := 'CREATE %s INDEX %s ON %s (%s);';
  Result := Format(Result, [GetUniqueColumnDefinition(AIndexe.Unique),
                            AIndexe.Name,
                            _QualifyTable(AIndexe.Table),
                            GetIndexeKeyColumnsDefinition(AIndexe)]);
end;

function TDDLSQLGenerator.GenerateCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'CONSTRAINT %s PRIMARY KEY (%s)';
  Result := Format(Result, [APrimaryKey.Name,
                            GetPrimaryKeyColumnsDefinition(APrimaryKey)]);
end;

function TDDLSQLGenerator.GenerateCreateSequence(ASequence: TSequenceMIK): String;
begin
  Result := '';
end;

function TDDLSQLGenerator.GenerateDropColumn(AColumn: TColumnMIK): String;
begin
  Result := 'ALTER TABLE %s DROP COLUMN %s;';
  Result := Format(Result, [_QualifyTable(AColumn.Table), AColumn.Name]);
end;

function TDDLSQLGenerator.GenerateDropForeignKey(AForeignKey: TForeignKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP CONSTRAINT %s;';
  Result := Format(Result, [_QualifyTable(AForeignKey.Table), AForeignKey.Name]);
end;

function TDDLSQLGenerator.GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
begin
  Result := 'DROP INDEX %s ON %s;';
  Result := Format(Result, [AIndexe.Name, _QualifyTable(AIndexe.Table)]);
end;

function TDDLSQLGenerator.GenerateDropCheck(ACheck: TCheckMIK): String;
begin
  Result := 'ALTER TABLE %s DROP CONSTRAINT %s;';
  Result := Format(Result, [_QualifyTable(ACheck.Table), ACheck.Name]);
end;

function TDDLSQLGenerator.GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
begin
  Result := 'ALTER TABLE %s DROP CONSTRAINT %s;';
  Result := Format(Result, [_QualifyTable(APrimaryKey.Table), APrimaryKey.Name]);
end;

function TDDLSQLGenerator.GenerateDropSequence(ASequence: TSequenceMIK): String;
begin
  Result := 'DROP SEQUENCE %s;';
  Result := Format(Result, [ASequence.Name]);
end;

function TDDLSQLGenerator.IsTextualFieldType(const AFieldType: TFieldType): Boolean;
begin
  Result := AFieldType in [ftString, ftWideString, ftFixedChar,
                            ftFixedWideChar, ftMemo, ftWideMemo];
end;

function TDDLSQLGenerator.IsAlreadyQuoted(const AValue: String): Boolean;
begin
  // Length >= 2 guard: a lone apostrophe ("'") must NOT be treated as an
  // already-quoted value (its single char would otherwise satisfy both the
  // opening and closing quote check), or it would be emitted unescaped.
  Result := (Length(AValue) >= 2) and
            (AValue[1] = '''') and
            (AValue[Length(AValue)] = '''');
end;

function TDDLSQLGenerator.IsKnownFunctionOrKeyword(const AValue: String): Boolean;
var
  LValue: String;
begin
  LValue := AnsiUpperCase(Trim(AValue));
  Result := (LValue = 'CURRENT_TIMESTAMP') or
            (LValue = 'CURRENT_DATE') or
            (LValue = 'CURRENT_TIME') or
            (LValue = 'NOW()') or
            (LValue = 'NULL');
end;

function TDDLSQLGenerator.QuoteDefaultValueIfNeeded(AColumn: TColumnMIK;
  const AValue: String): String;
begin
  Result := AValue;
  // Textual columns need their default literal quoted, otherwise the DDL
  // is invalid (e.g. DEFAULT SEM NOME instead of DEFAULT 'SEM NOME').
  // Values already quoted or known functions/keywords are left untouched,
  // and non-textual columns keep the original (unquoted) behavior.
  if IsTextualFieldType(AColumn.FieldType) and
     not IsAlreadyQuoted(Result) and
     not IsKnownFunctionOrKeyword(Result) then
    Result := QuotedStr(Result);
end;

function TDDLSQLGenerator.GetAlterFieldDefaultDefinition(AColumn: TColumnMIK): String;
begin
  if Length(AColumn.DefaultValue) = 0 then
    Exit('');
  Result := QuoteDefaultValueIfNeeded(AColumn, AColumn.DefaultValue);
end;

function TDDLSQLGenerator.GetCreateFieldDefaultDefinition(AColumn: TColumnMIK): String;
begin
  if Length(AColumn.DefaultValue) = 0 then
    Exit('');
  Result := ' DEFAULT ' + QuoteDefaultValueIfNeeded(AColumn, AColumn.DefaultValue);
end;

function TDDLSQLGenerator.BuilderAlterFieldDefinition(AColumn: TColumnMIK): String;
begin
  Result := AColumn.Name + ' ' +
            GetFieldTypeDefinition(AColumn)    +
//            GetAlterFieldDefaultDefinition(AColumn) +
            GetFieldNotNullDefinition(AColumn) ;
end;

function TDDLSQLGenerator.BuilderCheckDefinition(ATable: TTableMIK): String;
var
  oCheck: TPair<String,TCheckMIK>;
begin
  Result := '';
  for oCheck in ATable.Checks do
  begin
    Result := Result + sLineBreak;
    Result := Result + '  ' + GenerateCreateCheck(oCheck.Value);
  end;
end;

function TDDLSQLGenerator.BuilderCreateFieldDefinition(AColumn: TColumnMIK): String;
begin
  Result := AColumn.Name + ' ' +
            GetFieldTypeDefinition(AColumn) +
            GetCreateFieldDefaultDefinition(AColumn) +
            GetFieldNotNullDefinition(AColumn) ;
end;

function TDDLSQLGenerator.BuilderForeignKeyDefinition(ATable: TTableMIK): String;
var
  oForeignKey: TPair<String,TForeignKeyMIK>;
begin
  Result := '';
  for oForeignKey in ATable.ForeignKeys do
  begin
    Result := Result + sLineBreak;
    Result := Result + '  ' + GenerateCreateForeignKey(oForeignKey.Value);
  end;
end;

function TDDLSQLGenerator.GetFieldNotNullDefinition(AColumn: TColumnMIK): String;
begin
  Result := ifThen(AColumn.NotNull, ' NOT NULL', '');
end;

function TDDLSQLGenerator.GetFieldTypeDefinition(AColumn: TColumnMIK): String;
var
  LResult: String;
begin
  LResult := AColumn.TypeName + IfThen(Length(AColumn.CharSet) > 0, ' CHARACTER SET ' + AColumn.CharSet, '');
  LResult := StringReplace(LResult, '%l', IntToStr(AColumn.Size), [rfIgnoreCase]);
  LResult := StringReplace(LResult, '%p', IntToStr(AColumn.Precision), [rfIgnoreCase]);
  LResult := StringReplace(LResult, '%s', IntToStr(AColumn.Scale), [rfIgnoreCase]);
  Result  := ' ' + LResult;
end;

function TDDLSQLGenerator.BuilderIndexeDefinition(ATable: TTableMIK): String;
var
  oIndexe: TPair<String,TIndexeKeyMIK>;
begin
  Result := '';
  for oIndexe in ATable.IndexeKeys do
  begin
    Result := Result + sLineBreak;
    Result := Result + GenerateCreateIndexe(oIndexe.Value);
  end;
end;

function TDDLSQLGenerator.BuilderPrimayKeyDefinition(ATable: TTableMIK): String;
begin
  Result := '  ' + GenerateCreatePrimaryKey(ATable.PrimaryKey);
end;

function TDDLSQLGenerator.GetRuleDeleteActionDefinition(ARuleAction: TRuleAction): String;
begin
  Result := '';
  if      ARuleAction in [TRuleAction.Cascade]    then Result := 'ON DELETE CASCADE'
  else if ARuleAction in [TRuleAction.SetNull]    then Result := 'ON DELETE SET NULL'
  else if ARuleAction in [TRuleAction.SetDefault] then Result := 'ON DELETE SET DEFAULT';
end;

function TDDLSQLGenerator.GetRuleUpdateActionDefinition(ARuleAction: TRuleAction): String;
begin
  Result := '';
  if      ARuleAction in [TRuleAction.Cascade]    then Result := 'ON UPDATE CASCADE'
  else if ARuleAction in [TRuleAction.SetNull]    then Result := 'ON UPDATE SET NULL'
  else if ARuleAction in [TRuleAction.SetDefault] then Result := 'ON UPDATE SET DEFAULT';
end;

function TDDLSQLGenerator.GetSupportedFeatures: TSupportedFeatures;
begin
  // Base historica: os 5 recursos originais. Domains/Procedures (FRENTE 15) NAO
  // entram aqui - cada dialeto que os implementa os adiciona no seu override.
  Result := [TSupportedFeature.Sequences,
             TSupportedFeature.ForeignKeys,
             TSupportedFeature.Checks,
             TSupportedFeature.Views,
             TSupportedFeature.Triggers];
end;

function TDDLSQLGenerator.GenerateCreateDomain(ADomain: TDomainMIK): String;
begin
  // Sintaxe comum a Firebird e PostgreSQL: CREATE DOMAIN <n> AS <tipo>
  // [DEFAULT <x>] [NOT NULL] [CHECK (<cond>)]. O TypeName ja vem resolvido pelo
  // extractor (ex.: 'VARCHAR(20)'); nao aplicamos placeholders %l/%p/%s aqui.
  Result := 'CREATE DOMAIN ' + ADomain.Name + ' AS ' + ADomain.TypeName;
  if Trim(ADomain.DefaultValue) <> '' then
    Result := Result + ' DEFAULT ' + ADomain.DefaultValue;
  if ADomain.NotNull then
    Result := Result + ' NOT NULL';
  if Trim(ADomain.CheckCondition) <> '' then
    Result := Result + ' CHECK (' + ADomain.CheckCondition + ')';
  Result := Result + ';';
end;

function TDDLSQLGenerator.GenerateDropDomain(ADomain: TDomainMIK): String;
begin
  Result := Format('DROP DOMAIN %s;', [ADomain.Name]);
end;

function TDDLSQLGenerator.GenerateCreateProcedure(AProcedure: TProcedureMIK): String;
begin
  // O script extraido do banco (pg_get_functiondef / sys.sql_modules.definition /
  // RDB$PROCEDURES source) ja E o CREATE completo: apenas o repassamos. O
  // executor roda 1 comando por chamada, entao NAO ha necessidade de SET TERM
  // (terminador) na API - documentado no cabecalho da FRENTE 15.
  Result := AProcedure.Script;
end;

function TDDLSQLGenerator.GenerateDropProcedure(AProcedure: TProcedureMIK): String;
begin
  if AProcedure.IsFunction then
    Result := Format('DROP FUNCTION %s;', [AProcedure.Name])
  else
    Result := Format('DROP PROCEDURE %s;', [AProcedure.Name]);
end;

function TDDLSQLGenerator.GenerateSetComment(ATable: TTableMIK;
  AColumn: TColumnMIK): String;
begin
  // COMMENT ON e padrao em PostgreSQL, Firebird e Oracle. Exatamente um dos
  // argumentos e nao-nil (garantido pelo comando/factory).
  if AColumn <> nil then
    Result := Format('COMMENT ON COLUMN %s.%s IS %s;',
      [_QualifyTable(AColumn.Table), AColumn.Name, QuotedStr(AColumn.Description)])
  else
    Result := Format('COMMENT ON TABLE %s IS %s;',
      [_QualifyTable(ATable), QuotedStr(ATable.Description)]);
end;

function TDDLSQLGenerator.GetUniqueColumnDefinition(AUnique: Boolean): String;
begin
  Result := ifThen(AUnique, 'UNIQUE', '');
end;

function TDDLSQLGenerator.GetForeignKeyFromColumnsDefinition(AForeignKey: TForeignKeyMIK): String;
var
  oColumn: TPair<String,TColumnMIK>;
begin
  for oColumn in AForeignKey.FromFieldsSort do
    Result := Result + oColumn.Value.Name + ', ';
  Result := Trim(Result);
  Delete(Result, Length(Result), 1);
end;

function TDDLSQLGenerator.GetForeignKeyToColumnsDefinition(AForeignKey: TForeignKeyMIK): String;
var
  oColumn: TPair<String,TColumnMIK>;
begin
  for oColumn in AForeignKey.ToFieldsSort do
    Result := Result + oColumn.Value.Name + ', ';
  Result := Trim(Result);
  Delete(Result, Length(Result), 1);
end;

function TDDLSQLGenerator.GetIndexeKeyColumnsDefinition(AIndexeKey: TIndexeKeyMIK): String;
var
  oColumn: TPair<String,TColumnMIK>;
begin
  for oColumn in AIndexeKey.FieldsSort do
    Result := Result + oColumn.Value.Name + ', ';
  Result := Trim(Result);
  Delete(Result, Length(Result), 1);
end;

function TDDLSQLGenerator.GetPrimaryKeyColumnsDefinition(APrimaryKey: TPrimaryKeyMIK): String;
var
  oColumn: TPair<String,TColumnMIK>;
begin
  for oColumn in APrimaryKey.FieldsSort do
    Result := Result + oColumn.Value.Name + ', ';
  Result := Trim(Result);
  Delete(Result, Length(Result), 1);
end;

end.
