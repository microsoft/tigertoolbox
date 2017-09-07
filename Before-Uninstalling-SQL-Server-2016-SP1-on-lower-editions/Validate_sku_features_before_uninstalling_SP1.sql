SET NOCOUNT ON;
DECLARE @database_id int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000), @ErrorMessage NVARCHAR(1000), @sqlmajorver int

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
DROP TABLE #tmpdbs;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
CREATE TABLE #tmpdbs (id int IDENTITY(1,1), [database_id] int, [dbname] VARCHAR(1000), is_database_joined bit, isdone bit);

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerSku'))
DROP TABLE #tblPerSku;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerSku'))
CREATE TABLE #tblPerSku ([dbname] sysname NULL, [feature_name] VARCHAR(100));

/*
Reference: SERVERPROPERTY for sql major versions supported after:
@sqlmajorver >= 13 OR (@sqlmajorver = 12 AND @sqlbuild >= 2556 AND @sqlbuild < 4100) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427)
*/
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff)

SET @sqlcmd = 'SELECT sd.database_id, sd.name, rcs.is_database_joined, 0 
FROM master.sys.databases (NOLOCK) sd
	LEFT JOIN sys.dm_hadr_database_replica_states (NOLOCK) d ON sd.database_id = d.database_id
	LEFT JOIN sys.availability_replicas ar (NOLOCK) ON d.group_id = ar.group_id AND d.replica_id = ar.replica_id
	LEFT JOIN sys.dm_hadr_availability_replica_states (NOLOCK) ars ON d.group_id = ars.group_id AND d.replica_id = ars.replica_id
	LEFT JOIN sys.dm_hadr_database_replica_cluster_states (NOLOCK) rcs ON rcs.database_name = sd.name AND rcs.replica_id = ar.replica_id
WHERE sd.[state] = 0 AND sd.database_id > 4
GROUP BY sd.database_id, sd.name, sd.is_read_only, sd.[state], sd.is_distributor, ar.secondary_role_allow_connections, sd.[compatibility_level], rcs.is_database_joined, rcs.is_failover_ready
HAVING MIN(COALESCE(ars.[role],1)) <> 2;'

INSERT INTO #tmpdbs ([database_id], [dbname], is_database_joined, [isdone])
EXEC sp_executesql @sqlcmd;

WHILE (SELECT COUNT(id) FROM #tmpdbs WHERE isdone = 0) > 0
BEGIN
	SELECT TOP 1 @dbname = [dbname], @database_id = [database_id] FROM #tmpdbs WHERE isdone = 0
			
	SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], feature_name FROM sys.dm_db_persisted_sku_features (NOLOCK)
UNION ALL
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''ChangeTracking'' AS feature_name FROM sys.change_tracking_databases (NOLOCK) WHERE database_id = DB_ID()
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''RowLevelSecurity'' AS feature_name FROM sys.security_policies (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''FineGrainedAuditing'' AS feature_name FROM sys.database_audit_specifications (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''AlwaysEncrypted'' AS feature_name FROM sys.column_master_keys (NOLOCK)'

IF @sqlmajorver >= 13
SET @sqlcmd = @sqlcmd + CHAR(10) + 'UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Polybase'' AS feature_name FROM sys.external_data_sources (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''DynamicDataMasking'' AS feature_name FROM sys.masked_columns (NOLOCK) WHERE is_masked = 1'

	BEGIN TRY
		INSERT INTO #tblPerSku
		EXECUTE sp_executesql @sqlcmd
	END TRY
	BEGIN CATCH
		;THROW
	END CATCH
			
	UPDATE #tmpdbs
	SET isdone = 1
	WHERE [database_id] = @database_id
END;
	
IF (SELECT COUNT(DISTINCT [name]) FROM master.sys.databases (NOLOCK) WHERE database_id NOT IN (2,3) AND source_database_id IS NOT NULL) > 0 -- Snapshot
BEGIN
	INSERT INTO #tblPerSku
	SELECT DISTINCT [name], 'DatabaseSnapshot' AS feature_name FROM master.sys.databases (NOLOCK) WHERE database_id NOT IN (2,3) AND source_database_id IS NOT NULL;
END;

IF (SELECT COUNT([dbname]) FROM #tblPerSku) > 0
BEGIN
	SELECT [Feature_Name], [dbname] AS [Database_Name]
	FROM #tblPerSku
	ORDER BY [Feature_Name], [dbname];

	THROW 60000, 'The instance cannot be downgraded from SP1 as it contains at least 1 database mentioned above with SKU features not available in SQL Server 2016 RTM. If downgrade is attempted, it can leave the database in suspect mode. DROP or DISABLE the feature and rerun the script to confirm before you downgrade',0
END
ELSE
BEGIN
	;THROW 60000,'The instance can be downgraded as it does not contain any database leveraging features that were only enabled on lower editions with SP1',0
END