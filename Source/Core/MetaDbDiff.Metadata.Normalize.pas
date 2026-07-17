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

  Fachada de normalizacao usada TANTO pelo Core (comparacao no
  MetaDbDiff.Database.Factory) QUANTO pelos extractors por dialeto
  (Source\Drivers). Ao viver numa unit neutra do Core, evita o acoplamento
  invertido apontado em review anterior (PostgreSQL -> Firebird) e permite ao
  lado MASTER aplicar EXATAMENTE a mesma canonizacao aplicada pelos extractors.

  Estilo Delphi (regra do dono): nada de funcoes livres no escopo de unit - a API
  e exposta como class functions estaticas de TMetadataNormalizer (idioma de
  fachada de TMappingExplorer); metodos private levam prefixo '_'; nenhuma
  variavel de loop 'I' - contadores sao LFor/LIndex.

  IMPORTANTE: estes helpers so normalizam o texto usado na COMPARACAO. O script
  armazenado (usado no CREATE) permanece intacto - o create emite o texto
  original, nunca o normalizado.
}

unit MetaDbDiff.Metadata.Normalize;

interface

type
  /// <summary>
  ///   Fachada estatica de normalizacao de metadados (checks e scripts de
  ///   view/trigger). Sem estado; todos os metodos sao class functions.
  /// </summary>
  TMetadataNormalizer = class
  strict private
    class function _IsWhitespaceChar(const AChar: Char): Boolean; static; inline;
  public
    /// <summary>
    ///   Canoniza a condicao de um CHECK vinda do catalogo para o formato
    ///   esperado pelo gerador (que reconstroi "CHECK (...)"). Compartilhada entre
    ///   os extractors Firebird (RDB$TRIGGER_SOURCE) e PostgreSQL
    ///   (pg_get_constraintdef), que entregam "CHECK (<cond>)", e tambem pelo lado
    ///   MASTER do compare (Database.Factory) para o Condition cru do atributo
    ///   [Check].
    ///     1) remove o prefixo CHECK;
    ///     2) remove pares de parenteses EXTERNOS BALANCEADOS iterativamente,
    ///        preservando expressoes como "(A) OR (B)".
    ///   Ex.: 'CHECK ((AGE > 18))' -> 'AGE > 18'; 'CHECK ((A) OR (B))' -> '(A) OR (B)'.
    /// </summary>
    class function CanonicalizeCheckCondition(const ASource: String): String; static;
    /// <summary>
    ///   Remove a palavra-chave DEFAULT (e um '=' opcional) do inicio de um
    ///   default_source vindo do catalogo, deixando SO A EXPRESSAO. Compartilhada
    ///   entre o extractor de COLUNAS (rdb$default_source ja embrulhava "DEFAULT x")
    ///   e o de DOMINIOS (FRENTE 15): sem isto o gerador re-adicionaria a keyword,
    ///   produzindo "DEFAULT DEFAULT 0". Mesma normalizacao (UpperCase + Trim) do
    ///   caminho de colunas do Firebird, para consistencia de comparacao.
    ///   Ex.: 'DEFAULT 0' -> '0'; 'DEFAULT = 0' -> '0'; '' -> ''.
    /// </summary>
    class function StripDefaultKeyword(const ASource: String): String; static;
    /// <summary>
    ///   Normaliza um script (VIEW/TRIGGER) SO PARA FINS DE COMPARACAO: colapsa
    ///   qualquer sequencia de whitespace (espaco, TAB, CR, LF, form feed) num
    ///   unico espaco e faz Trim. NAO altera caixa (a comparacao usa CompareText,
    ///   ja case-insensitive). Whitespace DENTRO de literais de string (entre
    ///   aspas simples) e PRESERVADO verbatim (scanner com estado de aspas), pois
    ///   ali o espaco e significativo. O script ORIGINAL nunca e tocado.
    /// </summary>
    class function NormalizeScript(const AScript: String): String; static;
    /// <summary>
    ///   Remove o cabecalho "CREATE [OR ALTER] VIEW <nome> AS" de uma definicao de
    ///   view, deixando SO O CORPO (o SELECT). Necessario porque alguns catalogos
    ///   (MSSQL sys.sql_modules.definition, SQLite sqlite_master.sql) devolvem o
    ///   CREATE VIEW COMPLETO, enquanto PostgreSQL/MySQL/Firebird devolvem so o
    ///   corpo. Sem isto o recreate embrulharia "CREATE VIEW %s AS <CREATE VIEW ...>"
    ///   (invalido). Case-insensitive e tolerante a whitespace/brackets/aspas no
    ///   nome; se o padrao nao for reconhecido, devolve o texto original intacto.
    /// </summary>
    class function StripCreateViewPrefix(const AScript: String): String; static;
  end;

implementation

uses
  SysUtils;

{ TMetadataNormalizer }

class function TMetadataNormalizer._IsWhitespaceChar(const AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9) or (AChar = #10) or (AChar = #13) or
            (AChar = #12);
end;

class function TMetadataNormalizer.CanonicalizeCheckCondition(const ASource: String): String;

  // Remove o par de parenteses mais externo apenas se '(' inicial e ')' final
  // formarem um par CASADO que envolve a expressao inteira. Conta a profundidade:
  // se ela zerar antes do ultimo caractere, o '(' inicial NAO envolve tudo (ex.:
  // "(A) OR (B)" zera no ')' de (A)) e nada e removido.
  function StripOuterBalancedParens(const S: String): String;
  var
    LDepth, LFor: Integer;
    LWrapped: Boolean;
  begin
    Result := S;
    if (Length(Result) < 2) or (Result[1] <> '(') or (Result[Length(Result)] <> ')') then
      Exit;
    LDepth := 0;
    LWrapped := True;
    for LFor := 1 to Length(Result) do
    begin
      if Result[LFor] = '(' then
        Inc(LDepth)
      else if Result[LFor] = ')' then
        Dec(LDepth);
      if (LDepth = 0) and (LFor < Length(Result)) then
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

class function TMetadataNormalizer.StripDefaultKeyword(const ASource: String): String;
var
  LPos: Integer;
begin
  // Mesma logica do ExtractDefaultValue do extractor de colunas Firebird (que
  // agora delega aqui): UpperCase + Trim, remove "DEFAULT" e "=" iniciais.
  Result := UpperCase(Trim(ASource));
  if Length(Result) > 0 then
  begin
    LPos := Pos('DEFAULT', Result);
    if LPos = 1 then
      Delete(Result, 1, 7);
    LPos := Pos('=', Result);
    if LPos = 1 then
      Delete(Result, 1, 1);
  end;
  Result := Trim(Result);
end;

class function TMetadataNormalizer.NormalizeScript(const AScript: String): String;
var
  LBuilder: TStringBuilder;
  LFor: Integer;
  LInWhitespace: Boolean;
  LInString: Boolean;
  LChar: Char;
begin
  LBuilder := TStringBuilder.Create(Length(AScript));
  try
    LInWhitespace := False;
    LInString := False;
    for LFor := 1 to Length(AScript) do
    begin
      LChar := AScript[LFor];
      if LInString then
      begin
        // Dentro de um literal: copia TUDO verbatim (whitespace e significativo).
        // A aspa simples encerra o literal; se for parte de um escape '' (aspas
        // duplas), o proximo caractere reabre o literal no ramo abaixo, e o par
        // acaba copiado literalmente de qualquer forma.
        LBuilder.Append(LChar);
        if LChar = '''' then
          LInString := False;
        LInWhitespace := False;
        Continue;
      end;
      if LChar = '''' then
      begin
        if LInWhitespace and (LBuilder.Length > 0) then
          LBuilder.Append(' ');
        LInWhitespace := False;
        LBuilder.Append(LChar);
        LInString := True;
        Continue;
      end;
      // Trata espaco, TAB, CR, LF e form feed como um unico separador logico.
      if _IsWhitespaceChar(LChar) then
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

class function TMetadataNormalizer.StripCreateViewPrefix(const AScript: String): String;
var
  LUpper: String;
  LViewPos, LIndex, LLen: Integer;
begin
  Result := AScript;
  LLen := Length(AScript);
  if LLen = 0 then
    Exit;
  LUpper := UpperCase(AScript);
  // Localiza a palavra-chave VIEW (em "CREATE VIEW"/"CREATE OR ALTER VIEW"/
  // "ALTER VIEW") como token isolado (bordas em whitespace, bracket ou aspas).
  LViewPos := 0;
  LIndex := 1;
  while LIndex <= LLen - 3 do
  begin
    if (LUpper[LIndex] = 'V') and (LUpper[LIndex + 1] = 'I') and
       (LUpper[LIndex + 2] = 'E') and (LUpper[LIndex + 3] = 'W') and
       ((LIndex = 1) or _IsWhitespaceChar(LUpper[LIndex - 1])) and
       ((LIndex + 4 > LLen) or _IsWhitespaceChar(LUpper[LIndex + 4]) or
        (LUpper[LIndex + 4] = '"') or (LUpper[LIndex + 4] = '[')) then
    begin
      LViewPos := LIndex;
      Break;
    end;
    Inc(LIndex);
  end;
  if LViewPos = 0 then
    Exit;                      // nao parece "... VIEW ..."; devolve intacto.
  // A partir de VIEW, acha o primeiro token AS isolado (bordas em whitespace): e
  // o separador entre o cabecalho e o corpo. O nome (com brackets/aspas/schema)
  // fica entre VIEW e esse AS.
  LIndex := LViewPos + 4;
  while LIndex <= LLen - 1 do
  begin
    if (LUpper[LIndex] = 'A') and (LUpper[LIndex + 1] = 'S') and
       (LIndex - 1 >= 1) and _IsWhitespaceChar(LUpper[LIndex - 1]) and
       ((LIndex + 2 > LLen) or _IsWhitespaceChar(LUpper[LIndex + 2])) then
    begin
      Result := Trim(Copy(AScript, LIndex + 2, MaxInt));
      Exit;
    end;
    Inc(LIndex);
  end;
  // AS nao encontrado: devolve o original (tolerante).
end;

end.
