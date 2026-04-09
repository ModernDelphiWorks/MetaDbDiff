{
      ORM Brasil � um ORM simples e descomplicado para quem utiliza Delphi

                   Copyright (c) 2016, Isaque Pinheiro
                          All rights reserved.

                    GNU Lesser General Public License
                      Vers�o 3, 29 de junho de 2007

       Copyright (C) 2007 Free Software Foundation, Inc. <http://fsf.org/>
       A todos � permitido copiar e distribuir c�pias deste documento de
       licen�a, mas mud�-lo n�o � permitido.

       Esta vers�o da GNU Lesser General Public License incorpora
       os termos e condi��es da vers�o 3 da GNU General Public License
       Licen�a, complementado pelas permiss�es adicionais listadas no
       arquivo LICENSE na pasta principal.
}

{
  @abstract(ORMBr Framework.)
  @created(20 Jul 2016)
  @author(Isaque Pinheiro <isaquepsp@gmail.com>)
  @abstract(Website : http://www.ormbr.com.br)
  @abstract(Telagram : https://t.me/ormbr)
}

unit MetaDbDiff.Types.Mapping;

interface

type
//  {$SCOPEDENUMS ON}
  TRuleAction = (None, Cascade, SetNull, SetDefault);
  TSortingOrder = (NoSort, Ascending, Descending);
  TMultiplicity = (OneToOne, OneToMany, ManyToOne, ManyToMany);
  TGenerated = (Never, Insert, Always);
  TJoin = (InnerJoin, LeftJoin, RightJoin, FullJoin);
  TAutoIncType = (NotInc, AutoInc);
  TGeneratorType = (NoneInc,
                    SequenceInc,
                    TableInc,
                    GuidInc, // 'deprected Use Guid32Inc, Guid36Inc or Guid38Inc'
                    Guid38Inc,
                    Guid36Inc,
                    Guid32Inc);
  TRestriction = (NotNull,
                  NoInsert,
                  NoUpdate,
                  NoValidate,
                  Unique,
                  Hidden,
                  VirtualData);
  TRestrictions = set of TRestriction;
  TCascadeAction = (CascadeNone,
                    CascadeAutoInc,
                    CascadeInsert,
                    CascadeUpdate,
                    CascadeDelete);
  TCascadeActions = set of TCascadeAction;
  TMasterEvent = (AutoPost, AutoEdit, AutoInsert);
  TMasterEvents = set of TMasterEvent;
  TEnumType = (etChar, etString, etInteger, etBoolean);
  TFieldEvent = (onChange, onGetText, onSetText, onValidate);
  TFieldEvents = set of TFieldEvent;
//  {$SCOPEDENUMS OFF}

implementation

end.
