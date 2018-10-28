-- 2010-09-22 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights)
--
-- 2013-12-03 Fixed divide by zero error
--
-- Recomends type of compression per object - all more trustworthy as instance uptime increases.
--
-- [Percent_Update]
-- The percentage of update operations on a specific table, index, or partition, relative to total operations on that object. The lower the value of U (that is, the table, index, or partition is infrequently updated), the better candidate it is for page compression. 
--
-- [Percent_Scan]
-- The percentage of scan operations on a table, index, or partition, relative to total operations on that object. The higher the value of Scan (that is, the table, index, or partition is mostly scanned), the better candidate it is for page compression.
--
-- [Compression_Type_Recommendation] - READ DataCompression Best Practises before implementing.
-- When ? means ROW if object suffers mainly UPDATES, PAGE if mainly INSERTS
-- When NO_GAIN means that according to sp_estimate_data_compression_savings no space gains will be attained when compressing.
--
-- based on Data Compression Whitepaper at http://msdn.microsoft.com/en-us/library/dd894051(SQL.100).aspx
--
-- General algorithm validated by Paul Randall IF ENOUGH CPU AND RAM AVAILABLE.
-- 
SET NOCOUNT ON;

CREATE TABLE ##tmpCompression ([Schema] sysname,
	[Table_Name] sysname,
	[Index_Name] sysname NULL,
	[Partition] int,
	[Index_ID] int,
	[Index_Type] VARCHAR(12),
	[Percent_Scan] smallint,
	[Percent_Update] smallint,
	[ROW_estimate_Pct_of_orig] smallint,
	[PAGE_estimate_Pct_of_orig] smallint,
	[Compression_Type_Recommendation] VARCHAR(7)
);

CREATE TABLE ##tmpEstimateRow (
	objname sysname,
	schname sysname,
	indid int,
	partnr int,
	size_cur bigint,
	size_req bigint,
	sample_cur bigint,
	sample_req bigint
);

CREATE TABLE ##tmpEstimatePage (
	objname sysname,
	schname sysname,
	indid int,
	partnr int,
	size_cur bigint,
	size_req bigint,
	sample_cur bigint,
	sample_req bigint
);

INSERT INTO ##tmpCompression ([Schema], [Table_Name], [Index_Name], [Partition], [Index_ID], [Index_Type], [Percent_Scan], [Percent_Update])
SELECT s.name AS [Schema], o.name AS [Table_Name], x.name AS [Index_Name],
       i.partition_number AS [Partition], i.index_id AS [Index_ID], x.type_desc AS [Index_Type],
       i.range_scan_count * 100.0 / (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) AS [Percent_Scan],
       i.leaf_update_count * 100.0 / (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) AS [Percent_Update]
FROM sys.dm_db_index_operational_stats (db_id(), NULL, NULL, NULL) i
	INNER JOIN sys.objects o ON o.object_id = i.object_id
	INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
	INNER JOIN sys.indexes x ON x.object_id = i.object_id AND x.index_id = i.index_id
WHERE (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) <> 0
	AND objectproperty(i.object_id,'IsUserTable') = 1
ORDER BY [Table_Name] ASC;

DECLARE @schema sysname, @tbname sysname, @ixid int
DECLARE cur CURSOR FAST_FORWARD FOR SELECT [Schema], [Table_Name], [Index_ID] FROM ##tmpCompression
OPEN cur
FETCH NEXT FROM cur INTO @schema, @tbname, @ixid
WHILE @@FETCH_STATUS = 0
BEGIN
	--SELECT @schema, @tbname
	INSERT INTO ##tmpEstimateRow
	EXEC ('sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + @ixid + ''', NULL, ''ROW''' );
	INSERT INTO ##tmpEstimatePage
	EXEC ('sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + @ixid + ''', NULL, ''PAGE''');
	FETCH NEXT FROM cur INTO @schema, @tbname, @ixid
END
CLOSE cur
DEALLOCATE cur;

--SELECT * FROM ##tmpEstimateRow
--SELECT * FROM ##tmpEstimatePage;

WITH tmp_CTE (objname, schname, indid, pct_of_orig_row, pct_of_orig_page)
AS (SELECT tr.objname, tr.schname, tr.indid,	
	(tr.sample_req*100)/CASE WHEN tr.sample_cur = 0 THEN 1 ELSE tr.sample_cur END AS pct_of_orig_row,
	(tp.sample_req*100)/CASE WHEN tp.sample_cur = 0 THEN 1 ELSE tp.sample_cur END AS pct_of_orig_page
	FROM ##tmpEstimateRow tr INNER JOIN ##tmpEstimatePage tp ON tr.objname = tp.objname
	AND tr.schname = tp.schname AND tr.indid = tp.indid AND tr.partnr = tp.partnr)
UPDATE ##tmpCompression
SET [ROW_estimate_Pct_of_orig] = tcte.pct_of_orig_row, [PAGE_estimate_Pct_of_orig] = tcte.pct_of_orig_page
FROM tmp_CTE tcte, ##tmpCompression tcomp
WHERE tcte.objname = tcomp.Table_Name AND
tcte.schname = tcomp.[Schema] AND
tcte.indid = tcomp.Index_ID;

WITH tmp_CTE2 (Table_Name, [Schema], Index_ID, [Compression_Type_Recommendation])
AS (SELECT Table_Name, [Schema], Index_ID,
	CASE WHEN [ROW_estimate_Pct_of_orig] >= 100 AND [PAGE_estimate_Pct_of_orig] >= 100 THEN 'NO_GAIN'
		WHEN [Percent_Update] >= 10 THEN 'ROW' 
		WHEN [Percent_Scan] <= 1 AND [Percent_Update] <= 1 AND [ROW_estimate_Pct_of_orig] < [PAGE_estimate_Pct_of_orig] THEN 'ROW'
		WHEN [Percent_Scan] <= 1 AND [Percent_Update] <= 1 AND [ROW_estimate_Pct_of_orig] > [PAGE_estimate_Pct_of_orig] THEN 'PAGE'
		WHEN [Percent_Scan] >= 60 AND [Percent_Update] <= 5 THEN 'PAGE'
		WHEN [Percent_Scan] <= 35 AND [Percent_Update] <= 5 THEN '?'
		ELSE 'ROW'
		END
	FROM ##tmpCompression)
UPDATE ##tmpCompression
SET [Compression_Type_Recommendation] = tcte2.[Compression_Type_Recommendation]
FROM tmp_CTE2 tcte2, ##tmpCompression tcomp2
WHERE tcte2.Table_Name = tcomp2.Table_Name AND
tcte2.[Schema] = tcomp2.[Schema] AND
tcte2.Index_ID = tcomp2.Index_ID;

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

SELECT @StartDate AS Collecting_Data_Since, * FROM ##tmpCompression;

DROP TABLE ##tmpCompression
DROP TABLE ##tmpEstimateRow
DROP TABLE ##tmpEstimatePage;
GO