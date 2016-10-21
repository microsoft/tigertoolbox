/*
T-SQL script to fetch security_error_ring_buffer_recorded information from the system health extended event session.

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
EventXML.value('(/event/data/value)[3]', 'int') as SessionID,
EventXML.value('(/event/data/value)[4]', 'int') as ErrorCode,
EventXML.value('(/event/data/value)[5]', 'varchar(100)') as APIName,
EventXML.value('(/event/data/value)[6]', 'varchar(100)') as CallingAPIName,
EventXML.value('(/event/data/value)[7]', 'nvarchar(max)') as CallStack
FROM CTE_HealthSession 
WHERE EventXML.value('(/event/@name)[1]', 'varchar(255)') = 'security_error_ring_buffer_recorded' 
ORDER BY EventTime;

-- Drop the temporary table
DROP TABLE #SystemHealthSessionData;

END 

SET NOCOUNT OFF