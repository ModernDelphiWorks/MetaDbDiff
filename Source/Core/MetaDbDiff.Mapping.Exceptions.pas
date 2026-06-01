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
}

unit MetaDbDiff.Mapping.Exceptions;

interface

uses
  SysUtils,
  Rtti;

type
  EClassNotRegistered = class(Exception)
  public
    constructor Create(AClass: TClass);
  end;

  EFieldNotNull = class(Exception)
  public
    constructor Create(const ADisplayLabel: String);
  end;

  EFieldValidate = class(Exception)
  public
    constructor Create(const AField: String; const AMensagem: String);
  end;

  EMinimumValueConstraint = class(Exception)
  public
    constructor Create(const ADisplayLabel: String;
      const AValue: Double);
  end;

  EMaximumValueConstraint = class(Exception)
  public
    constructor Create(const ADisplayLabel: String; const AValue: Double);
  end;

  ENotEmptyConstraint = class(Exception)
  public
    constructor Create(const ADisplayLabel: String);
  end;

  EMaxLengthConstraint = class(Exception)
  public
    constructor Create(const ADisplayLabel: String; const MaxLength: Integer);
  end;

  EMinLengthConstraint = class(Exception)
  public
    constructor Create(const ADisplayLabel: String; const MinLength: Integer);
  end;

  EDefaultExpression = class(Exception)
  public
    constructor Create(const ADefault, AColumnName, AClassName: String);
  end;

implementation

uses
  MetaDbDiff.Mapping.Attributes;

{ EClassNotRegistered }

constructor EClassNotRegistered.Create(AClass: TClass);
begin
   inherited CreateFmt('Classe %s n�o registrada. Registre no Initialization usando TRegisterClasses.GetInstance.RegisterClass(%s)',
                       [AClass.ClassName]);
end;

{ EFieldNotNull }

constructor EFieldNotNull.Create(const ADisplayLabel: String);
begin
  inherited CreateFmt('Campo [ %s ] n�o pode ser vazio',
                      [ADisplayLabel]);
end;

{ EHighestConstraint }

constructor EMinimumValueConstraint.Create(const ADisplayLabel: String;
  const AValue: Double);
begin
  inherited CreateFmt('O valor m�nimo do campo [ %s ] permitido � [ %s ]!',
                      [ADisplayLabel, FloatToStr(AValue)]);
end;

{ EFieldValidate }

constructor EFieldValidate.Create(const AField: String; const AMensagem: String);
begin
  inherited CreateFmt('[ %s ] %s',
                      [AField, AMensagem]);
end;

{ EDefaultExpression }

constructor EDefaultExpression.Create(const ADefault, AColumnName, AClassName: String);
begin
  inherited CreateFmt('O valor Default [ %s ] do campo [ %s ] na classe [ %s ], � inv�lido!',
                      [ADefault, AColumnName, AClassName]);
end;

{ EMaximumValueConstraint }

constructor EMaximumValueConstraint.Create(const ADisplayLabel: String; const AValue: Double);
begin
  inherited CreateFmt('O valor m�ximo do campo [ %s ] permitido � [ %s ]!',
                      [ADisplayLabel, FloatToStr(AValue)]);
end;

{ ENotEmptyConstraint }

constructor ENotEmptyConstraint.Create(const ADisplayLabel: String);
begin
  inherited CreateFmt('O campo [ %s ] n�o pode ser vazio!', [ADisplayLabel]);
end;

{ EMaxLengthConstraint }

constructor EMaxLengthConstraint.Create(const ADisplayLabel: String; const MaxLength: Integer);
begin
  inherited CreateFmt('O campo [ %s ] n�o pode ter o tamanho maior que %s!', [ADisplayLabel, IntToStr(MaxLength)]);
end;

{ EMinLengthConstraint }

constructor EMinLengthConstraint.Create(const ADisplayLabel: String; const MinLength: Integer);
begin
  inherited CreateFmt('O campo [ %s ] n�o pode ter o tamanho menor que %s!', [ADisplayLabel, IntToStr(MinLength)]);
end;

end.
