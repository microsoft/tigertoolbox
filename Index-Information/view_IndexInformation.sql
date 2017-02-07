-- 2012-03-19 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/ezequiel)
--
-- All Databases index info, including duplicate, redundant, rarely used and unused indexes.
--
-- 4/5/2012		Simplified execution by subdividing input queries
-- 4/5/2012		Fixed some collation issues;
-- 4/6/2012		Split in separate listings the unused indexes from rarely used indexes; Split in separate list
-- 6/6/2012		Fixed issue with partition aligned indexes
-- 10/31/2012	Widened search for Redundant Indexes
-- 12/17/2012	Fixed several issues
-- 1/17/2013	Added several index related info
-- 2/1/2013		Fixed issue with Heap identification
-- 2/26/2013	Fixed issue with partition info; Removed alternate keys from search for Unused and Rarely used
-- 4/17/2013	Added more information to duplicate and redundant indexes output, valuable when deciding which
-- 4/19/2013	Fixed issue with potential duplicate index_ids in sys.dm_db_index_operational_stats relating t
-- 5/6/2013		Changed data collection to minimize blocking potential on VLDBs.
-- 5/20/2013	Fixed issue with database names with special characters.
-- 5/29/2013	Fixed issue with large integers in aggregation.
-- 6/20/2013	Added step to avoid entering in loop that generates dump in SQL 2005.
-- 11/10/2013	Added index checks.
-- 2/24/2014	Added info to Unused_IX section.
-- 6/4/2014		Refined search for duplicate and redundant indexes.
-- 11/12/2014	Added SQL 2014 Hash indexes support; changed scan mode to LIMITED; added search for hard coded
-- 11/2/2016	Added support for SQL Server 2016 sys.dm_db_index_operational_stats changes; Added script creation.

/*
NOTE: on SQL Server 2005, be aware that querying sys.dm_db_index_usage_stats when it has large number of rows may lead to performance issues.
URL: http://support.microsoft.com/kb/2003031
*/

SET NOCOUNT ON;

DECLARE @UpTime VARCHAR(12), @StartDate DATETIME, @sqlmajorver int, @sqlcmd NVARCHAR(4000), @params NVARCHAR(500)
DECLARE @DatabaseName sysname, @indexName sysname
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

SELECT @StartDate AS Collecting_Data_Since, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'h ' + CONVERT(VARCHAR(4),@UpTime%60) + 'm' AS Collecting_Data_For

RAISERROR (N'Starting...', 10, 1) WITH NOWAIT

DECLARE @dbid int--, @sqlcmd NVARCHAR(4000)

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDatabases'))
DROP TABLE #tblDatabases;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDatabases'))
CREATE TABLE #tblDatabases (database_id int PRIMARY KEY, is_done bit)

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
DROP TABLE #tblWorking;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
CREATE TABLE #tblWorking (database_id int, [object_id] int, [object_name] NVARCHAR(255), index_id int, index_name NVARCHAR(255), [schema_name] NVARCHAR(255), partition_number int, is_done bit)

INSERT INTO #tblDatabases 
SELECT database_id, 0 FROM sys.databases WHERE is_read_only = 0 AND state = 0 AND database_id > 4 AND is_distributor = 0;

RAISERROR (N'Populating support tables...', 10, 1) WITH NOWAIT

WHILE (SELECT COUNT(*) FROM #tblDatabases WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @dbid = database_id FROM #tblDatabases WHERE is_done = 0
SELECT @sqlcmd = 'SELECT ' + CONVERT(NVARCHAR(255), @dbid) + ', si.[object_id], mst.[name], si.index_id, si.name, t.name, sp.partition_number, 0
FROM [' + DB_NAME(@dbid) + '].sys.indexes si
INNER JOIN [' + DB_NAME(@dbid) + '].sys.partitions sp ON si.[object_id] = sp.[object_id] AND si.index_id = sp.index_id
INNER JOIN [' + DB_NAME(@dbid) + '].sys.tables AS mst ON mst.[object_id] = si.[object_id]
INNER JOIN [' + DB_NAME(@dbid) + '].sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE mst.is_ms_shipped = 0'
	INSERT INTO #tblWorking
	EXEC sp_executesql @sqlcmd;
	
	UPDATE #tblDatabases
	SET is_done = 1
	WHERE database_id = @dbid;
END

--------------------------------------------------------
-- Index physical and usage stats
--------------------------------------------------------
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
DROP TABLE #tmpIPS;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
CREATE TABLE #tmpIPS (
	[database_id] int,
	[object_id] int,
	[index_id] int,
	[partition_number] int,
	fragmentation DECIMAL(18,3),
	[page_count] bigint,
	[size_MB] DECIMAL(26,3),
	record_count int,
	forwarded_record_count int NULL,
	CONSTRAINT PK_IPS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]))

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIOS'))
DROP TABLE #tmpIOS;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIOS'))
CREATE TABLE #tmpIOS (
	[database_id] int,
	[object_id] int,
	[index_id] int,
	[partition_number] int,
	range_scan_count bigint NULL,
	singleton_lookup_count bigint NULL,
	forwarded_fetch_count bigint NULL,
	row_lock_count bigint NULL,
	row_lock_wait_count bigint NULL,
	row_lock_pct NUMERIC(15,2) NULL,
	row_lock_wait_in_ms bigint NULL,
	[avg_row_lock_waits_in_ms] NUMERIC(15,2) NULL,
	page_lock_count bigint NULL,
	page_lock_wait_count bigint NULL,
	page_lock_pct NUMERIC(15,2) NULL,
	page_lock_wait_in_ms bigint NULL,
	[avg_page_lock_waits_in_ms] NUMERIC(15,2) NULL,
	page_io_latch_wait_in_ms bigint NULL,
	[avg_page_io_latch_wait_in_ms] NUMERIC(15,2) NULL
	CONSTRAINT PK_IOS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]));

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIUS'))
DROP TABLE #tmpIUS;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIUS'))
CREATE TABLE #tmpIUS (
	[database_id] int,
	[schema_name] VARCHAR(100) COLLATE database_default,
	[object_id] int,
	[index_id] int,
	[Hits] bigint NULL,
	[Reads_Ratio] DECIMAL(5,2),
	[Writes_Ratio] DECIMAL(5,2),
	user_updates bigint,
	last_user_seek DATETIME NULL,
	last_user_scan DATETIME NULL,
	last_user_lookup DATETIME NULL,
	last_user_update DATETIME NULL
	CONSTRAINT PK_IUS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id]));

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIxs'))
DROP TABLE #tmpIxs;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIxs'))
CREATE TABLE #tmpIxs (
	[database_id] int, 
	[database_name] VARCHAR(500), 
	[object_id] int, 
	[schema_name] VARCHAR(100) COLLATE database_default, 
	[table_name] VARCHAR(300) COLLATE database_default, 
	[index_id] int, 
	[index_name] VARCHAR(300) COLLATE database_default,
	[partition_number] int,
	[index_type] tinyint,
	type_desc NVARCHAR(30),
	is_primary_key bit,
	is_unique_constraint bit,
	is_disabled bit,
	fill_factor tinyint, 
	is_unique bit, 
	is_padded bit, 
	has_filter bit,
	filter_definition NVARCHAR(max),
	KeyCols VARCHAR(4000), 
	KeyColsOrdered VARCHAR(4000), 
	IncludedCols VARCHAR(4000) NULL, 
	IncludedColsOrdered VARCHAR(4000) NULL, 
	AllColsOrdered VARCHAR(4000) NULL,
	[KeyCols_data_length_bytes] int,
	CONSTRAINT PK_Ixs PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]));

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAgg'))
DROP TABLE #tmpAgg;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAgg'))
CREATE TABLE #tmpAgg (
	[database_id] int,
	[database_name] sysname,
	[object_id] int,
	[schema_name] VARCHAR(100) COLLATE database_default,
	[table_name] VARCHAR(300) COLLATE database_default,
	[index_id] int,
	[index_name] VARCHAR(300) COLLATE database_default,
	[partition_number] int,
	fragmentation DECIMAL(18,3),
	fill_factor tinyint,
	[page_count] bigint,
	[size_MB] DECIMAL(26,3),
	record_count bigint, 
	forwarded_record_count bigint NULL,
	range_scan_count bigint NULL,
	singleton_lookup_count bigint NULL,
	forwarded_fetch_count bigint NULL,
	row_lock_count bigint NULL,
	row_lock_wait_count bigint NULL,
	row_lock_pct NUMERIC(15,2) NULL,
	row_lock_wait_in_ms bigint NULL,
	[avg_row_lock_waits_in_ms] NUMERIC(15,2) NULL,
	page_lock_count bigint NULL,
	page_lock_wait_count bigint NULL,
	page_lock_pct NUMERIC(15,2) NULL,
	page_lock_wait_in_ms bigint NULL,
	[avg_page_lock_waits_in_ms] NUMERIC(15,2) NULL,
	page_io_latch_wait_in_ms bigint NULL,
	[avg_page_io_latch_wait_in_ms] NUMERIC(15,2) NULL,
	[Hits] bigint NULL,
	[Reads_Ratio] DECIMAL(5,2),
	[Writes_Ratio] DECIMAL(5,2),
	user_updates bigint,
	last_user_seek DATETIME NULL,
	last_user_scan DATETIME NULL,
	last_user_lookup DATETIME NULL,
	last_user_update DATETIME NULL,
	KeyCols VARCHAR(4000) COLLATE database_default,
	KeyColsOrdered VARCHAR(4000) COLLATE database_default,
	IncludedCols VARCHAR(4000) COLLATE database_default NULL,
	IncludedColsOrdered VARCHAR(4000) COLLATE database_default NULL, 
	AllColsOrdered VARCHAR(4000) COLLATE database_default NULL,
	is_unique bit,
	[type] tinyint,
	type_desc NVARCHAR(30),
	is_primary_key bit,
	is_unique_constraint bit,
	is_padded bit, 
	has_filter bit, 
	filter_definition NVARCHAR(max),
	is_disabled bit,
	[KeyCols_data_length_bytes] int,	
	CONSTRAINT PK_tmpAgg PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]));

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
DROP TABLE #tblCode;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
CREATE TABLE #tblCode (
	[DatabaseName] sysname, 
	[schemaName] VARCHAR(100), 
	[objectName] VARCHAR(200), 
	[indexName] VARCHAR(200), 
	type_desc NVARCHAR(60));
	
IF @sqlmajorver >= 12
BEGIN
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
	DROP TABLE #tmpXIS;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
	CREATE TABLE #tmpXIS (
		[database_id] int,
		[object_id] int,
		[schema_name] VARCHAR(100) COLLATE database_default,
		[table_name] VARCHAR(300) COLLATE database_default,
		[index_id] int,
		[index_name] VARCHAR(300) COLLATE database_default,
		total_bucket_count bigint, 
		empty_bucket_count bigint, 
		avg_chain_length bigint, 
		max_chain_length bigint, 
		scans_started bigint, 
		scans_retries bigint, 
		rows_returned bigint, 
		rows_touched bigint,
		CONSTRAINT PK_tmpXIS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
	DROP TABLE #tmpXNCIS;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
	CREATE TABLE #tmpXNCIS (
		[database_id] int,
		[object_id] int,
		[schema_name] VARCHAR(100) COLLATE database_default,
		[table_name] VARCHAR(300) COLLATE database_default,
		[index_id] int,
		[index_name] VARCHAR(300) COLLATE database_default,
		delta_pages bigint, 
		internal_pages bigint, 
		leaf_pages bigint, 
		page_update_count bigint,
		page_update_retry_count bigint, 
		page_consolidation_count bigint,
		page_consolidation_retry_count bigint, 
		page_split_count bigint, 
		page_split_retry_count bigint,
		key_split_count bigint, 
		key_split_retry_count bigint, 
		page_merge_count bigint, 
		page_merge_retry_count bigint,
		key_merge_count bigint, 
		key_merge_retry_count bigint, 
		scans_started bigint, 
		scans_retries bigint, 
		rows_returned bigint, 
		rows_touched bigint,
		CONSTRAINT PK_tmpXNCIS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPHash'))
	DROP TABLE #tmpAggXTPHash;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPHash'))
	CREATE TABLE #tmpAggXTPHash (
		[database_id] int,
		[database_name] sysname,
		[object_id] int,
		[schema_name] VARCHAR(100) COLLATE database_default,
		[table_name] VARCHAR(300) COLLATE database_default,
		[index_id] int,
		[index_name] VARCHAR(300) COLLATE database_default,
		total_bucket_count bigint, 
		empty_bucket_count bigint, 
		avg_chain_length bigint, 
		max_chain_length bigint, 
		scans_started bigint, 
		scans_retries bigint, 
		rows_returned bigint, 
		rows_touched bigint,
		KeyCols VARCHAR(4000) COLLATE database_default,
		KeyColsOrdered VARCHAR(4000) COLLATE database_default,
		IncludedCols VARCHAR(4000) COLLATE database_default NULL,
		IncludedColsOrdered VARCHAR(4000) COLLATE database_default NULL, 
		AllColsOrdered VARCHAR(4000) COLLATE database_default NULL,
		is_unique bit,
		[type] tinyint,
		type_desc NVARCHAR(30),
		is_primary_key bit,
		is_unique_constraint bit,
		is_padded bit, 
		has_filter bit, 
		filter_definition NVARCHAR(max),
		is_disabled bit,
		[KeyCols_data_length_bytes] int,	
		CONSTRAINT PK_tmpAggXTPHash PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPNC'))
	DROP TABLE #tmpAggXTPNC;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPNC'))
	CREATE TABLE #tmpAggXTPNC (
		[database_id] int,
		[database_name] sysname,
		[object_id] int,
		[schema_name] VARCHAR(100) COLLATE database_default,
		[table_name] VARCHAR(300) COLLATE database_default,
		[index_id] int,
		[index_name] VARCHAR(300) COLLATE database_default,
		delta_pages bigint, 
		internal_pages bigint, 
		leaf_pages bigint, 
		page_update_count bigint,
		page_update_retry_count bigint, 
		page_consolidation_count bigint,
		page_consolidation_retry_count bigint, 
		page_split_count bigint, 
		page_split_retry_count bigint,
		key_split_count bigint, 
		key_split_retry_count bigint, 
		page_merge_count bigint, 
		page_merge_retry_count bigint,
		key_merge_count bigint, 
		key_merge_retry_count bigint, 
		scans_started bigint, 
		scans_retries bigint, 
		rows_returned bigint, 
		rows_touched bigint,
		KeyCols VARCHAR(4000) COLLATE database_default,
		KeyColsOrdered VARCHAR(4000) COLLATE database_default,
		IncludedCols VARCHAR(4000) COLLATE database_default NULL,
		IncludedColsOrdered VARCHAR(4000) COLLATE database_default NULL, 
		AllColsOrdered VARCHAR(4000) COLLATE database_default NULL,
		is_unique bit,
		[type] tinyint,
		type_desc NVARCHAR(30),
		is_primary_key bit,
		is_unique_constraint bit,
		is_padded bit,
		has_filter bit,
		filter_definition NVARCHAR(max),
		is_disabled bit,
		[KeyCols_data_length_bytes] int,	
		CONSTRAINT PK_tmpAggXTPNC PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpHashIxs'))
	DROP TABLE #tmpHashIxs;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpHashIxs'))
	CREATE TABLE #tmpHashIxs (
		[database_id] int, 
		[database_name] VARCHAR(500), 
		[object_id] int, 
		[schema_name] VARCHAR(100) COLLATE database_default, 
		[table_name] VARCHAR(300) COLLATE database_default, 
		[index_id] int, 
		[index_name] VARCHAR(300) COLLATE database_default,
		[partition_number] int,
		[index_type] tinyint,
		type_desc NVARCHAR(30),
		is_primary_key bit,
		is_unique_constraint bit,
		is_disabled bit,
		fill_factor tinyint, 
		is_unique bit, 
		is_padded bit, 
		has_filter bit,
		filter_definition NVARCHAR(max),
		[bucket_count] bigint,
		KeyCols VARCHAR(4000), 
		KeyColsOrdered VARCHAR(4000), 
		IncludedCols VARCHAR(4000) NULL, 
		IncludedColsOrdered VARCHAR(4000) NULL, 
		AllColsOrdered VARCHAR(4000) NULL,
		[KeyCols_data_length_bytes] int,
		CONSTRAINT PK_HashIxs PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]));
END;

DECLARE /*@dbid int, */@objectid int, @indexid int, @partition_nr int, @dbname NVARCHAR(255), @oname NVARCHAR(255), @iname NVARCHAR(255), @sname NVARCHAR(255)

RAISERROR (N'Gathering sys.dm_db_index_physical_stats and sys.dm_db_index_operational_stats data...', 10, 1) WITH NOWAIT

WHILE (SELECT COUNT(*) FROM #tblWorking WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @dbid = database_id, @objectid = [object_id], @indexid = index_id, @partition_nr = partition_number, @oname = [object_name], @iname = index_name, @sname = [schema_name]
	FROM #tblWorking WHERE is_done = 0
	
	INSERT INTO #tmpIPS
	SELECT ps.database_id, 
		ps.[object_id], 
		ps.index_id, 
		ps.partition_number, 
		SUM(ps.avg_fragmentation_in_percent),
		SUM(ps.page_count),
		CAST((SUM(ps.page_count)*8)/1024 AS DECIMAL(26,3)) AS [size_MB],
		SUM(ISNULL(ps.record_count,0)),
		SUM(ISNULL(ps.forwarded_record_count,0)) -- for heaps
	FROM sys.dm_db_index_physical_stats(@dbid, @objectid, @indexid , @partition_nr, 'SAMPLED') AS ps
	WHERE /*ps.index_id > 0 -- ignore heaps
		AND */ps.index_level = 0 -- leaf-level nodes only
		AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'
	GROUP BY ps.database_id, ps.[object_id], ps.index_id, ps.partition_number
	OPTION (MAXDOP 2);

	-- Avoid entering in loop that generates dump in SQL 2005
	IF @sqlmajorver = 9
	BEGIN
		SET @sqlcmd = (SELECT 'USE [' + DB_NAME(@dbid) + '];
UPDATE STATISTICS ' + QUOTENAME(@sname) + '.' + QUOTENAME(@oname) + CASE WHEN @iname IS NULL THEN '' ELSE ' (' + QUOTENAME(@iname) + ')' END)
		EXEC sp_executesql @sqlcmd
	END;
	SET @sqlcmd = N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + DB_NAME(@dbid) + '];
WITH osCTE (database_id, [object_id], index_id, partition_number, range_scan_count, singleton_lookup_count, 
	forwarded_fetch_count, row_lock_count, row_lock_wait_count, row_lock_wait_in_ms, page_lock_count, 
	page_lock_wait_count, page_lock_wait_in_ms, page_io_latch_wait_count, page_io_latch_wait_in_ms)
AS (SELECT os.database_id, 
	os.[object_id], 
	os.index_id,
	os.partition_number, 
	SUM(os.range_scan_count), 
	SUM(os.singleton_lookup_count),
	SUM(os.forwarded_fetch_count),
	SUM(os.row_lock_count),
	SUM(os.row_lock_wait_count),
	SUM(os.row_lock_wait_in_ms),
	SUM(os.page_lock_count),
	SUM(os.page_lock_wait_count),
	SUM(os.page_lock_wait_in_ms),
	SUM(os.page_io_latch_wait_count),
	SUM(os.page_io_latch_wait_in_ms)
FROM sys.dm_db_index_operational_stats(' + CONVERT(NVARCHAR(20), @dbid) + ', ' + CONVERT(NVARCHAR(20), @objectid) + ', ' + CONVERT(NVARCHAR(20), @indexid) + ', ' + CONVERT(NVARCHAR(20), @partition_nr) + ') AS os
INNER JOIN sys.objects AS o WITH (NOLOCK) ON os.[object_id] = o.[object_id]
' + CASE WHEN @sqlmajorver >= 13 THEN 'LEFT JOIN sys.internal_partitions AS ip WITH (NOLOCK) ON os.hobt_id = ip.hobt_id AND ip.internal_object_type IN (2,3)' ELSE '' END + '
WHERE o.[type] = ''U''
GROUP BY os.database_id, os.[object_id], os.index_id, os.partition_number
)
SELECT osCTE.database_id, 
	osCTE.[object_id], 
	osCTE.index_id,
	osCTE.partition_number, 
	osCTE.range_scan_count, 
	osCTE.singleton_lookup_count,
	osCTE.forwarded_fetch_count,
	osCTE.row_lock_count,
	osCTE.row_lock_wait_count,
	CAST(100.0 * osCTE.row_lock_wait_count / (1 + osCTE.row_lock_count) AS numeric(15,2)) AS row_lock_pct,
	osCTE.row_lock_wait_in_ms,
	CAST(1.0 * osCTE.row_lock_wait_in_ms / (1 + osCTE.row_lock_wait_count) AS numeric(15,2)) AS [avg_row_lock_waits_in_ms],
	osCTE.page_lock_count,
	osCTE.page_lock_wait_count,
	CAST(100.0 * osCTE.page_lock_wait_count / (1 + osCTE.page_lock_count) AS numeric(15,2)) AS page_lock_pct,
	osCTE.page_lock_wait_in_ms,
	CAST(1.0 * osCTE.page_lock_wait_in_ms / (1 + osCTE.page_lock_wait_count) AS numeric(15,2)) AS [avg_page_lock_waits_in_ms],
	osCTE.page_io_latch_wait_in_ms,
	CAST(1.0 * osCTE.page_io_latch_wait_in_ms / (1 + osCTE.page_io_latch_wait_count) AS numeric(15,2)) AS [avg_page_io_latch_wait_in_ms]
FROM osCTE
--WHERE os.index_id > 0 -- ignore heaps
OPTION (MAXDOP 2);'

	INSERT INTO #tmpIOS
	EXEC sp_executesql @sqlcmd

	UPDATE #tblWorking
	SET is_done = 1
	WHERE database_id = @dbid AND [object_id] = @objectid AND index_id = @indexid AND partition_number = @partition_nr
END;

RAISERROR (N'Gathering sys.dm_db_index_usage_stats data...', 10, 1) WITH NOWAIT

UPDATE #tblDatabases
SET is_done = 0;

WHILE (SELECT COUNT(*) FROM #tblDatabases WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @dbid = database_id FROM #tblDatabases WHERE is_done = 0
	SELECT @dbname = DB_NAME(@dbid)
	
	SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT s.database_id, t.name, s.[object_id], s.index_id,
	(s.user_seeks + s.user_scans + s.user_lookups) AS [Hits],
	RTRIM(CONVERT(NVARCHAR(20),CAST(CASE WHEN (s.user_seeks + s.user_scans + s.user_lookups) = 0 THEN 0 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups)) * 100 /
		CASE (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates) WHEN 0 THEN 1 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates)) END END AS DECIMAL(18,2))) COLLATE database_default) AS [Reads_Ratio],
	RTRIM(CONVERT(NVARCHAR(20),CAST(CASE WHEN s.user_updates = 0 THEN 0 ELSE CONVERT(REAL, s.user_updates) * 100 /
		CASE (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates) WHEN 0 THEN 1 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates)) END END AS DECIMAL(18,2))) COLLATE database_default) AS [Writes_Ratio],
	s.user_updates,
	MAX(s.last_user_seek) AS last_user_seek,
	MAX(s.last_user_scan) AS last_user_scan,
	MAX(s.last_user_lookup) AS last_user_lookup,
	MAX(s.last_user_update) AS last_user_update
FROM sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
INNER JOIN sys.objects AS o WITH (NOLOCK) ON s.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst WITH (NOLOCK) ON mst.[object_id] = s.[object_id]
INNER JOIN sys.schemas AS t WITH (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U''
	AND s.database_id = ' + CONVERT(NVARCHAR(20), @dbid) + ' 
	--AND s.index_id > 0 -- ignore heaps
GROUP BY s.database_id, t.name, s.[object_id], s.index_id, s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
OPTION (MAXDOP 2)'

	INSERT INTO #tmpIUS
	EXECUTE sp_executesql @sqlcmd

	SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id], t.name, i.[object_id], i.index_id, 0, 0, 0, NULL, NULL, NULL, NULL, NULL
FROM sys.indexes i WITH (NOLOCK)
INNER JOIN sys.objects o WITH (NOLOCK) ON i.object_id = o.object_id 
INNER JOIN sys.tables AS mst WITH (NOLOCK) ON mst.[object_id] = i.[object_id]
INNER JOIN sys.schemas AS t WITH (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U''
AND i.index_id NOT IN (SELECT s.index_id
	FROM sys.dm_db_index_usage_stats s WITH (NOLOCK)
	WHERE s.object_id = i.object_id 
		AND i.index_id = s.index_id 
		AND database_id = ' + CONVERT(NVARCHAR(20), @dbid) + ')
		AND i.name IS NOT NULL
		AND i.index_id > 1'

	INSERT INTO #tmpIUS
	EXECUTE sp_executesql @sqlcmd

	UPDATE #tblDatabases
	SET is_done = 1
	WHERE database_id = @dbid;
END;

IF @sqlmajorver >= 12
BEGIN
	RAISERROR (N'Gathering sys.dm_db_xtp_hash_index_stats and sys.dm_db_xtp_nonclustered_index_stats data...', 10, 1) WITH NOWAIT

	UPDATE #tblDatabases
	SET is_done = 0;

	WHILE (SELECT COUNT(*) FROM #tblDatabases WHERE is_done = 0) > 0
	BEGIN
		SELECT TOP 1 @dbid = database_id FROM #tblDatabases WHERE is_done = 0
		SELECT @dbname = DB_NAME(@dbid)
		
		SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id], xis.[object_id], t.name, o.name, xis.index_id, si.name, 
	xhis.total_bucket_count, xhis.empty_bucket_count, xhis.avg_chain_length, xhis.max_chain_length, 
	xis.scans_started, xis.scans_retries, xis.rows_returned, xis.rows_touched
FROM sys.dm_db_xtp_hash_index_stats xhis
INNER JOIN sys.dm_db_xtp_index_stats xis ON xis.[object_id] = xhis.[object_id] AND xis.[index_id] = xhis.[index_id] 
INNER JOIN sys.indexes AS si WITH (NOLOCK) ON xis.[object_id] = si.[object_id] AND xis.[index_id] = si.[index_id]
INNER JOIN sys.objects AS o WITH (NOLOCK) ON si.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst WITH (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas AS t WITH (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U'''

		INSERT INTO #tmpXIS
		EXECUTE sp_executesql @sqlcmd
	
		SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id],
	xis.[object_id], t.name, o.name, xis.index_id, si.name, 
	xnis.delta_pages, xnis.internal_pages, xnis.leaf_pages, xnis.page_update_count,
	xnis.page_update_retry_count, xnis.page_consolidation_count,
	xnis.page_consolidation_retry_count, xnis.page_split_count, xnis.page_split_retry_count,
	xnis.key_split_count, xnis.key_split_retry_count, xnis.page_merge_count, xnis.page_merge_retry_count,
	xnis.key_merge_count, xnis.key_merge_retry_count,
	xis.scans_started, xis.scans_retries, xis.rows_returned, xis.rows_touched
FROM sys.dm_db_xtp_nonclustered_index_stats AS xnis WITH (NOLOCK)
INNER JOIN sys.dm_db_xtp_index_stats AS xis WITH (NOLOCK) ON xis.[object_id] = xnis.[object_id] AND xis.[index_id] = xnis.[index_id]
INNER JOIN sys.indexes AS si WITH (NOLOCK) ON xis.[object_id] = si.[object_id] AND xis.[index_id] = si.[index_id]
INNER JOIN sys.objects AS o WITH (NOLOCK) ON si.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst WITH (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas AS t WITH (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U'''
	
		INSERT INTO #tmpXNCIS
		EXECUTE sp_executesql @sqlcmd

		UPDATE #tblDatabases
		SET is_done = 1
		WHERE database_id = @dbid;
	END
END;

RAISERROR (N'Gathering index column data...', 10, 1) WITH NOWAIT

UPDATE #tblDatabases
SET is_done = 0;

WHILE (SELECT COUNT(*) FROM #tblDatabases WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @dbid = database_id FROM #tblDatabases WHERE is_done = 0
	SELECT @dbname = DB_NAME(@dbid)

	SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id], ''' + DB_NAME(@dbid) + ''' AS database_name,
	mst.[object_id], t.name, mst.[name], 
	mi.index_id, mi.[name], p.partition_number,
	mi.[type], mi.[type_desc], mi.is_primary_key, mi.is_unique_constraint, mi.is_disabled, 
	mi.fill_factor, mi.is_unique, mi.is_padded, ' + CASE WHEN @sqlmajorver > 9 THEN 'mi.has_filter, mi.filter_definition,' ELSE 'NULL, NULL,' END + '
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS KeyCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS KeyColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS IncludedCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS IncludedColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS AllColsOrdered,
	(SELECT SUM(CASE sty.name WHEN ''nvarchar'' THEN sc.max_length/2 ELSE sc.max_length END) FROM sys.indexes AS i
		INNER JOIN sys.tables AS t ON t.[object_id] = i.[object_id]
		INNER JOIN sys.schemas ss ON ss.[schema_id] = t.[schema_id]
		INNER JOIN sys.index_columns AS sic ON sic.object_id = mst.object_id AND sic.index_id = mi.index_id
		INNER JOIN sys.columns AS sc ON sc.object_id = t.object_id AND sc.column_id = sic.column_id
		INNER JOIN sys.types AS sty ON sc.user_type_id = sty.user_type_id
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id) AS [KeyCols_data_length_bytes]
FROM sys.indexes AS mi
	INNER JOIN sys.tables AS mst ON mst.[object_id] = mi.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.partitions AS p ON p.[object_id] = mi.[object_id] AND p.index_id = mi.index_id
WHERE mi.type IN (0,1,2,5,6) AND mst.is_ms_shipped = 0
ORDER BY mst.name
OPTION (MAXDOP 2);'

	INSERT INTO #tmpIxs
	EXECUTE sp_executesql @sqlcmd;

	IF @sqlmajorver >= 12
	BEGIN
		SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + DB_NAME(@dbid) + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id], ''' + DB_NAME(@dbid) + ''' AS database_name,
	mst.[object_id], t.name, mst.[name], 
	mi.index_id, mi.[name], p.partition_number,
	mi.[type], mi.[type_desc], mi.is_primary_key, mi.is_unique_constraint, mi.is_disabled, 
	mi.fill_factor, mi.is_unique, mi.is_padded, mi.has_filter, mi.filter_definition,[bucket_count],
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.hash_indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS KeyCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.hash_indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS KeyColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.hash_indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS IncludedCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.hash_indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS IncludedColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.hash_indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS AllColsOrdered,
	(SELECT SUM(CASE sty.name WHEN ''nvarchar'' THEN sc.max_length/2 ELSE sc.max_length END) FROM sys.hash_indexes AS i
		INNER JOIN sys.tables AS t ON t.[object_id] = i.[object_id]
		INNER JOIN sys.schemas ss ON ss.[schema_id] = t.[schema_id]
		INNER JOIN sys.index_columns AS sic ON sic.object_id = mst.object_id AND sic.index_id = mi.index_id
		INNER JOIN sys.columns AS sc ON sc.object_id = t.object_id AND sc.column_id = sic.column_id
		INNER JOIN sys.types AS sty ON sc.user_type_id = sty.user_type_id
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id) AS [KeyCols_data_length_bytes]
FROM sys.hash_indexes AS mi
	INNER JOIN sys.tables AS mst ON mst.[object_id] = mi.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.partitions AS p ON p.[object_id] = mi.[object_id] AND p.index_id = mi.index_id
WHERE mi.type IN (7) AND mst.is_ms_shipped = 0
ORDER BY mst.name
OPTION (MAXDOP 2);'

		INSERT INTO #tmpHashIxs
		EXECUTE sp_executesql @sqlcmd;
	END;
	
	UPDATE #tblDatabases
	SET is_done = 1
	WHERE database_id = @dbid;
END;

RAISERROR (N'Aggregating data...', 10, 1) WITH NOWAIT

INSERT INTO #tmpAgg
SELECT ISNULL(ps.database_id, si.[database_id]), si.database_name, ISNULL(ps.[object_id], si.[object_id]),
	si.[schema_name], si.table_name, si.index_id, si.index_name, ISNULL(ps.partition_number, si.partition_number), 
	ps.fragmentation, si.fill_factor, ps.page_count, ps.[size_MB], ps.record_count, ps.forwarded_record_count, -- for heaps
	os.range_scan_count, os.singleton_lookup_count, os.forwarded_fetch_count, os.row_lock_count,
	os.row_lock_wait_count, os.row_lock_pct, os.row_lock_wait_in_ms, os.[avg_row_lock_waits_in_ms],
	os.page_lock_count, os.page_lock_wait_count, os.page_lock_pct, os.page_lock_wait_in_ms,
	os.[avg_page_lock_waits_in_ms], os.[page_io_latch_wait_in_ms], os.[avg_page_io_latch_wait_in_ms],
	s.[Hits], s.[Reads_Ratio], s.[Writes_Ratio], s.user_updates, s.last_user_seek, s.last_user_scan,
	s.last_user_lookup, s.last_user_update, si.KeyCols, si.KeyColsOrdered, si.IncludedCols,
	si.IncludedColsOrdered, si.AllColsOrdered, si.is_unique, si.[index_type], si.[type_desc],
	si.is_primary_key, si.is_unique_constraint, si.is_padded, si.has_filter, si.filter_definition,
	si.is_disabled,	si.[KeyCols_data_length_bytes]
FROM #tmpIxs AS si
	LEFT JOIN #tmpIPS AS ps ON si.database_id = ps.database_id AND si.index_id = ps.index_id AND si.[object_id] = ps.[object_id] AND si.partition_number = ps.partition_number
	LEFT JOIN #tmpIOS AS os ON os.database_id = ps.database_id AND os.index_id = ps.index_id AND os.[object_id] = ps.[object_id] AND os.partition_number = ps.partition_number
	LEFT JOIN #tmpIUS AS s ON s.database_id = ps.database_id AND s.index_id = ps.index_id and s.[object_id] = ps.[object_id]
--WHERE si.type > 0 -- ignore heaps
ORDER BY database_name, [table_name], fragmentation DESC, index_id
OPTION (MAXDOP 2);

IF @sqlmajorver >= 12
BEGIN
	INSERT INTO #tmpAggXTPHash
	SELECT ISNULL(ps.database_id, si.[database_id]), si.database_name, ISNULL(ps.[object_id], si.[object_id]),
		si.[schema_name], si.table_name, si.index_id, si.index_name, ps.total_bucket_count, ps.empty_bucket_count, 
		ps.avg_chain_length, ps.max_chain_length, ps.scans_started, ps.scans_retries, ps.rows_returned, 
		ps.rows_touched, si.KeyCols, si.KeyColsOrdered, si.IncludedCols, si.IncludedColsOrdered,
		si.AllColsOrdered, si.is_unique, si.[index_type], si.[type_desc], si.is_primary_key, si.is_unique_constraint,
		si.is_padded, si.has_filter, si.filter_definition, si.is_disabled, si.[KeyCols_data_length_bytes]	
	FROM #tmpHashIxs AS si
		LEFT JOIN #tmpXIS AS ps ON si.database_id = ps.database_id AND si.index_id = ps.index_id AND si.[object_id] = ps.[object_id]
	ORDER BY database_name, [table_name], index_id
	OPTION (MAXDOP 2);

	INSERT INTO #tmpAggXTPNC
	SELECT ISNULL(ps.database_id, si.[database_id]), si.database_name, ISNULL(ps.[object_id], si.[object_id]),
		si.[schema_name], si.table_name, si.index_id, si.index_name, ps.delta_pages, ps.internal_pages, 
		ps.leaf_pages, ps.page_update_count, ps.page_update_retry_count, 
		ps.page_consolidation_count, ps.page_consolidation_retry_count, ps.page_split_count, 
		ps.page_split_retry_count, ps.key_split_count, ps.key_split_retry_count, ps.page_merge_count, 
		ps.page_merge_retry_count, ps.key_merge_count, ps.key_merge_retry_count,
		ps.scans_started, ps.scans_retries, ps.rows_returned, ps.rows_touched,
		si.KeyCols, si.KeyColsOrdered, si.IncludedCols, si.IncludedColsOrdered, si.AllColsOrdered,
		si.is_unique, si.[index_type], si.[type_desc], si.is_primary_key, si.is_unique_constraint,
		si.is_padded, si.has_filter, si.filter_definition, si.is_disabled, si.[KeyCols_data_length_bytes]	
	FROM #tmpHashIxs AS si
		LEFT JOIN #tmpXNCIS AS ps ON si.database_id = ps.database_id AND si.index_id = ps.index_id AND si.[object_id] = ps.[object_id]
	ORDER BY database_name, [table_name], index_id
	OPTION (MAXDOP 2);
END;
RAISERROR (N'Output index information', 10, 1) WITH NOWAIT

-- All index information
SELECT 'All_IX_Info' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type,
	[partition_number], fragmentation, fill_factor, [page_count], [size_MB], record_count, range_scan_count, singleton_lookup_count, row_lock_count, row_lock_wait_count,
	row_lock_pct, row_lock_wait_in_ms, [avg_row_lock_waits_in_ms], page_lock_count, page_lock_wait_count,
	page_lock_pct, page_lock_wait_in_ms, [avg_page_lock_waits_in_ms], page_io_latch_wait_in_ms, [avg_page_io_latch_wait_in_ms], [Hits],
	CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
	user_updates, last_user_seek, last_user_scan, last_user_lookup, last_user_update, KeyCols, IncludedCols,
	is_unique, is_primary_key, is_unique_constraint, is_disabled, is_padded, has_filter, filter_definition, KeyCols_data_length_bytes
FROM #tmpAgg
WHERE index_id > 0 -- ignore heaps
ORDER BY [database_name], [schema_name], table_name, [page_count] DESC, forwarded_record_count DESC;

-- All XTP index information
IF @sqlmajorver >= 12
BEGIN
	SELECT 'All_XTP_HashIX_Info' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type,
		total_bucket_count, empty_bucket_count, FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) AS [empty_bucket_pct], avg_chain_length, max_chain_length, 
		scans_started, scans_retries, rows_returned, rows_touched, KeyCols, IncludedCols, is_unique, is_primary_key, is_unique_constraint, is_disabled, is_padded, has_filter, 
		filter_definition, KeyCols_data_length_bytes
	FROM #tmpAggXTPHash
	ORDER BY [database_name], [schema_name], table_name, [total_bucket_count] DESC;

	SELECT 'All_XTP_RangeIX_Info' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type,
		delta_pages, internal_pages, leaf_pages, page_update_count, page_update_retry_count, page_consolidation_count, page_consolidation_retry_count, 
		page_split_count, page_split_retry_count, key_split_count, key_split_retry_count, page_merge_count, page_merge_retry_count, key_merge_count, key_merge_retry_count,
		scans_started, scans_retries, rows_returned, rows_touched, KeyCols, IncludedCols, is_unique, is_primary_key, is_unique_constraint, is_disabled, is_padded, has_filter, 
		filter_definition, KeyCols_data_length_bytes
	FROM #tmpAggXTPNC
	ORDER BY [database_name], [schema_name], table_name, [leaf_pages] DESC;
END;

-- All Heaps information
SELECT 'All_Heaps_Info' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [type_desc] AS index_type,
	[partition_number], fragmentation, [page_count], [size_MB], record_count, forwarded_record_count, forwarded_fetch_count,
	range_scan_count, singleton_lookup_count, row_lock_count, row_lock_wait_count,
	row_lock_pct, row_lock_wait_in_ms, [avg_row_lock_waits_in_ms], page_lock_count, page_lock_wait_count,
	page_lock_pct, page_lock_wait_in_ms, [avg_page_lock_waits_in_ms], page_io_latch_wait_in_ms, [avg_page_io_latch_wait_in_ms]
FROM #tmpAgg
WHERE index_id = 0 -- only heaps
ORDER BY [database_name], [schema_name], table_name, [page_count] DESC, forwarded_record_count DESC;

-- Unused indexes that can possibly be dropped or disabled
SELECT 'Unused_IX_With_Updates' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type, [Hits],
	CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
	[page_count], [size_MB], record_count, user_updates, last_user_seek, last_user_scan, 
	last_user_lookup, last_user_update, is_unique, is_padded, has_filter, filter_definition
FROM #tmpAgg
WHERE [Hits] = 0 
	AND last_user_update > 0
	AND [type] IN (2,6)				-- non-clustered and non-clustered columnstore indexes only
	AND is_primary_key = 0			-- no primary keys
	AND is_unique_constraint = 0	-- no unique constraints
	AND is_unique = 0 				-- no alternate keys
UNION ALL
SELECT 'Unused_IX_No_Updates' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type, [Hits],
	CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
	[page_count], [size_MB], record_count, user_updates, last_user_seek, last_user_scan, 
	last_user_lookup, last_user_update, is_unique, is_padded, has_filter, filter_definition
FROM #tmpAgg
WHERE [Hits] = 0 
	AND (last_user_update = 0 OR last_user_update IS NULL)
	AND [type] IN (2,6)				-- non-clustered and non-clustered columnstore indexes only
	AND is_primary_key = 0			-- no primary keys
	AND is_unique_constraint = 0	-- no unique constraints
	AND is_unique = 0 				-- no alternate keys
ORDER BY [table_name], user_updates DESC, [page_count] DESC;

-- Rarely used indexes that can possibly be dropped or disabled
SELECT 'Rarely_Used_IX' AS [Category], [database_id], [database_name], [object_id], [schema_name], [table_name], [index_id], [index_name], [type_desc] AS index_type, [Hits],
	CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
	[page_count], [size_MB], record_count, user_updates, last_user_seek, last_user_scan, 
	last_user_lookup, last_user_update, is_unique, is_padded, has_filter, filter_definition
FROM #tmpAgg
WHERE [Hits] > 0 AND [Reads_Ratio] < 5
	AND [type] IN (2,6)				-- non-clustered and non-clustered columnstore indexes only
	AND is_primary_key = 0			-- no primary keys
	AND is_unique_constraint = 0	-- no unique constraints
	AND is_unique = 0 				-- no alternate keys
ORDER BY [database_name], [table_name], [page_count] DESC;

-- Duplicate Indexes
SELECT 'Duplicate_IX' AS [Category], I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[type_desc] AS index_type, I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition, 
	I.[Hits], I.[KeyCols], I.IncludedCols, CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END AS [AllColsOrdered]
FROM #tmpAgg I INNER JOIN #tmpAgg I2
	ON I.database_id = I2.database_id AND I.[object_id] = I2.[object_id] AND I.[index_id] <> I2.[index_id] 
	AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
	AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
WHERE I.[type] IN (1,2,5,6)			-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I2.[type] IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
GROUP BY I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[schema_name], I.[index_id], I.[index_name], I.[Hits], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.type_desc, I.[AllColsOrdered], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition
ORDER BY I.database_name, I.[table_name], I.[index_id];

/*
Note that it is possible that a clustered index (unique or not) is among the duplicate indexes to be dropped, 
namely if a non-clustered primary key exists on the table.
In this case, make the appropriate changes in the clustered index (making it unique and/or primary key in this case),
and drop the non-clustered instead.
*/
SELECT 'Duplicate_IX_toDrop' AS [Category], I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[type_desc] AS index_type, I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition, 
	I.[Hits], I.[KeyCols], I.IncludedCols, CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END AS [AllColsOrdered]
FROM #tmpAgg I INNER JOIN #tmpAgg I2
	ON I.database_id = I2.database_id AND I.[object_id] = I2.[object_id] AND I.[index_id] <> I2.[index_id] 
	AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
	AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
WHERE I.[type] IN (1,2,5,6)			-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I2.[type] IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I.[index_id] NOT IN (
			SELECT COALESCE((SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
			(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
			(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
			))
GROUP BY I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[Hits], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.type_desc, I.[AllColsOrdered], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition
ORDER BY I.database_name, I.[table_name], I.[index_id];

RAISERROR (N'Starting index search in sql modules...', 10, 1) WITH NOWAIT

DECLARE Dup_Stats CURSOR FAST_FORWARD FOR SELECT I.database_name,I.[index_name] 
FROM #tmpAgg I INNER JOIN #tmpAgg I2
	ON I.database_id = I2.database_id AND I.[object_id] = I2.[object_id] AND I.[index_id] <> I2.[index_id] 
	AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
	AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
WHERE I.[type] IN (1,2,5,6)			-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I2.[type] IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I.[index_id] NOT IN (
			SELECT COALESCE((SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
			(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
			(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
			WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
				AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
			GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
			))
GROUP BY I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[Hits], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.type_desc, I.[AllColsOrdered], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition
ORDER BY I.database_name, I.[table_name], I.[index_id];

OPEN Dup_Stats
FETCH NEXT FROM Dup_Stats INTO @DatabaseName,@indexName
WHILE (@@FETCH_STATUS = 0)
BEGIN
	SET @sqlcmd = 'USE [' + @DatabaseName + '];
SELECT ''' + @DatabaseName + ''' AS [database_name], ss.name AS [schema_name], so.name AS [table_name], ''' + @indexName + ''' AS [index_name], so.type_desc
FROM sys.sql_modules sm
INNER JOIN sys.objects so ON sm.[object_id] = so.[object_id]
INNER JOIN sys.schemas ss ON ss.[schema_id] = so.[schema_id]
WHERE sm.[definition] LIKE ''%' + @indexName + '%'''

	INSERT INTO #tblCode
	EXECUTE sp_executesql @sqlcmd

	FETCH NEXT FROM Dup_Stats INTO @DatabaseName,@indexName
END
CLOSE Dup_Stats
DEALLOCATE Dup_Stats

RAISERROR (N'Ended index search in sql modules', 10, 1) WITH NOWAIT

SELECT 'Duplicate_Indexes_HardCoded' AS [Category], [DatabaseName], [schemaName], [objectName] AS [referedIn_objectName], 
	indexName AS [referenced_indexName], type_desc AS [refered_objectType]
FROM #tblCode
ORDER BY [DatabaseName], [objectName];

-- Redundant Indexes
SELECT 'Redundant_IX' AS [Category], I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[type_desc] AS index_type, I.is_unique, I.is_padded, I.has_filter, I.filter_definition,
	I.[Hits], I.[KeyCols], I.IncludedCols, CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END AS [AllColsOrdered]
FROM #tmpAgg I INNER JOIN #tmpAgg I2
ON I.[database_id] = I2.[database_id] AND I.[object_id] = I2.[object_id] AND I.[index_id] <> I2.[index_id] 
	AND (((I.[KeyColsOrdered] <> I2.[KeyColsOrdered] OR I.IncludedColsOrdered <> I2.IncludedColsOrdered)
		AND ((CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END) = (CASE WHEN I2.IncludedColsOrdered IS NULL THEN I2.[KeyColsOrdered] ELSE I2.[KeyColsOrdered] + ',' + I2.IncludedColsOrdered END)
			OR I.[AllColsOrdered] = I2.[AllColsOrdered]))
	OR (I.[KeyColsOrdered] <> I2.[KeyColsOrdered] AND I.IncludedColsOrdered = I2.IncludedColsOrdered)
	OR (I.[KeyColsOrdered] = I2.[KeyColsOrdered] AND I.IncludedColsOrdered <> I2.IncludedColsOrdered)
	OR ((I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NULL AND I2.filter_definition IS NOT NULL) OR (I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NOT NULL AND I2.filter_definition IS NULL)))
	AND I.[index_id] NOT IN (SELECT I3.[index_id]
		FROM #tmpIxs I3 INNER JOIN #tmpIxs I4
		ON I3.[database_id] = I4.[database_id] AND I3.[object_id] = I4.[object_id] AND I3.[index_id] <> I4.[index_id] 
			AND I3.[KeyCols] = I4.[KeyCols] AND (I3.IncludedCols = I4.IncludedCols OR (I3.IncludedCols IS NULL AND I4.IncludedCols IS NULL))
		WHERE I3.[database_id] = I.[database_id] AND I3.[object_id] = I.[object_id]
		GROUP BY I3.[index_id])
WHERE I.[type] IN (1,2,5,6)			-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I2.[type] IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
	AND I.is_unique_constraint = 0	-- no unique constraints
	AND I2.is_unique_constraint = 0	-- no unique constraints
GROUP BY I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[Hits], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.type_desc, I.[AllColsOrdered], I.is_unique, I.is_padded, I.has_filter, I.filter_definition
ORDER BY I.database_name, I.[table_name], I.[AllColsOrdered], I.[index_id];

-- Large IX Keys
SELECT 'Large_Index_Key' AS [Category], I.[database_name], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], 
	I.KeyCols, [KeyCols_data_length_bytes]
FROM #tmpAgg I
WHERE [KeyCols_data_length_bytes] > 900
ORDER BY I.[database_name], I.[schema_name], I.[table_name], I.[index_id];

-- Low Fill Factor
SELECT 'Low_Fill_Factor' AS [Category], I.[database_name], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], 
	[fill_factor], I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedCols IS NULL THEN I.[KeyCols] ELSE I.[KeyCols] + ',' + I.IncludedCols END AS [AllColsOrdered]
FROM #tmpAgg I
WHERE [fill_factor] BETWEEN 1 AND 79
ORDER BY I.[database_name], I.[schema_name], I.[table_name], I.[index_id];

--NonUnique Clustered IXs
SELECT 'NonUnique_CIXs' AS [Category], I.[database_name], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[KeyCols]
FROM #tmpAgg I
WHERE [is_unique] = 0 
	AND I.[index_id] = 1
ORDER BY I.[database_name], I.[schema_name], I.[table_name];

RAISERROR (N'Generating scripts...', 10, 1) WITH NOWAIT

DECLARE @strSQL NVARCHAR(4000)
PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'

IF (SELECT COUNT(*) FROM #tmpAgg WHERE [Hits] = 0 AND last_user_update > 0) > 0
BEGIN
	PRINT CHAR(10) + '--############# Existing unused indexes with updates drop statements #############' + CHAR(10)
	DECLARE Un_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [database_name] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [index_name] + ''')' + CHAR(10) + 'DROP INDEX ' + QUOTENAME([index_name]) + ' ON ' + QUOTENAME([schema_name]) + '.' + QUOTENAME([table_name]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
	FROM #tmpAgg
	WHERE [Hits] = 0 AND last_user_update > 0
	ORDER BY [database_name], [table_name], [Reads_Ratio] DESC;

	OPEN Un_Stats
	FETCH NEXT FROM Un_Stats INTO @strSQL
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		PRINT @strSQL
		FETCH NEXT FROM Un_Stats INTO @strSQL
	END
	CLOSE Un_Stats
	DEALLOCATE Un_Stats
	PRINT CHAR(10) + '--############# Ended unused indexes with updates drop statements #############' + CHAR(10)
END;

IF (SELECT COUNT(*) FROM #tmpAgg WHERE [Hits] = 0 AND (last_user_update = 0 OR last_user_update IS NULL)) > 0
BEGIN
	PRINT CHAR(10) + '--############# Existing unused indexes with no updates drop statements #############' + CHAR(10)
	DECLARE Un_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [database_name] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [index_name] + ''')' + CHAR(10) + 'DROP INDEX ' + QUOTENAME([index_name]) + ' ON ' + QUOTENAME([schema_name]) + '.' + QUOTENAME([table_name]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
	FROM #tmpAgg
	WHERE [Hits] = 0 AND (last_user_update = 0 OR last_user_update IS NULL)
	ORDER BY [database_name], [table_name], [Reads_Ratio] DESC;

	OPEN Un_Stats
	FETCH NEXT FROM Un_Stats INTO @strSQL
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		PRINT @strSQL
		FETCH NEXT FROM Un_Stats INTO @strSQL
	END
	CLOSE Un_Stats
	DEALLOCATE Un_Stats
	PRINT CHAR(10) + '--############# Ended unused indexes with no updates drop statements #############' + CHAR(10)
END;

IF (SELECT COUNT(*) FROM #tmpAgg WHERE [Hits] > 0 AND [Reads_Ratio] < 5) > 0
BEGIN
	PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
	PRINT CHAR(10) + '--############# Existing rarely used indexes drop statements #############' + CHAR(10)
	DECLARE curRarUsed CURSOR FAST_FORWARD FOR SELECT 'USE ' + [database_name] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [index_name] + ''')' + CHAR(10) + 'DROP INDEX ' + QUOTENAME([index_name]) + ' ON ' + QUOTENAME([schema_name]) + '.' + QUOTENAME([table_name]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
	FROM #tmpAgg
	WHERE [Hits] > 0 AND [Reads_Ratio] < 5
	ORDER BY [database_name], [table_name], [Reads_Ratio] DESC

	OPEN curRarUsed
	FETCH NEXT FROM curRarUsed INTO @strSQL
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		PRINT @strSQL
		FETCH NEXT FROM curRarUsed INTO @strSQL
	END
	CLOSE curRarUsed
	DEALLOCATE curRarUsed
	PRINT '--############# Ended rarely used indexes drop statements #############' + CHAR(10)
END;

PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
PRINT CHAR(10) + '/*
NOTE: It is possible that a clustered index (unique or not) is among the duplicate indexes to be dropped, namely if a non-clustered primary key exists on the table.
In this case, make the appropriate changes in the clustered index (making it unique and/or primary key in this case), and drop the non-clustered instead.
*/'
PRINT CHAR(10) + '--############# Existing Duplicate indexes drop statements #############' + CHAR(10)
DECLARE Dup_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + I.[database_name] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ I.[index_name] + ''')' + CHAR(10) + 'DROP INDEX ' + QUOTENAME(I.[index_name]) + ' ON ' + QUOTENAME(I.[schema_name]) + '.' + QUOTENAME(I.[table_name]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
	FROM #tmpAgg I INNER JOIN #tmpAgg I2
		ON I.database_id = I2.database_id AND I.[object_id] = I2.[object_id] AND I.[index_id] <> I2.[index_id] 
		AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
		AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
	WHERE I.[type] IN (1,2,5,6)			-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
		AND I2.[type] IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
		AND I.[index_id] NOT IN (
				SELECT COALESCE((SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
				WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
				GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
				WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
				GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[index_id]) FROM #tmpAgg tI3
				WHERE tI3.[database_id] = I.[database_id] AND tI3.[object_id] = I.[object_id] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				GROUP BY tI3.[object_id], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
				))
	GROUP BY I.[database_id], I.[database_name], I.[object_id], I.[schema_name], I.[table_name], I.[index_id], I.[index_name], I.[Hits], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.type_desc, I.[AllColsOrdered], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.is_padded, I.has_filter, I.filter_definition
	ORDER BY I.database_name, I.[table_name], I.[index_id];
OPEN Dup_Stats
FETCH NEXT FROM Dup_Stats INTO @strSQL
WHILE (@@FETCH_STATUS = 0)
BEGIN
	PRINT @strSQL
	FETCH NEXT FROM Dup_Stats INTO @strSQL
END
CLOSE Dup_Stats
DEALLOCATE Dup_Stats
PRINT '--############# Ended Duplicate indexes drop statements #############' + CHAR(10)

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
DROP TABLE #tmpIPS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIOS'))
DROP TABLE #tmpIOS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIUS'))
DROP TABLE #tmpIUS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
DROP TABLE #tmpXIS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
DROP TABLE #tmpXNCIS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIxs'))
DROP TABLE #tmpIxs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpHashIxs'))
DROP TABLE #tmpHashIxs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAgg'))
DROP TABLE #tmpAgg;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPHash'))
DROP TABLE #tmpAggXTPHash;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpAggXTPNC'))
DROP TABLE #tmpAggXTPNC;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
DROP TABLE #tblWorking;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
DROP TABLE #tblCode;
GO