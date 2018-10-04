SET NOCOUNT ON;
DROP TABLE IF EXISTS #tmpUserDBs;

SELECT [database_id], 0 AS [IsDone]
INTO #tmpUserDBs
FROM master.sys.databases
WHERE [database_id] > 4
	AND [state] = 0 -- must be ONLINE
	AND is_read_only = 0 -- cannot be READ_ONLY
	AND [database_id] NOT IN (SELECT dr.database_id FROM sys.dm_hadr_database_replica_states dr -- Except all local Always On secondary replicas
		INNER JOIN sys.dm_hadr_availability_replica_states rs ON dr.group_id = rs.group_id
		INNER JOIN sys.databases d ON dr.database_id = d.database_id
		WHERE rs.role = 2 -- Is Secondary
			AND dr.is_local = 1
			AND rs.is_local = 1)

DECLARE @userDB sysname;

WHILE (SELECT COUNT([database_id]) FROM #tmpUserDBs WHERE [IsDone] = 0) > 0
BEGIN
	SELECT TOP 1 @userDB = DB_NAME([database_id]) FROM #tmpUserDBs WHERE [IsDone] = 0

	-- PRINT 'Working on database ' + @userDB

	EXEC ('USE [' + @userDB + '];
DECLARE @clearPlan bigint, @clearQry bigint;
IF EXISTS (SELECT [actual_state] FROM sys.database_query_store_options WHERE [actual_state] IN (1,2))
BEGIN
	IF EXISTS (SELECT plan_id FROM sys.query_store_plan WHERE engine_version = ''14.0.3008.27'')
	BEGIN
		DROP TABLE IF EXISTS #tmpclearPlans;

		SELECT plan_id, query_id, 0 AS [IsDone]
		INTO #tmpclearPlans
		FROM sys.query_store_plan WHERE engine_version = ''14.0.3008.27''

		WHILE (SELECT COUNT(plan_id) FROM #tmpclearPlans WHERE [IsDone] = 0) > 0
		BEGIN
			SELECT TOP 1 @clearPlan = plan_id, @clearQry = query_id FROM #tmpclearPlans WHERE [IsDone] = 0
			EXECUTE sys.sp_query_store_unforce_plan @clearQry, @clearPlan;
			EXECUTE sys.sp_query_store_remove_plan @clearPlan;

			UPDATE #tmpclearPlans 
			SET [IsDone] = 1 
			WHERE plan_id = @clearPlan AND query_id = @clearQry
		END;

		PRINT ''- Cleared possibly affected plans in database [' + @userDB + ']''
	END
	ELSE
	BEGIN
		PRINT ''- No affected plans in database [' + @userDB + ']''
	END
END
ELSE
BEGIN
	PRINT ''- Query Store not enabled in database [' + @userDB + ']''
END')
		UPDATE #tmpUserDBs 
		SET [IsDone] = 1 
		WHERE [database_id] = DB_ID(@userDB)
END