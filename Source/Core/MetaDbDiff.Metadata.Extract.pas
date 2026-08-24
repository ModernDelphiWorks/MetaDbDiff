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
  @created(20 Jul 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @author(Skype : ispinheiro)

  ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi.

  @abstract(Contribui��o - Carlos Eduardo R. Grillo)
}

unit MetaDbDiff.Metadata.Extract;

interface

uses
  DB,
  SysUtils,
  StrUtils,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Interfaces,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Types.Mapping;

type
  TMetadataAbstract = class(TInterfacedObject)
  private
    function _GetModelForDatabase: Boolean;
    procedure _SetModelForDatabase(const Value: Boolean);
    function GetCatalogMetadata: TCatalogMetadataMIK;
    procedure SetCatalogMetadata(const Value: TCatalogMetadataMIK);
    procedure _SetGuidOrOctetos(const AColumn: TColumnMIK;
      const ADriverName: TDriverName);
  protected
    FConnection: IDBConnection;
    FCatalogMetadata: TCatalogMetadataMIK;
    FModelForDatabase: Boolean;
    procedure GetFieldTypeDefinition(const AColumn: TColumnMIK); virtual;
    function GetRuleAction(ARuleAction: String): TRuleAction; overload;
    function GetRuleAction(ARuleAction: Variant): TRuleAction; overload;
  public
    constructor Create; overload; virtual; abstract;
    constructor Create(ACatalogMetadata: TCatalogMetadataMIK); overload; virtual; abstract;
    property CatalogMetadata: TCatalogMetadataMIK read GetCatalogMetadata write SetCatalogMetadata;
    property ModelForDatabase: Boolean read _GetModelForDatabase write _SetModelForDatabase;
  end;

  /// <summary>
  ///   Levantada quando o nome de schema configurado (property Schema do
  ///   compare, propagada ate o extractor) contem caracteres que nao formam um
  ///   identificador SQL valido. Como o nome do schema entra na montagem dos
  ///   selects de extracao (via QuotedStr apos esta validacao), rejeitar aqui
  ///   um nome malicioso ('x; DROP', aspas, espacos, ";" etc.) e a barreira que
  ///   impede injecao no metadata-scan. String vazia ('') e sempre valida e
  ///   significa "comportamento historico (sem filtro de schema)".
  /// </summary>
  EMetaDbDiffSchema = class(Exception);

  TCatalogMetadataAbstract = class(TMetadataAbstract, IDatabaseMetadata)
  private
    function GetConnection: IDBConnection;
    procedure SetConnection(const Value: IDBConnection);
    procedure SetSchema(const Value: String);
  protected
    FSQLText: String;
    FSchema: String;
    FFieldType: TDictionary<String, TFieldType>;
    /// <summary>
    ///   Schema efetivo do FILTRO de extracao, ja validado: '' (default) = sem
    ///   filtro (comportamento historico), ou o identificador configurado. Os
    ///   GetSelect* dos extractors multi-schema (PostgreSQL/MSSQL) so acrescentam
    ///   o filtro de schema quando este retorna nao-vazio, garantindo SQL de
    ///   extracao identico ao historico quando nada e configurado.
    /// </summary>
    function EffectiveSchema: String;
    /// <summary>
    ///   Schema DEFAULT do dialeto usado para carimbar o catalogo/qualificar o
    ///   DDL quando NENHUM schema foi configurado. Base: '' (dialetos sem schema
    ///   - o DDL sai sem qualificacao). O extractor PostgreSQL sobrescreve para
    ///   'public', restaurando o comportamento historico (catalogo/DDL public).
    /// </summary>
    function DefaultSchema: String; virtual;
    /// <summary>
    ///   Schema efetivamente gravado no catalogo (e, portanto, usado pelo
    ///   generator para qualificar o DDL): o schema configurado quando nao-vazio,
    ///   senao o DefaultSchema do dialeto. NAO e o mesmo que EffectiveSchema, que
    ///   governa apenas o FILTRO dos selects (este permanece '' no default para
    ///   nao alterar o SQL historico de extracao).
    /// </summary>
    function CatalogSchema: String;
    procedure SetFieldType(var AColumnMIK: TColumnMIK); virtual;
    function GetSelectTables: String; virtual; abstract;
    function GetSelectTableColumns(ATableName: String): String; virtual; abstract;
    function GetSelectPrimaryKey(ATableName: String): String; virtual; abstract;
    function GetSelectPrimaryKeyColumns(APrimaryKeyName: String): String; virtual; abstract;
    function GetSelectForeignKey(ATableName: String): String; virtual; abstract;
    function GetSelectForeignKeyColumns(AForeignKeyName: String): String; virtual; abstract;
    function GetSelectIndexe(ATableName: String): String; virtual; abstract;
    function GetSelectIndexeColumns(AIndexeName: String): String; virtual; abstract;
    function GetSelectTriggers(ATableName: String): String; virtual; abstract;
    function GetSelectChecks(ATableName: String): String; virtual; abstract;
    function GetSelectViews: String; virtual; abstract;
    function GetSelectSequences: String; virtual; abstract;
  public
    constructor Create; overload; override;
    destructor Destroy; override;
    procedure CreateFieldTypeList; virtual;
    procedure GetCatalogs; virtual; abstract;
    procedure GetSchemas; virtual; abstract;
    procedure GetTables; virtual; abstract;
    procedure GetColumns(ATable: TTableMIK); virtual; abstract;
    procedure GetPrimaryKey(ATable: TTableMIK); virtual; abstract;
    procedure GetIndexeKeys(ATable: TTableMIK); virtual; abstract;
    procedure GetForeignKeys(ATable: TTableMIK); virtual; abstract;
    procedure GetChecks(ATable: TTableMIK); virtual; abstract;
    procedure GetTriggers(ATable: TTableMIK); virtual; abstract;
    procedure GetSequences; virtual; abstract;
    procedure GetProcedures; virtual; abstract;
    procedure GetFunctions; virtual; abstract;
    procedure GetViews; virtual; abstract;
    /// <summary>
    ///   FRENTE 15: extracao de DOMINIOS (nao-abstrata: base vazia). Apenas os
    ///   dialetos com dominios reais sobrescrevem (Firebird/Firebird3/PostgreSQL);
    ///   os demais herdam o no-op.
    /// </summary>
    procedure GetDomains; virtual;
    procedure GetDatabaseMetadata; virtual; abstract;
    /// <summary>
    ///   Valida um nome de schema como identificador SQL seguro. '' e sempre
    ///   valido (default = sem qualificacao). Um nome nao-vazio deve conter
    ///   apenas letras/digitos/underscore, comecar por letra ou underscore e ter
    ///   no maximo 128 caracteres - qualquer outra coisa (aspas, espacos, ";",
    ///   etc.) levanta EMetaDbDiffSchema. Retorna o proprio nome quando valido,
    ///   para uso fluente na montagem dos selects.
    /// </summary>
    class function ValidateSchemaName(const ASchema: String): String; static;
    /// <summary>
    ///   Schema configurado a ser comparado/qualificado. Default '' preserva o
    ///   comportamento historico POR DIALETO (PostgreSQL: catalogo/DDL 'public';
    ///   demais: sem qualificacao). O write valida o identificador
    ///   (ValidateSchemaName) - schema malicioso e rejeitado ja na atribuicao.
    /// </summary>
    property Schema: String read FSchema write SetSchema;
    property Connection: IDBConnection read GetConnection write SetConnection;
  end;

  TModelMetadataAbstract = class(TMetadataAbstract, IModelMetadata)
  private
    function GetConnection: IDBConnection;
    procedure SetConnection(const Value: IDBConnection);
  public
    constructor Create; overload; override;
    procedure GetCatalogs; virtual; abstract;
    procedure GetSchemas; virtual; abstract;
    procedure GetTables; virtual; abstract;
    procedure GetColumns(ATable: TTableMIK; AClass: TClass); virtual; abstract;
    procedure GetPrimaryKey(ATable: TTableMIK; AClass: TClass); virtual; abstract;
    procedure GetIndexeKeys(ATable: TTableMIK; AClass: TClass); virtual; abstract;
    procedure GetForeignKeys(ATable: TTableMIK; AClass: TClass); virtual; abstract;
    procedure GetChecks(ATable: TTableMIK; AClass: TClass); virtual; abstract;
    procedure GetSequences; virtual; abstract;
    procedure GetProcedures; virtual; abstract;
    procedure GetFunctions; virtual; abstract;
    procedure GetViews; virtual; abstract;
    procedure GetTriggers; virtual; abstract;
    procedure GetModelMetadata; virtual; abstract;
    property Connection: IDBConnection read GetConnection write SetConnection;
  end;

implementation

const
  /// <summary>
  ///   Comprimento do literal canonico de GUID em modo TEXTO: a forma
  ///   QuotedStr(TGUID.ToString) = '{8-4-4-4-12}', com chaves, hifens e hex -
  ///   ver TDMLGeneratorAbstract.CanonicalGuidLiteral, em
  ///   Janus.DML.Generator.pas, que e quem grava o valor que esta coluna tem
  ///   de caber e quem o emite de volta no WHERE. Serve de default quando o
  ///   mapeamento nao declara tamanho; nao substitui um tamanho declarado.
  /// </summary>
  C_GUID_TEXT_LITERAL_LENGTH = 38;

{ TCatalogMetadataAbstract }

constructor TCatalogMetadataAbstract.Create;
begin
  FFieldType := TDictionary<String, TFieldType>.Create;
  // Inst�ncia um dicion�rio interno com uma lista de NOMES e TIPOS de
  // colunas dos bancos de dados.
  CreateFieldTypeList;
end;

procedure TCatalogMetadataAbstract.CreateFieldTypeList;
begin

end;

procedure TCatalogMetadataAbstract.GetDomains;
begin
  // Base: no-op. Dialetos com dominios reais (Firebird/PostgreSQL) sobrescrevem.
end;

destructor TCatalogMetadataAbstract.Destroy;
begin
  FFieldType.Free;
  inherited;
end;

class function TCatalogMetadataAbstract.ValidateSchemaName(const ASchema: String): String;
var
  LFor: Integer;
  LChar: Char;
begin
  Result := ASchema;
  // '' = default (comportamento historico, sem filtro/qualificacao): valido.
  if ASchema = '' then
    Exit;
  if Length(ASchema) > 128 then
    raise EMetaDbDiffSchema.CreateFmt(
      'MetaDbDiff: nome de schema invalido "%s" (excede 128 caracteres).', [ASchema]);
  // Primeiro caractere nao pode ser digito (regra de identificador SQL).
  if CharInSet(ASchema[1], ['0'..'9']) then
    raise EMetaDbDiffSchema.CreateFmt(
      'MetaDbDiff: nome de schema invalido "%s": nao pode comecar por digito.', [ASchema]);
  for LFor := 1 to Length(ASchema) do
  begin
    LChar := ASchema[LFor];
    // Whitelist estrita: sem aspas, espacos, ";", pontos ou qualquer outro
    // metacaractere - so assim o QuotedStr posterior nao pode ser subvertido.
    if not CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      raise EMetaDbDiffSchema.CreateFmt(
        'MetaDbDiff: nome de schema invalido "%s": apenas letras, digitos e ' +
        'underscore sao permitidos (sem aspas, espacos, ";" ou pontos).', [ASchema]);
  end;
end;

function TCatalogMetadataAbstract.EffectiveSchema: String;
begin
  Result := ValidateSchemaName(FSchema);
end;

function TCatalogMetadataAbstract.DefaultSchema: String;
begin
  // Base (dialetos sem schema): sem default - DDL sem qualificacao.
  Result := '';
end;

function TCatalogMetadataAbstract.CatalogSchema: String;
begin
  Result := EffectiveSchema;
  if Result = '' then
    Result := DefaultSchema;
end;

procedure TCatalogMetadataAbstract.SetSchema(const Value: String);
begin
  FSchema := ValidateSchemaName(Value);
end;

function TCatalogMetadataAbstract.GetConnection: IDBConnection;
begin
  Result := FConnection;
end;

procedure TCatalogMetadataAbstract.SetFieldType(var AColumnMIK: TColumnMIK);
begin
  AColumnMIK.FieldType := FFieldType[Trim(AColumnMIK.TypeName)];
end;

procedure TCatalogMetadataAbstract.SetConnection(const Value: IDBConnection);
begin
  FConnection := Value;
end;

{ TModelMetadataAbstract }

constructor TModelMetadataAbstract.Create;
begin

end;

function TModelMetadataAbstract.GetConnection: IDBConnection;
begin
  Result := FConnection;
end;

procedure TModelMetadataAbstract.SetConnection(const Value: IDBConnection);
begin
  FConnection := Value;
end;

{ TMetadataAbstract }

function TMetadataAbstract.GetCatalogMetadata: TCatalogMetadataMIK;
begin
  Result := FCatalogMetadata;
end;

procedure TMetadataAbstract.SetCatalogMetadata(const Value: TCatalogMetadataMIK);
begin
  FCatalogMetadata := Value;
end;

procedure TMetadataAbstract._SetModelForDatabase(const Value: Boolean);
begin
  FModelForDatabase := Value;
end;

procedure TMetadataAbstract.GetFieldTypeDefinition(const AColumn: TColumnMIK);
var
  LDriverName: TDriverName;
begin
  LDriverName := FConnection.GetDriver;
  case AColumn.FieldType of
    ftBoolean:
    begin
      if      LDriverName = dnADS   then AColumn.TypeName := 'LOGICAL'
      else if LDriverName = dnASA   then AColumn.TypeName := 'BIT'
      else if LDriverName = dnMSSQL then AColumn.TypeName := 'BIT'
      else                               AColumn.TypeName := 'Boolean';
    end;
    ftByte, ftShortint, ftSmallint, ftWord:
    begin
      if LDriverName = dnOracle then AColumn.TypeName := 'NUMBER'
      else                           AColumn.TypeName := 'SMALLINT';
    end;
    ftInteger, ftLongWord:
    begin
      if      LDriverName = dnMSSQL  then AColumn.TypeName := 'INT'
      else if LDriverName = dnMySQL  then AColumn.TypeName := 'INT'
      else if LDriverName = dnOracle then AColumn.TypeName := 'NUMBER'
      else                                AColumn.TypeName := 'INTEGER';
    end;
    ftLargeint:
      if      LDriverName = dnOracle     then AColumn.TypeName := 'NUMBER'
      else if LDriverName = dnFirebird   then AColumn.TypeName := 'BIGINT'
      else if LDriverName = dnInterbase  then AColumn.TypeName := 'BIGINT'
      else if LDriverName = dnPostgreSQL then AColumn.TypeName := 'BIGINT'
      else                                    AColumn.TypeName := 'NUMERIC(%l)';
    ftString:
      if LDriverName = dnOracle                               then AColumn.TypeName := 'VARCHAR2(%l)'
      else if (LDriverName = dnMSSQL) and (AColumn.Size = -1) then AColumn.TypeName := 'VARCHAR(MAX)'
      else                                                         AColumn.TypeName := 'VARCHAR(%l)';
    ftWideString:
      if      LDriverName = dnOracle    then AColumn.TypeName := 'NVARCHAR2(%l)'
      else if LDriverName = dnFirebird  then AColumn.TypeName := 'VARCHAR(%l)'
      else if LDriverName = dnInterbase then AColumn.TypeName := 'VARCHAR(%l)'
      else                                   AColumn.TypeName := 'NVARCHAR(%l)';
    ftFixedChar:
      AColumn.TypeName := 'CHAR(%l)';
    ftFixedWideChar:
      AColumn.TypeName := 'NCHAR(%l)';
    ftDate:
      AColumn.TypeName := 'DATE';
    ftTime:
      if LDriverName = dnOracle then AColumn.TypeName := 'DATE'
      else                           AColumn.TypeName := 'TIME';
    ftDateTime:
      // ftDateTime carries both date and time-of-day, so it must map to a
      // type that preserves the time part.
      if      LDriverName = dnInterbase  then AColumn.TypeName := 'TIMESTAMP' // IB6+: DATE is date-only; TIMESTAMP is date+time.
      else if LDriverName = dnFirebird   then AColumn.TypeName := 'TIMESTAMP' // FB dialect 3+: DATE is date-only; TIMESTAMP is date+time.
      else if LDriverName = dnOracle     then AColumn.TypeName := 'DATE'      // Not a bug: Oracle DATE stores date+time down to the second.
      else if LDriverName = dnPostgreSQL then AColumn.TypeName := 'TIMESTAMP' // PostgreSQL DATE is date-only; TIMESTAMP is date+time.
      else                                   AColumn.TypeName := 'DATETIME';
    ftTimeStamp, ftOraTimeStamp, ftTimeStampOffset:
      if LDriverName = dnOracle    then AColumn.TypeName := 'DATE'
      else                              AColumn.TypeName := 'TIMESTAMP';
    ftFloat:
    begin
      if      LDriverName = dnSQLite     then AColumn.TypeName := 'FLOAT(%p,%s)'
      else if LDriverName = dnPostgreSQL then AColumn.TypeName := 'NUMERIC(%p,%s)'
      else                                    AColumn.TypeName := 'FLOAT';
    end;
    ftSingle:
      if LDriverName = dnOracle    then AColumn.TypeName := 'NUMBER(%p,%s)'
      else                              AColumn.TypeName := 'REAL';
    ftExtended:
    begin
      if      LDriverName = dnMSSQL  then AColumn.TypeName := 'FLOAT'
      else if LDriverName = dnSQLite then AColumn.TypeName := 'DOUBLE'
      else if LDriverName = dnMySQL  then AColumn.TypeName := 'DOUBLE'
      else if LDriverName = dnDB2    then AColumn.TypeName := 'DOUBLE'
      else if LDriverName = dnOracle then AColumn.TypeName := 'BINARY_DOUBLE'
      else                                AColumn.TypeName := 'DOUBLE PRECISION';
    end;
    ftCurrency:
    begin
      if      LDriverName = dnMSSQL      then AColumn.TypeName := 'MONEY'
      else if LDriverName = dnSQLite     then AColumn.TypeName := 'MONEY'
      else if LDriverName = dnPostgreSQL then AColumn.TypeName := 'MONEY'
      else if LDriverName = dnOracle     then AColumn.TypeName := 'NUMBER(%p,%s)'
      else                                    AColumn.TypeName := 'NUMERIC(%p,%s)';
    end;
    ftBCD, ftFMTBcd:
    begin
      if      LDriverName = dnOracle  then AColumn.TypeName := 'NUMBER(%p,%s)'
      else if LDriverName = dnSQLite  then AColumn.TypeName := 'FLOAT(%p,%s)'
      else                                 AColumn.TypeName := 'DECIMAL(%p,%s)';
    end;
    ftBlob, ftOraBlob:
    begin
      if      LDriverName = dnMSSQL      then AColumn.TypeName := 'VARBINARY(MAX)'
      else if LDriverName = dnPostgreSQL then AColumn.TypeName := 'BYTEA'
      else                                    AColumn.TypeName := 'BLOB'
    end;
    ftGraphic:
    begin
      if LDriverName = dnMSSQL  then AColumn.TypeName := 'IMAGE'
      else                           AColumn.TypeName := 'BLOB'
    end;
    ftWideMemo:
    begin
      if      LDriverName = dnFirebird  then AColumn.TypeName := 'BLOB SUB_TYPE 1'
      else if LDriverName = dnInterbase then AColumn.TypeName := 'BLOB SUB_TYPE 1'
      else if LDriverName = dnMSSQL     then AColumn.TypeName := 'NTEXT'
      else if LDriverName = dnOracle    then AColumn.TypeName := 'NCLOB'
      else                                   AColumn.TypeName := 'TEXT';
    end;
    ftMemo, ftOraClob:
    begin
      if      LDriverName = dnFirebird  then AColumn.TypeName := 'BLOB SUB_TYPE 1'
      else if LDriverName = dnInterbase then AColumn.TypeName := 'BLOB SUB_TYPE 1'
      else if LDriverName = dnOracle    then AColumn.TypeName := 'CLOB'
      else                                   AColumn.TypeName := 'TEXT';
    end;
    ftGuid:
    begin
      // GUID OCTETs (ou simplesmente octetos) se referem aos 16 bytes
      // (128 bits) que comp�em um GUID (Globally Unique Identifier).
      // Cada octeto � representado por dois caracteres em hexadecimal,
      // formando uma sequ�ncia de 32 caracteres hexadecimais separados
      // por h�fens (por exemplo, "550e8400-e29b-41d4-a716-446655440000").
      if FConnection.Options.StoreGUIDAsOctet then
      begin
        _SetGuidOrOctetos(AColumn, LDriverName);
      end
      else
      begin
        // O placeholder de tamanho e '%l' (letra ele minuscula): e o unico que
        // TDDLSQLGenerator.GetFieldTypeDefinition substitui (DDL.Generator.pas).
        // '%1' (o algarismo um) nunca foi substituido por ninguem e ia parar
        // literal no DDL. Oracle: o tipo de tamanho FIXO e NCHAR(n) - 'NCHAR2'
        // nao existe (existem NCHAR(n), fixo, e NVARCHAR2(n), variavel).
        //
        // E o placeholder precisa de um tamanho para resolver: o atributo
        // Column sem tamanho deixa Size em zero (Column.Create, em
        // MetaDbDiff.Mapping.Attributes.pas), e ai o %l resolveria para uma
        // coluna de tamanho ZERO - que nao guarda literal de GUID nenhum. O
        // default e o comprimento do literal canonico que este ecossistema
        // grava e compara (C_GUID_TEXT_LITERAL_LENGTH). Um tamanho que o
        // mapeamento declarou - ou que a extracao leu do banco - continua
        // mandando, porque so o valor nao-positivo cai no default.
        if AColumn.Size <= 0 then
          AColumn.Size := C_GUID_TEXT_LITERAL_LENGTH;

        if      LDriverName = dnPostgreSQL then AColumn.TypeName := 'CHAR(%l)'
        else if LDriverName = dnFirebird   then AColumn.TypeName := 'CHAR(%l)'
        else if LDriverName = dnInterbase  then AColumn.TypeName := 'CHAR(%l)'
        else if LDriverName = dnMySQL      then AColumn.TypeName := 'CHAR(%l)'
        else if LDriverName = dnOracle     then AColumn.TypeName := 'NCHAR(%l)'
        else                                    AColumn.TypeName := 'GUID';
      end;
    end;
  else
    raise Exception.Create('Tipo da coluna definida [' + AColumn.Table.Name + '.' +
                                          FieldTypeNames[AColumn.FieldType] + '], n�o existe no DBCBr.');
  end;
  // Defini��es de propriedades de tamnanho
  if FModelForDatabase then
  begin
    if MatchStr(AColumn.TypeName, ['SMALLINT','INT','INT4','INT8','INTEGER',
                                   'DATE','TIME','BIGINT','DATETIME','TIMESTAMP',
                                   'REAL','DOUBLE PRECISION','BLOB SUB_TYPE TEXT',
                                   'TEXT','NTEXT','NUMBER','BLOB SUB_TYPE 1']) then
    begin
      AColumn.Size := 0;
      AColumn.Precision := 0;
      AColumn.Scale := 0;
    end
    else
    if MatchStr(AColumn.TypeName, ['BLOB']) then
      AColumn.Size := 8
    else
    if MatchStr(AColumn.TypeName, ['Boolean']) then
      AColumn.Size := 1
    else
    if MatchStr(AColumn.TypeName, ['FLOAT']) then
      AColumn.Size := 0
    else
    if MatchStr(AColumn.TypeName, ['DECIMAL(%p,%s)','NUMERIC(%p,%s)','NUMBER(%p,%s)',
                                   'FLOAT(%p,%s)']) then
      AColumn.Size := 0
    else
    if MatchStr(AColumn.TypeName, ['NUMERIC(%l)','VARCHAR(%l)','VARCHAR2(%l)',
                                   'NVARCHAR(%l)','NVARCHAR(%l)','CHAR(%l)','NCHAR(%l)']) then
    begin
      AColumn.Precision := 0;
      AColumn.Scale := 0;
    end;
  end;
end;

function TMetadataAbstract._GetModelForDatabase: Boolean;
begin
  Result := FModelForDatabase;
end;

function TMetadataAbstract.GetRuleAction(ARuleAction: String): TRuleAction;
begin
  if      ARuleAction = 'NO ACTION'   then Result := TRuleAction.None
  else if ARuleAction = 'SET NULL'    then Result := TRuleAction.SetNull
  else if ARuleAction = 'SET DEFAULT' then Result := TRuleAction.SetDefault
  else if ARuleAction = 'CASCADE'     then Result := TRuleAction.Cascade
  else Result := TRuleAction.None;
end;

function TMetadataAbstract.GetRuleAction(ARuleAction: Variant): TRuleAction;
begin
  if      ARuleAction = 0 then Result := TRuleAction.None
  else if ARuleAction = 1 then Result := TRuleAction.Cascade
  else if ARuleAction = 2 then Result := TRuleAction.SetNull
  else if ARuleAction = 3 then Result := TRuleAction.SetDefault
  else Result := TRuleAction.None;
end;

procedure TMetadataAbstract._SetGuidOrOctetos(const AColumn: TColumnMIK;
  const ADriverName: TDriverName);
begin
  if ADriverName = dnFirebird  then
  begin
    AColumn.TypeName := 'CHAR(%l)';
    AColumn.CharSet := 'OCTETS';
    AColumn.Size := 16;
  end
  else
  if ADriverName = dnPostgreSQL  then
  begin
    // 'BYTE' nao e tipo do PostgreSQL. O tipo binario dele e BYTEA - o mesmo
    // que esta unit ja emite para ftBlob/ftOraBlob neste dialeto -, e BYTEA
    // NAO aceita modificador de comprimento: por isso o tipo sai sem
    // parenteses e sem placeholder. Size continua registrando os octetos que
    // o GUID ocupa, para quem compara metadado, mas nao entra no tipo.
    // NAO MEDIDO contra banco vivo: se o round-trip de leitura do metadado
    // devolve esse mesmo Size para uma coluna bytea.
    AColumn.TypeName := 'BYTEA';
    AColumn.Size := 16;
  end
  else
    // Ramo "else" do modo octeto (Oracle/MySQL/MSSQL/SQLite/...): mantem o
    // CHAR(n) historico e NAO forca Size. Os tipos binarios por dialeto
    // (Oracle RAW(16), MySQL BINARY(16), ...) seguem em aberto na issue #19 -
    // nenhum foi medido contra banco vivo.
    AColumn.TypeName := 'CHAR(%l)';
end;

end.
