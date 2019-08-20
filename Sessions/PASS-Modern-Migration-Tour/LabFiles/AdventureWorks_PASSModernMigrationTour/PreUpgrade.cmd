@ECHO OFF

SETLOCAL
SET SCENARIONAME=DB_Upgrade_Pre

IF "%1"=="" (
  @ECHO Warning: SQLSERVER env var undefined - assuming a default SQL instance. 
  SET SQLSERVER=.\SQL2008R2
) ELSE (
  SET SQLSERVER=%1
)

REM ========== Setup ========== 
@ECHO %date% %time% - Starting scenario %SCENARIONAME%...
sqlcmd.exe -S%SQLSERVER% -E -dAdventureWorksDW2008R2 -ooutput\Cleanup.out -iCleanup.sql %NULLREDIRECT%
@ECHO %date% %time% - %SCENARIONAME% setup...
sqlcmd.exe -S%SQLSERVER% -E -dAdventureWorksDW2008R2 -ooutput\PreSetup.out -iPreSetup.sql %NULLREDIRECT%

REM ========== Start ========== 
REM Start expensive query
@ECHO %date% %time% - Starting foreground queries...
SET /A NUMTHREADS=%NUMBER_OF_PROCESSORS%
.\ostress -E -iWorkload.sql -n%NUMTHREADS% -r25 -q -S%SQLSERVER%

REM @ECHO %date% %time% - Press ENTER to end the scenario. 
REM pause %NULLREDIRECT%
@ECHO %date% %time% - Shutting down...


