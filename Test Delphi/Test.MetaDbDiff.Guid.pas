{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  ftGuid DDL emission, per dialect, WITHOUT a live database (issue #19).

  The whole ftGuid branch of TMetadataAbstract.GetFieldTypeDefinition
  (MetaDbDiff.Metadata.Extract.pas) only reads FConnection.GetDriver and
  FConnection.Options.StoreGUIDAsOctet, so a "shell" IDBConnection built over an
  UNCONNECTED TFDConnection is enough - exactly like Test.MetaDbDiff.Metadata.Model.
  The resolved TypeName is then handed to the registered DDL generator of the same
  dialect, and the emitted string is asserted: the three defects of issue #19 show
  up in the string, not in the execution.

  Case matters here (a SQL type name is what is being asserted), so every string
  comparison passes ignoreCase = False explicitly - DUnitX defaults it to True.

  Each dialect has its OWN test on purpose: the seven near-identical lines of the
  ftGuid branch are seven separate chances to measure only one of them.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Guid;

interface

uses
  DB,
  SysUtils,
  DUnitX.TestFramework,
  FireDAC.Comp.Client,
  DataEngine.FactoryInterfaces,
  DataEngine.FactoryFireDac,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Database.Mapping,
  MetaDbDiff.Metadata.Model,
  MetaDbDiff.DDL.Interfaces,
  MetaDbDiff.DDL.Register,
  // Os generators se registram no initialization destas units - sem elas no uses
  // o dialeto nao existe no registro e GetDriver levanta excecao:
  MetaDbDiff.DDL.Generator.Firebird,
  MetaDbDiff.DDL.Generator.Firebird3,
  MetaDbDiff.DDL.Generator.Interbase,
  MetaDbDiff.DDL.Generator.MSSQL,
  MetaDbDiff.DDL.Generator.MySQL,
  MetaDbDiff.DDL.Generator.Oracle,
  MetaDbDiff.DDL.Generator.PostgreSQL,
  MetaDbDiff.DDL.Generator.SQLite;

type
  /// <summary>
  ///   Expoe TMetadataAbstract.GetFieldTypeDefinition (protected) para o teste.
  ///   TModelMetadata e usado apenas como descendente concreto; nenhum metodo de
  ///   extracao de modelo e chamado.
  /// </summary>
  TGuidTypeProbe = class(TModelMetadata)
  public
    procedure ResolveTypeName(const AColumn: TColumnMIK);
  end;

  [TestFixture]
  TTestGuidDDL = class
  private
    const
      /// <summary>
      ///   Tamanho de entrada deliberadamente diferente de 16 e de 36: se o DDL
      ///   sair com este numero, a substituicao usou AColumn.Size de verdade e
      ///   nao um literal chumbado.
      /// </summary>
      C_SIZE_IN = 38;
    function _NormalizeSQL(const ASQL: String): String;
    /// <summary>
    ///   Resolve o TypeName de uma coluna ftGuid pelo dialeto ADriver e devolve
    ///   o DDL "ALTER TABLE ... ADD ...;" emitido pelo generator desse dialeto.
    ///   ATypeName devolve o TypeName cru (ainda com placeholder, se houver).
    /// </summary>
    function _EmitGuidColumn(const ADriver: TDriverName;
      const AStoreAsOctet: Boolean; out ATypeName: String;
      const ASize: Integer = C_SIZE_IN): String;
    function _EmitGuidDDL(const ADriver: TDriverName;
      const AStoreAsOctet: Boolean): String;
  public
    // -------------------------------------------------- StoreGUIDAsOctet = False
    [Test]
    procedure Guid_PostgreSQL_NotOctet_EmitsCharWithSize;
    [Test]
    procedure Guid_Firebird_NotOctet_EmitsCharWithSize;
    [Test]
    procedure Guid_Interbase_NotOctet_EmitsCharWithSize;
    [Test]
    procedure Guid_MySQL_NotOctet_EmitsCharWithSize;
    [Test]
    procedure Guid_Oracle_NotOctet_EmitsNCharWithSize;
    // --------------------------------------------------- StoreGUIDAsOctet = True
    [Test]
    procedure Guid_Firebird_Octet_EmitsChar16Octets;
    [Test]
    procedure Guid_PostgreSQL_Octet_SubstitutesSize;
    [Test]
    procedure Guid_Oracle_Octet_FallsBackToCharWithSize;
    [Test]
    procedure Guid_MySQL_Octet_FallsBackToCharWithSize;
    [Test]
    procedure Guid_MSSQL_Octet_FallsBackToCharWithSize;
    // ------------------------------------------------------------------ Varredura
    [Test]
    procedure Guid_NoRegisteredDialect_LeavesAPlaceholderInTheDDL;
  end;

implementation

{ TGuidTypeProbe }

procedure TGuidTypeProbe.ResolveTypeName(const AColumn: TColumnMIK);
begin
  GetFieldTypeDefinition(AColumn);
end;

{ TTestGuidDDL }

function TTestGuidDDL._NormalizeSQL(const ASQL: String): String;
begin
  Result := StringReplace(ASQL, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

function TTestGuidDDL._EmitGuidColumn(const ADriver: TDriverName;
  const AStoreAsOctet: Boolean; out ATypeName: String;
  const ASize: Integer): String;
var
  LFDConnection: TFDConnection;
  LConnection: IDBConnection;
  LCatalog: TCatalogMetadataMIK;
  LTable: TTableMIK;
  LColumn: TColumnMIK;
  LProbe: TGuidTypeProbe;
begin
  LFDConnection := TFDConnection.Create(nil);
  try
    // Conexao "casca": nunca e aberta; so informa o dialeto e as Options.
    LConnection := TFactoryFireDAC.Create(LFDConnection, ADriver);
    LConnection.Options.StoreGUIDAsOctet(AStoreAsOctet);
    LCatalog := TCatalogMetadataMIK.Create;
    try
      LCatalog.Name := '';
      LCatalog.Schema := '';
      LTable := TTableMIK.Create(LCatalog);
      LTable.Name := 'CLIENTE';
      LCatalog.Tables.Add(LTable.Name, LTable);
      LColumn := TColumnMIK.Create(LTable);
      LColumn.Name := 'ID_GUID';
      LColumn.Position := 0;
      LColumn.FieldType := ftGuid;
      LColumn.Size := ASize;
      LTable.Fields.Add('000000', LColumn);

      LProbe := TGuidTypeProbe.Create;
      try
        LProbe.Connection := LConnection;
        LProbe.ModelForDatabase := False;
        LProbe.ResolveTypeName(LColumn);
      finally
        LProbe.Free;
      end;
      ATypeName := LColumn.TypeName;
      Result := _NormalizeSQL(TSQLDriverRegister.GetInstance
                                .GetDriver(ADriver)
                                .GenerateCreateColumn(LColumn));
    finally
      LCatalog.Free;
    end;
  finally
    LConnection := nil;
    LFDConnection.Free;
  end;
end;

function TTestGuidDDL._EmitGuidDDL(const ADriver: TDriverName;
  const AStoreAsOctet: Boolean): String;
var
  LTypeName: String;
begin
  Result := _EmitGuidColumn(ADriver, AStoreAsOctet, LTypeName);
end;

// ---------------------------------------------------------------------------
// StoreGUIDAsOctet = False (Metadata.Extract.pas :440-444)
// ---------------------------------------------------------------------------

procedure TTestGuidDDL.Guid_PostgreSQL_NotOctet_EmitsCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:440
  LSQL := _EmitGuidColumn(dnPostgreSQL, False, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False,
    'O placeholder de tamanho do PostgreSQL deve ser %l (o unico que o generator substitui)');
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL PostgreSQL/ftGuid: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_Firebird_NotOctet_EmitsCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:441
  LSQL := _EmitGuidColumn(dnFirebird, False, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False,
    'O placeholder de tamanho do Firebird deve ser %l');
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL Firebird/ftGuid: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_Interbase_NotOctet_EmitsCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:442
  LSQL := _EmitGuidColumn(dnInterbase, False, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False,
    'O placeholder de tamanho do Interbase deve ser %l');
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL Interbase/ftGuid: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_MySQL_NotOctet_EmitsCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:443
  LSQL := _EmitGuidColumn(dnMySQL, False, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False,
    'O placeholder de tamanho do MySQL deve ser %l');
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL MySQL/ftGuid: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_Oracle_NotOctet_EmitsNCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:444. NCHAR2 nao existe no Oracle; o analogo de tamanho
  // FIXO para GUID e NCHAR(n) (NVARCHAR2 e o tipo VARIAVEL, nao serve aqui).
  LSQL := _EmitGuidColumn(dnOracle, False, LTypeName);
  Assert.AreEqual('NCHAR(%l)', LTypeName, False,
    'Oracle: o tipo fixo e NCHAR(n); NCHAR2 nao existe');
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID NCHAR(38);', LSQL, False,
    'DDL Oracle/ftGuid: ' + LSQL);
  Assert.IsFalse(Pos('NCHAR2', LSQL) > 0, 'NCHAR2 nao existe no Oracle: ' + LSQL);
end;

// ---------------------------------------------------------------------------
// StoreGUIDAsOctet = True (Metadata.Extract.pas :509-526, _SetGuidOrOctetos)
// ---------------------------------------------------------------------------

procedure TTestGuidDDL.Guid_Firebird_Octet_EmitsChar16Octets;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:514-516 - unico ramo que ja escrevia %l corretamente.
  // Size e forcado a 16 (16 octetos), sobrepondo o C_SIZE_IN de entrada.
  LSQL := _EmitGuidColumn(dnFirebird, True, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False);
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(16) CHARACTER SET OCTETS;',
    LSQL, False, 'DDL Firebird/ftGuid octeto: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_PostgreSQL_Octet_SubstitutesSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:521-522.
  // ATENCAO: BYTE nao e tipo do PostgreSQL (o binario dele e bytea, e bytea NAO
  // e dimensionado). Este teste NAO afirma que BYTE(16) esta correto - afirma
  // apenas que o placeholder de tamanho passou a ser substituido nesta linha,
  // que e o que a issue #19 fecha. A escolha do tipo do modo octeto no
  // PostgreSQL (e o Size := 16 que a acompanha) segue EM ABERTO na issue por
  // falta de medicao contra banco vivo.
  LSQL := _EmitGuidColumn(dnPostgreSQL, True, LTypeName);
  Assert.AreEqual('BYTE(%l)', LTypeName, False);
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID BYTE(16);', LSQL, False,
    'DDL PostgreSQL/ftGuid octeto: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_Oracle_Octet_FallsBackToCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:525 - ramo "else" do modo octeto: NAO forca Size,
  // entao o tamanho de entrada e o que aparece no DDL.
  LSQL := _EmitGuidColumn(dnOracle, True, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False);
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL Oracle/ftGuid octeto: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_MySQL_Octet_FallsBackToCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:525 (mesmo ramo else, outro dialeto).
  LSQL := _EmitGuidColumn(dnMySQL, True, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False);
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL MySQL/ftGuid octeto: ' + LSQL);
end;

procedure TTestGuidDDL.Guid_MSSQL_Octet_FallsBackToCharWithSize;
var
  LTypeName, LSQL: String;
begin
  // Metadata.Extract.pas:525 (mesmo ramo else, outro dialeto).
  LSQL := _EmitGuidColumn(dnMSSQL, True, LTypeName);
  Assert.AreEqual('CHAR(%l)', LTypeName, False);
  Assert.AreEqual('ALTER TABLE CLIENTE ADD ID_GUID CHAR(38);', LSQL, False,
    'DDL MSSQL/ftGuid octeto: ' + LSQL);
end;

// ---------------------------------------------------------------------------
// Varredura: nenhum dialeto registrado pode deixar placeholder no DDL final.
// ---------------------------------------------------------------------------

procedure TTestGuidDDL.Guid_NoRegisteredDialect_LeavesAPlaceholderInTheDDL;
const
  C_DRIVERS: array[0..7] of TDriverName =
    (dnMSSQL, dnMySQL, dnFirebird, dnSQLite, dnInterbase, dnOracle,
     dnPostgreSQL, dnFirebird3);
var
  LDriver: TDriverName;
  LOctet: Boolean;
  LIndex: Integer;
  LSQL: String;
begin
  for LIndex := Low(C_DRIVERS) to High(C_DRIVERS) do
  begin
    LDriver := C_DRIVERS[LIndex];
    for LOctet := False to True do
    begin
      LSQL := _EmitGuidDDL(LDriver, LOctet);
      Assert.IsFalse(Pos('%', LSQL) > 0,
        Format('Placeholder nao substituido no DDL ftGuid (driver ord=%d, octeto=%s): %s',
               [Ord(LDriver), BoolToStr(LOctet, True), LSQL]));
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGuidDDL);

end.
