{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Shared test entities decorated with the mapping attributes.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------

  IMPORTANT - one-shot registry behaviour:
  TRegisterClass.GetAllEntityClass/GetAllViewClass/GetAllTriggerClass EMPTY the
  internal list after the first read (see MetaDbDiff.Mapping.Register.pas), and
  TMappingExplorer.GetRepositoryMapping caches the resulting TMappingRepository
  the first time it is invoked. Therefore:
    - Entities MUST be registered in an initialization section (before any
      test runs), so that the first call to GetRepositoryMapping - whenever it
      happens - snapshots them.
    - Tests must NEVER call TRegisterClass.GetAllEntityClass directly, or they
      would drain the list and starve GetRepositoryMapping.
  TMappingExplorer also caches every GetMapping* result per ClassName, so all
  fixtures observe the same (first) mapping instances.
}

unit Test.MetaDbDiff.Entities;

interface

uses
  DB,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Mapping.Attributes,
  MetaDbDiff.Mapping.Register;

type
  [Table('CLIENTE', 'Tabela de clientes')]
  [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc,
    TSortingOrder.NoSort, False, 'Chave primaria do cliente')]
  [Sequence('SEQ_CLIENTE')]
  [Indexe('IDX_CLIENTE_NOME', 'NOME', 'Indice por nome')]
  [Check('CK_CLIENTE_IDADE', 'IDADE >= 0', 'Idade nao pode ser negativa')]
  TClienteTest = class
  private
    FId: Integer;
    FNome: String;
    FIdade: Integer;
    FSaldo: Double;
    FCriadoEm: TDateTime;
  public
    [Restrictions([TRestriction.NotNull])]
    [Column('ID', ftInteger)]
    [Dictionary('Id', 'Id obrigatorio')]
    property Id: Integer read FId write FId;

    [Restrictions([TRestriction.NotNull])]
    [Column('NOME', ftString, 60)]
    [Dictionary('Nome', 'Nome invalido', 'SEM NOME')]
    property Nome: String read FNome write FNome;

    [Column('IDADE', ftInteger)]
    property Idade: Integer read FIdade write FIdade;

    [Column('SALDO', ftBCD, 18, 2)]
    property Saldo: Double read FSaldo write FSaldo;

    [Column('CRIADO_EM', ftDateTime)]
    property CriadoEm: TDateTime read FCriadoEm write FCriadoEm;
  end;

  [Table('PEDIDO', 'Tabela de pedidos')]
  [PrimaryKey('ID_EMPRESA, ID_PEDIDO', 'Chave composta do pedido')]
  [ForeignKey('FK_PEDIDO_CLIENTE', 'ID_CLIENTE', 'CLIENTE', 'ID',
    TRuleAction.Cascade, TRuleAction.SetNull, 'FK para cliente')]
  [Indexe('IDX_PEDIDO_UNQ', 'ID_EMPRESA, ID_PEDIDO', TSortingOrder.NoSort,
    True, 'Indice unico da chave composta')]
  TPedidoTest = class
  private
    FIdEmpresa: Integer;
    FIdPedido: Integer;
    FIdCliente: Integer;
    FValorTotal: Currency;
  public
    [Restrictions([TRestriction.NotNull])]
    [Column('ID_EMPRESA', ftInteger)]
    property IdEmpresa: Integer read FIdEmpresa write FIdEmpresa;

    [Restrictions([TRestriction.NotNull])]
    [Column('ID_PEDIDO', ftInteger)]
    property IdPedido: Integer read FIdPedido write FIdPedido;

    [Column('ID_CLIENTE', ftInteger)]
    property IdCliente: Integer read FIdCliente write FIdCliente;

    [Column('VALOR_TOTAL', ftCurrency, 15, 2)]
    property ValorTotal: Currency read FValorTotal write FValorTotal;
  end;

implementation

initialization
  // Registered BEFORE any test runs - see the one-shot warning in the header.
  TRegisterClass.RegisterEntity(TClienteTest);
  TRegisterClass.RegisterEntity(TPedidoTest);

end.
