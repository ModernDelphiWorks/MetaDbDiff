---
displayed_sidebar: metadbdiffSidebar
title: API Reference
sidebar_position: 5
---

# API Reference

This page documents every public type, interface, and attribute that consumers of MetaDbDiff interact with directly.

---

## MIK (MetaInfo Kind) — Internal Schema Model

Defined in `MetaDbDiff.Database.Mapping`.

### `TMetaInfoKind`

Abstract base for all MIK objects.

| Member | Type | Description |
|:---|:---|:---|
| `Description` | `string` (r/w) | Human-readable description |

---

### `TColumnMIK`

Represents a database column inside a `TTableMIK`.

| Property | Type | Description |
|:---|:---|:---|
| `Table` | `TTableMIK` | Owning table |
| `Name` | `string` (r/w) | Column name |
| `Position` | `Integer` (r/w) | Ordinal column position |
| `FieldType` | `TFieldType` (r/w) | Delphi field type |
| `TypeName` | `string` (r/w) | Native database type name |
| `Size` | `Integer` (r/w) | Character/byte length |
| `Precision` | `Integer` (r/w) | Numeric precision |
| `Scale` | `Integer` (r/w) | Numeric scale |
| `NotNull` | `Boolean` (r/w) | NOT NULL constraint |
| `AutoIncrement` | `Boolean` (r/w) | Auto-increment flag |
| `SortingOrder` | `TSortingOrder` (r/w) | ASC / DESC / NoSort |
| `DefaultValue` | `string` (r/w) | Column default expression |
| `IsPrimaryKey` | `Boolean` (r/w) | Whether column is part of the PK |
| `CharSet` | `string` (r/w) | Character set (e.g., `UTF8`) |

---

### `TTableMIK`

Represents a database table.

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Table name |
| `Description` | `string` (r/w) | Optional description |
| `Fields` | `TObjectDictionary<string, TColumnMIK>` (r) | Column map (key = column name upper-case) |
| `PrimaryKey` | `TPrimaryKeyMIK` (r/w) | Primary key descriptor |
| `IndexeKeys` | `TObjectDictionary<string, TIndexeKeyMIK>` (r) | Index map |
| `ForeignKeys` | `TObjectDictionary<string, TForeignKeyMIK>` (r) | FK map |
| `Checks` | `TObjectDictionary<string, TCheckMIK>` (r) | CHECK constraint map |
| `Triggers` | `TObjectDictionary<string, TTriggerMIK>` (r) | Trigger map |
| `Database` | `TCatalogMetadataMIK` (r) | Owning catalog |
| `FieldsSort` | `TArray<TPair<string, TColumnMIK>>` | Returns columns sorted alphabetically by key |

---

### `TPrimaryKeyMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Constraint name (e.g., `PK_CUSTOMERS`) |
| `AutoIncrement` | `Boolean` (r/w) | Auto-increment flag |
| `Fields` | `TObjectDictionary<string, TColumnMIK>` (r) | Column map |
| `Table` | `TTableMIK` (r) | Owning table |
| `FieldsSort` | `TArray<TPair<string, TColumnMIK>>` | Columns sorted alphabetically |

---

### `TForeignKeyMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Constraint name |
| `FromTable` | `string` (r/w) | Referencing table name |
| `FromFields` | `TObjectDictionary<string, TColumnMIK>` (r) | Referencing column map |
| `ToFields` | `TObjectDictionary<string, TColumnMIK>` (r) | Referenced column map |
| `OnUpdate` | `TRuleAction` (r/w) | Referential update action |
| `OnDelete` | `TRuleAction` (r/w) | Referential delete action |
| `Table` | `TTableMIK` (r) | Owning table |
| `FromFieldsSort` | `TArray<TPair<string, TColumnMIK>>` | Referencing columns sorted |
| `ToFieldsSort` | `TArray<TPair<string, TColumnMIK>>` | Referenced columns sorted |

---

### `TIndexeKeyMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Index name |
| `Unique` | `Boolean` (r/w) | Unique index flag |
| `Fields` | `TObjectDictionary<string, TColumnMIK>` (r) | Index column map |
| `Table` | `TTableMIK` (r) | Owning table |
| `FieldsSort` | `TArray<TPair<string, TColumnMIK>>` | Columns sorted alphabetically |

---

### `TSequenceMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Sequence / generator name |
| `InitialValue` | `Integer` (r/w) | Starting value |
| `Increment` | `Integer` (r/w) | Increment step |
| `TableName` | `string` (r/w) | Associated table (if any) |
| `Database` | `TCatalogMetadataMIK` (r) | Owning catalog |

---

### `TCheckMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Constraint name |
| `Condition` | `string` (r/w) | CHECK expression |
| `Table` | `TTableMIK` (r) | Owning table |

---

### `TTriggerMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Trigger name |
| `Script` | `string` (r/w) | Trigger body |
| `Table` | `TTableMIK` (r) | Owning table |

---

### `TViewMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | View name |
| `Script` | `string` (r/w) | View SELECT script |
| `Fields` | `TObjectDictionary<string, TColumnMIK>` (r/w) | Column map |
| `Database` | `TCatalogMetadataMIK` (r) | Owning catalog |

---

### `TCatalogMetadataMIK`

| Property | Type | Description |
|:---|:---|:---|
| `Name` | `string` (r/w) | Catalog/database name |
| `Schema` | `string` (r/w) | Schema name |
| `Tables` | `TObjectDictionary<string, TTableMIK>` (r) | Table map |
| `Sequences` | `TObjectDictionary<string, TSequenceMIK>` (r) | Sequence map |
| `Views` | `TObjectDictionary<string, TViewMIK>` (r) | View map |
| `TablesSort` | `TArray<TPair<string, TTableMIK>>` | Tables sorted alphabetically |
| `Clear` | procedure | Empties tables and sequences |

---

## DDL Generator Interface

Defined in `MetaDbDiff.DDL.Interfaces`.

### `IDDLGeneratorCommand`

Every DDL dialect driver implements this interface.

| Method | Description |
|:---|:---|
| `GenerateCreateTable(ATable)` | `CREATE TABLE` with all columns, PK, indexes, FKs, checks |
| `GenerateCreateColumn(AColumn)` | `ALTER TABLE ... ADD COLUMN` |
| `GenerateCreatePrimaryKey(APK)` | `ALTER TABLE ... ADD CONSTRAINT PK_...` |
| `GenerateCreateForeignKey(AFK)` | `ALTER TABLE ... ADD CONSTRAINT FK_...` |
| `GenerateCreateSequence(ASeq)` | `CREATE SEQUENCE / GENERATOR ...` |
| `GenerateCreateIndexe(AIdx)` | `CREATE [UNIQUE] INDEX ...` |
| `GenerateCreateCheck(ACheck)` | `ALTER TABLE ... ADD CONSTRAINT CHK_...` |
| `GenerateCreateView(AView)` | `CREATE OR REPLACE VIEW ...` |
| `GenerateCreateTrigger(ATrig)` | `CREATE TRIGGER ...` |
| `GenerateAlterColumn(AColumn)` | `ALTER TABLE ... ALTER COLUMN` |
| `GenerateAlterColumnPosition(AColumn)` | Reorder column (dialect-dependent) |
| `GenerateAlterDefaultValue(AColumn)` | Set column default |
| `GenerateAlterCheck(ACheck)` | Drop + recreate CHECK |
| `GenerateDropTable(ATable)` | `DROP TABLE` |
| `GenerateDropPrimaryKey(APK)` | `ALTER TABLE ... DROP CONSTRAINT PK_...` |
| `GenerateDropForeignKey(AFK)` | `ALTER TABLE ... DROP CONSTRAINT FK_...` |
| `GenerateDropSequence(ASeq)` | `DROP SEQUENCE / GENERATOR ...` |
| `GenerateDropIndexe(AIdx)` | `DROP INDEX ...` |
| `GenerateDropCheck(ACheck)` | `ALTER TABLE ... DROP CONSTRAINT CHK_...` |
| `GenerateDropView(AView)` | `DROP VIEW ...` |
| `GenerateDropTrigger(ATrig)` | `DROP TRIGGER ...` |
| `GenerateDropColumn(AColumn)` | `ALTER TABLE ... DROP COLUMN` |
| `GenerateDropDefaultValue(AColumn)` | Drop column default |
| `GenerateEnableForeignKeys(AEnable)` | Disable/enable all FK constraints |
| `GenerateEnableTriggers(AEnable)` | Disable/enable all triggers |
| `SupportedFeatures` | `TSupportedFeatures` set — `Sequences`, `ForeignKeys`, `Checks`, `Views`, `Triggers` |

---

## Database Compare Classes

### `IDatabaseCompare` (interface, `MetaDbDiff.Database.Interfaces`)

| Member | Type | Description |
|:---|:---|:---|
| `BuildDatabase` | procedure | Run the full compare+generate pipeline |
| `GetCommandList` | `TArray<TDDLCommand>` | Retrieve generated DDL command list |
| `GeneratorCommand` | `IDDLGeneratorCommand` | The dialect-specific generator |
| `CommandsAutoExecute` | `Boolean` (r/w) | If `True`, execute DDL on target immediately |
| `ComparerFieldPosition` | `Boolean` (r/w) | If `True`, also reorder columns |

### `TDatabaseCompare` (`MetaDbDiff.Database.Compare`)

Concrete class for Database-to-Database comparison.

```delphi
constructor Create(AConnMaster, AConnTarget: IDBConnection); overload;
```

Connects both databases on construction and raises if either fails to connect.

---

## Mapping Attributes

Defined in `MetaDbDiff.Mapping.Attributes`. These decorate Delphi entity classes for Model-to-Database mode.

| Attribute | Constructor signature | Description |
|:---|:---|:---|
| `Entity` | `Create(AName, ASchemaName: string)` | Marks a class as a mapped entity |
| `Table` | `Create(AName: string)` | Maps the class to a physical table |
| `View` | `Create(AName: string)` | Maps the class to a database view |
| `Column` | `Create(AColumnName, AFieldType, ASize)` | Column mapping with optional size/precision/scale |
| `PrimaryKey` | `Create(AColumns, AAutoIncType, AGeneratorType, ...)` | PK definition |
| `ForeignKey` | `Create(AName, AFromColumns, ATableNameRef, AToColumns, ARuleDelete, ARuleUpdate)` | FK definition |
| `Indexe` | `Create(AName, AColumns, ASortingOrder, AUnique)` | Index definition |
| `Sequence` | `Create(AName, AInitial, AIncrement)` | Sequence/generator definition |
| `Check` | `Create(AName, ACondition)` | CHECK constraint |
| `Association` | `Create(AMultiplicity, AColumnsName, ATableNameRef, AColumnsNameRef)` | ORM relationship |
| `JoinColumn` | `Create(AColumnName, ARefTableName, ARefColumnName, ARefColumnNameSelect, AJoin)` | JOIN mapping |
| `CascadeActions` | `Create(ACascadeActions: TCascadeActions)` | Cascade delete/update behaviour |
| `Trigger` | `Create(AName, ATableName)` | Trigger mapping |
| `Dictionary` | `Create(ADisplayLabel, AConstraintErrorMessage)` | UI metadata / display hints |
| `OrderBy` | `Create(AColumnsName)` | Default ORDER BY clause |
| `Restrictions` | `Create(ARestrictions: TRestrictions)` | Row-level filter restrictions |
| `NotNullConstraint` | `Create` | Validates field is not null/empty |
| `MinimumValueConstraint` | `Create(AValue: Double)` | Validates minimum numeric value |
| `MaximumValueConstraint` | `Create(AValue: Double)` | Validates maximum numeric value |
| `NotEmpty` | `Create` | Validates string/numeric field is not empty/zero |
| `Size` | `Create(Max, Min: Integer)` | Validates string length range |
| `NullIfEmpty` | — | Converts empty string to null |
| `CalcField` | `Create(AFieldName, AFieldType, ASize, AHidden)` | Calculated field mapping |
| `AggregateField` | `Create(AFieldName, AExpression, AAlignment, ADisplayFormat)` | Aggregate/display field |
| `Enumeration` | `Create(AEnumType, AEnumValues)` | Enum column mapping |
| `FieldEvents` | `Create(AFieldEvents: TFieldEvents)` | Field-level event hooks |

---

## Mapping Classes (`MetaDbDiff.Mapping.Classes`)

Internal runtime representation of attributes — populated by RTTI exploration.

| Class | Equivalent attribute |
|:---|:---|
| `TTableMapping` | `Table` |
| `TColumnMapping` | `Column` |
| `TPrimaryKeyMapping` | `PrimaryKey` |
| `TForeignKeyMapping` | `ForeignKey` |
| `TIndexeMapping` | `Indexe` |
| `TSequenceMapping` | `Sequence` |
| `TCheckMapping` | `Check` |
| `TTriggerMapping` | `Trigger` |
| `TAssociationMapping` | `Association` |
| `TJoinColumnMapping` | `JoinColumn` |
| `TViewMapping` | `View` |
| `TEnumerationMapping` | `Enumeration` |
| `TCalcFieldMapping` | `CalcField` |
| `TFieldEventsMapping` | `FieldEvents` |
| `TRestrictionMapping` | `Restrictions` |
| `TOrderByMapping` | `OrderBy` |

---

## Types (`MetaDbDiff.Types.Mapping`)

Key enumerations used across attributes and MIK objects.

<!-- TODO: confirm full enum member list from MetaDbDiff.Types.Mapping.pas -->

| Type | Members (partial) |
|:---|:---|
| `TSortingOrder` | `NoSort`, `Ascending`, `Descending` |
| `TMultiplicity` | `OneToOne`, `OneToMany`, `ManyToOne`, `ManyToMany` |
| `TRuleAction` | `None`, `Cascade`, `SetNull`, `SetDefault`, `Restrict` |
| `TGeneratorType` | `NoneInc`, `SequenceInc`, `TableInc`, `GuidInc` |
| `TAutoIncType` | `NotInc`, `AutoInc` |
| `TJoin` | `InnerJoin`, `LeftJoin`, `RightJoin`, `FullJoin` |
| `TSupportedFeature` | `Sequences`, `ForeignKeys`, `Checks`, `Views`, `Triggers` |
