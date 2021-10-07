-- 2012-04-07 Pedro Lopes (Microsoft) (http://aka.ms/tigertoolbox/)

-- Replace CREATE PROCEDURE with ALTER PROCEDURE or CREATE OR ALTER PROCEDURE to allow new changes to the SP if the SP is already present. Wonks in SQL Server, Azure SQL Managed INstance, and Azure SQL DB (create in user DB)

CREATE PROCEDURE usp_whatsup @sqluptime bit = 1, @requests bit = 1, @blocking bit = 1, @spstats bit = 0, @qrystats bit = 0, @trstats bit = 0, @fnstats bit = 0, @top smallint = 100
AS

-- Returns running sessions/requests; blocking information; sessions that have been granted locks or waiting for locks; and optionally top SP/Query/Trigger/Function execution stats.

SET NOCOUNT ON;

DECLARE @sqlmajorver int, @sqlbuild int, @sqlcmd VARCHAR(8000), @sqlcmdup NVARCHAR(500), @params NVARCHAR(500)
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);
	
IF @sqluptime = 1
BEGIN
	DECLARE @UpTime VARCHAR(12), @StartDate DATETIME

	IF @sqlmajorver = 9
	BEGIN
		SET @sqlcmdup = N'SELECT @StartDateOUT = login_time, @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()) FROM master..sysprocesses WHERE spid = 1';
	END
	ELSE
	BEGIN
		SET @sqlcmdup = N'SELECT @StartDateOUT = sqlserver_start_time, @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()) FROM sys.dm_os_sys_info';
	END

	SET @params = N'@StartDateOUT DATETIME OUTPUT, @UpTimeOUT VARCHAR(12) OUTPUT';

	EXECUTE sp_executesql @sqlcmdup, @params, @StartDateOUT=@StartDate OUTPUT, @UpTimeOUT=@UpTime OUTPUT;

	SELECT 'Uptime_Information' AS [Information], GETDATE() AS [Current_Time], @StartDate AS Last_Startup, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'h ' + CONVERT(VARCHAR(4),@UpTime%60) + 'm' AS Uptime

END;

-- Running Sessions/Requests Report
IF @requests = 1
BEGIN
	IF @sqlmajorver = 9
	BEGIN
		SELECT @sqlcmd = N'SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name], -- NULL if Ad-Hoc or Prepared statements
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	--ot.task_state AS [status],
	er.status,
	--er.command,
	qp.query_plan,
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	--mg.ideal_memory_kb,
	mg.query_cost,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF @sqlmajorver IN (10,11,12) OR (@sqlmajorver = 13 AND @sqlbuild < 4000)
	BEGIN
		SET @sqlcmd = N';WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	er.status,
	er.command,
	qp.query_plan,
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF (@sqlmajorver = 13 AND @sqlbuild > 4000) OR @sqlmajorver = 14 OR (@sqlmajorver = 15 AND @sqlbuild < 1400)
	BEGIN
		SELECT @sqlcmd = N'WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		ib.event_info,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_input_buffer(er.session_id, er.request_id) AS ib
		FOR XML PATH(''''), TYPE) AS [input_buffer],
	er.status,
	er.command,
	qp.query_plan,
	CASE WHEN qes.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qes.query_plan END AS [live_query_plan_snapshot],
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_MB,
	(er.logical_reads*8)/1024 AS logical_reads_MB,
	(er.writes*8)/1024 AS writes_MB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp 
	OUTER APPLY sys.dm_exec_query_statistics_xml(er.session_id) qes
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF (@sqlmajorver = 15 AND @sqlbuild >= 1400) OR @sqlmajorver > 15 
	BEGIN
		SELECT @sqlcmd = N'WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	--ot.task_state AS [status],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		ib.event_info,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_input_buffer(er.session_id, er.request_id) AS ib
		FOR XML PATH(''''), TYPE) AS [input_buffer],
	er.status,
	er.command,
	qp.query_plan,
	CASE WHEN qes.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qes.query_plan END AS [live_query_plan_snapshot],
	CASE WHEN qps.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qps.query_plan END AS [last_actual_execution_plan],
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	pi.page_type_desc AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp 
	OUTER APPLY sys.dm_exec_query_statistics_xml(er.session_id) qes
	OUTER APPLY sys.dm_exec_query_plan_stats(er.plan_handle) qps
	OUTER APPLY sys.fn_PageResCracker(er.page_resource) pc  
	OUTER APPLY sys.dm_db_page_info(ISNULL(pc.db_id, 0), ISNULL(pc.file_id, 0), ISNULL(pc.page_id, 0), ''LIMITED'') pi
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END

	EXECUTE (@sqlcmd)
END;

-- Waiter and Blocking Report
IF @blocking = 1
BEGIN
	SELECT 'Waiter_Blocking_Report' AS [Information],
		-- blocked
		es.session_id AS blocked_spid,
		es.[status] AS [blocked_spid_status],
		ot.task_state AS [blocked_task_status],
		owt.wait_type AS blocked_spid_wait_type,
		COALESCE(owt.wait_duration_ms, DATEDIFF(ms, es.last_request_start_time, GETDATE())) AS blocked_spid_wait_time_ms,
		--er.total_elapsed_time AS blocked_elapsed_time_ms,
		/* 
			Check sys.dm_os_waiting_tasks for Exchange wait types in http://technet.microsoft.com/en-us/library/ms188743.aspx.
			- Wait Resource e_waitPipeNewRow in CXPACKET waits  Producer waiting on consumer for a packet to fill.
			- Wait Resource e_waitPipeGetRow in CXPACKET waits  Consumer waiting on producer to fill a packet.
		*/
		owt.resource_description AS blocked_spid_res_desc,
		owt.[objid] AS blocked_objectid,
		owt.pageid AS blocked_pageid,
		CASE WHEN owt.pageid = 1 OR owt.pageid % 8088 = 0 THEN 'Is_PFS_Page'
			WHEN owt.pageid = 2 OR owt.pageid % 511232 = 0 THEN 'Is_GAM_Page'
			WHEN owt.pageid = 3 OR (owt.pageid - 1) % 511232 = 0 THEN 'Is_SGAM_Page'
			WHEN owt.pageid IS NULL THEN NULL
			ELSE 'Is_not_PFS_GAM_SGAM_page' END AS blocked_spid_res_type,
		(SELECT qt.text AS [text()] 
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt 
			FOR XML PATH(''), TYPE) AS [blocked_batch],
		(SELECT SUBSTRING(qt2.text, 
			1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
			1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))) AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocked_statement],
		es.last_request_start_time AS blocked_last_start,
		LEFT (CASE COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot'
			ELSE CONVERT (VARCHAR(30), COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocked_tran_isolation_level,

		-- blocker
		er.blocking_session_id As blocker_spid,
		CASE 
			-- session has an active request, is blocked, but is blocking others or session is idle but has an open tran and is blocking others
			WHEN (er2.session_id IS NULL OR owt.blocking_session_id IS NULL) AND (er.blocking_session_id = 0 OR er.session_id IS NULL) THEN 1
			-- session is either not blocking someone, or is blocking someone but is blocked by another party
			ELSE 0
		END AS is_head_blocker,
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			qt2.text,
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_batch],
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			SUBSTRING(qt2.text, 
			1+(CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END),
			1+(CASE WHEN er2.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er2.statement_end_offset/2 END - (CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END))),
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_statement],
		es2.last_request_start_time AS blocker_last_start,
		LEFT (CASE COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot' 
			ELSE CONVERT (VARCHAR(30), COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocker_tran_isolation_level,

		-- blocked - other data
		DB_NAME(er.database_id) AS blocked_database, 
		es.[host_name] AS blocked_host,
		es.[program_name] AS blocked_program, 
		es.login_name AS blocked_login,
		CASE WHEN es.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocked_session_comment,
		es.is_user_process AS [blocked_is_user_process],

		-- blocker - other data
		DB_NAME(er2.database_id) AS blocker_database,
		es2.[host_name] AS blocker_host,
		es2.[program_name] AS blocker_program,	
		es2.login_name AS blocker_login,
		CASE WHEN es2.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es2.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es2.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocker_session_comment,
		es2.is_user_process AS [blocker_is_user_process]
	FROM sys.dm_exec_sessions (NOLOCK) es
	LEFT OUTER JOIN sys.dm_exec_requests (NOLOCK) er ON es.session_id = er.session_id
	LEFT OUTER JOIN sys.dm_exec_connections (NOLOCK) ec ON es.session_id = ec.session_id
	LEFT OUTER JOIN sys.dm_os_tasks (NOLOCK) ot ON er.session_id = ot.session_id AND er.request_id = ot.request_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es2 ON er.blocking_session_id = es2.session_id
	LEFT OUTER JOIN sys.dm_exec_requests (NOLOCK) er2 ON es2.session_id = er2.session_id
	LEFT OUTER JOIN sys.dm_exec_connections (NOLOCK) ec2 ON es2.session_id = ec2.session_id
	LEFT OUTER JOIN 
	(
		-- In some cases (e.g. parallel queries, also waiting for a worker), one thread can be flagged as 
		-- waiting for several different threads.  This will cause that thread to show up in multiple rows 
		-- in our grid, which we don't want.  Use ROW_NUMBER to select the longest wait for each thread, 
		-- and use it as representative of the other wait relationships this thread is involved in. 
		SELECT waiting_task_address, session_id, exec_context_id, wait_duration_ms, 
			wait_type, resource_address, blocking_task_address, blocking_session_id, 
			blocking_exec_context_id, resource_description,
			CASE WHEN [wait_type] LIKE 'PAGE%' AND [resource_description] LIKE '%:%' THEN CAST(RIGHT([resource_description], LEN([resource_description]) - CHARINDEX(':', [resource_description], LEN([resource_description])-CHARINDEX(':', REVERSE([resource_description])))) AS int)
				WHEN [wait_type] LIKE 'LCK%' AND [resource_description] LIKE '%pageid%' AND ISNUMERIC(RIGHT(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1),CHARINDEX('=',REVERSE(RTRIM(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1)))))) = 1 THEN CAST(RIGHT(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1),CHARINDEX('=',REVERSE(RTRIM(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1))))) AS bigint)
				ELSE NULL END AS pageid,
			CASE WHEN [wait_type] LIKE 'LCK%' AND [resource_description] LIKE '%associatedObjectId%' AND ISNUMERIC(RIGHT([resource_description],CHARINDEX('=', REVERSE([resource_description]))-1)) = 1 THEN CAST(RIGHT([resource_description],CHARINDEX('=', REVERSE([resource_description]))-1) AS bigint)
				ELSE NULL END AS [objid],
			ROW_NUMBER() OVER (PARTITION BY waiting_task_address ORDER BY wait_duration_ms DESC) AS row_num
		FROM sys.dm_os_waiting_tasks (NOLOCK)
	) owt ON ot.task_address = owt.waiting_task_address AND owt.row_num = 1
	--OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) est
	--OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) eqp
	WHERE es.session_id <> @@SPID AND es.is_user_process = 1 
		--AND ((owt.wait_duration_ms/1000 > 5) OR (er.total_elapsed_time/1000) > 5 OR er.total_elapsed_time IS NULL) --Only report blocks > 5 Seconds plus head blocker
		AND (es.session_id IN (SELECT er3.blocking_session_id FROM sys.dm_exec_requests (NOLOCK) er3) OR er.blocking_session_id IS NOT NULL OR er.blocking_session_id > 0)
	ORDER BY blocked_spid, is_head_blocker DESC, blocked_spid_wait_time_ms DESC, blocker_spid
END;

-- Query stats
IF @qrystats = 1 AND @sqlmajorver >= 11
BEGIN 
	SELECT @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN CONVERT(int,pa.value) = 32767 THEN ''ResourceDB'' ELSE DB_NAME(CONVERT(int,pa.value)) END AS DatabaseName,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		st.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qs.creation_time AS cached_time,
	qs.last_execution_time,
	qs.execution_count,
	qs.total_elapsed_time/qs.execution_count AS avg_elapsed_time,
	qs.last_elapsed_time,
	qs.total_worker_time/qs.execution_count AS avg_cpu_time,
	qs.last_worker_time AS last_cpu_time,
	qs.min_worker_time AS min_cpu_time, qs.max_worker_time AS max_cpu_time,
	qs.total_logical_reads/qs.execution_count AS avg_logical_reads,
	qs.last_logical_reads, qs.min_logical_reads, qs.max_logical_reads,
	qs.total_physical_reads/qs.execution_count AS avg_physical_reads,
	qs.last_physical_reads, qs.min_physical_reads, qs.max_physical_reads,
	qs.total_logical_writes/qs.execution_count AS avg_logical_writes,
	qs.last_logical_writes, qs.min_logical_writes, qs.max_logical_writes' + CASE WHEN @sqlmajorver >= 13 THEN ',
	CASE WHEN qs.total_grant_kb IS NOT NULL THEN qs.total_grant_kb/qs.execution_count ELSE -1 END AS avg_grant_kb,
	CASE WHEN qs.total_used_grant_kb IS NOT NULL THEN qs.total_used_grant_kb/qs.execution_count ELSE -1 END AS avg_used_grant_kb,
	COALESCE(((qs.total_used_grant_kb * 100.00) / NULLIF(qs.total_grant_kb,0)), 0) AS grant2used_ratio,
	CASE WHEN qs.total_ideal_grant_kb IS NOT NULL THEN qs.total_ideal_grant_kb/qs.execution_count ELSE -1 END AS avg_ideal_grant_kb,
	CASE WHEN qs.total_dop IS NOT NULL THEN qs.total_dop/qs.execution_count ELSE -1 END AS avg_dop,
	CASE WHEN qs.total_reserved_threads IS NOT NULL THEN qs.total_reserved_threads/qs.execution_count ELSE -1 END AS avg_reserved_threads,
	CASE WHEN qs.total_used_threads IS NOT NULL THEN qs.total_used_threads/qs.execution_count ELSE -1 END AS avg_used_threads' ELSE '' END + 
	CASE WHEN @sqlmajorver >= 15 OR (@sqlmajorver = 13 AND @sqlbuild >= 5026) OR (@sqlmajorver = 14 AND @sqlbuild >= 3015) THEN ',
	CASE WHEN qs.total_columnstore_segment_reads IS NOT NULL THEN qs.total_columnstore_segment_reads/qs.execution_count ELSE -1 END AS avg_columnstore_segment_reads,
	CASE WHEN qs.total_columnstore_segment_skips IS NOT NULL THEN qs.total_columnstore_segment_skips/qs.execution_count ELSE -1 END AS avg_columnstore_segment_skips,
	CASE WHEN qs.total_spills IS NOT NULL THEN qs.total_spills/qs.execution_count ELSE -1 END AS avg_spills' ELSE '' END +'
FROM sys.dm_exec_query_stats (NOLOCK) AS qs
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE pa.attribute = ''dbid'''
	EXEC (@sqlcmd);
END;

-- Stored procedure stats
IF @spstats = 1 AND @sqlmajorver >= 11
BEGIN 
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN ps.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(ps.database_id) END AS DatabaseName, 
	CASE WHEN ps.database_id = 32767 THEN NULL ELSE OBJECT_NAME(ps.[object_id], ps.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_procedure_stats (NOLOCK) ps2 CROSS APPLY sys.dm_exec_sql_text(ps2.sql_handle) qt
		WHERE ps2.database_id = ps.database_id AND ps2.[object_id] = ps.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	ps.cached_time,
	ps.last_execution_time,
	ps.execution_count,
	ps.total_elapsed_time/ps.execution_count AS avg_elapsed_time,
	ps.last_elapsed_time,
	ps.total_worker_time/ps.execution_count AS avg_cpu_time,
	ps.last_worker_time AS last_cpu_time,
	ps.min_worker_time AS min_cpu_time, ps.max_worker_time AS max_cpu_time,
	ps.total_logical_reads/ps.execution_count AS avg_logical_reads,
	ps.last_logical_reads, ps.min_logical_reads, ps.max_logical_reads,
	ps.total_physical_reads/ps.execution_count AS avg_physical_reads,
	ps.last_physical_reads, ps.min_physical_reads, ps.max_physical_reads,
	ps.total_logical_writes/ps.execution_count AS avg_logical_writes,
	ps.last_logical_writes, ps.min_logical_writes, ps.max_logical_writes
 FROM sys.dm_exec_procedure_stats (NOLOCK) ps
 CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp'
	EXEC (@sqlcmd);
END;

-- Trigger stats
IF @trstats = 1 AND @sqlmajorver >= 11
BEGIN
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN ts.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(ts.database_id) END AS DatabaseName, 
	CASE WHEN ts.database_id = 32767 THEN NULL ELSE OBJECT_NAME(ts.[object_id], ts.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_trigger_stats (NOLOCK) ts2 CROSS APPLY sys.dm_exec_sql_text(ts2.sql_handle) qt 
		WHERE ts2.database_id = ts.database_id AND ts2.[object_id] = ts.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	ts.cached_time,
	ts.last_execution_time,
	ts.execution_count,
	ts.total_elapsed_time/ts.execution_count AS avg_elapsed_time,
	ts.last_elapsed_time,
	ts.total_worker_time/ts.execution_count AS avg_cpu_time,
	ts.last_worker_time AS last_cpu_time,
	ts.min_worker_time AS min_cpu_time, ts.max_worker_time AS max_cpu_time,
	ts.total_logical_reads/ts.execution_count AS avg_logical_reads,
	ts.last_logical_reads, ts.min_logical_reads, ts.max_logical_reads,
	ts.total_physical_reads/ts.execution_count AS avg_physical_reads,
	ts.last_physical_reads, ts.min_physical_reads, ts.max_physical_reads,
	ts.total_logical_writes/ts.execution_count AS avg_logical_writes,
	ts.last_logical_writes, ts.min_logical_writes, ts.max_logical_writes
FROM sys.dm_exec_trigger_stats (NOLOCK) ts
CROSS APPLY sys.dm_exec_query_plan(ts.plan_handle) qp'
	EXEC (@sqlcmd);
END;

-- Function stats
IF @fnstats = 1 AND @sqlmajorver >= 13
BEGIN
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN fs.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(fs.database_id) END AS DatabaseName, 
	CASE WHEN fs.database_id = 32767 THEN NULL ELSE OBJECT_NAME(fs.[object_id], fs.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_function_stats (NOLOCK) fs2 CROSS APPLY sys.dm_exec_sql_text(fs2.sql_handle) qt 
		WHERE fs2.database_id = fs.database_id AND fs2.[object_id] = fs.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	fs.cached_time,
	fs.last_execution_time,
	fs.execution_count,
	fs.total_elapsed_time/fs.execution_count AS avg_elapsed_time,
	fs.last_elapsed_time,
	fs.total_worker_time/fs.execution_count AS avg_cpu_time,
	fs.last_worker_time AS last_cpu_time,
	fs.min_worker_time AS min_cpu_time, fs.max_worker_time AS max_cpu_time,
	fs.total_logical_reads/fs.execution_count AS avg_logical_reads,
	fs.last_logical_reads, fs.min_logical_reads, fs.max_logical_reads,
	fs.total_physical_reads/fs.execution_count AS avg_physical_reads,
	fs.last_physical_reads, fs.min_physical_reads, fs.max_physical_reads,
	fs.total_logical_writes/fs.execution_count AS avg_logical_writes,
	fs.last_logical_writes, fs.min_logical_writes, fs.max_logical_writes
FROM sys.dm_exec_function_stats (NOLOCK) fs
CROSS APPLY sys.dm_exec_query_plan(fs.plan_handle) qp'
	EXEC (@sqlcmd);
END;
