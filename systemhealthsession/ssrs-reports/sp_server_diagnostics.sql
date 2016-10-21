/*
T-SQL script to fetch sp_server_diagnostics information from the System Health Sessions .XEL files stored in the SQL Server instance LOG folder.

Note: This works only for SQL Server 2012 instances.

Author: Amit Banerjee
Contact details:
Blog: www.troubleshootingsql.com
Twitter: http://twitter.com/banerjeeamit 
Email: troubleshootingsql@outlook.com 

DISCLAIMER:
This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
*/

SET NOCOUNT ON

IF (SUBSTRING(CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)),1,CHARINDEX('.',CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)))-1) >= 11)
BEGIN

	DECLARE @UTDDateDiff int
	SET @UTDDateDiff = DATEDIFF(mi,GETUTCDATE(),GETDATE())

-- Fetch information about the XEL file location
DECLARE @filename varchar(8000) ;
SELECT @filename = CAST(target_data as XML).value('(/EventFileTarget/File/@name)[1]', 'varchar(8000)')
FROM sys.dm_xe_session_targets
WHERE target_name = 'event_file' and event_session_address = (select address from sys.dm_xe_sessions where name = 'system_health');

SET @filename = SUBSTRING(@filename,1,CHARINDEX('system_health',@filename,1)-1) + '*.xel';

-- Read the XEL files to get the System Health Session Data
SELECT object_name,CAST(event_data as XML) as XMLData
INTO #tbl_sp_server_diagnostics
FROM sys.fn_xe_file_target_read_file(@filename, null, null, null)
WHERE object_name = 'sp_server_diagnostics_component_result'

SELECT 
DATEADD(mi,@UTDDateDiff,XMLData.value('(/event/@timestamp)[1]','datetime')) as EventTime,
XMLData.value('(/event/data/text)[1]','varchar(255)') as Component,
XMLData.value('(/event/data/text)[2]','varchar(255)') as [State]
FROM #tbl_sp_server_diagnostics
--WHERE  XMLData.value('(/event/data/text)[2]','varchar(255)')  <> 'CLEAN'
ORDER BY EventTime DESC

SELECT 
DATEADD(mi,@UTDDateDiff,XMLData.value('(/event/@timestamp)[1]','datetime')) as [Event Time],
XMLData.value('(/event/data/text)[1]','varchar(255)') as Component,
XMLData.value('(/event/data/value/system/@latchWarnings)[1]','bigint') as [Latch Warnings],
XMLData.value('(/event/data/value/system/@isAccessViolationOccurred)[1]','bigint') as [Access Violations],
XMLData.value('(/event/data/value/system/@nonYieldingTasksReported)[1]','bigint') as [Non Yields Reported],
XMLData.value('(/event/data/value/system/@pageFaults)[1]','bigint') as [Page Faults],
XMLData.value('(/event/data/value/system/@systemCpuUtilization)[1]','int') as [System CPU Utilization %],
XMLData.value('(/event/data/value/system/@sqlCpuUtilization)[1]','int') as [SQL CPU Utilization %],
XMLData.value('(/event/data/value/system/@BadPagesDetected)[1]','bigint') as [Bad Pages Detected],
XMLData.value('(/event/data/value/system/@BadPagesFixed)[1]','bigint') as [Bad Pages Fixed]
FROM #tbl_sp_server_diagnostics
WHERE XMLData.value('(/event/data/text)[1]','varchar(255)') = 'SYSTEM'
ORDER BY [Event Time] DESC

SELECT 
DATEADD(mi,@UTDDateDiff,XMLData.value('(/event/@timestamp)[1]','datetime')) as [Event Time],
XMLData.value('(/event/data/text)[1]','varchar(255)') as Component,
XMLData.value('(/event/data/value/queryProcessing/@maxWorkers)[1]','bigint') as [Max Workers],
XMLData.value('(/event/data/value/queryProcessing/@workersCreated)[1]','bigint') as [Workers Created],
XMLData.value('(/event/data/value/queryProcessing/@workersIdle)[1]','bigint') as [Idle Workers],
XMLData.value('(/event/data/value/queryProcessing/@pendingTasks)[1]','bigint') as [Pending Tasks],
XMLData.value('(/event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]','int') as [Unresolvable Deadlock],
XMLData.value('(/event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]','int') as [Deadlocked Schedulers]
FROM #tbl_sp_server_diagnostics
WHERE XMLData.value('(/event/data/text)[1]','varchar(255)') = 'QUERY_PROCESSING'
ORDER BY [Event Time] DESC

SELECT 
DATEADD(mi,@UTDDateDiff,XMLData.value('(/event/@timestamp)[1]','datetime')) as [Event Time],
XMLData.value('(/event/data/text)[1]','varchar(255)') as Component,
XMLData.value('(/event/data/value/resource/@outOfMemoryExceptions)[1]','bigint')  as [OOM Exceptions],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[1]','bigint')/(1024*1024*1024)  as [Available Physical Memory (GB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[3]','bigint')/(1024*1024*1024) as [Available Paging File (GB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[5]','int') as [Percent of Committed Memory in WS],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[6]','bigint') as [Page Faults],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[12]','bigint')/1024 as [VM Committed (MB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[13]','bigint')/(1024*1024) as [Locked Pages Allocated (GB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[14]','bigint')/(1024*1024) as [Large Pages Allocated (GB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[17]','bigint')/(1024*1024) as [Target Committed (GB)],
XMLData.value('(/event/data/value/resource/memoryReport/entry/@value)[18]','bigint')/(1024*1024) as [Current Committed (GB)]
FROM #tbl_sp_server_diagnostics
WHERE XMLData.value('(/event/data/text)[1]','varchar(255)') = 'RESOURCE'
ORDER BY [Event Time] DESC

SELECT 
DATEADD(mi,@UTDDateDiff,XMLData.value('(/event/@timestamp)[1]','datetime')) as [Event Time],
XMLData.value('(/event/data/text)[1]','varchar(255)') as Component,
XMLData.value('(/event/data/value/ioSubsystem/@ioLatchTimeouts)[1]','bigint')  as [IO Latch Timeouts],
XMLData.value('(/event/data/value/ioSubsystem/@totalLongIos)[1]','bigint')  as [Total Long IOs],
XMLData.value('(/event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@filePath)[1]','varchar(8000)')  as [Longest Pending Request File],
XMLData.value('(/event/data/value/ioSubsystem/longestPendingRequests/pendingRequest/@duration)[1]','bigint')  as [Longest Pending IO Duration]
FROM #tbl_sp_server_diagnostics
WHERE XMLData.value('(/event/data/text)[1]','varchar(255)') = 'IO_SUBSYSTEM'
ORDER BY [Event Time] DESC

DROP TABLE #tbl_sp_server_diagnostics

END 

SET NOCOUNT OFF