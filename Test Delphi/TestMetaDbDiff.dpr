program TestMetaDbDiff;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}{$STRONGLINKTYPES ON}
uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ENDIF }
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  Test.MetaDbDiff.Entities in 'Test.MetaDbDiff.Entities.pas',
  Test.MetaDbDiff.Mapping in 'Test.MetaDbDiff.Mapping.pas',
  Test.MetaDbDiff.DDL.Generator in 'Test.MetaDbDiff.DDL.Generator.pas',
  Test.MetaDbDiff.Metadata.Model in 'Test.MetaDbDiff.Metadata.Model.pas',
  Test.MetaDbDiff.Policy in 'Test.MetaDbDiff.Policy.pas',
  MetaDbDiff.Compare.Options in '..\Source\Core\MetaDbDiff.Compare.Options.pas',
  Test.MetaDbDiff.Fakes in 'Test.MetaDbDiff.Fakes.pas',
  Test.MetaDbDiff.Sequencer in 'Test.MetaDbDiff.Sequencer.pas',
  Test.MetaDbDiff.Integration in 'Test.MetaDbDiff.Integration.pas',
  MetaDbDiff.Mapping.Attributes in '..\Source\Core\MetaDbDiff.Mapping.Attributes.pas',
  MetaDbDiff.Mapping.Classes in '..\Source\Core\MetaDbDiff.Mapping.Classes.pas',
  MetaDbDiff.Mapping.Exceptions in '..\Source\Core\MetaDbDiff.Mapping.Exceptions.pas',
  MetaDbDiff.Mapping.Explorer in '..\Source\Core\MetaDbDiff.Mapping.Explorer.pas',
  MetaDbDiff.Mapping.Popular in '..\Source\Core\MetaDbDiff.Mapping.Popular.pas',
  MetaDbDiff.Mapping.Register in '..\Source\Core\MetaDbDiff.Mapping.Register.pas',
  MetaDbDiff.Mapping.Repository in '..\Source\Core\MetaDbDiff.Mapping.Repository.pas',
  MetaDbDiff.RTTI.Helper in '..\Source\Core\MetaDbDiff.RTTI.Helper.pas',
  MetaDbDiff.Database.Abstract in '..\Source\Core\MetaDbDiff.Database.Abstract.pas',
  MetaDbDiff.Database.Compare in '..\Source\Core\MetaDbDiff.Database.Compare.pas',
  MetaDbDiff.Database.Factory in '..\Source\Core\MetaDbDiff.Database.Factory.pas',
  MetaDbDiff.Database.ModelCompare in '..\Source\Core\MetaDbDiff.Database.ModelCompare.pas',
  MetaDbDiff.Metadata.Model.Factory in '..\Source\Core\MetaDbDiff.Metadata.Model.Factory.pas',
  MetaDbDiff.Database.Interfaces in '..\Source\Core\MetaDbDiff.Database.Interfaces.pas',
  MetaDbDiff.Database.Mapping in '..\Source\Core\MetaDbDiff.Database.Mapping.pas',
  MetaDbDiff.Database.MetaInfo in '..\Source\Core\MetaDbDiff.Database.MetaInfo.pas',
  MetaDbDiff.DDL.Commands in '..\Source\Core\MetaDbDiff.DDL.Commands.pas',
  MetaDbDiff.DDL.Sequencer in '..\Source\Core\MetaDbDiff.DDL.Sequencer.pas',
  MetaDbDiff.Migration.Executor in '..\Source\Core\MetaDbDiff.Migration.Executor.pas',
  MetaDbDiff.DDL.Generator in '..\Source\Core\MetaDbDiff.DDL.Generator.pas',
  MetaDbDiff.DDL.Interfaces in '..\Source\Core\MetaDbDiff.DDL.Interfaces.pas',
  MetaDbDiff.DDL.Register in '..\Source\Core\MetaDbDiff.DDL.Register.pas',
  MetaDbDiff.DDL.Generator.AbsoluteDB in '..\Source\Drivers\MetaDbDiff.DDL.Generator.AbsoluteDB.pas',
  MetaDbDiff.DDL.Generator.Firebird in '..\Source\Drivers\MetaDbDiff.DDL.Generator.Firebird.pas',
  MetaDbDiff.DDL.Generator.Firebird3 in '..\Source\Drivers\MetaDbDiff.DDL.Generator.Firebird3.pas',
  MetaDbDiff.DDL.Generator.MSSQL in '..\Source\Drivers\MetaDbDiff.DDL.Generator.MSSQL.pas',
  MetaDbDiff.DDL.Generator.MySQL in '..\Source\Drivers\MetaDbDiff.DDL.Generator.MySQL.pas',
  MetaDbDiff.DDL.Generator.Oracle in '..\Source\Drivers\MetaDbDiff.DDL.Generator.Oracle.pas',
  MetaDbDiff.DDL.Generator.PostgreSQL in '..\Source\Drivers\MetaDbDiff.DDL.Generator.PostgreSQL.pas',
  MetaDbDiff.DDL.Generator.SQLite in '..\Source\Drivers\MetaDbDiff.DDL.Generator.SQLite.pas',
  MetaDbDiff.Metadata.Firebird in '..\Source\Drivers\MetaDbDiff.Metadata.Firebird.pas',
  MetaDbDiff.Metadata.Firebird3 in '..\Source\Drivers\MetaDbDiff.Metadata.Firebird3.pas',
  MetaDbDiff.Metadata.MSSQL in '..\Source\Drivers\MetaDbDiff.Metadata.MSSQL.pas',
  MetaDbDiff.Metadata.MySQL in '..\Source\Drivers\MetaDbDiff.Metadata.MySQL.pas',
  MetaDbDiff.Metadata.Oracle in '..\Source\Drivers\MetaDbDiff.Metadata.Oracle.pas',
  MetaDbDiff.Metadata.PostgreSQL in '..\Source\Drivers\MetaDbDiff.Metadata.PostgreSQL.pas',
  MetaDbDiff.Metadata.SQLite in '..\Source\Drivers\MetaDbDiff.Metadata.SQLite.pas',
  MetaDbDiff.Types.Mapping in '..\Source\Core\MetaDbDiff.Types.Mapping.pas',
  MetaDbDiff.Metadata.DB.Factory in '..\Source\Core\MetaDbDiff.Metadata.DB.Factory.pas',
  MetaDbDiff.Metadata.Register in '..\Source\Core\MetaDbDiff.Metadata.Register.pas',
  MetaDbDiff.Metadata.Extract in '..\Source\Core\MetaDbDiff.Metadata.Extract.pas',
  MetaDbDiff.Metadata.Interfaces in '..\Source\Core\MetaDbDiff.Metadata.Interfaces.pas',
  MetaDbDiff.Metadata.Model in '..\Source\Drivers\MetaDbDiff.Metadata.Model.pas';

{$IFNDEF TESTINSIGHT}
var
  runner : ITestRunner;
  results : IRunResults;
  logger : ITestLogger;
  nunitLogger : ITestLogger;
{$ENDIF}
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    //Create the test runner
    runner := TDUnitX.CreateRunner;
    //Tell the runner to use RTTI to find Fixtures
    runner.UseRTTI := True;
    //tell the runner how we will log things
    //Log to the console window
    logger := TDUnitXConsoleLogger.Create(true);
    runner.AddLogger(logger);
    //Generate an NUnit compatible XML File
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);
    runner.FailsOnNoAsserts := False; //When true, Assertions must be made during tests;

    //Run tests
    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    //We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.
