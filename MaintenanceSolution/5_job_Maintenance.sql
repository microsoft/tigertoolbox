USE [msdb]
GO

IF EXISTS(SELECT [object_id] FROM sys.views WHERE [name] = 'vw_MaintenanceLog')
BEGIN
	DROP VIEW vw_MaintenanceLog;
	PRINT 'View vw_MaintenanceLog dropped'
END
GO

CREATE VIEW vw_MaintenanceLog AS
SELECT [name]
	,[step_name]
    ,(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		[log],
		NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		AS [text()] FROM [msdb].[dbo].[sysjobstepslogs] sjsl2 WHERE sjsl2.log_id = sjsl.log_id FOR XML PATH(''), TYPE) AS 'Log'
	,sjsl.[date_created]
    ,sjsl.[date_modified]
    ,([log_size]/1024) AS [log_size_kb]
FROM [msdb].[dbo].[sysjobstepslogs] sjsl
INNER JOIN [msdb].[dbo].[sysjobsteps] sjs ON sjs.[step_uid] = sjsl.[step_uid]
INNER JOIN [msdb].[dbo].[sysjobs] sj ON sj.[job_id] = sjs.[job_id]
WHERE [name] = 'Weekly Maintenance';
GO

PRINT 'View vw_MaintenanceLog view created';
GO

IF OBJECTPROPERTY(OBJECT_ID('dbo.usp_CheckIntegrity'), N'IsProcedure') = 1
BEGIN
	DROP PROCEDURE dbo.usp_CheckIntegrity;
	PRINT 'Procedure usp_CheckIntegrity dropped'
END	
GO

CREATE PROCEDURE usp_CheckIntegrity @VLDBMode bit = 1, @SingleUser bit = 0, @CreateSnap bit = 1, @SnapPath NVARCHAR(1000) = NULL, @AO_Secondary bit = 0, @Physical bit = 0
AS
/* 
This checks the logical and physical integrity of all the objects in the specified database by performing the following operations: 
|-For VLDBs (larger than 1TB):
  |- On Sundays, if VLDB Mode = 0, runs DBCC CHECKALLOC.
  |- On Sundays, runs DBCC CHECKCATALOG.
  |- Everyday, if VLDB Mode = 0, runs DBCC CHECKTABLE or if VLDB Mode = 1, DBCC CHECKFILEGROUP on a subset of tables and views, divided by daily buckets.
|-For DBs smaller than 1TB:
  |- Every Sunday a DBCC CHECKDB checks the logical and physical integrity of all the objects in the specified database.

To set how VLDBs are handled, set @VLDBMode to 0 = Bucket by Table Size or 1 = Bucket by Filegroup Size
Buckets are built weekly, on Sunday.

IMPORTANT: Consider running DBCC CHECKDB routinely (at least, weekly). On large databases and for more frequent checks, consider using the PHYSICAL_ONLY parameter.
http://msdn.microsoft.com/en-us/library/ms176064.aspx
http://blogs.msdn.com/b/sqlserverstorageengine/archive/2006/10/20/consistency-checking-options-for-a-vldb.aspx

Excludes all Offline and Read-Only DBs, and works on databases over 1TB

If a database has Read-Only filegroups, any integrity check will fail if there are other open connections to the database.
Setting @CreateSnap = 1 will create a database snapshot before running the check on the snapshot, and drop it at the end (default).
Setting @CreateSnap = 0 means the integrity check might fail if there are other open connection on the database.
Note: set a custom snapshot creation path in @SnapPath or the same path as the database in scope will be used.
Ex.: @SnapPath = 'C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data'

If snapshots are not allowed and a database has Read-Only filegroups, any integrity check will fail if there are other openned connections to the database.
Setting @SingleUser = 1 will set the database in single user mode before running the check, and to multi user afterwards.
Setting @SingleUser = 0 means the integrity check might fail if there are other open connection on the database.

If on SQL Server 2012 or above and you are using Availability Replicas: 
Setting @AO_Secondary = 0 then AlwaysOn primary replicas are eligible for Integrity Checks, but secondary replicas are skipped.
Setting @AO_Secondary = 1 then AlwaysOn secondary replicas are eligible for Integrity Checks, but primary replicas are skipped.

If more frequent checks are required, consider using the PHYSICAL_ONLY parameter:
Setting @Physical = 0 does not consider PHYSICAL_ONLY option.
Setting @Physical = 1 enables PHYSICAL_ONLY option (where available).
*/

SET NOCOUNT ON;

IF @VLDBMode NOT IN (0,1)
BEGIN
	RAISERROR('[ERROR: Must set a integrity check strategy for any VLDBs we encounter - 0 = Bucket by Table Size; 1 = Bucket by Filegroup Size]', 16, 1, N'VLDB')
	RETURN
END

IF @CreateSnap = 1 AND @SingleUser = 1
BEGIN
	RAISERROR('[ERROR: Must select only one method of checking databases with Read-Only FGs]', 16, 1, N'ReadOnlyFGs')
	RETURN
END

DECLARE @dbid int, @dbname sysname, @sqlcmdROFG NVARCHAR(1000), @sqlcmd NVARCHAR(max), @sqlcmd_Create NVARCHAR(max), @sqlcmd_Drop NVARCHAR(500)
DECLARE @msg NVARCHAR(500), @params NVARCHAR(500), @sqlcmd_AO NVARCHAR(4000);
DECLARE @filename sysname, @filecreateid int, @Message VARCHAR(1000);
DECLARE @Buckets tinyint, @BucketCnt tinyint, @BucketPages bigint, @TodayBucket tinyint, @dbsize bigint, @fg_id int, @HasROFG bigint, @sqlsnapcmd NVARCHAR(max);
DECLARE @BucketId tinyint, @object_id int, @name sysname, @schema sysname, @type CHAR(2), @type_desc NVARCHAR(60), @used_page_count bigint;
DECLARE @sqlmajorver int, @ErrorMessage NVARCHAR(4000)
		
IF NOT EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tblDbBuckets')
CREATE TABLE tblDbBuckets (BucketId int, [database_id] int, [object_id] int, [name] sysname, [schema] sysname, [type] CHAR(2), type_desc NVARCHAR(60), used_page_count bigint, isdone bit);
IF NOT EXISTS(SELECT [object_id] FROM sys.tables WHERE [name] = 'tblFgBuckets')
CREATE TABLE tblFgBuckets (BucketId int, [database_id] int, [data_space_id] int, [name] sysname, used_page_count bigint, isdone bit);
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
CREATE TABLE #tmpdbs (id int IDENTITY(1,1), [dbid] int, [dbname] sysname, rows_size_MB bigint, isdone bit)
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblBuckets'))
CREATE TABLE #tblBuckets (BucketId int, MaxAmount bigint, CurrentRunTotal bigint)
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblObj'))
CREATE TABLE #tblObj ([object_id] int, [name] sysname, [schema] sysname, [type] CHAR(2), type_desc NVARCHAR(60), used_page_count bigint, isdone bit)
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFGs'))
CREATE TABLE #tblFGs ([data_space_id] int, [name] sysname, used_page_count bigint, isdone bit)
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSnapFiles'))
CREATE TABLE #tblSnapFiles ([name] sysname, isdone bit)

SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);

SELECT @Message = '** Start: ' + CONVERT(VARCHAR, GETDATE())
RAISERROR(@Message, 0, 42) WITH NOWAIT;

SET @sqlcmd_AO = 'SELECT sd.database_id, sd.name, SUM((size * 8) / 1024) AS rows_size_MB, 0 
FROM sys.databases sd (NOLOCK)
INNER JOIN sys.master_files smf (NOLOCK) ON sd.database_id = smf.database_id
WHERE sd.is_read_only = 0 AND sd.state = 0 AND sd.database_id <> 2 AND smf.[type] = 0';

IF @sqlmajorver >= 11 AND @AO_Secondary = 0 -- Skip all local AlwaysOn secondary replicas
BEGIN
	SET @sqlcmd_AO = @sqlcmd_AO + CHAR(10) + 'AND sd.[database_id] NOT IN (SELECT dr.database_id FROM sys.dm_hadr_database_replica_states dr
INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
INNER JOIN sys.databases d ON dr.database_id = d.database_id
WHERE rs.role = 2 -- Is Secondary
AND dr.is_local = 1
AND rs.is_local = 1)'
END;

IF @sqlmajorver >= 11 AND @AO_Secondary = 1 -- Skip all local AlwaysOn primary replicas
BEGIN
	SET @sqlcmd_AO = @sqlcmd_AO + CHAR(10) + 'AND sd.[database_id] NOT IN (SELECT dr.database_id FROM sys.dm_hadr_database_replica_states dr
INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
INNER JOIN sys.databases d ON dr.database_id = d.database_id
WHERE rs.role = 1 -- Is Primary
AND dr.is_local = 1
AND rs.is_local = 0)'
END;

SET @sqlcmd_AO = @sqlcmd_AO + CHAR(10) + 'GROUP BY sd.database_id, sd.name';

INSERT INTO #tmpdbs ([dbid], [dbname], rows_size_MB, isdone)
EXEC sp_executesql @sqlcmd_AO;

WHILE (SELECT COUNT([dbid]) FROM #tmpdbs WHERE isdone = 0) > 0
BEGIN
	SET @dbid = (SELECT TOP 1 [dbid] FROM #tmpdbs WHERE isdone = 0)
	SET @dbname = (SELECT TOP 1 [dbname] FROM #tmpdbs WHERE isdone = 0)
	SET @dbsize = (SELECT TOP 1 [rows_size_MB] FROM #tmpdbs WHERE isdone = 0)
	
	-- If a snapshot is to be created, set the proper path
	IF @SnapPath IS NULL
	BEGIN
		SELECT TOP 1 @SnapPath = physical_name FROM sys.master_files WHERE database_id = @dbid AND [type] = 0 AND [state] = 0
		IF @SnapPath IS NOT NULL
		BEGIN
			SELECT @SnapPath = LEFT(@SnapPath, LEN(@SnapPath)-CHARINDEX('\',REVERSE(@SnapPath)))
		END
	END;

	-- Find if database has Read-Only FGs
	SET @sqlcmd = N'USE [' + @dbname + ']; SELECT @HasROFGOUT = COUNT(data_space_id) FROM sys.filegroups WHERE is_read_only = 1'
	SET @params = N'@HasROFGOUT bigint OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @HasROFGOUT=@HasROFG OUTPUT;
	
	SET @sqlcmd = ''

	IF @dbsize < 1048576 -- smaller than 1TB
	BEGIN
		-- Is it Sunday yet? If so, start database check
		IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
		BEGIN
			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
			SELECT @msg = CHAR(10) + CONVERT(VARCHAR, GETDATE(), 9) + ' - Started integrity checks on ' + @dbname + '_CheckDB_Snapshot';
			
			IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
			SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started integrity checks on ' + @dbname;
			
			RAISERROR (@msg, 10, 1) WITH NOWAIT

			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
			SET @sqlcmd = 'DBCC CHECKDB (''' + @dbname + '_CheckDB_Snapshot'') WITH '
			
			IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
			SET @sqlcmd = 'DBCC CHECKDB (' + CONVERT(NVARCHAR(10),@dbid) + ') WITH '
			
			IF @Physical = 1
			BEGIN
				SET @sqlcmd = @sqlcmd + 'PHYSICAL_ONLY;'
			END
			ELSE
			BEGIN
				SET @sqlcmd = @sqlcmd + 'DATA_PURITY;'
			END;

			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
			BEGIN
				TRUNCATE TABLE #tblSnapFiles;
				
				INSERT INTO #tblSnapFiles
				SELECT name, 0 FROM sys.master_files WHERE database_id = @dbid AND [type] = 0;
				
				SET @filecreateid = 1
				SET @sqlsnapcmd = ''

				WHILE (SELECT COUNT([name]) FROM #tblSnapFiles WHERE isdone = 0) > 0
				BEGIN
					SELECT TOP 1 @filename = [name] FROM #tblSnapFiles WHERE isdone = 0
					SET @sqlsnapcmd = @sqlsnapcmd + CHAR(10) + '(NAME = [' + @filename + '], FILENAME = ''' + @SnapPath + '\' + @dbname + '_CheckDB_Snapshot_Data_' + CONVERT(VARCHAR(10), @filecreateid) + '.ss''),'
					SET @filecreateid = @filecreateid + 1

					UPDATE #tblSnapFiles
					SET isdone = 1 WHERE [name] = @filename;
				END;

				SELECT @sqlsnapcmd = LEFT(@sqlsnapcmd, LEN(@sqlsnapcmd)-1);

				SET @sqlcmd_Create = 'USE master;
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'')
CREATE DATABASE [' + @dbname + '_CheckDB_Snapshot] ON ' + @sqlsnapcmd + CHAR(10) + 'AS SNAPSHOT OF [' + @dbname + '];' 
				
				SET @sqlcmd_Drop = 'USE master; 
IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'') 
DROP DATABASE [' + @dbname + '_CheckDB_Snapshot];'
			END
			
			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NULL
			BEGIN
				SET @sqlcmd = NULL
				SELECT @Message = '** Skipping database ' + @dbname + ': Could not find a valid path to create DB snapshot - ' + CONVERT(VARCHAR, GETDATE())
				RAISERROR(@Message, 0, 42) WITH NOWAIT;
			END
			
			IF @HasROFG > 0 AND @SingleUser = 1
			BEGIN
				SET @sqlcmd = 'USE master;
ALTER DATABASE [' + @dbname + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10) + @sqlcmd + CHAR(10) + 
'USE master;
ALTER DATABASE [' + @dbname + '] SET MULTI_USER WITH ROLLBACK IMMEDIATE;'
			END

			IF @sqlcmd_Create IS NOT NULL
			BEGIN TRY
				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Creating database snapshot ' + @dbname + '_CheckDB_Snapshot';
				RAISERROR (@msg, 10, 1) WITH NOWAIT	

				EXEC sp_executesql @sqlcmd_Create;
			END TRY
			BEGIN CATCH
				EXEC sp_executesql @sqlcmd_Drop;
				
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Create Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH

			IF @sqlcmd IS NOT NULL
			BEGIN TRY					
				EXEC sp_executesql @sqlcmd;

				UPDATE tblFgBuckets
				SET isdone = 1
				FROM tblFgBuckets
				WHERE [database_id] = @dbid AND [data_space_id] = @fg_id AND used_page_count = @used_page_count AND isdone = 0 AND BucketId = @TodayBucket
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Check cycle - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
				RETURN
			END CATCH
			
			IF @sqlcmd_Drop IS NOT NULL
			BEGIN TRY
				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Droping database snapshot ' + @dbname + '_CheckDB_Snapshot';
				RAISERROR (@msg, 10, 1) WITH NOWAIT	
				EXEC sp_executesql @sqlcmd_Drop;
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Drop Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
		END
		ELSE
		BEGIN
			SELECT @Message = '** Skipping database ' + @dbname + ': Today is not Sunday - ' + CONVERT(VARCHAR, GETDATE())
			RAISERROR(@Message, 0, 42) WITH NOWAIT;
		END
	END;

	IF @dbsize >= 1048576 -- 1TB or Larger, then create buckets
	BEGIN
		-- Buckets are built on a weekly basis, so is it Sunday yet? If so, start building
		IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
		BEGIN
			TRUNCATE TABLE #tblObj
			TRUNCATE TABLE #tblBuckets
			TRUNCATE TABLE #tblFGs
			TRUNCATE TABLE tblFgBuckets
			TRUNCATE TABLE tblDbBuckets

			SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Creating database snapshot ' + @dbname + '_CheckDB_Snapshot';
			RAISERROR (@msg, 10, 1) WITH NOWAIT				

			IF @VLDBMode = 0 -- Setup to bucketize by Table Size
			BEGIN
				SET @sqlcmd = 'SELECT so.[object_id], so.[name], ss.name, so.[type], so.type_desc, SUM(sps.used_page_count) AS used_page_count, 0
FROM [' + @dbname + '].sys.objects so
INNER JOIN [' + @dbname + '].sys.dm_db_partition_stats sps ON so.[object_id] = sps.[object_id]
INNER JOIN [' + @dbname + '].sys.indexes si ON so.[object_id] = si.[object_id]
INNER JOIN [' + @dbname + '].sys.schemas ss ON so.[schema_id] = ss.[schema_id] 
WHERE so.[type] IN (''S'', ''U'', ''V'')
GROUP BY so.[object_id], so.[name], ss.name, so.[type], so.type_desc
ORDER BY used_page_count DESC'

				INSERT INTO #tblObj
				EXEC sp_executesql @sqlcmd;
			END

			IF @VLDBMode = 1 -- Setup to bucketize by Filegroup Size
			BEGIN
				SET @sqlcmd = 'SELECT fg.data_space_id, fg.name AS [filegroup_name], SUM(sps.used_page_count) AS used_page_count, 0
FROM [' + @dbname + '].sys.dm_db_partition_stats sps
INNER JOIN [' + @dbname + '].sys.indexes i ON sps.object_id = i.object_id
INNER JOIN [' + @dbname + '].sys.partition_schemes ps ON ps.data_space_id = i.data_space_id 
INNER JOIN [' + @dbname + '].sys.destination_data_spaces dds ON dds.partition_scheme_id = ps.data_space_id AND dds.destination_id = sps.partition_number 
INNER JOIN [' + @dbname + '].sys.filegroups fg ON dds.data_space_id = fg.data_space_id
--WHERE fg.is_read_only = 0
GROUP BY fg.name, ps.name, fg.data_space_id
ORDER BY SUM(sps.used_page_count) DESC, fg.data_space_id'

				INSERT INTO #tblFGs
				EXEC sp_executesql @sqlcmd;
			END
			
			SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Bucketizing by ' + CASE WHEN @VLDBMode = 1 THEN 'Filegroup Size' ELSE 'Table Size' END;
			RAISERROR (@msg, 10, 1) WITH NOWAIT	

			-- Create buckets
			SET @Buckets = 8
			SET @BucketCnt = 1
			SET @sqlcmd = N'SELECT @BucketPagesOUT = SUM(used_page_count)/7 FROM ' + CASE WHEN @VLDBMode = 0 THEN '#tblObj' WHEN @VLDBMode = 1 THEN '#tblFGs' END
			SET @params = N'@BucketPagesOUT bigint OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @BucketPagesOUT=@BucketPages OUTPUT;

			WHILE @BucketCnt <> @Buckets
			BEGIN
				INSERT INTO #tblBuckets VALUES (@BucketCnt, @BucketPages, 0) 
				SET @BucketCnt = @BucketCnt + 1
			END

			IF @VLDBMode = 0 -- Populate buckets by Table Size
			BEGIN
				WHILE (SELECT COUNT(*) FROM #tblObj WHERE isdone = 0) > 0
				BEGIN
					SELECT TOP 1 @object_id = [object_id], @name = [name], @schema = [schema], @type = [type], @type_desc = type_desc, @used_page_count = used_page_count
					FROM #tblObj
					WHERE isdone = 0
					ORDER BY used_page_count DESC

					SELECT TOP 1 @BucketId = BucketId FROM #tblBuckets ORDER BY CurrentRunTotal

					INSERT INTO tblDbBuckets 
					SELECT @BucketId, @dbid, @object_id, @name, @schema, @type, @type_desc, @used_page_count, 0;

					UPDATE #tblObj
					SET isdone = 1
					FROM #tblObj
					WHERE [object_id] = @object_id AND used_page_count = @used_page_count AND isdone = 0;

					UPDATE #tblBuckets
					SET CurrentRunTotal = CurrentRunTotal + @used_page_count
					WHERE BucketId = @BucketId;
				END
			END;

			IF @VLDBMode = 1 -- Populate buckets by Filegroup Size
			BEGIN
				WHILE (SELECT COUNT(*) FROM #tblFGs WHERE isdone = 0) > 0
				BEGIN
					SELECT TOP 1 @fg_id = [data_space_id], @name = [name], @used_page_count = used_page_count
					FROM #tblFGs
					WHERE isdone = 0
					ORDER BY used_page_count DESC

					SELECT TOP 1 @BucketId = BucketId FROM #tblBuckets ORDER BY CurrentRunTotal

					INSERT INTO tblFgBuckets 
					SELECT @BucketId, @dbid, @fg_id, @name, @used_page_count, 0;

					UPDATE #tblFGs
					SET isdone = 1
					FROM #tblFGs
					WHERE [data_space_id] = @fg_id AND used_page_count = @used_page_count AND isdone = 0;

					UPDATE #tblBuckets
					SET CurrentRunTotal = CurrentRunTotal + @used_page_count
					WHERE BucketId = @BucketId;
				END
			END
		END;

		-- What day is today? 1=Sunday, 2=Monday, 4=Tuesday, 8=Wednesday, 16=Thursday, 32=Friday, 64=Saturday
		SELECT @TodayBucket = CASE WHEN 1 & POWER(2, DATEPART(weekday, GETDATE())-1) = 1 THEN 1 
				WHEN 2 & POWER(2, DATEPART(weekday, GETDATE())-1) = 2 THEN 2
				WHEN 4 & POWER(2, DATEPART(weekday, GETDATE())-1) = 4 THEN 3
				WHEN 8 & POWER(2, DATEPART(weekday, GETDATE())-1) = 8 THEN 4
				WHEN 16 & POWER(2, DATEPART(weekday, GETDATE())-1) = 16 THEN 5
				WHEN 32 & POWER(2, DATEPART(weekday, GETDATE())-1) = 32 THEN 6
				WHEN 64 & POWER(2, DATEPART(weekday, GETDATE())-1) = 64 THEN 7
			END;

		-- Is it Sunday yet? If so, start working on allocation and catalog checks on todays bucket
		IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
		BEGIN
			IF @VLDBMode = 0
			BEGIN
				IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started allocation checks on ' + @dbname + '_CheckDB_Snapshot]';
			
				IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started allocation checks on ' + @dbname;

				RAISERROR (@msg, 10, 1) WITH NOWAIT

				IF @HasROFG > 0 AND @CreateSnap = 1
				SET @sqlcmd = 'DBCC CHECKALLOC (''' + @dbname + '_CheckDB_Snapshot'');'
				
				IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
				SET @sqlcmd = 'DBCC CHECKALLOC (' + CONVERT(NVARCHAR(10),@dbid) + ');'

				IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
				BEGIN
					TRUNCATE TABLE #tblSnapFiles;
				
					INSERT INTO #tblSnapFiles
					SELECT name, 0 FROM sys.master_files WHERE database_id = @dbid AND [type] = 0;
				
					SET @filecreateid = 1
					SET @sqlsnapcmd = ''

					WHILE (SELECT COUNT([name]) FROM #tblSnapFiles WHERE isdone = 0) > 0
					BEGIN
						SELECT TOP 1 @filename = [name] FROM #tblSnapFiles WHERE isdone = 0
						SET @sqlsnapcmd = @sqlsnapcmd + CHAR(10) + '(NAME = [' + @filename + '], FILENAME = ''' + @SnapPath + '\' + @dbname + '_CheckDB_Snapshot_Data_' + CONVERT(VARCHAR(10), @filecreateid) + '.ss''),'
						SET @filecreateid = @filecreateid + 1

						UPDATE #tblSnapFiles
						SET isdone = 1 WHERE [name] = @filename;
					END;

					SELECT @sqlsnapcmd = LEFT(@sqlsnapcmd, LEN(@sqlsnapcmd)-1);

					SET @sqlcmd_Create = 'USE master;
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'')
CREATE DATABASE [' + @dbname + '_CheckDB_Snapshot] ON ' + @sqlsnapcmd + CHAR(10) + 'AS SNAPSHOT OF [' + @dbname + '];' 
				
					SET @sqlcmd_Drop = 'USE master; 
IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'') 
DROP DATABASE [' + @dbname + '_CheckDB_Snapshot];'
				END
			
				IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NULL
				BEGIN
					SET @sqlcmd = NULL
					SELECT @Message = '** Skipping database ' + @dbname + ': Could not find a valid path to create DB snapshot - ' + CONVERT(VARCHAR, GETDATE())
					RAISERROR(@Message, 0, 42) WITH NOWAIT;
				END
				
				IF @HasROFG > 0 AND @SingleUser = 1
				BEGIN
					SET @sqlcmd = 'USE master;
ALTER DATABASE [' + @dbname + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10) + @sqlcmd + CHAR(10) + 
'USE master;
ALTER DATABASE [' + @dbname + '] SET MULTI_USER WITH ROLLBACK IMMEDIATE;'
				END

				IF @sqlcmd_Create IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Creating database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	

					EXEC sp_executesql @sqlcmd_Create;
				END TRY
				BEGIN CATCH
					EXEC sp_executesql @sqlcmd_Drop;
					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Create Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH

				IF @sqlcmd IS NOT NULL
				BEGIN TRY					
					EXEC sp_executesql @sqlcmd;

					UPDATE tblFgBuckets
					SET isdone = 1
					FROM tblFgBuckets
					WHERE [database_id] = @dbid AND [data_space_id] = @fg_id AND used_page_count = @used_page_count AND isdone = 0 AND BucketId = @TodayBucket
				END TRY
				BEGIN CATCH
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Check cycle - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
					RETURN
				END CATCH
				
				IF @sqlcmd_Drop IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Droping database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	
					EXEC sp_executesql @sqlcmd_Drop;
				END TRY
				BEGIN CATCH
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Drop Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH
			END;

			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
			SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started catalog checks on ' + @dbname + '_CheckDB_Snapshot';
			
			IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
			SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started catalog checks on ' + @dbname;

			RAISERROR (@msg, 10, 1) WITH NOWAIT

			IF @HasROFG > 0 AND @CreateSnap = 1
			SET @sqlcmd = 'DBCC CHECKCATALOG (''' + @dbname + '_CheckDB_Snapshot'');'
			
			IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
			SET @sqlcmd = 'DBCC CHECKCATALOG (' + CONVERT(NVARCHAR(10),@dbid) + ');'

			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
			BEGIN
				TRUNCATE TABLE #tblSnapFiles;
				
				INSERT INTO #tblSnapFiles
				SELECT name, 0 FROM sys.master_files WHERE database_id = @dbid AND [type] = 0;
				
				SET @filecreateid = 1
				SET @sqlsnapcmd = ''

				WHILE (SELECT COUNT([name]) FROM #tblSnapFiles WHERE isdone = 0) > 0
				BEGIN
					SELECT TOP 1 @filename = [name] FROM #tblSnapFiles WHERE isdone = 0
					SET @sqlsnapcmd = @sqlsnapcmd + CHAR(10) + '(NAME = [' + @filename + '], FILENAME = ''' + @SnapPath + '\' + @dbname + '_CheckDB_Snapshot_Data_' + CONVERT(VARCHAR(10), @filecreateid) + '.ss''),'
					SET @filecreateid = @filecreateid + 1

					UPDATE #tblSnapFiles
					SET isdone = 1 WHERE [name] = @filename;
				END;

				SELECT @sqlsnapcmd = LEFT(@sqlsnapcmd, LEN(@sqlsnapcmd)-1);

				SET @sqlcmd_Create = 'USE master;
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'')
CREATE DATABASE [' + @dbname + '_CheckDB_Snapshot] ON ' + @sqlsnapcmd + CHAR(10) + 'AS SNAPSHOT OF [' + @dbname + '];' 
				
				SET @sqlcmd_Drop = 'USE master; 
IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'') 
DROP DATABASE [' + @dbname + '_CheckDB_Snapshot];'
			END
			
			IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NULL
			BEGIN
				SET @sqlcmd = NULL
				SELECT @Message = '** Skipping database ' + @dbname + ': Could not find a valid path to create DB snapshot - ' + CONVERT(VARCHAR, GETDATE())
				RAISERROR(@Message, 0, 42) WITH NOWAIT;
			END
			
			IF @HasROFG > 0 AND @SingleUser = 1
			BEGIN
				SET @sqlcmd = 'USE master;
ALTER DATABASE [' + @dbname + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10) + @sqlcmd + CHAR(10) + 
'USE master;
ALTER DATABASE [' + @dbname + '] SET MULTI_USER WITH ROLLBACK IMMEDIATE;'
			END
			
				IF @sqlcmd_Create IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Creating database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	
					EXEC sp_executesql @sqlcmd_Create;
				END TRY
				BEGIN CATCH
					EXEC sp_executesql @sqlcmd_Drop;
					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Create Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH

				IF @sqlcmd IS NOT NULL
				BEGIN TRY					
					EXEC sp_executesql @sqlcmd;

					UPDATE tblFgBuckets
					SET isdone = 1
					FROM tblFgBuckets
					WHERE [database_id] = @dbid AND [data_space_id] = @fg_id AND used_page_count = @used_page_count AND isdone = 0 AND BucketId = @TodayBucket
				END TRY
				BEGIN CATCH					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Check cycle - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
					RETURN
				END CATCH
				
				IF @sqlcmd_Drop IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Droping database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	
					EXEC sp_executesql @sqlcmd_Drop;
				END TRY
				BEGIN CATCH
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Drop Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH
		END

		IF @VLDBMode = 0 -- Now do table checks on todays bucket
		BEGIN
			WHILE (SELECT COUNT(*) FROM tblDbBuckets WHERE [database_id] = @dbid AND isdone = 0 AND BucketId = @TodayBucket
                               -- Confirm the table still exists
                               AND OBJECT_ID(N'[' + DB_NAME(database_id) + '].[' + [schema] + '].[' + [name] + ']') IS NOT NULL) > 0
			BEGIN
				SELECT TOP 1 @name = [name], @schema = [schema], @used_page_count = used_page_count
				FROM tblDbBuckets
				WHERE [database_id] = @dbid AND isdone = 0 AND BucketId = @TodayBucket
				ORDER BY used_page_count DESC

				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started table checks on ' + @dbname + ' - table ' + @schema + '.' + @name;
				RAISERROR (@msg, 10, 1) WITH NOWAIT

				SET @sqlcmd = 'USE [' + @dbname + '];
DBCC CHECKTABLE (''' + @schema + '.' + @name + ''') WITH '

				IF @Physical = 1
				BEGIN
					SET @sqlcmd = @sqlcmd + 'PHYSICAL_ONLY;'
				END
				ELSE
				BEGIN
					SET @sqlcmd = @sqlcmd + 'DATA_PURITY;'
				END;

				IF @sqlcmd IS NOT NULL
				BEGIN TRY
					EXEC sp_executesql @sqlcmd;

					UPDATE tblDbBuckets
					SET isdone = 1
					FROM tblDbBuckets
					WHERE [database_id] = @dbid AND [name] = @name AND [schema] = @schema AND used_page_count = @used_page_count AND isdone = 0 AND BucketId = @TodayBucket
				END TRY
				BEGIN CATCH					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH
			END
		END

		IF @VLDBMode = 1 -- Now do filegroup checks on todays bucket
		BEGIN
			WHILE (SELECT COUNT(*) FROM tblFgBuckets WHERE [database_id] = @dbid AND isdone = 0 AND BucketId = @TodayBucket) > 0
			BEGIN
				SELECT TOP 1 @fg_id = [data_space_id], @name = [name], @used_page_count = used_page_count
				FROM tblFgBuckets
				WHERE [database_id] = @dbid AND isdone = 0 AND BucketId = @TodayBucket
				ORDER BY used_page_count DESC

				SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Started filegroup checks on [' + @dbname + '] - filegroup ' + @name;
				RAISERROR (@msg, 10, 1) WITH NOWAIT

				IF @HasROFG > 0 AND @CreateSnap = 1
				SET @sqlcmd = 'USE [' + @dbname + '_CheckDB_Snapshot];
DBCC CHECKFILEGROUP (' + CONVERT(NVARCHAR(10), @fg_id) + ')'
				
				IF (@HasROFG > 0 AND @SingleUser = 1) OR (@HasROFG = 0)
				SET @sqlcmd = 'USE [' + @dbname + '];
DBCC CHECKFILEGROUP (' + CONVERT(NVARCHAR(10), @fg_id) + ')'

				IF @Physical = 1
				BEGIN
					SET @sqlcmd = @sqlcmd + ' WITH PHYSICAL_ONLY;'
				END
				ELSE
				BEGIN
					SET @sqlcmd = @sqlcmd + ';'
				END;

				IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NOT NULL
				BEGIN
					TRUNCATE TABLE #tblSnapFiles;
				
					INSERT INTO #tblSnapFiles
					SELECT name, 0 FROM sys.master_files WHERE database_id = @dbid AND [type] = 0;
				
					SET @filecreateid = 1
					SET @sqlsnapcmd = ''

					WHILE (SELECT COUNT([name]) FROM #tblSnapFiles WHERE isdone = 0) > 0
					BEGIN
						SELECT TOP 1 @filename = [name] FROM #tblSnapFiles WHERE isdone = 0
						SET @sqlsnapcmd = @sqlsnapcmd + CHAR(10) + '(NAME = [' + @filename + '], FILENAME = ''' + @SnapPath + '\' + @dbname + '_CheckDB_Snapshot_Data_' + CONVERT(VARCHAR(10), @filecreateid) + '.ss''),'
						SET @filecreateid = @filecreateid + 1

						UPDATE #tblSnapFiles
						SET isdone = 1 WHERE [name] = @filename;
					END;

					SELECT @sqlsnapcmd = LEFT(@sqlsnapcmd, LEN(@sqlsnapcmd)-1);

					SET @sqlcmd_Create = 'USE master;
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'')
CREATE DATABASE [' + @dbname + '_CheckDB_Snapshot] ON ' + @sqlsnapcmd + CHAR(10) + 'AS SNAPSHOT OF [' + @dbname + '];' 

					SET @sqlcmd_Drop = 'USE master; 
IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = ''' + @dbname + '_CheckDB_Snapshot'') 
DROP DATABASE [' + @dbname + '_CheckDB_Snapshot];'
				END;
			
				IF @HasROFG > 0 AND @CreateSnap = 1 AND @SnapPath IS NULL
				BEGIN
					SET @sqlcmd = NULL
					SELECT @Message = '** Skipping database ' + @dbname + ': Could not find a valid path to create DB snapshot - ' + CONVERT(VARCHAR, GETDATE())
					RAISERROR(@Message, 0, 42) WITH NOWAIT;
				END
				
				IF @HasROFG > 0 AND @SingleUser = 1
				BEGIN
					SET @sqlcmd = 'USE master;
ALTER DATABASE [' + @dbname + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10) + @sqlcmd + CHAR(10) + 
'USE master;
ALTER DATABASE [' + @dbname + '] SET MULTI_USER WITH ROLLBACK IMMEDIATE;'
				END
				
				IF @sqlcmd_Create IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Creating database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	
					EXEC sp_executesql @sqlcmd_Create;
				END TRY
				BEGIN CATCH
					EXEC sp_executesql @sqlcmd_Drop;
					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Create Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH

				IF @sqlcmd IS NOT NULL
				BEGIN TRY					
					EXEC sp_executesql @sqlcmd;

					UPDATE tblFgBuckets
					SET isdone = 1
					FROM tblFgBuckets
					WHERE [database_id] = @dbid AND [data_space_id] = @fg_id AND used_page_count = @used_page_count AND isdone = 0 AND BucketId = @TodayBucket
				END TRY
				BEGIN CATCH					
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Check cycle - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
					RETURN
				END CATCH
				
				IF @sqlcmd_Drop IS NOT NULL
				BEGIN TRY
					SELECT @msg = CONVERT(VARCHAR, GETDATE(), 9) + ' - Droping database snapshot ' + @dbname + '_CheckDB_Snapshot';
					RAISERROR (@msg, 10, 1) WITH NOWAIT	
					EXEC sp_executesql @sqlcmd_Drop;
				END TRY
				BEGIN CATCH
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Drop Snapshot - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH
			END
		END
	END;
 
	UPDATE #tmpdbs
	SET isdone = 1
	FROM #tmpdbs
	WHERE [dbid] = @dbid AND isdone = 0
END;

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
DROP TABLE #tmpdbs
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblObj'))
DROP TABLE #tblObj;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblBuckets'))
DROP TABLE #tblBuckets;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFGs'))
DROP TABLE #tblFGs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSnapFiles'))
DROP TABLE #tblSnapFiles;

SELECT @Message = '** Finished: ' + CONVERT(VARCHAR, GETDATE())
RAISERROR(@Message, 0, 42) WITH NOWAIT;

GO

PRINT 'Procedure usp_CheckIntegrity created';
GO

------------------------------------------------------------------------------------------------------------------------------	

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'Weekly Maintenance')
EXEC msdb.dbo.sp_delete_job @job_name=N'Weekly Maintenance', @delete_unused_schedule=1
GO

PRINT 'Creating Weekly Maintenance job';
GO

BEGIN TRANSACTION

-- Set the Operator name to receive notifications, if any. Set the job owner, if not sa.
DECLARE @customoper sysname, @jobowner sysname
SET @customoper = 'SQLAdmins'
SET @jobowner = 'sa'

DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
IF EXISTS (SELECT name FROM msdb.dbo.sysoperators WHERE name = @customoper)
BEGIN
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Weekly Maintenance', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=3, 
		@notify_level_netsend=2, 
		@notify_level_page=2,  
		@delete_level=0, 
		@description=N'Runs weekly maintenance cycle. Most steps execute on Sundays only. For integrity checks, depending on whether the database in scope is a VLDB or not, different actions are executed. See job steps for further detail.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=@jobowner, 
		@notify_email_operator_name=@customoper, 
		@job_id = @jobId OUTPUT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END
ELSE
BEGIN
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Weekly Maintenance', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=3, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Runs weekly maintenance cycle. Most steps execute on Sundays only. For integrity checks, depending on whether the database in scope is a VLDB or not, different actions are executed. See job steps for further detail.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=@jobowner,
		@job_id = @jobId OUTPUT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DBCC CheckDB', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/* 
This checks the logical and physical integrity of all the objects in the specified database by performing the following operations: 
|-For VLDBs (larger than 1TB):
  |- On Sundays, if VLDB Mode = 0, runs DBCC CHECKALLOC.
  |- On Sundays, runs DBCC CHECKCATALOG.
  |- Everyday, if VLDB Mode = 0, runs DBCC CHECKTABLE or if VLDB Mode = 1, DBCC CHECKFILEGROUP on a subset of tables and views, divided by daily buckets.
|-For DBs smaller than 1TB:
  |- Every Sunday a DBCC CHECKDB checks the logical and physical integrity of all the objects in the specified database.

To set how VLDBs are handled, set @VLDBMode to 0 = Bucket by Table Size or 1 = Bucket by Filegroup Size

IMPORTANT: Consider running DBCC CHECKDB routinely (at least, weekly). On large databases and for more frequent checks, consider using the PHYSICAL_ONLY parameter.
http://msdn.microsoft.com/en-us/library/ms176064.aspx
http://blogs.msdn.com/b/sqlserverstorageengine/archive/2006/10/20/consistency-checking-options-for-a-vldb.aspx

If a database has Read-Only filegroups, any integrity check will fail if there are other open connections to the database.

Setting @CreateSnap = 1 will create a database snapshot before running the check on the snapshot, and drop it at the end (default).
Setting @CreateSnap = 0 means the integrity check might fail if there are other open connection on the database.


If snapshots are not allowed and a database has Read-Only filegroups, any integrity check will fail if there are other openned connections to the database.
Setting @SingleUser = 1 will set the database in single user mode before running the check, and to multi user afterwards.
Setting @SingleUser = 0 means the integrity check might fail if there are other open connection on the database.
*/

EXEC msdb.dbo.usp_CheckIntegrity @VLDBMode = 1, @SingleUser = 0, @CreateSnap = 1
', 
		@database_name=N'master', 
		@flags=20
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'update usage', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/*
DBCC UPDATEUSAGE corrects the rows, used pages, reserved pages, leaf pages and data page counts for each partition in a table or index.
IMPORTANT: Consider running DBCC UPDATEUSAGE routinely (for example, weekly) only if the database undergoes frequent Data Definition Language (DDL) modifications, such as CREATE, ALTER, or DROP statements.
http://msdn.microsoft.com/en-us/library/ms188414.aspx

Exludes all Offline or Read-Only DBs. Also excludes all databases over 4GB in size.
*/

SET NOCOUNT ON;
-- Is it Sunday yet?
IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
BEGIN
	PRINT ''** Start: '' + CONVERT(VARCHAR, GETDATE())
	DECLARE @dbname sysname, @sqlcmd NVARCHAR(500)
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.#tmpdbs''))
	CREATE TABLE #tmpdbs (id int IDENTITY(1,1), [dbname] sysname, isdone bit)

	INSERT INTO #tmpdbs ([dbname], isdone)
	(SELECT DISTINCT QUOTENAME(d.name), 0 FROM sys.databases d 
	INNER JOIN sys.master_files smf ON d.database_id = smf.database_id
	JOIN sys.dm_hadr_database_replica_states hadrdrs ON d.database_id = hadrdrs.database_id
	WHERE d.is_read_only = 0 AND d.state = 0 AND d.database_id <> 2 AND smf.type = 0 AND (smf.size * 8)/1024 < 4096 AND hadrdrs.is_primary_replica = 1)
	UNION
	(SELECT DISTINCT QUOTENAME(d.name), 0 FROM sys.databases d 
	INNER JOIN sys.master_files smf ON d.database_id = smf.database_id
	LEFT JOIN sys.dm_hadr_database_replica_states hadrdrs ON d.database_id = hadrdrs.database_id
	WHERE d.is_read_only = 0 AND d.state = 0 AND d.database_id <> 2 AND smf.type = 0 AND (smf.size * 8)/1024 < 4096 AND hadrdrs.database_id IS NULL);

	WHILE (SELECT COUNT([dbname]) FROM #tmpdbs WHERE isdone = 0) > 0
	BEGIN
		SET @dbname = (SELECT TOP 1 [dbname] FROM #tmpdbs WHERE isdone = 0)
		SET @sqlcmd = ''DBCC UPDATEUSAGE ('' + @dbname + '')''
		PRINT CHAR(10) + CONVERT(VARCHAR, GETDATE()) + '' - Started space corrections on '' + @dbname
		EXECUTE sp_executesql @sqlcmd
		PRINT CONVERT(VARCHAR, GETDATE()) + '' - Ended space corrections on '' + @dbname
			
		UPDATE #tmpdbs
		SET isdone = 1
		FROM #tmpdbs
		WHERE [dbname] = @dbname AND isdone = 0
	END;

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.#tmpdbs''))
	DROP TABLE #tmpdbs;

	PRINT ''** Finished: '' + CONVERT(VARCHAR, GETDATE())
END
ELSE
BEGIN
	PRINT ''** Skipping: Today is not Sunday - '' + CONVERT(VARCHAR, GETDATE())
END;', 
		@database_name=N'master', 
		@flags=20
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_createstats', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/*
Creates statistics only on columns that are part of an existing index, and are not the first column in any index definition. 
Creating single-column statistics increases the number of histograms, which can improve cardinality estimates, query plans, and query performance. 
The first column of a statistics object has a histogram; other columns do not have a histogram. 

http://msdn.microsoft.com/en-us/library/ms186834.aspx

Exludes all Offline and Read-Only DBs
*/

SET NOCOUNT ON;
-- Is it Sunday yet?
IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
BEGIN
	PRINT ''** Start: '' + CONVERT(VARCHAR, GETDATE())
	DECLARE @dbname sysname, @sqlcmd NVARCHAR(500)

	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.#tmpdbs''))
	CREATE TABLE #tmpdbs (id int IDENTITY(1,1), [dbname] sysname, isdone bit)

	INSERT INTO #tmpdbs ([dbname], isdone)
	(SELECT QUOTENAME(name), 0 FROM sys.databases JOIN sys.dm_hadr_database_replica_states hadrdrs ON d.database_id = hadrdrs.database_id WHERE is_read_only = 0 AND state = 0 AND database_id > 4 AND is_distributor = 0 AND hadrdrs.is_primary_replica = 1)
	UNION
	(SELECT QUOTENAME(name), 0 FROM sys.databases LEFT JOIN sys.dm_hadr_database_replica_states hadrdrs ON d.database_id = hadrdrs.database_id WHERE is_read_only = 0 AND state = 0 AND database_id > 4 AND is_distributor = 0 AND hadrdrs.database_id IS NULL);

	WHILE (SELECT COUNT([dbname]) FROM #tmpdbs WHERE isdone = 0) > 0
	BEGIN
		SET @dbname = (SELECT TOP 1 [dbname] FROM #tmpdbs WHERE isdone = 0)
		SET @sqlcmd = @dbname + ''.dbo.sp_createstats @indexonly = ''''indexonly''''''
		SELECT CHAR(10) + CONVERT(VARCHAR, GETDATE()) + '' - Started indexed stats creation on '' + @dbname
		EXECUTE sp_executesql @sqlcmd
		SELECT CONVERT(VARCHAR, GETDATE()) + '' - Ended indexed stats creation on '' + @dbname

		UPDATE #tmpdbs
		SET isdone = 1
		FROM #tmpdbs
		WHERE [dbname] = @dbname AND isdone = 0
	END;

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.#tmpdbs''))
	DROP TABLE #tmpdbs;
	PRINT ''** Finished: '' + CONVERT(VARCHAR, GETDATE())
END
ELSE
BEGIN
	PRINT ''** Skipping: Today is not Sunday - '' + CONVERT(VARCHAR, GETDATE())
END;', 
		@database_name=N'master', 
		@flags=20
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup Job History', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'-- Cleans msdb job history older than 30 days
SET NOCOUNT ON;
-- Is it Sunday yet?
IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
BEGIN
	DECLARE @date DATETIME
	SET @date = GETDATE()-30
	EXEC msdb.dbo.sp_purge_jobhistory @oldest_date=@date;
END
ELSE
BEGIN
	PRINT ''** Skipping: Today is not Sunday - '' + CONVERT(VARCHAR, GETDATE())
END;', 
		@database_name=N'msdb', 
		@flags=20
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cleanup Maintenance Plan txt reports', 
		@step_id=5, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'-- Cleans maintenance plans txt reports older than 30 days
SET NOCOUNT ON;
-- Is it Sunday yet?
IF (SELECT 1 & POWER(2, DATEPART(weekday, GETDATE())-1)) > 0
BEGIN
	DECLARE @path NVARCHAR(500), @date DATETIME
	DECLARE @sqlcmd NVARCHAR(1000), @params NVARCHAR(100), @sqlmajorver int

	SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
	SET @date = GETDATE()-30

	IF @sqlmajorver < 11
	BEGIN
		EXEC master..xp_instance_regread N''HKEY_LOCAL_MACHINE'',N''Software\Microsoft\MSSQLServer\Setup'',N''SQLPath'', @path OUTPUT
		SET @path = @path + ''\LOG''
	END
	ELSE
	BEGIN
		SET @sqlcmd = N''SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations'';
		SET @params = N''@pathOUT NVARCHAR(2048) OUTPUT'';
		EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
	END

	-- Default location for maintenance plan txt files is the Log folder. 
	-- If you changed from the default location since you last installed SQL Server, uncomment below and set the custom desired path.
	--SET @path = ''C:\custom_location''

	EXECUTE master..xp_delete_file 1,@path,N''txt'',@date,1
END
ELSE
BEGIN
	PRINT ''** Skipping: Today is not Sunday - '' + CONVERT(VARCHAR, GETDATE())
END;', 
		@database_name=N'master', 
		@flags=20
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Weekly Maintenance - Sundays', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20071009, 
		@active_end_date=99991231, 
		@active_start_time=83000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Weekly Maintenance - Weekdays and Saturdays', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=126, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20131017, 
		@active_end_date=99991231, 
		@active_start_time=10000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

PRINT 'Weekly Maintenance job created';
GO
