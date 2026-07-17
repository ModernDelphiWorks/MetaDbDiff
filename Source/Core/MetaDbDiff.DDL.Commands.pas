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

unit MetaDbDiff.DDL.Commands;

interface

uses
  SysUtils,
  StrUtils,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.DDL.Interfaces;

type
  TDDLCommand = class abstract
  protected
    FWarning: String;
    FCommand: String;
  public
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; virtual; abstract;
    /// <summary>
    ///   Anexa uma nota (ex.: aviso de risco da estrategia de alter column) ao
    ///   Warning existente. Nunca silencioso: o texto aparece no relatorio e no
    ///   script. So APPEND - jamais sobrescreve o prefixo parseavel do Warning.
    /// </summary>
    procedure AppendWarning(const AText: String);
    property Warning: String read FWarning;
    property Command: String read FCommand;
  end;

  TDDLCommandCreateTable = class(TDDLCommand)
  strict private
    FTable: TTableMIK;
  public
    constructor Create(ATable: TTableMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateSequence = class(TDDLCommand)
  strict private
    FSequence: TSequenceMIK;
  public
    constructor Create(ASequence: TSequenceMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandAlterSequence = class(TDDLCommand)
  strict private
    FSequence: TSequenceMIK;
  public
    constructor Create(ASequence: TSequenceMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateColumn = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandAlterColumn = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
    /// <summary>
    ///   Coluna MASTER (estado desejado) desta alteracao. Exposta somente-leitura
    ///   para o TAlterColumnRebuilder decidir a estrategia sem parsear o Warning.
    /// </summary>
    property Column: TColumnMIK read FColumn;
  end;

  TDDLCommandAlterColumnPosition = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandAlterDefaultValue = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreatePrimaryKey = class(TDDLCommand)
  strict private
    FPrimaryKey: TPrimaryKeyMIK;
  public
    constructor Create(APrimaryKey: TPrimaryKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateForeignKey = class(TDDLCommand)
  strict private
    FForeignKey: TForeignKeyMIK;
  public
    constructor Create(AForeignKey: TForeignKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateIndexe = class(TDDLCommand)
  strict private
    FIndexe: TIndexeKeyMIK;
  public
    constructor Create(AIndexe: TIndexeKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateCheck = class(TDDLCommand)
  strict private
    FCheck: TCheckMIK;
  public
    constructor Create(ACheck: TCheckMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandAlterCheck = class(TDDLCommand)
  strict private
    FCheck: TCheckMIK;
  public
    constructor Create(ACheck: TCheckMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateView = class(TDDLCommand)
  strict private
    FView: TViewMIK;
  public
    constructor Create(AView: TViewMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateTrigger = class(TDDLCommand)
  strict private
    FTrigger: TTriggerMIK;
  public
    constructor Create(ATrigger: TTriggerMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropTable = class(TDDLCommand)
  strict private
    FTable: TTableMIK;
  public
    constructor Create(ATable: TTableMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropSequence = class(TDDLCommand)
  strict private
    FSequence: TSequenceMIK;
  public
    constructor Create(ASequence: TSequenceMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropForeignKey = class(TDDLCommand)
  strict private
    FForeignKey: TForeignKeyMIK;
  public
    constructor Create(AForeignKey: TForeignKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropPrimaryKey = class(TDDLCommand)
  strict private
    FPrimaryKey: TPrimaryKeyMIK;
  public
    constructor Create(APrimaryKey: TPrimaryKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropColumn = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropDefaultValue = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
  public
    constructor Create(AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropIndexe = class(TDDLCommand)
  strict private
    FIndexe: TIndexeKeyMIK;
  public
    constructor Create(AIndexe: TIndexeKeyMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropCheck = class(TDDLCommand)
  strict private
    FCheck: TCheckMIK;
  public
    constructor Create(ACheck: TCheckMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropView = class(TDDLCommand)
  strict private
    FView: TViewMIK;
  public
    constructor Create(AView: TViewMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropTrigger = class(TDDLCommand)
  strict private
    FTrigger: TTriggerMIK;
  public
    constructor Create(ATrigger: TTriggerMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandEnableForeignKeys = class(TDDLCommand)
  strict private
    FEnable: Boolean;
  public
    constructor Create(AEnable: Boolean);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandEnableTriggers = class(TDDLCommand)
  strict private
    FEnable: Boolean;
  public
    constructor Create(AEnable: Boolean);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  { --- FRENTE 15: Domains / Procedures / Comments --- }

  TDDLCommandCreateDomain = class(TDDLCommand)
  strict private
    FDomain: TDomainMIK;
  public
    constructor Create(ADomain: TDomainMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropDomain = class(TDDLCommand)
  strict private
    FDomain: TDomainMIK;
  public
    constructor Create(ADomain: TDomainMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandCreateProcedure = class(TDDLCommand)
  strict private
    FProcedure: TProcedureMIK;
  public
    constructor Create(AProcedure: TProcedureMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  TDDLCommandDropProcedure = class(TDDLCommand)
  strict private
    FProcedure: TProcedureMIK;
  public
    constructor Create(AProcedure: TProcedureMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  /// <summary>
  ///   COMMENT ON TABLE/COLUMN. Carrega o objeto-alvo: exatamente UM de
  ///   FTable/FColumn e nao-nil (o construtor exige). Um FColumn nao-nil produz
  ///   COMMENT ON COLUMN; caso contrario COMMENT ON TABLE.
  /// </summary>
  TDDLCommandSetComment = class(TDDLCommand)
  strict private
    FTable: TTableMIK;
    FColumn: TColumnMIK;
  public
    constructor Create(ATable: TTableMIK; AColumn: TColumnMIK);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  { --- Safe ALTER COLUMN rebuild commands (FRENTE 11) --- }

  /// <summary>
  ///   CREATE da coluna temporaria <nome>_MDBTMP dentro de uma sequencia de
  ///   rebuild. Reusa a geracao de TDDLCommandCreateColumn; a subclasse existe
  ///   apenas para o Sequencer manter o comando na fase COLUMNS e para a policy
  ///   classifica-lo como RebuildColumn (nao como CreateColumn generico).
  /// </summary>
  TDDLCommandCreateColumnRebuild = class(TDDLCommandCreateColumn);

  /// <summary>
  ///   DROP da coluna original dentro de uma sequencia de rebuild. Reusa a
  ///   geracao de TDDLCommandDropColumn; a subclasse existe para o Sequencer
  ///   NAO mover este drop para a fase 'Drop Columns' (que roda ANTES da fase
  ///   COLUMNS e destruiria a coluna antes da copia dos dados) e para a policy
  ///   classifica-lo como RebuildColumn.
  /// </summary>
  TDDLCommandDropColumnRebuild = class(TDDLCommandDropColumn);

  /// <summary>
  ///   Copia/backfill de dados de coluna (DML) usada no rebuild:
  ///   - modo copia (ABackfillNull=False): UPDATE <t> SET <col> = CAST(<origem> AS <tipo>)
  ///   - modo backfill (ABackfillNull=True): UPDATE <t> SET <col> = <default> WHERE <col> IS NULL
  /// </summary>
  TDDLCommandCopyColumnData = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
    FSourceColumn: String;
    FBackfillNull: Boolean;
  public
    constructor Create(AColumn: TColumnMIK; const ASourceColumn: String;
      ABackfillNull: Boolean);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

  /// <summary>
  ///   RENAME de coluna (por dialeto) usado no rebuild para devolver o nome
  ///   original a coluna temporaria. AColumn carrega o nome ATUAL (temporario) e
  ///   a tabela; ANewName e o nome de destino.
  /// </summary>
  TDDLCommandRenameColumn = class(TDDLCommand)
  strict private
    FColumn: TColumnMIK;
    FNewName: String;
  public
    constructor Create(AColumn: TColumnMIK; const ANewName: String);
    function BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String; override;
  end;

implementation

{ TDDLCommandCreateTable }

function TDDLCommandCreateTable.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateTable(FTable);
  Result := FCommand;
end;

constructor TDDLCommandCreateTable.Create(ATable: TTableMIK);
begin
  FTable := ATable;
  FWarning := Format('Create Table: %s', [ATable.Name]);
end;

{ TDDLCommandDropSequence }

function TDDLCommandDropSequence.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropSequence(FSequence);
  Result := FCommand;
end;

constructor TDDLCommandDropSequence.Create(ASequence: TSequenceMIK);
begin
  FSequence := ASequence;
  FWarning := Format('Drop Sequence: %s', [ASequence.Name]);
end;

{ TDDLCommandDropForeignKey }

function TDDLCommandDropForeignKey.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropForeignKey(FForeignKey);
  Result := FCommand;
end;

constructor TDDLCommandDropForeignKey.Create(AForeignKey: TForeignKeyMIK);
begin
  FForeignKey := AForeignKey;
  FWarning := Format('Drop ForeignKey: %s', [AForeignKey.Name]);
end;

{ TDDLCommandCreateColumn }

function TDDLCommandCreateColumn.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateColumn(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandCreateColumn.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Create Column: %s', [AColumn.Name]);
end;

{ TDDLCommandDropColumn }

function TDDLCommandDropColumn.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropColumn(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandDropColumn.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Drop Column: %s', [AColumn.Name]);
end;

{ TDDLCommandCreateForeignKey }

function TDDLCommandCreateForeignKey.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateForeignKey(FForeignKey);
  Result := FCommand;
end;

constructor TDDLCommandCreateForeignKey.Create(AForeignKey: TForeignKeyMIK);
begin
  FForeignKey := AForeignKey;
  FWarning := Format('Create ForeignKey: %s', [AForeignKey.Name]);
end;

{ TDDLCommandCreateSequence }

function TDDLCommandCreateSequence.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateSequence(FSequence);
  Result := FCommand;
end;

constructor TDDLCommandCreateSequence.Create(ASequence: TSequenceMIK);
begin
  FSequence := ASequence;
  FWarning := Format('Create Sequence: %s', [ASequence.Name]);
end;

{ TDDLCommandAlterSequence }

function TDDLCommandAlterSequence.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateAlterSequence(FSequence);
  Result := FCommand;
end;

constructor TDDLCommandAlterSequence.Create(ASequence: TSequenceMIK);
begin
  FSequence := ASequence;
  FWarning := Format('Alter Sequence: %s', [ASequence.Name]);
end;

{ TDDLCommandDropTable }

function TDDLCommandDropTable.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropTable(FTable);
  Result := FCommand;
end;

constructor TDDLCommandDropTable.Create(ATable: TTableMIK);
begin
  FTable := ATable;
  FWarning := Format('Drop Table: %s', [ATable.Name]);
end;

{ TDDLCommandEnableForeignKeys }

function TDDLCommandEnableForeignKeys.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateEnableForeignKeys(FEnable);
  Result := FCommand;
end;

constructor TDDLCommandEnableForeignKeys.Create(AEnable: Boolean);
begin
  FEnable := AEnable;
  FWarning := Format('Enable ForeignKeys: %s', [ifThen(AEnable, 'On', 'Off')]);
end;

{ TDDLCommandDropIndexe }

function TDDLCommandDropIndexe.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropIndexe(FIndexe);
  Result := FCommand;
end;

constructor TDDLCommandDropIndexe.Create(AIndexe: TIndexeKeyMIK);
begin
  FIndexe := AIndexe;
  FWarning := Format('Drop Indexe: %s', [AIndexe.Name]);
end;

{ TDDLCommandCreateIndexe }

function TDDLCommandCreateIndexe.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateIndexe(FIndexe);
  Result := FCommand;
end;

constructor TDDLCommandCreateIndexe.Create(AIndexe: TIndexeKeyMIK);
begin
  FIndexe := AIndexe;
  FWarning := Format('Create Indexe: %s', [AIndexe.Name]);
end;

{ TDDLCommandEnableTriggers }

function TDDLCommandEnableTriggers.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateEnableTriggers(FEnable);
  Result := FCommand;
end;

constructor TDDLCommandEnableTriggers.Create(AEnable: Boolean);
begin
  FEnable := AEnable;
  FWarning := Format('Enable Triggers: %s', [ifThen(AEnable, 'On', 'Off')]);
end;

{ TDDLCommandDropView }

function TDDLCommandDropView.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropView(FView);
  Result := FCommand;
end;

constructor TDDLCommandDropView.Create(AView: TViewMIK);
begin
  FView := AView;
  FWarning := Format('Drop View: %s', [AView.Name]);
end;

{ TDDLCommandCreateView }

function TDDLCommandCreateView.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateView(FView);
  Result := FCommand;
end;

constructor TDDLCommandCreateView.Create(AView: TViewMIK);
begin
  FView := AView;
  FWarning := Format('Create View: %s', [AView.Name]);
end;

{ TDDLCommandCreateTrigger }

function TDDLCommandCreateTrigger.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateTrigger(FTrigger);
  Result := FCommand;
end;

constructor TDDLCommandCreateTrigger.Create(ATrigger: TTriggerMIK);
begin
  FTrigger := ATrigger;
  FWarning := Format('Create Trigger: %s', [ATrigger.Name]);
end;

{ TDDLCommandDropTrigger }

function TDDLCommandDropTrigger.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropTrigger(FTrigger);
  Result := FCommand;
end;

constructor TDDLCommandDropTrigger.Create(ATrigger: TTriggerMIK);
begin
  FTrigger := ATrigger;
  FWarning := Format('Drop Trigger: %s', [ATrigger.Name]);
end;

{ TDDLCommandAlterColumn }

function TDDLCommandAlterColumn.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateAlterColumn(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandAlterColumn.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Alter Column: %s', [AColumn.Name]);
end;

{ TDDLCommandDropPrimaryKey }

function TDDLCommandDropPrimaryKey.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropPrimaryKey(FPrimaryKey);
  Result := FCommand;
end;

constructor TDDLCommandDropPrimaryKey.Create(APrimaryKey: TPrimaryKeyMIK);
begin
  FPrimaryKey := APrimaryKey;
  FWarning := Format('Drop PrimaryKey: %s', [APrimaryKey.Name]);
end;

{ TDDLCommandCreatePrimaryKey }

function TDDLCommandCreatePrimaryKey.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreatePrimaryKey(FPrimaryKey);
  Result := FCommand;
end;

constructor TDDLCommandCreatePrimaryKey.Create(APrimaryKey: TPrimaryKeyMIK);
begin
  FPrimaryKey := APrimaryKey;
  FWarning := Format('Create PrimaryKey: %s', [APrimaryKey.Name]);
end;

{ TDDLCommandCreateCheck }

function TDDLCommandCreateCheck.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateCheck(FCheck);
  Result := FCommand;
end;

constructor TDDLCommandCreateCheck.Create(ACheck: TCheckMIK);
begin
  FCheck := ACheck;
  FWarning := Format('Create Check: %s', [ACheck.Name]);
end;

{ TDDLCommandDropCheck }

function TDDLCommandDropCheck.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropCheck(FCheck);
  Result := FCommand;
end;

constructor TDDLCommandDropCheck.Create(ACheck: TCheckMIK);
begin
  FCheck := ACheck;
  FWarning := Format('Drop Check: %s', [ACheck.Name]);
end;

{ TDDLCommandAlterDefaultValue }

function TDDLCommandAlterDefaultValue.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateAlterDefaultValue(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandAlterDefaultValue.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Set Default: %s', [AColumn.Name]);
end;

{ TDDLCommandDropDefaultValue }

function TDDLCommandDropDefaultValue.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropDefaultValue(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandDropDefaultValue.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Drop Default: %s', [AColumn.Name]);
end;

{ TDDLCommandAlterCheck }

function TDDLCommandAlterCheck.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateAlterCheck(FCheck);
  Result := FCommand;
end;

constructor TDDLCommandAlterCheck.Create(ACheck: TCheckMIK);
begin
  FCheck := ACheck;
  FWarning := Format('Create Check: %s', [ACheck.Name]);
end;

{ TDDLCommandAlterColumnPosition }

function TDDLCommandAlterColumnPosition.BuildCommand(
  ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateAlterColumnPosition(FColumn);
  Result := FCommand;
end;

constructor TDDLCommandAlterColumnPosition.Create(AColumn: TColumnMIK);
begin
  FColumn := AColumn;
  FWarning := Format('Alter Column Position: %s', [AColumn.Name]);
end;

{ TDDLCommandCreateDomain }

constructor TDDLCommandCreateDomain.Create(ADomain: TDomainMIK);
begin
  FDomain := ADomain;
  FWarning := Format('Create Domain: %s', [ADomain.Name]);
end;

function TDDLCommandCreateDomain.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateDomain(FDomain);
  Result := FCommand;
end;

{ TDDLCommandDropDomain }

constructor TDDLCommandDropDomain.Create(ADomain: TDomainMIK);
begin
  FDomain := ADomain;
  FWarning := Format('Drop Domain: %s', [ADomain.Name]);
end;

function TDDLCommandDropDomain.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropDomain(FDomain);
  Result := FCommand;
end;

{ TDDLCommandCreateProcedure }

constructor TDDLCommandCreateProcedure.Create(AProcedure: TProcedureMIK);
begin
  FProcedure := AProcedure;
  FWarning := Format('Create Procedure: %s', [AProcedure.Name]);
end;

function TDDLCommandCreateProcedure.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCreateProcedure(FProcedure);
  Result := FCommand;
end;

{ TDDLCommandDropProcedure }

constructor TDDLCommandDropProcedure.Create(AProcedure: TProcedureMIK);
begin
  FProcedure := AProcedure;
  FWarning := Format('Drop Procedure: %s', [AProcedure.Name]);
end;

function TDDLCommandDropProcedure.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateDropProcedure(FProcedure);
  Result := FCommand;
end;

{ TDDLCommandSetComment }

constructor TDDLCommandSetComment.Create(ATable: TTableMIK; AColumn: TColumnMIK);
begin
  FTable := ATable;
  FColumn := AColumn;
  if AColumn <> nil then
    FWarning := Format('Set Comment: %s.%s', [AColumn.Table.Name, AColumn.Name])
  else
    FWarning := Format('Set Comment: %s', [ATable.Name]);
end;

function TDDLCommandSetComment.BuildCommand(ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateSetComment(FTable, FColumn);
  Result := FCommand;
end;

{ TDDLCommand }

procedure TDDLCommand.AppendWarning(const AText: String);
begin
  if Trim(AText) = '' then
    Exit;
  if FWarning = '' then
    FWarning := AText
  else
    FWarning := FWarning + ' | ' + AText;
end;

{ TDDLCommandCopyColumnData }

constructor TDDLCommandCopyColumnData.Create(AColumn: TColumnMIK;
  const ASourceColumn: String; ABackfillNull: Boolean);
begin
  FColumn := AColumn;
  FSourceColumn := ASourceColumn;
  FBackfillNull := ABackfillNull;
  if ABackfillNull then
    FWarning := Format('Backfill Column Data: %s', [AColumn.Name])
  else
    FWarning := Format('Copy Column Data: %s -> %s', [ASourceColumn, AColumn.Name]);
end;

function TDDLCommandCopyColumnData.BuildCommand(
  ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateCopyColumnData(FColumn, FSourceColumn,
    FBackfillNull);
  Result := FCommand;
end;

{ TDDLCommandRenameColumn }

constructor TDDLCommandRenameColumn.Create(AColumn: TColumnMIK;
  const ANewName: String);
begin
  FColumn := AColumn;
  FNewName := ANewName;
  FWarning := Format('Rename Column: %s TO %s', [AColumn.Name, ANewName]);
end;

function TDDLCommandRenameColumn.BuildCommand(
  ASQLGeneratorCommand: IDDLGeneratorCommand): String;
begin
  FCommand := ASQLGeneratorCommand.GenerateRenameColumn(FColumn, FNewName);
  Result := FCommand;
end;

end.

