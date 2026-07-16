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

{ @abstract(MetaDbDiff - Neutral metadata normalization helpers.)
  @created(16 Jul 2026)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)

  Helpers de normalizacao usados TANTO pelo Core (comparacao no
  MetaDbDiff.Database.Factory) QUANTO pelos extractors por dialeto
  (Source\Drivers). Ao viver numa unit neutra do Core, evita o acoplamento
  invertido apontado em review anterior (PostgreSQL -> Firebird) e permite ao
  lado MASTER aplicar EXATAMENTE a mesma canonizacao aplicada pelos extractors.

  IMPORTANTE: estes helpers so normalizam o texto usado na COMPARACAO. O script
  armazenado (usado no CREATE) permanece intacto - o create emite o texto
  original, nunca o normalizado.
}

unit MetaDbDiff.Metadata.Normalize;

interface

/// <summary>
///   Canoniza a condicao de um CHECK vinda do catalogo para o formato esperado
///   pelo gerador (que reconstroi "CHECK (...)"). Compartilhada entre os
///   extractors Firebird (RDB$TRIGGER_SOURCE) e PostgreSQL (pg_get_constraintdef),
///   que entregam a definicao completa "CHECK (<cond>)", e AGORA tambem pelo lado
///   MASTER do compare (Database.Factory) para o Condition cru do atributo [Check].
///     1) remove o prefixo CHECK;
///     2) remove pares de parenteses EXTERNOS BALANCEADOS de forma iterativa,
///        preservando expressoes como "(A) OR (B)".
///   Exemplos: 'CHECK ((AGE > 18))' -> 'AGE > 18'; 'CHECK ((A) OR (B))' -> '(A) OR (B)'.
/// </summary>
function CanonicalizeCheckCondition(const ASource: String): String;

/// <summary>
///   Normaliza um script (VIEW/TRIGGER) SO PARA FINS DE COMPARACAO: colapsa
///   qualquer sequencia de espacos em branco (espaco, TAB, CR, LF, form feed) em
///   um unico espaco e faz Trim. NAO altera caixa (a comparacao usa CompareText,
///   que ja e case-insensitive). Assim, dois scripts equivalentes que diferem
///   apenas em espacamento/quebras de linha NAO geram um drop+create espurio.
///   O script ORIGINAL (armazenado) nunca e tocado - so a copia comparada.
/// </summary>
function NormalizeScript(const AScript: String): String;

implementation

uses
  SysUtils;

function CanonicalizeCheckCondition(const ASource: String): String;

  // Remove o par de parenteses mais externo apenas se '(' inicial e ')' final
  // formarem um par CASADO que envolve a expressao inteira. Conta a profundidade:
  // se ela zerar antes do ultimo caractere, o '(' inicial NAO envolve tudo (ex.:
  // "(A) OR (B)" zera no ')' de (A)) e nada e removido.
  function StripOuterBalancedParens(const S: String): String;
  var
    LDepth, I: Integer;
    LWrapped: Boolean;
  begin
    Result := S;
    if (Length(Result) < 2) or (Result[1] <> '(') or (Result[Length(Result)] <> ')') then
      Exit;
    LDepth := 0;
    LWrapped := True;
    for I := 1 to Length(Result) do
    begin
      if Result[I] = '(' then
        Inc(LDepth)
      else if Result[I] = ')' then
        Dec(LDepth);
      if (LDepth = 0) and (I < Length(Result)) then
      begin
        LWrapped := False;
        Break;
      end;
    end;
    if LWrapped and (LDepth = 0) then
      Result := Copy(Result, 2, Length(Result) - 2);
  end;

var
  LPrevious: String;
begin
  Result := Trim(ASource);
  // 1) Remove a palavra-chave CHECK (o gerador reconstroi "CHECK (...)").
  if UpperCase(Copy(Result, 1, 5)) = 'CHECK' then
    Result := Trim(Copy(Result, 6, Length(Result)));
  // 2) Descasca pares externos balanceados ate estabilizar.
  repeat
    LPrevious := Result;
    Result := Trim(StripOuterBalancedParens(Result));
  until Result = LPrevious;
end;

function NormalizeScript(const AScript: String): String;
var
  LBuilder: TStringBuilder;
  I: Integer;
  LInWhitespace: Boolean;
  LChar: Char;
begin
  LBuilder := TStringBuilder.Create(Length(AScript));
  try
    LInWhitespace := False;
    for I := 1 to Length(AScript) do
    begin
      LChar := AScript[I];
      // Trata espaco, TAB, CR, LF e form feed como um unico separador logico.
      if (LChar = ' ') or (LChar = #9) or (LChar = #10) or (LChar = #13) or
         (LChar = #12) then
      begin
        LInWhitespace := True;
      end
      else
      begin
        // Colapsa a sequencia de whitespace acumulada num unico espaco, mas nunca
        // no inicio (Trim implicito na borda esquerda: so insere apos algum token).
        if LInWhitespace and (LBuilder.Length > 0) then
          LBuilder.Append(' ');
        LInWhitespace := False;
        LBuilder.Append(LChar);
      end;
    end;
    // O whitespace final pendente nunca e emitido (Trim implicito na direita).
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

end.
