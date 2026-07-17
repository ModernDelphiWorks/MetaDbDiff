{
  ------------------------------------------------------------------------------
  MetaDbDiff - Test Suite
  Concurrency / thread-safety of TMappingExplorer.

  Deterministic race reproducer for the lazy per-ClassName caches of
  TMappingExplorer (P1 of the delphi-janus-specialist review, root cause of the
  residual ~1-3% of AV under concurrent reads measured in backend PR #307).

  Every GetMapping* getter used to do an unlocked ContainsKey -> FContext.GetType
  -> Add. Under N concurrent readers with COLD caches this triples up:
    * TOCTOU: two threads both miss ContainsKey then both Add the same key =>
      EListError "Duplicate key".
    * TDictionary Grow/Rehash while another thread reads/adds => nil-deref AV
      ("Read of address 0x00000000").
    * A single shared TRttiContext (FContext) hit by concurrent GetType => RTL
      RTTI pool corruption / AV.

  This fixture drives that path on purpose: it reinitialises the explorer to a
  cold state (public ExecuteDestroy/ExecuteCreate), then fires THREADS workers
  that hammer ALL getters over a set of decorated classes, and repeats ROUNDS
  times. Each worker swallows and counts exceptions; the test asserts ZERO
  failures. Against the unlocked explorer it fails (duplicate-key / AV); with the
  TCriticalSection serializing each getter it passes across all rounds.

  SPDX-License-Identifier: MIT
  Copyright (c) 2025-2026 Isaque Pinheiro
  ------------------------------------------------------------------------------
}

unit Test.MetaDbDiff.Concurrency;

interface

uses
  DB,
  Classes,
  SysUtils,
  SyncObjs,
  Generics.Collections,
  DUnitX.TestFramework,
  MetaDbDiff.Types.Mapping,
  MetaDbDiff.Mapping.Attributes,
  MetaDbDiff.Mapping.Classes,
  MetaDbDiff.Mapping.Explorer;

type
  // --- A batch of distinct decorated classes: distinct ClassName keys maximise
  //     the number of concurrent Add()s per round, forcing dictionary rehash. ---
  [Table('CONC01', 'c01')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  [Sequence('SEQ_CONC01')] [Indexe('IDX_CONC01', 'NOME', 'ix')] [Check('CK_CONC01', 'ID >= 0', 'ck')]
  TConc01 = class
  private
    FId: Integer; FNome: String;
  public
    [Restrictions([TRestriction.NotNull])] [Column('ID', ftInteger)] property Id: Integer read FId write FId;
    [Column('NOME', ftString, 40)] property Nome: String read FNome write FNome;
  end;
  [Table('CONC02', 'c02')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc02 = class
  private
    FId: Integer; FNome: String;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
    [Column('NOME', ftString, 40)] property Nome: String read FNome write FNome;
  end;
  [Table('CONC03', 'c03')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc03 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC04', 'c04')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc04 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC05', 'c05')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc05 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC06', 'c06')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc06 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC07', 'c07')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc07 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC08', 'c08')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc08 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC09', 'c09')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc09 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC10', 'c10')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc10 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC11', 'c11')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc11 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;
  [Table('CONC12', 'c12')] [PrimaryKey('ID', TAutoIncType.AutoInc, TGeneratorType.SequenceInc, TSortingOrder.NoSort, False, '')]
  TConc12 = class
  private
    FId: Integer;
  public
    [Column('ID', ftInteger)] property Id: Integer read FId write FId;
  end;

  [TestFixture]
  TTestConcurrency = class
  public
    [Test]
    procedure ColdCacheGetters_AreThreadSafe;
  end;

implementation

var
  GClasses: TArray<TClass>;
  GFailures: Integer;      // touched via TInterlocked only
  GFirstErrLock: TCriticalSection;
  GFirstError: String;

type
  TgetterWorker = class(TThread)
  private
    FGate: TEvent;
    procedure HammerAll;
  protected
    procedure Execute; override;
  public
    constructor Create(AGate: TEvent);
  end;

constructor TgetterWorker.Create(AGate: TEvent);
begin
  FGate := AGate;
  inherited Create(False); // start now, will block on the gate
end;

procedure TgetterWorker.HammerAll;
var
  LClass: TClass;
begin
  for LClass in GClasses do
  begin
    // Exercise EVERY lazy getter of TMappingExplorer for this ClassName. On a
    // cold cache each of these is a ContainsKey -> GetType -> Add race.
    TMappingExplorer.GetMappingTable(LClass);
    TMappingExplorer.GetMappingColumn(LClass);
    TMappingExplorer.GetMappingPrimaryKey(LClass);
    TMappingExplorer.GetMappingPrimaryKeyColumns(LClass);
    TMappingExplorer.GetMappingSequence(LClass);
    TMappingExplorer.GetMappingOrderBy(LClass);
    TMappingExplorer.GetMappingCalcField(LClass);
    TMappingExplorer.GetMappingAssociation(LClass);
    TMappingExplorer.GetMappingJoinColumn(LClass);
    TMappingExplorer.GetMappingForeignKey(LClass);
    TMappingExplorer.GetMappingIndexe(LClass);
    TMappingExplorer.GetMappingCheck(LClass);
    TMappingExplorer.GetMappingTrigger(LClass);
    TMappingExplorer.GetMappingView(LClass);
    TMappingExplorer.GetMappingFieldEvents(LClass);
    TMappingExplorer.GetMappingEnumeration(LClass);
    TMappingExplorer.GetNotServerUse(LClass);
    TMappingExplorer.GetRESTReadOnly(LClass);
    TMappingExplorer.GetRESTAllowVerbs(LClass);
  end;
end;

procedure TgetterWorker.Execute;
begin
  // Barrier: every worker waits here, so all of them slam the cold caches at
  // (nearly) the same instant, which is what surfaces the race.
  FGate.WaitFor(INFINITE);
  try
    HammerAll;
  except
    on E: Exception do
    begin
      TInterlocked.Increment(GFailures);
      GFirstErrLock.Enter;
      try
        if GFirstError = '' then
          GFirstError := E.ClassName + ': ' + E.Message;
      finally
        GFirstErrLock.Leave;
      end;
    end;
  end;
end;

{ TTestConcurrency }

procedure TTestConcurrency.ColdCacheGetters_AreThreadSafe;
const
  ROUNDS  = 60;
  THREADS = 16;
var
  LRound, I: Integer;
  LGate: TEvent;
  LWorkers: array of TgetterWorker;
begin
  GFailures := 0;
  GFirstError := '';
  SetLength(LWorkers, THREADS);
  for LRound := 1 to ROUNDS do
  begin
    // Reinitialise the explorer to a COLD state (public API). Every dictionary
    // is empty again, so this round's getters all take the miss path.
    TMappingExplorer.ExecuteDestroy;
    TMappingExplorer.ExecuteCreate;

    LGate := TEvent.Create(nil, True, False, ''); // manual-reset, initially off
    try
      for I := 0 to THREADS - 1 do
        LWorkers[I] := TgetterWorker.Create(LGate);
      // Release all workers simultaneously.
      LGate.SetEvent;
      for I := 0 to THREADS - 1 do
      begin
        LWorkers[I].WaitFor;
        LWorkers[I].Free;
      end;
    finally
      LGate.Free;
    end;
  end;

  Assert.AreEqual(0, GFailures,
    Format('Concurrent cold-cache getters raced across %d rounds x %d threads. First error: %s',
      [ROUNDS, THREADS, GFirstError]));
end;

initialization
  GClasses := TArray<TClass>.Create(
    TConc01, TConc02, TConc03, TConc04, TConc05, TConc06,
    TConc07, TConc08, TConc09, TConc10, TConc11, TConc12);
  GFirstErrLock := TCriticalSection.Create;
  TDUnitX.RegisterTestFixture(TTestConcurrency);

finalization
  GFirstErrLock.Free;

end.
