---
displayed_sidebar: metadbdiffSidebar
title: MetaDbDiff Overview
sidebar_position: 0
---

# MetaDbDiff

**MetaDbDiff** (v2.0.0) is a lightweight database metadata comparison and DDL migration script generation engine for Delphi and Lazarus.

## What it does

| Capability | Description |
|:---|:---|
| **Model → Database** | Compare decorated Delphi Pascal entity classes against a physical database schema and emit surgical DDL to close the gap. |
| **Database → Database** | Compare two live databases (source vs. target) and emit DDL to bring the target in line with the source. |
| **DDL Generation** | Generates `CREATE TABLE`, `DROP TABLE`, `ADD/DROP COLUMN`, `ALTER COLUMN`, `ADD/DROP PRIMARY KEY`, `ADD/DROP FOREIGN KEY`, `CREATE/DROP INDEX`, `CREATE/DROP SEQUENCE`, `CREATE/DROP VIEW`, `CREATE/DROP TRIGGER`, and `CHECK` constraint statements. |
| **Multi-dialect** | Firebird 2.x, Firebird 3, Interbase, PostgreSQL, MySQL, MSSQL, Oracle, SQLite, AbsoluteDB. |
| **Decoupled** | Zero transactional/CRUD code — purely structural comparison and DDL emission. |

## Quick links

- [Introduction](./introduction) — architectural concepts and design goals
- [Getting Started](./getting-started) — install and first run
- [Guide: Compare Schemas](./guide-compare-schemas) — step-by-step comparison workflows
- [Guide: Generate DDL](./guide-generate-ddl) — producing and executing migration scripts
- [API Reference](./reference-api) — full interface and class catalogue
- [Troubleshooting](./troubleshooting) — common errors and fixes

## Compatibility

| Environment | Platform | Model→DB | DB→DB |
|:---|:---|:---:|:---:|
| Delphi XE or higher | VCL, FMX, Console (Win/Linux/macOS/iOS/Android) | Yes | Yes |
| Lazarus / FreePascal | LCL, Console (cross-platform) | Yes | Yes |
