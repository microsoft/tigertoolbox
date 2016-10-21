/*
T-SQL script to fetch connectivity_ring_buffer_recorded information from the system health extended event session.

Author: Amit Banerjee
Contact details:
Blog: www.troubleshootingsql.com
Twitter: http://twitter.com/banerjeeamit 

DISCLAIMER:
This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
*/

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

-- Parse XML data and provide required values in the form of a table
;WITH CTE_HealthSession (EventXML) AS
(
SELECT C.query('.') EventXML
FROM #SystemHealthSessionData a
CROSS APPLY a.XMLDATA.nodes('/RingBufferTarget/event') as T(C)
)
SELECT DATEADD(mi,@UTCDateDiff,EventXML.value('(/event/@timestamp)[1]', 'datetime')) as EventTime,
EventXML.value('(/event/data/text)[1]', 'varchar(255)') as connectivity_record_type,
EventXML.value('(/event/data/text)[2]', 'varchar(255)') as connectivity_record_source,
EventXML.value('(/event/data/text)[3]', 'varchar(255)') as tds_flags,
EventXML.value('(/event/data/value)[5]', 'int') as sessionid,
EventXML.value('(/event/data/value)[6]', 'int') as os_error,
EventXML.value('(/event/data/value)[7]', 'int') as sni_error,
EventXML.value('(/event/data/value)[8]', 'int') as sni_consumer_error,
EventXML.value('(/event/data/value)[9]', 'int') as sni_provider,
EventXML.value('(/event/data/value)[10]', 'int') as state,
EventXML.value('(/event/data/value)[11]', 'int') as local_port,
EventXML.value('(/event/data/value)[12]', 'int') as remote_port,
EventXML.value('(/event/data/value)[13]', 'int') as tds_input_buffer_error,
EventXML.value('(/event/data/value)[14]', 'int') as tds_output_buffer_error,
EventXML.value('(/event/data/value)[17]', 'int') as total_login_time_ms,
EventXML.value('(/event/data/value)[18]', 'int') as login_task_enqueued_ms,
EventXML.value('(/event/data/value)[19]', 'int') as network_writes_ms,
EventXML.value('(/event/data/value)[20]', 'int') as network_reads_ms,
EventXML.value('(/event/data/value)[21]', 'int') as ssl_processing_ms,
EventXML.value('(/event/data/value)[22]', 'int') as sspi_processing_ms,
EventXML.value('(/event/data/value)[23]', 'int') as login_trigger_and_resource_governor_processing_ms,
EventXML.value('(/event/data/value)[26]', 'varchar(255)') as local_host,
EventXML.value('(/event/data/value)[27]', 'varchar(255)') as remote_host
FROM CTE_HealthSession 
WHERE EventXML.value('(/event/@name)[1]', 'varchar(255)') = 'connectivity_ring_buffer_recorded' 
ORDER BY EventTime;

-- Drop the temporary table
DROP TABLE #SystemHealthSessionData;

END 

SET NOCOUNT OFF