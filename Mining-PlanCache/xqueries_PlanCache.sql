-- 2013-04-13 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlserverteam/)
--
-- Plan cache xqueries
--
-- 2013-07-16 - Optimized xQueries performance and usability
--
-- 2014-03-16 - Added details to several snippets
--

-- Querying the plan cache for missing indexes
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; 
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	PlanMissingIndexes AS (SELECT query_plan, cp.usecounts, cp.refcounts, cp.plan_handle
							FROM sys.dm_exec_cached_plans cp (NOLOCK)
							CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) tp
							WHERE cp.cacheobjtype = 'Compiled Plan' 
								AND tp.query_plan.exist('//MissingIndex')=1
							)
SELECT c1.value('(//MissingIndex/@Database)[1]', 'sysname') AS database_name,
	c1.value('(//MissingIndex/@Schema)[1]', 'sysname') AS [schema_name],
	c1.value('(//MissingIndex/@Table)[1]', 'sysname') AS [table_name],
	c1.value('@StatementText', 'VARCHAR(4000)') AS sql_text,
	c1.value('@StatementId', 'int') AS StatementId,
	pmi.usecounts,
	pmi.refcounts,
	c1.value('(//MissingIndexGroup/@Impact)[1]', 'FLOAT') AS impact,
	REPLACE(c1.query('for $group in //ColumnGroup for $column in $group/Column where $group/@Usage="EQUALITY" return string($column/@Name)').value('.', 'varchar(max)'),'] [', '],[') AS equality_columns,
	REPLACE(c1.query('for $group in //ColumnGroup for $column in $group/Column where $group/@Usage="INEQUALITY" return string($column/@Name)').value('.', 'varchar(max)'),'] [', '],[') AS inequality_columns,
	REPLACE(c1.query('for $group in //ColumnGroup for $column in $group/Column where $group/@Usage="INCLUDE" return string($column/@Name)').value('.', 'varchar(max)'),'] [', '],[') AS include_columns,
	pmi.query_plan,
	pmi.plan_handle
FROM PlanMissingIndexes pmi
CROSS APPLY pmi.query_plan.nodes('//StmtSimple') AS q1(c1)
WHERE pmi.usecounts > 1
ORDER BY c1.value('(//MissingIndexGroup/@Impact)[1]', 'FLOAT') DESC
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for plans that have warnings
-- Note that SpillToTempDb warnings are only found in actual execution plans
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	WarningSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, wn.query('.') AS StmtSimple, cp.plan_handle
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(wn)
						WHERE wn.exist('//Warnings') = 1
							AND wn.exist('@QueryHash') = 1
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c1.value('@PhysicalOp','sysname') AS physical_op,
	c1.value('@LogicalOp','sysname') AS logical_op,
	CASE WHEN c2.exist('@NoJoinPredicate[. = "1"]') = 1 THEN 'NoJoinPredicate' 
		WHEN c3.exist('@Database') = 1 THEN 'ColumnsWithNoStatistics' END AS warning,
	ws.objtype,
	ws.usecounts,
	ws.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ws.plan_handle
FROM WarningSearch ws
CROSS APPLY StmtSimple.nodes('//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('./Warnings') AS q2(c2)
OUTER APPLY c2.nodes('./ColumnsWithNoStatistics/ColumnReference') AS q3(c3)
UNION ALL
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c3.value('@NodeId','int') AS node_id,
	c3.value('@PhysicalOp','sysname') AS physical_op,
	c3.value('@LogicalOp','sysname') AS logical_op,
	CASE WHEN c2.exist('@UnmatchedIndexes[. = "1"]') = 1 THEN 'UnmatchedIndexes' 
		WHEN (c4.exist('@ConvertIssue[. = "Cardinality Estimate"]') = 1 OR c4.exist('@ConvertIssue[. = "Seek Plan"]') = 1) 
		THEN 'ConvertIssue_' + c4.value('@ConvertIssue','sysname') END AS warning,
	ws.objtype,
	ws.usecounts,
	ws.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ws.plan_handle
FROM WarningSearch ws
CROSS APPLY StmtSimple.nodes('//QueryPlan') AS q1(c1)
CROSS APPLY c1.nodes('./Warnings') AS q2(c2)
CROSS APPLY c1.nodes('./RelOp') AS q3(c3)
OUTER APPLY c2.nodes('./PlanAffectingConvert') AS q4(c4)
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for batch sorts
-- Do we need TF2340 or USE HINT 'DISABLE_OPTIMIZED_NESTED_LOOP' query hint?
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	Scansearch AS (SELECT qp.query_plan, cp.usecounts, ss.query('.') AS StmtSimple, cp.plan_handle
					FROM sys.dm_exec_cached_plans cp (NOLOCK)
					CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
					CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ss)
					WHERE ss.exist('//RelOp[@PhysicalOp = "Nested Loops"]') = 1
						AND ss.exist('@QueryHash') = 1
					)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c3.value('@Database','sysname') AS database_name,
	c3.value('@Schema','sysname') AS [schema_name],
	c3.value('@Table','sysname') AS table_name,
	c1.value('@PhysicalOp','sysname') AS physical_operator, 
	c1.value('@LogicalOp','sysname') AS logical_operator, 
	c2.value('@Optimized','sysname') AS Batch_Sort_Optimized,
	--c2.value('@WithUnorderedPrefetch','sysname') AS WithUnorderedPrefetch,
	c4.value('@SerialDesiredMemory', 'int') AS MemGrant_SerialDesiredMemory,
	c5.value('@EstimatedAvailableMemoryGrant', 'int') AS EstimatedAvailableMemoryGrant,
	--c5.value('@EstimatedPagesCached', 'int') AS EstimatedPagesCached,
	--c5.value('@EstimatedAvailableDegreeOfParallelism', 'int') AS EstimatedAvailableDegreeOfParallelism,
	ss.usecounts,
	ss.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@TableCardinality','sysname') AS TableCardinality,
	c1.value('@EstimateRows','sysname') AS EstimateRows,
	--c1.value('@EstimateIO','sysname') AS EstimateIO,
	--c1.value('@EstimateCPU','sysname') AS EstimateCPU,
	c1.value('@AvgRowSize','int') AS AvgRowSize,
	--c1.value('@Parallel','bit') AS Parallel,
	c1.value('@EstimateRebinds','int') AS EstimateRebinds,
	c1.value('@EstimateRewinds','int') AS EstimateRewinds,
	c1.value('@EstimatedExecutionMode','sysname') AS EstimatedExecutionMode,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ss.plan_handle
FROM Scansearch ss
CROSS APPLY query_plan.nodes('//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('./NestedLoops') AS q2(c2)
CROSS APPLY c1.nodes('./OutputList/ColumnReference[1]') AS q3(c3)
OUTER APPLY query_plan.nodes('//MemoryGrantInfo') AS q4(c4)
OUTER APPLY query_plan.nodes('//OptimizerHardwareDependentProperties') AS q5(c5)
WHERE c1.exist('@PhysicalOp[. = "Nested Loops"]') = 1
	AND c3.value('@Schema','sysname') <> '[sys]'
	AND c2.value('@Optimized','sysname') = 1
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for index scans
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	Scansearch AS (SELECT qp.query_plan, cp.usecounts, ss.query('.') AS StmtSimple, cp.plan_handle
					FROM sys.dm_exec_cached_plans cp (NOLOCK)
					CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
					CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ss)
					WHERE cp.cacheobjtype = 'Compiled Plan'
						AND (ss.exist('//RelOp[@PhysicalOp = "Index Scan"]') = 1
								OR ss.exist('//RelOp[@PhysicalOp = "Clustered Index Scan"]') = 1)
						AND ss.exist('@QueryHash') = 1
					)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c2.value('@Database','sysname') AS database_name,
	c2.value('@Schema','sysname') AS [schema_name],
	c2.value('@Table','sysname') AS table_name,
	c1.value('@PhysicalOp','sysname') AS physical_operator, 
	c2.value('@Index','sysname') AS index_name,
	c3.value('@ScalarString[1]','VARCHAR(4000)') AS [predicate],
	c1.value('@TableCardinality','sysname') AS TableCardinality,
	c1.value('@EstimateRows','sysname') AS EstimateRows,
	--c1.value('@EstimateIO','sysname') AS EstimateIO,
	--c1.value('@EstimateCPU','sysname') AS EstimateCPU,
	c1.value('@AvgRowSize','int') AS AvgRowSize,
	--c1.value('@Parallel','bit') AS Parallel,
	c1.value('@EstimateRebinds','int') AS EstimateRebinds,
	c1.value('@EstimateRewinds','int') AS EstimateRewinds,
	c1.value('@EstimatedExecutionMode','sysname') AS EstimatedExecutionMode,
	c4.value('@Lookup','bit') AS Lookup,
	c4.value('@Ordered','bit') AS Ordered,
	c4.value('@ScanDirection','sysname') AS ScanDirection,
	c4.value('@ForceSeek','bit') AS ForceSeek,
	c4.value('@ForceScan','bit') AS ForceScan,
	c4.value('@NoExpandHint','bit') AS NoExpandHint,
	c4.value('@Storage','sysname') AS Storage,
	ss.usecounts,
	ss.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ss.plan_handle
FROM Scansearch ss
CROSS APPLY query_plan.nodes('//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('./IndexScan') AS q4(c4)
CROSS APPLY c1.nodes('./IndexScan/Object') AS q2(c2)
OUTER APPLY c1.nodes('./IndexScan/Predicate/ScalarOperator[1]') AS q3(c3)
WHERE (c1.exist('@PhysicalOp[. = "Index Scan"]') = 1
		OR c1.exist('@PhysicalOp[. = "Clustered Index Scan"]') = 1)
	AND c2.value('@Schema','sysname') <> '[sys]'
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for Lookups
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	Lookupsearch AS (SELECT qp.query_plan, cp.usecounts, ls.query('.') AS StmtSimple, cp.plan_handle
					FROM sys.dm_exec_cached_plans cp (NOLOCK)
					CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
					CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ls)
					WHERE cp.cacheobjtype = 'Compiled Plan'
						AND ls.exist('//IndexScan[@Lookup = "1"]') = 1
						AND ls.exist('@QueryHash') = 1
					)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c2.value('@Database','sysname') AS database_name,
	c2.value('@Schema','sysname') AS [schema_name],
	c2.value('@Table','sysname') AS table_name,
	'Lookup - ' + c1.value('@PhysicalOp','sysname') AS physical_operator, 
	c2.value('@Index','sysname') AS index_name,
	c3.value('@ScalarString','VARCHAR(4000)') AS predicate,
	c1.value('@TableCardinality','sysname') AS table_cardinality,
	c1.value('@EstimateRows','sysname') AS estimate_rows,
	c1.value('@AvgRowSize','sysname') AS avg_row_size,
	ls.usecounts,
	ls.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ls.plan_handle
FROM Lookupsearch ls
CROSS APPLY query_plan.nodes('//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('./IndexScan/Object') AS q2(c2)
OUTER APPLY c1.nodes('./IndexScan//ScalarOperator[1]') AS q3(c3)
-- Below attribute is present either in Index Seeks or RID Lookups so it can reveal a Lookup is executed
WHERE c1.exist('./IndexScan[@Lookup = "1"]') = 1 
	AND c2.value('@Schema','sysname') <> '[sys]'
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for specific Implicit type conversions
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	Convertsearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, cp.plan_handle, cs.query('.') AS StmtSimple
					FROM sys.dm_exec_cached_plans cp (NOLOCK)
					CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
					CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(cs)
					WHERE cp.cacheobjtype = 'Compiled Plan' 
							AND cs.exist('@QueryHash') = 1
							AND cs.exist('.//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') = 1
							AND cs.exist('.[contains(@StatementText, "Convertsearch")]') = 0
					)
SELECT c2.value('@StatementText', 'VARCHAR(4000)') AS sql_text,
	c2.value('@StatementId', 'int') AS StatementId,
	c3.value('@ScalarString[1]','VARCHAR(4000)') AS expression,
	ss.usecounts,
	ss.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c2.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ss.plan_handle
FROM Convertsearch ss
CROSS APPLY query_plan.nodes('//StmtSimple') AS q2(c2)
CROSS APPLY c2.nodes('.//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') AS q3(c3)
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for index usage (change @IndexName below)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @IndexName sysname = '<ix_name>';
SET @IndexName = QUOTENAME(@IndexName,'[');
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	IndexSearch AS (SELECT qp.query_plan, cp.usecounts, ix.query('.') AS StmtSimple, cp.plan_handle
					FROM sys.dm_exec_cached_plans cp (NOLOCK)
					CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
					CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ix)
					WHERE cp.cacheobjtype = 'Compiled Plan' 
						AND ix.exist('//Object[@Index = sql:variable("@IndexName")]') = 1 
					)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	c2.value('@Database','sysname') AS database_name,
	c2.value('@Schema','sysname') AS [schema_name],
	c2.value('@Table','sysname') AS table_name,
	c2.value('@Index','sysname') AS index_name,
	c1.value('@PhysicalOp','NVARCHAR(50)') as physical_operator,
	c3.value('@ScalarString[1]','VARCHAR(4000)') AS predicate,
	c4.value('@Column[1]','VARCHAR(256)') AS seek_columns,
	c1.value('@EstimateRows','sysname') AS estimate_rows,
	c1.value('@AvgRowSize','sysname') AS avg_row_size,
	ixs.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ixs.plan_handle
FROM IndexSearch ixs
CROSS APPLY StmtSimple.nodes('//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('IndexScan/Object[@Index = sql:variable("@IndexName")]') AS q2(c2)
OUTER APPLY c1.nodes('IndexScan/Predicate/ScalarOperator') AS q3(c3)
OUTER APPLY c1.nodes('IndexScan/SeekPredicates/SeekPredicateNew//ColumnReference') AS q4(c4)
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for parametrization
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	PlanParameters AS (SELECT cp.plan_handle, qp.query_plan, qp.dbid, qp.objectid
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						WHERE qp.query_plan.exist('//ParameterList')=1
							AND cp.cacheobjtype = 'Compiled Plan'
						)
SELECT QUOTENAME(DB_NAME(pp.dbid)) AS database_name,
	ISNULL(OBJECT_NAME(pp.objectid, pp.dbid), 'No_Associated_Object') AS [object_name],
	c2.value('(@Column)[1]','sysname') AS parameter_name,
	c2.value('(@ParameterCompiledValue)[1]','VARCHAR(max)') AS parameter_compiled_value,
	pp.query_plan,
	pp.plan_handle
FROM PlanParameters pp
CROSS APPLY query_plan.nodes('//ParameterList') AS q1(c1)
CROSS APPLY c1.nodes('ColumnReference') as q2(c2)
WHERE pp.dbid > 4 AND pp.dbid < 32767
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for plans that use parallelism and their cost (useful for tuning Cost Threshold for Parallelism)
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	ParallelSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, ix.query('.') AS StmtSimple, cp.plan_handle
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ix)
						WHERE ix.exist('//RelOp[@Parallel = "1"]') = 1
							AND ix.exist('@QueryHash') = 1
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	ps.plan_handle,
	ps.objtype,
	ps.usecounts,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	ps.query_plan,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	c1.value('@CachedPlanSize','sysname') AS CachedPlanSize,
	c2.value('@SerialRequiredMemory','sysname') AS SerialRequiredMemory,
	c2.value('@SerialDesiredMemory','sysname') AS SerialDesiredMemory,
	c3.value('@EstimatedAvailableMemoryGrant','sysname') AS EstimatedAvailableMemoryGrant,
	c3.value('@EstimatedPagesCached','sysname') AS EstimatedPagesCached,
	c3.value('@EstimatedAvailableDegreeOfParallelism','sysname') AS EstimatedAvailableDegreeOfParallelism,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash
FROM ParallelSearch ps
CROSS APPLY StmtSimple.nodes('//QueryPlan') AS q1(c1)
CROSS APPLY c1.nodes('.//MemoryGrantInfo') AS q2(c2)
CROSS APPLY c1.nodes('.//OptimizerHardwareDependentProperties') AS q3(c3)
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for plans that use parallelism, with more details
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	ParallelSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, ix.query('.') AS StmtSimple, cp.plan_handle
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ix)
						WHERE cp.cacheobjtype = 'Compiled Plan' 
							AND ix.exist('//RelOp[@Parallel = "1"]') = 1
							AND ix.exist('@QueryHash') = 1
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c2.value('@Database','sysname') AS database_name,
	c2.value('@Schema','sysname') AS [schema_name],
	c2.value('@Table','sysname') AS table_name,
	c2.value('@Index','sysname') AS [index],
	c2.value('@IndexKind','sysname') AS index_type,
	c1.value('@PhysicalOp','sysname') AS physical_op,
	c1.value('@LogicalOp','sysname') AS logical_op,
	c1.value('@TableCardinality','sysname') AS table_cardinality,
	c1.value('@EstimateRows','sysname') AS estimate_rows,
	c1.value('@AvgRowSize','sysname') AS avg_row_size,
	ps.objtype,
	ps.usecounts,
	ps.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ps.plan_handle
FROM ParallelSearch ps
CROSS APPLY StmtSimple.nodes('//Parallelism//RelOp') AS q1(c1)
CROSS APPLY c1.nodes('.//IndexScan/Object') AS q2(c2)
WHERE c1.value('@Parallel','int') = 1
	AND (c1.exist('@PhysicalOp[. = "Index Scan"]') = 1
	OR c1.exist('@PhysicalOp[. = "Clustered Index Scan"]') = 1
	OR c1.exist('@PhysicalOp[. = "Index Seek"]') = 1
	OR c1.exist('@PhysicalOp[. = "Clustered Index Seek"]') = 1
	OR c1.exist('@PhysicalOp[. = "Table Scan"]') = 1)
	AND c2.value('@Schema','sysname') <> '[sys]'
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for plans that use parallelism, and scheduler time < elapsed time
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	ParallelSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, qs.[total_worker_time], qs.[total_elapsed_time], qs.[execution_count],
							ix.query('.') AS StmtSimple, cp.plan_handle
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						INNER JOIN sys.dm_exec_query_stats qs (NOLOCK) ON cp.plan_handle = qs.plan_handle
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ix)
						WHERE cp.cacheobjtype = 'Compiled Plan' 
							AND ix.exist('//RelOp[@Parallel = "1"]') = 1
							AND ix.exist('@QueryHash') = 1
							AND (qs.[total_worker_time]/qs.[execution_count]) < (qs.[total_elapsed_time]/qs.[execution_count])
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	ps.objtype,
	ps.usecounts,
	ps.[total_worker_time]/ps.[execution_count] AS avg_worker_time,
	ps.[total_elapsed_time]/ps.[execution_count] As avg_elapsed_time,
	ps.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ps.plan_handle
FROM ParallelSearch ps
CROSS APPLY StmtSimple.nodes('//RelOp[1]') AS q1(c1)
WHERE c1.value('@Parallel','int') = 1 AND c1.value('@NodeId','int') = 0
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for plans that use parallelism, and scheduler time < elapsed time and more detailed output
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	ParallelSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, qs.[total_worker_time], qs.[total_elapsed_time], qs.[execution_count],
							ix.query('.') AS StmtSimple, cp.plan_handle
						FROM sys.dm_exec_cached_plans cp (NOLOCK)
						INNER JOIN sys.dm_exec_query_stats qs (NOLOCK) ON cp.plan_handle = qs.plan_handle
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY qp.query_plan.nodes('//StmtSimple') AS p(ix)
						WHERE cp.cacheobjtype = 'Compiled Plan' 
							AND ix.exist('//RelOp[@Parallel = "1"]') = 1
							AND ix.exist('@QueryHash') = 1
							AND (qs.[total_worker_time]/qs.[execution_count]) < (qs.[total_elapsed_time]/qs.[execution_count])
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	StmtSimple.value('StmtSimple[1]/@StatementId', 'int') AS StatementId,
	c1.value('@NodeId','int') AS node_id,
	c2.value('@Database','sysname') AS database_name,
	c2.value('@Schema','sysname') AS [schema_name],
	c2.value('@Table','sysname') AS table_name,
	c2.value('@Index','sysname') AS [index],
	c2.value('@IndexKind','sysname') AS index_type,
	c1.value('@PhysicalOp','sysname') AS physical_op,
	c1.value('@LogicalOp','sysname') AS logical_op,
	c1.value('@TableCardinality','sysname') AS table_cardinality,
	c1.value('@EstimateRows','sysname') AS estimate_rows,
	c1.value('@AvgRowSize','sysname') AS avg_row_size,
	ps.objtype,
	ps.usecounts,
	ps.[total_worker_time]/ps.[execution_count] AS avg_worker_time,
	ps.[total_elapsed_time]/ps.[execution_count] As avg_elapsed_time,
	ps.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ps.plan_handle
FROM ParallelSearch ps
CROSS APPLY StmtSimple.nodes('//Parallelism//RelOp') AS q1(c1)
OUTER APPLY c1.nodes('.//IndexScan/Object') AS q2(c2)
WHERE c1.value('@Parallel','int') = 1
	AND (c1.exist('@PhysicalOp[. = "Index Scan"]') = 1
	OR c1.exist('@PhysicalOp[. = "Clustered Index Scan"]') = 1
	OR c1.exist('@PhysicalOp[. = "Index Seek"]') = 1
	OR c1.exist('@PhysicalOp[. = "Clustered Index Seek"]') = 1
	OR c1.exist('@PhysicalOp[. = "Table Scan"]') = 1)
	AND c2.value('@Schema','sysname') <> '[sys]'
OPTION(RECOMPILE, MAXDOP 1); 
GO

-- Querying the plan cache for specific statements (change @Statement below)
DECLARE @Statement VARCHAR(4000) = 'Sales.SalesOrderDetail';
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'), 
	StatementSearch AS (SELECT qp.query_plan, cp.usecounts, cp.objtype, cp.plan_handle, ss.query('.') AS StmtSimple
						FROM sys.dm_exec_cached_plans cp
						CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
						CROSS APPLY query_plan.nodes('//StmtSimple[contains(@StatementText, sql:variable("@Statement"))]') AS p(ss)
						WHERE cp.cacheobjtype = 'Compiled Plan' 
							AND ss.exist('@QueryHash') = 1
						)
SELECT StmtSimple.value('StmtSimple[1]/@StatementText', 'VARCHAR(4000)') AS sql_text,
	ss.objtype,
	ss.usecounts,
	ss.query_plan,
	StmtSimple.value('StmtSimple[1]/@QueryHash', 'VARCHAR(100)') AS query_hash,
	StmtSimple.value('StmtSimple[1]/@QueryPlanHash', 'VARCHAR(100)') AS query_plan_hash,
	StmtSimple.value('StmtSimple[1]/@StatementSubTreeCost', 'sysname') AS StatementSubTreeCost,
	c1.value('@EstimatedTotalSubtreeCost','sysname') AS EstimatedTotalSubtreeCost,
	StmtSimple.value('StmtSimple[1]/@StatementOptmEarlyAbortReason', 'sysname') AS StatementOptmEarlyAbortReason,
	StmtSimple.value('StmtSimple[1]/@StatementOptmLevel', 'sysname') AS StatementOptmLevel,
	ss.plan_handle
FROM StatementSearch ss
CROSS APPLY StmtSimple.nodes('//Parallelism//RelOp') AS q1(c1)
OPTION(RECOMPILE, MAXDOP 1); 
GO