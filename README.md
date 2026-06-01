# MetaDbDiff Framework for Delphi

[![Delphi Supported Versions](https://img.shields.io/badge/Delphi%20Supported%20Versions-XE%2B-blue.svg)]()
[![License](https://img.shields.io/badge/Licence-LGPL--3.0-blue.svg)](https://opensource.org/licenses/LGPL-3.0)

*   [🇬🇧 English](#-english)
*   [🇧🇷 Português](#-português)

---

## 🇬🇧 English

**MetaDbDiff** (historically named **DBCBr** / **Database Comparer Brasil**) is a powerful database metadata comparison and DDL migration script generation engine for Delphi. 

Born out of the need for robust, standalone database maintenance, MetaDbDiff compares two database structures or compares a Delphi Pascal object-oriented ORM model class directly with a relational database. It then automatically generates highly precise DDL synchronization scripts (creating/dropping tables, columns, indexes, foreign keys, primary keys, and adjusting column types or sizes).

<p align="center">
  <a href="https://www.isaquepinheiro.com.br">
    <img src="https://github.com/HashLoad/DBCBr/blob/master/Images/dbcbr_framework.png" width="200" height="200" alt="MetaDbDiff Logo">
  </a>
</p>

### 🏛 Supported Platforms
*   **Delphi XE or superior** (VCL, FMX, Console, IDE)
*   **Lazarus / FreePascal** (Compatible Core)

### ⚙️ Installation
To install using [`boss`]:
```sh
boss install "https://github.com/ModernDelphiWorks/MetaDbDiff"
```

### ⚠ Dependencies
*   [DataEngine Framework](https://github.com/hashload/dbebr) (Uniform connection abstraction layer)

---

### 🚀 Key Features

*   **Model-to-Database Comparison:** Compares your active Delphi Pascal entity model classes (decorated with ORM attributes) against a physical database.
*   **Database-to-Database Comparison:** Compares a source database schema directly against a target database schema.
*   **Precise DDL Migration Scripts:** Generates exact SQL scripts to synchronize structures, supporting:
    *   **Tables:** `CREATE TABLE`, `DROP TABLE`
    *   **Columns:** `ADD COLUMN`, `DROP COLUMN`, `ALTER COLUMN` (type and size adjustments)
    *   **Constraints:** `ADD/DROP PRIMARY KEY`, `ADD/DROP FOREIGN KEY`
    *   **Performance:** `CREATE INDEX`, `DROP INDEX`
*   **Decoupled Architecture:** 100% focused on metadata comparison without being mixed into standard ORM persistence layers, making it highly modular and easy for the open-source community to contribute.

---

### ⛏️ Contributing
Our team would love to receive contributions to this open-source project. Feel free to open issues or submit pull requests.

### 📬 Contact & Support
*   **Telegram**: [HashLoad Channel](https://t.me/hashload)
*   **Website**: [isaquepinheiro.com.br](https://www.isaquepinheiro.com.br)

### 💲 Donation
[![Doação](https://img.shields.io/badge/PagSeguro-contribua-green)](https://pag.ae/bglQrWD)

---

## 🇧🇷 Português

**MetaDbDiff** (historicamente chamado de **DBCBr** / **Database Comparer Brasil**) é um poderoso motor de comparação de metadados e geração de scripts de migração DDL para Delphi.

Nascido da necessidade de manutenção estruturada e robusta de bancos de dados, o MetaDbDiff compara a estrutura entre duas bases de dados físicas ou compara uma classe de modelo objeto-relacional (ORM) escrita em Delphi Pascal diretamente com um banco de dados relacional. Ele gera de forma totalmente automática scripts DDL altamente precisos para atualizar os metadados (criar/remover tabelas, colunas, índices, chaves estrangeiras, chaves primárias, além de atualizar tipos e tamanhos de campos).

### 🏛 Plataformas Suportadas
*   **Delphi XE ou superior** (VCL, FMX, Console, IDE)
*   **Lazarus / FreePascal** (Core Compatível)

### ⚙️ Instalação
Para instalar usando o [`boss`]:
```sh
boss install "https://github.com/ModernDelphiWorks/MetaDbDiff"
```

### ⚠ Dependências
*   [DataEngine Framework](https://github.com/hashload/dbebr) (Camada uniforme de abstração de conexão)

---

### 🚀 Recursos Principais

*   **Comparação Modelo-para-Banco:** Compara as suas classes de modelo de entidade Delphi Pascal (decoradas com atributos de ORM) contra um banco de dados físico.
*   **Comparação Banco-para-Banco:** Compara o schema de um banco de dados de origem diretamente contra um banco de dados de destino.
*   **Scripts DDL Precisos:** Gera scripts SQL cirúrgicos para sincronizar as estruturas de banco de dados, com suporte a:
    *   **Tabelas:** `CREATE TABLE`, `DROP TABLE`
    *   **Colunas:** `ADD COLUMN`, `DROP COLUMN`, `ALTER COLUMN` (ajuste de tipos e tamanhos de campos)
    *   **Restrições:** `ADD/DROP PRIMARY KEY`, `ADD/DROP FOREIGN KEY`
    *   **Performance:** `CREATE INDEX`, `DROP INDEX`
*   **Arquitetura Desacoplada:** Código 100% independente e focado exclusivamente na comparação de banco de dados, sem estar misturado ao código principal de persistência ORM. Isso dá muito mais poder de ajuda para a comunidade open source evoluir a comparação estruturada de forma focada e limpa.

---

### ⛏️ Contribuição
Adoramos contribuições! Sinta-se à vontade para abrir issues ou enviar pull requests.

### 📬 Contato & Suporte
*   **Telegram**: [Canal HashLoad](https://t.me/hashload)
*   **Website**: [isaquepinheiro.com.br](https://www.isaquepinheiro.com.br)

### 💲 Doação
[![Doação](https://img.shields.io/badge/PagSeguro-contribua-green)](https://pag.ae/bglQrWD)

---
*Copyright © 2025-2026 Isaque Pinheiro. Licensed under LGPL-3.0 License.*
