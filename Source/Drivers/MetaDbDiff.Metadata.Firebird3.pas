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
}

unit MetaDbDiff.Metadata.Firebird3;

interface

uses
  SysUtils,
  Variants,
  Generics.Collections,
  DataEngine.FactoryInterfaces,
  MetaDbDiff.Metadata.Firebird,
  MetaDbDiff.Metadata.Register,
  MetaDbDiff.Metadata.Extract,
  MetaDbDiff.Database.Mapping;

type
  // Firebird 3/4 herda todo o extractor 2.5 (ja auditado) e acrescenta os
  // recursos exclusivos das versoes 3+:
  //  - RDB$GENERATORS com RDB$INITIAL_VALUE e RDB$GENERATOR_INCREMENT;
  //  - colunas IDENTITY (RDB$RELATION_FIELDS.RDB$IDENTITY_TYPE);
  //  - BOOLEAN nativo (tipo 23) ja resolvido no ResolveFieldType do base.
  TCatalogMetadataFirebird3 = class(TCatalogMetadataFirebird)
  protected
    function GetSelectSequences: String; override;
  public
    procedure GetColumns(ATable: TTableMIK); override;
    procedure GetSequences; override;
  end;

implementation

function TCatalogMetadataFirebird3.GetSelectSequences: String;
begin
  // FB3+: RDB$GENERATORS ganhou RDB$INITIAL_VALUE e RDB$GENERATOR_INCREMENT.
  // O filtro coalesce(rdb$system_flag,0) = 0 mantem apenas sequences criadas
  // pelo usuario (CREATE SEQUENCE/GENERATOR) e descarta as geradas pelo sistema,
  // incluindo as que dao suporte a colunas IDENTITY (system_flag <> 0) -- estas
  // nao devem aparecer como "sequence sobrando" no diff.
  Result := ' select rdb$generator_name      as name, ' +
            '        rdb$description          as description, ' +
            '        rdb$initial_value        as initial_value, ' +
            '        rdb$generator_increment  as increment ' +
            ' from rdb$generators ' +
            ' where coalesce(rdb$system_flag, 0) = 0 ' +
            ' order by rdb$generator_name ';
end;

procedure TCatalogMetadataFirebird3.GetSequences;
var
  LDBResultSet: IDBResultSet;
  LSequence: TSequenceMIK;

  function ResolveIntNull(AValue: Variant; ADefault: Integer): Integer;
  begin
    Result := ADefault;
    if not VarIsNull(AValue) then
      Result := VarAsType(AValue, varInteger);
  end;

begin
  FSQLText := GetSelectSequences;
  LDBResultSet := Execute;
  while LDBResultSet.NotEof do
  begin
    LSequence := TSequenceMIK.Create(FCatalogMetadata);
    LSequence.Name := Trim(VarToStr(LDBResultSet.GetFieldValue('name')));
    LSequence.Description := VarToStr(LDBResultSet.GetFieldValue('description'));
    // Preenche tambem valor inicial/incremento (campos ja existentes no MIK).
    LSequence.InitialValue := ResolveIntNull(LDBResultSet.GetFieldValue('initial_value'), 0);
    LSequence.Increment := ResolveIntNull(LDBResultSet.GetFieldValue('increment'), 1);
    FCatalogMetadata.Sequences.Add(UpperCase(LSequence.Name), LSequence);
  end;
end;

procedure TCatalogMetadataFirebird3.GetColumns(ATable: TTableMIK);
var
  LDBResultSet: IDBResultSet;
  LColumnName: String;
  LPair: TPair<String, TColumnMIK>;
begin
  // Reaproveita integralmente a extracao de colunas do FB2.5 (tipos, tamanho,
  // charset, default, not null, boolean nativo etc.).
  inherited GetColumns(ATable);
  // FB3+: marca AutoIncrement nas colunas IDENTITY. RDB$IDENTITY_TYPE e NULL
  // para colunas comuns, 1 (BY DEFAULT) ou 2 (ALWAYS) para identidade.
  FSQLText := ' select rf.rdb$field_name as column_name ' +
              ' from rdb$relation_fields rf ' +
              ' where rf.rdb$relation_name = ' + QuotedStr(ATable.Name) +
              ' and rf.rdb$identity_type is not null ';
  LDBResultSet := Execute;
  while LDBResultSet.NotEof do
  begin
    LColumnName := Trim(VarToStr(LDBResultSet.GetFieldValue('column_name')));
    for LPair in ATable.Fields do
      if SameText(Trim(LPair.Value.Name), LColumnName) then
        LPair.Value.AutoIncrement := True;
  end;
end;

initialization
  TMetadataRegister.GetInstance.RegisterMetadata(dnFirebird3, TCatalogMetadataFirebird3.Create);

end.
