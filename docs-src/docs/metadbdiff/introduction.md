---
displayed_sidebar: metadbdiffSidebar
title: Introduction
sidebar_position: 1
---

# Introduction

## What is MetaDbDiff?

**MetaDbDiff** is a database metadata comparison and DDL migration script generation engine for Delphi and Lazarus. It is entirely decoupled from any transactional ORM layer: it has one job — compare two schema descriptions and emit the SQL `ALTER`/`CREATE`/`DROP` statements required to reconcile them.

It serves two use-cases:

1. **Model-to-Database sync** — You decorate Delphi Pascal entity classes with attributes (`[Table]`, `[Column]`, `[PrimaryKey]`, `[ForeignKey]`, `[Indexe]`, etc.) and MetaDbDiff reads them via RTTI, extracts the live schema from the database through a `DataEngine` connection, then computes the diff.

2. **Database-to-Database sync** — You provide two `IDBConnection` handles (source/master and target). MetaDbDiff extracts both schemas and generates the DDL to evolve the target to match the source.

## Design goals

- **Surgical DDL**: no full-schema drops. Each command is as narrow as possible — `ALTER COLUMN` when only a type changes, `DROP INDEX` + `CREATE INDEX` when uniqueness changes, etc.
- **Driver isolation**: every database engine (Firebird, PostgreSQL, MySQL, MSSQL, Oracle, SQLite, Interbase, AbsoluteDB) implements `TDDLSQLGenerator` and registers itself in `TDDLRegister`. The core never references a dialect directly.
- **Feature flags**: dialects declare their capabilities via `TSupportedFeatures` (`Sequences`, `ForeignKeys`, `Checks`, `Views`, `Triggers`). The comparison engine guards every optional block with a feature check.
- **Transaction safety**: DDL commands are batched through `IDBConnection.AddScript` / `ExecuteScripts` / `Commit`; if any step raises the connection is rolled back.

## Core internal model (MIK layer)

All schema metadata — whether extracted from a live database or derived from RTTI entity classes — is translated into the **MIK** (MetaInfo Kind) object model before comparison:

| Class | Represents |
|:---|:---|
| `TCatalogMetadataMIK` | A full database catalog (tables, sequences, views) |
| `TTableMIK` | A single table with its columns, PK, indexes, FKs, checks, triggers |
| `TColumnMIK` | A column with name, type, size, precision, nullability, charset, position, default value |
| `TPrimaryKeyMIK` | A primary key with its constituent column set |
| `TForeignKeyMIK` | A foreign key with source/target column maps and referential actions |
| `TIndexeKeyMIK` | An index with its column set and uniqueness flag |
| `TCheckMIK` | A CHECK constraint |
| `TTriggerMIK` | A trigger (script) |
| `TViewMIK` | A database view |
| `TSequenceMIK` | A sequence / generator |

## Relation to Janus ORM

MetaDbDiff is the structural foundation used by the **Janus** ORM for its `BuildDatabase` / auto-migration feature. Janus registers its entity classes in the MetaDbDiff mapping registry; MetaDbDiff then computes and optionally executes the required DDL at startup. You can also use MetaDbDiff standalone — no Janus dependency is required.

## Dependency

MetaDbDiff requires **DataEngine** (`github.com/ModernDelphiWorks/DataEngine`) for the `IDBConnection` abstraction layer. DataEngine provides driver wrappers for FireDAC, DBX, Zeos, and others.
