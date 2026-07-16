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

unit MetaDbDiff.DDL.Interfaces;

interface

uses
  MetaDbDiff.Database.Mapping;

type
  TSupportedFeature = (Sequences, ForeignKeys, Checks, Views, Triggers);
  TSupportedFeatures = set of TSupportedFeature;
  /// <summary>
  /// Class unit : MetaDbDiff.DDL.Generator.pas
  /// Class Name : TDDLSQLGeneratorAbstract
  /// </summary>
  IDDLGeneratorCommand = interface
    ['{9E14DD57-94B9-4117-982A-BB9E8CBA54C6}']
    function GenerateCreateTable(ATable: TTableMIK): String;
    function GenerateCreatePrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
    function GenerateCreateForeignKey(AForeignKey: TForeignKeyMIK): String;
    function GenerateCreateSequence(ASequence: TSequenceMIK): String;
    function GenerateCreateIndexe(AIndexe: TIndexeKeyMIK): String;
    function GenerateCreateCheck(ACheck: TCheckMIK): String;
    function GenerateCreateView(AView: TViewMIK): String;
    function GenerateCreateTrigger(ATrigger: TTriggerMIK): String;
    function GenerateCreateColumn(AColumn: TColumnMIK): String;
    function GenerateAlterColumn(AColumn: TColumnMIK): String;
    function GenerateAlterColumnPosition(AColumn: TColumnMIK): String;
    /// <summary>
    ///   DML de copia/backfill de coluna usada pela estrategia de rebuild seguro
    ///   (TAlterColumnRebuilder). ABackfillNull=False: UPDATE t SET AColumn =
    ///   CAST(ASourceColumn AS <tipo>). ABackfillNull=True: UPDATE t SET AColumn =
    ///   <default> WHERE AColumn IS NULL. O CAST pode variar por dialeto (override).
    /// </summary>
    function GenerateCopyColumnData(AColumn: TColumnMIK; const ASourceColumn: String;
      ABackfillNull: Boolean): String;
    /// <summary>
    ///   Rename de coluna por dialeto (Firebird ALTER COLUMN ... TO; PostgreSQL/
    ///   Oracle/MySQL 8+/SQLite 3.25+ RENAME COLUMN; MSSQL sp_rename). AColumn
    ///   carrega o nome atual + a tabela; ANewName e o destino.
    /// </summary>
    function GenerateRenameColumn(AColumn: TColumnMIK; const ANewName: String): String;
    function GenerateAlterDefaultValue(AColumn: TColumnMIK): String;
    function GenerateAlterCheck(ACheck: TCheckMIK): String;
    function GenerateAlterSequence(ASequence: TSequenceMIK): String;
    function GenerateDropTable(ATable: TTableMIK): String;
    function GenerateDropPrimaryKey(APrimaryKey: TPrimaryKeyMIK): String;
    function GenerateDropForeignKey(AForeignKey: TForeignKeyMIK): String;
    function GenerateDropSequence(ASequence: TSequenceMIK): String;
    function GenerateDropIndexe(AIndexe: TIndexeKeyMIK): String;
    function GenerateDropCheck(ACheck: TCheckMIK): String;
    function GenerateDropView(AView: TViewMIK): String;
    function GenerateDropTrigger(ATrigger: TTriggerMIK): String;
    function GenerateDropColumn(AColumn: TColumnMIK): String;
    function GenerateDropDefaultValue(AColumn: TColumnMIK): String;
    function GenerateEnableForeignKeys(AEnable: Boolean): String;
    function GenerateEnableTriggers(AEnable: Boolean): String;
    /// <summary>
    /// Propriedade para identificar os recursos de diferentes banco de dados
    /// usando o mesmo modelo.
    /// </summary>
    function GetSupportedFeatures: TSupportedFeatures;
    property SupportedFeatures: TSupportedFeatures read GetSupportedFeatures;
  end;

implementation

end.
