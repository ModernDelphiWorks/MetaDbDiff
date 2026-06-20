---
displayed_sidebar: docsSidebar
title: MetaDbDiff
slug: /
sidebar_position: 0
---

Welcome to the **MetaDbDiff** technical documentation portal. Content is derived from source code, tests, and pipeline artifacts.

## Projects

<div className="row">
  <div className="col col--6 margin-bottom--lg">
    <div className="card">
      <div className="card__header">
        <h3>MetaDbDiff</h3>
      </div>
      <div className="card__body">
        <p>Database metadata comparison and DDL migration script generation engine for Delphi and Lazarus. Compare two physical database schemas, or compare a Delphi Pascal ORM entity model against an active database, and emit surgical DDL synchronization scripts. <strong>v2.0.0</strong> — supports Firebird, Firebird 3, Interbase, PostgreSQL, MySQL, MSSQL, Oracle, SQLite, and AbsoluteDB.</p>
      </div>
      <div className="card__footer">
        <a className="button button--primary" href="./metadbdiff/">Open documentation →</a>
      </div>
    </div>
  </div>
</div>

## Documented release

This portal matches the published **v2.0.0** tag, per `boss.json` and repository tags.

- **[2.0.0]** — Multi-dialect DDL engine: Firebird / Firebird 3 / Interbase / PostgreSQL / MySQL / MSSQL / Oracle / SQLite / AbsoluteDB. Decoupled metadata extraction layer (`TMetadataDBAbstract`). Full MIK (MetaInfo Kind) internal model (`TTableMIK`, `TColumnMIK`, `TPrimaryKeyMIK`, `TForeignKeyMIK`, `TIndexeKeyMIK`, `TCheckMIK`, `TViewMIK`, `TTriggerMIK`, `TCatalogMetadataMIK`). Column-position reordering via `ComparerFieldPosition`.

See [`IDDLGeneratorCommand`](./metadbdiff/reference-api) for the full DDL generation interface.
