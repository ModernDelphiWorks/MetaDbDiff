---
displayed_sidebar: metadbdiffSidebar
title: Troubleshooting
sidebar_position: 6
---

# Troubleshooting

## Connection errors

### "Não foi possivel fazer conexão com o banco de dados Master"

`TDatabaseCompare.Create` connects both databases immediately. This exception means the **master** (source) connection could not be established.

**Checklist:**
- Verify `IDBConnection` is created with the correct `TDriverName` (`dnFirebird`, `dnPostgreSQL`, etc.).
- Call `IDBConnection.Connect` and check `IsConnected` before passing to `TDatabaseCompare`.
- Confirm the server address, port, database file path, and credentials in your `TFDConnection` (or equivalent).

### "Não foi possivel fazer conexão com o banco de dados Target"

Same as above but for the **target** connection.

---

## DDL execution errors

### "DBCBr Command : [&lt;warning&gt;] - &lt;exception&gt;\nScript : &lt;sql&gt;"

Thrown by `TDatabaseCompare.ExecuteDDLCommands` when a DDL command fails. The exception wraps:
- `LDDLCommand.Warning` — which command caused the failure (e.g., `"Alter Column: EMAIL"`)
- The original exception message
- The SQL string that was attempted

**Steps:**
1. Note the `Warning` field — it identifies the exact operation.
2. Execute the SQL string manually against the target database to see the full engine error.
3. Common causes:
   - Column referenced by an FK cannot be dropped without dropping the FK first (check FK detection logic).
   - Type change incompatible with existing data (e.g., `VARCHAR(50)` → `INTEGER` with existing text data).
   - Insufficient privileges for DDL.

---

## Schema comparison issues

### Foreign key is not being created

**Possible causes:**
- The dialect does not include `ForeignKeys` in `SupportedFeatures` — check `TDDLSQLGenerator*.GetSupportedFeatures`.
- The target table for the FK does not exist yet in the target database at the time FK commands run. MetaDbDiff processes FKs last but if the referenced table itself is new it must have been created earlier in the same batch. <!-- TODO: confirm ordering guarantee for new tables -->

### Columns are not being reordered

Column-position reordering is disabled by default. Enable it:

```delphi
LMapping.ComparerFieldPosition := True;
```

Not all dialects implement `GenerateAlterColumnPosition`. For those that do not, the method returns an empty string and the command is silently skipped.

### Check constraints are not generated

The dialect must include `Checks` in `TSupportedFeatures`. Verify the concrete generator class overrides `GetSupportedFeatures` and includes `TSupportedFeature.Checks`.

### Sequences are ignored for SQLite

SQLite does not support sequences — `TSupportedFeature.Sequences` is not in its feature set. This is by design.

---

## Build / compile issues

### "Unit not found: DataEngine.Factory.Interfaces"

MetaDbDiff requires DataEngine. Install it:

```sh
boss install github.com/ModernDelphiWorks/DataEngine
```

Or add `DataEngine/Source` to the project search path manually.

### Linux64 standalone build fails with interface/type import error

The units consumed by backend applications compile and run on Linux64. A full standalone framework build (including DataEngine) hits a naming discrepancy between `DataEngine.Factory.Interfaces` and `DataEngine.FactoryInterfaces` in some DataEngine versions. This is a known follow-up item — not a platform issue. Workaround: use the version of DataEngine that matches the `boss.json` pin in the MetaDbDiff repository.

---

## Runtime errors

### Exception in `TDatabaseMapping` with no clear message

Enable `CommandsAutoExecute := False` and iterate `GetCommandList` to find the offending command before execution:

```delphi
for LCmd in LMapping.GetCommandList do
  Writeln(LCmd.Warning, ' → ', LCmd.BuildCommand(LMapping.GeneratorCommand));
```

### `TColumnMIK.CharSet` mismatch causes unexpected ALTER COLUMN

MetaDbDiff compares `CharSet` only when the master column has a non-empty `CharSet`. If you are migrating between databases with different default character sets, explicitly set `CharSet` on the master side or suppress charset comparison by ensuring master columns have an empty `CharSet`.

---

## Getting help

- GitHub Issues: [github.com/ModernDelphiWorks/MetaDbDiff/issues](https://github.com/ModernDelphiWorks/MetaDbDiff/issues)
- Security disclosures: see [SECURITY.md](https://github.com/ModernDelphiWorks/MetaDbDiff/blob/main/SECURITY.md)
- Package portal (SBOM): [pubpascal.dev/packages/metadbdiff](https://www.pubpascal.dev/packages/metadbdiff)
