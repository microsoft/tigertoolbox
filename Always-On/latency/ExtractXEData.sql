-- Extract the data from the AlwaysOn extended event trace and store the extracted data in a tempdb table
-- This tempdb table would be used by the PowerBI Desktop report to pull data
USE TEMPDB
GO
IF OBJECT_ID('DMReplicaEvents') IS NOT NULL
BEGIN
  DROP TABLE DMReplicaEvents;
END
GO
SET NOCOUNT ON
SELECT 
@@SERVERNAME as server_name,
event_name,
xe.event_data.value('(/event/data[@name="log_block_id"]/value)[1]','bigint') AS log_block_id,
xe.event_data.value('(/event/data[@name="database_id"]/value)[1]','int') AS database_id,
CASE event_name 
	WHEN 'hadr_db_commit_mgr_harden' THEN xe.event_data.value('(/event/data[@name="time_to_commit"]/value)[1]','bigint')
	WHEN 'hadr_apply_log_block' THEN xe.event_data.value('(/event/data[@name="total_processing_time"]/value)[1]','bigint')
	WHEN 'hadr_log_block_send_complete' THEN xe.event_data.value('(/event/data[@name="total_processing_time"]/value)[1]','bigint')
	WHEN 'hadr_lsn_send_complete' THEN xe.event_data.value('(/event/data[@name="total_processing_time"]/value)[1]','bigint')
	ELSE xe.event_data.value('(/event/data[@name="processing_time"]/value)[1]','bigint') 
END AS processing_time,
xe.event_data.value('(/event/data[@name="start_timestamp"]/value)[1]','bigint') AS start_timestamp,
xe.event_data.value('(/event/@timestamp)[1]','DATETIMEOFFSET') AS publish_timestamp,
CASE event_name
	WHEN 'hadr_log_block_compression' THEN xe.event_data.value('(/event/data[@name="uncompressed_size"]/value)[1]','int')
	WHEN 'hadr_log_block_decompression' THEN xe.event_data.value('(/event/data[@name="uncompressed_size"]/value)[1]','int')
	WHEN 'hadr_capture_log_block' THEN xe.event_data.value('(/event/data[@name="log_block_size"]/value)[1]','int')
	ELSE NULL 
END AS log_block_size,
CASE event_name
	WHEN 'hadr_db_commit_mgr_harden' THEN xe.event_data.value('(/event/data[@name="replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_log_block_compression' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_log_block_decompression' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_capture_log_block' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_capture_filestream_wait' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_receive_harden_lsn_message' THEN xe.event_data.value('(/event/data[@name="target_availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_transport_receive_log_block_message' THEN xe.event_data.value('(/event/data[@name="target_availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_capture_vlfheader' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_send_harden_lsn_message' THEN xe.event_data.value('(/event/data[@name="availability_replica_id"]/value)[1]','uniqueidentifier')
	ELSE NULL 
END AS target_availability_replica_id,
CASE event_name
	WHEN 'hadr_receive_harden_lsn_message' THEN xe.event_data.value('(/event/data[@name="local_availability_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_transport_receive_log_block_message' THEN xe.event_data.value('(/event/data[@name="local_availability_replica_id"]/value)[1]','uniqueidentifier')
	ELSE drs.replica_id 
END AS local_availability_replica_id,
CASE event_name 
	WHEN 'hadr_db_commit_mgr_harden' THEN xe.event_data.value('(/event/data[@name="ag_database_id"]/value)[1]','uniqueidentifier')
	WHEN 'log_flush_start' THEN drs.group_database_id
	WHEN 'log_flush_complete' THEN drs.group_database_id
	WHEN 'log_block_pushed_to_logpool' THEN drs.group_database_id
	WHEN 'hadr_log_block_group_commit' THEN drs.group_database_id
	WHEN 'hadr_log_block_compression' THEN drs.group_database_id
	WHEN 'hadr_log_block_decompression' THEN drs.group_database_id
	WHEN 'recovery_unit_harden_log_timestamps' THEN drs.group_database_id
	WHEN 'hadr_capture_log_block' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_capture_filestream_wait' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_receive_harden_lsn_message' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_capture_vlfheader' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_apply_log_block' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_send_harden_lsn_message' THEN xe.event_data.value('(/event/data[@name="hadr_database_id"]/value)[1]','uniqueidentifier')
	WHEN 'hadr_transport_receive_log_block_message' THEN xe.event_data.value('(/event/data[@name="database_replica_id"]/value)[1]','uniqueidentifier')
	ELSE NULL 
END AS database_replica_id,
xe.event_data.value('(/event/data[@name="mode"]/value)[1]','bigint') AS mode
INTO DMReplicaEvents
FROM
(
	SELECT
		object_name as event_name,
		CONVERT(XML,Event_data) AS event_data
	FROM sys.fn_xe_file_target_read_file(
				'C:\Program Files\Microsoft SQL Server\MSSQL11.TigerAG1\MSSQL\Log\AlwaysOn_Data_Movement_Tracing*.xel', 
				null, null, null) as xe
	where object_name in ('hadr_log_block_group_commit',
							'log_block_pushed_to_logpool',
							'log_flush_start',
							'log_flush_complete',
							'hadr_log_block_compression',
							'hadr_capture_log_block',
							'hadr_capture_filestream_wait',
							'hadr_log_block_send_complete',
							'hadr_receive_harden_lsn_message',
							'hadr_db_commit_mgr_harden',
							'recovery_unit_harden_log_timestamps',
							'hadr_capture_vlfheader',
							'hadr_log_block_decompression',
							'hadr_apply_log_block',
							'hadr_send_harden_lsn_message',
							'hadr_log_block_decompression',
							'hadr_lsn_send_complete',
							'hadr_transport_receive_log_block_message')
) xe
LEFT OUTER JOIN sys.dm_hadr_database_replica_states drs 
ON drs.database_id = xe.event_data.value('(/event/data[@name="database_id"]/value)[1]','int') AND is_local = 1

-- Extract and store the replica information in tempdb as this is needed for providing the names of the databases and the replica instance in the visualizations
 USE TEMPDB
 GO
 IF OBJECT_ID('DMReplicaDBs') IS NOT NULL
 BEGIN
   DROP TABLE DMReplicaDBs;
 END
 GO
 SELECT d.database_id, drs.group_database_id,d.name
 INTO DMReplicaDBs
 FROM sys.databases d 
 	inner join sys.dm_hadr_database_replica_states drs 
 	on drs.database_id = d.database_id
WHERE is_local = 1
