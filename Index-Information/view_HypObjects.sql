--
-- 2012-06-14 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights/)
--
-- List Hypothetical objects (with drop statements);
--

SET NOCOUNT ON;

DECLARE @i int, @maxi int, @dbname sysname, @sqlcmd NVARCHAR(4000), @dbid int, @ErrorMessage NVARCHAR(500)

IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
CREATE TABLE #tmpdbs (id int IDENTITY(1,1), [dbid] int, [dbname] sysname)

INSERT INTO #tmpdbs ([dbid], [dbname])
SELECT database_id, name FROM master.sys.databases WHERE is_read_only = 0 AND state = 0 AND database_id > 4 AND is_distributor = 0;

IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHypObj'))
CREATE TABLE #tblHypObj ([DBName] sysname, [Table] VARCHAR(255), [Object] VARCHAR(255), [Type] VARCHAR(10))

SET @i = 1
SET @maxi = (SELECT MAX(id) FROM #tmpdbs)

WHILE @i <= @maxi
BEGIN
	SET @dbname = (SELECT [dbname] FROM #tmpdbs WHERE id = @i)
	SET @dbid = (SELECT [dbid] FROM #tmpdbs WHERE id = @i)
	SET @sqlcmd = 'SELECT ''' + @dbname + ''' AS [DBName], QUOTENAME(o.[name]), i.name, ''INDEX'' FROM ' + QUOTENAME(@dbname) + '.sys.indexes i 
INNER JOIN sys.objects o ON o.[object_id] = i.[object_id] 
INNER JOIN sys.tables AS mst ON mst.[object_id] = i.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE i.is_hypothetical = 1
UNION ALL
SELECT ''' + @dbname + ''' AS [DBName], QUOTENAME(o.[name]), s.name, ''STATISTICS'' FROM ' + QUOTENAME(@dbname) + '.sys.stats s 
INNER JOIN sys.objects o (NOLOCK) ON o.[object_id] = s.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = s.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE (s.name LIKE ''hind_%'' OR s.name LIKE ''_dta_stat%'') AND auto_created = 0
AND s.name NOT IN (SELECT name FROM ' + QUOTENAME(@dbname) + '.sys.indexes)'

	BEGIN TRY
		INSERT INTO #tblHypObj
		EXECUTE sp_executesql @sqlcmd
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Hypothetical objects subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage,16,1);
	END CATCH
	
	SET @i = @i + 1
END	

IF (SELECT COUNT([Object]) FROM #tblHypObj) > 0
BEGIN
	SELECT 'Hypothetical_objects' AS [Information], '[WARNING: Some databases have indexes or statistics that are marked as hypothetical. It is recommended to drop these objects as soon as possible]' AS [Deviation]
	SELECT 'Hypothetical_objects' AS [Information], DBName AS [Database Name], [Table] AS [Table Name], [Object] AS [Object Name], [Type] AS [Object Type]
	FROM #tblHypObj
	ORDER BY 2, 3, 5
	
	DECLARE @strSQL NVARCHAR(4000)
	PRINT '--** Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */' + CHAR(10)

	PRINT CHAR(10) + '--############# Existing Hypothetical objects drop statements #############' + CHAR(10)
	
	DECLARE ITW_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DBName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM ' + CASE WHEN [Type] = 'STATISTICS' THEN 'sys.stats' ELSE 'sys.indexes' END + ' WHERE name = N'''+ [Object] + ''')' + CHAR(10) +
	CASE WHEN [Type] = 'STATISTICS' THEN 'DROP STATISTICS ' + [Table] + '.' +  QUOTENAME([Object]) + ';' + CHAR(10) + 'GO' + CHAR(10)
		ELSE 'DROP INDEX ' + QUOTENAME([Object]) + ' ON ' + [Table] + ';' + CHAR(10) + 'GO' + CHAR(10) 
		END
	FROM #tblHypObj
	ORDER BY DBName, [Table]

	OPEN ITW_Stats
	FETCH NEXT FROM ITW_Stats INTO @strSQL
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		PRINT @strSQL
		FETCH NEXT FROM ITW_Stats INTO @strSQL
	END
	CLOSE ITW_Stats
	DEALLOCATE ITW_Stats

	PRINT '--############# Ended Hypothetical objects drop statements #############' + CHAR(10)

END
ELSE
BEGIN
	SELECT 'Hypothetical_objects' AS [Information], '[OK]' AS [Deviation]
END;

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs'))
DROP TABLE #tmpdbs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHypObj'))
DROP TABLE #tblHypObj;
GO