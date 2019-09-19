-- If you are using AdaptiveIndexDefrag together with the maintenance plans in http://blogs.msdn.com/b/blogdoezequiel/archive/2012/09/18/about-maintenance-plans-grooming-sql-server.aspx
-- please note that the job that runs AdaptiveIndexDefrag is expecting msdb. As such, change the database context accordingly.

-- For deployment in Azure SQL Database, remove or comment the USE statement below.
USE msdb
GO

SET NOCOUNT ON;

DECLARE @deploymode bit
SET @deploymode = 0 /* 0 = Upgrade from immediately previous version, preserving all historic data;
							1 = Rewrite all objects, disregarding historic data */

/* Scroll down to line 429 to the see notes, disclaimers, and licensing information */

RAISERROR('Droping existing objects', 0, 42) WITH NOWAIT;

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_CurrentExecStats')
DROP VIEW vw_CurrentExecStats

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_ErrLst30Days')
DROP VIEW vw_ErrLst30Days

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_LastRun_Log')
DROP VIEW vw_LastRun_Log

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_ErrLst24Hrs')
DROP VIEW vw_ErrLst24Hrs

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_AvgSamplingLst30Days')
DROP VIEW vw_AvgSamplingLst30Days

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_AvgTimeLst30Days ')
DROP VIEW vw_AvgTimeLst30Days

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_AvgFragLst30Days')
DROP VIEW vw_AvgFragLst30Days

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_AvgLargestLst30Days')
DROP VIEW vw_AvgLargestLst30Days

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_AvgMostUsedLst30Days')
DROP VIEW vw_AvgMostUsedLst30Days

IF @deploymode = 0
BEGIN
	RAISERROR('Preserving historic data', 0, 42) WITH NOWAIT;
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_log', 'tbl_AdaptiveIndexDefrag_log_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_log_old.PK_AdaptiveIndexDefrag_log', N'PK_AdaptiveIndexDefrag_log_old', N'INDEX';
	END;
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_Analysis_log', 'tbl_AdaptiveIndexDefrag_Analysis_log_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_Analysis_log_old.PK_AdaptiveIndexDefrag_Analysis_log', N'PK_AdaptiveIndexDefrag_Analysis_log_old', N'INDEX';
	END;
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_Stats_log', 'tbl_AdaptiveIndexDefrag_Stats_log_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_Stats_log_old.PK_AdaptiveIndexDefrag_Stats_log', N'PK_AdaptiveIndexDefrag_Stats_log_old', N'INDEX';
	END;
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_Exceptions', 'tbl_AdaptiveIndexDefrag_Exceptions_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_Exceptions_old.PK_AdaptiveIndexDefrag_Exceptions', N'PK_AdaptiveIndexDefrag_Exceptions_old', N'INDEX';
	END;
		
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_Working', 'tbl_AdaptiveIndexDefrag_Working_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_Working_old.PK_AdaptiveIndexDefrag_Working', N'PK_AdaptiveIndexDefrag_Working_old', N'INDEX';
	END;
		
	IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_Stats_Working', 'tbl_AdaptiveIndexDefrag_Stats_Working_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_Stats_Working_old.PK_AdaptiveIndexDefrag_Stats_Working', N'PK_AdaptiveIndexDefrag_Stats_Working_old', N'INDEX';
	END;
		IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus') AND NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus_old')
	BEGIN
		EXEC sp_rename 'tbl_AdaptiveIndexDefrag_IxDisableStatus', 'tbl_AdaptiveIndexDefrag_IxDisableStatus_old';
		EXEC sp_rename N'tbl_AdaptiveIndexDefrag_IxDisableStatus_old.PK_AdaptiveIndexDefrag_IxDisableStatus', N'PK_AdaptiveIndexDefrag_IxDisableStatus_old', N'INDEX';
	END;
END

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log')
DROP TABLE tbl_AdaptiveIndexDefrag_log;

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log')
DROP TABLE tbl_AdaptiveIndexDefrag_Analysis_log

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log')
DROP TABLE tbl_AdaptiveIndexDefrag_Stats_log;

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions')
DROP TABLE tbl_AdaptiveIndexDefrag_Exceptions;

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working')
DROP TABLE tbl_AdaptiveIndexDefrag_Working;

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working')
DROP TABLE tbl_AdaptiveIndexDefrag_Stats_Working;

IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus')
DROP TABLE tbl_AdaptiveIndexDefrag_IxDisableStatus;

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_AdaptiveIndexDefrag_PurgeLogs'), N'IsProcedure') = 1
DROP PROCEDURE dbo.usp_AdaptiveIndexDefrag_PurgeLogs;

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_AdaptiveIndexDefrag_Exceptions'), N'IsProcedure') = 1
DROP PROCEDURE dbo.usp_AdaptiveIndexDefrag_Exceptions;

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_AdaptiveIndexDefrag_Exclusions'), N'IsProcedure') = 1
DROP PROCEDURE dbo.usp_AdaptiveIndexDefrag_Exclusions;

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_CurrentExecStats'), N'IsProcedure') = 1
DROP PROCEDURE dbo.usp_CurrentExecStats;

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_AdaptiveIndexDefrag_CurrentExecStats'), N'IsProcedure') = 1
DROP PROCEDURE dbo.usp_AdaptiveIndexDefrag_CurrentExecStats;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_log
	(indexDefrag_id int identity(1,1) NOT NULL
	, dbID int NOT NULL
	, dbName NVARCHAR(128) NOT NULL
	, objectID int NOT NULL
	, objectName NVARCHAR(256) NULL
	, indexID int NOT NULL
	, indexName NVARCHAR(256) NULL
	, partitionNumber smallint
	, fragmentation float NOT NULL
	, page_count bigint NOT NULL
	, range_scan_count bigint NULL
	, fill_factor int NULL
	, dateTimeStart DATETIME NOT NULL
	, dateTimeEnd DATETIME NULL
	, durationSeconds int NULL
	, sqlStatement VARCHAR(4000) NULL
	, errorMessage VARCHAR(1000) NULL
	CONSTRAINT PK_AdaptiveIndexDefrag_log PRIMARY KEY CLUSTERED (indexDefrag_id));

CREATE INDEX IX_tbl_AdaptiveIndexDefrag_log ON [dbo].[tbl_AdaptiveIndexDefrag_log] ([dbID], [objectID], [indexName], [dateTimeEnd]);
CREATE INDEX IX_tbl_AdaptiveIndexDefrag_log_dateTimeEnd ON [dbo].[tbl_AdaptiveIndexDefrag_log] ([indexDefrag_id], [dateTimeEnd]);
RAISERROR('tbl_AdaptiveIndexDefrag_log table created', 0, 42) WITH NOWAIT;
	
IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_Analysis_log
	(analysis_id int identity(1,1) NOT NULL
	, [Operation] NCHAR(5)
	, dbID int NOT NULL
	, dbName NVARCHAR(128) NOT NULL
	, objectID int NOT NULL
	, objectName NVARCHAR(256) NULL
	, index_or_stat_ID int NOT NULL
	, partitionNumber smallint
	, dateTimeStart DATETIME NOT NULL
	, dateTimeEnd DATETIME NULL
	, durationSeconds int NULL
	, errorMessage VARCHAR(1000) NULL
	CONSTRAINT PK_AdaptiveIndexDefrag_Analysis_log PRIMARY KEY CLUSTERED (analysis_id));
	
CREATE INDEX IX_tbl_AdaptiveIndexDefrag_Analysis_log_dateTimeEnd ON [dbo].[tbl_AdaptiveIndexDefrag_Analysis_log] ([analysis_id], [dateTimeEnd]);
RAISERROR('tbl_AdaptiveIndexDefrag_Analysis_log table created', 0, 42) WITH NOWAIT;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_Exceptions
	(dbID int NOT NULL
	, objectID int NOT NULL
	, indexID int NOT NULL	
	, dbName NVARCHAR(128) NOT NULL
	, objectName NVARCHAR(256) NOT NULL
	, indexName NVARCHAR(256) NOT NULL
	, exclusionMask int NOT NULL
		/* Same as in msdb.dbo.sysschedules:
		1=Sunday, 2=Monday, 4=Tuesday, 8=Wednesday, 16=Thursday, 32=Friday, 64=Saturday, 0=AllWeek, -1=Never
		For multiple days, sum the corresponding values*/	
	CONSTRAINT PK_AdaptiveIndexDefrag_Exceptions PRIMARY KEY CLUSTERED (dbID, objectID, indexID));
RAISERROR('tbl_AdaptiveIndexDefrag_Exceptions table created', 0, 42) WITH NOWAIT;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_Working
	(dbID int
	, objectID int
	, indexID int
	, partitionNumber smallint
	, dbName NVARCHAR(128)
	, schemaName NVARCHAR(128) NULL
	, objectName NVARCHAR(256) NULL
	, indexName NVARCHAR(256) NULL
	, fragmentation float
	, page_count int
	, is_primary_key bit
	, fill_factor int
	, is_disabled bit
	, is_padded bit
	, is_hypothetical bit
	, has_filter bit
	, allow_page_locks bit
	, compression_type NVARCHAR(60) NULL -- 0 = NONE; 1 = ROW; 2 = PAGE; 3 = COLUMNSTORE; 4 = COLUMNSTORE_ARCHIVE
	, range_scan_count bigint NULL
	, record_count bigint
	, [type] tinyint -- 0 = Heap; 1 = Clustered; 2 = Nonclustered; 3 = XML; 4 = Spatial; 5 = Clustered columnstore; 6 = Nonclustered columnstore; 7 = Nonclustered hash
	, scanDate DATETIME
	, defragDate DATETIME NULL
	, printStatus bit DEFAULT(0) -- Used for loop control when printing the SQL commands.
	, exclusionMask int DEFAULT(0)
	CONSTRAINT PK_AdaptiveIndexDefrag_Working PRIMARY KEY CLUSTERED(dbID, objectID, indexID, partitionNumber));

RAISERROR('tbl_AdaptiveIndexDefrag_Working table created', 0, 42) WITH NOWAIT;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	(dbID int
	, objectID int
	, statsID int
	, partitionNumber smallint
	, dbName NVARCHAR(128)
	, schemaName NVARCHAR(128) NULL
	, objectName NVARCHAR(256) NULL
	, statsName NVARCHAR(256)
	, [no_recompute] bit
	, [is_incremental] bit
	, scanDate DATETIME
	, updateDate DATETIME NULL
	, printStatus bit DEFAULT(0) -- Used for loop control when printing the SQL commands.
	CONSTRAINT PK_AdaptiveIndexDefrag_Stats_Working PRIMARY KEY CLUSTERED(dbID, objectID, statsID, partitionNumber));

RAISERROR('tbl_AdaptiveIndexDefrag_Stats_Working table created', 0, 42) WITH NOWAIT;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_Stats_log
	(statsUpdate_id int identity(1,1) NOT NULL
	, dbID int NOT NULL
	, dbName NVARCHAR(128) NULL
	, objectID int NULL
	, objectName NVARCHAR(256) NULL
	, statsID int NOT NULL
	, statsName NVARCHAR(256) NULL
	, partitionNumber smallint
	, [rows] bigint
	, rows_sampled bigint
	, modification_counter bigint
	, [no_recompute] bit
	, dateTimeStart DATETIME NOT NULL
	, dateTimeEnd DATETIME NULL
	, durationSeconds int NULL
	, sqlStatement VARCHAR(4000) NULL
	, errorMessage VARCHAR(1000) NULL
	CONSTRAINT PK_AdaptiveIndexDefrag_Stats_log PRIMARY KEY CLUSTERED (statsUpdate_id));

CREATE INDEX IX_tbl_AdaptiveIndexDefrag_Stats_log ON [dbo].[tbl_AdaptiveIndexDefrag_Stats_log] ([dbID], [objectID], [statsName], [dateTimeEnd]);
	RAISERROR('tbl_AdaptiveIndexDefrag_Stats_log table created', 0, 42) WITH NOWAIT;

IF NOT EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus')
CREATE TABLE dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus
	(disable_id int identity(1,1) NOT NULL
	, dbID int NOT NULL	
	, objectID int NOT NULL	
	, indexID int NOT NULL		
	, [is_disabled] bit		
	, dateTimeChange DATETIME NOT NULL
	CONSTRAINT PK_AdaptiveIndexDefrag_IxDisableStatus PRIMARY KEY CLUSTERED (disable_id));

RAISERROR('tbl_AdaptiveIndexDefrag_IxDisableStatus table created', 0, 42) WITH NOWAIT;

IF @deploymode = 0
BEGIN
	RAISERROR('Copying old data...', 0, 42) WITH NOWAIT;

	BEGIN TRY
		IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log_old')
		INSERT INTO dbo.tbl_AdaptiveIndexDefrag_log ([dbID],[dbName],[objectID],[objectName]
			,[indexID],[indexName],[partitionNumber],[fragmentation],[page_count]
			,[range_scan_count],[fill_factor],[dateTimeStart],[dateTimeEnd]
			,[durationSeconds],[sqlStatement],[errorMessage])
		SELECT [dbID],[dbName],[objectID],[objectName],[indexID]
			,[indexName],[partitionNumber],[fragmentation],[page_count]
			,[range_scan_count],[fill_factor],[dateTimeStart],[dateTimeEnd]
			,[durationSeconds],[sqlStatement],[errorMessage]
		FROM dbo.tbl_AdaptiveIndexDefrag_log_old;
		
		IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log_old')
		INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Analysis_log ([Operation],[dbID],[dbName],[objectID],[objectName]
			,[index_or_stat_ID],[partitionNumber],[dateTimeStart],[dateTimeEnd]
			,[durationSeconds],[errorMessage])
		SELECT [Operation],[dbID],[dbName],[objectID],[objectName],[index_or_stat_ID]
			,[partitionNumber],[dateTimeStart],[dateTimeEnd]
			,[durationSeconds],[errorMessage]
		FROM dbo.tbl_AdaptiveIndexDefrag_Analysis_log_old;
		
		IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old')
		BEGIN
			IF (SELECT COUNT(sc.column_id) FROM sys.tables st INNER JOIN sys.columns sc ON st.[object_id] = sc.[object_id] WHERE (sc.[name] = 'partitionNumber' OR sc.[name] = 'rows' OR sc.[name] = 'rows_sampled' OR sc.[name] = 'modification_counter') AND st.[name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old') = 4
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log ([dbID],[dbName],[objectID],[objectName],[statsID],[statsName],[partitionNumber],[rows],rows_sampled,modification_counter,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage])
SELECT [dbID],[dbName],[objectID],[objectName],[statsID],[statsName],[partitionNumber],[rows],rows_sampled,modification_counter,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log_old;')
			END
			ELSE IF (SELECT COUNT(sc.column_id) FROM sys.tables st INNER JOIN sys.columns sc ON st.[object_id] = sc.[object_id] WHERE sc.[name] = 'partitionNumber' AND st.[name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old') = 1
				AND (SELECT COUNT(sc.column_id) FROM sys.tables st INNER JOIN sys.columns sc ON st.[object_id] = sc.[object_id] WHERE (sc.[name] = 'rows' OR sc.[name] = 'rows_sampled' OR sc.[name] = 'modification_counter') AND st.[name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old') = 0
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log ([dbID],[dbName],[objectID],[objectName],[statsID],[statsName],[partitionNumber],[rows],rows_sampled,modification_counter,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage])
SELECT [dbID],[dbName],[objectID],[objectName],[statsID],[statsName],[partitionNumber],-1,-1,-1,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log_old;')
			END
			ELSE 
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log ([dbID],[dbName],[objectID],[objectName],[statsID],[statsName],[partitionNumber],[rows],rows_sampled,modification_counter,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage])
SELECT [dbID],[dbName],[objectID],[objectName],[statsID],[statsName],1,-1,-1,-1,[no_recompute],[dateTimeStart],[dateTimeEnd],[durationSeconds],[sqlStatement],[errorMessage]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log_old;')
			END
		END

		IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions_old')
		INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Exceptions ([dbID],[objectID],[indexID],[dbName],[objectName],[indexName],[exclusionMask])
		SELECT [dbID],[objectID],[indexID],[dbName],[objectName],[indexName],[exclusionMask]
		FROM dbo.tbl_AdaptiveIndexDefrag_Exceptions_old;
		
		IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working_old')
		BEGIN
			IF EXISTS (SELECT sc.column_id FROM sys.tables st INNER JOIN sys.columns sc ON st.[object_id] = sc.[object_id] WHERE (sc.[name] = 'compression_type') AND st.[name] = 'tbl_AdaptiveIndexDefrag_Working_old')
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Working ([dbID],[objectID],[indexID],[partitionNumber],[dbName],[schemaName],[objectName],[indexName],[fragmentation],[page_count],[fill_factor],[is_disabled],[is_padded],[is_hypothetical],[has_filter],[allow_page_locks],[compression_type],[range_scan_count],[record_count],[type],[scanDate],[defragDate],[printStatus],[exclusionMask])
SELECT [dbID],[objectID],[indexID],[partitionNumber],[dbName],[schemaName],[objectName],[indexName],[fragmentation],[page_count],[fill_factor],[is_disabled],[is_padded],[is_hypothetical],[has_filter],[allow_page_locks],[compression_type],[range_scan_count],[record_count],[type],[scanDate],[defragDate],[printStatus],[exclusionMask]
FROM dbo.tbl_AdaptiveIndexDefrag_Working_old;')
			END
			ELSE
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Working ([dbID],[objectID],[indexID],[partitionNumber],[dbName],[schemaName],[objectName],[indexName],[fragmentation],[page_count],[fill_factor],[is_disabled],[is_padded],[is_hypothetical],[has_filter],[allow_page_locks],[range_scan_count],[record_count],[type],[scanDate],[defragDate],[printStatus],[exclusionMask])
SELECT [dbID],[objectID],[indexID],[partitionNumber],[dbName],[schemaName],[objectName],[indexName],[fragmentation],[page_count],[fill_factor],[is_disabled],[is_padded],[is_hypothetical],[has_filter],[allow_page_locks],[range_scan_count],[record_count],[type],[scanDate],[defragDate],[printStatus],[exclusionMask]
FROM dbo.tbl_AdaptiveIndexDefrag_Working_old;')
			END
		END
		
		IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working_old')
		BEGIN
			IF EXISTS (SELECT sc.column_id FROM sys.tables st INNER JOIN sys.columns sc ON st.[object_id] = sc.[object_id] WHERE (sc.[name] = 'partitionNumber' OR sc.[name] = 'is_incremental') AND st.[name] = 'tbl_AdaptiveIndexDefrag_Stats_Working_old')
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_Working ([dbID],[objectID],[statsID],[dbName],[schemaName],[objectName],[statsName],[partitionNumber],[no_recompute],[is_incremental],[scanDate],[updateDate],[printStatus])
SELECT [dbID],[objectID],[statsID],[dbName],[schemaName],[objectName],[statsName],[partitionNumber],[no_recompute],[is_incremental],[scanDate],[updateDate],[printStatus]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working_old;')
			END
			ELSE
			BEGIN
				EXEC ('INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_Working ([dbID],[objectID],[statsID],[dbName],[schemaName],[objectName],[statsName],[partitionNumber],[no_recompute],[is_incremental],[scanDate],[updateDate],[printStatus])
SELECT [dbID],[objectID],[statsID],[dbName],[schemaName],[objectName],[statsName],1,[no_recompute],0,[scanDate],[updateDate],[printStatus]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working_old;')
			END
		END

		IF EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus') AND EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus_old')
		INSERT INTO dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus ([dbID],[objectID],[indexID],[is_disabled],dateTimeChange)
		SELECT [dbID],[objectID],[indexID],[is_disabled],dateTimeChange
		FROM dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus_old;
	END TRY
	BEGIN CATCH					
		RAISERROR('Could not copy old data back. Check for any previous errors.', 15, 42) WITH NOWAIT;
		RETURN
	END CATCH

	RAISERROR('Done copying old data...', 0, 42) WITH NOWAIT;
	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_log_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_log)
		DROP TABLE tbl_AdaptiveIndexDefrag_log_old
	END;

	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Analysis_log_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Analysis_log)
		DROP TABLE tbl_AdaptiveIndexDefrag_Analysis_log_old
	END;	
	
	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log)
		DROP TABLE tbl_AdaptiveIndexDefrag_Stats_log_old
	END;

	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Exceptions_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Exceptions)
		DROP TABLE tbl_AdaptiveIndexDefrag_Exceptions_old
	END;

	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working)
		DROP TABLE tbl_AdaptiveIndexDefrag_Working_old
	END;

	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working)
		DROP TABLE tbl_AdaptiveIndexDefrag_Stats_Working_old
	END;

	IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus_old')
	BEGIN
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus_old) = (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus)
		DROP TABLE tbl_AdaptiveIndexDefrag_IxDisableStatus_old
	END;
		IF EXISTS (SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_Working_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_log_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Analysis_log_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Stats_log_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Exceptions_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_Working_old')
		OR EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tbl_AdaptiveIndexDefrag_IxDisableStatus_old')
	BEGIN
		RAISERROR('Data mismatch. Keeping some or all old tables as <tablename_old>.', 0, 42) WITH NOWAIT;
	END
	ELSE
	BEGIN
		RAISERROR('Removed old tables...', 0, 42) WITH NOWAIT;
	END
END;
GO

------------------------------------------------------------------------------------------------------------------------------		
		
IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_AdaptiveIndexDefrag'), N'IsProcedure') = 1
BEGIN
	DROP PROCEDURE dbo.usp_AdaptiveIndexDefrag;
	PRINT 'Procedure usp_AdaptiveIndexDefrag dropped';
END;
GO

CREATE PROCEDURE dbo.usp_AdaptiveIndexDefrag
	@Exec_Print bit = 1		
		/* 1 = execute commands; 0 = print commands only */
	, @printCmds bit = 0		
		/* 1 = print commands; 0 = do not print commands */	
	, @outputResults bit = 0		
		/* 1 = output fragmentation information;
		0 = do not output */
	, @debugMode bit = 0		
		/* display some useful comments to help determine if/where issues occur
			1 = display debug comments;
			0 = do not display debug comments*/	
	, @timeLimit int = 480 /* defaults to 8 hours */		
		/* Optional time limitation; expressed in minutes */	
	, @dbScope NVARCHAR(256) = NULL
		/* Option to specify a database name; NULL will return all */	
	, @tblName NVARCHAR(1000) = NULL -- schema.table_name		
		/* Option to specify a table name; NULL will return all */	
	, @defragOrderColumn NVARCHAR(20) = 'range_scan_count'		
		/* Valid options are: range_scan_count, fragmentation, page_count */	
	, @defragSortOrder NVARCHAR(4) = 'DESC'		
		/* Valid options are: ASC, DESC */	
	, @forceRescan bit = 0		
		/* Whether to force a rescan of indexes into the tbl_AdaptiveIndexDefrag_Working table or not;
		1 = force, 0 = use existing scan when available, used to continue where previous run left off */	
	, @defragDelay CHAR(8) = '00:00:05'		
		/* time to wait between defrag commands */	
	, @ixtypeOption	bit = NULL
		/* NULL = all indexes will be defragmented; 1 = only Clustered indexes will be defragmented; 0 = only Non-Clustered indexes will be defragmented (includes XML and Spatial); */
	, @minFragmentation float = 5.0		
		/* in percent, will not defrag if fragmentation is less than specified */	
	, @rebuildThreshold float = 30.0		
		/* in percent, greater than @rebuildThreshold will result in rebuild instead of reorg */
	, @rebuildThreshold_cs float = 10.0		
		/* in percent, greater than @rebuildThreshold_cs will result in rebuild the columnstore index */
	, @minPageCount int = 8		
		/* Recommended is defrag when index is at least > 1 extent (8 pages) */	
	, @maxPageCount int = NULL
		/* NULL = no limit */	
	, @fillfactor bit = 1
		/* 1 = original from when the index was created or last defraged;
		0 = default fillfactor */
	, @scanMode VARCHAR(10) = N'LIMITED'
		/* Options are LIMITED, SAMPLED, and DETAILED */
	, @onlineRebuild bit = 0
		/* 1 = online rebuild; 0 = offline rebuild; only in Enterprise Edition */
	, @resumableRebuild bit = 0
		/* 1 = resumable rebuild; 0 = normal rebuild */		
	, @sortInTempDB bit = 0	
		/* 1 = perform sort operation in TempDB; 0 = perform sort operation in the indexes database */
	, @maxDopRestriction tinyint = NULL
		/* Option to restrict the number of processors for both index and statistics operations; only in Enterprise Edition */
	, @updateStats bit = 1
		/* 1 = updates stats when reorganizing; 0 = does not update stats when reorganizing */
	, @updateStatsWhere bit = 0
		/* 1 = updates only index related stats; 0 = updates all stats in table */
	, @statsSample NVARCHAR(8) = NULL
		/* Valid options are: NULL, <percentage>, FULLSCAN, and RESAMPLE */
	, @persistStatsSample bit = NULL
		/* 1 = turns ON fixed sampling rate; 0 = turns OFF fixed sampling rate; NULL = do nothing */
	, @statsThreshold float	= NULL
		/* Valid options are: NULL to use default stats sample method (same as TF2371), float number greater or equal to 0.001 and less than 100 to use custom stats sample */
	, @statsMinRows bigint = NULL
		/* Valid options are: NULL , integer number that sets the min number of rows a table has to have to be considered for @statsThreshold use */
	, @ix_statsnorecompute bit = 0
		/* 1 = STATISTICS_NORECOMPUTE on; 0 = default which is with STATISTICS_NORECOMPUTE off */
	, @statsIncremental	bit = NULL
		/* NULL = Keep server setting; 1 = Enable auto create statistics with Incremental; 0 = Disable auto create statistics with Incremental */
	, @dealMaxPartition bit = 0	
		/* 0 = only right-most partition; 1 = exclude right-most populated partition; NULL = do not exclude; see notes for caveats; only in Enterprise Edition */
	, @dealLOB bit = 0
		/* 0 = compact LOBs when reorganizing (default behavior); 1 = does not compact LOBs when reorganizing */
	, @ignoreDropObj bit = 0
		/* 0 = includes errors about objects that have been dropped since the defrag cycle began (default behavior);
		1 = for error reporting purposes, ignores the fact that objects have been dropped since the defrag cycle began */
	, @disableNCIX bit = 0
		/* 0 = does NOT disable non-clustered indexes prior to a rebuild;
		1 = disables non-clustered indexes prior to a rebuild, if the database is not being replicated (space saving feature) */
	, @offlinelocktimeout int = -1
		/* -1 = (default) indicates no time-out period; Any other positive integer sets the number of milliseconds that will pass before Microsoft SQL Server returns a locking error */
	, @onlinelocktimeout int = 5
		/* 5 = (default) indicates a time-out period for locks to wait at low priority, expressed in minutes; this is valid from SQL Server 2014 onwards */
	, @abortAfterwait bit = 1
		/* NULL = (default) After lock timeout occurs, continue waiting for the lock with normal (regular) priority;
		0 = Kill all user transactions that block the online index rebuild DDL operation so that the operation can continue.
		1 = Exit the online index rebuild DDL operation currently being executed without taking any action.*/
	, @dealROWG	bit = 0
		/* 0 = (default) compress closed rowgroups on columnstore.
		1 = compress all rowgroups on columnstore, and not just closed ones.*/
	, @getBlobfrag bit = 0
		/* 0 = (default) exclude blobs from fragmentation scan.
		1 = include blobs and off-row data when scanning for fragmentation.*/
	, @dataCompression NVARCHAR(4) = NULL
		/* NULL = (default) Keeps whatever compression setting exists for the object and partition; 
		NONE = Forces no compression (and removes compression if set);
		PAGE = Forces page compression;
		ROW = Forces row compression.*/
AS
/*
usp_AdaptiveIndexDefrag.sql - pedro.lopes@microsoft.com (http://aka.ms/AID)

v1 inspired by Michelle Ufford (http://sqlfool.com)

PURPOSE: Intelligent defrag on one or more indexes and statistics update for one or more databases.

DISCLAIMER:
This code is not supported under any Microsoft standard support program or service.
This code and information are provided "AS IS" without warranty of any kind, either expressed or implied.
The entire risk arising out of the use or performance of the script and documentation remains with you.
Furthermore, Microsoft, the author or "Blog do Ezequiel" team shall not be liable for any damages you may sustain by using this information, whether direct,
indirect, special, incidental or consequential, including, without limitation, damages for loss of business profits, business interruption, loss of business information
or other pecuniary loss even if it has been advised of the possibility of such damages.
Read all the implementation and usage notes thoroughly.

CHANGE LOG:
See https://github.com/microsoft/tigertoolbox/blob/master/AdaptiveIndexDefrag/CHANGELOG.txt

IMPORTANT:
Execute in the database context of where you created the log and working tables.			
										
ALL parameters are optional. If not specified, the defaults for each parameter are used.	

@Exec_Print 		1 = execute the SQL code generated by this SP;
					0 = print commands only
					
@printCmds			1 = print commands to screen;
					0 = do not print commands

@outputResults		1 = output fragmentation information after run completes;
					0 = do not output fragmentation information
					
@debugMode 			1 = display debug comments;
					0 = do not display debug comments
					
@timeLimit 			Limits how much time can be spent performing index defrags; expressed in minutes.
					NOTE: The time limit is checked BEFORE an index defrag begins, thus a long index defrag can exceed the time limit.

@dbScope 			Specify specific database name to defrag; if not specified, all non-system databases plus msdb and model will be defragmented.

@tblName 			Specify if you only want to defrag indexes for a specific table, format = schema.table_name; if not specified, all tables will be defragmented.

@defragOrderColumn 	Defines how to prioritize the order of defrags. Only used if @Exec_Print = 1.
					range_scan_count = count of range and table scans on the index; this is what can benefit the most from defragmentation;
					fragmentation = amount of fragmentation in the index;
					page_count = number of pages in the index; bigger indexes can take longer to defrag and thus generate more contention; may want to start with these;

@defragSortOrder 	The sort order of the ORDER BY clause on the above query on how to prioritize the order of defrags.
					ASC (ascending)
					DESC (descending) is the default.

@forceRescan 		Action on index rescan. If = 0, a rescan will not occur until all indexes have been defragmented. This can span multiple executions.
					1 = force a rescan
					0 = use previous scan, if there are indexes left to defrag

@defragDelay 		Time to wait between defrag commands; gives the server a breathe between runs
					
@ixtypeOption		NULL = all indexes will be defragmented;
					1 = only Clustered indexes will be defragmented;
					0 = only Non-Clustered indexes will be defragmented (includes XML and Spatial Indexes);

@minFragmentation 	Defaults to 5%, will not defrag if fragmentation is less.
					Refer to http://docs.microsoft.com/sql/relational-databases/indexes/reorganize-and-rebuild-indexes

@rebuildThreshold 	Defaults to 30%. greater than 30% will result in rebuild instead of reorganize.
					Refer to http://docs.microsoft.com/sql/relational-databases/indexes/reorganize-and-rebuild-indexes
										
@rebuildThreshold_csDefaults to 10%. Greater than 10% will result in columnstore rebuild.
					Refer to http://docs.microsoft.com/sql/relational-databases/sql-server-index-design-guide
										
@minPageCount 		Specifies how many pages must exist in an index in order to be considered for a defrag. Default to an extent. 
					Refer to http://docs.microsoft.com/sql/relational-databases/indexes/reorganize-and-rebuild-indexes
					NOTE: The @minPageCount will restrict the indexes that are stored in tbl_AdaptiveIndexDefrag_Working table and can render other options inoperative.

@maxPageCount 		Specifies the maximum number of pages that can exist in an index and still be considered for a defrag.
					Useful for scheduling small indexes during business hours and large indexes for non-business hours.
					NOTE: The @maxPageCount will restrict the indexes selective for defrag; 								

@fillfactor 		1 = original from when the index was created or last defragmented;
					0 = default fill factor

@scanMode 			Specifies which scan mode to use to determine fragmentation levels. Options are:
					LIMITED = the fastest mode and scans the smallest number of pages.
							For an index, only the parent-level pages of the B-tree (that is, the pages above the leaf level) are scanned.
							For a heap, only the associated PFS and IAM pages are examined; the data pages of the heap are not scanned.
							Recommended for most cases.
					SAMPLED = returns statistics based on a 1 percent sample of all the pages in the index or heap.
							If the index or heap has fewer than 10,000 pages, DETAILED mode is used instead of SAMPLED.
					DETAILED = scans all pages and returns all statistics. Can cause performance issues.

@onlineRebuild 		1 = online rebuild if possible; only in Enterprise Edition;
					0 = offline rebuild

@sortInTempDB 		When 1, the sort results are stored in TempDB. When 0, the sort results are stored in the filegroup or partition scheme in which the resulting index is stored.
					If a sort operation is not required, or if the sort can be performed in memory, SORT_IN_TEMPDB is ignored.
					Enabling this option can result in faster defrags and prevent database file size inflation.	Just have monitor TempDB closely.
					Refer to http://docs.microsoft.com/sql/relational-databases/indexes/sort-in-tempdb-option-for-indexes and http://docs.microsoft.com/sql/relational-databases/indexes/disk-space-requirements-for-index-ddl-operations and http://docs.microsoft.com/sql/relational-databases/indexes/disk-space-requirements-for-index-ddl-operations
					1 = perform sort operation in TempDB
					0 = perform sort operation in the indexes database

@maxDopRestriction 	Option to specify a processor limit for index rebuilds and statistics updates. If not specified, defrag operations will use the system MaxDOP setting, up to a limit of 8.
					
@updateStats		1 = updates stats when reorganizing;
					0 = does not update stats when reorganizing	
					
@updateStatsWhere	Update statistics within certain thresholds. Refer to http://docs.microsoft.com/sql/relational-databases/statistics/statistics
					1 = updates only index related stats;
					0 = updates all stats in entire table
										
@statsSample		NULL = perform a sample scan on the target table or indexed view. The database engine automatically computes the required sample size;
					<percentage> = perform a fixed percentage scan on the target table or indexed view. Valid values are integers between 1 and 100;
					FULLSCAN = all rows in table or view should be read to gather the statistics;
					RESAMPLE = statistics will be gathered using an inherited sampling ratio for all existing statistics including indexes
					
@persistStatsSample Persist a specific statistics sampling rate (depends on version) if <percentage> or FULLSCAN needs to be used in @statsSample
					NULL = do nothing;
					1 = turns ON fixed sampling rate;
					0 = turns OFF fixed sampling rate
					
@statsThreshold		Custom threshold of changes needed to trigger update statistics, overriding default handling;
					NULL = assume default handling which is similar to TF2371;
					A float number greater or equal to 0.001 and less than 100 to use custom stats sample
					
@statsMinRows 		Sets the min number of rows a table has to have to be considered for @statsThreshold use;
					NULL = use @statsThreshold (if set) for any size table;
					An integer number that sets the min number of rows a table has to have to be considered for @statsThreshold use

@ix_statsnorecompute	1 = STATISTICS_NORECOMPUTE on will disable the auto update statistics.
					If you are dealing with stats update with a custom job (or even with this code by updating statistics), you may use this option;
					0 = default which is with STATISTICS_NORECOMPUTE off
					
@statsIncremental	When Incremental is ON, the statistics created are per partition statistics. 
					When OFF, the statistics tree is dropped and SQL Server re-computes the statistics. This setting overrides the database level INCREMENTAL property. 
					Refer to http://docs.microsoft.com/sql/relational-databases/statistics/statistics
					NULL = Keep server setting;
					1 = Enable auto create statistics with Incremental
					0 = Disable auto create statistics with Incremental

@dealMaxPartition 	If an index is partitioned, this option specifies whether to exclude the right-most populated partition, or act only on that same partition, excluding all others.
					Typically, this is the partition that is currently being written to in a sliding-window scenario.
					Enabling this feature may reduce contention. This may not be applicable in other types of partitioning scenarios.
					Non-partitioned indexes are unaffected by this option. Only in Enterprise Edition.
					1 = exclude right-most populated partition										
					0 = only right-most populated partition (remember to verify @minPageCount, if partition is smaller than @minPageCount, it won't be considered)										
					NULL = do not exclude any partitions
					
@dealLOB			Specifies that all pages that contain large object (LOB) data are compacted. The LOB data types are image, text, ntext, varchar(max), nvarchar(max), varbinary(max), and xml.
					Compacting this data can improve disk space use.
					Reorganizing a specified clustered index compacts all LOB columns that are contained in the clustered index.
					Reorganizing a non-clustered index compacts all LOB columns that are nonkey (included) columns in the index.
					0 = compact LOBs when reorganizing (default behavior);
					1 = does not compact LOBs when reorganizing	

@ignoreDropObj		If a table or index is dropped after the defrag cycle has begun, you can choose to ignore those errors in the overall outcome,
					thus not showing a job as failed if the only errors present refer to dropped database objects.	
					0 = includes errors about objects that have been dropped since the defrag cycle began (default behavior);
					1 = for error reporting purposes, ignores the fact that objects have been dropped since the defrag cycle began				

@disableNCIX		If disk space is limited, it may be helpful to disable the non-clustered index before rebuilding it;
					When a non-clustered index is not disabled, the rebuild operation requires enough temporary disk space to store both the old and new index;
					However, by disabling and rebuilding a non-clustered index in separate transactions, the disk space made available by disabling the index can be reused by the subsequent rebuild or any other operation;
					No additional space is required except for temporary disk space for sorting; this is typically 20 percent of the index size;
					Does not disable indexes on partitioned tables when defragging a subset of existing partitions;
					Keeps track of whatever indexes were disabled by the defrag cycle. In case the defrag is cancelled, it will account for these disabled indexes in the next run.
					0 = does NOT disable non-clustered indexes prior to a rebuild (default behavior);
					1 = disables non-clustered indexes prior to a rebuild (space saving feature)

@offlinelocktimeout	As set in SET LOCK_TIMEOUT option
					Refer to http://docs.microsoft.com/sql/t-sql/statements/set-lock-timeout-transact-sql
					-1 = (default) indicates no time-out period
					Any other positive integer = sets the number of milliseconds that will pass before Microsoft SQL Server returns a locking error

@onlinelocktimeout	Indicates a time-out period for locks to wait at low priority, expressed in minutes; this is valid from SQL Server 2014 onwards

@abortAfterwait 	If the online low priority lock timeout occurs, this will set the action to perform afterwards.
					NULL = (default) After lock timeout occurs, continue waiting for the lock with normal (regular) priority;
					1 = Exit the online index rebuild DDL operation currently being executed without taking any action;
					2 = Kill all user transactions that block the online index rebuild DDL operation so that the operation can continue.

@dealROWG			Set Columnstore reorg option to compress all rowgroups, and not just closed ones		
					0 = (default) compress closed rowgroups on columnstore.
					1 = compress all rowgroups on columnstore, and not just closed ones.
					
@getBlobfrag		Indicates whether to exclude or include blobs from fragmentation scan.
					0 = (default) exclude blobs from fragmentation scan.
					1 = include blobs and off-row data when scanning for fragmentation.
					
@dataCompression 	Sets specific compression options for all indexes. 
					NULL = (default) Does not use the DATA_COMPRESSION keyword in index rebuild, keeping whatever compression setting exists.
					NONE = Index or specified partitions are not compressed.
					PAGE = Use page compression.
					ROW = Use row compression.
				
-------------------------------------------------------		
Usage:
		EXEC dbo.usp_AdaptiveIndexDefrag
	or customize it like the example:

	EXEC dbo.usp_AdaptiveIndexDefrag		
		@Exec_Print = 0	
		, @printCmds = 1
		, @updateStats = 1
		, @updateStatsWhere = 1	
		, @debugMode = 1	
		, @outputResults = 1
		, @dbScope = 'AdventureWorks2008R2'
		, @forceRescan = 1	
		, @maxDopRestriction = 2	
		, @minPageCount = 8	
		, @maxPageCount = NULL	
		, @minFragmentation = 1	
		, @rebuildThreshold = 1
		, @rebuildThreshold_cs = 1
		, @defragDelay = '00:00:05'	
		, @defragOrderColumn = 'range_scan_count'	
		, @dealMaxPartition = NULL
		, @disableNCIX = 1
		, @offlinelocktimeout = 180;
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET DATEFORMAT ymd;
SET DEADLOCK_PRIORITY -10;
-- Required so it can update stats on Indexed Views and Filtered Indexes
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

/* Find sql server version and edition info */
DECLARE @sqlmajorver int, @sqlminorver int, @sqlbuild int, @engineedition int;
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff);
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);
SELECT @engineedition = CONVERT(int, SERVERPROPERTY('EngineEdition'));

BEGIN
	BEGIN TRY		
		/* Validating and normalizing options... */	
		
		IF @debugMode = 1
		RAISERROR('Validating options...', 0, 42) WITH NOWAIT;
		
		IF @minFragmentation IS NULL OR @minFragmentation NOT BETWEEN 0.00 AND 100.0
		SET @minFragmentation = 5.0;

		IF @rebuildThreshold IS NULL OR @rebuildThreshold NOT BETWEEN 0.00 AND 100.0
		SET @rebuildThreshold = 30.0;
				
		IF @rebuildThreshold_cs IS NULL OR @rebuildThreshold_cs NOT BETWEEN 0.00 AND 100.0
		SET @rebuildThreshold_cs = 10.0;
		
		IF @statsThreshold IS NOT NULL AND @statsThreshold NOT BETWEEN 0.001 AND 100.0
		SET @statsThreshold = NULL;

		IF @timeLimit IS NULL
		SET @timeLimit = 480;
		
		IF @dataCompression IS NOT NULL AND UPPER(@dataCompression) NOT IN ('NONE','ROW','PAGE')
		SET @dataCompression = NULL;

		/* Validate if table name is fully qualified and database scope is set */
		IF @tblName IS NOT NULL AND @tblName NOT LIKE '%.%'
		BEGIN
			RAISERROR('WARNING: Table name must be fully qualified. Input format should be <schema>.<table_name>.', 15, 42) WITH NOWAIT;
			RETURN
		END;
			
		/* Validate if database scope is set when table name is also set */
		IF @tblName IS NOT NULL AND @dbScope IS NULL
		BEGIN
			RAISERROR('WARNING: A database scope must be set when using table names.', 15, 42) WITH NOWAIT;
			RETURN
		END;
		
		/* Validate if database scope exists */
		IF @dbScope IS NOT NULL AND LOWER(@dbScope) NOT IN (SELECT LOWER([name]) FROM sys.databases WHERE LOWER([name]) NOT IN ('master', 'tempdb', 'model', 'reportservertempdb','semanticsdb') AND is_distributor = 0)
		BEGIN
			RAISERROR('WARNING: The database in scope does not exist or is a system database.', 15, 42) WITH NOWAIT;
			RETURN
		END;

		/* Validate offline lock timeout settings */
		IF @offlinelocktimeout IS NULL OR ISNUMERIC(@offlinelocktimeout) <> 1
		BEGIN
			RAISERROR('WARNING: Offline lock timeout must be set to an integer number.', 15, 42) WITH NOWAIT;
			RETURN
		END;
		
		IF @offlinelocktimeout <> -1 AND @offlinelocktimeout IS NOT NULL
		SET @offlinelocktimeout = ABS(@offlinelocktimeout)

		/* Validate online lock timeout settings */
		IF @onlinelocktimeout IS NULL OR ISNUMERIC(@onlinelocktimeout) <> 1
		BEGIN
			RAISERROR('WARNING: Online lock timeout must be set to an integer number.', 15, 42) WITH NOWAIT;
			RETURN
		END;
		
		IF @onlinelocktimeout <> 5 AND @onlinelocktimeout IS NOT NULL
		SET @onlinelocktimeout = ABS(@onlinelocktimeout)

		/* Validate online lock timeout wait action settings */
		IF @abortAfterwait IS NOT NULL AND @abortAfterwait NOT IN (0,1)
		BEGIN
			RAISERROR('WARNING: Online lock timeout action is invalid.', 15, 42) WITH NOWAIT;
			RETURN
		END;
		
		/* Validate amount of breather time to give between operations*/
		IF @defragDelay NOT LIKE '00:[0-5][0-9]:[0-5][0-9]'
		BEGIN
			SET @defragDelay = '00:00:05';
			RAISERROR('Defrag delay input not valid. Defaulting to 5s.', 0, 42) WITH NOWAIT;
		END;

		IF @defragOrderColumn IS NULL OR LOWER(@defragOrderColumn) NOT IN ('range_scan_count', 'fragmentation', 'page_count')
		BEGIN
			SET @defragOrderColumn = 'range_scan_count';
			RAISERROR('Defrag order input not valid. Defaulting to range_scan_count.', 0, 42) WITH NOWAIT;
		END;

		IF @defragSortOrder IS NULL	OR UPPER(@defragSortOrder) NOT IN ('ASC', 'DESC')
		SET @defragSortOrder = 'DESC';

		IF UPPER(@scanMode) NOT IN ('LIMITED', 'SAMPLED', 'DETAILED')
		BEGIN
			SET @scanMode = 'LIMITED';
			RAISERROR('Index scan mode input not valid. Defaulting to LIMITED.', 0, 42) WITH NOWAIT;
		END;
		
		IF @ixtypeOption IS NOT NULL AND @ixtypeOption NOT IN (0,1)
		SET @ixtypeOption = NULL;

		IF @statsSample	IS NOT NULL AND (ISNUMERIC(@statsSample) = 1 AND @statsSample NOT BETWEEN 1 AND 100)
			OR (ISNUMERIC(@statsSample) = 0 AND UPPER(@statsSample) NOT IN ('FULLSCAN', 'RESAMPLE'))
		SET @statsSample = NULL
		
		IF (@persistStatsSample IS NOT NULL AND @persistStatsSample NOT IN (0,1))
			OR (@sqlmajorver <> 13 OR (@sqlmajorver = 13 AND @sqlbuild < 4446))
		SET @persistStatsSample = NULL;

		/* Recognize if database in scope is a Always On secondary replica */
		IF @dbScope IS NOT NULL AND @sqlmajorver >= 11 AND @engineedition NOT IN (5, 6) -- Except SQL Database and SQL DW
		BEGIN
			DECLARE @sqlcmdAO NVARCHAR(3000), @paramsAO NVARCHAR(50), @DBinAG int
			SET @sqlcmdAO = 'IF LOWER(@dbScopeIN) IN (SELECT LOWER(DB_NAME(dr.database_id))
FROM sys.dm_hadr_database_replica_states dr
INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
INNER JOIN sys.databases d ON dr.database_id = d.database_id
WHERE rs.role = 2 -- Is Secondary
	AND dr.is_local = 1
	AND rs.is_local = 1)
BEGIN
	SET @DBinAG_OUT = 1
END
ELSE
BEGIN
	SET @DBinAG_OUT = 0
END'
			SET @paramsAO = N'@dbScopeIN NVARCHAR(256), @DBinAG_OUT int OUTPUT'
		
			EXECUTE sp_executesql @sqlcmdAO, @paramsAO, @dbScopeIN = @dbScope, @DBinAG_OUT = @DBinAG OUTPUT
		
			IF @DBinAG = 1
			BEGIN
				RAISERROR('WARNING: Cannot defrag database in scope because it is part of an Always On secondary replica.', 15, 42) WITH NOWAIT;
				RETURN
			END
		END
			
		/* Check if database scope has changed, if rescan is not being forced */
		IF @forceRescan = 0 AND @dbScope IS NOT NULL -- Specific scope was set
		BEGIN
			IF (SELECT COUNT(DISTINCT [dbID]) FROM dbo.tbl_AdaptiveIndexDefrag_Working) > 1
				OR QUOTENAME(LOWER(@dbScope)) NOT IN (SELECT DISTINCT LOWER([dbName]) FROM dbo.tbl_AdaptiveIndexDefrag_Working UNION SELECT DISTINCT LOWER(dbName) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working)
			BEGIN
				SET @forceRescan = 1
				RAISERROR('Scope has changed. Forcing rescan of single database in scope...', 0, 42) WITH NOWAIT;
			END;
		END;

		/* Recognize if we have indexes of the chosen type left to defrag or stats left to update;
			otherwise force rescan of database(s), if rescan is not being forced */
		IF @forceRescan = 0
			AND (NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL AND [type] = 1 AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0) AND @ixtypeOption = 1)
			AND (NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL AND [type] <> 1 AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0) AND @ixtypeOption = 0)
			AND (NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0 ) AND @ixtypeOption IS NULL)
			AND NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working AS idss WHERE idss.updateDate IS NULL AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0))
		BEGIN
			SET @forceRescan = 1
			RAISERROR('No indexes of the chosen type left to defrag nor statistics left to update. Forcing rescan...', 0, 42) WITH NOWAIT;
		END;
		
		/* Recognize if we missing information post-upgrade;
			if so force rescan of database(s) */
		IF @forceRescan = 0
			AND (EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working 
			WHERE (fill_factor IS NULL OR is_padded IS NULL OR compression_type IS NULL) AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0))		BEGIN
			SET @forceRescan = 1
			RAISERROR('Missing column information due to post-upgrade condition. Forcing rescan...', 0, 42) WITH NOWAIT;
		END;
		
		/* Check if any databases where dropped or created since last run, if rescan is not being forced */		
		IF @forceRescan = 0 AND @dbScope IS NULL
		BEGIN
			DECLARE @sqlcmd_CntSrc NVARCHAR(3000), @params_CntSrc NVARCHAR(50), @CountSrc int
			DECLARE @sqlcmd_CntTgt NVARCHAR(3000), @params_CntTgt NVARCHAR(50), @CountTgt int
			DECLARE @dbIDIX int, @hasIXs bit, @hasIXsCntsqlcmd NVARCHAR(3000), @hasIXsCntsqlcmdParams NVARCHAR(50)
			
			-- What is in working tables plus exceptions that still exist in server
			SET @sqlcmd_CntSrc = 'SELECT @CountSrc_OUT = COUNT(DISTINCT Working.[dbID]) FROM
(SELECT DISTINCT [dbID] FROM [' + DB_NAME() + '].dbo.tbl_AdaptiveIndexDefrag_Working
UNION
SELECT DISTINCT [dbID] FROM [' + DB_NAME() + '].dbo.tbl_AdaptiveIndexDefrag_Stats_Working
UNION
SELECT DISTINCT [dbID] FROM [' + DB_NAME() + '].dbo.tbl_AdaptiveIndexDefrag_Exceptions
WHERE [dbID] IN (SELECT DISTINCT database_id FROM sys.databases sd
	WHERE LOWER(sd.[name]) NOT IN (''master'', ''tempdb'', ''model'', ''reportservertempdb'',''semanticsdb'')
		AND [state] = 0 -- must be ONLINE
		AND is_read_only = 0 -- cannot be READ_ONLY
		AND is_distributor = 0)
) Working'
			SET @params_CntSrc = N'@CountSrc_OUT int OUTPUT'

			-- What exists in current instance, in ONLINE state and READ_WRITE			
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexFindInDatabaseList'))
			DROP TABLE #tblIndexFindInDatabaseList;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexFindInDatabaseList'))
			CREATE TABLE #tblIndexFindInDatabaseList	
			(	
				[dbID] int
				, hasIXs bit NOT NULL
				, scanStatus bit NULL
			);
			
			/* Retrieve the list of databases to loop, excluding Always On secondary replicas */	
			SET @sqlcmd_CntTgt = 'SELECT [database_id], 0, 0 -- not yet scanned
FROM sys.databases
WHERE LOWER([name]) = ISNULL(LOWER(@dbScopeIN), LOWER([name]))	
	AND LOWER([name]) NOT IN (''master'', ''tempdb'', ''model'', ''reportservertempdb'',''semanticsdb'') -- exclude system databases
	AND [state] = 0 -- must be ONLINE
	AND is_read_only = 0 -- cannot be READ_ONLY
	AND is_distributor = 0'
				
			IF @sqlmajorver >= 11 AND (SELECT @@VERSION) NOT LIKE 'Microsoft SQL Azure%' -- Except all local Always On secondary replicas
			BEGIN
				SET @sqlcmd_CntTgt = @sqlcmd_CntTgt + CHAR(10) + 'AND [database_id] NOT IN (SELECT dr.database_id FROM sys.dm_hadr_database_replica_states dr
INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
INNER JOIN sys.databases d ON dr.database_id = d.database_id
WHERE rs.role = 2 -- Is Secondary
	AND dr.is_local = 1
	AND rs.is_local = 1)'
			END

			SET @params_CntTgt = N'@dbScopeIN NVARCHAR(256)'
			
			INSERT INTO #tblIndexFindInDatabaseList	
			EXECUTE sp_executesql @sqlcmd_CntTgt, @params_CntTgt, @dbScopeIN = @dbScope

			WHILE (SELECT COUNT(*) FROM #tblIndexFindInDatabaseList WHERE scanStatus = 0) > 0
			BEGIN
				SELECT TOP 1 @dbIDIX = [dbID] FROM #tblIndexFindInDatabaseList WHERE scanStatus = 0;

				SET @hasIXsCntsqlcmd = 'IF EXISTS (SELECT TOP 1 [index_id] from [' + DB_NAME(@dbIDIX) + '].sys.indexes AS si
INNER JOIN [' + DB_NAME(@dbIDIX) + '].sys.objects so ON si.object_id = so.object_id
WHERE so.is_ms_shipped = 0 AND [index_id] > 0 AND si.is_hypothetical = 0
	AND si.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + DB_NAME(@dbIDIX) + '].sys.internal_tables AS sit))
OR
EXISTS (SELECT TOP 1 [stats_id] from [' + DB_NAME(@dbIDIX) + '].sys.stats AS ss
INNER JOIN [' + DB_NAME(@dbIDIX) + '].sys.objects so ON ss.[object_id] = so.[object_id]
WHERE so.is_ms_shipped = 0
AND ss.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + DB_NAME(@dbIDIX) + '].sys.internal_tables AS sit))	
BEGIN SET @hasIXsOUT = 1 END ELSE BEGIN SET @hasIXsOUT = 0 END'
				SET @hasIXsCntsqlcmdParams = '@hasIXsOUT int OUTPUT'
				EXECUTE sp_executesql @hasIXsCntsqlcmd, @hasIXsCntsqlcmdParams, @hasIXsOUT = @hasIXs OUTPUT

				UPDATE #tblIndexFindInDatabaseList
				SET hasIXs = @hasIXs, scanStatus = 1
				WHERE [dbID] = @dbIDIX
			END

			EXECUTE sp_executesql @sqlcmd_CntSrc, @params_CntSrc, @CountSrc_OUT = @CountSrc OUTPUT
			SELECT @CountTgt = COUNT([dbID]) FROM #tblIndexFindInDatabaseList WHERE hasIXs = 1

			IF @CountSrc <> @CountTgt -- current databases in working lists <> number of eligible databases in instance
			BEGIN
				SET @forceRescan = 1
				RAISERROR('Scope has changed. Forcing rescan...', 0, 42) WITH NOWAIT;
			END
		END

		IF @debugMode = 1
		RAISERROR('Starting up...', 0, 42) WITH NOWAIT;

		/* Declare variables */	
		DECLARE @ver VARCHAR(10)
				, @objectID int
				, @dbID int		
				, @dbName NVARCHAR(256)
				, @indexID int
				, @operationFlag bit -- 0 = Reorganize, 1 = Rebuild
				, @partitionCount bigint
				, @schemaName NVARCHAR(128)
				, @objectName NVARCHAR(256)
				, @indexName NVARCHAR(256)
				, @statsobjectID int
				, @statsschemaName NVARCHAR(128)
				, @statsName NVARCHAR(256)
				, @statsobjectName NVARCHAR(256)
				, @stats_norecompute bit
				, @stats_isincremental bit
				, @is_primary_key bit
				, @fill_factor int									
				, @is_disabled bit
				, @is_padded bit
				, @has_filter bit
				, @partitionNumber smallint
				, @maxpartitionNumber smallint
				, @minpartitionNumber smallint		
				, @fragmentation float		
				, @pageCount int		
				, @sqlcommand NVARCHAR(4000)		
				, @sqlcommand2 NVARCHAR(600)
				, @sqldisablecommand NVARCHAR(600)
				, @sqlprecommand NVARCHAR(600)									
				, @rebuildcommand NVARCHAR(600)		
				, @dateTimeStart DATETIME		
				, @dateTimeEnd DATETIME		
				, @containsColumnstore int
				, @CStore_SQL NVARCHAR(4000)					
				, @CStore_SQL_Param NVARCHAR(1000)
				, @editionCheck bit		
				, @debugMessage VARCHAR(2048)		
				, @updateSQL NVARCHAR(4000)		
				, @partitionSQL NVARCHAR(4000)		
				, @partitionSQL_Param NVARCHAR(1000)
				, @rowmodctrSQL NVARCHAR(4000)
				, @rowmodctrSQL_Param NVARCHAR(1000)
				, @rowmodctr NUMERIC(10,3)
				, @record_count bigint
				, @range_scan_count bigint
				, @getStatSQL NVARCHAR(4000)
				, @getStatSQL_Param NVARCHAR(1000)
				, @statsID int
				, @surrogateStatsID int
				, @ixtype tinyint -- 0 = Heap; 1 = Clustered; 2 = Nonclustered; 3 = XML; 4 = Spatial
				, @containsLOB int
				, @LOB_SQL NVARCHAR(4000)					
				, @LOB_SQL_Param NVARCHAR(1000)		
				, @indexDefrag_id int
				, @statsUpdate_id int
				, @analysis_id int
				, @startDateTime DATETIME		
				, @endDateTime DATETIME		
				, @getIndexSQL NVARCHAR(4000)		
				, @getIndexSQL_Param NVARCHAR(4000)		
				, @allowPageLockSQL NVARCHAR(4000)		
				, @allowPageLockSQL_Param NVARCHAR(4000)		
				, @allowPageLocks bit		
				, @dealMaxPartitionSQL NVARCHAR(4000)
				, @cpucount smallint
				, @tblNameFQN NVARCHAR(1000)
				, @TableScanSQL NVARCHAR(2000)
				, @ixCntSource int
				, @ixCntTarget int
				, @ixCntsqlcmd NVARCHAR(1000)
				, @ixCntsqlcmdParams NVARCHAR(100)
				, @ColumnStoreGetIXSQL NVARCHAR(2000)
				, @ColumnStoreGetIXSQL_Param NVARCHAR(1000)
				, @rows bigint
				, @rows_sampled bigint
				, @AID_dbID int
				, @currCompression NVARCHAR(60)

		/* Initialize variables */	
		SELECT @AID_dbID = DB_ID(), @startDateTime = GETDATE(), @endDateTime = DATEADD(minute, @timeLimit, GETDATE()), @operationFlag = NULL, @ver = '1.6.6.9';
	
		/* Create temporary tables */	
		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragDatabaseList'))
		DROP TABLE #tblIndexDefragDatabaseList;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragDatabaseList'))
		CREATE TABLE #tblIndexDefragDatabaseList	
		(	
			dbID int
			, dbName NVARCHAR(256)
			, scanStatus bit NULL
		);

		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragmaxPartitionList'))
		DROP TABLE #tblIndexDefragmaxPartitionList;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragmaxPartitionList'))
		CREATE TABLE #tblIndexDefragmaxPartitionList	
		(	
			objectID int
			, indexID int
			, maxPartition int
		);

		/* Create table for fragmentation scan per table, index and partition - slower but less chance of blocking*/
		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragScanWorking'))
		DROP TABLE #tblIndexDefragScanWorking;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragScanWorking'))
		CREATE TABLE #tblIndexDefragScanWorking
		(
			objectID int
			, indexID int
			, type tinyint
			, partitionNumber int
			, is_done bit
		);

		/* Find available processors*/	
		SELECT @cpucount = COUNT(*)
		FROM sys.dm_os_schedulers
		WHERE is_online = 1 AND scheduler_id < 255	AND status = 'VISIBLE ONLINE'

		IF @maxDopRestriction IS NOT NULL AND @maxDopRestriction > @cpucount AND @cpucount <= 8
		BEGIN
			SET @maxDopRestriction = @cpucount
		END
		ELSE IF @maxDopRestriction IS NOT NULL AND ((@maxDopRestriction > @cpucount AND @cpucount > 8) OR @maxDopRestriction > 8)
		BEGIN
			SET @maxDopRestriction = 8;
		END

		/* Refer to http://docs.microsoft.com/sql/t-sql/functions/serverproperty-transact-sql */	
		IF (SELECT SERVERPROPERTY('EditionID')) IN (1804890536, 1872460670, 610778273, -2117995310)	
		SET @editionCheck = 1 -- supports enterprise only features: online rebuilds, partitioned indexes and MaxDOP
		ELSE	
		SET @editionCheck = 0; -- does not support enterprise only features: online rebuilds, partitioned indexes and MaxDOP		

		/* Output the parameters to work with */	
		IF @debugMode = 1	
		BEGIN	
			SELECT @debugMessage = CHAR(10) + 'Executing AdaptiveIndexDefrag v' + @ver + ' on ' + @@VERSION + '
The selected parameters are:
Defragment indexes with fragmentation greater or equal to ' + CAST(@minFragmentation AS NVARCHAR(10)) + ';
Rebuild indexes with fragmentation greater than ' + CAST(@rebuildThreshold AS NVARCHAR(10)) + ';
Rebuild columnstore indexes with fragmentation greater than ' + CAST(@rebuildThreshold_cs AS NVARCHAR(10)) + ';
' + CASE WHEN @disableNCIX = 1 THEN 'Non-clustered indexes will be disabled prior to rebuild;
' ELSE '' END + 'Defragment ' + CASE WHEN @ixtypeOption IS NULL THEN 'ALL indexes' WHEN @ixtypeOption = 1 THEN 'only CLUSTERED indexes' ELSE 'only NON-CLUSTERED, XML and Spatial indexes' END + ';
Commands' + CASE WHEN @Exec_Print = 1 THEN ' WILL' ELSE ' WILL NOT' END + ' be executed automatically;
Defragment indexes in ' + @defragSortOrder + ' order of the ' + UPPER(@defragOrderColumn) + ' value;
Time limit' + CASE WHEN @timeLimit IS NULL THEN ' was not specified;' ELSE ' was specified and is '	+ CAST(@timeLimit AS NVARCHAR(10)) END + ' minutes;
' + CASE WHEN @dbScope IS NULL THEN 'ALL databases' ELSE 'The [' + @dbScope + '] database' END + ' will be defragmented;
' + CASE WHEN @tblName IS NULL THEN 'ALL tables' ELSE 'The ' + @tblName + ' table' END + ' will be defragmented;
' + 'We' + CASE WHEN EXISTS(SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL) AND @forceRescan = 0 THEN ' will resume any existing previous run. If so, we WILL NOT' ELSE ' WILL' END + ' be rescanning indexes;
The scan will be performed in ' + @scanMode + ' mode;
LOBs will ' + CASE WHEN @dealLOB = 1 THEN 'NOT ' ELSE '' END + 'be compacted;
Limit defrags to indexes' + CASE WHEN @maxPageCount IS NULL THEN ' with more than ' + CAST(@minPageCount AS NVARCHAR(10)) ELSE		
' between ' + CAST(@minPageCount AS NVARCHAR(10)) + ' and ' + CAST(@maxPageCount AS NVARCHAR(10)) END + ' pages;
Indexes will be defragmented' + CASE WHEN @onlineRebuild = 0 OR @editionCheck = 0 THEN ' OFFLINE;' ELSE ' ONLINE;' END + '
Indexes will be sorted in' + CASE WHEN @sortInTempDB = 0 THEN ' the DATABASE;' ELSE ' TEMPDB;' END + '
Indexes will use ' + CASE WHEN @dataCompression IS NULL THEN 'CURRENT compression setting;' WHEN @dataCompression = 'NONE' THEN 'NO compression on all indexes;' WHEN @dataCompression = 'PAGE' THEN 'PAGE compression on all indexes;' WHEN @dataCompression = 'ROW' THEN 'ROW compression on all indexes;' ELSE @dataCompression + 'COLUMNSTORE compression on all indexes;' END + '
Indexes will keep' + CASE WHEN @fillfactor = 1 THEN ' its EXISTING' ELSE ' the DEFAULT' END + ' Fill Factor;' +
CASE WHEN @dealMaxPartition = 1 AND @editionCheck = 1 THEN '
The right-most populated partitions will be ignored;'
WHEN @dealMaxPartition = 0 AND @editionCheck = 1 THEN '		
Only the right-most populated partitions will be considered if greater than ' + CAST(@minPageCount AS NVARCHAR(10)) + ' page(s);'
ELSE CHAR(10) + 'All partitions will be considered;' END +
CHAR(10) + 'Statistics ' + CASE WHEN @updateStats = 1 THEN 'WILL' ELSE 'WILL NOT' END + ' be updated ' + CASE WHEN @updateStatsWhere = 1 THEN 'on reorganized indexes;' ELSE 'on all stats belonging to parent table;' END +		
CASE WHEN @updateStats = 1 AND @statsSample IS NOT NULL AND ISNUMERIC(@statsSample) = 0 THEN CHAR(10) + 'Statistics will be updated with ' + @statsSample ELSE '' END +
CASE WHEN @updateStats = 1 AND @statsSample IS NOT NULL AND ISNUMERIC(@statsSample) = 1 THEN CHAR(10) + 'Statistics will be updated with ' + RTRIM(@statsSample) + ' sampling rate' ELSE '' END +
CASE WHEN @updateStats = 1 AND @statsSample IS NOT NULL AND ISNUMERIC(@statsSample) = 1 AND @persistStatsSample = 1 THEN ' and persisting specified sampling rate percent;' ELSE '' END +
CASE WHEN @updateStats = 1 AND @statsSample IS NOT NULL AND ((ISNUMERIC(@statsSample) = 1 AND @persistStatsSample = 0) OR @persistStatsSample IS NULL) THEN ' and NOT persisting specified sampling rate percent;' ELSE '' END +
CHAR(10) + 'Statistics will be updated using ' + CASE WHEN @statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.001 AND 100.0 THEN 'a threshold of ' + CONVERT(VARCHAR, @statsThreshold) + ' percent' ELSE 'a calculated threshold similar to TF2371' END + 
+ ' on tables' + CASE WHEN @statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.01 AND 100.0 AND @statsMinRows IS NOT NULL THEN ' with a min of ' + CONVERT(VARCHAR, @statsMinRows) + ' rows.' WHEN @statsMinRows IS NOT NULL THEN ' of any size.' ELSE '.' END + 		
CHAR(10) + 'Statistics will be updated with Incremental property (if any) ' + CASE WHEN @statsIncremental = 1 THEN 'as ON' WHEN @statsIncremental = 0 THEN 'as OFF' ELSE 'not changed from current setting' END + '.' +
CHAR(10) + 'Defragmentation will use ' + CASE WHEN @editionCheck = 0 OR @maxDopRestriction IS NULL THEN 'system defaults for processors;'
ELSE CAST(@maxDopRestriction AS VARCHAR(3)) + ' processors;' END +
CHAR(10) + 'Lock timeout is set to ' + CASE WHEN @offlinelocktimeout <> -1 AND @offlinelocktimeout IS NOT NULL THEN CONVERT(NVARCHAR(15), @offlinelocktimeout) ELSE 'system default' END + ' for offline rebuilds;' +
CHAR(10) + 'Starting with SQL Server 2014, lock timeout is set to ' + CONVERT(NVARCHAR(15), @onlinelocktimeout) + ' for online rebuilds;' +
CHAR(10) + 'Starting with SQL Server 2014, lock timeout action is set to ' + CASE WHEN @abortAfterwait = 0 THEN 'BLOCKERS' WHEN @abortAfterwait = 1 THEN 'SELF' ELSE 'NONE' END + ' for online rebuilds;' +
CHAR(10) + CASE WHEN @printCmds = 1 THEN ' DO print' ELSE ' DO NOT print' END + ' the sql commands;' +
CHAR(10) + CASE WHEN @outputResults = 1 THEN ' DO output' ELSE ' DO NOT output' END + ' fragmentation levels;
Wait ' + @defragDelay + ' (hh:mm:ss) between index operations;
Execute in' + CASE WHEN @debugMode = 1 THEN ' DEBUG' ELSE ' SILENT' END + ' mode.' + CHAR(10);
			RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
		END;
		
		/* If we are scanning the database(s), do some pre-work */
		IF @forceRescan = 1 OR (NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)
									AND NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working AS idss WHERE idss.updateDate IS NULL AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)))
		BEGIN
			IF @debugMode = 1
			RAISERROR('Listing databases...', 0, 42) WITH NOWAIT;

			/* Retrieve the list of databases to loop, excluding Always On secondary replicas */	
			DECLARE @sqlcmdAO2 NVARCHAR(4000), @paramsAO2 NVARCHAR(50)
			
			IF @debugMode = 1 AND @sqlmajorver >= 11
			RAISERROR('Retrieving list of databases to loop, excluding Always On secondary replicas...', 0, 42) WITH NOWAIT;

			IF @debugMode = 1 AND @sqlmajorver < 11
			RAISERROR('Retrieving list of databases to loop...', 0, 42) WITH NOWAIT;

			SET @sqlcmdAO2 = 'SELECT [database_id], name, 0 -- not yet scanned for fragmentation
FROM sys.databases
WHERE LOWER([name]) = ISNULL(LOWER(@dbScopeIN), LOWER([name]))	
	AND LOWER([name]) NOT IN (''master'', ''tempdb'', ''model'', ''reportservertempdb'',''semanticsdb'') -- exclude system databases
	AND [state] = 0 -- must be ONLINE
	AND is_read_only = 0 -- cannot be READ_ONLY
	AND is_distributor = 0'
				
			IF @sqlmajorver >= 11 AND (SELECT @@VERSION) NOT LIKE 'Microsoft SQL Azure%'-- Except all local Always On secondary replicas
			BEGIN
				SET @sqlcmdAO2 = @sqlcmdAO2 + CHAR(10) + 'AND [database_id] NOT IN (SELECT dr.database_id FROM sys.dm_hadr_database_replica_states dr
INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
INNER JOIN sys.databases d ON dr.database_id = d.database_id
WHERE rs.role = 2 -- Is Secondary
	AND dr.is_local = 1
	AND rs.is_local = 1)'
			END
			
			SET @paramsAO2 = N'@dbScopeIN NVARCHAR(256)'
			
			INSERT INTO #tblIndexDefragDatabaseList	
			EXECUTE sp_executesql @sqlcmdAO2, @paramsAO2, @dbScopeIN = @dbScope
			
			IF @debugMode = 1
			RAISERROR('Cross checking with exceptions for today...', 0, 42) WITH NOWAIT;

			/* Avoid scanning databases that have all its indexes in the exceptions table i.e, fully excluded */
			WHILE (SELECT COUNT(*) FROM #tblIndexDefragDatabaseList WHERE scanStatus = 0) > 0
			BEGIN
				SELECT TOP 1 @dbID = dbID FROM #tblIndexDefragDatabaseList WHERE scanStatus = 0;

				SELECT @ixCntSource = COUNT([indexName]) FROM dbo.tbl_AdaptiveIndexDefrag_Exceptions WHERE [dbID] = @dbID AND exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0

				SET @ixCntsqlcmd = 'SELECT @ixCntTargetOUT = COUNT(si.index_id) FROM [' + DB_NAME(@dbID) + '].sys.indexes si
INNER JOIN [' + DB_NAME(@dbID) + '].sys.objects so ON si.object_id = so.object_id
WHERE so.is_ms_shipped = 0 AND si.index_id > 0 AND si.is_hypothetical = 0
	AND si.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + DB_NAME(@dbID) + '].sys.internal_tables AS sit)' -- Exclude Heaps, Internal and Hypothetical objects
				SET @ixCntsqlcmdParams = '@ixCntTargetOUT int OUTPUT'
				EXECUTE sp_executesql @ixCntsqlcmd, @ixCntsqlcmdParams, @ixCntTargetOUT = @ixCntTarget OUTPUT

				IF @ixCntSource = @ixCntTarget AND @ixCntSource > 0 -- All database objects are excluded, so skip database scanning
				BEGIN
					UPDATE #tblIndexDefragDatabaseList
					SET scanStatus = NULL
					WHERE dbID = @dbID;

					IF @debugMode = 1
					SELECT @debugMessage = '  Database ' + DB_NAME(@dbID) + ' is fully excluded from todays work.';

					IF @debugMode = 1
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END

				IF @ixCntSource < @ixCntTarget AND @ixCntSource > 0 -- Only some database objects are excluded, so scan anyway and deal with exclusions on a granular level
				BEGIN
					UPDATE #tblIndexDefragDatabaseList
					SET scanStatus = 1
					WHERE dbID = @dbID;
					
					IF @debugMode = 1
					SELECT @debugMessage = '  Database ' + DB_NAME(@dbID) + ' is partially excluded from todays work.';

					IF @debugMode = 1
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END

				IF @ixCntSource = 0 -- Database does not have excluded objects
				BEGIN
					UPDATE #tblIndexDefragDatabaseList		
					SET scanStatus = 1		
					WHERE dbID = @dbID;
				END;
			END;

			/* Delete databases that are fully excluded for today */
			DELETE FROM #tblIndexDefragDatabaseList
			WHERE scanStatus IS NULL;
			
			/* Reset status after cross check with exceptions */
			UPDATE #tblIndexDefragDatabaseList
			SET scanStatus = 0;
			
			/* Delete database set by @dbScope */
			IF @dbScope IS NOT NULL
			BEGIN
				DELETE FROM #tblIndexDefragDatabaseList
				WHERE dbID <> DB_ID(@dbScope);
			END;
		END

		/* Check to see if we have indexes of the chosen type in need of defrag, or stats to update; otherwise, allow re-scanning the database(s) */
		IF @forceRescan = 1 OR (@forceRescan = 0 
			AND NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL AND [exclusionMask] & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)
			AND NOT EXISTS (SELECT TOP 1 * FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working AS idss WHERE idss.updateDate IS NULL AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)))
		BEGIN	
			IF @debugMode = 1
			RAISERROR('Preparing for new database scan...', 0, 42) WITH NOWAIT;
			
			/* Truncate list of indexes and stats to prepare for a new scan */
			TRUNCATE TABLE dbo.tbl_AdaptiveIndexDefrag_Working;
			TRUNCATE TABLE dbo.tbl_AdaptiveIndexDefrag_Stats_Working;
		END
		ELSE
		BEGIN
			/* Print an error message if there are any indexes left to defrag according to the chosen criteria */		
			IF @debugMode = 1		
			RAISERROR('There are still fragmented indexes or out-of-date stats from last execution. Resuming...', 0, 42) WITH NOWAIT;
		END

		/* Scan the database(s) */	
		IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working) = 0
		BEGIN
			IF @debugMode = 1
			RAISERROR('Scanning database(s)...', 0, 42) WITH NOWAIT;

			IF @debugMode = 1
			RAISERROR(' Looping through list of databases and checking for fragmentation...', 0, 42) WITH NOWAIT;

			/* Loop through list of databases */
			WHILE (SELECT COUNT(*) FROM #tblIndexDefragDatabaseList WHERE scanStatus = 0) > 0
			BEGIN
				SELECT TOP 1 @dbID = dbID FROM #tblIndexDefragDatabaseList WHERE scanStatus = 0;
				
				IF @debugMode = 1
				SELECT @debugMessage = '  Working on database [' + DB_NAME(@dbID) + ']...';

				IF @debugMode = 1		
				RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

				IF @dbScope IS NOT NULL AND @tblName IS NOT NULL
				SELECT @tblNameFQN = @dbScope + '.' + @tblName
				
				/* Set partitioning rebuild options; requires Enterprise Edition */		
				IF @dealMaxPartition IS NOT NULL AND @editionCheck = 0		
				SET @dealMaxPartition = NULL;

				/* Truncate list of tables, indexes and partitions to prepare for a new scan */
				TRUNCATE TABLE #tblIndexDefragScanWorking;
				
				IF @debugMode = 1
				RAISERROR('   Building list of objects in database...', 0, 42) WITH NOWAIT;
				SELECT @TableScanSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE [' + DB_NAME(@dbID) + '];
' ELSE '' END + 'SELECT si.[object_id], si.index_id, si.type, sp.partition_number, 0
FROM sys.indexes si
INNER JOIN sys.partitions sp ON si.[object_id] = sp.[object_id] AND si.index_id = sp.index_id
INNER JOIN sys.tables AS mst ON mst.[object_id] = si.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]' +
CASE WHEN @dbScope IS NULL AND @tblName IS NULL THEN CHAR(10) + 'LEFT JOIN [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Exceptions AS ide ON ide.[dbID] = ' + CONVERT(NVARCHAR(10),@dbID) + ' AND ide.objectID = si.[object_id] AND ide.indexID = si.index_id' ELSE '' END +
CHAR(10) + 'WHERE mst.is_ms_shipped = 0 ' + CASE WHEN @dbScope IS NULL AND @tblName IS NULL THEN 'AND (ide.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0 OR ide.exclusionMask IS NULL)' ELSE '' END + '
	AND si.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + DB_NAME(@dbID) + '].sys.internal_tables AS sit)' +
		CASE WHEN @dbScope IS NOT NULL AND @tblName IS NOT NULL THEN '
	AND t.name + ''.'' + mst.name = ''' + @tblName + ''';' ELSE ';' END
	
				INSERT INTO #tblIndexDefragScanWorking
				EXEC sp_executesql @TableScanSQL;

				/* Do we want to act on a subset of existing partitions? */		
				IF @dealMaxPartition = 1 OR @dealMaxPartition = 0		
				BEGIN
					IF @debugMode = 1
					RAISERROR('    Setting partition handling...', 0, 42) WITH NOWAIT;

					SET @dealMaxPartitionSQL = 'SELECT [object_id], index_id, MAX(partition_number) AS [maxPartition] FROM [' + DB_NAME(@dbID) + '].sys.partitions WHERE partition_number > 1 AND [rows] > 0 GROUP BY object_id, index_id;';

					INSERT INTO #tblIndexDefragmaxPartitionList	
					EXEC sp_executesql @dealMaxPartitionSQL;
				END;

				/* We don't want to defrag the right-most populated partition, so delete any records for partitioned indexes where partition = MAX(partition) */
				IF @dealMaxPartition = 1 AND @editionCheck = 1	
				BEGIN							
					IF @debugMode = 1
					RAISERROR('      Ignoring right-most populated partition...', 0, 42) WITH NOWAIT;

					DELETE ids		
					FROM #tblIndexDefragScanWorking AS ids		
					INNER JOIN #tblIndexDefragmaxPartitionList AS mpl ON ids.objectID = mpl.objectID AND ids.indexID = mpl.indexID AND ids.partitionNumber = mpl.maxPartition;
				END;

				/* We only want to defrag the right-most populated partition, so delete any records for partitioned indexes where partition <> MAX(partition) */
				IF @dealMaxPartition = 0 AND @editionCheck = 1
				BEGIN
					IF @debugMode = 1
					RAISERROR('      Setting only right-most populated partition...', 0, 42) WITH NOWAIT;

					DELETE ids		
					FROM #tblIndexDefragScanWorking AS ids		
					INNER JOIN #tblIndexDefragmaxPartitionList AS mpl ON ids.objectID = mpl.objectID AND ids.indexID = mpl.indexID AND ids.partitionNumber <> mpl.maxPartition;
				END;
				
				/* Determine which indexes to defrag using user-defined parameters */
				IF @debugMode = 1
				RAISERROR('      Filtering indexes according to ixtypeOption parameter...', 0, 42) WITH NOWAIT;
				IF @ixtypeOption IS NULL
				BEGIN
					DELETE FROM #tblIndexDefragScanWorking		
					WHERE [type] = 0; -- ignore heaps
				END
				ELSE IF @ixtypeOption = 1
				BEGIN
					DELETE FROM #tblIndexDefragScanWorking		
					WHERE [type] NOT IN (1,5); -- keep only clustered index	
				END
				ELSE IF @ixtypeOption = 0
				BEGIN
					DELETE FROM #tblIndexDefragScanWorking		
					WHERE [type] NOT IN (2,6); -- keep only non-clustered indexes
				END;

				-- Get rowstore indexes to work on
				IF @debugMode = 1
				RAISERROR('    Getting rowstore indexes...', 0, 42) WITH NOWAIT;
				WHILE (SELECT COUNT(*) FROM #tblIndexDefragScanWorking WHERE is_done = 0 AND [type] IN (1,2)) > 0
				BEGIN
					SELECT TOP 1 @objectID = objectID, @indexID = indexID, @partitionNumber = partitionNumber
					FROM #tblIndexDefragScanWorking WHERE is_done = 0 AND type IN (1,2)
					
					/* Get the time for logging purposes */		
					SET @dateTimeStart = GETDATE();

					IF @debugMode = 1
					BEGIN
						SELECT @debugMessage = '      Analyzing index ID ' + CONVERT(VARCHAR(20), @indexID) + ' on table [' + OBJECT_NAME(@objectID, @dbID) + ']...'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					/* Start log actions */
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Analysis_log ([Operation], [dbID], dbName, objectID, objectName, index_or_stat_ID, partitionNumber, dateTimeStart)		
					SELECT 'Index', @dbID, DB_NAME(@dbID), @objectID, OBJECT_NAME(@objectID, @dbID), @indexID, @partitionNumber, @dateTimeStart;

					SET @analysis_id = SCOPE_IDENTITY();
					
					BEGIN TRY
						IF @getBlobfrag = 1
						BEGIN
							INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Working (dbID, dbName, objectID, indexID, partitionNumber, fragmentation, page_count, range_scan_count, record_count, scanDate)		
							SELECT @dbID AS [dbID], QUOTENAME(DB_NAME(ps.database_id)) AS [dbName], @objectID AS [objectID], @indexID AS [indexID], ps.partition_number AS [partitionNumber], SUM(ps.avg_fragmentation_in_percent) AS [fragmentation], SUM(ps.page_count) AS [page_count], os.range_scan_count, ps.record_count, GETDATE() AS [scanDate]
							FROM sys.dm_db_index_physical_stats(@dbID, @objectID, @indexID, @partitionNumber, @scanMode) AS ps
							LEFT JOIN sys.dm_db_index_operational_stats(@dbID, @objectID, @indexID, @partitionNumber) AS os ON ps.database_id = os.database_id AND ps.object_id = os.object_id AND ps.index_id = os.index_id AND ps.partition_number = os.partition_number
							WHERE avg_fragmentation_in_percent >= @minFragmentation
								AND ps.page_count >= @minPageCount
								AND ps.index_level = 0 -- leaf-level nodes only, supports @scanMode
								AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'  -- exclude blobs
							GROUP BY ps.database_id, QUOTENAME(DB_NAME(ps.database_id)), ps.partition_number, os.range_scan_count, ps.record_count	
							OPTION (MAXDOP 2);
						END
						ELSE IF @getBlobfrag = 0
						BEGIN
							INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Working (dbID, dbName, objectID, indexID, partitionNumber, fragmentation, page_count, range_scan_count, record_count, scanDate)		
							SELECT @dbID AS [dbID], QUOTENAME(DB_NAME(ps.database_id)) AS [dbName], @objectID AS [objectID], @indexID AS [indexID], ps.partition_number AS [partitionNumber], SUM(ps.avg_fragmentation_in_percent) AS [fragmentation], SUM(ps.page_count) AS [page_count], os.range_scan_count, ps.record_count, GETDATE() AS [scanDate]
							FROM sys.dm_db_index_physical_stats(@dbID, @objectID, @indexID, @partitionNumber, @scanMode) AS ps
							LEFT JOIN sys.dm_db_index_operational_stats(@dbID, @objectID, @indexID, @partitionNumber) AS os ON ps.database_id = os.database_id AND ps.object_id = os.object_id AND ps.index_id = os.index_id AND ps.partition_number = os.partition_number
							WHERE avg_fragmentation_in_percent >= @minFragmentation
								AND ps.page_count >= @minPageCount
								AND ps.index_level = 0 -- leaf-level nodes only, supports @scanMode
							GROUP BY ps.database_id, QUOTENAME(DB_NAME(ps.database_id)), ps.partition_number, os.range_scan_count, ps.record_count	
							OPTION (MAXDOP 2);
						END
					END TRY
					BEGIN CATCH						
						IF @debugMode = 1
						BEGIN
							SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred while determining which rowstore indexes to defrag. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'

							SET @dateTimeEnd = GETDATE();

							/* Update log with completion time */	
							UPDATE dbo.tbl_AdaptiveIndexDefrag_Analysis_log	
							SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd), errorMessage = LTRIM(@debugMessage)
							WHERE analysis_id = @analysis_id AND dateTimeEnd IS NULL;

							RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
							--RAISERROR('     An error has occurred executing the pre-command! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 0, 42) WITH NOWAIT;
						END
					END CATCH
					
					SET @dateTimeEnd = GETDATE();
												
					/* Update log with completion time */	
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Analysis_log	
					SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)
					WHERE analysis_id = @analysis_id AND dateTimeEnd IS NULL;
						
					UPDATE #tblIndexDefragScanWorking
					SET is_done = 1
					WHERE objectID = @objectID AND indexID = @indexID AND partitionNumber = @partitionNumber
				END;

				-- Get columnstore indexes to work on
				IF @debugMode = 1 AND @sqlmajorver >= 12
				RAISERROR('    Getting columnstore indexes...', 0, 42) WITH NOWAIT;
				IF @sqlmajorver >= 12
				BEGIN
					WHILE (SELECT COUNT(*) FROM #tblIndexDefragScanWorking WHERE is_done = 0 AND [type] IN (5,6)) > 0
					BEGIN
						SELECT TOP 1 @objectID = objectID, @indexID = indexID, @partitionNumber = partitionNumber
						FROM #tblIndexDefragScanWorking WHERE is_done = 0 AND type IN (5,6)

						/* Get the time for logging purposes */		
						SET @dateTimeStart = GETDATE();

						/* Start log actions */
						INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Analysis_log ([Operation], [dbID], dbName, objectID, objectName, index_or_stat_ID, partitionNumber, dateTimeStart)		
						SELECT 'Index', @dbID, DB_NAME(@dbID), @objectID, OBJECT_NAME(@objectID, @dbID), @indexID, @partitionNumber, @dateTimeStart;					

						SET @analysis_id = SCOPE_IDENTITY();
					
						BEGIN TRY
							SELECT @ColumnStoreGetIXSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE [' + DB_NAME(@dbID) + '];
' ELSE '' END + 'SELECT @dbID_In, QUOTENAME(DB_NAME(@dbID_In)), rg.object_id, rg.index_id, rg.partition_number, CASE WHEN SUM((ISNULL(rg.deleted_rows,1)*100)/rg.total_rows) > 100 THEN 100 ELSE SUM((ISNULL(rg.deleted_rows,1)*100)/rg.total_rows) END AS [fragmentation], SUM(ISNULL(rg.size_in_bytes,1)/1024/8) AS [simulated_page_count], SUM(rg.total_rows) AS total_rows, GETDATE() AS [scanDate]	
FROM ' + CASE WHEN @sqlmajorver = 12 THEN 'sys.column_store_row_groups' ELSE 'sys.dm_db_column_store_row_group_physical_stats' END + ' rg WITH (NOLOCK)
WHERE rg.object_id = @objectID_In
	AND rg.index_id = @indexID_In
	AND rg.partition_number = @partitionNumber_In
	AND rg.state = 3 -- Only COMPRESSED row groups
GROUP BY rg.object_id, rg.index_id, rg.partition_number
HAVING SUM(ISNULL(rg.size_in_bytes,1)/1024/8) >= @minPageCount_In
OPTION (MAXDOP 2)'
							SET @ColumnStoreGetIXSQL_Param = N'@dbID_In int, @objectID_In int, @indexID_In int, @partitionNumber_In smallint, @minPageCount_in int';

							INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Working (dbID, dbName, objectID, indexID, partitionNumber, fragmentation, page_count, record_count, scanDate)		
							EXECUTE sp_executesql @ColumnStoreGetIXSQL, @ColumnStoreGetIXSQL_Param, @dbID_In = @dbID, @objectID_In = @objectID, @indexID_In = @indexID, @partitionNumber_In = @partitionNumber, @minPageCount_in = @minPageCount;
						END TRY
						BEGIN CATCH						
							IF @debugMode = 1
							BEGIN
								SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred while determining which columnstore indexes to defrag. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'

								SET @dateTimeEnd = GETDATE();
															
								/* Update log with completion time */	
								UPDATE dbo.tbl_AdaptiveIndexDefrag_Analysis_log	
								SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd), errorMessage = LTRIM(@debugMessage)
								WHERE analysis_id = @analysis_id AND dateTimeEnd IS NULL;
								
								RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
								--RAISERROR('     An error has occurred executing the pre-command! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 0, 42) WITH NOWAIT;
							END
						END CATCH;

						SET @dateTimeEnd = GETDATE();
													
						/* Update log with completion time */	
						UPDATE dbo.tbl_AdaptiveIndexDefrag_Analysis_log	
						SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)
						WHERE analysis_id = @analysis_id AND dateTimeEnd IS NULL;
							
						UPDATE #tblIndexDefragScanWorking
						SET is_done = 1
						WHERE objectID = @objectID AND indexID = @indexID AND partitionNumber = @partitionNumber
					END
				END;

				/* Look up index status for various purposes */	
				SELECT @updateSQL = N'UPDATE ids		
SET schemaName = QUOTENAME(s.name), objectName = QUOTENAME(o.name), indexName = QUOTENAME(i.name), is_primary_key = i.is_primary_key, fill_factor = i.fill_factor, is_disabled = i.is_disabled, is_padded = i.is_padded, is_hypothetical = i.is_hypothetical, has_filter = ' + CASE WHEN @sqlmajorver >= 10 THEN 'i.has_filter' ELSE '0' END + ', allow_page_locks = i.allow_page_locks, type = i.type
FROM [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Working ids WITH (NOLOCK)
INNER JOIN [' + DB_NAME(@dbID) + '].sys.objects AS o WITH (NOLOCK) ON ids.objectID = o.object_id
INNER JOIN [' + DB_NAME(@dbID) + '].sys.indexes AS i WITH (NOLOCK) ON o.object_id = i.object_id AND ids.indexID = i.index_id
INNER JOIN [' + DB_NAME(@dbID) + '].sys.schemas AS s WITH (NOLOCK) ON o.schema_id = s.schema_id
WHERE o.object_id = ids.objectID AND i.index_id = ids.indexID AND i.type > 0
AND o.object_id NOT IN (SELECT sit.object_id FROM [' + DB_NAME(@dbID) + '].sys.internal_tables AS sit)
AND ids.[dbID] = ' + CAST(@dbID AS NVARCHAR(10));

				IF @debugMode = 1
				BEGIN
					RAISERROR('    Looking up additional index information (pass 1)...', 0, 42) WITH NOWAIT;
					--PRINT @updateSQL
				END
				
				EXECUTE sp_executesql @updateSQL;
				
				IF @sqlmajorver = 9
				BEGIN
					SELECT @updateSQL = N'UPDATE ids
SET [record_count] = [rows], [compression_type] = N''''
FROM [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Working ids WITH (NOLOCK)
INNER JOIN [' + DB_NAME(@dbID) + '].sys.partitions AS p WITH (NOLOCK) ON ids.objectID = p.[object_id] AND ids.indexID = p.index_id AND ids.partitionNumber = p.partition_number
WHERE ids.[dbID] = ' + CAST(@dbID AS NVARCHAR(10));
				END
				ELSE
				BEGIN
					SELECT @updateSQL = N'UPDATE ids
SET [record_count] = [rows], [compression_type] = [data_compression_desc]
FROM [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Working ids WITH (NOLOCK)
INNER JOIN [' + DB_NAME(@dbID) + '].sys.partitions AS p WITH (NOLOCK) ON ids.objectID = p.[object_id] AND ids.indexID = p.index_id AND ids.partitionNumber = p.partition_number
WHERE ids.[dbID] = ' + CAST(@dbID AS NVARCHAR(10));
				END

				IF @debugMode = 1
				BEGIN
					RAISERROR('    Looking up additional index information (pass 2)...', 0, 42) WITH NOWAIT;
					--PRINT @updateSQL
				END
				
				EXECUTE sp_executesql @updateSQL;
				
				IF @debugMode = 1
				RAISERROR('    Looking up additional statistic information...', 0, 42) WITH NOWAIT;
				
				/* Look up stats information for various purposes */
				DECLARE @tblNameOnly NVARCHAR(1000), @schemaNameOnly NVARCHAR(128)
				IF @tblName IS NOT NULL
				BEGIN
					SELECT @tblNameOnly = RIGHT(@tblName, LEN(@tblName) - CHARINDEX('.', @tblName, 1)), @schemaNameOnly = LEFT(@tblName, CHARINDEX('.', @tblName, 1) -1)
				END
				
				SELECT @updateSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE [' + DB_NAME(@dbID) + '];
' ELSE '' END + 'SELECT DISTINCT ' + CAST(@dbID AS NVARCHAR(10)) + ', ''[' + DB_NAME(@dbID) + ']'', ss.[object_id], ss.stats_id, ' + CASE WHEN ((@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver > 12) THEN 'ISNULL(sp.partition_number,1),' ELSE '1,' END + '
	QUOTENAME(s.name), QUOTENAME(so.name), QUOTENAME(ss.name), ss.[no_recompute], ' + CASE WHEN @sqlmajorver < 12 THEN '0 AS ' ELSE 'ss.' END + '[is_incremental], GETDATE() AS scanDate
FROM sys.stats AS ss WITH (NOLOCK)
INNER JOIN sys.objects AS so WITH (NOLOCK) ON ss.[object_id] = so.[object_id]
INNER JOIN sys.schemas AS s WITH (NOLOCK) ON so.[schema_id] = s.[schema_id]' +
CASE WHEN @updateStatsWhere = 0 THEN 'LEFT JOIN' ELSE 'INNER JOIN' END + -- @updateStatsWhere = 0 then table-wide statistics;
' sys.indexes AS si WITH (NOLOCK) ON ss.[object_id] = si.[object_id] and ss.name = si.name' +
CASE WHEN @dbScope IS NULL AND @tblName IS NULL THEN CHAR(10) + CHAR(10) + 'LEFT JOIN [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Exceptions AS ide ON ide.[dbID] = ' + CONVERT(NVARCHAR(10),@dbID) + ' AND ide.objectID = so.[object_id]' ELSE '' END +
CASE WHEN ((@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver > 12) THEN CHAR(10) + 'CROSS APPLY sys.dm_db_stats_properties_internal(ss.[object_id], ss.stats_id) sp' ELSE '' END + 
CHAR(10) + 'WHERE is_ms_shipped = 0 ' + CASE WHEN @sqlmajorver >= 12 THEN 'AND ss.is_temporary = 0' ELSE '' END + '
	AND so.[object_id] NOT IN (SELECT sit.[object_id] FROM sys.internal_tables AS sit)
	AND so.[type] IN (''U'',''V'')
	AND (si.[type] IS NULL OR si.[type] NOT IN (5,6,7))' + -- Avoid error 35337
CASE WHEN @dbScope IS NOT NULL AND @tblName IS NOT NULL THEN CHAR(10) + 'AND s.name = ''' + @schemaNameOnly + ''' AND so.name = ''' + @tblNameOnly + ''';' ELSE ';' END
				
				INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_Working (dbID, dbName, objectID, statsID, partitionNumber, schemaName, objectName, statsName, [no_recompute], [is_incremental], scanDate)
				EXECUTE sp_executesql @updateSQL;

				/* Keep track of which databases have already been scanned */	
				UPDATE #tblIndexDefragDatabaseList		
				SET scanStatus = 1		
				WHERE dbID = @dbID;
			END;

			/* Delete any records for disabled (except those disabled by the defrag cycle itself) or hypothetical indexes */						
			IF @debugMode = 1
			RAISERROR(' Listing and removing disabled indexes (except those disabled by the defrag cycle itself) or hypothetical indexes from loop...', 0, 42) WITH NOWAIT;
		
			IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working AS ids	WHERE ids.is_disabled = 1 OR ids.is_hypothetical = 1) > 0
			DELETE ids		
			FROM dbo.tbl_AdaptiveIndexDefrag_Working AS ids
				LEFT JOIN dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus AS ids_disable ON ids.objectID = ids_disable.objectID AND ids.indexID = ids_disable.indexID AND ids.[dbID] = ids_disable.dbID
			WHERE ids.is_disabled = 1 OR ids.is_hypothetical = 1 AND ids_disable.indexID IS NULL;

			IF @debugMode = 1
			RAISERROR(' Updating Exception mask for any index that has a restriction on the days it CANNOT be defragmented...', 0, 42) WITH NOWAIT;

			/* Update our Exception mask for any index that has a restriction on the days it CANNOT be defragmented
			   based on 1=Sunday, 2=Monday, 4=Tuesday, 8=Wednesday, 16=Thursday, 32=Friday, 64=Saturday, 127=AllWeek
			*/
			UPDATE ids
			SET ids.exclusionMask = ide.exclusionMask
			FROM dbo.tbl_AdaptiveIndexDefrag_Working AS ids
			INNER JOIN dbo.tbl_AdaptiveIndexDefrag_Exceptions AS ide ON ids.[dbID] = ide.[dbID] AND ids.objectID = ide.objectID AND ids.indexID = ide.indexID;
		END;
		
		IF @debugMode = 1
		SELECT @debugMessage = 'Looping through batch list... There are ' + CAST(COUNT(DISTINCT indexName) AS NVARCHAR(10)) + ' indexes to defragment in ' + CAST(COUNT(DISTINCT dbName) AS NVARCHAR(10)) + ' database(s)!'	
		FROM dbo.tbl_AdaptiveIndexDefrag_Working	
		WHERE defragDate IS NULL AND page_count BETWEEN @minPageCount AND ISNULL(@maxPageCount, page_count) AND exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0;

		IF @debugMode = 1
		RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

		IF @debugMode = 1
		BEGIN
			IF @updateStatsWhere = 1
			BEGIN
				SELECT @debugMessage = 'Looping through batch list... There are ' + CAST(COUNT(DISTINCT statsName) AS NVARCHAR(10)) + ' index related statistics to update in ' + CAST(COUNT(DISTINCT idss.dbName) AS NVARCHAR(10)) + ' database(s)!'	
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss
					INNER JOIN dbo.tbl_AdaptiveIndexDefrag_Working ids ON ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID
				WHERE idss.schemaName = ids.schemaName AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0;
			END
			ELSE
			BEGIN
				SELECT @debugMessage = 'Looping through batch list... There are ' + CAST(COUNT(DISTINCT statsName) AS NVARCHAR(10)) + ' index related statistics to update in ' + CAST(COUNT(DISTINCT idss.dbName) AS NVARCHAR(10)) + ' database(s),'	
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss
					INNER JOIN dbo.tbl_AdaptiveIndexDefrag_Working ids ON ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID
				WHERE idss.schemaName = ids.schemaName AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0;

				SELECT @debugMessage = @debugMessage + ' plus ' + CAST(COUNT(DISTINCT statsName) AS NVARCHAR(10)) + ' other statistics to update in ' + CAST(COUNT(DISTINCT dbName) AS NVARCHAR(10)) + ' database(s)!'	
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss
				WHERE idss.updateDate IS NULL
					AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0);
			END
		END
		
		IF @debugMode = 1		
		RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

		IF @Exec_Print = 0 AND @printCmds = 1
		BEGIN
			RAISERROR(' Printing SQL statements...', 0, 42) WITH NOWAIT;
		END;
		
		/* Begin defragmentation loop */	
		WHILE (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE ((@Exec_Print = 1 AND defragDate IS NULL) OR (@Exec_Print = 0 AND defragDate IS NULL AND printStatus = 0)) AND exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0 AND page_count BETWEEN @minPageCount AND ISNULL(@maxPageCount, page_count)) > 0
		BEGIN						
			/* Check to see if we need to exit loop because of our time limit */
			IF ISNULL(@endDateTime, GETDATE()) < GETDATE()
			RAISERROR('Time limit has been exceeded for this maintenance window!', 16, 42) WITH NOWAIT;

			IF @debugMode = 1
			RAISERROR(' Selecting an index to defragment...', 0, 42) WITH NOWAIT;

			/* Select the index with highest priority, based on the values submitted; Verify date constraint for this index in the Exception table */
			SET @getIndexSQL = N'SELECT TOP 1 @objectID_Out = objectID, @indexID_Out = indexID, @dbID_Out = dbID									
FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NULL '
+ CASE WHEN @Exec_Print = 0 THEN 'AND printStatus = 0 ' ELSE '' END + '		
AND exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0
AND page_count BETWEEN @p_minPageCount AND ISNULL(@p_maxPageCount, page_count)		
ORDER BY + ' + @defragOrderColumn + ' ' + @defragSortOrder + ', objectID DESC';

			SET @getIndexSQL_Param = N'@objectID_Out int OUTPUT, @indexID_Out int OUTPUT, @dbID_Out int OUTPUT, @p_minPageCount int, @p_maxPageCount int';
			EXECUTE sp_executesql @getIndexSQL, @getIndexSQL_Param, @p_minPageCount = @minPageCount, @p_maxPageCount = @maxPageCount, @objectID_Out = @objectID OUTPUT, @indexID_Out = @indexID OUTPUT, @dbID_Out = @dbID OUTPUT;

			IF @debugMode = 1
			RAISERROR('  Getting partition count...', 0, 42) WITH NOWAIT;

			/* Determine if the index is partitioned */
			SELECT @partitionCount = MAX(partitionNumber)
			FROM dbo.tbl_AdaptiveIndexDefrag_Working AS ids
			WHERE objectID = @objectID AND indexID = @indexID AND dbID = @dbID
			
			IF @debugMode = 1
			RAISERROR('  Getting selected index information...', 0, 42) WITH NOWAIT;

			/* Get object names and info */
			IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
			BEGIN
				IF @debugMode = 1
				RAISERROR('  	Partition number specific...', 0, 42) WITH NOWAIT;

				SELECT TOP 1 @objectName = objectName, @schemaName = schemaName, @indexName = indexName, @dbName = dbName, @fragmentation = fragmentation, @partitionNumber = partitionNumber, @pageCount = page_count, @range_scan_count = range_scan_count, @is_primary_key = is_primary_key, @fill_factor = fill_factor, @record_count = record_count, @ixtype = [type], @is_disabled = is_disabled, @is_padded = is_padded, @has_filter = has_filter, @currCompression = [compression_type]
				FROM dbo.tbl_AdaptiveIndexDefrag_Working
				WHERE objectID = @objectID AND indexID = @indexID AND dbID = @dbID AND ((@Exec_Print = 1 AND defragDate IS NULL) OR (@Exec_Print = 0 AND defragDate IS NULL AND printStatus = 0))
				ORDER BY partitionNumber ASC; -- ensure that we have always the same sequence in order to continue resumeable operations
			END
			ELSE
			BEGIN
				RAISERROR('  	Not partition number specific...', 0, 42) WITH NOWAIT;

				SELECT TOP 1 @objectName = objectName, @schemaName = schemaName, @indexName = indexName, @dbName = dbName, @fragmentation = fragmentation, @partitionNumber = NULL, @pageCount = page_count, @range_scan_count = range_scan_count, @is_primary_key = is_primary_key, @fill_factor = fill_factor, @record_count = record_count, @ixtype = [type], @is_disabled = is_disabled, @is_padded = is_padded, @has_filter = has_filter, @currCompression = [compression_type]
				FROM dbo.tbl_AdaptiveIndexDefrag_Working
				WHERE objectID = @objectID AND indexID = @indexID AND dbID = @dbID AND ((@Exec_Print = 1 AND defragDate IS NULL) OR (@Exec_Print = 0 AND defragDate IS NULL AND printStatus = 0));
			END
			
			/* Determine maximum partition number for use with stats update*/
			IF @updateStats = 1
			BEGIN
				SELECT @maxpartitionNumber = MAX(partitionNumber), @minpartitionNumber = MIN(partitionNumber)
				FROM dbo.tbl_AdaptiveIndexDefrag_Working
				WHERE objectID = @objectID AND indexID = @indexID AND dbID = @dbID;
			END
			
			IF @debugMode = 1
			RAISERROR('  Checking if any LOBs exist...', 0, 42) WITH NOWAIT;
			
			SET @containsLOB = 0

			/* Determine if the index contains LOBs, with info from sys.types */
			IF @ixtype = 2 AND @sqlmajorver < 11 -- Nonclustered and LOBs in INCLUDED columns? Up to SQL 2008R2
			BEGIN
				SELECT @LOB_SQL = 'SELECT @containsLOB_OUT = COUNT(*) FROM ' + @dbName + '.sys.columns c WITH (NOLOCK)
INNER JOIN ' + @dbName + '.sys.index_columns ic WITH (NOLOCK) ON c.[object_id] = ic.[object_id] AND c.column_id = ic.column_id
INNER JOIN ' + @dbName + '.sys.indexes i WITH (NOLOCK) ON i.[object_id] = ic.[object_id] and i.index_id = ic.index_id
WHERE max_length = -1 AND ic.is_included_column = 1
AND i.object_id = ' + CAST(@objectID AS NVARCHAR(10)) + ' AND i.index_id = ' + CAST(@indexID AS NVARCHAR(10)) + ';'
			/* max_length = -1 for VARBINARY(MAX), VARCHAR(MAX), NVARCHAR(MAX), XML */								
				,@LOB_SQL_Param = '@containsLOB_OUT int OUTPUT';
				EXECUTE sp_executesql @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;
				
				IF @debugMode = 1 AND @containsLOB > 0 AND @onlineRebuild = 1
				RAISERROR('    Online rebuild not possible on indexes with LOBs in INCLUDED columns...', 0, 42) WITH NOWAIT;
			END

			IF @ixtype = 1 -- Clustered and has LOBs in table?
			BEGIN
				SELECT @LOB_SQL = 'SELECT @containsLOB_OUT = COUNT(*) FROM ' + @dbName + '.sys.columns c WITH (NOLOCK)
INNER JOIN ' + @dbName + '.sys.indexes i WITH (NOLOCK) ON c.[object_id] = i.[object_id]
WHERE system_type_id IN (34, 35, 99) ' + CASE WHEN @sqlmajorver < 11 THEN 'OR max_length = -1 ' ELSE '' END +
'AND i.object_id = ' + CAST(@objectID AS NVARCHAR(10)) + ' AND i.index_id = ' + CAST(@indexID AS NVARCHAR(10)) + ';'
			/* system_type_id = 34 for IMAGE, 35 for TEXT, 99 for NTEXT,
				max_length = -1 for VARBINARY(MAX), VARCHAR(MAX), NVARCHAR(MAX), XML */								
				,@LOB_SQL_Param = '@containsLOB_OUT int OUTPUT';
				EXECUTE sp_executesql @LOB_SQL, @LOB_SQL_Param, @containsLOB_OUT = @containsLOB OUTPUT;
				
				IF @debugMode = 1 AND @containsLOB > 0 AND @onlineRebuild = 1
				RAISERROR('    Online rebuild not possible on clustered index when certain LOBs exist in table...', 0, 42) WITH NOWAIT;
			END
			
			IF @debugMode = 1 AND (@sqlmajorver >= 11 OR @ixtype IN (5,6))
			RAISERROR('  Checking for Columnstore index...', 0, 42) WITH NOWAIT;
			
			SET @containsColumnstore = 0
			
			IF @ixtype NOT IN (5,6) -- Not already in the scope of a Columnstore index
				AND @sqlmajorver >= 11 -- Parent table has Columnstore indexes?
			BEGIN
				SELECT @CStore_SQL = 'SELECT @containsColumnstore_OUT = COUNT(*) FROM ' + @dbName + '.sys.indexes i WITH (NOLOCK) WHERE i.object_id = ' + CAST(@objectID AS NVARCHAR(10)) + ' AND i.type IN (5,6);'							
					,@CStore_SQL_Param = '@containsColumnstore_OUT int OUTPUT';
				EXECUTE sp_executesql @CStore_SQL, @CStore_SQL_Param, @containsColumnstore_OUT = @containsColumnstore OUTPUT;
				
				IF @debugMode = 1 AND @containsColumnstore > 0 AND @onlineRebuild = 1
				RAISERROR('    Online rebuild not possible when parent table has Columnstore index...', 0, 42) WITH NOWAIT;
			END
			
			IF @ixtype IN (5,6)
			BEGIN
				SET @containsColumnstore = 1
				
				IF @debugMode = 1 AND @containsColumnstore > 0 AND @onlineRebuild = 1
				RAISERROR('    Online rebuild not possible on Columnstore indexes...', 0, 42) WITH NOWAIT;
			END
			
			IF @debugMode = 1
			RAISERROR('  Checking if index does not allow page locks...', 0, 42) WITH NOWAIT;

			/* Determine if page locks are not allowed; these must always rebuild; if @forceRescan = 0 then always check in real time in case it has changed*/	
			IF @forceRescan = 0
			BEGIN		
				SELECT @allowPageLockSQL = 'SELECT @allowPageLocks_OUT = allow_page_locks FROM ' + @dbName + '.sys.indexes WHERE [object_id] = ' + CAST(@objectID AS NVARCHAR(10)) + ' AND [index_id] = ' + CAST(@indexID AS NVARCHAR(10)) + ';'
					,@allowPageLockSQL_Param = '@allowPageLocks_OUT bit OUTPUT';
				EXECUTE sp_executesql @allowPageLockSQL, @allowPageLockSQL_Param, @allowPageLocks_OUT = @allowPageLocks OUTPUT;
			END
			ELSE
			BEGIN
				SELECT @allowPageLocks = [allow_page_locks] FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE objectID = @objectID AND indexID = @indexID AND [dbID] = @dbID	
			END
			
			IF @debugMode = 1 AND @allowPageLocks = 0
			RAISERROR('    Index does not allow page locks...', 0, 42) WITH NOWAIT;

			IF @debugMode = 1
			BEGIN
				SELECT @debugMessage = '    Found ' + CONVERT(NVARCHAR(10), @fragmentation) + ' percent fragmentation on index ' + @indexName + '...';
				RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
			END
			
			IF @debugMode = 1
			RAISERROR('  Building SQL statements...', 0, 42) WITH NOWAIT;

			/* If there's not a lot of fragmentation, or if we have a LOB, we should reorganize.
			Filtered indexes or indexes that do not allow page locks should always rebuild. */
			IF (@fragmentation < @rebuildThreshold AND @ixtype IN (1,2) AND @has_filter = 0 AND @allowPageLocks = 1)
				OR (@fragmentation < @rebuildThreshold_cs AND @ixtype IN (5,6))
			BEGIN		
				SET @operationFlag = 0	

				/* Set Reorg command */
				SET @sqlcommand = N'ALTER INDEX ' + @indexName + N' ON ' + @dbName + N'.' + @schemaName + N'.' + @objectName + N' REORGANIZE';

				/* Set partition reorg options; requires Enterprise Edition; valid only if more than one partition exists */		
				IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1	
				SET @sqlcommand = @sqlcommand + N' PARTITION = ' + CAST(@partitionNumber AS NVARCHAR(10));
				
				/* Set LOB reorg options; valid only if no more than one partition exists */		
				IF @dealLOB = 1 AND @partitionCount = 1 AND @ixtype IN (1,2)
				SET @sqlcommand = @sqlcommand + N' WITH (LOB_COMPACTION = OFF)';
				
				IF @dealLOB = 0 AND @partitionCount = 1 AND @ixtype IN (1,2) 
				SET @sqlcommand = @sqlcommand + N' WITH (LOB_COMPACTION = ON)';
				
				/* Set Columnstore reorg option to compress all rowgroups, and not just closed ones */		
				IF @sqlmajorver >= 12 AND @dealROWG = 1 AND @ixtype IN (5,6) 
				SET @sqlcommand = @sqlcommand + N' WITH (COMPRESS_ALL_ROW_GROUPS = ON)';
				
				SET @sqlcommand = @sqlcommand + N';';
			END
			/* If the index is heavily fragmented and doesn't contain any partitions,
			or if the index does not allow page locks, or if it is a filtered index, rebuild it */
			ELSE IF ((@fragmentation >= @rebuildThreshold AND @ixtype IN (1,2)) OR @rebuildThreshold = 0)
				OR ((@fragmentation >= @rebuildThreshold_cs AND @ixtype IN (5,6)) OR @rebuildThreshold_cs = 0)
				OR @has_filter = 1 OR @allowPageLocks = 0
			BEGIN			
				SET @rebuildcommand = N' REBUILD'
				SET @operationFlag = 1

				/* Set partition rebuild options; requires Enterprise Edition; valid only if more than one partition exists */		
				IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1	
				SET @rebuildcommand = @rebuildcommand + N' PARTITION = ' + CAST(@partitionNumber AS NVARCHAR(10));
				--ELSE IF @dealMaxPartition IS NULL AND @editionCheck = 1 AND @partitionCount > 1		
				--SET @rebuildcommand = @rebuildcommand + N' PARTITION = ALL';

				/* Disallow disabling indexes on partitioned tables when defraging a subset of existing partitions */		
				IF @dealMaxPartition IS NOT NULL AND @partitionCount > 1	
				SET @disableNCIX = 0
				
				/* Set defrag options*/
				SET @rebuildcommand = @rebuildcommand + N' WITH ('
				
				/* Set index pad options; not compatible with partition operations */
				IF @is_padded = 1 AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1))
				SET @rebuildcommand = @rebuildcommand + N'PAD_INDEX = ON, '
				
				/* Sets specific compression options for indexes */
				IF @dataCompression IN ('NONE','PAGE','ROW') 
					AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1))
					AND @ixtype IN (1,2)
					AND (@sqlmajorver > 13 OR (@sqlmajorver = 13 AND @sqlbuild >= 4001) OR @editionCheck = 1) -- SQL 2016 SP1 or higher	for compression in non-EE
				SET @rebuildcommand = @rebuildcommand + N'DATA_COMPRESSION = ' + @dataCompression + ', '
				
				IF @dataCompression IS NULL 
					AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1))
					AND @ixtype IN (1,2)
					AND (@sqlmajorver > 13 OR (@sqlmajorver = 13 AND @sqlbuild >= 4001) OR @editionCheck = 1) -- SQL 2016 SP1 or higher	for compression in non-EE
				SET @rebuildcommand = @rebuildcommand + N'DATA_COMPRESSION = ' + @currCompression + ', '
				
				IF @dataCompression IN ('NONE','PAGE','ROW') AND @ixtype IN (1,2)
					AND @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
				SET @rebuildcommand = @rebuildcommand + N'DATA_COMPRESSION = ' + @dataCompression + ' ON PARTITIONS (' + CAST(@partitionNumber AS NVARCHAR(10)) + '), '

				IF @dataCompression IS NULL AND @ixtype IN (1,2)
					AND @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
				SET @rebuildcommand = @rebuildcommand + N'DATA_COMPRESSION = ' + @currCompression + ' ON PARTITIONS (' + CAST(@partitionNumber AS NVARCHAR(10)) + '), '

				/* Set online rebuild options; requires Enterprise Edition; not compatible with partition operations, Columnstore indexes in table and XML or Spatial indexes.
				Up to SQL Server 2008R2, not compatible with clustered indexes with LOB columns in table or non-clustered indexes with LOBs in INCLUDED columns.
				In SQL Server 2012, not compatible with clustered indexes with LOB columns in table.*/		
				IF @sqlmajorver <= 11 AND @onlineRebuild = 1 AND @editionCheck = 1
					AND @ixtype IN (1,2) AND @containsLOB = 0
					AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1))	
				SET @rebuildcommand = @rebuildcommand + N'ONLINE = ON, ';
				
				/* Set online rebuild options; requires Enterprise Edition; not compatible with partition operations, Columnstore indexes in table and XML or Spatial indexes.
				In SQL Server 2014, not compatible with clustered indexes with LOB columns in table, but compatible with partition operations.
				Also, we can use Lock Priority with online indexing. */	
				IF @sqlmajorver > 11 AND @onlineRebuild = 1 AND @editionCheck = 1
					AND @ixtype IN (1,2) AND @containsLOB = 0
				SELECT @rebuildcommand = @rebuildcommand + N'ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = ' + CONVERT(NVARCHAR(15), @onlinelocktimeout) + ', ABORT_AFTER_WAIT = ' + CASE WHEN @abortAfterwait = 0 THEN 'BLOCKERS' WHEN @abortAfterwait = 1 THEN 'SELF' ELSE 'NONE' END + ')), '

				/* Set fill factor operation preferences; not compatible with partition operations and Columnstore indexes */		
				IF @fillfactor = 1 AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1)) AND @ixtype IN (1,2) 		
				SET @rebuildcommand = @rebuildcommand + N'FILLFACTOR = ' + CONVERT(NVARCHAR, CASE WHEN @fill_factor = 0 THEN 100 ELSE @fill_factor END) + N', ';

				IF @fillfactor = 0 AND (@dealMaxPartition IS NULL OR (@dealMaxPartition IS NOT NULL AND @partitionCount = 1)) AND @ixtype IN (1,2)		
				SET @rebuildcommand = @rebuildcommand + N'FILLFACTOR = 100, ';

				/* Resumable requires an ONLINE rebuild and version >= SQL Server 2017 */
				IF @sqlmajorver >= 14 AND @onlineRebuild = 1 AND @resumableRebuild = 1
				SET @rebuildcommand = @rebuildcommand + N'RESUMABLE = ON, ';	

				/* Set sort operation preferences */
				IF @sortInTempDB = 1 AND @ixtype IN (1,2)
				SET @rebuildcommand = @rebuildcommand + N'SORT_IN_TEMPDB = ON, ';
				IF @sortInTempDB = 0 AND @ixtype IN (1,2)		
				SET @rebuildcommand = @rebuildcommand + N'SORT_IN_TEMPDB = OFF, ';

				/* Set NO_RECOMPUTE preference */
				IF @ix_statsnorecompute = 1 AND @ixtype IN (1,2)
				SET @sqlcommand = @sqlcommand + N' STATISTICS_NORECOMPUTE = ON, ';
				IF @ix_statsnorecompute = 0 AND @ixtype IN (1,2)
				SET @sqlcommand = @sqlcommand + N' STATISTICS_NORECOMPUTE = OFF, ';

				/* Set processor restriction options; requires Enterprise Edition */		
				IF @maxDopRestriction IS NOT NULL AND @editionCheck = 1		
				SET @rebuildcommand = @rebuildcommand + N'MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3)) + N');';
				ELSE		
				SET @rebuildcommand = @rebuildcommand + N');';

				IF @rebuildcommand LIKE '% WITH ();'
				SET @rebuildcommand = REPLACE(@rebuildcommand, ' WITH ()', '')

				/* Set NCIX disable command, except for clustered index*/
				SET @sqldisablecommand = NULL
				IF @disableNCIX = 1 AND @ixtype = 2 AND @is_primary_key = 0
				BEGIN
					SET @sqldisablecommand = N'ALTER INDEX ' + @indexName + N' ON ' + @dbName + N'.' + @schemaName + N'.' + @objectName + ' DISABLE;';
				END

				/* Set update statistics command for index only, before rebuild, as rebuild performance is dependent on statistics (only working on non-partitioned tables)
				http://blogs.msdn.com/b/psssql/archive/2009/03/18/be-aware-of-parallel-index-creation-performance-issues.aspx */
				SET @sqlprecommand = NULL
				
				/* Is stat incremental? */
				SELECT TOP 1 @stats_isincremental = [is_incremental] FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working 
				WHERE dbName = @dbName AND schemaName = @schemaName AND objectName = @objectName AND statsName = @indexName;

				/* Are there paused index operations? */
				DECLARE @sqlcmdRI NVARCHAR(100), @paramsRI NVARCHAR(50), @HasRI int
				SET @HasRI = 0
				IF @sqlmajorver > 14
				BEGIN
					SET @sqlcmdRI = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @HasRI_OUT = COUNT(*) FROM sys.index_resumable_operations'
					SET @paramsRI = N'@HasRI_OUT int OUTPUT'
				
					EXECUTE sp_executesql @sqlcmdRI, @paramsRI, @HasRI_OUT = @HasRI OUTPUT
				END;
				
				IF @HasRI > 0
				BEGIN
					IF @debugMode = 1
					RAISERROR('    Found ongoing resumable index operations - skipping all pre-commands...', 0, 42) WITH NOWAIT;
					
					SET @sqlprecommand = N''
				END
				ELSE IF (@sqlmajorver < 13 OR @partitionCount = 1) AND @sqldisablecommand IS NULL AND @ixtype IN (1,2)
				BEGIN
					SET @sqlprecommand = N'UPDATE STATISTICS ' + @dbName + N'.' + @schemaName + N'.' + @objectName + N' (' + @indexName + N')'
					
					/* Set processor restriction options */		
					IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
					SET @sqlprecommand = @sqlprecommand + N' WITH MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3)) + N'; ';
					ELSE		
					SET @sqlprecommand = @sqlprecommand + N'; ';
				END
				ELSE IF @sqlmajorver >= 13 AND @partitionCount > 1 AND @stats_isincremental = 1 AND @sqldisablecommand IS NULL AND @ixtype IN (1,2)
				BEGIN
					SET @sqlprecommand = N'UPDATE STATISTICS ' + @dbName + N'.' + @schemaName + N'.' + @objectName + N' (' + @indexName + N') WITH RESAMPLE ON PARTITIONS(' + CONVERT(NVARCHAR(10), @partitionNumber) + N')'
					
					/* Set processor restriction options */		
					IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
					SET @sqlprecommand = @sqlprecommand + N' WITH MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3)) + N'; ';
					ELSE					
					SET @sqlprecommand = @sqlprecommand + N'; '
				END
				
				/* Set Rebuild command */
				SET @sqlcommand = N'ALTER INDEX ' + @indexName + N' ON ' + @dbName + N'.' + @schemaName + N'.' + @objectName + REPLACE(@rebuildcommand,', )', ')');
				
				/* For offline rebuilds, set lock timeout if not default */
				IF @onlineRebuild = 0 AND @offlinelocktimeout > -1 AND @offlinelocktimeout IS NOT NULL
				SET @sqlcommand = 'SET LOCK_TIMEOUT ' + CONVERT(NVARCHAR(15), @offlinelocktimeout) + '; ' + @sqlcommand
			END
			ELSE
			BEGIN
				/* Print an error message if any indexes happen to not meet the criteria above */		
				IF @debugMode = 1
				BEGIN
					SET @debugMessage = 'We are unable to defrag index ' + @indexName + N' on table ' + @dbName + N'.' + @schemaName + N'.' + @objectName
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END
			END;

			IF @operationFlag = 0 AND @sqlprecommand IS NOT NULL
			SET @sqlprecommand = NULL

			IF @operationFlag = 0 AND @sqldisablecommand IS NOT NULL
			SET @sqldisablecommand = NULL
					
			/* Are we executing the SQL? If so, do it */
			IF @Exec_Print = 1
			BEGIN
				/* Get the time for logging purposes */		
				SET @dateTimeStart = GETDATE();

				/* Start log actions */
				IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
				BEGIN
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_log (dbID, dbName, objectID, objectName, indexID, indexName, partitionNumber, fragmentation, page_count, range_scan_count, fill_factor, dateTimeStart, sqlStatement)		
					SELECT @dbID, @dbName, @objectID, @objectName, @indexID, @indexName, @partitionNumber, @fragmentation, @pageCount, @range_scan_count, @fill_factor, @dateTimeStart, ISNULL(@sqlprecommand, '') + @sqlcommand;
				END
				ELSE
				BEGIN
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_log (dbID, dbName, objectID, objectName, indexID, indexName, partitionNumber, fragmentation, page_count, range_scan_count, fill_factor, dateTimeStart, sqlStatement)		
					SELECT @dbID, @dbName, @objectID, @objectName, @indexID, @indexName, 1, @fragmentation, @pageCount, @range_scan_count, @fill_factor, @dateTimeStart, ISNULL(@sqlprecommand, '') + @sqlcommand;
				END
				
				SET @indexDefrag_id = SCOPE_IDENTITY();
				
				IF @sqlprecommand IS NULL AND @sqldisablecommand IS NULL
				BEGIN
					SET @debugMessage = '     ' + @sqlcommand;
				END
				ELSE IF @sqlprecommand IS NOT NULL AND @sqldisablecommand IS NULL
				BEGIN
					SET @debugMessage = '     ' + @sqlprecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				ELSE IF @sqlprecommand IS NULL AND @sqldisablecommand IS NOT NULL
				BEGIN
					SET @debugMessage = '     ' + @sqldisablecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				ELSE IF @sqlprecommand IS NOT NULL AND @sqldisablecommand IS NOT NULL
				BEGIN
					SET @debugMessage = '     ' + @sqldisablecommand + CHAR(10) + '     ' + @sqlprecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				
				/* Print the commands we'll be executing, if specified to do so */				
				IF (@debugMode = 1 OR @printCmds = 1) AND @sqlcommand IS NOT NULL
				BEGIN
					RAISERROR('  Printing SQL statements...', 0, 42) WITH NOWAIT;
					SET @debugMessage = '   Executing: ' + CHAR(10) + @debugMessage;
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END;				

				/* Execute default update stats on index only. With better stats, index rebuild process will generally have better performance */
				IF @operationFlag = 1
				BEGIN
					BEGIN TRY					
						EXECUTE sp_executesql @sqlprecommand;
						SET @sqlprecommand = NULL
						SET @dateTimeEnd = GETDATE();
					
						-- /* Update log with completion time */ --> if logged here, completion time after actual rebuild is not logged	
						-- UPDATE dbo.tbl_AdaptiveIndexDefrag_log	
						-- SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)
						-- WHERE indexDefrag_id = @indexDefrag_id AND dateTimeEnd IS NULL;
						
						/* If rebuilding, update statistics log with completion time */
						IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
						BEGIN
							INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], [rows_sampled], [modification_counter], [no_recompute], dateTimeStart, dateTimeEnd, durationSeconds, sqlStatement)		
							SELECT @dbID, @dbName, @objectID, @objectName, statsID, statsName, @partitionNumber, -1, -1, -1, [no_recompute], @dateTimeStart, @dateTimeEnd, DATEDIFF(second, @dateTimeStart, @dateTimeEnd), @sqlcommand
							FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
							WHERE objectID = @objectID AND dbID = @dbID
								AND statsName = @indexName
								AND ((@Exec_Print = 1 AND updateDate IS NULL) OR (@Exec_Print = 0 AND updateDate IS NULL AND printStatus = 0));
						END
						ELSE
						BEGIN
							INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], [rows_sampled], [modification_counter],[no_recompute], dateTimeStart, dateTimeEnd, durationSeconds, sqlStatement)		
							SELECT @dbID, @dbName, @objectID, @objectName, statsID, statsName, 1, -1, -1, -1, [no_recompute], @dateTimeStart, @dateTimeEnd, DATEDIFF(second, @dateTimeStart, @dateTimeEnd), @sqlcommand
							FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
							WHERE objectID = @objectID AND dbID = @dbID
								AND statsName = @indexName
								AND ((@Exec_Print = 1 AND updateDate IS NULL) OR (@Exec_Print = 0 AND updateDate IS NULL AND printStatus = 0));
						END
					END TRY
					BEGIN CATCH						
						/* Update log with error message */	
						UPDATE dbo.tbl_AdaptiveIndexDefrag_log	
						SET dateTimeEnd = GETDATE(), durationSeconds = -1, errorMessage = 'Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing the pre-command for index ' + @indexName +'. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
						WHERE indexDefrag_id = @indexDefrag_id AND dateTimeEnd IS NULL;

						IF @debugMode = 1
						BEGIN
							SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing the pre-command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
							RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
							--RAISERROR('     An error has occurred executing the pre-command! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 0, 42) WITH NOWAIT;
						END
					END CATCH
				END;

				/* Execute NCIX disable command */
				IF @operationFlag = 1 AND @disableNCIX = 1 AND @indexID > 1 AND (@sqldisablecommand IS NOT NULL OR LEN(@sqldisablecommand) > 0)
				BEGIN
					BEGIN TRY
						EXECUTE sp_executesql @sqldisablecommand;
						/* Insert into working table for disabled state control */
						INSERT INTO dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus (dbID, objectID, indexID, [is_disabled], dateTimeChange)
						SELECT @dbID, @objectID, @indexID, 1, GETDATE()
					END TRY
					BEGIN CATCH						
						/* Delete from working table for disabled state control */
						DELETE FROM dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus
						WHERE dbID = @dbID AND objectID = @objectID AND indexID = @indexID;

						IF @debugMode = 1
						BEGIN
							SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing the disable index command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
							RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
							--RAISERROR('     An error has occurred executing the disable index command! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 0, 42) WITH NOWAIT;
						END
					END CATCH
				END;
				
				/* Execute defrag! */		
				BEGIN TRY
					EXECUTE sp_executesql @sqlcommand;
					SET @dateTimeEnd = GETDATE();
					
					UPDATE dbo.tbl_AdaptiveIndexDefrag_log	
					/* Update log with completion time */	
					SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)
					WHERE indexDefrag_id = @indexDefrag_id AND dateTimeEnd IS NULL;
					
					IF @operationFlag = 1 AND @disableNCIX = 1 AND @indexID > 1
					BEGIN
						/* Delete from working table for disabled state control */
						DELETE FROM dbo.tbl_AdaptiveIndexDefrag_IxDisableStatus
						WHERE dbID = @dbID AND objectID = @objectID AND indexID = @indexID;
					END;
				END TRY		
				BEGIN CATCH						
					/* Update log with error message */	
					UPDATE dbo.tbl_AdaptiveIndexDefrag_log	
					SET dateTimeEnd = GETDATE(), durationSeconds = -1, errorMessage = 'Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'	
					WHERE indexDefrag_id = @indexDefrag_id AND dateTimeEnd IS NULL;

					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
						--RAISERROR('     An error has occurred executing this command! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 0, 42) WITH NOWAIT;
					END
				END CATCH

				/* Update working table and resume loop */
				IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Working	
					SET defragDate = ISNULL(@dateTimeEnd, GETDATE()), printStatus = 1	
					WHERE dbID = @dbID AND objectID = @objectID	AND indexID = @indexID AND partitionNumber = @partitionNumber;
				END
				ELSE
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Working
					SET defragDate = ISNULL(@dateTimeEnd, GETDATE()), printStatus = 1
					WHERE dbID = @dbID AND objectID = @objectID	AND indexID = @indexID;
				END

				IF @operationFlag = 1
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working
					SET updateDate = ISNULL(@dateTimeEnd, GETDATE()), printStatus = 1
					WHERE objectID = @objectID AND dbID = @dbID AND statsName = @indexName;
				END
				
				/* Just a little breather for the server */		
				WAITFOR DELAY @defragDelay;
			END;
			ELSE IF @Exec_Print = 0
			BEGIN
				IF @operationFlag = 0 AND @sqlprecommand IS NOT NULL
				SET @sqlprecommand = NULL
				
				IF @sqlprecommand IS NULL AND (@sqldisablecommand IS NULL OR @sqldisablecommand = '')
				BEGIN
					SET @debugMessage = '     ' + @sqlcommand;
				END
				ELSE IF @sqlprecommand IS NOT NULL AND (@sqldisablecommand IS NULL OR @sqldisablecommand = '')
				BEGIN
					SET @debugMessage = '     ' + @sqlprecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				ELSE IF @sqlprecommand IS NULL AND (@sqldisablecommand IS NOT NULL OR LEN(@sqldisablecommand) > 0)
				BEGIN
					SET @debugMessage = '     ' + @sqldisablecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				ELSE IF @sqlprecommand IS NOT NULL AND (@sqldisablecommand IS NOT NULL OR LEN(@sqldisablecommand) > 0)
				BEGIN
					SET @debugMessage = '     ' + @sqldisablecommand + CHAR(10) + '     ' + @sqlprecommand + CHAR(10) + '     ' + @sqlcommand;
				END;
				
				/* Print the commands we're executing if specified to do so */				
				IF (@debugMode = 1 OR @printCmds = 1) AND @sqlcommand IS NOT NULL
				BEGIN
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END
				
				/* Update working table and resume loop */
				IF @partitionCount > 1 AND @dealMaxPartition IS NOT NULL AND @editionCheck = 1
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Working		
					SET printStatus = 1	
					WHERE dbID = @dbID AND objectID = @objectID	AND indexID = @indexID AND partitionNumber = @partitionNumber;
				END
				ELSE
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Working		
					SET printStatus = 1	
					WHERE dbID = @dbID AND objectID = @objectID	AND indexID = @indexID;
				END
				
				IF @operationFlag = 1
				BEGIN
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
					SET printStatus = 1		
					WHERE objectID = @objectID AND dbID = @dbID AND statsName = @indexName;
				END;
			END;
			
			IF @operationFlag = 0 AND @updateStats = 1 -- When reorganizing, update stats afterwards
				AND @updateStatsWhere = 0 AND @ixtype NOT IN (5,6,7)
			BEGIN
				IF @debugMode = 1	
				RAISERROR('   Updating index related statistics using finer thresholds (if any)...', 0, 42) WITH NOWAIT;
				
				/* Handling index related statistics */
				IF @debugMode = 1
				RAISERROR('   Selecting a statistic to update...', 0, 42) WITH NOWAIT;
				
				/* Select the stat */
				BEGIN TRY
					SET @getStatSQL = N'SELECT TOP 1 @statsID_Out = idss.statsID FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss WHERE idss.updateDate IS NULL ' + CASE WHEN @Exec_Print = 0 THEN 'AND idss.printStatus = 0 ' ELSE '' END + ' AND idss.[dbID] = ' + CONVERT(NVARCHAR, @dbID) + ' AND idss.statsName = ''' + @indexName + '''' + ' AND idss.objectID = ' + CONVERT(NVARCHAR, @objectID) + ' AND EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.defragDate IS NOT NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)';
					SET @getStatSQL_Param = N'@statsID_Out int OUTPUT'
					EXECUTE sp_executesql @getStatSQL, @getStatSQL_Param, @statsID_Out = @statsID OUTPUT;
					
					SET @statsName = @indexName
				END TRY
				BEGIN CATCH						
					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while determining which statistic to update. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
				END CATCH
				
				IF @debugMode = 1
				RAISERROR('   Getting information on selected statistic...', 0, 42) WITH NOWAIT;

				/* Get object name and auto update setting */
				SELECT TOP 1 @statsName = statsName, @partitionNumber = partitionNumber, @stats_norecompute = [no_recompute], @stats_isincremental = [is_incremental]
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
				WHERE objectID = @objectID AND statsID = @statsID AND [dbID] = @dbID;

				IF @debugMode = 1
				BEGIN
					SET @debugMessage = '   Determining modification row counter for statistic ' + @statsName + ' on table or view ' + @objectName + ' of DB ' + @dbName + '...';
					
					IF @debugMessage IS NOT NULL
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END;

				/* Determine modification row counter to ascertain if update stats is required */
				IF ((@sqlmajorver = 12 AND @sqlbuild >= 5000) OR (@sqlmajorver = 13 AND @sqlbuild >= 4000) OR @sqlmajorver > 13) AND ISNULL(@stats_isincremental,1) = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE')
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_incremental_stats_properties DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_incremental_stats_properties(@statsobjectID_In, @statsID_In) WHERE partition_number = @partitionNumber_In;'
				END
				ELSE IF ((@sqlmajorver = 12 AND @sqlbuild < 5000) OR (@sqlmajorver = 13 AND @sqlbuild < 4000)) AND ISNULL(@stats_isincremental,1) = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE')
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_stats_properties_internal DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_stats_properties_internal(@statsobjectID_In, @statsID_In) WHERE partition_number = @partitionNumber_In;'
				END
				ELSE IF ((@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4000) OR (@sqlmajorver = 11 AND @sqlbuild >= 3000) OR @sqlmajorver >= 12) AND (ISNULL(@stats_isincremental,1) = 0 OR UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1)
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_stats_properties DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_stats_properties(@statsobjectID_In, @statsID_In);'
				END
				ELSE
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.sysindexes...', 0, 42) WITH NOWAIT;
					SELECT TOP 1 @surrogateStatsID = indexID FROM dbo.tbl_AdaptiveIndexDefrag_Working (NOLOCK) WHERE objectID = @statsobjectID AND indexName = @statsName 
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = SUM(ISNULL(rowmodctr,0)), @rows_Out = ISNULL(rowcnt,0), @rows_sampled_Out = -1 FROM sys.sysindexes WHERE id = @statsobjectID_In AND indid = @statsID_In AND rowmodctr > 0;'
					
					IF @statsID IS NULL
					SET @statsID = @surrogateStatsID	
				END
				SET @rowmodctrSQL_Param = N'@partitionNumber_In smallint, @statsobjectID_In int, @statsID_In int, @rowmodctr_Out bigint OUTPUT, @rows_Out bigint OUTPUT, @rows_sampled_Out bigint OUTPUT'

				BEGIN TRY
					EXECUTE sp_executesql @rowmodctrSQL, @rowmodctrSQL_Param, @statsobjectID_In = @statsobjectID, @statsID_In = @statsID, @partitionNumber_In = @partitionNumber, @rowmodctr_Out = @rowmodctr OUTPUT, @rows_Out = @rows OUTPUT, @rows_sampled_Out = @rows_sampled OUTPUT;
					SET @rowmodctr = (SELECT ISNULL(@rowmodctr, 0));
				END TRY
				BEGIN CATCH						
					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while determining row modification counter. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
				END CATCH
				
				IF @rows IS NOT NULL AND @rows > 0 
				SET @record_count = @rows

				IF @debugMode = 1
				BEGIN
					SELECT @debugMessage = '     Found a row modification counter of ' + CONVERT(NVARCHAR(15), @rowmodctr) + ' and ' + CONVERT(NVARCHAR(15), @record_count) + ' rows' + CASE WHEN ISNULL(@stats_isincremental,0) = 1 THEN ' on partition ' + CONVERT(NVARCHAR(15), @partitionNumber) ELSE '' END + '...';
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END

				/* Because we are reorganizing, we will update statistics if they have changed since last update with same threshold as TF2371.
				Default rules for auto update stats are:
				If the cardinality for a table is greater than 6, but less than or equal to 500, update status every 500 modifications.
				If the cardinality for a table is greater than 500, update statistics when (500 + 20 percent of the table) changes have occurred.
				Reference: http://docs.microsoft.com/sql/relational-databases/statistics/statistics and http://support.microsoft.com/kb/195565
				*/
				IF (@statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.001 AND 100.0 AND @statsMinRows IS NULL AND (@rowmodctr*100)/@record_count >= @statsThreshold)
					OR (@statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.001 AND 100.0 AND @statsMinRows IS NOT NULL AND @record_count >= @statsMinRows AND (@rowmodctr*100)/@record_count >= @statsThreshold)
					OR (@statsThreshold IS NULL AND (
						(@record_count BETWEEN 6 AND 500 AND @rowmodctr >= 500) OR -- like the default
						(@record_count BETWEEN 501 AND 10000 AND (@rowmodctr >= (@record_count*20)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 20 percent or simulate TF 2371
						(@record_count BETWEEN 10001 AND 100000 AND (@rowmodctr >= (@record_count*15)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 15 percent or simulate TF 2371
						(@record_count BETWEEN 100001 AND 1000000 AND (@rowmodctr >= (@record_count*10)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 10 percent or simulate TF 2371
						(@record_count >= 1000001 AND (@rowmodctr >= (@record_count*5)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) -- 500 + 5 percent or simulate TF 2371
					))
				BEGIN
					SET @sqlcommand2 = N'UPDATE STATISTICS ' + @dbName + N'.'+ @schemaName + N'.' + @objectName + N' (' + @statsName + N')'
					IF UPPER(@statsSample) = 'FULLSCAN' AND (@partitionNumber = 1 OR @partitionNumber = @maxpartitionNumber)
					SET @sqlcommand2 = @sqlcommand2 + N' WITH FULLSCAN'
					IF ISNUMERIC(@statsSample) = 1 AND (@partitionNumber = 1 OR @partitionNumber = @maxpartitionNumber)
					SET @sqlcommand2 = @sqlcommand2 + N' WITH SAMPLE ' + @statsSample + ' PERCENT'
					IF UPPER(@statsSample) = 'RESAMPLE'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH RESAMPLE'
					
					IF (UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1) AND @persistStatsSample = 1 
						AND UPPER(@sqlcommand2) LIKE '%WITH%' AND @sqlmajorver = 13 AND @sqlbuild >= 4446
					SET @sqlcommand2 = @sqlcommand2 + N', PERSIST_SAMPLE_PERCENT = ON'
					IF (UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1) AND @persistStatsSample = 0 
						AND UPPER(@sqlcommand2) LIKE '%WITH%' AND @sqlmajorver = 13 AND @sqlbuild >= 4446
					SET @sqlcommand2 = @sqlcommand2 + N', PERSIST_SAMPLE_PERCENT = OFF'

					IF @partitionCount > 1 AND @stats_isincremental = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE') AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ON PARTITIONS(' + CONVERT(NVARCHAR(10), @partitionNumber) + N');'
					ELSE IF @partitionCount > 1 AND @stats_isincremental = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE') AND UPPER(@sqlcommand2) NOT LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH RESAMPLE ON PARTITIONS(' + CONVERT(NVARCHAR(10), @partitionNumber) + N')'
					
					IF @stats_norecompute = 1 AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ,NORECOMPUTE'
					ELSE IF @stats_norecompute = 1 AND @sqlcommand2 NOT LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH NORECOMPUTE'
					
					IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
						AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ,MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3));
					ELSE IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
						AND UPPER(@sqlcommand2) NOT LIKE '%WITH%'	
					SET @sqlcommand2 = @sqlcommand2 + N' WITH MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3));
					
					/* For list of incremental stats unsupported scenarios check http://docs.microsoft.com/sql/t-sql/statements/update-statistics-transact-sql */
					IF @partitionCount > 1 AND @statsIncremental = 1 AND @has_filter = 0
					BEGIN
						IF UPPER(@sqlcommand2) LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N' ,INCREMENTAL = ON'
						ELSE IF UPPER(@sqlcommand2) NOT LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N'WITH INCREMENTAL = ON'
					END
					ELSE IF @statsIncremental = 0
					BEGIN
						IF UPPER(@sqlcommand2) LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N', INCREMENTAL = OFF'
						ELSE IF UPPER(@sqlcommand2) NOT LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N'WITH INCREMENTAL = OFF'
					END
				
					SET @sqlcommand2 = @sqlcommand2 + N';'
				END
				ELSE
				BEGIN
					SET @sqlcommand2 = NULL
				END

				/* Are we executing the SQL? If so, do it */
				IF @Exec_Print = 1 AND @sqlcommand2 IS NOT NULL
				BEGIN
					SET @debugMessage = '     ' + @sqlcommand2;

					/* Print the commands we'll be executing, if specified to do so */		
					IF (@printCmds = 1 OR @debugMode = 1)	
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

					/* Get the time for logging purposes */		
					SET @dateTimeStart = GETDATE();

					/* Log actions */		
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], rows_sampled, modification_counter, [no_recompute], dateTimeStart, sqlStatement)		
					SELECT @dbID, @dbName, @objectID, @objectName, @statsID, @statsName, @partitionNumber, @record_count, @rows_sampled, @rowmodctr, @stats_norecompute, @dateTimeStart, @sqlcommand2;

					SET @statsUpdate_id = SCOPE_IDENTITY();

					/* Wrap execution attempt in a TRY/CATCH and log any errors that occur */		
					IF @operationFlag = 0
					BEGIN	
						BEGIN TRY				
							/* Execute update! */
							EXECUTE sp_executesql @sqlcommand2;
							SET @dateTimeEnd = GETDATE();
							SET @sqlcommand2 = NULL

							/* Update log with completion time */
							UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_log
							SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)										
							WHERE statsUpdate_id = @statsUpdate_id AND partitionNumber = @partitionNumber AND dateTimeEnd IS NULL;
							
							/* Update working table */
							UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
							SET updateDate = GETDATE(), printStatus = 1		
							WHERE dbID = @dbID AND objectID = @objectID AND statsID = @statsID AND partitionNumber = @partitionNumber;
						END TRY	
						BEGIN CATCH	
							/* Update log with error message */
							UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_log
							SET dateTimeEnd = GETDATE(), durationSeconds = -1, errorMessage = 'Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'										
							WHERE statsUpdate_id = @statsUpdate_id AND partitionNumber = @partitionNumber AND dateTimeEnd IS NULL;

							/* Update working table */
							UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
							SET updateDate = GETDATE(), printStatus = 1		
							WHERE dbID = @dbID AND objectID = @objectID AND statsID = @statsID AND partitionNumber = @partitionNumber;

							IF @debugMode = 1
							BEGIN
								SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
								RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
								--RAISERROR('     An error has occurred executing this command. Please review the tbl_AdaptiveIndexDefrag_Stats_log table for details.', 0, 42) WITH NOWAIT;
							END
						END CATCH	
					END
				END
				ELSE IF @Exec_Print = 1 AND @sqlcommand2 IS NULL
				BEGIN
					IF @debugMode = 1
					BEGIN
						SELECT @debugMessage = '     No need to update statistic ' + @statsName + ' on table or view ' + @objectName + ' of DB ' + @dbName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					IF @printCmds = 1 AND @debugMode = 0
					BEGIN
						 SELECT @debugMessage = '     -- No need to update statistic ' + @statsName + ' on table or view ' + @objectName + ' of DB ' + @dbName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						 RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					/* Update working table */
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
					SET updateDate = GETDATE(), printStatus = 1	
					WHERE dbID = @dbID AND objectID = @objectID AND statsID = @statsID AND partitionNumber = @partitionNumber;
					
					/* Log actions */		
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], rows_sampled, modification_counter, [no_recompute], dateTimeStart, dateTimeEnd, durationSeconds, sqlStatement)		
					SELECT @dbID, @dbName, @objectID, @objectName, @statsID, @statsName, @partitionNumber, @record_count, ISNULL(@rows_sampled,-1), @rowmodctr, @stats_norecompute, @dateTimeStart, @dateTimeStart, -1, @sqlcommand2;
				END
				ELSE IF @Exec_Print = 0
				BEGIN
					IF @debugMode = 1 AND @sqlcommand2 IS NULL
					BEGIN
						SET @debugMessage = '     No need to update statistic ' + @statsName + ' on table or view ' + @objectName + ' of DB ' + @dbName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
					
					/* Print the commands we're executing if specified to do so */
					IF (@printCmds = 1 OR @debugMode = 1) AND @sqlcommand2 IS NOT NULL
					BEGIN
						SET @debugMessage = '     ' + @sqlcommand2;
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					IF @printCmds = 1 AND @debugMode = 0 AND @sqlcommand2 IS NULL
					BEGIN
						SET @debugMessage = '     -- No need to update statistic ' + @statsName + ' on table or view ' + @objectName + ' of DB ' + @dbName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					/* Update working table */
					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working
					SET printStatus = 1
					WHERE dbID = @dbID AND objectID = @objectID AND statsID = @statsID AND partitionNumber = @partitionNumber;
				END
			END
		END;

		/* Handling all the other statistics not covered before*/	
		IF @updateStats = 1 -- When reorganizing, update stats afterwards
			AND @updateStatsWhere = 0 -- @updateStatsWhere = 0 then table-wide statistics;
			AND (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss WHERE ((@Exec_Print = 1 AND idss.updateDate IS NULL) OR (@Exec_Print = 0 AND idss.updateDate IS NULL AND idss.printStatus = 0))) > 0 --AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)) > 0 -- If any unhandled statistics remain
		BEGIN
			IF @debugMode = 1
			RAISERROR(' Updating all other unhandled statistics using finer thresholds (if any)...', 0, 42) WITH NOWAIT;
			
			WHILE (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss WHERE ((@Exec_Print = 1 AND idss.updateDate IS NULL) OR (@Exec_Print = 0 AND idss.updateDate IS NULL AND idss.printStatus = 0))) > 0 --AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0)) > 0
			BEGIN
				/* Check to see if we need to exit loop because of our time limit */
				IF ISNULL(@endDateTime, GETDATE()) < GETDATE()
				RAISERROR('Time limit has been exceeded for this maintenance window!', 16, 42) WITH NOWAIT;

				IF @debugMode = 1
				RAISERROR('   Selecting a statistic to update...', 0, 42) WITH NOWAIT;
				
				/* Select the stat */
				IF @Exec_Print = 1
				BEGIN
					SELECT TOP 1 @statsID = idss.statsID, @dbID = idss.dbID, @statsobjectID = idss.objectID, @dbName = idss.dbName, @statsobjectName = idss.objectName, @statsschemaName = idss.schemaName, @partitionNumber = idss.partitionNumber
					FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss
					WHERE idss.updateDate IS NULL --AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0) 
				END
				ELSE IF @Exec_Print = 0
				BEGIN
					SELECT TOP 1 @statsID = idss.statsID, @dbID = idss.dbID, @statsobjectID = idss.objectID, @dbName = idss.dbName, @statsobjectName = idss.objectName, @statsschemaName = idss.schemaName, @partitionNumber = idss.partitionNumber
					FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss
					WHERE idss.updateDate IS NULL AND idss.printStatus = 0 --AND NOT EXISTS (SELECT TOP 1 objectID FROM dbo.tbl_AdaptiveIndexDefrag_Working ids WHERE ids.[dbID] = idss.[dbID] AND ids.objectID = idss.objectID AND idss.statsName = ids.indexName AND idss.updateDate IS NULL AND ids.exclusionMask & POWER(2, DATEPART(weekday, GETDATE())-1) = 0) 
				END

				/* Get stat associated table record count */
				BEGIN TRY
					SELECT @getStatSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT TOP 1 @record_count_Out = p.[rows] FROM [' + DB_NAME(@AID_dbID) + '].dbo.tbl_AdaptiveIndexDefrag_Stats_Working idss INNER JOIN sys.partitions AS p ON idss.objectID = p.[object_id] AND idss.partitionNumber = p.partition_number WHERE idss.updateDate IS NULL ' + CASE WHEN @Exec_Print = 0 THEN 'AND idss.printStatus = 0 ' ELSE '' END + ' AND idss.statsID = @statsID_In AND idss.dbID = @dbID_In AND idss.objectID = @statsobjectID_In' 
					SET @getStatSQL_Param = N'@statsID_In int, @dbID_In int, @statsobjectID_In int, @record_count_Out bigint OUTPUT'
					EXECUTE sp_executesql @getStatSQL, @getStatSQL_Param, @statsID_In = @statsID, @dbID_In = @dbID, @statsobjectID_In = @statsobjectID, @record_count_Out = @record_count OUTPUT;
				END TRY
				BEGIN CATCH						
					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while getting stat associated table row count. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
				END CATCH
				
				IF @debugMode = 1
				RAISERROR('   Getting information on selected statistic...', 0, 42) WITH NOWAIT;
				
				/* Get object name and auto update setting */
				SELECT TOP 1 @statsName = statsName, @stats_norecompute = [no_recompute], @stats_isincremental = [is_incremental]
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
				WHERE objectID = @statsobjectID AND statsID = @statsID AND [dbID] = @dbID AND partitionNumber = @partitionNumber;

				IF @debugMode = 1
				BEGIN
					SET @debugMessage = '   Determining modification row counter for statistic ' + @statsName + ' on table or view ' + @statsobjectName + ' of DB ' + @dbName + '...';
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
				END
 
				/* Determine modification row counter to ascertain if update stats is required */
				IF ((@sqlmajorver = 12 AND @sqlbuild >= 5000) OR (@sqlmajorver = 13 AND @sqlbuild >= 4000) OR @sqlmajorver > 13) AND ISNULL(@stats_isincremental,1) = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE')
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_incremental_stats_properties DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_incremental_stats_properties(@statsobjectID_In, @statsID_In) WHERE partition_number = @partitionNumber_In;'
				END
				ELSE IF ((@sqlmajorver = 12 AND @sqlbuild < 5000) OR (@sqlmajorver = 13 AND @sqlbuild < 4000)) AND ISNULL(@stats_isincremental,1) = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE')
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_stats_properties_internal DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_stats_properties_internal(@statsobjectID_In, @statsID_In) WHERE partition_number = @partitionNumber_In;'
				END
				ELSE IF ((@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4000) OR (@sqlmajorver = 11 AND @sqlbuild >= 3000) OR @sqlmajorver >= 12) AND (ISNULL(@stats_isincremental,1) = 0 OR UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1)
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.dm_db_stats_properties DMF...', 0, 42) WITH NOWAIT;
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = ISNULL(modification_counter,0), @rows_Out = ISNULL(rows,0), @rows_sampled_Out = ISNULL(rows_sampled,0) FROM sys.dm_db_stats_properties(@statsobjectID_In, @statsID_In);'
				END
				ELSE
				BEGIN
					IF @debugMode = 1
					RAISERROR('     Using sys.sysindexes...', 0, 42) WITH NOWAIT;
					SELECT TOP 1 @surrogateStatsID = indexID FROM dbo.tbl_AdaptiveIndexDefrag_Working (NOLOCK) WHERE objectID = @statsobjectID AND indexName = @statsName 
					SELECT @rowmodctrSQL = CASE WHEN @engineedition NOT IN (5, 6) THEN 'USE ' + QUOTENAME(@dbName) ELSE '' END + '; SELECT @rowmodctr_Out = SUM(ISNULL(rowmodctr,0)), @rows_Out = ISNULL(rowcnt,0), @rows_sampled_Out = -1 FROM sys.sysindexes WHERE id = @statsobjectID_In AND indid = @statsID_In AND rowmodctr > 0;'

					IF @statsID IS NULL
					SET @statsID = @surrogateStatsID
				END
				SET @rowmodctrSQL_Param = N'@partitionNumber_In smallint, @statsobjectID_In int, @statsID_In int, @rowmodctr_Out bigint OUTPUT, @rows_Out bigint OUTPUT, @rows_sampled_Out bigint OUTPUT'

				BEGIN TRY
					EXECUTE sp_executesql @rowmodctrSQL, @rowmodctrSQL_Param, @statsobjectID_In = @statsobjectID, @statsID_In = @statsID, @partitionNumber_In = @partitionNumber, @rowmodctr_Out = @rowmodctr OUTPUT, @rows_Out = @rows OUTPUT, @rows_sampled_Out = @rows_sampled OUTPUT;
					SET @rowmodctr = (SELECT ISNULL(@rowmodctr, 0));
				END TRY
				BEGIN CATCH						
					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while determining row modification counter. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
				END CATCH
				
				IF @rows IS NOT NULL AND @rows > 0 
				SET @record_count = @rows

				IF @debugMode = 1
				BEGIN
					SELECT @debugMessage = '     Found a row modification counter of ' + CONVERT(NVARCHAR(15), @rowmodctr) + ' and ' + CONVERT(NVARCHAR(15), CASE WHEN @rows IS NOT NULL AND @rows < @record_count THEN @rows ELSE @record_count END) + ' rows' + CASE WHEN @stats_isincremental = 1 THEN ' on partition ' + CONVERT(NVARCHAR(15), @partitionNumber) ELSE '' END + '...';
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					--select @debugMessage
				END
				
				/* We will update statistics if they have changed since last update with customized, more finer values, just like when TF2371 is enabled for Auto-Update.
				Default rules for auto update stats are:
				If the cardinality for a table is greater than 6, but less than or equal to 500, update status every 500 modifications.
				If the cardinality for a table is greater than 500, update statistics when (500 + 20 percent of the table) changes have occurred.
				*/
				IF (@statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.001 AND 100.0 AND @statsMinRows IS NULL AND (@rowmodctr*100)/@record_count >= @statsThreshold)
					OR (@statsThreshold IS NOT NULL AND @statsThreshold BETWEEN 0.001 AND 100.0 AND @statsMinRows IS NOT NULL AND @record_count >= @statsMinRows AND (@rowmodctr*100)/@record_count >= @statsThreshold)
					OR (@statsThreshold IS NULL AND (
						(@record_count BETWEEN 6 AND 500 AND @rowmodctr >= 500) OR -- like the default
						(@record_count BETWEEN 501 AND 10000 AND (@rowmodctr >= (@record_count*20)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 20 percent or simulate TF 2371
						(@record_count BETWEEN 10001 AND 100000 AND (@rowmodctr >= (@record_count*15)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 15 percent or simulate TF 2371
						(@record_count BETWEEN 100001 AND 1000000 AND (@rowmodctr >= (@record_count*10)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) OR -- 500 + 10 percent or simulate TF 2371
						(@record_count >= 1000001 AND (@rowmodctr >= (@record_count*5)/100 + 500 OR @rowmodctr >= SQRT(@record_count*1000))) -- 500 + 5 percent or simulate TF 2371
					))
				BEGIN	
					SET @sqlcommand2 = N'UPDATE STATISTICS ' + @dbName + N'.' + @statsschemaName + N'.' + @statsobjectName + N' (' + @statsName + N')'
					IF UPPER(@statsSample) = 'FULLSCAN' AND (@partitionNumber = 1 OR @partitionNumber = @maxpartitionNumber)
					SET @sqlcommand2 = @sqlcommand2 + N' WITH FULLSCAN'
					IF ISNUMERIC(@statsSample) = 1 AND (@partitionNumber = 1 OR @partitionNumber = @maxpartitionNumber)
					SET @sqlcommand2 = @sqlcommand2 + N' WITH SAMPLE ' + @statsSample + ' PERCENT'
					IF UPPER(@statsSample) = 'RESAMPLE'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH RESAMPLE'
					
					IF (UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1) AND @persistStatsSample = 1 
						AND UPPER(@sqlcommand2) LIKE '%WITH%' AND @sqlmajorver = 13 AND @sqlbuild >= 4446
					SET @sqlcommand2 = @sqlcommand2 + N', PERSIST_SAMPLE_PERCENT = ON'
					IF (UPPER(@statsSample) = 'FULLSCAN' OR ISNUMERIC(@statsSample) = 1) AND @persistStatsSample = 0 
						AND UPPER(@sqlcommand2) LIKE '%WITH%' AND @sqlmajorver = 13 AND @sqlbuild >= 4446
					SET @sqlcommand2 = @sqlcommand2 + N', PERSIST_SAMPLE_PERCENT = OFF'

					IF @stats_isincremental = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE') AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ON PARTITIONS(' + CONVERT(NVARCHAR(10), @partitionNumber) + N');'
					ELSE IF @stats_isincremental = 1 AND (@statsSample IS NULL OR UPPER(@statsSample) = 'RESAMPLE') AND UPPER(@sqlcommand2) NOT LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH RESAMPLE ON PARTITIONS(' + CONVERT(NVARCHAR(10), @partitionNumber) + N')'					
				
					IF @stats_norecompute = 1 AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ,NORECOMPUTE'
					ELSE IF @stats_norecompute = 1 AND UPPER(@sqlcommand2) NOT LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' WITH NORECOMPUTE'
					
					IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
						AND UPPER(@sqlcommand2) LIKE '%WITH%'
					SET @sqlcommand2 = @sqlcommand2 + N' ,MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3));
					ELSE IF @maxDopRestriction IS NOT NULL	
						AND ((@sqlmajorver >= 14 AND @sqlbuild >= 3015) /*OR (@sqlmajorver = 13 AND @sqlbuild >= xxxx)*/) -- SQL 2016 SP2, SQL 2017 CU3 or higher for MAXDOP in stats
						AND UPPER(@sqlcommand2) NOT LIKE '%WITH%'	
					SET @sqlcommand2 = @sqlcommand2 + N' WITH MAXDOP = ' + CAST(@maxDopRestriction AS VARCHAR(3));
					
					/* For list of incremental stats unsupported scenarios check http://docs.microsoft.com/sql/t-sql/statements/update-statistics-transact-sql */
					IF @partitionCount > 1 AND @statsIncremental = 1 AND @has_filter = 0
					BEGIN
						IF UPPER(@sqlcommand2) LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N' ,INCREMENTAL = ON'
						ELSE IF UPPER(@sqlcommand2) NOT LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N'WITH INCREMENTAL = ON'
					END
					ELSE IF @statsIncremental = 0
					BEGIN
						IF UPPER(@sqlcommand2) LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N', INCREMENTAL = OFF'
						ELSE IF UPPER(@sqlcommand2) NOT LIKE '%WITH%'
						SET @sqlcommand2 = @sqlcommand2 + N'WITH INCREMENTAL = OFF'
					END

					SET @sqlcommand2 = @sqlcommand2 + N';'
				END
				ELSE
				BEGIN
					SET @sqlcommand2 = NULL
				END;

				/* Are we executing the SQL? If so, do it */
				IF @Exec_Print = 1 AND @sqlcommand2 IS NOT NULL
				BEGIN
					SET @debugMessage = '     ' + @sqlcommand2;

					/* Print the commands we're executing if specified to do so */
					IF (@printCmds = 1 OR @debugMode = 1)
					RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;

					/* Get the time for logging purposes */
					SET @dateTimeStart = GETDATE();

					/* Log actions */
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], rows_sampled, modification_counter, [no_recompute], dateTimeStart, sqlStatement)		
					SELECT @dbID, @dbName, @statsobjectID, @statsobjectName, @statsID, @statsName, @partitionNumber, @record_count, @rows_sampled, @rowmodctr, @stats_norecompute, @dateTimeStart, @sqlcommand2;
					
					SET @statsUpdate_id = SCOPE_IDENTITY();

					/* Wrap execution attempt in a TRY/CATCH and log any errors that occur */
					BEGIN TRY
						/* Execute update! */
						EXECUTE sp_executesql @sqlcommand2;
						SET @dateTimeEnd = GETDATE();
						SET @sqlcommand2 = NULL

						/* Update log with completion time */
						UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_log
						SET dateTimeEnd = @dateTimeEnd, durationSeconds = DATEDIFF(second, @dateTimeStart, @dateTimeEnd)										
						WHERE statsUpdate_id = @statsUpdate_id AND partitionNumber = @partitionNumber AND dateTimeEnd IS NULL;
						
						UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
						SET updateDate = GETDATE(), printStatus = 1		
						WHERE dbID = @dbID AND objectID = @statsobjectID AND statsID = @statsID AND partitionNumber = @partitionNumber;
					END TRY
					BEGIN CATCH
						/* Update log with error message */
						UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_log
						SET dateTimeEnd = GETDATE(), durationSeconds = -1, errorMessage = 'Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'										
						WHERE statsUpdate_id = @statsUpdate_id AND partitionNumber = @partitionNumber AND dateTimeEnd IS NULL;
						
						UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
						SET updateDate = GETDATE(), printStatus = 1		
						WHERE dbID = @dbID AND objectID = @statsobjectID AND statsID = @statsID AND partitionNumber = @partitionNumber;

						IF @debugMode = 1
						BEGIN
							SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred executing this command. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
							RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
							--RAISERROR('     An error has occurred executing this command. Please review the tbl_AdaptiveIndexDefrag_Stats_log table for details.', 0, 42) WITH NOWAIT;
						END
					END CATCH
				END
				ELSE IF @Exec_Print = 1 AND @sqlcommand2 IS NULL
				BEGIN
					IF @debugMode = 1
					BEGIN
						SET @debugMessage = '     No need to update statistic ' + @statsName + ' on DB ' + @dbName + ' and object ' + @statsobjectName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					IF @printCmds = 1 AND @debugMode = 0
					BEGIN
						 SET @debugMessage = '     -- No need to update statistic ' + @statsName + ' on DB ' + @dbName + ' and object ' + @statsobjectName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						 RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working
					SET updateDate = GETDATE(), printStatus = 1
					WHERE dbID = @dbID AND objectID = @statsobjectID AND statsID = @statsID AND partitionNumber = @partitionNumber;
					
					/* Get the time for logging purposes */
					IF @dateTimeStart IS NULL
					SET @dateTimeStart = GETDATE();
					
					/* Log actions */		
					INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Stats_log (dbID, dbName, objectID, objectName, statsID, statsName, [partitionNumber], [rows], rows_sampled, modification_counter, [no_recompute], dateTimeStart, dateTimeEnd, durationSeconds, sqlStatement)		
					SELECT @dbID, @dbName, @objectID, @objectName, @statsID, @statsName, @partitionNumber, @record_count, ISNULL(@rows_sampled,-1), @rowmodctr, @stats_norecompute, @dateTimeStart, @dateTimeStart, -1, @sqlcommand2;
				END
				ELSE IF @Exec_Print = 0
				BEGIN
					IF @debugMode = 1 AND @sqlcommand2 IS NULL
					BEGIN
						SET @debugMessage = '     No need to update statistic ' + @statsName + ' on DB ' + @dbName + ' and object ' + @statsobjectName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					/* Print the commands we're executing if specified to do so */
					IF (@printCmds = 1 OR @debugMode = 1) AND @sqlcommand2 IS NOT NULL
					BEGIN
						SET @debugMessage = '     ' + @sqlcommand2;
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END
					
					IF @printCmds = 1 AND @debugMode = 0 AND @sqlcommand2 IS NULL
					BEGIN
						SET @debugMessage = '     -- No need to update statistic ' + @statsName + ' on DB ' + @dbName + ' and object ' + @statsobjectName + CASE WHEN @stats_isincremental = 1 THEN ', on partition ' + CONVERT(NVARCHAR(10), @partitionNumber) ELSE '' END + '...';
						
						IF @debugMessage IS NOT NULL
						RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
					END

					UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working		
					SET printStatus = 1	
					WHERE dbID = @dbID AND objectID = @statsobjectID AND statsID = @statsID AND partitionNumber = @partitionNumber;					
				END
			END
			IF (@printCmds = 1 OR @debugMode = 1)		
			PRINT ' No remaining statistics to update...';
		END
		ELSE
		BEGIN
			IF (@printCmds = 1 OR @debugMode = 1)		
			PRINT ' No remaining statistics to update...';
		END

		/* Output results? */	
		IF @outputResults = 1 AND @Exec_Print = 1
		BEGIN			
			IF (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate >= @startDateTime) > 0
				OR (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working WHERE updateDate >= @startDateTime) > 0
			BEGIN
				IF @debugMode = 1
				RAISERROR(' Displaying a summary of our actions...', 0, 42) WITH NOWAIT;
			
				SELECT [dbName], objectName, indexName, partitionNumber, CONVERT(decimal(9,2),fragmentation) AS fragmentation, page_count, fill_factor, range_scan_count, defragDate		
				FROM dbo.tbl_AdaptiveIndexDefrag_Working
				WHERE defragDate >= @startDateTime
				ORDER BY defragDate;
				
				SELECT [dbName], [statsName], partitionNumber, [no_recompute], [is_incremental], updateDate
				FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
				WHERE updateDate >= @startDateTime
				ORDER BY updateDate;

				IF @debugMode = 1 AND (SELECT COUNT(*) FROM dbo.tbl_AdaptiveIndexDefrag_log WHERE errorMessage IS NOT NULL AND dateTimeStart >= @startDateTime) > 0
				BEGIN
					RAISERROR('Displaying a summary of all errors...', 0, 42) WITH NOWAIT;
					
					SELECT dbName, objectName, indexName, partitionNumber, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
					FROM dbo.tbl_AdaptiveIndexDefrag_log
					WHERE errorMessage IS NOT NULL AND dateTimeStart >= @startDateTime
					ORDER BY dateTimeStart;
				END
				
				IF @debugMode = 1
				RAISERROR(' Displaying some statistical information about this defragmentation run...', 0, 42) WITH NOWAIT;

				SELECT TOP 10 'Longest time' AS Comment, dbName, objectName, indexName, partitionNumber, dateTimeStart, dateTimeEnd, durationSeconds
				FROM dbo.tbl_AdaptiveIndexDefrag_log
				WHERE dateTimeStart >= @startDateTime
				ORDER BY durationSeconds DESC;
			END
		END;
	END TRY
	BEGIN CATCH
		SET @debugMessage = '     Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ' has occurred. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')'
		RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
	END CATCH;
		/* Reset printStatus */
	IF @debugMode = 1
	RAISERROR(' Reseting working table statuses.', 0, 42) WITH NOWAIT;
		UPDATE dbo.tbl_AdaptiveIndexDefrag_Working
	SET printStatus = 0;
	UPDATE dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	SET printStatus = 0;

	/* Drop all temp tables */
	IF @debugMode = 1
	RAISERROR(' Dropping temporary objects', 0, 42) WITH NOWAIT;
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragDatabaseList'))
	DROP TABLE #tblIndexDefragDatabaseList;
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragmaxPartitionList'))
	DROP TABLE #tblIndexDefragmaxPartitionList;
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexDefragScanWorking'))
	DROP TABLE #tblIndexDefragScanWorking;
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIndexFindInDatabaseList'))
	DROP TABLE #tblIndexFindInDatabaseList;

	IF @debugMode = 1
	RAISERROR('All done!', 0, 42) WITH NOWAIT;
		IF @Exec_Print = 0
	BEGIN
		IF @ignoreDropObj = 0
		BEGIN
			IF (SELECT COUNT([errorMessage]) FROM dbo.vw_LastRun_Log) > 0 AND @ignoreDropObj = 0
			BEGIN
				RAISERROR('Defrag job found execution errors! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 16, 42) WITH NOWAIT;
				RETURN -1
			END
			ELSE
			BEGIN
				RETURN 0		
			END
		END
		ELSE
		BEGIN
			IF (SELECT COUNT([errorMessage]) FROM dbo.vw_LastRun_Log WHERE [errorMessage] NOT LIKE 'Table%does not exist%') > 0
			BEGIN
				RAISERROR('Defrag job found execution errors! Please review the tbl_AdaptiveIndexDefrag_log table for details.', 16, 42) WITH NOWAIT;
				RETURN -1
			END
			ELSE
			BEGIN
				RETURN 0		
			END
		END
	END
END
GO

--EXEC sys.sp_MS_marksystemobject 'usp_AdaptiveIndexDefrag'
--GO	

PRINT 'Procedure usp_AdaptiveIndexDefrag created';
GO

------------------------------------------------------------------------------------------------------------------------------		

CREATE VIEW vw_ErrLst30Days
AS
SELECT TOP 100 PERCENT dbName, objectName, indexName, partitionNumber, NULL AS statsName, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
FROM dbo.tbl_AdaptiveIndexDefrag_log
WHERE errorMessage IS NOT NULL AND dateTimeStart >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
UNION ALL
SELECT TOP 100 PERCENT dbName, objectName, NULL AS indexName, NULL AS partitionNumber, statsName, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log
WHERE errorMessage IS NOT NULL AND dateTimeStart >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
ORDER BY dateTimeStart;
GO

CREATE VIEW vw_ErrLst24Hrs
AS
SELECT TOP 100 PERCENT dbName, objectName, indexName, partitionNumber, NULL AS statsName, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
FROM dbo.tbl_AdaptiveIndexDefrag_log
WHERE errorMessage IS NOT NULL AND dateTimeStart >= DATEADD(hh, -24, GETDATE())
UNION ALL
SELECT TOP 100 PERCENT dbName, objectName, NULL AS indexName, partitionNumber, statsName, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log
WHERE errorMessage IS NOT NULL AND dateTimeStart >= DATEADD(hh, -24, GETDATE())
ORDER BY dateTimeStart;
GO

CREATE VIEW vw_AvgTimeLst30Days
AS
SELECT TOP 100 PERCENT 'Longest time' AS Comment, dbName, objectName, indexName, partitionNumber, AVG(durationSeconds) AS Avg_durationSeconds		
FROM dbo.tbl_AdaptiveIndexDefrag_log
WHERE dateTimeStart >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
GROUP BY dbName, objectName, indexName, partitionNumber
ORDER BY AVG(durationSeconds) DESC, dbName, objectName, indexName, partitionNumber;
GO

CREATE VIEW vw_AvgFragLst30Days
AS
SELECT TOP 100 PERCENT 'Most fragmented' AS Comment, dbName, objectName, indexName, partitionNumber, CONVERT(decimal(9,2),AVG(fragmentation)) AS Avg_fragmentation
FROM dbo.tbl_AdaptiveIndexDefrag_Working
WHERE defragDate >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
GROUP BY dbName, objectName, indexName, partitionNumber
ORDER BY AVG(fragmentation) DESC, dbName, objectName, indexName, partitionNumber;
GO

CREATE VIEW vw_AvgSamplingLst30Days
AS
SELECT TOP 100 PERCENT 'Avg_Sampling' AS Comment, dbName, objectName, partitionNumber, statsName, CAST((rows_sampled/([rows]*1.00))*100.0 AS DECIMAL(5,2)) AS sampling, dateTimeStart, dateTimeEnd, sqlStatement, errorMessage		
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log
WHERE errorMessage IS NOT NULL AND dateTimeStart >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
ORDER BY dateTimeStart;
GO

CREATE VIEW vw_AvgLargestLst30Days
AS
SELECT TOP 100 PERCENT 'Largest' AS Comment, dbName, objectName, indexName, partitionNumber, AVG(page_count)*8 AS Avg_size_KB, fill_factor		
FROM dbo.tbl_AdaptiveIndexDefrag_Working
WHERE defragDate >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
GROUP BY dbName, objectName, indexName, partitionNumber, fill_factor
ORDER BY AVG(page_count) DESC, dbName, objectName, indexName, partitionNumber
GO

CREATE VIEW vw_AvgMostUsedLst30Days
AS
SELECT TOP 100 PERCENT 'Most used' AS Comment, dbName, objectName, indexName, partitionNumber, AVG(range_scan_count) AS Avg_range_scan_count	
FROM dbo.tbl_AdaptiveIndexDefrag_Working
WHERE defragDate >= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -30)
GROUP BY dbName, objectName, indexName, partitionNumber
ORDER BY AVG(range_scan_count) DESC;
GO

CREATE VIEW vw_LastRun_Log
AS
SELECT TOP 100 percent [dbName]
      ,[objectName]
      ,[indexName]
      , NULL AS [statsName]
      ,[partitionNumber]
      ,[fragmentation]
	  ,[page_count]
	  ,[range_scan_count]
      ,[dateTimeStart]
      ,[dateTimeEnd]
      ,[durationSeconds]
      ,CASE WHEN [sqlStatement] LIKE '%REORGANIZE%' THEN 'Reorg' ELSE 'Rebuild' END AS [Operation]
      ,[errorMessage]
FROM dbo.tbl_AdaptiveIndexDefrag_log ixlog
CROSS APPLY (SELECT TOP 1 minIxDate = CASE WHEN defragDate IS NULL THEN CONVERT(DATETIME, CONVERT(NVARCHAR, scanDate, 112))
	ELSE CONVERT(DATETIME, CONVERT(NVARCHAR, defragDate, 112)) END
	FROM [dbo].[tbl_AdaptiveIndexDefrag_Working]
	ORDER BY defragDate ASC, scanDate ASC) AS minDateIxCte
WHERE dateTimeStart >= minIxDate
UNION ALL
SELECT TOP 100 percent [dbName]
      ,[objectName]
      ,NULL AS [indexName]
      ,[statsName]
      ,NULL AS [partitionNumber]
      ,NULL AS [fragmentation]
	  ,NULL AS [page_count]
	  ,NULL AS [range_scan_count]
      ,[dateTimeStart]
      ,[dateTimeEnd]
      ,[durationSeconds]
      ,'UpdateStats' AS [Operation]
      ,[errorMessage]
FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log statlog
CROSS APPLY (SELECT TOP 1 minStatDate = CASE WHEN updateDate IS NULL THEN CONVERT(DATETIME, CONVERT(NVARCHAR, scanDate, 112))
		ELSE CONVERT(DATETIME, CONVERT(NVARCHAR, updateDate, 112)) END
		FROM [dbo].[tbl_AdaptiveIndexDefrag_Stats_Working]
	ORDER BY updateDate ASC, scanDate ASC) AS minDateStatCte
WHERE dateTimeStart >= minStatDate
ORDER BY dateTimeEnd ASC
GO

PRINT 'Reporting views created';
GO

------------------------------------------------------------------------------------------------------------------------------		

CREATE PROCEDURE usp_AdaptiveIndexDefrag_PurgeLogs @daystokeep smallint = 90
AS
/*
usp_AdaptiveIndexDefrag_PurgeLogs.sql - pedro.lopes@microsoft.com (http://aka.ms/AID)

Purge log tables to avoid indefinite growth.
Default is data older than 90 days.
Change @daystokeep as you deem fit.

*/
SET NOCOUNT ON;
SET DATEFORMAT ymd;

DELETE FROM dbo.tbl_AdaptiveIndexDefrag_log
WHERE dateTimeStart <= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -@daystokeep);
DELETE FROM dbo.tbl_AdaptiveIndexDefrag_Stats_log
WHERE dateTimeStart <= DATEADD(dd, DATEDIFF(dd, 0, GETDATE()), -@daystokeep);
GO

--EXEC sys.sp_MS_marksystemobject 'usp_AdaptiveIndexDefrag_PurgeLogs'
--GO

PRINT 'Procedure usp_AdaptiveIndexDefrag_PurgeLogs created (Default purge is 90 days old)';
GO

------------------------------------------------------------------------------------------------------------------------------

CREATE PROCEDURE usp_AdaptiveIndexDefrag_CurrentExecStats @dbname NVARCHAR(255) = NULL
AS
/*
usp_AdaptiveIndexDefrag_CurrentExecStats.sql - pedro.lopes@microsoft.com (http://aka.ms/AID)

Allows monitoring of what has been done so far in the defrag loop.

Use @dbname to monitor a specific database

Example:
EXEC usp_AdaptiveIndexDefrag_CurrentExecStats @dbname = 'AdventureWorks2008R2'

*/
SET NOCOUNT ON;
IF @dbname IS NULL
BEGIN
	WITH cte1 ([Database_Name], Total_indexes) AS (SELECT [dbName], COUNT(indexID) AS Total_Indexes FROM dbo.tbl_AdaptiveIndexDefrag_Working GROUP BY [dbName]),
		cte2 ([Database_Name], Defraged_Indexes) AS (SELECT [dbName], COUNT(indexID) AS Total_Indexes FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE defragDate IS NOT NULL OR printStatus = 1 GROUP BY [dbName]),
		cte3 ([Database_Name], Total_statistics) AS (SELECT [dbName], COUNT(statsID) AS Total_statistics FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working GROUP BY [dbName]),
		cte4 ([Database_Name], Updated_statistics) AS (SELECT [dbName], COUNT(statsID) AS Updated_statistics FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working WHERE updateDate IS NOT NULL OR printStatus = 1 GROUP BY [dbName])
	SELECT cte1.[Database_Name], SUM(cte1.Total_indexes) AS Total_indexes, SUM(ISNULL(cte2.Defraged_Indexes, 0)) AS Defraged_Indexes,
		SUM(cte3.Total_statistics) AS Total_statistics, SUM(ISNULL(cte4.Updated_statistics, 0)) AS Updated_statistics
	FROM cte1 INNER JOIN cte3 ON cte1.Database_Name = cte3.Database_Name
	LEFT JOIN cte2 ON cte1.Database_Name = cte2.Database_Name
	LEFT JOIN cte4 ON cte1.Database_Name = cte4.Database_Name
	GROUP BY cte1.[Database_Name];

	SELECT 'Index' AS [Type], 'Done' AS [Result], dbName, objectName, indexName
	FROM dbo.tbl_AdaptiveIndexDefrag_Working
	WHERE defragDate IS NOT NULL OR printStatus = 1
	UNION ALL
	SELECT 'Index' AS [Type], 'To do' AS [Result], dbName, objectName, indexName
	FROM dbo.tbl_AdaptiveIndexDefrag_Working
	WHERE defragDate IS NULL AND printStatus = 0
	ORDER BY 2, dbName, objectName, indexName;

	SELECT 'Statistic' AS [Type], 'Done' AS [Result], dbName, objectName, statsName
	FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	WHERE updateDate IS NOT NULL OR printStatus = 1
	UNION ALL
	SELECT 'Statistic' AS [Type], 'To do' AS [Result], dbName, objectName, statsName
	FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	WHERE updateDate IS NULL AND printStatus = 0
	ORDER BY 2, dbName, objectName, statsName;
END
ELSE
BEGIN
	WITH cte1 ([Database_Name], Total_indexes) AS (SELECT [dbName], COUNT(indexID) AS Total_Indexes FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE [dbName] = QUOTENAME(@dbname) GROUP BY [dbName]),
		cte2 ([Database_Name], Defraged_Indexes) AS (SELECT [dbName], COUNT(indexID) AS Total_Indexes FROM dbo.tbl_AdaptiveIndexDefrag_Working WHERE [dbName] = QUOTENAME(@dbname) AND defragDate IS NOT NULL OR printStatus = 1 GROUP BY [dbName]),
		cte3 ([Database_Name], Total_statistics) AS (SELECT [dbName], COUNT(statsID) AS Total_statistics FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working WHERE [dbName] = QUOTENAME(@dbname) GROUP BY [dbName]),
		cte4 ([Database_Name], Updated_statistics) AS (SELECT [dbName], COUNT(statsID) AS Updated_statistics FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working WHERE [dbName] = QUOTENAME(@dbname) AND updateDate IS NOT NULL OR printStatus = 1 GROUP BY [dbName])
	SELECT cte1.[Database_Name], SUM(cte1.Total_indexes) AS Total_indexes, SUM(ISNULL(cte2.Defraged_Indexes, 0)) AS Defraged_Indexes,
		SUM(cte3.Total_statistics) AS Total_statistics, SUM(ISNULL(cte4.Updated_statistics, 0)) AS Updated_statistics
	FROM cte1 INNER JOIN cte3 ON cte1.Database_Name = cte3.Database_Name
	LEFT JOIN cte2 ON cte1.Database_Name = cte2.Database_Name
	LEFT JOIN cte4 ON cte1.Database_Name = cte4.Database_Name
	GROUP BY cte1.[Database_Name];

	SELECT 'Index' AS [Type], 'Done' AS [Result], dbName, objectName, indexName, partitionNumber
	FROM dbo.tbl_AdaptiveIndexDefrag_Working
	WHERE [dbName] = QUOTENAME(@dbname) AND (defragDate IS NOT NULL OR printStatus = 1)
	UNION ALL
	SELECT 'Index' AS [Type], 'To do' AS [Result], dbName, objectName, indexName, partitionNumber
	FROM dbo.tbl_AdaptiveIndexDefrag_Working
	WHERE [dbName] = QUOTENAME(@dbname) AND defragDate IS NULL AND printStatus = 0
	ORDER BY 2, dbName, objectName, indexName;

	SELECT 'Statistic' AS [Type], 'Done' AS [Result], dbName, objectName, statsName
	FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	WHERE [dbName] = QUOTENAME(@dbname) AND ([updateDate] IS NOT NULL OR printStatus = 1)
	UNION ALL
	SELECT 'Statistic' AS [Type], 'To do' AS [Result], dbName, objectName, statsName
	FROM dbo.tbl_AdaptiveIndexDefrag_Stats_Working
	WHERE [dbName] = QUOTENAME(@dbname) AND [updateDate] IS NULL AND printStatus = 0
	ORDER BY 2, dbName, objectName, statsName;
END
GO

--EXEC sys.sp_MS_marksystemobject 'usp_AdaptiveIndexDefrag_CurrentExecStats'
--GO

PRINT 'Procedure usp_AdaptiveIndexDefrag_CurrentExecStats created (Use this to monitor defrag loop progress)';
GO

------------------------------------------------------------------------------------------------------------------------------

CREATE PROCEDURE usp_AdaptiveIndexDefrag_Exceptions @exceptionMask_DB NVARCHAR(255) = NULL,
	@exceptionMask_days NVARCHAR(27) = NULL,
	@exceptionMask_tables NVARCHAR(500) = NULL,
	@exceptionMask_indexes NVARCHAR(500) = NULL
AS
/*
usp_AdaptiveIndexDefrag_Exceptions.sql - pedro.lopes@microsoft.com (http://aka.ms/AID)

To insert info into the Exceptions table, use the following guidelines:
For @exceptionMask_DB, enter only one database name at a time.
For @exceptionMask_days, enter weekdays in short form, between commas.
	* NOTE: Keep only the weekdays you DO NOT WANT to ALLOW defrag. *
	Order is not mandatory, but weekday short names are important AS IS ('Sun,Mon,Tue,Wed,Thu,Fri,Sat').
	* NOTE: If you WANT to NEVER allow defrag, set as NULL or leave blank *
For @exceptionMask_tables (optional) enter table names separated by commas ('table_name_1, table_name_2, table_name_3').
For @exceptionMask_indexes (optional) enter index names separated by commas ('index_name_1, index_name_2, index_name_3').
	If you want to exclude all indexes in a given table, enter its name but don't add index names.

Example:
EXEC usp_AdaptiveIndexDefrag_Exceptions @exceptionMask_DB = 'AdventureWorks2008R2',
	@exceptionMask_days = 'Mon,Wed',
	@exceptionMask_tables = 'Employee',
	@exceptionMask_indexes = 'AK_Employee_LoginID'

*/
SET NOCOUNT ON;

IF @exceptionMask_DB IS NULL OR QUOTENAME(@exceptionMask_DB) NOT IN (SELECT QUOTENAME(name) FROM sys.databases)
RAISERROR('Syntax error. Please input a valid database name.', 15, 42) WITH NOWAIT;

IF @exceptionMask_days IS NOT NULL AND
	(@exceptionMask_days NOT LIKE '___' AND
	@exceptionMask_days NOT LIKE '___,___' AND
	@exceptionMask_days NOT LIKE '___,___,___' AND
	@exceptionMask_days NOT LIKE '___,___,___,___' AND
	@exceptionMask_days NOT LIKE '___,___,___,___,___' AND
	@exceptionMask_days NOT LIKE '___,___,___,___,___,___' AND
	@exceptionMask_days NOT LIKE '___,___,___,___,___,___,___')
RAISERROR('Syntax error. Please input weekdays in short form, between commas, or leave NULL to always exclude.', 15, 42) WITH NOWAIT;

IF @exceptionMask_days LIKE '[___,___,___,___,___,___,___]'
RAISERROR('Warning. You chose to permanently exclude a table and/or index from being defragmented.', 0, 42) WITH NOWAIT;

IF @exceptionMask_tables IS NOT NULL AND @exceptionMask_tables LIKE '%.%'
RAISERROR('Syntax error. Please do not input schema with table name(s).', 15, 42) WITH NOWAIT;

DECLARE @debugMessage NVARCHAR(4000), @sqlcmd NVARCHAR(4000), @sqlmajorver int

/* Find sql server version */
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
		
BEGIN TRY
	--Always exclude from defrag?
	IF @exceptionMask_days IS NULL OR @exceptionMask_days = ''
		BEGIN
			SET @exceptionMask_days = 127
		END
	ELSE
		BEGIN
			-- 1=Sunday, 2=Monday, 4=Tuesday, 8=Wednesday, 16=Thursday, 32=Friday, 64=Saturday, 127=AllWeek
			SET @exceptionMask_days = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@exceptionMask_days,',','+'),'Sun',1),'Mon',2),'Tue',4),'Wed',8),'Thu',16),'Fri',32),'Sat',64);
		END
	--Just get everything as it should be
	SET @exceptionMask_tables = CHAR(39) + REPLACE(REPLACE(@exceptionMask_tables, ' ', ''),',', CHAR(39) + ',' + CHAR(39)) + CHAR(39)
	SET @exceptionMask_indexes = CHAR(39) + REPLACE(REPLACE(@exceptionMask_indexes, ' ', ''),',', CHAR(39) + ',' + CHAR(39)) + CHAR(39)

	--Get the exceptions insert command
	IF @sqlmajorver > 9
	BEGIN	
		SELECT @sqlcmd = 'MERGE dbo.tbl_AdaptiveIndexDefrag_Exceptions AS target
USING (SELECT ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ' AS dbID, si.[object_id] AS objectID, si.index_id AS indexID,
''' + @exceptionMask_DB + ''' AS dbName, OBJECT_NAME(si.[object_id], ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ') AS objectName, si.[name] AS indexName,
' + CONVERT(NVARCHAR,@exceptionMask_days) + ' AS exclusionMask
FROM ' + QUOTENAME(@exceptionMask_DB) + '.sys.indexes si
INNER JOIN ' + QUOTENAME(@exceptionMask_DB) + '.sys.objects so ON si.object_id = so.object_id
WHERE so.is_ms_shipped = 0 AND si.index_id > 0 AND si.is_hypothetical = 0
	AND si.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + @exceptionMask_DB + '].sys.internal_tables AS sit)' -- Exclude Heaps, Internal and Hypothetical objects
	+ CASE WHEN @exceptionMask_tables IS NOT NULL THEN ' AND OBJECT_NAME(si.[object_id], ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ') IN (' + @exceptionMask_tables + ')' ELSE '' END
	+ CASE WHEN @exceptionMask_indexes IS NOT NULL THEN ' AND si.[name] IN (' + @exceptionMask_indexes + ')' ELSE '' END
+ ') AS source
ON (target.[dbID] = source.[dbID] AND target.objectID = source.objectID AND target.indexID = source.indexID)
WHEN MATCHED THEN
	UPDATE SET exclusionMask = source.exclusionMask
WHEN NOT MATCHED THEN
	INSERT (dbID, objectID, indexID, dbName, objectName, indexName, exclusionMask)
	VALUES (source.dbID, source.objectID, source.indexID, source.dbName, source.objectName, source.indexName, source.exclusionMask);';
	END
	ELSE
	BEGIN	
			SELECT @sqlcmd = 'DELETE FROM dbo.tbl_AdaptiveIndexDefrag_Exceptions
WHERE dbID = ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB))
+ CASE WHEN @exceptionMask_tables IS NOT NULL THEN ' AND [objectName] IN (' + @exceptionMask_tables + ')' ELSE '' END
+ CASE WHEN @exceptionMask_indexes IS NOT NULL THEN ' AND [indexName] IN (' + @exceptionMask_indexes + ');' ELSE ';' END +
'INSERT INTO dbo.tbl_AdaptiveIndexDefrag_Exceptions
SELECT ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ' AS dbID, si.[object_id] AS objectID, si.index_id AS indexID,
''' + @exceptionMask_DB + ''' AS dbName, OBJECT_NAME(si.[object_id], ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ') AS objectName, si.[name] AS indexName,
' + CONVERT(NVARCHAR,@exceptionMask_days) + ' AS exclusionMask
FROM ' + QUOTENAME(@exceptionMask_DB) + '.sys.indexes si
INNER JOIN ' + QUOTENAME(@exceptionMask_DB) + '.sys.objects so ON si.object_id = so.object_id
WHERE so.is_ms_shipped = 0 AND si.index_id > 0 AND si.is_hypothetical = 0
	AND si.[object_id] NOT IN (SELECT sit.[object_id] FROM [' + @exceptionMask_DB + '].sys.internal_tables AS sit)' -- Exclude Heaps, Internal and Hypothetical objects
	+ CASE WHEN @exceptionMask_tables IS NOT NULL THEN ' AND OBJECT_NAME(si.[object_id], ' + CONVERT(NVARCHAR,DB_ID(@exceptionMask_DB)) + ') IN (' + @exceptionMask_tables + ')' ELSE '' END
	+ CASE WHEN @exceptionMask_indexes IS NOT NULL THEN ' AND si.[name] IN (' + @exceptionMask_indexes + ')' ELSE '' END;
	END;
	EXEC sp_executesql @sqlcmd;
END TRY		
BEGIN CATCH	
	SET @debugMessage = 'Error ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + ': ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + ')';
	RAISERROR(@debugMessage, 0, 42) WITH NOWAIT;
END CATCH;
GO	

--EXEC sys.sp_MS_marksystemobject 'usp_AdaptiveIndexDefrag_Exceptions'
--GO

PRINT 'Procedure usp_AdaptiveIndexDefrag_Exceptions created (If the defrag should not be daily, use this to set on which days to disallow it. It can be on entire DBs, tables and/or indexes)';

PRINT 'All done!'

GO
