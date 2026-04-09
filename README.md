# MetaDbDiff Framework for Delphi

DATABASE COMPARER BRASIL,  um comparador de estrutura de banco de dados, que nasceu do código do ORMBr que disponibiliza esse recurso, mas a um nível limitado como de criar tabelas, adicionar novos campos a tabela já existente, e outros recursos de criar PrimaryKeys, ForeignKeys e Indexes para as tabelas.

Nele pode-se comparar um banco de dados com outro banco de dados ou um banco de dados com classe modelos do ORMBr, onde será gerado um script para ser executado e atualizar o metatada do database.

Como descrito acima, podemos observar qual nos falta alguns recursos, exemplo como fazer drop e campos, tabelas, atualizar tipos de campos e até tamanho deles, assim como gerar scripts de UPDATE em geral necessários. Foi dessa necessidade, e carência de recursos mais completos, que foi decidido separar um código existente do core do ORMBr e criar um novo projeto do qual o ORMBr se tornaria dependente dele. Essa necessidade de recursos mais completos, e com a criação de um novo projeto, tendo ele somente o código com essa finalidade, poderá dar a comunidade mais poder de ajuda, sendo que os esforços estaria somente no código de comparação de database e não estaria misturado ao código do ORMBr, que levava ao receio de em qual código mexer e qual era de database compare e qual era do ORMBr.

Projeto open source MetaDbDiff (Database Compare Brasil), um código totalmente independente, o qual poderá receber ajuda e contribuições de amantes de código Open Source, e assim termos um produto totalmente confiável e funcional, que poderá ser usado com segurança por todos, e inclusive sendo recursos implementados, o próprio ORMBr que cedeu o código irá ter em si próprio mais poder de atualização de database.

<p align="center">
  <a href="https://www.isaquepinheiro.com.br">
    <img src="https://github.com/HashLoad/DBCBr/blob/master/Images/dbcbr_framework.png" width="200" height="200">
  </a>
</p>

## 🏛 Delphi Versions
Embarcadero Delphi XE e superior.

## ⚙️ Instalação
Instalação usando o [`boss install`]
```sh
boss install "https://github.com/ModernDelphiWorks/MetaDbDiff"
```

## ⚠ Dependências

:heavy_check_mark: [DataEngine Framework for Delphi/Lazarus](https://github.com/hashload/dbebr)

## ⚡️ Como usar
```Delphi
```

## ✍️ License
[![License](https://img.shields.io/badge/Licence-LGPL--3.0-blue.svg)](https://opensource.org/licenses/LGPL-3.0)

## ⛏️ Contribuição

Nossa equipe adoraria receber contribuições para este projeto open source. Se você tiver alguma ideia ou correção de bug, sinta-se à vontade para abrir uma issue ou enviar uma pull request.

[![Issues](https://img.shields.io/badge/Issues-channel-orange)](https://github.com/HashLoad/ormbr/issues)

Para enviar uma pull request, siga estas etapas:

1. Faça um fork do projeto
2. Crie uma nova branch (`git checkout -b minha-nova-funcionalidade`)
3. Faça suas alterações e commit (`git commit -am 'Adicionando nova funcionalidade'`)
4. Faça push da branch (`git push origin minha-nova-funcionalidade`)
5. Abra uma pull request

## 📬 Contato
[![Telegram](https://img.shields.io/badge/Telegram-channel-blue)](https://t.me/hashload)

## 💲 Doação
[![Doação](https://img.shields.io/badge/PagSeguro-contribua-green)](https://pag.ae/bglQrWD)
