-- T-SQL scripts to get relevant information from the Extended Event session

;WITH XEData 
AS
(
	SELECT CAST(xest.target_data as XML) xml_data
	FROM  sys.dm_xe_session_targets xest 
	INNER JOIN sys.dm_xe_sessions xes on xes.[address] = xest.event_session_address 
	WHERE xes.name = 'AG_XE_DEMO' 
	AND xest.target_name = 'ring_buffer'
)
SELECT 
dateadd(mi,datediff(mi,getutcdate(),getdate()),event_xml.value('(./@timestamp)', 'datetime')) as [Time],
event_xml.value('(./@timestamp)', 'datetime') as [UTCTime],
event_xml.value('(./data[@name="new_timeout"]/value)[1]', 'bigint') as [New_Timeout], 
event_xml.value('(./data[@name="state"]/text)[1]', 'varchar(255)') as [State],
event_xml.value('(./data[@name="id_or_name"]/value)[1]', 'varchar(255)') as [AG_Name],
event_xml.value('(./data[@name="error_code"]/value)[1]', 'varchar(255)') as [ErrorCode]
FROM XEData
CROSS APPLY xml_data.nodes('//event[@name="hadr_ag_lease_renewal"]') n (event_xml) 

;WITH XEData 
AS
(
	SELECT CAST(xest.target_data as XML) xml_data
	FROM  sys.dm_xe_session_targets xest 
	INNER JOIN sys.dm_xe_sessions xes on xes.[address] = xest.event_session_address 
	WHERE xes.name = 'AG_XE_DEMO' 
	AND xest.target_name = 'ring_buffer'
)
SELECT 
dateadd(mi,datediff(mi,getutcdate(),getdate()),event_xml.value('(./@timestamp)', 'datetime')) as [Time],
event_xml.value('(./@timestamp)', 'datetime') as [UTCTime],
event_xml.value('(./data[@name="new_timeout"]/value)[1]', 'bigint') as [New_Timeout], 
event_xml.value('(./data[@name="availability_group_name"]/value)[1]', 'varchar(255)') as [AGName],
event_xml.value('(./data[@name="current_time"]/value)[1]', 'bigint') as [Current_Time],
event_xml.value('(./data[@name="state"]/value)[1]', 'varchar(255)') as [State]
FROM XEData
CROSS APPLY xml_data.nodes('//event[@name="availability_group_lease_expired"]') n (event_xml) 
