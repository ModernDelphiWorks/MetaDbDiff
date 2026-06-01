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
