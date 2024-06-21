-- 2010-05-20 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights/)
--
-- Checks for wait types and related info
--
-- 2012-09-19 - Added documentation to some waits
-- 2013-03-05 - Added instantaneous waits vs. historical waits
-- 2014-04-04 - Added custom data collection interval duration
-- 2014-04-30 - Detailed categorization of memory related waits
-- 4/12/2017 - Added additional waits categorization
-- 8/8/2017 - Filtered out additional sleep waits

SET NOCOUNT ON;
DECLARE @UpTime VARCHAR(12), @StartDate DATETIME, @sqlmajorver int, @sqlcmd NVARCHAR(500), @params NVARCHAR(500)
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
IF @sqlmajorver = 9
BEGIN
	SET @sqlcmd = N'SELECT @StartDateOUT = login_time, @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()) FROM master..sysprocesses WHERE spid = 1';
END
ELSE
BEGIN
	SET @sqlcmd = N'SELECT @StartDateOUT = sqlserver_start_time, @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()) FROM sys.dm_os_sys_info';
END
SET @params = N'@StartDateOUT DATETIME OUTPUT, @UpTimeOUT VARCHAR(12) OUTPUT';
EXECUTE sp_executesql @sqlcmd, @params, @StartDateOUT=@StartDate OUTPUT, @UpTimeOUT=@UpTime OUTPUT;
SELECT 'Uptime_Information' AS [Information], GETDATE() AS [Current_Time], @StartDate AS Last_Startup, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'h ' + CONVERT(VARCHAR(4),@UpTime%60) + 'm' AS Uptime
GO



/*
References:
http://msdn.microsoft.com/en-us/library/ms179984.aspx
http://blogs.msdn.com/b/psssql/archive/2009/11/03/the-sql-server-wait-type-repository.aspx
http://blogs.msdn.com/b/sql_service_broker/archive/2008/12/01/service-broker-wait-types.aspx
https://www.sqlskills.com/blogs/paul/wait-statistics-or-please-tell-me-where-it-hurts/
Glenn Alan Berry chapter in the MVP Deep Dive Book
*/

DECLARE @duration tinyint, @ErrorMessage VARCHAR(1000), @durationstr NVARCHAR(24)

/*
Set @duration to the number of seconds between data collection points.
Duration must be between 10s and 255s (4m 15s), with a default of 60s.
*/
SET @duration = 60

-- DBCC SQLPERF ("sys.dm_os_wait_stats",CLEAR)

SELECT @ErrorMessage = 'Starting Waits collection (wait for ' + CONVERT(VARCHAR(3), @duration) + 's)'
RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT

DECLARE @minctr DATETIME, @maxctr DATETIME

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWaits'))
DROP TABLE #tblWaits
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWaits'))
CREATE TABLE [dbo].[#tblWaits](
	[retrieval_time] [datetime],
	[wait_type] [nvarchar](60) NOT NULL,
	[wait_time_ms] bigint NULL,
	[signal_wait_time_ms] bigint NULL,
	[resource_wait_time_ms] bigint NULL
	);

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalWaits'))
DROP TABLE #tblFinalWaits
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalWaits'))
CREATE TABLE [dbo].[#tblFinalWaits](
	[wait_type] [nvarchar](60) NOT NULL,
	[wait_time_s] [numeric](16, 6) NULL,
	[signal_wait_time_s] [numeric](16, 6) NULL,
	[resource_wait_time_s] [numeric](16, 6) NULL,
	[pct] [numeric](12, 2) NULL,
	[rn] [bigint] NULL,
	[signal_wait_pct] [numeric](12, 2) NULL,
	[resource_wait_pct] [numeric](12, 2) NULL
	);
	
INSERT INTO #tblWaits
SELECT GETDATE(), wait_type, wait_time_ms, signal_wait_time_ms,(wait_time_ms-signal_wait_time_ms) AS resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
	AND wait_type NOT LIKE N'SLEEP_%'
	AND wait_time_ms > 0;

IF @duration > 255
SET @duration = 255;

IF @duration < 10
SET @duration = 10;

SELECT @durationstr = 'WAITFOR DELAY ''00:' + CASE WHEN LEN(CONVERT(VARCHAR(3),@duration/60%60)) = 1 
	THEN '0' + CONVERT(VARCHAR(3),@duration/60%60) 
		ELSE CONVERT(VARCHAR(3),@duration/60%60) END 
	+ ':' + CONVERT(VARCHAR(3),@duration-(@duration/60)*60) + ''''
EXECUTE sp_executesql @durationstr;

INSERT INTO #tblWaits
SELECT GETDATE(), wait_type, wait_time_ms, signal_wait_time_ms,(wait_time_ms-signal_wait_time_ms) AS resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
	AND wait_type NOT LIKE N'SLEEP_%'
	AND wait_time_ms > 0;

SELECT @minctr = MIN([retrieval_time]), @maxctr = MAX([retrieval_time]) FROM #tblWaits;
	
;WITH cteWaits1 (wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms) AS (SELECT wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms FROM #tblWaits WHERE [retrieval_time] = @minctr),
	cteWaits2 (wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms) AS (SELECT wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms FROM #tblWaits WHERE [retrieval_time] = @maxctr)
INSERT INTO #tblFinalWaits
SELECT DISTINCT t1.wait_type, (t2.wait_time_ms-t1.wait_time_ms) / 1000. AS wait_time_s,
	(t2.signal_wait_time_ms-t1.signal_wait_time_ms) / 1000. AS signal_wait_time_s,
	((t2.wait_time_ms-t2.signal_wait_time_ms)-(t1.wait_time_ms-t1.signal_wait_time_ms)) / 1000. AS resource_wait_time_s,
	100.0 * (t2.wait_time_ms-t1.wait_time_ms) / SUM(t2.wait_time_ms-t1.wait_time_ms) OVER() AS pct,
	ROW_NUMBER() OVER(ORDER BY (t2.wait_time_ms-t1.wait_time_ms) DESC) AS rn,
	SUM(t2.signal_wait_time_ms-t1.signal_wait_time_ms) * 1.0 / SUM(t2.wait_time_ms-t1.wait_time_ms) * 100 AS signal_wait_pct,
	(SUM(t2.wait_time_ms-t2.signal_wait_time_ms)-SUM(t1.wait_time_ms-t1.signal_wait_time_ms)) * 1.0 / (SUM(t2.wait_time_ms)-SUM(t1.wait_time_ms)) * 100 AS resource_wait_pct
FROM cteWaits1 t1 INNER JOIN cteWaits2 t2 ON t1.wait_type = t2.wait_type
GROUP BY t1.wait_type, t1.wait_time_ms, t1.signal_wait_time_ms, t1.resource_wait_time_ms, t2.wait_time_ms, t2.signal_wait_time_ms, t2.resource_wait_time_ms
HAVING (t2.wait_time_ms-t1.wait_time_ms) > 0
ORDER BY wait_time_s DESC;

SELECT 'Waits_last_' + CONVERT(VARCHAR(3), @duration) + 's' AS [Information], W1.wait_type, 
	CAST(W1.wait_time_s AS DECIMAL(12, 2)) AS wait_time_s,
	CAST(W1.signal_wait_time_s AS DECIMAL(12, 2)) AS signal_wait_time_s,
	CAST(W1.resource_wait_time_s AS DECIMAL(12, 2)) AS resource_wait_time_s,
	CAST(W1.pct AS DECIMAL(12, 2)) AS pct,
	CAST(SUM(W2.pct) AS DECIMAL(12, 2)) AS overall_running_pct,
	CAST(W1.signal_wait_pct AS DECIMAL(12, 2)) AS signal_wait_pct,
	CAST(W1.resource_wait_pct AS DECIMAL(12, 2)) AS resource_wait_pct,
	CASE WHEN W1.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU' 
		WHEN W1.wait_type = N'THREADPOOL' THEN 'CPU - Unavailable Worker Threads'
		WHEN W1.wait_type LIKE N'LCK_%' OR W1.wait_type = N'LOCK' THEN N'Lock' 
		WHEN W1.wait_type LIKE N'LATCH_%' THEN N'Latch' 
		WHEN W1.wait_type LIKE N'PAGELATCH_%' THEN N'Buffer Latch' 
		WHEN W1.wait_type LIKE N'PAGEIOLATCH_%' THEN N'Buffer IO' 
		WHEN W1.wait_type LIKE N'HADR_SYNC_COMMIT' THEN N'Always On - Secondary Synch' 
		WHEN W1.wait_type LIKE N'HADR_%' OR W1.wait_type LIKE N'PWAIT_HADR_%' THEN N'Always On'
		WHEN W1.wait_type LIKE N'FFT_%' THEN N'FileTable'
		WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Memory - Compilation'
		WHEN W1.wait_type IN (N'UTIL_PAGE_ALLOC', N'SOS_VIRTUALMEMORY_LOW', N'SOS_RESERVEDMEMBLOCKLIST', N'RESOURCE_SEMAPHORE', N'CMEMTHREAD', N'CMEMPARTITIONED', N'EE_PMOLOCK', N'MEMORY_ALLOCATION_EXT', N'RESERVED_MEMORY_ALLOCATION_EXT', N'MEMORY_GRANT_UPDATE') THEN N'Memory'
		WHEN W1.wait_type LIKE N'CLR%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'SQL CLR' 
		WHEN W1.wait_type LIKE N'DBMIRROR%' OR W1.wait_type = N'MIRROR_SEND_MESSAGE' THEN N'Mirroring' 
		WHEN W1.wait_type LIKE N'XACT%' or W1.wait_type LIKE N'DTC%' or W1.wait_type LIKE N'TRAN_MARKLATCH_%' or W1.wait_type LIKE N'MSQL_XACT_%' or W1.wait_type = N'TRANSACTION_MUTEX' THEN N'Transaction' 
		--WHEN W1.wait_type LIKE N'SLEEP_%' or W1.wait_type IN (N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'XE_DISPATCHER_WAIT', N'REQUEST_FOR_DEADLOCK_SEARCH', N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE', N'CHECKPOINT_QUEUE', N'XE_TIMER_EVENT') THEN N'Idle' 
		WHEN W1.wait_type LIKE N'PREEMPTIVE_%' THEN N'External APIs or XPs' 
		WHEN W1.wait_type LIKE N'BROKER_%' AND W1.wait_type <> N'BROKER_RECEIVE_WAITFOR' THEN N'Service Broker' 
		WHEN W1.wait_type IN (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'LOGMGR_PMM_LOG', N'CHKPT', N'WRITELOG') THEN N'Tran Log IO' 
		WHEN W1.wait_type IN (N'ASYNC_NETWORK_IO', N'NET_WAITFOR_PACKET', N'PROXY_NETWORK_IO', N'EXTERNAL_SCRIPT_NETWORK_IO') THEN N'Network IO' 
		WHEN W1.wait_type IN (N'CXPACKET', N'EXCHANGE', N'CXCONSUMER') THEN N'CPU - Parallelism'
		WHEN W1.wait_type IN (N'WAITFOR', N'WAIT_FOR_RESULTS', N'BROKER_RECEIVE_WAITFOR') THEN N'User Wait' 
		WHEN W1.wait_type IN (N'TRACEWRITE', N'SQLTRACE_LOCK', N'SQLTRACE_FILE_BUFFER', N'SQLTRACE_FILE_WRITE_IO_COMPLETION', N'SQLTRACE_FILE_READ_IO_COMPLETION', N'SQLTRACE_PENDING_BUFFER_WRITERS', N'SQLTRACE_SHUTDOWN', N'QUERY_TRACEOUT', N'TRACE_EVTNOTIF') THEN N'Tracing' 
		WHEN W1.wait_type LIKE N'FT_%' OR W1.wait_type IN (N'FULLTEXT GATHERER', N'MSSEARCH', N'PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC') THEN N'Full Text Search' 
		WHEN W1.wait_type IN (N'ASYNC_IO_COMPLETION', N'IO_COMPLETION', N'WRITE_COMPLETION', N'IO_QUEUE_LIMIT', /*N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',*/ N'IO_RETRY') THEN N'Other Disk IO' 
		WHEN W1.wait_type IN (N'BACKUPIO', N'BACKUPBUFFER') THEN 'Backup IO'
		WHEN W1.wait_type LIKE N'SE_REPL_%' or W1.wait_type LIKE N'REPL_%'  or W1.wait_type IN (N'REPLICA_WRITES', N'FCB_REPLICA_WRITE', N'FCB_REPLICA_READ', N'PWAIT_HADRSIM') THEN N'Replication' 
		WHEN W1.wait_type IN (N'LOG_RATE_GOVERNOR', N'POOL_LOG_RATE_GOVERNOR', N'HADR_THROTTLE_LOG_RATE_GOVERNOR', N'INSTANCE_LOG_RATE_GOVERNOR') THEN N'Log Rate Governor' 
		--	WHEN W1.wait_type LIKE N'SLEEP_%' OR W1.wait_type IN(N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'WAITFOR', N'WAIT_FOR_RESULTS', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SLEEP_TASK', N'SLEEP_SYSTEMTASK') THEN N'Sleep'
		WHEN W1.wait_type = N'REPLICA_WRITE' THEN 'Snapshots'
		WHEN W1.wait_type = N'WAIT_XTP_OFFLINE_CKPT_LOG_IO' OR W1.wait_type = N'WAIT_XTP_CKPT_CLOSE' THEN 'In-Memory OLTP Logging'
		WHEN W1.wait_type LIKE N'QDS%' THEN N'Query Store'
		WHEN W1.wait_type LIKE N'XTP%' OR W1.wait_type LIKE N'WAIT_XTP%' THEN N'In-Memory OLTP'
		WHEN W1.wait_type LIKE N'PARALLEL_REDO%' THEN N'Parallel Redo'
		WHEN W1.wait_type LIKE N'COLUMNSTORE%' THEN N'Columnstore'
	ELSE N'Other' END AS 'wait_category'
FROM #tblFinalWaits AS W1 INNER JOIN #tblFinalWaits AS W2 ON W2.rn <= W1.rn
GROUP BY W1.rn, W1.wait_type, W1.wait_time_s, W1.pct, W1.signal_wait_time_s, W1.resource_wait_time_s, W1.signal_wait_pct, W1.resource_wait_pct
HAVING W1.wait_time_s >= 0.01 AND (SUM(W2.pct)-W1.pct) < 100  -- percentage threshold
ORDER BY W1.rn; 

;WITH Waits AS
(SELECT wait_type, wait_time_ms / 1000. AS wait_time_s,
	signal_wait_time_ms / 1000. AS signal_wait_time_s,
	(wait_time_ms-signal_wait_time_ms) / 1000. AS resource_wait_time_s,
	SUM(signal_wait_time_ms) * 1.0 / SUM(wait_time_ms) * 100 AS signal_wait_pct,
	SUM(wait_time_ms-signal_wait_time_ms) * 1.0 / SUM(wait_time_ms) * 100 AS resource_wait_pct,
	100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct,
	ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS rn
	FROM sys.dm_os_wait_stats
	WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
		AND wait_type NOT LIKE N'SLEEP_%'
	GROUP BY wait_type, wait_time_ms, signal_wait_time_ms)
SELECT 'Historical_Waits' AS [Information], W1.wait_type, 
	CAST(MAX(W1.wait_time_s) AS DECIMAL(12, 2)) AS wait_time_s,
	CAST(MAX(W1.signal_wait_time_s) AS DECIMAL(12, 2)) AS signal_wait_time_s,
	CAST(MAX(W1.resource_wait_time_s) AS DECIMAL(12, 2)) AS resource_wait_time_s,
	CAST(W1.pct AS DECIMAL(12, 2)) AS pct,
	CAST(SUM(W2.pct) AS DECIMAL(12, 2)) AS overall_running_pct,
	CAST(W1.signal_wait_pct AS DECIMAL(12, 2)) AS signal_wait_pct,
	CAST(W1.resource_wait_pct AS DECIMAL(12, 2)) AS resource_wait_pct,
	CASE -- SOS_SCHEDULER_YIELD = Might indicate CPU pressure if very high overall percentage. Check yielding conditions IN http://technet.microsoft.com/en-us/library/cc917684.aspx
		WHEN W1.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU' 
		-- THREADPOOL = Look for high blocking or contention problems with workers. This will not show up in sys.dm_exec_requests;
		WHEN W1.wait_type = N'THREADPOOL' THEN 'CPU - Unavailable Worker Threads'
		WHEN W1.wait_type LIKE N'LCK_%' OR W1.wait_type = N'LOCK' THEN N'Lock' 
		-- LATCH = indicates contention for access to some non-page structures. ACCESS_METHODS_DATASET_PARENT, ACCESS_METHODS_SCAN_RANGE_GENERATOR or NESTING_TRANSACTION_FULL latches indicate parallelism issues;
		WHEN W1.wait_type LIKE N'LATCH_%' THEN N'Latch' 
		-- PAGELATCH = indicates contention for access to In-memory copies of pages, like PFS, SGAM and GAM; 
		-- PAGELATCH_UP = Does the filegroup have enough files? Contention in PFS?
		-- PAGELATCH_EX = Contention while doing many UPDATE statements against small tables? 
		-- PAGELATCH_EX = Many concurrent INSERT statements into a table that has an index on an IDENTITY or NEWSEQUENTIALID column? -> http://aka.ms/sqlinsights/archive/2013/05/23/pagelatch-ex-waits-and-heavy-inserts.aspx
		WHEN W1.wait_type LIKE N'PAGELATCH_%' THEN N'Buffer Latch' 
		-- PAGEIOLATCH = indicates data pages IO problems, or BP pressure.
		WHEN W1.wait_type LIKE N'PAGEIOLATCH_%' THEN N'Buffer IO' 
		WHEN W1.wait_type LIKE N'HADR_SYNC_COMMIT' THEN N'Always On - Secondary Synch' 
		WHEN W1.wait_type LIKE N'HADR_%' OR W1.wait_type LIKE N'PWAIT_HADR_%' THEN N'Always On'
		WHEN W1.wait_type LIKE N'FFT_%' THEN N'FileTable'
		-- RESOURCE_SEMAPHORE_QUERY_COMPILE = usually high compilation or recompilation scenario (higher ratio of prepared plans vs. compiled plans). On x64 usually memory hungry queries and compiles. On x86 perhaps short on VAS. -> http://technet.microsoft.com/en-us/library/cc293620.aspx
		WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Memory - Compilation'
		-- SOS_RESERVEDMEMBLOCKLIST = look for procedures with a large number of parameters, or queries with a long list of expression values specified IN an IN clause, which would require multi-page allocations
		WHEN W1.wait_type IN (N'UTIL_PAGE_ALLOC',N'SOS_VIRTUALMEMORY_LOW',N'CMEMTHREAD', N'SOS_RESERVEDMEMBLOCKLIST') THEN N'Memory'
		WHEN W1.wait_type LIKE N'CLR%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'SQL CLR' 
		-- DBMIRROR_DBM_MUTEX = indicates contention for the send buffer that database mirroring shares between all the mirroring sessions. 
		WHEN W1.wait_type LIKE N'DBMIRROR%' OR W1.wait_type = N'MIRROR_SEND_MESSAGE' THEN N'Mirroring' 
		WHEN W1.wait_type LIKE N'XACT%' or W1.wait_type LIKE N'DTC%' or W1.wait_type LIKE N'TRAN_MARKLATCH_%' or W1.wait_type LIKE N'MSQL_XACT_%' or W1.wait_type = N'TRANSACTION_MUTEX' THEN N'Transaction' 
		WHEN W1.wait_type LIKE N'SLEEP_%' or W1.wait_type IN (N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'XE_DISPATCHER_WAIT', N'REQUEST_FOR_DEADLOCK_SEARCH', N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE', N'CHECKPOINT_QUEUE', N'XE_TIMER_EVENT') THEN N'Idle' 
		-- PREEMPTIVE_OS_WRITEFILEGATHERER (2008+) = usually autogrow scenarios, usually together with WRITELOG;
		-- PREEMPTIVE_OS_WAITFORSINGLEOBJECT can usually be seen together with NETWORK_IO.
		WHEN W1.wait_type LIKE N'PREEMPTIVE_%' THEN N'External APIs or XPs' 
		WHEN W1.wait_type LIKE N'BROKER_%' and W1.wait_type <> N'BROKER_RECEIVE_WAITFOR' THEN N'Service Broker' 
		-- WRITELOG = log management system waiting for a log flush to disk. Examine the IO latency for the log file.
		-- LOGMGR = Occurs when a task is waiting for any outstanding log I/Os to finish before shutting down the log while closing the database.
		WHEN W1.wait_type IN (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'LOGMGR_PMM_LOG', N'CHKPT', N'WRITELOG') THEN N'Tran Log IO' 
		WHEN W1.wait_type IN (N'ASYNC_NETWORK_IO', N'NET_WAITFOR_PACKET', N'PROXY_NETWORK_IO', N'EXTERNAL_SCRIPT_NETWORK_IO') THEN N'Network IO' 
		-- Check Waiting_tasks section below for Exchange wait types -> http://technet.microsoft.com/en-us/library/ms188743.aspx;
			-- Wait Resource e_waitPipeNewRow IN CXPACKET waits  Producer waiting on consumer for a packet to fill;
			-- Wait Resource e_waitPipeGetRow IN CXPACKET waits  Consumer waiting on producer to fill a packet;
		-- CXPACKET = if OLTP, check for parallelism issues if above 20 pct. If combined with a high number of PAGEIOLATCH_XX waits, it could be large parallel table scans going on because of incorrect non-clustered indexes, or out-of-date statistics causing a bad query plan;
		-- HT* = batch mode syncpoint waits, probably large parallel table scans;   
		WHEN W1.wait_type IN (N'CXPACKET', N'EXCHANGE', N'CXCONSUMER', N'HTBUILD', N'HTDELETE', N'HTMEMO', N'HTREINIT', N'HTREPARTITION') THEN N'CPU - Parallelism'
		-- CMEMTHREAD =  indicates that the rate of insertion of entries into the plan cache is very high and there is contention -> http://blogs.msdn.com/b/psssql/archive/2012/12/20/how-it-works-cmemthread-and-debugging-them.aspx
		-- RESOURCE_SEMAPHORE_SMALL_QUERY or RESOURCE_SEMAPHORE = queries are waiting for execution memory. Look for plans with excessive hashing or sorts.
		WHEN W1.wait_type IN (N'RESOURCE_SEMAPHORE_SMALL_QUERY', N'RESOURCE_SEMAPHORE', N'CMEMTHREAD', N'CMEMPARTITIONED', N'EE_PMOLOCK', N'MEMORY_ALLOCATION_EXT', N'RESERVED_MEMORY_ALLOCATION_EXT', N'MEMORY_GRANT_UPDATE') THEN N'Memory' 
		WHEN W1.wait_type IN (N'WAITFOR', N'WAIT_FOR_RESULTS', N'BROKER_RECEIVE_WAITFOR') THEN N'User Wait' 
		WHEN W1.wait_type IN (N'TRACEWRITE', N'SQLTRACE_LOCK', N'SQLTRACE_FILE_BUFFER', N'SQLTRACE_FILE_WRITE_IO_COMPLETION', N'SQLTRACE_FILE_READ_IO_COMPLETION', N'SQLTRACE_PENDING_BUFFER_WRITERS', N'SQLTRACE_SHUTDOWN', N'QUERY_TRACEOUT', N'TRACE_EVTNOTIF') THEN N'Tracing' 
		WHEN W1.wait_type LIKE N'FT_%' OR W1.wait_type IN (N'FULLTEXT GATHERER', N'MSSEARCH', N'PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC') THEN N'Full Text Search' 
		-- IO_COMPLETION = usually TempDB spilling; 
		-- ASYNC_IO_COMPLETION = usually when not using IFI, or waiting on backups.
		-- DISKIO_SUSPEND = High wait times here indicate the SNAPSHOT BACKUP may be taking longer than expected. Typically the delay is within the VDI application perform the snapshot backup;
		WHEN W1.wait_type IN (N'ASYNC_IO_COMPLETION', N'IO_COMPLETION', N'WRITE_COMPLETION', N'IO_QUEUE_LIMIT', /*N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',*/ N'IO_RETRY') THEN N'Other Disk IO' 
		-- BACKUPIO = check for slow backup media slow, LIKE Tapes or Disks;
		-- BACKUPBUFFER = usually when backing up to Tape;
		WHEN W1.wait_type IN(N'BACKUPIO', N'BACKUPBUFFER') THEN 'Backup IO'
		WHEN W1.wait_type LIKE N'SE_REPL_%' or W1.wait_type LIKE N'REPL_%'  or W1.wait_type IN (N'REPLICA_WRITES', N'FCB_REPLICA_WRITE', N'FCB_REPLICA_READ', N'PWAIT_HADRSIM') THEN N'Replication' 
		WHEN W1.wait_type IN (N'LOG_RATE_GOVERNOR', N'POOL_LOG_RATE_GOVERNOR', N'HADR_THROTTLE_LOG_RATE_GOVERNOR', N'INSTANCE_LOG_RATE_GOVERNOR') THEN N'Log Rate Governor' 
		WHEN W1.wait_type LIKE N'CLR_%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'CLR'
		--	WHEN W1.wait_type LIKE N'SLEEP_%' OR W1.wait_type IN(N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'WAITFOR', N'WAIT_FOR_RESULTS', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SLEEP_TASK', N'SLEEP_SYSTEMTASK') THEN N'Sleep'
		WHEN W1.wait_type = N'REPLICA_WRITE' THEN 'Snapshots'
		WHEN W1.wait_type = N'WAIT_XTP_OFFLINE_CKPT_LOG_IO' OR W1.wait_type = N'WAIT_XTP_CKPT_CLOSE' THEN 'In-Memory Logging'	
	ELSE N'Other' END AS 'wait_category'
FROM Waits AS W1
INNER JOIN Waits AS W2
ON W2.rn <= W1.rn
GROUP BY W1.rn, W1.wait_type, W1.wait_time_s, W1.pct, W1.signal_wait_time_s, W1.resource_wait_time_s, W1.signal_wait_pct, W1.resource_wait_pct
HAVING W1.wait_time_s >= 0.01 AND (SUM(W2.pct)-W1.pct) < 100  -- percentage threshold
ORDER BY W1.rn; 
GO

SELECT 'Waiting_tasks_per_Conn' AS [Information], st.text AS [SQL Text], c.connection_id, w.session_id, w.wait_duration_ms, w.wait_type, w.resource_address, w.blocking_session_id, w.resource_description, c.client_net_address, c.connect_time
FROM sys.dm_os_waiting_tasks AS w
INNER JOIN sys.dm_exec_connections AS c ON w.session_id = c.session_id 
CROSS APPLY (SELECT * FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS st WHERE w.session_id > 50 AND w.wait_duration_ms > 0
ORDER BY c.connection_id, w.session_id
GO

SELECT 'Waiting_tasks' AS [Information], owt.session_id,
	owt.wait_duration_ms,
	owt.wait_type,
	owt.blocking_session_id,
	owt.resource_description,
	es.program_name,
	est.text,
	est.dbid,
	eqp.query_plan,
	er.database_id,
	es.cpu_time,
	es.memory_usage*8 AS memory_usage_KB
 FROM sys.dm_os_waiting_tasks owt
 INNER JOIN sys.dm_exec_sessions es ON owt.session_id = es.session_id
 INNER JOIN sys.dm_exec_requests er ON es.session_id = er.session_id
 OUTER APPLY sys.dm_exec_sql_text (er.sql_handle) est
 OUTER APPLY sys.dm_exec_query_plan (er.plan_handle) eqp
 WHERE es.is_user_process = 1
 ORDER BY owt.session_id;
 GO
