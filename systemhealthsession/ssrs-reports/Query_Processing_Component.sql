SET NOCOUNT ON

-- Fetch data for only SQL Server 2012 instances
IF (SUBSTRING(CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)),1,CHARINDEX('.',CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)))-1) >= 11)
BEGIN

-- Get UTC time difference for reporting event times local to server time
DECLARE @UTCDateDiff int = DATEDIFF(mi,GETUTCDATE(),GETDATE());

-- Store XML data retrieved in temp table
SELECT TOP 1 CAST(xet.target_data AS XML) AS XMLDATA
INTO #SystemHealthSessionData
FROM sys.dm_xe_session_targets xet 
JOIN sys.dm_xe_sessions xe 
ON (xe.address = xet.event_session_address) 
WHERE xe.name = 'system_health'
AND xet.target_name = 'ring_buffer';



;WITH CTE_HealthSession (EventXML) AS
(
SELECT C.query('.') EventXML
FROM #SystemHealthSessionData a
CROSS APPLY a.XMLDATA.nodes('/RingBufferTarget/event') as T(C)
)
SELECT 
DATEADD(mi,@UTCDateDiff,EventXML.value('(/event/@timestamp)[1]','datetime')) as [Event Time],
EventXML.value('(/event/data/value/queryProcessing/@maxWorkers)[1]','bigint') as [Max Workers],
EventXML.value('(/event/data/value/queryProcessing/@workersCreated)[1]','bigint') as [Workers Created],
EventXML.value('(/event/data/value/queryProcessing/@workersIdle)[1]','bigint') as [Idle Workers],
EventXML.value('(/event/data/value/queryProcessing/@pendingTasks)[1]','bigint') as [Pending Tasks],
EventXML.value('(/event/data/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]','int') as [Unresolvable Deadlock],
EventXML.value('(/event/data/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]','int') as [Deadlocked Schedulers]
FROM CTE_HealthSession 
WHERE EventXML.value('(/event/@name)[1]', 'varchar(255)') = 'sp_server_diagnostics_component_result'
AND EventXML.value('(/event/data/text)[1]','varchar(255)') = 'QUERY_PROCESSING'
ORDER BY [Event Time];

DROP TABLE #SystemHealthSessionData

END
