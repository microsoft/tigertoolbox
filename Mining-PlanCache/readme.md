# Exploring the Plan Cache

Most of the queries below are also part of the Performance and Best Practices Check (http://aka.ms/BPCheck). It may make sense to explore what’s going on with your cached plans, especially for SQL Server versions where the Query Store is not available.

Fixing performance issues by having a proper database design, indexing and well written code is not only better but also much less expensive that upgrading your servers hardware, as a way to minimize performance issues. 

The following examples retrieve valuable information that is sitting right there in your plan cache. If you ever looked at a graphical execution plan, it is nothing more than an XML file. So it makes sense to use xqueries to explore the richness of information that is stored there.

The queries available here allow you to look for the following:
- Plans with Missing Indexes
- Plans with Warnings
- Plans with Implicit Conversions
- Plans with Index Scans
- Plans with Lookups
- Finding index usage
- Plans with Parameterization
- Cost of Parallel Plans
- Cost of Parallel Plans with detail per Operator
- Parallel plans where Avg. Worker Time > Avg. Elapsed Time
- Parallel plans where Avg. Worker Time > Avg. Elapsed Time with detail per Operator

## Querying the plan cache for missing indexes
Will allow you to get a sense if the engine is outputting any information on what may be perceived as inadequacy between the current database design and possible benefits of creating new or changing current indexes for your relevant workload. 
It may be important to review this information against the current indexes, verify its validity against the importance of the workload it refers to, and always test before making any changes. 
Last but not least, in an OLTP environment, never create redundant indexes.  

```sql
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
```

## Querying the plan cache for plans that have warnings

This one is especially useful in SQL Server 2012 and above, where we have many more and quite useful warnings about the plan execution. 
Still, you can use from SQL Server 2005 to 2008R2 to find warnings regarding ColumnsWithNoStatistics and NoJoinPredicate. 
In SQL Server 2012 and above, this can also get warnings such as UnmatchedIndexes (where a filtered index could not be used due to parameterization) and convert issues (PlanAffectingConvert) that affect either Cardinality Estimate or the ability to choose a Seek Plan. 
Also note that we cannot leverage this type of cache exploration queries to know where SpillToTempDb or MemoryGrant warnings occur, as they are only found when we output an actual execution plan, and not in cached execution plans.

```sql
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
```

## Finding plans with Batch Sorts

Optimized Nested Loops (or Batch Sort) is effectively an optimization aimed at minimizing I/O during a nested loop when the inner side table is large, regardless of it being parallelized or not.
The presence of this optimization in a given plan may not be very obvious when you look at an execution plan, given the sort itself is hidden, but you can see this by looking in the plan XML, and looking for the attribute Optimized, meaning the Nested Loop join may try to reorder the input rows to improve I/O performance. You can read more about this [here](https://blogs.msdn.microsoft.com/sql_server_team/addressing-large-memory-grant-requests-from-optimized-nested-loops/).

If these are present and causing issues, trace flag 2340 avoids the use of a sort operation (batch sort) for optimized Nested Loops joins when generating a plan. Starting with SQL Server 2016 (13.x) SP1, to accomplish this at the query level, add the USE HINT 'DISABLE_OPTIMIZED_NESTED_LOOP' query hint instead of using this trace flag.

```sql
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
```
 
## Querying the plan cache for specific implicit conversions

Implicit conversions are evil in the sense they may prevent the Query Optimizer from being able to search the entire optimization space. An implicit conversion will have an overhead in your code execution because it will cause CPU cycles to be wasted, and may also limit the query optimizer to make the most appropriate choices when coming up with the execution plan. This is mostly because the optimizer will not be able to do correct cardinality estimations, and with that, it will leverage scans where seeks would be more suitable (this is a generalization). Just look at the following example that will illustrate what I’m saying:

```sql
USE AdventureWorks2016
SELECT p.FirstName, p.LastName, e.NationalIDNumber, e.LoginID
FROM HumanResources.Employee e
INNER JOIN Person.Person p ON e.BusinessEntityID = p.BusinessEntityID
WHERE NationalIDNumber = 112457891;
```

This will generate a plan with a **PlanAffectingConvert** warning inside, because the `NationaIDNumber` is actually of the NVARCHAR(15) data type, not an integer. As I stated above, if you are not running on SQL Server 2012 or above, you get no such warning, and that is why searching the plan cache for implicit conversions can be an important exercise.

```sql
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
```
 
## Querying the plan cache for index scans

This one will allow you to find where we are doing index scans. Why is this important? As you might know, scans are not always a bad thing, namely if you are not being narrow enough in your search arguments (if any), where a scan may be cheaper than a few hundred or thousand seeks. You can read more on a post I did some time ago, regarding a case of seeks and scans. 
The following code is most useful by allowing you to identify where scans are happening on tables with a high cardinality, and even look directly at the predicate for any tuning you might do on it.

```sql
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
```
 
## Querying the plan cache for Lookups

Searching for lookups, namely on large tables, may be a good way to search for opportunities to fine tune performance from the index standpoint. 
If a lookup is being done for a small subset of columns of a table, it may be a chance to review the existing non-clustered indexes, namely the one that is being used in conjunction with the lookup, and possibly add included columns to avoid these lookups.
The following code allows you to search for lookups and give you some information to quickly identify these potential issues.

```sql
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
```

## Querying the plan cache for index usage (Set @IndexName accordingly)

Using the missing index xquery in the previous post, let’s say we found an index that has great potential, and after we create it, we want to see where it is being used – perhaps it is even being used in other queries.
So, this one will allow you to search for usage information about a specific index. This can of course be achieved by other means other than an xquery, but in this fashion we get many useful information such as the type of operators in which indexes are used, predicates used and estimations.

```sql
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
```

## Querying the plan cache for specific statements (set @Statement accordingly)

This one will allow you to search for any plan that executed a specific statement.

```sql
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
```

## Querying the plan cache for parameterization

As part of the SQL Performance Tuning and Optimization Clinic, we may capture workload in production and replay it in a test server. As such, we need to get values to run parameterized queries, and while we can get to those values by other means, I am especially keen on using the values in which a plan was compiled.
This is also useful if you suspect you might be experiencing a parameter sniffing issue, and want to quickly list the parameterized values in query plans.
The xquery below gets us just that.

```sql
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
```

## Querying the plan cache for plans that use parallelism and their cost

The next few retrieve information about query plans that use parallelism.

DISCLAIMER: Microsoft does not recommend that you change the default Cost Threshold for Parallelism configuration unless any change has been tested and proven to yield better results for your particular server. If you are not having an issue that might warrant changes, there’s really no point in changing this setting.

The above being said, let’s say we want to tune the Cost Threshold for Parallelism in your OLTP system.
Would you just guess which value you would configure?
Or would you prefer to make an informed decision based on actual query costs in your system?
Most reasonable people would choose the second, and the next xquery allows us to list costs for cached query plans that are using parallelism.

```sql
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
```

Let's say I consider query 1 to be OLTP centric and I want it to run in serial, and for that purpose, I reconfigure the Cost Threshold for Parallelism for 70.
It may happen that the resulting plan is still parallelized, if the serial plan cost is above the new threshold of 70. Remember 70 became the cost threshold on which a decision to use parallelism or not will be used, but if the serial plan that is attempted always in the early stages of optimization is higher than the threshold, then as expected, you will still get a parallel plan.

This means that after identifying my sample workload that I want to make serial, I need to understand its serial cost before setting the Cost Threshold for Parallelism. This can be achieved, for example, by taking those sample queries, and adding the MAXDOP 1 query hint, and checking the cost for the resulting serial plan.

## Querying the plan cache for plans that use parallelism, with more details
This one takes the previous example, but we now have visibility over several costly operators, and several details on those specific operators, including their estimated subtree cost over the overall statement cost.

```sql
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
```

## Querying the plan cache for plans that use parallelism, and worker time > elapsed time

One of the ways to find inefficient query plans in an OLTP environment is to look for parallel plans that use more scheduler time than the elapsed time it took to run a query. Although this is not always the case, looking for such patterns might allow us to identify opportunities to fix OLTP queries where parallelism is being used but may not be a benefit.

```sql
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
```

## Querying the plan cache for plans that use parallelism, and worker time > elapsed time, with more details

The above can be completed with more details, using the below query.

```sql
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
```
 