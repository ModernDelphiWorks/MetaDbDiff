# MetaDbDiff — Test Suite (DUnitX)

Suite de testes unitários do MetaDbDiff. Não requer servidor de banco de dados:
os testes de extração usam uma conexão FireDAC "casca" (nunca aberta) apenas
para informar o dialeto.

## Unidades

| Unit | Cobre |
| --- | --- |
| `Test.MetaDbDiff.Entities.pas` | Entidades de teste decoradas (`[Table]`, `[Column]`, `[PrimaryKey]` simples/composta, `[ForeignKey]`, `[Indexe]`, `[Check]`, `[Sequence]`, `[Dictionary]`, `[Restrictions]`) e o registro via `TRegisterClass.RegisterEntity` |
| `Test.MetaDbDiff.Mapping.pas` | Leitura do mapeamento por RTTI via `TMappingExplorer` (Table/Column/PrimaryKey/ForeignKey/Indexe/Check/Sequence + cache e comportamento one-shot do registro) |
| `Test.MetaDbDiff.DDL.Generator.pas` | Geração de DDL (string pura) dos drivers Firebird e MSSQL a partir de objetos MIK montados à mão |
| `Test.MetaDbDiff.Metadata.Model.pas` | Extração modelo→MIK (`TModelMetadata`) sem conexão real + integração entidade→MIK→DDL |

## Requisitos

- Delphi com FireDAC (validado com RAD Studio 37.0; deve funcionar em versões
  com suporte a atributos e generics).
- DUnitX — embarcado na IDE em `$(BDS)\source\DUnitX` (ou clone de
  <https://github.com/VSoftTechnologies/DUnitX>).
- DataEngine — irmão deste módulo no layout `.modules`
  (`..\..\DataEngine` a partir da raiz do MetaDbDiff).

## Compilar e rodar (linha de comando)

O `TestMetaDbDiff.dproj` já traz os search paths relativos ao layout `.modules`:
`..\Source\Core;..\Source\Drivers;..\..\DataEngine\Source\Core;..\..\DataEngine\Source\Drivers`
além de `$(DUnitX)`.

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd "Test Delphi"
msbuild TestMetaDbDiff.dproj /t:Build /p:Config=Debug /p:Platform=Win32
TestMetaDbDiff.exe --exit:Continue
```

Fora da IDE a variável `$(DUnitX)` normalmente não existe; nesse caso (ou se o
checkout não estiver no layout `.modules`) sobrescreva o search path inteiro:

```bat
msbuild TestMetaDbDiff.dproj /t:Build /p:Config=Debug /p:Platform=Win32 ^
  /p:DCC_UnitSearchPath="C:\Program Files (x86)\Embarcadero\Studio\37.0\source\DUnitX;..\Source\Core;..\Source\Drivers;<caminho>\DataEngine\Source\Core;<caminho>\DataEngine\Source\Drivers"
```

O runner devolve exit code ≠ 0 se algum teste falhar e grava
`dunitx-results.xml` (formato NUnit) no diretório corrente.

## CI

Não há workflow de CI para esta suíte: os runners públicos do GitHub Actions
não têm compilador Delphi e o repositório não possui runner self-hosted
(`.github/workflows/` contém apenas o deploy da documentação). Rode a suíte
localmente antes de abrir PR.

## Armadilhas conhecidas (leia antes de escrever testes)

- `TRegisterClass.GetAllEntityClass/GetAllViewClass/GetAllTriggerClass`
  devolvem uma **cópia (snapshot)** da lista interna e NÃO a esvaziam mais:
  leituras repetidas continuam retornando o mesmo conteúdo. Isso é o que
  permite um segundo `TMappingRepository`/uma segunda comparação no mesmo
  processo. Ainda assim, registre entidades em `initialization` — o cache do
  `TMappingExplorer.GetRepositoryMapping` (ver abaixo) continua valendo: ele só
  monta o `TMappingRepository` na primeira chamada, então registros feitos
  depois dela não aparecem no snapshot cacheado.
- `TMappingExplorer` cacheia todo `GetMapping*` por `ClassName` e cacheia o
  `TMappingRepository` na primeira chamada de `GetRepositoryMapping`.
- Comparações de SQL devem normalizar whitespace: os geradores emitem espaços
  duplos (ex.: `CREATE  INDEX`, `NOME  VARCHAR(60)`) e quebras de linha.
