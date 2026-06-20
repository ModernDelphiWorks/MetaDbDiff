---
displayed_sidebar: metadbdiffSidebar
title: Guide — Generate DDL Scripts
sidebar_position: 4
---

# Guide: Generate DDL Scripts

After the comparison engine produces the `TDDLCommand` list, you can either execute commands immediately or collect the SQL text for review.

## Automatic execution

Set `CommandsAutoExecute := True` before calling `BuildDatabase`. The engine will:

1. Open a transaction on the **target** connection.
2. Call `BuildCommand` on each `TDDLCommand`, passing the dialect's `IDDLGeneratorCommand`.
3. Feed each non-empty SQL string to `IDBConnection.AddScript`.
4. Call `ExecuteScripts` then `Commit`.
5. On any exception, call `Rollback` and re-raise with context (command warning + SQL string).

```delphi
LCompare.CommandsAutoExecute := True;
LCompare.BuildDatabase;  // executes DDL in a single transaction
```

## Manual / dry-run mode

Leave `CommandsAutoExecute := False` (default). After `BuildDatabase` you can iterate:

```delphi
LCompare.CommandsAutoExecute := False;
LCompare.BuildDatabase;

var
  LSL: TStringList;
  LCmd: TDDLCommand;
  LSQL: string;
begin
  LSL := TStringList.Create;
  try
    for LCmd in LCompare.GetCommandList do
    begin
      LSQL := LCmd.BuildCommand(LCompare.GeneratorCommand);
      if Length(LSQL) > 0 then
        LSL.Add(LSQL);
    end;
    LSL.SaveToFile('migration.sql');
  finally
    LSL.Free;
  end;
end;
```

## The DDL command hierarchy

Every command descends from `TDDLCommand` and overrides `BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String`.

| Class | DDL verb |
|:---|:---|
| `TDDLCommandCreateTable` | `CREATE TABLE` (with columns, PK, indexes, FKs, checks) |
| `TDDLCommandDropTable` | `DROP TABLE` |
| `TDDLCommandCreateColumn` | `ALTER TABLE ... ADD COLUMN` |
| `TDDLCommandDropColumn` | `ALTER TABLE ... DROP COLUMN` |
| `TDDLCommandAlterColumn` | `ALTER TABLE ... ALTER COLUMN` (type/size/nullability change) |
| `TDDLCommandAlterColumnPosition` | Reorder column (dialect-dependent) |
| `TDDLCommandAlterDefaultValue` | Set column default value |
| `TDDLCommandDropDefaultValue` | Drop column default value |
| `TDDLCommandCreatePrimaryKey` | `ALTER TABLE ... ADD CONSTRAINT PK_...` |
| `TDDLCommandDropPrimaryKey` | `ALTER TABLE ... DROP CONSTRAINT PK_...` |
| `TDDLCommandCreateForeignKey` | `ALTER TABLE ... ADD CONSTRAINT FK_...` |
| `TDDLCommandDropForeignKey` | `ALTER TABLE ... DROP CONSTRAINT FK_...` |
| `TDDLCommandCreateIndexe` | `CREATE [UNIQUE] INDEX ...` |
| `TDDLCommandDropIndexe` | `DROP INDEX ...` |
| `TDDLCommandCreateSequence` | `CREATE SEQUENCE / GENERATOR ...` |
| `TDDLCommandDropSequence` | `DROP SEQUENCE / GENERATOR ...` |
| `TDDLCommandCreateView` | `CREATE OR REPLACE VIEW ...` |
| `TDDLCommandDropView` | `DROP VIEW ...` |
| `TDDLCommandCreateTrigger` | `CREATE TRIGGER ...` |
| `TDDLCommandDropTrigger` | `DROP TRIGGER ...` |
| `TDDLCommandCreateCheck` | `ALTER TABLE ... ADD CONSTRAINT CHK_...` |
| `TDDLCommandDropCheck` | `ALTER TABLE ... DROP CONSTRAINT CHK_...` |
| `TDDLCommandAlterCheck` | Drop + recreate a CHECK constraint |
| `TDDLCommandEnableForeignKeys` | Enable/disable all FKs (dialect-specific syntax) |
| `TDDLCommandEnableTriggers` | Enable/disable all triggers (dialect-specific syntax) |

## Supported dialects and driver units

| Dialect | Driver unit |
|:---|:---|
| Firebird 2.x | `MetaDbDiff.DDL.Generator.Firebird` |
| Firebird 3 | `MetaDbDiff.DDL.Generator.Firebird3` |
| Interbase | `MetaDbDiff.DDL.Generator.Interbase` |
| PostgreSQL | `MetaDbDiff.DDL.Generator.PostgreSQL` |
| MySQL | `MetaDbDiff.DDL.Generator.MySQL` |
| MSSQL (SQL Server) | `MetaDbDiff.DDL.Generator.MSSQL` |
| Oracle | `MetaDbDiff.DDL.Generator.Oracle` |
| SQLite | `MetaDbDiff.DDL.Generator.SQLite` |
| AbsoluteDB | `MetaDbDiff.DDL.Generator.AbsoluteDB` |

The correct generator is selected automatically from `DataEngine`'s `TDriverName` enum based on the connection's declared driver. No manual wiring is needed.

## Example: Firebird table creation

For a `TCustomer` entity with a `NAME VARCHAR(100)` column, MetaDbDiff generates:

```sql
CREATE TABLE CUSTOMERS (
  ID INTEGER NOT NULL,
  NAME VARCHAR(100) NOT NULL,
  EMAIL VARCHAR(200),
  CONSTRAINT PK_CUSTOMERS PRIMARY KEY (ID)
);
```

The exact syntax (keyword casing, quoting, sequence/generator naming) is handled by `TDDLSQLGeneratorFirebird`.

## Saving generated SQL to a file

```delphi
var
  LScript: TStringList;
  LCmd: TDDLCommand;
  LSQL: string;
begin
  LScript := TStringList.Create;
  try
    for LCmd in LMapping.GetCommandList do
    begin
      LSQL := LCmd.BuildCommand(LMapping.GeneratorCommand);
      if Length(LSQL) > 0 then
      begin
        LScript.Add('-- ' + LCmd.Warning);
        LScript.Add(LSQL);
        LScript.Add('');
      end;
    end;
    LScript.SaveToFile('migration_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.sql');
  finally
    LScript.Free;
  end;
end;
```

`TDDLCommand.Warning` contains a human-readable description (e.g., `"Create Table: CUSTOMERS"`, `"Alter Column: NAME"`).
