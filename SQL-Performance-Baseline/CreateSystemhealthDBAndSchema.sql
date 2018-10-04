/**************************
 This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
 Author: Denzil Ribeiro
 Date: Jan 6, 2013
 Description:
 This T-SQL script extracts information found in the System Health Session and puts them into a permanent tables in a database you create
*/
/*
use master
go
drop database XEvents_ImportSystemHealth
go


Create Database XEvents_ImportSystemHealth
go
Alter Database XEvents_ImportSystemHealth SET RECOVERY SIMPLE;
USE [XEvents_ImportSystemHealth]
GO
*/
/****** Object:  StoredProcedure [dbo].[sp_ImportXML]    Script Date: 1/25/2013 3:39:13 PM ******/
use dba_local
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[sp_ImportXML]
@path_to_health_session nvarchar(4000)
as
If object_id('tbl_XEImport') is not null
	drop table tbl_XEImport
select [object_name] ,CAST(event_data AS XML)  as c1
into tbl_XEImport
from sys.fn_xe_file_target_read_file(@path_to_health_session,NULL,NULL,NULL)

create index ind_xeImport on tbl_XEImport(object_name)

If object_id('tbl_ServerDiagnostics') is not null
	drop table tbl_ServerDiagnostics
	select c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)') as SdComponent,c1  
	into tbl_ServerDiagnostics
	from tbl_XEImport
	where object_name = 'sp_server_diagnostics_component_result'
/*
else
select c1.value('(event/data[@name="component"]/value)[1]', 'varchar(100)') as SdComponent,c1  
	into tbl_ServerDiagnostics
	from tbl_XEImport 
	where object_name = 'component_health_result'
*/
--create index ind_ServerDiagnostics on tbl_ServerDiagnostics(SdComponent)

GO
/****** Object:  StoredProcedure [dbo].[SpLoadComponentSummary]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadComponentSummary]
@UTDDateDiff int
as
if object_id('tbl_Summary') is not null
drop table tbl_Summary
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as timestamp,
	 c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)') as component_name,
	 c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') as [component_state]
/*
     CASE c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)')
		WHEN '' then  c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)')
		ELSE c1.value('(event/data[@name="component"]/value)[1]', 'varchar(100)')
	 END as component_name,
	 CASE c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') 
	   WHEN '' then c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') 
	   ELSE c1.value('(event/data[@name="state_desc"]/value)[1]', 'varchar(100)') 
	  END as [component_state]
*/
into tbl_Summary
FROM tbl_ServerDiagnostics 

CREATE NONCLUSTERED INDEX [Ind_TblSummary] ON [dbo].[tbl_Summary]
(
	[timestamp] ASC
)WITH (SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]


GO
/****** Object:  StoredProcedure [dbo].[spLoadConnectivity_ring_buffer]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[spLoadConnectivity_ring_buffer]
@UTDDateDiff int
as
if object_id('tbl_connectivity_ring_buffer') is not null
drop table tbl_connectivity_ring_buffer

  select 
   c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
  	DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
              c1.value('(./event/data[@name="type"]/text)[1]', 'varchar(100)') AS [Type],
              c1.value('(./event/data[@name="id"]/value)[1]', 'bigint') as record_id,
			  c1.value('(./event/data[@name="source"]/text)[1]', 'varchar(20)') as source,
			  c1.value('(./event/data[@name="session_id"]/value)[1]', 'int') as session_id,
			  c1.value('(./event/data[@name="os_error"]/value)[1]', 'bigint') as os_error,
			  c1.value('(./event/data[@name="sni_error"]/value)[1]', 'bigint') as sni_error,
			  c1.value('(./event/data[@name="sni_consumer_error"]/value)[1]', 'bigint') as sni_consumer_error,
			  c1.value('(./event/data[@name="state"]/value)[1]', 'int') as [state],
			  c1.value('(./event/data[@name="port"]/value)[1]', 'int') as port,
			  c1.value('(./event/data[@name="remote_port"]/value)[1]', 'int') as remote_port,
			  c1.value('(./event/data[@name="tds_input_buffer_error"]/value)[1]', 'bigint') as tds_inputbuffererror,
			  c1.value('(./event/data[@name="total_login_time_ms"]/value)[1]', 'bigint') as total_login_time_ms,
			  c1.value('(./event/data[@name="login_task_enqueued_ms"]/value)[1]', 'bigint') as login_task_enqueued_ms,
			  c1.value('(./event/data[@name="network_writes_ms"]/value)[1]', 'bigint') as network_writes_ms,
			  c1.value('(./event/data[@name="network_reads_ms"]/value)[1]', 'bigint') as network_reads_ms,
			  c1.value('(./event/data[@name="ssl_processing_ms"]/value)[1]', 'bigint') as ssl_processing_ms,
			  c1.value('(./event/data[@name="sspi_processing_ms"]/value)[1]', 'bigint') as sspi_processing_ms,
			  c1.value('(./event/data[@name="login_trigger_and_resource_governor_processing_ms"]/value)[1]', 'bigint') as login_trigger_and_resource_governor_processing_ms,
			  c1.value('(./event/data[@name="connection_id"]/value)[1]', 'varchar(50)') as connection_id,
			  c1.value('(./event/data[@name="connection_peer_id"]/value)[1]', 'varchar(50)') as connection_peer_id,
			  c1.value('(./event/data[@name="local_host"]/value)[1]', 'varchar (50)') as local_host,
			  c1.value('(./event/data[@name="remote_host"]/value)[1]', 'varchar (50)') as remote_host,
			  c1.value('(./event/data[@name="SessionIsKilled"]/value)[1]', 'smallint') as SessionIsKilled
	into tbl_connectivity_ring_buffer
	from tbl_XEImport where  object_name =  'connectivity_ring_buffer_recorded'              

GO
/****** Object:  StoredProcedure [dbo].[SpLoadErrorRecorded]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadErrorRecorded]
@UTDDateDiff int
as
if object_id('tbl_errors') is not null
drop table tbl_errors
select 
			c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
			DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
			c1.value('(./event/data[@name="session_id"])[1]', 'int') as session_id,
			c1.value('(./event/data[@name="database_id"])[1]', 'int') as database_id,
			c1.value('(./event/data[@name="error_number"])[1]', 'int') as [error_number],
			c1.value('(./event/data[@name="severity"])[1]', 'int') as severity,
			c1.value('(./event/data[@name="state"])[1]', 'int') as [state],
			c1.value('(./event/data[@name="category"]/text)[1]', 'nvarchar(100)') as category,
			c1.value('(./event/data[@name="destination"]/text)[1]', 'nvarchar(100)') as destination,
			c1.value('(./event/data[@name="message"])[1]', 'nvarchar(1000)') as message

into tbl_errors		
from tbl_XEImport
where object_name like 'error_reported'
GO

/****** Object:  StoredProcedure [dbo].[SpLoadIO_SUBSYSTEMComponent]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadIO_SUBSYSTEMComponent]
@UTDDateDiff int
as
if object_id('tbl_IO_SUBSYSTEM') is not null
drop table tbl_IO_SUBSYSTEM
select 
     c1.value('(./event/@timestamp)[1]', 'datetime') as UTCtimestamp,
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as timestamp,
     c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)') as [component_name],
	 c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') as [component_state],
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/@ioLatchTimeouts)[1]','int') as [ioLatchTimeouts],
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/@intervalLongIos)[1]','int') as [intervalLongIos],
 	 c1.value('(event/data[@name="data"]/value/ioSubsystem/@totalLongIos)[1]','int') as [totalLongIos],	 
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/longestPendingRequests/pendingRequest[1]/@duration)[1]','bigint') as [longestPendingRequests_duration],
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/longestPendingRequests/pendingRequest[1]/@filePath)[1]','nvarchar(500)') as [longestPendingRequests_filePath],
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/longestPendingRequests/pendingRequest[1]/@offset)[1]','bigint') as [longestPendingRequests_offset],
	 c1.value('(event/data[@name="data"]/value/ioSubsystem/longestPendingRequests/pendingRequest[1]/@handle)[1]','nvarchar(20)') as [longestPendingRequests_handle]
into tbl_IO_SUBSYSTEM
FROM tbl_ServerDiagnostics 
where SdComponent = 'IO_SUBSYSTEM'

GO
/****** Object:  StoredProcedure [dbo].[SpLoadQueryProcessing]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadQueryProcessing]
@UTDDateDiff int
as
if object_id('tbl_QUERY_PROCESSING') is not null
drop table [tbl_QUERY_PROCESSING]
select 
			c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
			DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
			 c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)') as [component_name],
			c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') as [component_state],
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@maxWorkers)[1]', 'int') as maxworkers,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@workersCreated)[1]', 'int') as workerscreated,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'int') as tasksCompletedWithinInterval,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'bigint') as oldestPendingTaskWaitingTime,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@pendingTasks)[1]', 'int') as pendingTasks,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'int') as hasUnresolvableDeadlockOccurred,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'int') as hasDeadlockedSchedulersOccurred,
			c1.value('(./event//data[@name="data"]/value/queryProcessing/@trackingNonYieldingScheduler)[1]', 'varchar(10)') as trackingNonYieldingScheduler
into [tbl_QUERY_PROCESSING]			
from tblQryProcessingXmlOutput

GO
/****** Object:  StoredProcedure [dbo].[SpLoadQueryProcessingComponent]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadQueryProcessingComponent]
@UTDDateDiff int
as
-- Import the XML
If object_id('tblQryProcessingXmlOutput') is not null
	drop table tblQryProcessingXmlOutput
CREATE TABLE [dbo].[tblQryProcessingXmlOutput](
	[c1] [xml] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

insert into tblQryProcessingXmlOutput (c1)
select c1 as snodes 
FROM tbl_ServerDiagnostics 
where SdComponent = 'QUERY_PROCESSING'
	
	
-- Call individual Pieces
exec SpLoadQueryProcessingComponent_TopWaits @UTDDateDiff
exec SpLoadQueryProcessing @UTDDateDiff
exec SpLoadQueryProcessingComponent_Blocking @UTDDateDiff
--exec SpLoadQueryProcessingComponent_HighCPU @UTDDateDiff
--exec SpLoadQueryProcessingComponent_QueryWaits @UTDDateDiff

GO
/****** Object:  StoredProcedure [dbo].[SpLoadQueryProcessingComponent_Blocking]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadQueryProcessingComponent_Blocking]
@UTDDateDiff int
as
if object_id('tbl_BlockingXeOutput') is not null
drop table tbl_BlockingXeOutput
select
	 [utctimestamp],[timestamp],
	 c1.value('(blocked-process-report/blocking-process/process/inputbuf)[1]', 'nvarchar(max)') as [blocking_process],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@spid)[1]', 'int') as [blocking_process_id],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@ecid)[1]', 'int') as [blocking_process_ecid],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@status)[1]', 'varchar(100)') as [blocking_process_status],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@isolationlevel)[1]', 'varchar(200)') as [blocking_process_isolationlevel],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@lastbatchstarted)[1]', 'datetime') as [blocking_process_lastbatchstarted],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@lastbatchcompleted)[1]', 'datetime') as [blocking_process_lastbatchcompleted],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@lastattention)[1]', 'datetime') as [blocking_process_lastattention],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@trancount)[1]', 'int') as [blocking_process_trancount],
	 c1.value('(blocked-process-report/blocking-process/process[1]/@xactid)[1]', 'bigint') as [blocking_process_xactid],
	 c1.value('(/blocked-process-report/blocking-process/process[1]/@clientapp)[1]', 'nvarchar(100)') as [blocking_process_clientapp],
	 c1.value('(/blocked-process-report/blocking-process/process[1]/@hostname)[1]', 'nvarchar(100)') as [blocking_process_hostname],
	 c1.value('(/blocked-process-report/blocking-process/process[1]/@loginname)[1]', 'nvarchar(100)') as [blocking_process_loginname],
	 c1.value('(/blocked-process-report/blocking-process/process[1]/@waitresource)[1]', 'nvarchar(200)') as [blocking_process_wait_resource],

	 c1.value('(/blocked-process-report/blocked-process/process/inputbuf)[1]', 'nvarchar(max)') as [blocked_process],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@spid)[1]', 'int') as [blocked_process_id],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@ecid)[1]', 'int') as [blocked_process_ecid],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@status)[1]', 'varchar(100)') as [blocked_process_status],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@waitresource)[1]', 'nvarchar(200)') as [blocked_process_wait_resource],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@lockMode)[1]', 'char(5)') as [blocked_process_lockMode],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@waittime)[1]', 'nvarchar(200)') as [blocked_process_wait_time],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@lastbatchstarted)[1]', 'datetime') as [blocked_process_lastbatchstarted],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@lastbatchcompleted)[1]', 'datetime') as [blocked_process_lastbatchcompleted],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@lastattention)[1]', 'datetime') as [blocked_process_lastattention],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@clientapp)[1]', 'nvarchar(100)') as [blocked_process_clientapp],
	 c1.value('(/value/blocked-process-report/blocked-process/process[1]/@hostname)[1]', 'nvarchar(100)') as [blocked_process_hostname],
	 c1.value('(/blocked-process-report/blocked-process/process[1]/@loginname)[1]', 'nvarchar(100)') as [blocked_process_loginname]
	 --T.bpnodes.value('(event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/executionstack/frame[1]/@sqlhandle)[1]', 'nvarchar(max)') as [blocking_process_sqlhandle]
into tbl_BlockingXeOutput
FROM 
(
select c1.value('(event/@timestamp)[1]','datetime') as [utctimestamp]
		,DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp]
		,T.blk.query( '.') as c1 from tblQryProcessingXmlOutput
CROSS APPLY c1.nodes('./event/data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report') as T(blk) 
) as T1

GO
/****** Object:  StoredProcedure [dbo].[SpLoadQueryProcessingComponent_TopWaits]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadQueryProcessingComponent_TopWaits]
@UTDDateDiff int
as
if object_id('tbl_OS_WAIT_STATS_byDuration') is not null
drop table tbl_OS_WAIT_STATS_byDuration

CREATE TABLE [dbo].[tbl_OS_WAIT_STATS_byDuration](
	[UTCtimestamp] [datetime] NULL,
	[timestamp] [datetime] NULL,
	[wait_type] [varchar](47) NULL,
	[waiting_tasks_count] [bigint] NULL,
	[avg_wait_time_ms] [bigint] NULL,
	[max_wait_time_ms] [bigint] NULL
) ON [PRIMARY]
ALTER TABLE [dbo].[tbl_OS_WAIT_STATS_byDuration] ADD [wait_category]  AS (case when [wait_type] like 'LCK%' then 'Locks' when [wait_type] like 'PAGEIO%' then 'Page I/O Latch' when [wait_type] like 'PAGELATCH%' then 'Page Latch (non-I/O)' when [wait_type] like 'LATCH%' then 'Latch (non-buffer)' when [wait_type] like 'IO_COMPLETION' then 'I/O Completion' when [wait_type] like 'ASYNC_NETWORK_IO' then 'Network I/O (client fetch)' when [wait_type]='CMEMTHREAD' OR [wait_type]='SOS_RESERVEDMEMBLOCKLIST' OR [wait_type]='RESOURCE_SEMAPHORE' then 'Memory' when [wait_type] like 'RESOURCE_SEMAPHORE_%' then 'Compilation' when [wait_type] like 'MSQL_XP' then 'XProc' when [wait_type] like 'WRITELOG' then 'Writelog' when [wait_type]='FT_IFTS_SCHEDULER_IDLE_WAIT' OR [wait_type]='WAITFOR' OR [wait_type]='EXECSYNC' OR [wait_type]='XE_TIMER_EVENT' OR [wait_type]='XE_DISPATCHER_WAIT' OR [wait_type]='WAITFOR_TASKSHUTDOWN' OR [wait_type]='WAIT_FOR_RESULTS' OR [wait_type]='SNI_HTTP_ACCEPT' OR [wait_type]='SLEEP_TEMPDBSTARTUP' OR [wait_type]='SLEEP_TASK' OR [wait_type]='SLEEP_SYSTEMTASK' OR [wait_type]='SLEEP_MSDBSTARTUP' OR [wait_type]='SLEEP_DCOMSTARTUP' OR [wait_type]='SLEEP_DBSTARTUP' OR [wait_type]='SLEEP_BPOOL_FLUSH' OR [wait_type]='SERVER_IDLE_CHECK' OR [wait_type]='RESOURCE_QUEUE' OR [wait_type]='REQUEST_FOR_DEADLOCK_SEARCH' OR [wait_type]='ONDEMAND_TASK_QUEUE' OR [wait_type]='LOGMGR_QUEUE' OR [wait_type]='LAZYWRITER_SLEEP' OR [wait_type]='KSOURCE_WAKEUP' OR [wait_type]='FSAGENT' OR [wait_type]='CLR_MANUAL_EVENT' OR [wait_type]='CLR_AUTO_EVENT' OR [wait_type]='CHKPT' OR [wait_type]='CHECKPOINT_QUEUE' OR [wait_type]='BROKER_TO_FLUSH' OR [wait_type]='BROKER_TASK_STOP' OR [wait_type]='BROKER_TRANSMITTER' OR [wait_type]='BROKER_RECEIVE_WAITFOR' OR [wait_type]='BROKER_EVENTHANDLER' OR [wait_type]='DBMIRROR_EVENTS_QUEUE' OR [wait_type]='DBMIRROR_DBM_EVENT' OR [wait_type]='DBMIRRORING_CMD' OR [wait_type]='DBMIRROR_WORKER_QUEUE' then 'IGNORABLE' else [wait_type] end)
Create clustered index [tbl_OS_WAIT_STATS_byDuration_Clus] on [tbl_OS_WAIT_STATS_byDuration](timestamp)


INSERT INTO [dbo].[tbl_OS_WAIT_STATS_byDuration]
           ([UTCtimestamp]
		    ,[timestamp]
           ,[wait_type]
           ,[waiting_tasks_count]
           ,[avg_wait_time_ms]
           ,[max_wait_time_ms])
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[1]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[1]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[1]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[1]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[2]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[2]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[2]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[2]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[3]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[3]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[3]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[3]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[4]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[4]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[4]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[4]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[5]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[5]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[5]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[5]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL 
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[6]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[6]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[6]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[6]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[7]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[7]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[7]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[7]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[8]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[8]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[8]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[8]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[9]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[9]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[9]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[9]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[10]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[10]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[10]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/nonPreemptive/byCount/wait[10]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput

UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[1]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[1]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[1]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[1]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[2]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[2]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[2]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[2]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[3]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[3]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[3]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[3]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[4]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[4]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[4]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[4]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[5]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[5]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[5]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[5]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL 
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[6]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[6]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[6]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[6]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[7]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[7]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[7]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[7]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[8]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[8]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[8]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[8]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[9]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[9]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[9]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[9]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput
UNION ALL
select 
     c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
     c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[10]/@waitType)[1]','varchar(47)') as [waitType],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[10]/@waits)[1]','bigint') as [waits],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[10]/@averageWaitTime)[1]','bigint') as [averageWaitTime],
	 c1.value('(event/data[@name="data"]/value/queryProcessing/topWaits/preemptive/byCount/wait[10]/@maxWaitTime)[1]','bigint') as [maxWaitTime]
FROM tblQryProcessingXmlOutput

GO
/****** Object:  StoredProcedure [dbo].[SpLoadResourceComponent]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadResourceComponent]
@UTDDateDiff int
as
if object_id('tbl_Resource') is not null
	drop table tbl_Resource
select 
			c1.value('(./event/@timestamp)[1]', 'datetime') as UTCtimestamp,
			DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
			c1.value('(./event//data[@name="state"]/text)[1]', 'varchar(20)') as State,
			c1.value('(./event//data[@name="data"]/value/resource/@lastNotification)[1]', 'nvarchar(100)') as lastNotification,
			c1.value('(./event//data[@name="data"]/value/resource/@outOfMemoryExceptions)[1]', 'tinyint') as outOfMemoryExceptions,
			c1.value('(./event//data[@name="data"]/value/resource/@isAnyPoolOutOfMemory)[1]', 'tinyint') as isAnyPoolOutOfMemory,
			c1.value('(./event//data[@name="data"]/value/resource/@processOutOfMemoryPeriod)[1]', 'tinyint') as processOutOfMemoryPeriod,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Available Physical Memory"]/@value)[1]', 'bigint') as available_physical_memory,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Available Virtual Memory"]/@value)[1]', 'bigint') as available_virtual_memory,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Available Paging File"]/@value)[1]', 'bigint') as available_paging_file,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Working Set"]/@value)[1]', 'bigint') as working_set,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Percent of Committed Memory in WS"]/@value)[1]', 'bigint') as percent_workingset_committed,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Page Faults"]/@value)[1]', 'bigint') as page_faults,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="System physical memory high"]/@value)[1]', 'bigint') as sys_physical_memory_high,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="System physical memory low"]/@value)[1]', 'bigint') as sys_physical_memory_low,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Process physical memory low"]/@value)[1]', 'bigint') as process_phyiscal_memory_low,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Process/System Counts"]/entry[@description="Process virtual memory low"]/@value)[1]', 'bigint') as process_virtual_memory_low,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="VM Reserved"]/@value)[1]', 'bigint') as vm_reserved_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="VM Committed"]/@value)[1]', 'bigint') as vm_committed_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Locked Pages Allocated"]/@value)[1]', 'bigint') as locked_pages_allocated_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Large Pages Allocated"]/@value)[1]', 'bigint') as large_pages_allocated_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Target Committed"]/@value)[1]', 'bigint') as target_committed_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Current Committed"]/@value)[1]', 'bigint') as current_committed_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Pages Allocated"]/@value)[1]', 'bigint') as Pages_allocated_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Pages Reserved"]/@value)[1]', 'bigint') as pages_reserved_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Pages Free"]/@value)[1]', 'bigint') as pages_free_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Pages In Use"]/@value)[1]', 'bigint') as pages_in_use_kb,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Page Alloc Potential"]/@value)[1]', 'bigint') as page_alloc_potential,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="NUMA Growth Phase"]/@value)[1]', 'int') as numa_growth_phase,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Last OOM Factor"]/@value)[1]', 'int') as last_oom_factor,
			c1.value('(./event//data[@name="data"]/value/resource/memoryReport[@name="Memory Manager"]/entry[@description="Last OS Error"]/@value)[1]', 'int') as last_os_error
into tbl_Resource
FROM  tbl_ServerDiagnostics
where SdComponent = 'RESOURCE'


GO
/****** Object:  StoredProcedure [dbo].[spLoadSchedulerMonitor]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create Procedure [dbo].[spLoadSchedulerMonitor]
@UTDDateDiff int
as
if object_id('tbl_scheduler_monitor') is not null
drop table tbl_scheduler_monitor
select 
			c1.value('(./event/@timestamp)[1]', 'datetime') as UTCtimestamp,
			DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
			c1.value('(./event/data[@name="id"])[1]', 'bigint') as [id],
			c1.value('(./event/data[@name="process_utilization"])[1]', 'int') as process_utilization,
			c1.value('(./event/data[@name="system_idle"])[1]', 'int') as system_idle,
			c1.value('(./event/data[@name="user_mode_time"])[1]', 'bigint') as user_mode_time,
			c1.value('(./event/data[@name="kernel_mode_time"])[1]', 'bigint') as kernel_mode_time,
			c1.value('(./event/data[@name="working_set_delta"])[1]', 'numeric(24,0)') as working_set_delta,
			c1.value('(./event/data[@name="memory_utilization"])[1]', 'int') as memory_utilization
into tbl_scheduler_monitor			
from tbl_XEImport
where object_name like 'scheduler_monitor_system_health_ring_buffer_recorded'

GO
/****** Object:  StoredProcedure [dbo].[SpLoadSecurityRingBuffer]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadSecurityRingBuffer]
@UTDDateDiff int
as
if object_id('tbl_security_ring_buffer') is not null
drop table [tbl_security_ring_buffer]
select 
			c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
			DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
			c1.value('(./event/data[@name="id"])[1]', 'bigint') as id,
			c1.value('(./event/data[@name="session_id"])[1]', 'int') as session_id,
			c1.value('(./event/data[@name="error_code"])[1]', 'bigint') as [error_code],
			c1.value('(./event/data[@name="api_name"])[1]', 'nvarchar(100)') as api_name,
			c1.value('(./event/data[@name="calling_api_name"])[1]', 'nvarchar(100)') as calling_api_name

into [tbl_security_ring_buffer]
from tbl_XEImport
where object_name like 'security_error_ring_buffer_recorded'

GO
/****** Object:  StoredProcedure [dbo].[SpLoadSYSTEMComponent]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[SpLoadSYSTEMComponent]
@UTDDateDiff int
as
if object_id('tbl_SYSTEM') is not null
drop table tbl_SYSTEM
select 
	 c1.value('(event/@timestamp)[1]','datetime') as [UTCtimestamp],
	 DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as timestamp,
	 c1.value('(event/data[@name="component"]/text)[1]', 'varchar(100)') as [component_name],
	 c1.value('(event/data[@name="state"]/text)[1]', 'varchar(100)') as [component_state],
	 c1.value('(event/data[@name="data"]/value/system[1]/@spinlockBackoffs)[1]', 'int') as [spinlockBackoffs],
	 c1.value('(event/data[@name="data"]/value/system[1]/@sickSpinlockTypeAfterAv)[1]', 'varchar(100)') as [sickSpinlockTypeAfterAv],
	 c1.value('(event/data[@name="data"]/value/system[1]/@latchWarnings)[1]', 'int') as [latchWarnings],
	 c1.value('(event/data[@name="data"]/value/system[1]/@isAccessViolationOccurred)[1]', 'int') as [isAccessViolationOccurred],
	 c1.value('(event/data[@name="data"]/value/system[1]/@writeAccessViolationCount)[1]', 'int') as [writeAccessViolationCount],
	 c1.value('(event/data[@name="data"]/value/system[1]/@totalDumpRequests)[1]', 'int') as [totalDumpRequests],
	 c1.value('(event/data[@name="data"]/value/system[1]/@intervalDumpRequests)[1]', 'int') as [intervalDumpRequests],
	 c1.value('(event/data[@name="data"]/value/system[1]/@nonYieldingTasksReported)[1]', 'int') as [nonYieldingTasksReported],
	 c1.value('(event/data[@name="data"]/value/system[1]/@pageFaults)[1]', 'bigint') as [pageFaults],
	 c1.value('(event/data[@name="data"]/value/system[1]/@systemCpuUtilization)[1]', 'int') as [systemCpuUtilization],
	 c1.value('(event/data[@name="data"]/value/system[1]/@sqlCpuUtilization)[1]', 'int') as [sqlCpuUtilization],
	 c1.value('(event/data[@name="data"]/value/system[1]/@BadPagesDetected)[1]', 'int') as [BadPagesDetected],
	 c1.value('(event/data[@name="data"]/value/system[1]/@BadPagesFixed)[1]', 'int') as [BadPagesFixed],
	 c1.value('(event/data[@name="data"]/value/system[1]/@LastBadPageAddress)[1]', 'nvarchar(30)') as [LastBadPageAddress]
into tbl_SYSTEM	  
FROM tbl_ServerDiagnostics 
where SdComponent = 'SYSTEM'
GO


/****** Object:  StoredProcedure [dbo].[spLoadWaitQueries]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[spLoadWaitQueries]
@UTDDateDiff int
as
if object_id('tbl_waitqueries') is not null
drop table tbl_waitqueries
SELECT
c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp],
c1.value('(/event/data[@name="wait_type"]/text)[1]', 'varchar(50)') as WaitType,
c1.value('(/event/data[@name="duration"]/value)[1]', 'bigint') as Duration,
c1.value('(/event/data[@name="signal_duration"]/value)[1]', 'bigint') as signal_duration,
c1.value('(/event/action[@name="session_id"]/value)[1]', 'int') as Session_ID,
c1.value('(/event/action[@name="sql_text"]/value)[1]', 'varchar(max)') as sql_text
into tbl_waitqueries
FROM tbl_XEImport
where object_name like  'wait_info%'
GO




/****** Object:  StoredProcedure [dbo].[spLoadDeadlockReport]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[spLoadDeadlockReport]
@UTDDateDiff int
as
if object_id('tbl_DeadlockReport') is not null
drop table tbl_DeadlockReport
SELECT
c1.value('(./event/@timestamp)[1]', 'datetime') as utctimestamp,
DATEADD(mi,@UTDDateDiff,c1.value('(./event/@timestamp)[1]', 'datetime')) as [timestamp]
, *
into tbl_DeadlockReport
FROM tbl_XEImport
where object_name like  'xml_deadlock_report'
GO




/****** Object:  StoredProcedure [dbo].[spLoadSystemHealthSession]    Script Date: 1/25/2013 3:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create procedure [dbo].[spLoadSystemHealthSession]
@path_to_health_session nvarchar(4000) = NULL ,
@UTDDateDiff int = 0
as

if object_id('tbl_ImportStatus') is not null
drop table tbl_ImportStatus
Create table tbl_ImportStatus
( StepName varchar(100),
  Status varchar(20),
  Starttime datetime
)
insert into tbl_ImportStatus Values('Load System Health Session','Processing',getdate())

DECLARE @filename varchar(8000) ;
IF (SUBSTRING(CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)),1,CHARINDEX('.',CAST(SERVERPROPERTY ('ProductVersion') AS varchar(50)))-1) >= 11)
BEGIN

	If ( @path_to_health_session is null or @path_to_health_session ='')
	begin
		SET @UTDDateDiff = DATEDIFF(mi,GETUTCDATE(),GETDATE())
	-- Fetch information about the XEL file location
	
		SELECT @filename = CAST(target_data as XML).value('(/EventFileTarget/File/@name)[1]', 'varchar(8000)')
		FROM sys.dm_xe_session_targets
		WHERE target_name = 'event_file' and event_session_address = (select address from sys.dm_xe_sessions where name = 'system_health')
		SET @path_to_health_session = SUBSTRING(@filename,1,CHARINDEX('system_health',@filename,1)-1) + 'system_health*.xel'
		select @path_to_health_session,@filename, @UTDDateDiff
	end

	insert into tbl_ImportStatus Values('Importing XEL file','Processing',getdate())
	exec sp_ImportXML @path_to_health_session 
	
	insert into tbl_ImportStatus Values('Load Scheduler Monitor','Processing',getdate())
	exec spLoadSchedulerMonitor @UTDDateDiff

	insert into tbl_ImportStatus Values('Load Resource Server Health Component','Processing',getdate())
	exec SpLoadResourceComponent @UTDDateDiff

	insert into tbl_ImportStatus Values('Load IO_Subsystem Server Health Component','Processing',getdate())
	exec SpLoadIO_SUBSYSTEMComponent @UTDDateDiff

	insert into tbl_ImportStatus Values('Load System Server Health Component','Processing',getdate())
	exec SpLoadSYSTEMComponent @UTDDateDiff

	insert into tbl_ImportStatus Values('Load System Health Summary','Processing',getdate())
	exec SpLoadComponentSummary @UTDDateDiff

	insert into tbl_ImportStatus Values('Load Query_Processing Server Health Component','Processing',getdate())
	exec SpLoadQueryProcessingComponent @UTDDateDiff

	insert into tbl_ImportStatus Values('Load Security Ring Buffer','Processing',getdate())
	exec SpLoadSecurityRingBuffer @UTDDateDiff

	insert into tbl_ImportStatus Values('Load Errors Recorded','Processing',getdate())
	exec SpLoadErrorRecorded @UTDDateDiff
	
	insert into tbl_ImportStatus Values('Wait Queries','Processing',getdate())
	exec spLoadWaitQueries @UTDDateDiff

	insert into tbl_ImportStatus Values('Connectivity Ring Buffer','Processing',getdate())
	exec spLoadConnectivity_ring_buffer @UTDDateDiff

	insert into tbl_ImportStatus Values('Deadlock Report','Processing',getdate())
	exec [spLoadDeadlockReport] @UTDDateDiff

	insert into tbl_ImportStatus Values('Import Finished','Done',getdate())
end
Else 
  select 'Not a supported Server version: ' + @@version

GO

/********** TODO
CREATE INDEXES to improve performance

****************/



select 'Process System Health Session fom a SQL instance' as ImportMethod, 'Exec spLoadSystemHealthSession' as Example
Union all
select 'Process System Health XEL files from a UNC' as ImportMethod, 'exec spLoadSystemHealthSession @path_to_health_session=''D:\XELFiles\system_health*.xel'',@UTDDateDiff=-6' as Example

/*
exec spLoadSystemHealthSession @path_to_health_session='D:\XELFiles\system_health*.xel',@UTDDateDiff=-6
Exec spLoadSystemHealthSession
*/
