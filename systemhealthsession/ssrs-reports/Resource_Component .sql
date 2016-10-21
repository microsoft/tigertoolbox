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
EventXML.value('(/event/data/text)[1]','varchar(255)') as Component,
EventXML.value('(/event/data/value/resource/@outOfMemoryExceptions)[1]','bigint')  as [OOM Exceptions],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[1]','bigint')/(1024*1024*1024)  as [Available Physical Memory (GB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[3]','bigint')/(1024*1024*1024) as [Available Paging File (GB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[5]','int') as [Percent of Committed Memory in WS],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[6]','bigint') as [Page Faults],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[12]','bigint')/1024 as [VM Committed (MB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[13]','bigint')/(1024*1024) as [Locked Pages Allocated (GB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[14]','bigint')/(1024*1024) as [Large Pages Allocated (GB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[17]','bigint')/(1024*1024) as [Target Committed (GB)],
EventXML.value('(/event/data/value/resource/memoryReport/entry/@value)[18]','bigint')/(1024*1024) as [Current Committed (GB)]
FROM CTE_HealthSession 
WHERE EventXML.value('(/event/@name)[1]', 'varchar(255)') = 'sp_server_diagnostics_component_result'
AND EventXML.value('(/event/data/text)[1]','varchar(255)') = 'RESOURCE'
ORDER BY [Event Time] desc;

DROP TABLE #SystemHealthSessionData

END
