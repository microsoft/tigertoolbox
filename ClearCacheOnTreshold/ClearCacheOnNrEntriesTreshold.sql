SET NOCOUNT ON;

DECLARE @sqlcmd NVARCHAR(4000), @params NVARCHAR(500), @ErrorMessage NVARCHAR(1000)
DECLARE @cacheentries bigint, @cachename NVARCHAR(256), @entriesthreshold int
DECLARE @tmpCacheTbl AS TABLE (cachename NVARCHAR(256), entries_count bigint, is_done bit)

SET @entriesthreshold = 10000 -- Triggers cache cleanup if exceeded

-- Populate cache table
INSERT INTO @tmpCacheTbl
SELECT name, entries_count, 0 
FROM sys.dm_os_memory_cache_counters
WHERE name IN ('Object Plans', 'SQL Plans', 'Bound Trees', 'Extended Stored Procedures', 'Temporary Tables & Table Variables')

WHILE (SELECT COUNT(cachename) FROM @tmpCacheTbl WHERE is_done = 0) > 0
BEGIN
	SELECT TOP 1 @cachename = cachename, @cacheentries = entries_count FROM @tmpCacheTbl WHERE is_done = 0
	IF @cacheentries >= @entriesthreshold
	BEGIN	
		SELECT @ErrorMessage = CONVERT(NVARCHAR(50), GETDATE()) + ': ' + @cachename + ' will be evicted because it exceeds ' + CONVERT(NVARCHAR(12), @entriesthreshold) + ' number of objects (' +  CONVERT(NVARCHAR(12), @cacheentries) + ').'
		RAISERROR (@ErrorMessage, 10, 1, N'Manual cache eviction');
		EXECUTE ('DBCC FREESYSTEMCACHE (''' + @cachename + ''') WITH MARK_IN_USE_FOR_REMOVAL')
	END
	ELSE
	BEGIN
		SELECT @ErrorMessage = CONVERT(NVARCHAR(50), GETDATE()) + ': ' + @cachename + ' does not exceed ' + CONVERT(NVARCHAR(12), @entriesthreshold) + ' number of objects (' +  CONVERT(NVARCHAR(12), @cacheentries) + ').'
		RAISERROR (@ErrorMessage, 10, 1, N'Manual cache eviction');
	END

	UPDATE @tmpCacheTbl
	SET is_done = 1
	WHERE cachename = @cachename
END
GO
