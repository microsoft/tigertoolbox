-- 04/01/2012 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights/)
--
-- Checks for statistics last update date in the current database.
--
-- 11/02/2016 Fixed rows col when sys.dm_db_stats_properties returns null
--

DECLARE @sqlcmd NVARCHAR(4000), @sqlmajorver int, @sqlminorver int, @sqlbuild int

SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff);
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);

IF (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4000) OR (@sqlmajorver = 11 AND @sqlbuild >= 3000) OR @sqlmajorver > 11
BEGIN
	SET @sqlcmd = 'USE ' + QUOTENAME(DB_NAME()) + ';
SELECT DISTINCT ''' + CONVERT(VARCHAR(12),DB_ID()) + ''' AS [databaseID], mst.[object_id] AS objectID, ss.[stats_id], ''' + DB_NAME() + ''' AS [DatabaseName], t.name AS schemaName, OBJECT_NAME(mst.[object_id]) AS tableName, ss.name AS [stat_name], ISNULL(sp.[rows],SUM(p.[rows])) AS [rows], sp.modification_counter, STATS_DATE(o.[object_id], ss.[stats_id]) AS [stats_date]
FROM sys.stats AS ss 
	INNER JOIN sys.objects AS o ON o.[object_id] = ss.[object_id]
	INNER JOIN sys.tables AS mst ON mst.[object_id] = o.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.partitions AS p ON p.[object_id] = ss.[object_id]
	CROSS APPLY sys.dm_db_stats_properties(ss.[object_id], ss.[stats_id]) AS sp
GROUP BY o.[object_id], mst.[object_id], t.name, ss.stats_id, ss.name, sp.[rows], sp.modification_counter
ORDER BY t.name, OBJECT_NAME(mst.[object_id]), ss.name'
END
ELSE
BEGIN
	SET @sqlcmd = 'USE ' + QUOTENAME(DB_NAME()) + ';
SELECT DISTINCT ''' + CONVERT(VARCHAR(12),DB_ID()) + ''' AS [databaseID], mst.[object_id] AS objectID, ss.[stats_id], ''' + DB_NAME() + ''' AS [DatabaseName], t.name AS schemaName, OBJECT_NAME(mst.[object_id]) AS tableName, ss.name AS [stat_name], SUM(p.[rows]) AS [rows], rowmodctr AS modification_counter, STATS_DATE(o.[object_id], ss.[stats_id]) AS [stats_date]
FROM sys.stats AS ss
	INNER JOIN sys.sysindexes AS si ON si.id = ss.[object_id]
	INNER JOIN sys.objects AS o ON o.[object_id] = si.id
	INNER JOIN sys.tables AS mst ON mst.[object_id] = o.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.partitions AS p ON p.[object_id] = ss.[object_id]
	LEFT JOIN sys.indexes i ON si.id = i.[object_id] AND si.indid = i.index_id
WHERE o.type <> ''S'' AND i.name IS NOT NULL
GROUP BY o.[object_id], mst.[object_id], t.name, rowmodctr, ss.stats_id, ss.name
ORDER BY t.name, OBJECT_NAME(mst.[object_id]), ss.name'
END

EXECUTE sp_executesql @sqlcmd