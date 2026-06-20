# MetaDbDiff — Database metadata comparison & DDL migration-script generation engine for Delphi/Lazarus

[![Delphi XE+](https://img.shields.io/badge/Delphi-XE%20or%20superior-blue.svg)]()
[![Lazarus Compatible](https://img.shields.io/badge/Lazarus-Compatible-orange.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CRA-ready](https://img.shields.io/badge/CRA--ready-SBOM%20%2B%20Security%20policy-success)](https://www.pubpascal.dev/packages/metadbdiff)

> 🔒 **Supply-chain transparency (CRA-ready):** a machine-readable **SBOM** (CycloneDX) is published on the package portal — [pubpascal.dev/packages/metadbdiff](https://www.pubpascal.dev/packages/metadbdiff) · security disclosure policy in **[SECURITY.md](SECURITY.md)**.

📚 **[Documentation](https://moderndelphiworks.github.io/MetaDbDiff/)** · ⬇️ **[Download](../../releases)** · 🐛 **[Issues](../../issues)**

*   [🇬🇧 English](#-english)
*   [🇧🇷 Português](#-português)

---

## 🇬🇧 English

**MetaDbDiff** is a powerful and lightweight database metadata comparison and DDL migration-script generation engine for Delphi and Lazarus. It enables developers to compare two physical database schemas, or directly compare a Delphi Pascal entity ORM class model with an active database. From this comparison, MetaDbDiff automatically generates highly precise DDL synchronization scripts — covering tables, columns, column types, primary/foreign keys, and performance indices. Decoupled from persistent runtime ORM layers, it is highly modular, customizable, and serves as the structural foundation for advanced Object-Relational Mappers (such as **Janus**).

### 🚀 Key Features

*   **Model-to-Database Comparison:** Match your active Delphi Pascal entity classes (decorated with ORM attributes) directly against physical database schemas.
*   **Database-to-Database Comparison:** Directly compare structural schemas between two distinct databases (Source vs. Target).
*   **Precise DDL Migration Scripts:** Generates surgical SQL commands to synchronize structures:
    *   *Tables:* `CREATE TABLE` and `DROP TABLE`.
    *   *Columns:* `ADD COLUMN`, `DROP COLUMN`, and `ALTER COLUMN` (adjusting types and sizes).
    *   *Constraints:* `ADD/DROP PRIMARY KEY` and `ADD/DROP FOREIGN KEY`.
    *   *Performance:* `CREATE INDEX` and `DROP INDEX`.
*   **Decoupled Architecture:** 100% focused on database schema comparison, cleanly separated from transactional CRUD logic.
*   **Multi-Dialect Core:** Extensible driver serialization framework supporting major relational engines out of the box.

### 🏛️ Compatibility Matrix

| Environment / IDE | Platform / Compiler | Model-to-DB Sync | DB-to-DB Sync |
| :--- | :--- | :---: | :---: |
| **Delphi XE or superior** | VCL, FMX, Console, IDE (Win/Linux/macOS/iOS/Android) | ✅ Yes | ✅ Yes |
| **Lazarus / FreePascal** | LCL, Console (Cross-platform) | ✅ Yes | ✅ Yes |

### 🐧 Cross-Platform Build — Win32 / Win64 / Linux64

> **Win32 / Win64:** ✅ verified (2026-06-20, real production backend). **Linux64:** the units used by the backend compile on Linux; a **standalone full-framework Linux build** currently hits an **internal (non-platform) dependency item** — some `DataEngine` interface/type imports (`IDBConnection`, `TDriverName`) need their `uses` reconciled (the `DataEngine.Factory.Interfaces` vs `DataEngine.FactoryInterfaces` naming). Tracked as a follow-up — **not** a platform issue.

**Building a consumer app for Linux64:** install the Linux 64-bit platform (RAD Studio GetIt / `GetItCmd -if=delphi_linux -ae`), provide a Linux SDK (RAD Studio SDK Manager + PAServer, **or** a sysroot assembled from a WSL/Linux toolchain passed to `dcclinux64` via `--syslibroot` / `--libpath`), then compile with `dcclinux64`.

### ⚙️ Installation

Install via the [**Boss**](https://github.com/HashLoad/boss) package manager:

```sh
boss install MetaDbDiff
```

Or register via [**pubpascal.dev**](https://www.pubpascal.dev/packages/metadbdiff) for SBOM-tracked supply-chain installs.

### ⚠️ Dependencies

*   [DataEngine](https://github.com/HashLoad/DataEngine) — uniform connection abstraction layer.

---

### ⚡️ Quick Start

#### 1. Comparing a Pascal Model to a Physical Database

```delphi
uses
  MetaDbDiff.Comparer,
  MetaDbDiff.Interfaces,
  DataEngine.Factory.FireDAC;

var
  FConn: IDBConnection;
  FComparer: IMetaDbComparer;
  FDelta: IMetaDbDelta;
  FSQLScript: string;
begin
  // Wrap the active FireDAC connection
  FConn := TFactoryFireDAC.Create(FDConnection1, dnPostgreSQL);

  FComparer := TMetaDbComparer.Create(FConn);

  // Compare registered Pascal entity classes against the active database schema
  FDelta := FComparer.CompareModelToDatabase;

  if FDelta.HasDifferences then
  begin
    // Emit surgical DDL and apply it
    FSQLScript := FDelta.GenerateDDLScript;
    FConn.ExecuteDirect(FSQLScript);
  end;
end;
```

#### 2. Comparing Database to Database (Source vs. Target)

```delphi
uses
  MetaDbDiff.Comparer,
  MetaDbDiff.Interfaces;

var
  FComparer: IMetaDbComparer;
  FDelta: IMetaDbDelta;
  FSQLScript: string;
begin
  // Compare structural schemas between two physical database connections
  FComparer := TMetaDbComparer.Create(FSourceConn, FTargetConn);
  FDelta := FComparer.CompareDatabaseToDatabase;

  if FDelta.HasDifferences then
    FSQLScript := FDelta.GenerateDDLScript;
end;
```

---

## 🇧🇷 Português

**MetaDbDiff** é um motor poderoso e leve de comparação de metadados de banco de dados e geração de scripts de migração DDL para Delphi e Lazarus. Ele permite que desenvolvedores comparem dois schemas físicos de banco de dados, ou comparem diretamente uma classe de entidade Delphi Pascal com um banco de dados ativo. A partir dessa análise, o MetaDbDiff gera automaticamente scripts DDL cirúrgicos e altamente precisos para sincronização estrutural — incluindo tabelas, colunas, tipos de dados, chaves primárias/estrangeiras e índices de performance. Totalmente desacoplado de camadas ativas de ORM transacional, fornece a base estrutural para mapeadores avançados (como o **Janus**).

### 🚀 Recursos Principais

*   **Comparação Modelo-para-Banco:** Compare suas classes de entidades Delphi Pascal (decoradas com atributos de ORM) diretamente contra a estrutura física do banco.
*   **Comparação Banco-para-Banco:** Compare a estrutura de tabelas, chaves e índices diretamente entre duas conexões físicas distintas (Origem vs. Destino).
*   **Scripts DDL Cirúrgicos:** Gera instruções SQL precisas para sincronização de schemas:
    *   *Tabelas:* `CREATE TABLE` e `DROP TABLE`.
    *   *Colunas:* `ADD COLUMN`, `DROP COLUMN` e `ALTER COLUMN` (com ajuste de tipo de dados e tamanho).
    *   *Chaves:* `ADD/DROP PRIMARY KEY` e `ADD/DROP FOREIGN KEY`.
    *   *Performance:* `CREATE INDEX` e `DROP INDEX`.
*   **Arquitetura Desacoplada:** Código 100% focado em comparação e geração DDL, totalmente isolado de código CRUD de transações persistentes.
*   **Suporte Multi-Dialeto:** Framework modular de driver de serialização compatível com os principais motores relacionais do mercado.

### 🏛️ Matriz de Compatibilidade

| Ambiente / IDE | Plataforma / Compilador | Sinc Modelo-para-Banco | Sinc Banco-para-Banco |
| :--- | :--- | :---: | :---: |
| **Delphi XE ou superior** | VCL, FMX, Console, IDE (Win/Linux/macOS/iOS/Android) | ✅ Sim | ✅ Sim |
| **Lazarus / FreePascal** | LCL, Console (Multiplataforma) | ✅ Sim | ✅ Sim |

### 🐧 Build Multiplataforma — Win32 / Win64 / Linux64

> **Win32 / Win64:** ✅ verificado (2026-06-20, backend real em produção). **Linux64:** as units usadas pelo backend compilam no Linux; um **build standalone do framework completo** esbarra hoje num **item interno (não-plataforma)** — alguns imports de interface/tipo do `DataEngine` (`IDBConnection`, `TDriverName`) precisam ter o `uses` reconciliado (nomenclatura `DataEngine.Factory.Interfaces` vs `DataEngine.FactoryInterfaces`). Registrado como follow-up — **não** é um problema de plataforma.

**Para buildar um app consumidor no Linux64:** instale a plataforma Linux 64-bit (RAD Studio GetIt / `GetItCmd -if=delphi_linux -ae`), forneça um SDK Linux (SDK Manager do RAD Studio + PAServer, **ou** um sysroot montado de um toolchain WSL/Linux passado ao `dcclinux64` via `--syslibroot` / `--libpath`), e compile com `dcclinux64`.

### ⚙️ Instalação

Instale via gerenciador de pacotes [**Boss**](https://github.com/HashLoad/boss):

```sh
boss install MetaDbDiff
```

Ou registre-se via [**pubpascal.dev**](https://www.pubpascal.dev/packages/metadbdiff) para instalações com rastreamento SBOM na cadeia de suprimento.

### ⚠️ Dependências

*   [DataEngine](https://github.com/HashLoad/DataEngine) — camada uniforme de abstração de conexão.

---

### ⚡️ Início Rápido

#### 1. Comparando Modelo Pascal com Banco de Dados Ativo

```delphi
uses
  MetaDbDiff.Comparer,
  MetaDbDiff.Interfaces,
  DataEngine.Factory.FireDAC;

var
  FConn: IDBConnection;
  FComparer: IMetaDbComparer;
  FDelta: IMetaDbDelta;
  FSQLScript: string;
begin
  // Wrapper da conexão FireDAC ativa
  FConn := TFactoryFireDAC.Create(FDConnection1, dnPostgreSQL);

  FComparer := TMetaDbComparer.Create(FConn);

  // Compara as classes Pascal registradas contra a estrutura do banco físico
  FDelta := FComparer.CompareModelToDatabase;

  if FDelta.HasDifferences then
  begin
    // Emite o script DDL cirúrgico e aplica no banco
    FSQLScript := FDelta.GenerateDDLScript;
    FConn.ExecuteDirect(FSQLScript);
  end;
end;
```

#### 2. Comparando Banco com Banco (Origem vs. Destino)

```delphi
uses
  MetaDbDiff.Comparer,
  MetaDbDiff.Interfaces;

var
  FComparer: IMetaDbComparer;
  FDelta: IMetaDbDelta;
  FSQLScript: string;
begin
  // Compara metadados estruturais entre duas conexões físicas distintas
  FComparer := TMetaDbComparer.Create(FSourceConn, FTargetConn);
  FDelta := FComparer.CompareDatabaseToDatabase;

  if FDelta.HasDifferences then
    FSQLScript := FDelta.GenerateDDLScript;
end;
```

---

## ⛏️ Contributing / Contribuição

Contributions are welcome — bug reports, feature proposals, and pull requests all help move the project forward.
Contribuições são bem-vindas — relatórios de bug, propostas de funcionalidades e pull requests ajudam o projeto a evoluir.

[![Issues](https://img.shields.io/badge/Issues-channel-orange)](../../issues)

**How to contribute / Como contribuir:**

1. Fork the repository / Faça um fork do repositório.
2. Create a feature branch: `git checkout -b feat/my-feature`.
3. Commit your changes with a clear message / Faça commit das suas mudanças com uma mensagem clara.
4. Open a Pull Request targeting `main` / Abra um Pull Request para a branch `main`.
5. Describe what changed and why in the PR body / Descreva o que mudou e por quê no corpo do PR.

---

## 📬 Contact / Contato

[![Email](https://img.shields.io/badge/Email-isaquesp%40gmail.com-D14836?logo=gmail&logoColor=white)](mailto:isaquesp@gmail.com)

---

## 💲 Donation / Doação

If MetaDbDiff saves you time, consider supporting its development.
Se o MetaDbDiff economiza o seu tempo, considere apoiar o desenvolvimento.

[![Doação](https://img.shields.io/badge/PagSeguro-contribua-green)](https://pag.ae/bglQrWD)

---

## 📄 License / Licença

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
Distribuído sob a Licença MIT. Consulte [LICENSE](LICENSE) para detalhes.

*Copyright © 2025-2026 Isaque Pinheiro.*
