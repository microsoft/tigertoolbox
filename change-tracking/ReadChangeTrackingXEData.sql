-- Sample script to read data Change Tracking Automatic Cleanup Data using XE "change_tracking_cleanup"

-- Create an XE session to read the 
CREATE EVENT SESSION [ChangeTracking] ON SERVER 
ADD EVENT sqlserver.change_tracking_cleanup
ADD TARGET package0.ring_buffer
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

-- Start the session
ALTER EVENT SESSION ChangeTracking  
ON SERVER  
STATE = start

-- Store the XML data in a temporary table
SELECT CAST(xet.target_data as xml) as XMLDATA
INTO #CTCleanupData
FROM sys.dm_xe_session_targets xet
JOIN sys.dm_xe_sessions xe
ON (xe.address = xet.event_session_address)
WHERE xe.name = 'changetracking' -- ### UPDATE with appropriate change tracking session name ###
and target_name = 'ring_buffer'

-- Get information about the steps executed by the automatic cleanup
;WITH CT_CleanupSession (EventXML) AS
(
	SELECT C.query('.') EventXML
	FROM #CTCleanupData a
	CROSS APPLY a.XMLDATA.nodes('/RingBufferTarget/event') as T(C)
)
SELECT 
	EventXML.value('(/event/@timestamp)[1]', 'datetime') as [Time (UTC)],
	DB_NAME(EventXML.value('(/event/data[@name = "database_id"]/value)[1]', 'int')) as [Database Name],
	OBJECT_NAME(EventXML.value('(/event/data[@name = "object_id"]/value)[1]', 'int')) as [Object Name],
	EventXML.value('(/event/data[@name = "cleanup_id"]/text)[1]', 'varchar(255)') as [Step],
	EventXML.value('(/event/data[@name = "value"]/value)[1]', 'varchar(255)') as [Value],
	CASE EventXML.value('(/event/data[@name = "status"]/value)[1]', 'int')
		WHEN 1 THEN 'Not Initialized'
		WHEN 2 THEN 'Initialized'
		WHEN 8 THEN 'In Progress'
		WHEN 16 THEN 'Finished' 
		WHEN 32 THEN 'Error'
		END as [Status]
FROM CT_CleanupSession
WHERE EventXML.value('(/event/@name)[1]', 'varchar(255)') = 'change_tracking_cleanup'

-- Drop the temporary table
DROP TABLE #CTCleanupData
