USE [dba_local]
GO

/****** Object:  Table [dbo].[Sessionstatus]    Script Date: 2/1/2016 11:33:43 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[Sessionstatus]') AND type in (N'U'))
              BEGIN
                     DROP TABLE dbo.[Sessionstatus]
                     PRINT 'Table Sessionstatus exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping table'
              END

IF NOT EXISTS (SELECT * FROM sys.objects WHERE OBJECT_ID = OBJECT_ID(N'[Sessionstatus]') AND TYPE IN (N'U'))
BEGIN
CREATE TABLE [dbo].[Sessionstatus](
       [DateCaptured] [datetime] NULL,
       [dbname] [nvarchar](100) NULL,
       [status] [nvarchar](50) NULL,
       [waittype] [nvarchar](100) NULL,
       [waittime] [bigint] NULL,
       [sessioncnt] [int] NULL,
       [opentran] [int] NULL
) ON [PRIMARY]
PRINT 'Table Sessionstatus created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
END
GO


DECLARE @is2012 bit

BEGIN TRY
       IF((SELECT CAST(REPLACE(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS varchar(10)),2),'.','') AS int)) = 11)
              SET @is2012 = 1
       ELSE 
              SET @is2012 = 0

       IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PerformanceCounterList]') AND type in (N'U'))
              BEGIN
                     DROP TABLE [PerformanceCounterList]
                     PRINT 'Table PerformanceCounterList exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping table'
              END

       IF NOT EXISTS (SELECT * FROM sys.objects WHERE OBJECT_ID = OBJECT_ID(N'[PerformanceCounterList]') AND TYPE IN (N'U'))
              BEGIN
                     CREATE TABLE [PerformanceCounterList](
                           [counter_name] [VARCHAR](500) NOT NULL,
                           [is_captured_ind] [BIT] NOT NULL,
                     CONSTRAINT [PK_PerformanceCounterList] PRIMARY KEY CLUSTERED 
                     (
                           [counter_name] ASC
                     )WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, FILLFACTOR = 100) ON [PRIMARY]
                     ) ON [PRIMARY]
                     
                     ALTER TABLE [PerformanceCounterList] ADD  CONSTRAINT [DF_PerformanceCounterList_is_captured_ind]  DEFAULT ((1)) FOR [is_captured_ind]
                     
                     PRINT 'Table PerformanceCounterList created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
              END

       IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PerformanceCounter]') AND type in (N'U'))
              BEGIN
                     DROP TABLE [PerformanceCounter]
                     PRINT 'Table PerformanceCounter exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping table'
              END

       IF NOT EXISTS (SELECT * FROM sys.objects WHERE OBJECT_ID = OBJECT_ID(N'[PerformanceCounter]') AND TYPE IN (N'U'))
              BEGIN
                     CREATE TABLE [PerformanceCounter](
                           [CounterName] [VARCHAR](250) NOT NULL,
                           [CounterValue] [VARCHAR](250) NOT NULL,
                           [DateSampled] [DATETIME] NOT NULL,
                     CONSTRAINT [PK_PerformanceCounter] PRIMARY KEY CLUSTERED 
                     (
                           [CounterName] ASC,
                           [DateSampled] ASC
                     )WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, FILLFACTOR = 80) ON [PRIMARY]
                     ) ON [PRIMARY]
                     
                     PRINT 'Table PerformanceCounter created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
              END

       IF  EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[vPerformanceCounter]'))
              BEGIN
                     DROP VIEW [vPerformanceCounter]
                     PRINT 'View vPerformanceCounter exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping view'
              END

       IF (@is2012 = 0)
              BEGIN
                     IF NOT EXISTS (SELECT * FROM sys.views WHERE OBJECT_ID = OBJECT_ID(N'[vPerformanceCounter]'))
                           BEGIN
                                  EXEC dbo.sp_executesql @statement = N'
                                  CREATE VIEW [vPerformanceCounter]
                                  AS
                                  SELECT * FROM
                                  (SELECT CounterName, CounterValue, DateSampled
                                  FROM PerformanceCounter) AS T1
                                  PIVOT
                                  (
                                  MAX(CounterValue)
                                  FOR CounterName IN ([logicaldisk(_total)\avg. disk queue length],
                                                                     [logicaldisk(_total)\avg. disk sec/read],
                                                                     [logicaldisk(_total)\avg. disk sec/transfer],
                                                                     [logicaldisk(_total)\avg. disk sec/write],
                                                                     [logicaldisk(_total)\current disk queue length],
                                                                     [memory\available mbytes],
                                                                     [paging file(_total)\% usage],
                                                                     [paging file(_total)\% usage peak],
                                                                     [processor(_total)\% privileged time],
                                                                     [processor(_total)\% processor time],
                                                                     [process(sqlservr)\% privileged time],
                                                                     [process(sqlservr)\% processor time],
                                                                     [sql statistics\batch requests/sec],
                                                                     [sql statistics\sql compilations/sec],
                                                                     [sql statistics\sql re-compilations/sec],
                                                                     [general statistics\user connections],
                                                                     [buffer manager\page life expectancy],
                                                                     [buffer manager\buffer cache hit ratio],
                                                                     [memory manager\target server memory (kb)],
                                                                     [memory manager\total server memory (kb)],
                                                                     [buffer manager\checkpoint pages/sec],
                                                                     [buffer manager\free pages],
                                                                     [buffer manager\lazy writes/sec],
                                                                     [transactions\free space in tempdb (kb)])
                                  ) AS PT;
                                  '
                                  PRINT 'View vPerformanceCounter created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
                           END 
                     ELSE PRINT 'View vPerformanceCounter already exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
              END
       ELSE
              BEGIN
                     IF NOT EXISTS (SELECT * FROM sys.views WHERE OBJECT_ID = OBJECT_ID(N'[vPerformanceCounter]'))
                           BEGIN
                                  EXEC dbo.sp_executesql @statement = N'
                                  CREATE VIEW [vPerformanceCounter]
                                  AS
                                  SELECT * FROM
                                  (SELECT CounterName, CounterValue, DateSampled
                                  FROM PerformanceCounter) AS T1
                                  PIVOT
                                  (
                                  MAX(CounterValue)
                                  FOR CounterName IN ([logicaldisk(_total)\avg. disk queue length],
                                                                     [logicaldisk(_total)\avg. disk sec/read],
                                                                    [logicaldisk(_total)\avg. disk sec/transfer],
                                                                     [logicaldisk(_total)\avg. disk sec/write],
                                                                     [logicaldisk(_total)\current disk queue length],
                                                                     [memory\available mbytes],
                                                                     [paging file(_total)\% usage],
                                                                     [paging file(_total)\% usage peak],
                                                                     [processor(_total)\% privileged time],
                                                                     [processor(_total)\% processor time],
                                                                     [process(sqlservr)\% privileged time],
                                                                     [process(sqlservr)\% processor time],
                                                                     [sql statistics\batch requests/sec],
                                                                     [sql statistics\sql compilations/sec],
                                                                     [sql statistics\sql re-compilations/sec],
                                                                     [general statistics\user connections],
                                                                     [buffer manager\page life expectancy],
                                                                     [buffer manager\buffer cache hit ratio],
                                                                     [memory manager\target server memory (kb)],
                                                                     [memory manager\total server memory (kb)],
                                                                     [buffer manager\checkpoint pages/sec],
                                                                     [buffer manager\lazy writes/sec],
                                                                     [transactions\free space in tempdb (kb)])
                                  ) AS PT;
                                  '
                                  PRINT 'View vPerformanceCounter created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
                           END 
                     ELSE PRINT 'View vPerformanceCounter already exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100))
              END

       SET NOCOUNT ON

       DECLARE @perfStr VARCHAR(100)
       DECLARE @instStr VARCHAR(100)

       SELECT @instStr = @@SERVICENAME
       --SET @instStr = 'NI1'

       IF(@instStr = 'MSSQLSERVER')
              SET @perfStr = '\SQLServer'
       ELSE 
              SET @perfStr = '\MSSQL$' + @instStr

       TRUNCATE TABLE PerformanceCounterList
       PRINT 'Truncated table PerformanceCounterList'

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Memory\Pages/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Memory\Pages Input/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Memory\Available MBytes',1)
              
       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Processor(_Total)\% Processor Time',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Processor(_Total)\% Privileged Time',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Process(sqlservr)\% Privileged Time',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Process(sqlservr)\% Processor Time',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Paging File(_Total)\% Usage',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Paging File(_Total)\% Usage Peak',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\PhysicalDisk(_Total)\Avg. Disk sec/Read',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\PhysicalDisk(_Total)\Avg. Disk sec/Write',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\PhysicalDisk(_Total)\Disk Reads/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\PhysicalDisk(_Total)\Disk Writes/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\System\Processor Queue Length',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\System\Context Switches/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Page life expectancy',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Buffer cache hit ratio',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Checkpoint Pages/Sec',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Lazy Writes/Sec',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Page Reads/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Page Writes/Sec',0)

       IF (@is2012 = 0)
              INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
              VALUES        (@perfStr + ':Buffer Manager\Free Pages',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Page Lookups/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Free List Stalls/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Readahead pages/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Database Pages',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Target Pages',0)
                     
       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Total Pages',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        (@perfStr + ':Buffer Manager\Stolen Pages',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':General Statistics\User Connections',1)
                     
       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':General Statistics\Processes blocked',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':General Statistics\Logins/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':General Statistics\Logouts/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Memory Grants Pending',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Total Server Memory (KB)',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Target Server Memory (KB)',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Granted Workspace Memory (KB)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Maximum Workspace Memory (KB)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Memory Manager\Memory Grants Outstanding',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':SQL Statistics\Batch Requests/sec',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':SQL Statistics\SQL Compilations/sec',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':SQL Statistics\SQL Re-Compilations/sec',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':SQL Statistics\Auto-Param Attempts/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Lock Waits/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Lock Requests/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Lock Timeouts/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Number of Deadlocks/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Lock Wait Time (ms)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Locks(_Total)\Average Wait Time (ms)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Latches\Total Latch Wait Time (ms)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Latches\Latch Waits/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Latches\Average Latch Wait Time (ms)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Forwarded Records/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Full Scans/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Page Splits/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Index Searches/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Workfiles Created/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Worktables Created/Sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Access Methods\Table Lock Escalations/sec',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Cursor Manager by Type(_Total)\Active cursors',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Transactions\Longest Transaction Running Time',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Transactions\Free Space in tempdb (KB)',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES (@perfStr + ':Transactions\Version Store Size (KB)',0)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\LogicalDisk(*)\Avg. Disk Queue Length',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\LogicalDisk(*)\Avg. Disk sec/Read',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\LogicalDisk(*)\Avg. Disk sec/Transfer',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\LogicalDisk(*)\Avg. Disk sec/Write',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\LogicalDisk(*)\Current Disk Queue Length',1)

       INSERT INTO PerformanceCounterList(counter_name,is_captured_ind)
       VALUES        ('\Paging File(*)\*',1)

       PRINT 'Inserts to table PerformanceCounterList completed'

       IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[ClearPerfCtrHistory]') AND type in (N'P', N'PC'))
              BEGIN
                     DROP PROCEDURE [ClearPerfCtrHistory]
                     PRINT 'Stored Procedure ClearPerfCtrHistory exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping stored procedure'
              END

       IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[ClearPerfCtrHistory]') AND type in (N'P', N'PC'))
              BEGIN
                     EXEC dbo.sp_executesql @statement = N'

                     CREATE PROCEDURE [ClearPerfCtrHistory]
                           @old_date     INT = 180
                     AS

                     --******************************************************************************************************
                     --*    Created date : September 2014
                     --* Purpose:         Clears out performance counter history  
                     --*
                     --* Usage:        EXEC ClearPerfCtrHistory: procedure can be called with no parameters and default 
                     --*                                                                 180 day history will be used
                     --*                       
                     --*                                             --OR-- specify the optional parameter below to customize history duration
                     --*
                     --*             EXEC ClearBackupHistory
                     --*                         @old_date              --number of days of history to delete
                     --*
                     --*****************************************************************************************************

                     SET NOCOUNT ON
                     SET XACT_ABORT ON

                     BEGIN TRY

                           IF EXISTS(SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[PerformanceCounter]'') AND type in (N''U''))
                                  BEGIN
                                         DELETE dbo.PerformanceCounter 
                                         WHERE DateSampled < DATEADD(dd,-@old_date, dateadd(dd, datediff(dd,0, GETDATE()),0))
                                  END

                     END TRY
                     BEGIN CATCH

                           IF (XACT_STATE()) != 0
                                  ROLLBACK TRANSACTION;
                            
                           DECLARE @errMessage varchar(MAX)
                           SET @errMessage = ''Stored procedure '' + OBJECT_NAME(@@PROCID) + '' failed with error '' + CAST(ERROR_NUMBER() AS VARCHAR(20)) + ''. '' + ERROR_MESSAGE() 
                           RAISERROR (@errMessage, 16, 1)
                                  
                     END CATCH
                     '
                     PRINT 'Stored procedure ClearPerfCtrHistory created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) 
              END
END TRY
BEGIN CATCH
       DECLARE @errMessage varchar(MAX) = ERROR_MESSAGE()
       PRINT @errMessage
       
       IF EXISTS(SELECT 1 FROM master.sys.databases WHERE name = 'dba_local')
              AND EXISTS (SELECT 1 FROM dba_local.sys.objects WHERE name = N'install_usp_logevent' AND type in (N'P', N'PC'))
                     BEGIN
                           EXEC [dba_local].[dbo].[install_usp_logevent] @errMessage
                     END
END CATCH

GO



/****** Object:  StoredProcedure [dbo].[spLoadSessionStatus]    Script Date: 2/1/2016 10:56:17 AM ******/

 IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[spLoadSessionStatus]') AND type in (N'P', N'PC'))
              BEGIN
                     DROP PROCEDURE dbo.[spLoadSessionStatus]
                     PRINT 'Procedure spLoadSessionStatus exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping table'
              END;
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[spLoadSessionStatus]') AND type in (N'P', N'PC'))
			BEGIN
				EXEC dbo.sp_executesql @statement = N'CREATE PROC [dbo].[spLoadSessionStatus] 
				AS
				BEGIN
				delete from dbo.Sessionstatus where DateCaptured < DATEADD(dd,-5,getdate());
				INSERT INTO dbo.Sessionstatus
				SELECT Getdate() as "Date Captured", DB_NAME(database_id) as "Database Name" ,status,wait_type,SUM(wait_time) as [Wait in ms],COUNT(r.session_id) as [Session Count],SUM(open_transaction_count) as [Open Transactions]
				from  sys.dm_exec_requests r  
				where 
				r.blocking_session_id = 0 and r.status NOT IN (''suspended'',''background'') 
				group by status,DB_NAME(database_id),wait_type

				UNION ALL

				SELECT Getdate() as "Date Captured", DB_NAME(database_id) as "Database Name" ,status,wait_type, SUM(wait_time) as [Wait in ms], COUNT(r.session_id) as [Session Count],SUM(open_transaction_count) as [Open Transactions]
				from  sys.dm_exec_requests r  
				where 
				r.blocking_session_id = 0 and r.status = ''suspended''
				group by status,DB_NAME(database_id),wait_type

				UNION ALL

				SELECT Getdate() as "Date Captured", DB_NAME(database_id) as "Database Name",''blocked'',wait_type, SUM(wait_time) as [Wait in ms],COUNT(r.session_id) as [Session Count],SUM(open_transaction_count) as [Open Transactions]
				from  sys.dm_exec_requests r  
				where 
				-- r.session_id > 50 and 
				r.blocking_session_id <> 0
				GROUP BY DB_NAME(database_id),wait_type

				UNION ALL

				SELECT Getdate() as "Date Captured", DB_NAME(database_id) as "Database Name",s.status,s.lastwaittype , SUM(s.waittime) as [Wait in ms],COUNT(s.spid) as [Session Count],SUM(s.open_tran) as [Open Transactions]
				from  sys.sysprocesses s  left join sys.dm_exec_requests r
				on s.spid = r.session_id
				where 
				r.session_id is NULL 
				GROUP BY DB_NAME(database_id),s.status,s.lastwaittype
				END';
			PRINT 'Procedure spLoadSessionStatus created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping table'
		END
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[spGetPerfCountersFromPowerShell]') AND type in (N'P', N'PC'))
              BEGIN
                     DROP PROCEDURE dbo.[spGetPerfCountersFromPowerShell]
                     PRINT 'Procedure spGetPerfCountersFromPowerShell exists on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' dropping procedure'
              END;
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[spGetPerfCountersFromPowerShell]') AND type in (N'P', N'PC'))
			BEGIN
				EXEC dbo.sp_executesql @statement = N'
-- =============================================
-- Author:		Adrian Sullivan, af.sullivan@outlook.com
-- Create date: 2016/12/12
-- Description:	Taking away the need for PS1 files and script folder
-- Update: Guilaumme Kierfer
-- Update date: 2017/04/18
-- Description: Update to handle named instance 
-- =============================================
CREATE PROCEDURE [dbo].[spGetPerfCountersFromPowerShell]
AS
BEGIN
DECLARE @syscounters NVARCHAR(4000)
SET @syscounters=STUFF((SELECT DISTINCT '''''','''''' +LTRIM([counter_name])
FROM [dba_local].[dbo].[PerformanceCounterList]
WHERE [is_captured_ind] = 1 FOR XML PATH('''')), 1, 2, '''')+'''''''' 

DECLARE @cmd NVARCHAR(4000)
DECLARE @syscountertable TABLE (id INT IDENTITY(1,1), [output] VARCHAR(500))
DECLARE @syscountervaluestable TABLE (id INT IDENTITY(1,1), [value] VARCHAR(500))

SET @cmd = ''C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe "& get-counter -counter ''+ @syscounters +'' | Select-Object -ExpandProperty Readings"''
INSERT @syscountertable
EXEC master..xp_cmdshell @cmd

declare @sqlnamedinstance sysname
declare @networkname sysname
if (select CHARINDEX(''\'',@@SERVERNAME)) = 0
	begin
	INSERT [dba_local].[dbo].[PerformanceCounter] (CounterName, CounterValue, DateSampled)
	SELECT  REPLACE(REPLACE(REPLACE(ct.[output],''\\''+@@SERVERNAME+''\'',''''),'' :'',''''),''sqlserver:'','''')[CounterName] , CONVERT(varchar(20),ct2.[output]) [CounterValue], GETDATE() [DateSampled]
	FROM @syscountertable ct
	LEFT OUTER JOIN (
	SELECT id - 1 [id], [output]
	FROM @syscountertable
	WHERE PATINDEX(''%[0-9]%'', LEFT([output],1)) > 0  
	) ct2 ON ct.id = ct2.id
	WHERE  ct.[output] LIKE ''\\%''
	ORDER BY [CounterName] ASC
	end

	else
	begin
	select @networkname=RTRIM(left(@@SERVERNAME, CHARINDEX(''\'', @@SERVERNAME) - 1))
	select @sqlnamedinstance=RIGHT(@@SERVERNAME,CHARINDEX(''\'',REVERSE(@@SERVERNAME))-1)
	INSERT [dba_local].[dbo].[PerformanceCounter] (CounterName, CounterValue, DateSampled)
	SELECT  REPLACE(REPLACE(REPLACE(ct.[output],''\\''+@networkname+''\'',''''),'' :'',''''),''mssql$''+@sqlnamedinstance+'':'','''')[CounterName] , CONVERT(varchar(20),ct2.[output]) [CounterValue], GETDATE() [DateSampled]
	FROM @syscountertable ct
	LEFT OUTER JOIN (
	SELECT id - 1 [id], [output]
	FROM @syscountertable
	WHERE PATINDEX(''%[0-9]%'', LEFT([output],1)) > 0  
	) ct2 ON ct.id = ct2.id
	WHERE  ct.[output] LIKE ''\\%''
	ORDER BY [CounterName] ASC
	END
END';
PRINT 'Procedure spGetPerfCountersFromPowerShell created on server ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(100)) + ' '
		END
GO
