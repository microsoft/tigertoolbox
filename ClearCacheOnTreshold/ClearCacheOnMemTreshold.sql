SET NOCOUNT ON;

DECLARE @sqlcmd NVARCHAR(4000), @params NVARCHAR(500), @ErrorMessage NVARCHAR(1000)
DECLARE @pages_MB bigint, @cachename NVARCHAR(256), @committed_MB bigint
DECLARE @memthreshold_pct smallint
DECLARE @tmpCacheTbl AS TABLE (cachename NVARCHAR(256), pages_kb bigint, is_done bit)

-- Set percentage of committed memory used by prepared single use plans that triggers a cache eviction
SET @memthreshold_pct = 10
SET @sqlcmd = N'SELECT @committedOUT=committed_kb/1024 FROM sys.dm_os_sys_info (NOLOCK)'
SET @params = N'@committedOUT bigint OUTPUT';
EXECUTE sp_executesql @sqlcmd, @params, @committedOUT=@committed_MB OUTPUT;

-- Populate cache table
INSERT INTO @tmpCacheTbl
SELECT name, pages_kb / 1024, 0 
FROM sys.dm_os_memory_cache_counters
WHERE name IN ('Object Plans', 'SQL Plans', 'Bound Trees', 'Extended Stored Procedures', 'Temporary Tables & Table Variables')

WHILE (SELECT COUNT(cachename) FROM @tmpCacheTbl WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @cachename = cachename, @pages_MB = pages_kb FROM @tmpCacheTbl WHERE is_done = 0

	IF (@pages_MB * 100) / @committed_MB >= @memthreshold_pct
	BEGIN	
		SELECT @ErrorMessage = CONVERT(NVARCHAR(50), GETDATE()) + ': ' + @cachename + ' will be evicted because it exceeds ' + CONVERT(NVARCHAR(12), @memthreshold_pct) + ' percent of total committed memory (' + CONVERT(NVARCHAR(12), @pages_MB) + 'MB of ' + CONVERT(NVARCHAR(12), @committed_MB) + 'MB).'
		RAISERROR (@ErrorMessage, 10, 1, N'Manual cache eviction');
		EXECUTE ('DBCC FREESYSTEMCACHE (''' + @cachename + ''') WITH MARK_IN_USE_FOR_REMOVAL')
	END
	ELSE
	BEGIN
		SELECT @ErrorMessage = CONVERT(NVARCHAR(50), GETDATE()) + ': ' + @cachename + ' does not exceed ' + CONVERT(NVARCHAR(12), @memthreshold_pct) + ' percent of total committed memory (' + CONVERT(NVARCHAR(12), @pages_MB) + 'MB of ' + CONVERT(NVARCHAR(12), @committed_MB) + 'MB).'
		RAISERROR (@ErrorMessage, 10, 1, N'Manual cache eviction');
	END

	UPDATE @tmpCacheTbl
	SET is_done = 1
	WHERE cachename = @cachename
END
GO
