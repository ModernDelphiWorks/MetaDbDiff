---
displayed_sidebar: metadbdiffSidebar
title: Getting Started
sidebar_position: 2
---

# Getting Started

## Prerequisites

- Delphi XE or higher **or** Lazarus / FreePascal
- [Boss](https://github.com/HashLoad/boss) package manager **or** [pubpascal](https://www.pubpascal.dev) (CRA-ready SBOM portal)
- [DataEngine](https://github.com/ModernDelphiWorks/DataEngine) — connection abstraction layer (installed automatically as a Boss dependency)

## Installation

### Via Boss

```sh
boss install MetaDbDiff
```

Boss resolves the `DataEngine` dependency automatically from `boss.json`.

### Via pubpascal

MetaDbDiff is listed on [pubpascal.dev/packages/metadbdiff](https://www.pubpascal.dev/packages/metadbdiff) with a CycloneDX SBOM and security disclosure policy.

### Manual / search path

1. Clone or download the repository.
2. Add `Source/Core` and `Source/Drivers` to the Delphi / Lazarus project search path.
3. Add `DataEngine/Source` (from the DataEngine repo) to the same search path.

## Adding to your project search path

```
<project root>/boss_modules/MetaDbDiff/Source/Core
<project root>/boss_modules/MetaDbDiff/Source/Drivers
<project root>/boss_modules/DataEngine/Source
```

## Quick start: Model-to-Database

Decorate your entity class, then call `TDatabaseMapping.BuildDatabase`:

```delphi
uses
  MetaDbDiff.Mapping.Attributes,
  MetaDbDiff.Mapping.Register,
  MetaDbDiff.Database.Abstract,
  DataEngine.Factory.FireDAC;

// 1. Decorate a Delphi entity class
type
  [Table('CUSTOMERS')]
  [PrimaryKey('ID', TAutoIncType.AutoInc)]
  TCustomer = class
  private
    FId: Integer;
    FName: string;
    FEmail: string;
  public
    [Column('ID', ftInteger)]
    property Id: Integer read FId write FId;

    [Column('NAME', ftString, 100)]
    [NotNullConstraint]
    property Name: string read FName write FName;

    [Column('EMAIL', ftString, 200)]
    property Email: string read FEmail write FEmail;
  end;

// 2. Register the entity
// (Registration happens automatically when the unit is included in uses,
//  or explicitly via TMetaDbMappingRegister.RegisterClass)
TMetaDbMappingRegister.RegisterClass(TCustomer);

// 3. Build / sync the database
var
  LConn: IDBConnection;
  LMapping: TDatabaseMapping;
begin
  LConn := TFactoryFireDAC.Create(FDConnection1, dnFirebird);
  LMapping := TDatabaseMapping.Create(LConn);
  try
    LMapping.CommandsAutoExecute := True;  // execute DDL immediately
    LMapping.BuildDatabase;
  finally
    LMapping.Free;
  end;
end;
```

## Quick start: Database-to-Database

```delphi
uses
  MetaDbDiff.Database.Compare,
  DataEngine.Factory.FireDAC;

var
  LSourceConn: IDBConnection;
  LTargetConn: IDBConnection;
  LCompare: TDatabaseCompare;
begin
  LSourceConn := TFactoryFireDAC.Create(FDSourceConn, dnFirebird);
  LTargetConn := TFactoryFireDAC.Create(FDTargetConn, dnFirebird);

  LCompare := TDatabaseCompare.Create(LSourceConn, LTargetConn);
  try
    LCompare.CommandsAutoExecute := True;
    LCompare.BuildDatabase;
  finally
    LCompare.Free;
  end;
end;
```

## Inspecting the DDL command list without executing

Set `CommandsAutoExecute := False` (the default) and inspect `GetCommandList`:

```delphi
LMapping.CommandsAutoExecute := False;
LMapping.BuildDatabase;

for LCmd in LMapping.GetCommandList do
  Writeln(LCmd.BuildCommand(LMapping.GeneratorCommand));
```

## Enabling column-position reordering

By default columns are compared by definition only. To also reorder columns to match model position:

```delphi
LMapping.ComparerFieldPosition := True;
LMapping.BuildDatabase;
```

> **Note:** Column-position reordering is only supported by dialects that implement `GenerateAlterColumnPosition`. In the current driver set this is **Firebird** (`TDDLSQLGeneratorFirebird`), **Firebird 3** (`TDDLSQLGeneratorFirebird3`), and **InterBase** (`TDDLSQLGeneratorInterbase`) — the latter two inherit the implementation from the Firebird driver. All other bundled drivers (MySQL, PostgreSQL, MSSQL, Oracle, SQLite, AbsoluteDB) do not override this method, so column reordering has no effect for those dialects.
