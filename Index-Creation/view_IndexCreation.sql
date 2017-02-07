--
-- 2007-10-11 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights/)
--
-- 2008-01-17 Check for possibly redundant indexes in the output.
-- 2009-05-21 Changed index scoring method; Disregards indexes with [Score] < 100000 and [User_Hits_on_Missing_Index] < 99;
-- 2013-03-21 Changed database loop method;
-- 2013-11-10 Added search for redundant indexes in missing indexes;

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @IC VARCHAR(4000), @ICWI VARCHAR(4000), @editionCheck bit

/* Refer to http://msdn.microsoft.com/en-us/library/ms174396.aspx */	
IF (SELECT SERVERPROPERTY('EditionID')) IN (1804890536, 1872460670, 610778273, -2117995310)	
SET @editionCheck = 1 -- supports enterprise only features
ELSE	
SET @editionCheck = 0; -- does not support enterprise only features

-- Create the helper functions
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_allcols'')) DROP FUNCTION dbo.fn_createindex_allcols')
EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_allcols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle 
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
')

EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_keycols'')) DROP FUNCTION dbo.fn_createindex_keycols')
EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_keycols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle
		AND (ic.column_usage = ''''EQUALITY'''' OR ic.column_usage = ''''INEQUALITY'''')
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
')

EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_includedcols'')) DROP FUNCTION dbo.fn_createindex_includedcols')
EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_includedcols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle
		AND ic.column_usage = ''''INCLUDE''''
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
')

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexCreation'))
DROP TABLE #IndexCreation
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexCreation'))
CREATE TABLE #IndexCreation (
	[database_id] int,
	DBName VARCHAR(255),
	[Table] VARCHAR(255),
	[ix_handle] int,
	[User_Hits_on_Missing_Index] int,
	[Estimated_Improvement_Percent] DECIMAL(5,2),
	[Avg_Total_User_Cost] int,
	[Unique_Compiles] int,
	[Score] NUMERIC(19,3),
	[KeyCols] VARCHAR(1000),
	[IncludedCols] VARCHAR(4000),
	[Ix_Name] VARCHAR(255),
	[AllCols] NVARCHAR(max),
	[KeyColsOrdered] NVARCHAR(max),
	[IncludedColsOrdered] NVARCHAR(max)
	)

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexRedundant'))
DROP TABLE #IndexRedundant
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexRedundant'))
CREATE TABLE #IndexRedundant (
	DBName VARCHAR(255),
	[Table] VARCHAR(255),
	[Ix_Name] VARCHAR(255),
	[ix_handle] int,
	[KeyCols] VARCHAR(1000),
	[IncludedCols] VARCHAR(4000),
	[Redundant_With] VARCHAR(255)
	)

INSERT INTO #IndexCreation
SELECT i.database_id,
	m.[name],
	RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)) AS [Table],
	i.index_handle AS [ix_handle],
	[User_Hits_on_Missing_Index] = (s.user_seeks + s.user_scans),
	s.avg_user_impact, -- Query cost would reduce by this amount in percentage, on average.
	s.avg_total_user_cost, -- Average cost of the user queries that could be reduced by the index in the group.
	s.unique_compiles, -- Number of compilations and recompilations that would benefit from this missing index group.
	(CONVERT(NUMERIC(19,3), s.user_seeks) + CONVERT(NUMERIC(19,3), s.user_scans)) 
		* CONVERT(NUMERIC(19,3), s.avg_total_user_cost) 
		* CONVERT(NUMERIC(19,3), s.avg_user_impact) AS Score, -- The higher the score, higher is the anticipated improvement for user queries.
	CASE WHEN (i.equality_columns IS NOT NULL AND i.inequality_columns IS NULL) THEN i.equality_columns
			WHEN (i.equality_columns IS NULL AND i.inequality_columns IS NOT NULL) THEN i.inequality_columns
			ELSE i.equality_columns + ',' + i.inequality_columns END AS [KeyCols],
	i.included_columns AS [IncludedCols],
	'IX_' + LEFT(RIGHT(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), LEN(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3))) - (CHARINDEX('.', RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), 1)) - 1),
		LEN(RIGHT(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), LEN(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3))) - (CHARINDEX('.', RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), 1)) - 1)) - 1) + '_' + CAST(i.index_handle AS NVARCHAR) AS [Ix_Name],
	tempdb.dbo.fn_createindex_allcols(i.index_handle), 
	tempdb.dbo.fn_createindex_keycols(i.index_handle),
	tempdb.dbo.fn_createindex_includedcols(i.index_handle)
FROM sys.dm_db_missing_index_details i
INNER JOIN master.sys.databases m ON i.database_id = m.database_id
INNER JOIN sys.dm_db_missing_index_groups g ON i.index_handle = g.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE i.database_id > 4

INSERT INTO #IndexRedundant
SELECT I.DBName, I.[Table], I.[Ix_Name], i.[ix_handle], I.[KeyCols], I.[IncludedCols], I2.[Ix_Name]
FROM #IndexCreation I 
INNER JOIN #IndexCreation I2 ON I.[database_id] = I2.[database_id] AND I.[Table] = I2.[Table] AND I.[Ix_Name] <> I2.[Ix_Name]
	AND (((I.KeyColsOrdered <> I2.KeyColsOrdered OR I.[IncludedColsOrdered] <> I2.[IncludedColsOrdered])
		AND ((CASE WHEN I.[IncludedColsOrdered] IS NULL THEN I.KeyColsOrdered ELSE I.KeyColsOrdered + ',' + I.[IncludedColsOrdered] END) = (CASE WHEN I2.[IncludedColsOrdered] IS NULL THEN I2.KeyColsOrdered ELSE I2.KeyColsOrdered + ',' + I2.[IncludedColsOrdered] END)
			OR I.[AllCols] = I2.[AllCols]))
	OR (I.KeyColsOrdered <> I2.KeyColsOrdered AND I.[IncludedColsOrdered] = I2.[IncludedColsOrdered])
	OR (I.KeyColsOrdered = I2.KeyColsOrdered AND I.[IncludedColsOrdered] <> I2.[IncludedColsOrdered]))
WHERE I.[Score] >= 100000
	AND I2.[Score] >= 100000
GROUP BY I.DBName, I.[Table], I.[Ix_Name], I.[ix_handle], I.[KeyCols], I.[IncludedCols], I2.[Ix_Name]
ORDER BY I.DBName, I.[Table], I.[Ix_Name]

IF (SELECT COUNT(*) FROM #IndexCreation WHERE [Score] >= 100000) > 0
BEGIN
	SELECT 'Missing_Indexes' AS [Information], IC.DBName AS [Database_Name], IC.[Table] AS [Table_Name], CONVERT(bigint,[Score]) AS [Score], [User_Hits_on_Missing_Index], 
		[Estimated_Improvement_Percent], [Avg_Total_User_Cost], [Unique_Compiles], IC.[KeyCols], IC.[IncludedCols], IC.[Ix_Name] AS [Index_Name],
		SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
			WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
		ORDER BY IR.[Redundant_With]
	FOR XML PATH('')), 2, 8000) AS [Possibly_Redundant_With]
	FROM #IndexCreation IC
	WHERE [Score] >= 100000
	ORDER BY IC.DBName, IC.[Score] DESC, IC.[User_Hits_on_Missing_Index], IC.[Estimated_Improvement_Percent];		

	SELECT DISTINCT 'Possibly_redundant_IXs_in_list' AS Comments, I.DBName AS [Database_Name], I.[Table] AS [Table_Name], 
		I.[Ix_Name] AS [Index_Name], I.[KeyCols], I.[IncludedCols]
	FROM #IndexRedundant I
	ORDER BY I.DBName, I.[Table], I.[Ix_Name]
END
ELSE
BEGIN
	SELECT 'Missing_Indexes' AS [Information], 'None' AS [Comment]
END;

IF (SELECT COUNT(*) FROM #IndexCreation IC WHERE IC.[IncludedCols] IS NULL AND IC.[Score] >= 100000) > 0
BEGIN
	PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */' + CHAR(10)
	PRINT '--############# Indexes creation statements #############' + CHAR(10)
	DECLARE cIC CURSOR FAST_FORWARD FOR
	SELECT '-- User Hits on Missing Index ' + IC.[Ix_Name] + ': ' + CONVERT(VARCHAR(20),IC.[User_Hits_on_Missing_Index]) + CHAR(10) +
		'-- Estimated Improvement Percent: ' + CONVERT(VARCHAR(6),IC.[Estimated_Improvement_Percent]) + CHAR(10) +
		'-- Average Total User Cost: ' + CONVERT(VARCHAR(50),IC.[Avg_Total_User_Cost]) + CHAR(10) +
		'-- Unique Compiles: ' + CONVERT(VARCHAR(50),IC.[Unique_Compiles]) + CHAR(10) +
		'-- Score: ' + CONVERT(VARCHAR(20),CONVERT(bigint,IC.[Score])) + 
		CASE WHEN (SELECT COUNT(IR.[Redundant_With]) FROM #IndexRedundant IR 
			WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]) > 0 
		THEN CHAR(10) + '-- Possibly Redundant with Missing Index(es): ' + SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
			WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
			FOR XML PATH('')), 2, 8000) 
		ELSE '' END +
		CHAR(10) + 'USE ' + QUOTENAME(IC.DBName) + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sysindexes WHERE name = N''' +
		IC.[Ix_Name] + ''') DROP INDEX ' + IC.[Table] + '.' +
		IC.[Ix_Name] + ';' + CHAR(10) + 'GO' + CHAR(10) + 'CREATE INDEX ' +
		IC.[Ix_Name] + ' ON ' + IC.[Table] + ' (' + IC.[KeyCols] + CASE WHEN @editionCheck = 1 THEN ') WITH (ONLINE = ON);' ELSE ');' END + CHAR(10) + 'GO' + CHAR(10)
	FROM #IndexCreation IC
	WHERE IC.[IncludedCols] IS NULL AND IC.[Score] >= 100000
	ORDER BY IC.DBName, IC.[Table], IC.[Ix_Name]
	OPEN cIC
	FETCH NEXT FROM cIC INTO @IC
	WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT @IC
			FETCH NEXT FROM cIC INTO @IC
		END
	CLOSE cIC
	DEALLOCATE cIC
END;

IF (SELECT COUNT(*) FROM #IndexCreation IC WHERE IC.[IncludedCols] IS NOT NULL AND IC.[Score] >= 100000) > 0
BEGIN
	PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */' + CHAR(10)
	PRINT '--############# Covering indexes creation statements #############' + CHAR(10)
	DECLARE cICWI CURSOR FAST_FORWARD FOR
	SELECT '-- User Hits on Missing Index ' + IC.[Ix_Name] + ': ' + CONVERT(VARCHAR(20),IC.[User_Hits_on_Missing_Index]) + CHAR(10) +
		'-- Estimated Improvement Percent: ' + CONVERT(VARCHAR(6),IC.[Estimated_Improvement_Percent]) + CHAR(10) +
		'-- Average Total User Cost: ' + CONVERT(VARCHAR(50),IC.[Avg_Total_User_Cost]) + CHAR(10) +
		'-- Unique Compiles: ' + CONVERT(VARCHAR(50),IC.[Unique_Compiles]) + CHAR(10) +
		'-- Score: ' + CONVERT(VARCHAR(20),CONVERT(bigint,IC.[Score])) + 
		CASE WHEN (SELECT COUNT(IR.[Redundant_With]) FROM #IndexRedundant IR 
			WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]) > 0 
		THEN CHAR(10) + '-- Possibly Redundant with Missing Index(es): ' + SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
			WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
			FOR XML PATH('')), 2, 8000) 
		ELSE '' END + 
		CHAR(10) + 'USE ' + QUOTENAME(IC.DBName) + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sysindexes WHERE name = N''' +
		IC.[Ix_Name] + ''') DROP INDEX ' + IC.[Table] + '.' +
		IC.[Ix_Name] + ';' + CHAR(10) + 'GO' + CHAR(10) + 'CREATE INDEX ' +
		IC.[Ix_Name] + ' ON ' + IC.[Table] + ' (' + IC.[KeyCols] + CASE WHEN @editionCheck = 1 THEN ') WITH (ONLINE = ON);' ELSE ');' END + CHAR(10) + 'GO' + CHAR(10)
	FROM #IndexCreation IC
	WHERE IC.[IncludedCols] IS NOT NULL AND IC.[Score] >= 100000
	ORDER BY IC.DBName, IC.[Table], IC.[Ix_Name]
	OPEN cICWI
	FETCH NEXT FROM cICWI INTO @ICWI
	WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT @ICWI
			FETCH NEXT FROM cICWI INTO @ICWI
		END
	CLOSE cICWI
	DEALLOCATE cICWI
END;

DROP TABLE #IndexCreation
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_keycols'')) DROP FUNCTION dbo.fn_createindex_keycols')
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_allcols'')) DROP FUNCTION dbo.fn_createindex_allcols')
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_includedcols'')) DROP FUNCTION dbo.fn_createindex_includedcols')
GO