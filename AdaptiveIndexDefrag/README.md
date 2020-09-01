Change log available in http://github.com/Microsoft/tigertoolbox/blob/master/AdaptiveIndexDefrag/CHANGELOG.txt.

Options list available in http://github.com/Microsoft/tigertoolbox/blob/master/AdaptiveIndexDefrag/OPTIONS.md.

## What’s the purpose of AdaptiveIndexDefrag?
The purpose for this procedure to perform an Intelligent defrag on one or more indexes, as well as required statistics update, for one or more databases. In a nutshell, this procedure automatically chooses whether to rebuild or reorganize an index according to its fragmentation level, amongst other parameters, like if page locks are allowed or the existence of LOBs, while keeping statistics updated with a linear threshold. All within a specified time frame you choose, defaulting to 8 hours. The defrag priority can also be set, either on size, fragmentation level or index usage (based on range scan count), which is the default. It also handles partitioned indexes, columnstore indexes, indexes in In-Memory tables, statistics update (table-wide or only those related to indexes), rebuilding with the original fill factor or index padding and online operations, to name a few options.

## Does it only handle index and statistics?
Yes, but it is used as a part of a full maintenance solution that also handles database integrity checks, errorlog cycling and other relevant SQL Server maintenance routines that every database administrator needs to handle. See more information in http://github.com/Microsoft/tigertoolbox/tree/master/MaintenanceSolution.

## On what version of SQL can I use it?
This procedure can be used from SQL Server 2005 SP2 onwards, because of the DMVs and DMFs involved.

**NOTE:** no longer garanteed to work with SQL Server 2005. Use at your own volition.

## How to deploy it?
Starting with v1.3.7, on any database context you choose to create the usp_AdaptiveIndexDefrag and its supporting objects, open the attached script, and either keep the @deploymode variable at the top to upgrade mode (preserving all historic data), or change for new deployments or overwrite old versions and objects (disregarding historic data).

## How to use it?
After executing the attached script in a user database of your choice, either run the procedure usp_AdaptiveIndexDefrag with no parameters, since all are optional (If not specified, the defaults for each parameter are used), or customize its use with parameters. Check all available parameters in the OPTIONS.md file.

## What objects are created when running the attached script?

- Several control and logging tables are created:
  - tbl_AdaptiveIndexDefrag_Working, used to keep track of which objects to act on, and crucial information that influence how those objects are handled. It also keeps track of which indexes were already defragged in a previous run, if your defrag cycle must span several days due to time constraints.
  - tbl_AdaptiveIndexDefrag_Stats_Working, the statistics counterpart of the above table.
  - tbl_AdaptiveIndexDefrag_log, an index operations logging table, where all the index operations are logged.
  - tbl_AdaptiveIndexDefrag_Stats_log, a statistics operations logging table, where all the statistics operations are logged.You might want to cleanup this and the above table after awhile using the procedure usp_AdaptiveIndexDefrag_PurgeLogs.
  - tbl_AdaptiveIndexDefrag_Exceptions, an exceptions table where you can set the restrictions on which days certain objects are handled (mask just like in sysschedules system table). You can also set exceptions for specific indexes, tables or entire databases. Say you have a specific table that you only want to defrag on weekends, you can set it in the exceptions table so that all indexes on that table will only be defragged on Saturdays and Sundays. Or you want to exclude one database or table from ever being defragged. These are just examples of how to manage specific needs.
  - tbl_AdaptiveIndexDefrag_IxDisableStatus, where indexes that were disabled are logged, so that an interruption in the defrag cycle can account for these indexes has being disabled by the defrag cycle itself and not the user.
  - usp_AdaptiveIndexDefrag_PurgeLogs, which will purge the log tables of data older than 90 days, to avoid indefinite growth. The 90 days is just the default, change @daystokeep input parameter to a value you deem fit. I recommend executing this in a job.
  - usp_AdaptiveIndexDefrag_Exclusions, which is will help in setting on which days (if any) you allow for a specific index, or even all indexes on a given table, to be defragmented. In the previous post here there was an example query of how you could set the exclusions embedded in the script, but due to some feedback, I’ve turned it into an SP.
  - usp_AdaptiveIndexDefrag_CurrentExecStats, which can be used to keep track of which indexes were already defragged thus far in the current execution.
  - usp_AdaptiveIndexDefrag, the main procedure that handles index defragmentation and statistics updates. Takes the input parameters shown before.
- And several views for miscellaneous purposes:
  - vw_ErrLst30Days, to check all known execution errors in the last 30 days.- vw_ErrLst24Hrs, to check all known execution errors in the last 24 hours.
  - vw_AvgTimeLst30Days, to check the average execution time for each index in the last 30 days.- vw_AvgFragLst30Days, to check the average fragmentation found for each index in the last 30 days.- vw_AvgLargestLst30Days, to check the average size for each index in the last 30 days.
  - vw_AvgMostUsedLst30Days, to check the average usage of each index in the last 30 days.
  - vw_LastRun_Log, to check in the log tables how the last execution did.

## A few common usage scenarios for this script

**EXEC dbo.usp_AdaptiveIndexDefrag**
The defaults are to defragment indexes with fragmentation greater than 5%; rebuild indexes with fragmentation greater than 30%; defragment ALL indexes; commands WILL be executed automatically; defragment indexes in DESC order of the RANGE_SCAN_COUNT value; time limit was specified and is 480 minutes (8 hours); ALL databases will be defragmented; ALL tables will be defragmented; WILL be rescanning indexes; the scan will be performed in LIMITED mode; LOBs will be compacted; limit defrags to indexes with more than 8 pages; indexes will be defragmented OFFLINE; indexes will be sorted in the DATABASE; indexes will have its ORIGINAL Fill Factor; only the right-most populated partitions will be considered if greater than 8 page(s); statistics WILL be updated on reorganized indexes; defragmentation will use system defaults for processors; does NOT print the t-sql commands; does NOT output fragmentation levels; waits 5s between index operations;

**EXEC dbo.usp_AdaptiveIndexDefrag @dbScope = 'AdventureWorks2014'**
Same as above, except its scope is only the 'AdventureWorks2014' database.

**EXEC dbo.usp_AdaptiveIndexDefrag @dbScope = 'AdventureWorks2014', @tblName = 'Production.BillOfMaterials'**
Same as above but only acting on the BillOfMaterials table.

**EXEC dbo.usp_AdaptiveIndexDefrag @Exec_Print = 0, @printCmds = 1**
Using the operating defaults in 1, this will not execute any commands. Instead, just prints them to the screen. Useful if you want to check what it will be doing behind the scenes.

**EXEC dbo.usp_AdaptiveIndexDefrag @Exec_Print = 0, @printCmds = 1, @scanMode = 'DETAILED', @updateStatsWhere = 1**
Same as above, but adding the DETAILED scanMode to allow for finer thresholds in stats update, and forcing the update statistics to run on index related stats, instead of all the table statistics.

**EXEC dbo.usp_AdaptiveIndexDefrag @scanMode = 'DETAILED', @updateStatsWhere = 1 , @disableNCIX = 1**
Differs from the above just because it will execute the comands instead of printing them and will disable non-clustered indexes prior to a rebuild operation.

**EXEC dbo.usp_AdaptiveIndexDefrag @minFragmentation = 3, @rebuildThreshold = 20**
Using the operating defaults in 1, this will lower the minimum fragmentation that allows the defrag to include a given index to 3%, and the rebuild vs. reorganize threshold to just 20%.

**EXEC dbo.usp_AdaptiveIndexDefrag @onlineRebuild = 1**
Using the operating defaults in 1, this will try to do online rebuild operations whenever possible.

**EXEC dbo.usp_AdaptiveIndexDefrag @onlineRebuild = 1, @updateStatsWhere = 0, @statsSample = 'FULLSCAN'**
Similar to the above, this will also force update statistics to run on all stats found on table with FULLSCAN.

**EXEC dbo.usp_AdaptiveIndexDefrag @onlineRebuild = 1, @updateStatsWhere = 0, @dbScope = 'AdventureWorks2014', @defragOrderColumn = 'fragmentation', @timeLimit = 240, @scanMode = 'DETAILED'**
Similar to the above, this will also restrict all defrag operations to the 'AdventureWorks2014' database, giving priority to the most fragmented indexes (instead of the most used, which is the default), limiting the time window for defrag operations to just 4 hours, and using the DETAILED scanMode to allow for finer thresholds in stats update.

**EXEC dbo.usp_AdaptiveIndexDefrag @timeLimit = 360**
Using the operating defaults in 1, will set the running window to just 6 hours.

**EXEC dbo.usp_AdaptiveIndexDefrag @offlinelocktimeout = 300, @onlinelocktimeout = 5**
Using the operating defaults in 1, will set the lock timeout value for 300s when doing offline rebuilds, and 5 minutes when doing online rebuilds (valid from SQL Server 2014 onward).

**EXEC dbo.usp_AdaptiveIndexDefrag @rebuildThreshold = 99, @dealMaxPartition = 1, @onlineRebuild = 1**
Using the operating defaults in 1, this will try to do online rebuild operations whenever possible and exclude from the defrag run the right-most partition will while setting a rebuild threshold of 99%, essentially forcing a reorganize instead of a rebuild. Useful if you consider the scenario where you had all your indexes with a low fill factor for some purpose in a partitioned table, but then had to rebuild them using a higher fill factor and reclaim the space using DBCC SHRINKFILE (yes, not advisable but can happen on occasion). Forcing a reorganize on all but the right-most partition (active) is the most efficient way of defragmenting your indexes again with minimum impact on the server availability.
