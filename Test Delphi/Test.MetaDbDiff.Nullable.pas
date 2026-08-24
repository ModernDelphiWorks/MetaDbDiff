{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  TRttiPropertyHelper.IsNullValue over Nullable<T> and over the [NullIfEmpty]
  opt-in (MetaDbDiff.RTTI.Helper.pas).

  IsNullValue is what the ORM consumer asks before deciding whether a column
  takes a value or takes NULL, so every assertion here is a Boolean read off a
  live object - no database, no connection, no mapping registry. The probe class
  is deliberately NOT decorated with [Table]/[Column]: IsNullable is resolved
  from the property TYPE alone (RTTI.Helper StartsText('Nullable<', ...)), and
  keeping the class out of the mapping registry keeps this fixture from
  perturbing the cached TMappingRepository the other fixtures share.

  Nullable<T> below is a STRUCTURAL stand-in, not an import: the real record
  lives in the consumer (Janus.Types.Nullable.pas) and MetaDbDiff must not
  depend on it. GetNullableValue reads the type by shape - a record whose type
  name starts with 'Nullable<', carrying the fields FHasValue and FValue - so a
  local record of that shape exercises exactly the path the consumer exercises.

  Comments are ASCII-only, matching the rest of this suite.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Nullable;

interface

uses
  Rtti,
  SysUtils,
  DUnitX.TestFramework,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Mapping.Attributes,
  MetaDbDiff.RTTI.Helper;

type
  /// <summary>
  ///   Structural stand-in for the consumer's Nullable&lt;T&gt;. Only the two
  ///   fields GetNullableValue looks up by name (FHasValue, FValue) and the
  ///   type-name prefix matter here; the operators exist so the tests can
  ///   assign a value in one line.
  /// </summary>
  Nullable<T> = record
  private
    FValue: T;
    FHasValue: Boolean;
  public
    class operator Implicit(const AValue: T): Nullable<T>;
    property HasValue: Boolean read FHasValue;
    property Value: T read FValue;
  end;

  /// <summary>
  ///   One property per clause. Nothing is assigned in the constructor: a
  ///   freshly created instance is exactly the "nobody touched it" state
  ///   (FHasValue = False) that must keep resolving to NULL.
  /// </summary>
  TNullableProbe = class
  private
    FCodigo: Nullable<Integer>;
    FValor: Nullable<Double>;
    FPreco: Nullable<Currency>;
    FEmissao: Nullable<TDateTime>;
    FDescricao: Nullable<String>;
    FAtivo: Nullable<Boolean>;
    FCodigoNotNull: Nullable<Integer>;
    FCodigoOptIn: Nullable<Integer>;
    FObservacao: String;
    FQuantidade: Integer;
  public
    // Bare Nullable<T>: nullity is HasValue and nothing else.
    property Codigo: Nullable<Integer> read FCodigo write FCodigo;
    property Valor: Nullable<Double> read FValor write FValor;
    property Preco: Nullable<Currency> read FPreco write FPreco;
    property Emissao: Nullable<TDateTime> read FEmissao write FEmissao;
    property Descricao: Nullable<String> read FDescricao write FDescricao;
    // tkEnumeration reaches none of the default-value branches - it is here to
    // pin the asymmetry that motivated this fixture, not to assert the fix.
    property Ativo: Nullable<Boolean> read FAtivo write FAtivo;

    // The existing escape hatch: NotNull exempts before anything else is read.
    [Restrictions([TRestriction.NotNull])]
    property CodigoNotNull: Nullable<Integer> read FCodigoNotNull write FCodigoNotNull;

    // The opt-in asked for explicitly ON a Nullable.
    [NullIfEmpty]
    property CodigoOptIn: Nullable<Integer> read FCodigoOptIn write FCodigoOptIn;

    // The opt-in on a plain (non-Nullable) property - the documented case.
    [NullIfEmpty]
    property Observacao: String read FObservacao write FObservacao;

    // The opt-in on a plain Integer: pins what the attribute does TODAY, which
    // is wider than what reference-api.md advertises for it.
    [NullIfEmpty]
    property Quantidade: Integer read FQuantidade write FQuantidade;
  end;

  [TestFixture]
  TTestNullableIsNullValue = class
  private
    FContext: TRttiContext;
    FProbe: TNullableProbe;
    function _IsNull(const APropertyName: String): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- Nullable<Integer> ---------------------------------------------------
    [Test]
    procedure NullableInteger_Unassigned_IsNull;
    [Test]
    procedure NullableInteger_Zero_IsNotNull;
    [Test]
    procedure NullableInteger_One_IsNotNull;

    // --- Nullable<Double> ----------------------------------------------------
    [Test]
    procedure NullableDouble_Unassigned_IsNull;
    [Test]
    procedure NullableDouble_Zero_IsNotNull;
    [Test]
    procedure NullableDouble_NonZero_IsNotNull;

    // --- Nullable<Currency> --------------------------------------------------
    [Test]
    procedure NullableCurrency_Unassigned_IsNull;
    [Test]
    procedure NullableCurrency_Zero_IsNotNull;

    // --- Nullable<TDateTime> -------------------------------------------------
    [Test]
    procedure NullableDateTime_Unassigned_IsNull;
    [Test]
    procedure NullableDateTime_Zero_IsNotNull;
    [Test]
    procedure NullableDateTime_RealDate_IsNotNull;

    // --- Nullable<String> ----------------------------------------------------
    [Test]
    procedure NullableString_Unassigned_IsNull;
    [Test]
    procedure NullableString_Empty_IsNotNull;
    [Test]
    procedure NullableString_NonEmpty_IsNotNull;

    // --- Nullable<Boolean> ---------------------------------------------------
    [Test]
    procedure NullableBoolean_Unassigned_IsNull;
    [Test]
    procedure NullableBoolean_False_IsNotNull;

    // --- escape hatch and opt-in --------------------------------------------
    [Test]
    procedure NotNullRestriction_ExemptsEvenWithoutValue;
    [Test]
    procedure NullIfEmpty_OnNullable_ZeroStillNull;
    [Test]
    procedure NullIfEmpty_OnPlainString_EmptyStillNull;
    [Test]
    procedure NullIfEmpty_OnPlainString_NonEmptyIsNotNull;
    [Test]
    procedure NullIfEmpty_OnPlainInteger_ZeroStillNull;
  end;

implementation

{ Nullable<T> }

class operator Nullable<T>.Implicit(const AValue: T): Nullable<T>;
begin
  Result.FValue := AValue;
  Result.FHasValue := True;
end;

{ TTestNullableIsNullValue }

procedure TTestNullableIsNullValue.Setup;
begin
  FContext := TRttiContext.Create;
  FProbe := TNullableProbe.Create;
end;

procedure TTestNullableIsNullValue.TearDown;
begin
  FProbe.Free;
  FContext.Free;
end;

function TTestNullableIsNullValue._IsNull(const APropertyName: String): Boolean;
var
  LProperty: TRttiProperty;
begin
  LProperty := FContext.GetType(TNullableProbe).GetProperty(APropertyName);
  Assert.IsNotNull(LProperty, 'Propriedade ' + APropertyName + ' sem RTTI');
  Result := LProperty.IsNullValue(FProbe);
end;

procedure TTestNullableIsNullValue.NullableInteger_Unassigned_IsNull;
begin
  // O caso mais comum do parque: ninguem atribuiu, HasValue = False.
  Assert.IsFalse(FProbe.Codigo.HasValue, 'Pre-condicao: HasValue deveria ser False');
  Assert.IsTrue(_IsNull('Codigo'),
    'Nullable<Integer> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableInteger_Zero_IsNotNull;
begin
  FProbe.Codigo := 0;
  Assert.IsTrue(FProbe.Codigo.HasValue, 'Pre-condicao: HasValue deveria ser True');
  Assert.IsFalse(_IsNull('Codigo'),
    'Nullable<Integer> valendo 0 e ZERO, nao NULL');
end;

procedure TTestNullableIsNullValue.NullableInteger_One_IsNotNull;
begin
  FProbe.Codigo := 1;
  Assert.IsFalse(_IsNull('Codigo'),
    'Nullable<Integer> valendo 1 nunca foi nulo');
end;

procedure TTestNullableIsNullValue.NullableDouble_Unassigned_IsNull;
begin
  Assert.IsTrue(_IsNull('Valor'),
    'Nullable<Double> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableDouble_Zero_IsNotNull;
begin
  FProbe.Valor := 0.0;
  Assert.IsFalse(_IsNull('Valor'),
    'Nullable<Double> valendo 0.0 e ZERO, nao NULL');
end;

procedure TTestNullableIsNullValue.NullableDouble_NonZero_IsNotNull;
begin
  FProbe.Valor := 1.5;
  Assert.IsFalse(_IsNull('Valor'),
    'Nullable<Double> valendo 1.5 nunca foi nulo');
end;

procedure TTestNullableIsNullValue.NullableCurrency_Unassigned_IsNull;
begin
  Assert.IsTrue(_IsNull('Preco'),
    'Nullable<Currency> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableCurrency_Zero_IsNotNull;
begin
  FProbe.Preco := Currency(0);
  Assert.IsFalse(_IsNull('Preco'),
    'Nullable<Currency> valendo 0 e ZERO, nao NULL');
end;

procedure TTestNullableIsNullValue.NullableDateTime_Unassigned_IsNull;
begin
  Assert.IsTrue(_IsNull('Emissao'),
    'Nullable<TDateTime> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableDateTime_Zero_IsNotNull;
begin
  // 0 em TDateTime e 30/12/1899 - uma data como qualquer outra para o banco.
  FProbe.Emissao := TDateTime(0);
  Assert.IsFalse(_IsNull('Emissao'),
    'Nullable<TDateTime> valendo zero foi ATRIBUIDO, nao e NULL');
end;

procedure TTestNullableIsNullValue.NullableDateTime_RealDate_IsNotNull;
begin
  FProbe.Emissao := EncodeDate(2026, 8, 24);
  Assert.IsFalse(_IsNull('Emissao'),
    'Nullable<TDateTime> com data real nunca foi nulo');
end;

procedure TTestNullableIsNullValue.NullableString_Unassigned_IsNull;
begin
  Assert.IsTrue(_IsNull('Descricao'),
    'Nullable<String> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableString_Empty_IsNotNull;
begin
  FProbe.Descricao := '';
  Assert.IsTrue(FProbe.Descricao.HasValue, 'Pre-condicao: HasValue deveria ser True');
  Assert.IsFalse(_IsNull('Descricao'),
    'Nullable<String> valendo string vazia e '''', nao NULL - quem quer '''' virando NULL pede [NullIfEmpty]');
end;

procedure TTestNullableIsNullValue.NullableString_NonEmpty_IsNotNull;
begin
  FProbe.Descricao := 'x';
  Assert.IsFalse(_IsNull('Descricao'),
    'Nullable<String> com texto nunca foi nulo');
end;

procedure TTestNullableIsNullValue.NullableBoolean_Unassigned_IsNull;
begin
  Assert.IsTrue(_IsNull('Ativo'),
    'Nullable<Boolean> sem atribuicao tem de continuar NULL');
end;

procedure TTestNullableIsNullValue.NullableBoolean_False_IsNotNull;
begin
  FProbe.Ativo := False;
  Assert.IsFalse(_IsNull('Ativo'),
    'Nullable<Boolean> valendo False e FALSE, nao NULL');
end;

procedure TTestNullableIsNullValue.NotNullRestriction_ExemptsEvenWithoutValue;
begin
  // Escotilha existente: com [Restrictions([NotNull])] o resolvedor nem roda,
  // mesmo com HasValue = False.
  Assert.IsFalse(FProbe.CodigoNotNull.HasValue, 'Pre-condicao: HasValue deveria ser False');
  Assert.IsFalse(_IsNull('CodigoNotNull'),
    'IsNotNull tem de continuar isentando antes de qualquer resolucao');
end;

procedure TTestNullableIsNullValue.NullIfEmpty_OnNullable_ZeroStillNull;
begin
  FProbe.CodigoOptIn := 0;
  Assert.IsTrue(FProbe.CodigoOptIn.HasValue, 'Pre-condicao: HasValue deveria ser True');
  Assert.IsTrue(_IsNull('CodigoOptIn'),
    'Quem PEDIU [NullIfEmpty] num Nullable continua recebendo NULL no valor default');
end;

procedure TTestNullableIsNullValue.NullIfEmpty_OnPlainString_EmptyStillNull;
begin
  FProbe.Observacao := '';
  Assert.IsTrue(_IsNull('Observacao'),
    '[NullIfEmpty] sobre String pura com '''' continua nulo - o opt-in nao pode quebrar');
end;

procedure TTestNullableIsNullValue.NullIfEmpty_OnPlainString_NonEmptyIsNotNull;
begin
  FProbe.Observacao := 'x';
  Assert.IsFalse(_IsNull('Observacao'),
    '[NullIfEmpty] sobre String pura com texto nao e nulo');
end;

procedure TTestNullableIsNullValue.NullIfEmpty_OnPlainInteger_ZeroStillNull;
begin
  FProbe.Quantidade := 0;
  // Fixa o comportamento de HOJE do atributo, que e mais largo do que a linha
  // de reference-api.md ("Converts empty string to null"). Esta rodada nao
  // estreita o opt-in; so o desacopla do Nullable.
  Assert.IsTrue(_IsNull('Quantidade'),
    '[NullIfEmpty] sobre Integer puro com 0 continua nulo (comportamento vigente)');
end;

end.
