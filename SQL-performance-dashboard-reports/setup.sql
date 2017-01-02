--
-- © 2012 Microsoft.  All Rights Reserved.
--
-- This script installs the stored procedures and functions invoked when a user opens the 
-- Performance Dashboard reports.  This script must be run against each SQL Server instance which
-- you plan to monitor via the reports.
--

-- Script must not be run in a transaction
SET IMPLICIT_TRANSACTIONS OFF
IF @@TRANCOUNT > 0 ROLLBACK TRAN
GO

-- Options that are saved with object definition
SET QUOTED_IDENTIFIER ON		-- Required to call methods on XML type
SET ANSI_NULLS ON				-- All queries use IS NULL check
go

use msdb
go

declare @Version nvarchar(100)
declare @MajorVer tinyint
declare @dec1 int
select @Version = convert(nvarchar(100), serverproperty('ProductVersion'))
select @dec1 = charindex('.', @Version)
select @MajorVer = convert(tinyint, substring(@Version, 1, @dec1 - 1))

if not (@MajorVer >= 10)
begin
	RAISERROR('SETUP FAILED: This server does not meet the requirements (SQL 2008 or later) for running the Performance Dashboard Reports.  This script will terminate and the required procedures will not be installed.', 18, 1)
end
GO

-- Prevent installs against SQL Azure (cross DB query limitation and DMV scoping)
if SERVERPROPERTY('Edition') = N'SQL Azure'
begin
	RAISERROR('SETUP FAILED: SQL Azure is currently not supported by the Performance Dashboard Reports.', 18, 1);

	-- On SQL Azure we can't raise a high enough severity error to abort execution of the script, so this will
	-- unfortunately continue on past this point
end
go


if not exists (select * from sys.schemas where name = 'MS_PerfDashboard')
	exec('create schema MS_PerfDashboard')
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.tblConfigValues'), 'IsUserTable') = 1
	drop table MS_PerfDashboard.tblConfigValues
go

create table MS_PerfDashboard.tblConfigValues
(
	Attribute varchar(60) not null PRIMARY KEY,
	AttribValue sql_variant null
)
go

set nocount on;
go

-- NOTE: ReportVersion attribute must be synchronized with .RDL version
insert into MS_PerfDashboard.tblConfigValues (Attribute, AttribValue) values ('ReportVersion', '2012-01-31');
insert into MS_PerfDashboard.tblConfigValues (Attribute, AttribValue) values ('InstalledDate', GETDATE());
insert into MS_PerfDashboard.tblConfigValues (Attribute, AttribValue) values ('InstalledBy', SUSER_SNAME());
go


if object_id('MS_PerfDashboard.usp_CheckDependencies', 'P') is not null
	drop procedure MS_PerfDashboard.usp_CheckDependencies
go

create procedure MS_PerfDashboard.usp_CheckDependencies
as
begin
	declare @Version nvarchar(100)
	declare @MajorVer tinyint, @MinorVer tinyint, @BuildNum smallint
	declare @dec1 int, @dec2 int, @dec3 int

	select @Version = convert(nvarchar(100), serverproperty('ProductVersion'))
	select @dec1 = charindex('.', @Version)

	select @MajorVer = convert(tinyint, substring(@Version, 1, @dec1 - 1));
	
	select @MajorVer as major_version, 
		NULL as minor_version, 
		NULL as build_number,
		convert(nvarchar(128), SERVERPROPERTY('MachineName')) + 
			CASE WHEN convert(nvarchar(128), SERVERPROPERTY('InstanceName')) IS NOT NULL THEN N'\' + convert(nvarchar(128), SERVERPROPERTY('InstanceName'))
			ELSE N''
			END as ServerInstance,
		@Version as ProductVersion,
		serverproperty('ProductLevel') as ProductLevel,
		serverproperty('Edition') as Edition

	if not (@MajorVer >= 10)
	begin
		RAISERROR('This server does not meet the requirements (SQL 2008 or later) for running the Performance Dashboard Reports.  This server is running version %s', 18, 1, @Version)
	end
end
go
grant execute on MS_PerfDashboard.usp_CheckDependencies to public
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_WaitTypeCategory'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_WaitTypeCategory
go

create function MS_PerfDashboard.fn_WaitTypeCategory(@wait_type nvarchar(60)) 
returns varchar(60)
as
begin
	declare @category nvarchar(60)
	select @category = 
		case 
			when @wait_type = N'SOS_SCHEDULER_YIELD' then N'CPU'
			when @wait_type = N'THREADPOOL' then N'Worker Thread'
			when @wait_type like N'LCK_M_%' then N'Lock'
			when @wait_type like N'LATCH_%' then N'Latch'
			when @wait_type like N'PAGELATCH_%' then N'Buffer Latch'
			when @wait_type like N'PAGEIOLATCH_%' then N'Buffer IO'
			when @wait_type like N'RESOURCE_SEMAPHORE_%' then N'Compilation'
			when @wait_type like N'CLR_%' or @wait_type like N'SQLCLR%' then N'SQL CLR'
			when @wait_type like N'DBMIRROR%' or @wait_type = N'MIRROR_SEND_MESSAGE' then N'Mirroring'
			when @wait_type like N'XACT%' or @wait_type like N'DTC_%' or @wait_type like N'TRAN_MARKLATCH_%' or @wait_type like N'MSQL_XACT_%' or @wait_type = N'TRANSACTION_MUTEX' then N'Transaction'
			when @wait_type like N'SLEEP_%' or @wait_type in(N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'XE_DISPATCHER_WAIT', N'REQUEST_FOR_DEADLOCK_SEARCH', N'SLEEP_TASK', N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE', N'CHECKPOINT_QUEUE', N'XE_TIMER_EVENT') then N'Idle'
			when @wait_type like N'PREEMPTIVE_%' then N'Preemptive'
			when @wait_type like N'BROKER_%' then N'Service Broker'
			when @wait_type in (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'WRITELOG') then N'Tran Log IO'
			when @wait_type in (N'ASYNC_NETWORK_IO', N'NET_WAITFOR_PACKET') then N'Network IO'
			when @wait_type in (N'CXPACKET', N'EXCHANGE') then N'Parallelism'
			when @wait_type in (N'RESOURCE_SEMAPHORE', N'CMEMTHREAD', N'SOS_RESERVEDMEMBLOCKLIST') then N'Memory'
			when @wait_type in (N'WAITFOR', N'WAIT_FOR_RESULTS', N'BROKER_RECEIVE_WAITFOR') then N'User Wait'
			when @wait_type in (N'TRACEWRITE', N'SQLTRACE_LOCK', N'SQLTRACE_FILE_BUFFER', N'SQLTRACE_FILE_WRITE_IO_COMPLETION') then N'Tracing'
			when @wait_type in (N'FT_RESTART_CRAWL', N'FULLTEXT GATHERER', N'MSSEARCH') then N'Full Text Search'
			when @wait_type in (N'ASYNC_IO_COMPLETION', N'IO_COMPLETION', N'BACKUPIO', N'WRITE_COMPLETION') then N'Other Disk IO'
			else N'Other'
		end

	return @category
end
go
GRANT EXECUTE ON MS_PerfDashboard.fn_WaitTypeCategory TO public
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_QueryTextFromHandle'), 'IsTableFunction') = 1
	drop function MS_PerfDashboard.fn_QueryTextFromHandle
go

CREATE function MS_PerfDashboard.fn_QueryTextFromHandle(@handle varbinary(64), @statement_start_offset int, @statement_end_offset int)
RETURNS @query_text TABLE (database_id smallint, object_id int, encrypted bit, query_text nvarchar(max))
begin
	if @handle is not null
	begin
		declare @start int, @end int
		declare @dbid smallint, @objectid int, @encrypted bit
		declare @batch nvarchar(max), @query nvarchar(max)

		-- statement_end_offset is zero prior to beginning query execution (e.g., compilation)
		select 
			@start = isnull(@statement_start_offset, 0), 
			@end = case when @statement_end_offset is null or @statement_end_offset = 0 then -1
						else @statement_end_offset 
					end

		select @dbid = t.dbid, 
			@objectid = t.objectid, 
			@encrypted = t.encrypted, 
			@batch = t.text 
		from sys.dm_exec_sql_text(@handle) as t

		select @query = case 
				when @encrypted = cast(1 as bit) then N'encrypted text' 
				else ltrim(substring(@batch, @start / 2 + 1, case when (@end - @start) / 2 >= 0 then (@end - @start) / 2 else 1000 end))
			end

		-- Found internal queries (e.g., CREATE INDEX) with end offset of original batch that is 
		-- greater than the length of the internal query and thus returns nothing if we don't do this
		if datalength(@query) = 0
		begin
			select @query = @batch
		end

		insert into @query_text (database_id, object_id, encrypted, query_text) 
		values (@dbid, @objectid, @encrypted, @query)
	end

	return
end
go
GRANT SELECT ON MS_PerfDashboard.fn_QueryTextFromHandle TO public
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_hexstrtovarbin'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_hexstrtovarbin
go

create function MS_PerfDashboard.fn_hexstrtovarbin(@input varchar(8000)) 
returns varbinary(8000) 
as 
begin 
	declare @result varbinary(8000)

	if @input is not null
	begin
		declare @i int, @l int 

		select @result = 0x, @l = len(@input) / 2, @i = 2 
	
		while @i <= @l 
		begin 
			set @result = @result + 
			cast(cast(case lower(substring(@input, @i*2-1, 1)) 
				when '0' then 0x00 
				when '1' then 0x10 
				when '2' then 0x20 
				when '3' then 0x30 
				when '4' then 0x40 
				when '5' then 0x50 
				when '6' then 0x60 
				when '7' then 0x70 
				when '8' then 0x80 
				when '9' then 0x90 
				when 'a' then 0xa0 
				when 'b' then 0xb0 
				when 'c' then 0xc0 
				when 'd' then 0xd0 
				when 'e' then 0xe0 
				when 'f' then 0xf0 
				end as tinyint) | 
			cast(case lower(substring(@input, @i*2, 1)) 
				when '0' then 0x00 
				when '1' then 0x01 
				when '2' then 0x02 
				when '3' then 0x03 
				when '4' then 0x04 
				when '5' then 0x05 
				when '6' then 0x06 
				when '7' then 0x07 
				when '8' then 0x08 
				when '9' then 0x09 
				when 'a' then 0x0a 
				when 'b' then 0x0b 
				when 'c' then 0x0c 
				when 'd' then 0x0d 
				when 'e' then 0x0e 
				when 'f' then 0x0f 
				end as tinyint) as binary(1)) 
		set @i = @i + 1 
		end 
	end

	return @result 
end 
go
GRANT EXECUTE ON MS_PerfDashboard.fn_hexstrtovarbin TO public
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_DatediffMilliseconds'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_DatediffMilliseconds
go

create function MS_PerfDashboard.fn_DatediffMilliseconds(@start datetime, @end datetime) 
returns bigint 
as 
begin 
	return (datediff(dd, @start, @end) * cast(86400000 as bigint) + datediff(ms, dateadd(dd, datediff(dd, @start, @end), @start), @end))
end
go


if object_id('MS_PerfDashboard.usp_Main_GetCPUHistory', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Main_GetCPUHistory
go

create procedure MS_PerfDashboard.usp_Main_GetCPUHistory
as
begin
	declare @ms_now bigint
	
	select @ms_now = ms_ticks from sys.dm_os_sys_info;

	select top 15 record_id,
		dateadd(ms, -1 * (@ms_now - [timestamp]), GetDate()) as EventTime, 
		SQLProcessUtilization,
		SystemIdle,
		100 - SystemIdle - SQLProcessUtilization as OtherProcessUtilization
	from (
		select 
			record.value('(./Record/@id)[1]', 'int') as record_id,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') as SystemIdle,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') as SQLProcessUtilization,
			timestamp
		from (
			select timestamp, convert(xml, record) as record 
			from sys.dm_os_ring_buffers 
			where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
			and record like '%<SystemHealth>%') as x
		) as y 
	order by record_id desc
	
end
go
grant execute on MS_PerfDashboard.usp_Main_GetCPUHistory to public
go


if object_id('MS_PerfDashboard.usp_Main_GetMiscInfo', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Main_GetMiscInfo
go

create procedure MS_PerfDashboard.usp_Main_GetMiscInfo
as
begin
	select 
		(select count(*) from sys.traces) as running_traces,
		(select count(*) from sys.databases) as number_of_databases,
		(select count(*) from sys.dm_db_missing_index_group_stats) as missing_index_count,
		(select waiting_tasks_count from sys.dm_os_wait_stats where wait_type = N'SQLCLR_QUANTUM_PUNISHMENT') as clr_quantum_waits,
		(select count(*) from sys.dm_os_ring_buffers where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' and record like N'%<NonYieldSchedBegin>%') as non_yield_count,
		(select cpu_count from sys.dm_os_sys_info) as number_of_cpus,
		(select scheduler_count from sys.dm_os_sys_info) as number_of_schedulers,
		(select COUNT(*) from sys.dm_xe_sessions) as number_of_xevent_sessions,
		(select convert(varchar(30), AttribValue) from MS_PerfDashboard.tblConfigValues where Attribute = 'ReportVersion') as report_script_version
	end
go
grant execute on MS_PerfDashboard.usp_Main_GetMiscInfo to public
go


if object_id('MS_PerfDashboard.usp_Main_GetSessionInfo', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Main_GetSessionInfo
go

create procedure MS_PerfDashboard.usp_Main_GetSessionInfo
as
begin
	select count(*) as num_sessions,
		sum(convert(bigint, s.total_elapsed_time)) as total_elapsed_time,
		sum(convert(bigint, s.cpu_time)) as cpu_time, 
		case when sum(convert(bigint, s.total_elapsed_time)) - sum(convert(bigint, s.cpu_time)) > 0
			then sum(convert(bigint, s.total_elapsed_time)) - sum(convert(bigint, s.cpu_time))
			else 0
		end as wait_time,
		sum(convert(bigint, MS_PerfDashboard.fn_DatediffMilliseconds(login_time, getdate()))) - sum(convert(bigint, s.total_elapsed_time)) as idle_connection_time,
		case when sum(s.logical_reads) > 0 then (sum(s.logical_reads) - isnull(sum(s.reads), 0)) / convert(float, sum(s.logical_reads))
			else NULL
			end as cache_hit_ratio
	from sys.dm_exec_sessions s
	where s.is_user_process = 0x1
end
go
grant execute on MS_PerfDashboard.usp_Main_GetSessionInfo to public
go



if object_id('MS_PerfDashboard.usp_Main_GetRequestInfo', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Main_GetRequestInfo
go

create procedure MS_PerfDashboard.usp_Main_GetRequestInfo
as
begin
	select count(r.request_id) as num_requests,
		sum(convert(bigint, r.total_elapsed_time)) as total_elapsed_time,
		sum(convert(bigint, r.cpu_time)) as cpu_time,
		case when sum(convert(bigint, r.total_elapsed_time)) - sum(convert(bigint, r.cpu_time)) > 0
			then sum(convert(bigint, r.total_elapsed_time)) - sum(convert(bigint, r.cpu_time))
			else 0
		end as wait_time,
		case when sum(r.logical_reads) > 0 then (sum(r.logical_reads) - isnull(sum(r.reads), 0)) / convert(float, sum(r.logical_reads))
			else NULL
			end as cache_hit_ratio
	from sys.dm_exec_requests r
		join sys.dm_exec_sessions s on r.session_id = s.session_id
	where s.is_user_process = 0x1
end
go
grant execute on MS_PerfDashboard.usp_Main_GetRequestInfo to public
go


if object_id('MS_PerfDashboard.usp_Main_GetRequestWaits', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Main_GetRequestWaits
go

create procedure MS_PerfDashboard.usp_Main_GetRequestWaits
as
begin
	SELECT 
		r.session_id, 
		MS_PerfDashboard.fn_WaitTypeCategory(r.wait_type) AS wait_category, 
		r.wait_type, 
		r.wait_time
	FROM sys.dm_exec_requests AS r 
		INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
	WHERE r.wait_type IS NOT NULL  
		AND s.is_user_process = 0x1		-- TODO: parameterize
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_Main_GetRequestWaits TO public
go



if object_id('MS_PerfDashboard.usp_GetPageDetails', 'P') is not null
	drop procedure MS_PerfDashboard.usp_GetPageDetails
go

create procedure MS_PerfDashboard.usp_GetPageDetails @wait_resource varchar(100)
as
begin
	declare @database_id smallint, @file_id smallint, @page_no int
	declare @t TABLE (ParentObject varchar(256), Object varchar(256), Field varchar(256), VALUE sql_variant)

	declare @colon1 int, @colon2 int
	select @colon1 = charindex(':', @wait_resource)
	select @colon2 = charindex(':', @wait_resource, @colon1 + 1)
	select @database_id = substring(@wait_resource, 1, @colon1 - 1)
	select @file_id = substring(@wait_resource, @colon1 + 1, @colon2 - @colon1 - 1)
	select @page_no = substring(@wait_resource, @colon2 + 1, 100)
	
	BEGIN TRY
		insert into @t exec sp_executesql N'dbcc page(@database_id, @file_id, @page_no) with tableresults', N'@database_id smallint, @file_id smallint, @page_no int', @database_id, @file_id, @page_no
	END TRY
	BEGIN CATCH
		--do nothing
	END CATCH
	
	select @database_id as database_id, 
		quotename(db_name(@database_id)) as database_name,
		@file_id as file_id,
		@page_no as page_no,
		convert(int, [Metadata: ObjectId]) as [object_id], 
		quotename(object_schema_name(convert(int, [Metadata: ObjectId]), @database_id)) + N'.' + quotename(object_name(convert(int, [Metadata: ObjectId]), @database_id)) as [object_name],
		convert(smallint, [Metadata: IndexId]) as [index_id],
		convert(int, [m_level]) as page_level,
		case convert(int, [m_type])
			when 1 then N'Data Page'
			when 2 then N'Index Page'
			when 3 then N'Text Mix Page'
			when 4 then N'Text Tree Page'
			when 8 then N'GAM Page'
			when 9 then N'SGAM Page'
			when 10 then N'IAM Page'
			when 11 then N'PFS Page'
			else convert(nvarchar(10), [m_type])	-- other types intentionally omitted
		end as page_type
	from (select * from @t where ParentObject = 'PAGE HEADER:' and 
			Field IN ('Metadata: ObjectId', 'Metadata: IndexId', 'm_objId (AllocUnitId.idObj)', 'm_level', 'm_type')) as x
		pivot (min([VALUE]) for Field in ([Metadata: ObjectId], [Metadata: IndexId], [m_level], [m_type])) as z
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_GetPageDetails TO public
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.usp_GetPlanGuideDetails'), 'IsProcedure') = 1
	drop procedure MS_PerfDashboard.usp_GetPlanGuideDetails
go

create procedure MS_PerfDashboard.usp_GetPlanGuideDetails @database_name nvarchar(128), @plan_guide_name nvarchar(128)
as
begin
	if (LEFT(@database_name, 1) = N'[' and RIGHT(@database_name, 1) = N']')
	begin
		select @database_name = substring(@database_name, 2, len(@database_name) - 2)
	end

	if (LEFT(@plan_guide_name, 1) = N'[' and RIGHT(@plan_guide_name, 1) = N']')
	begin
		select @plan_guide_name = substring(@plan_guide_name, 2, len(@plan_guide_name) - 2)
	end

	if db_id(@database_name) is not null
	begin
		declare @cmd nvarchar(4000)
		select @cmd = N'select * from [' + @database_name + N'].[sys].[plan_guides] where name = @P1'

		exec sp_executesql @cmd, N'@P1 nvarchar(128)', @plan_guide_name
	end
	else
	begin
		-- return empty result set
		select * from [sys].[plan_guides] where 0 = 1
	end
end
go

grant execute on MS_PerfDashboard.usp_GetPlanGuideDetails to public
go




if OBJECTPROPERTY(object_id('MS_PerfDashboard.usp_TransformShowplanXMLToTable'), 'IsProcedure') = 1
	drop procedure MS_PerfDashboard.usp_TransformShowplanXMLToTable
go

CREATE PROCEDURE MS_PerfDashboard.usp_TransformShowplanXMLToTable @plan_handle nvarchar(256), @stmt_start_offset int, @stmt_end_offset int, @fDebug bit = 0x0
AS
BEGIN
	SET NOCOUNT ON

	declare @plan nvarchar(max)
	declare @dbid int, @objid int
	declare @xml_plan xml
	declare @error int

	declare @output TABLE (
		node_id int, 
		parent_node_id int, 
		relevant_xml_text nvarchar(max), 
		stmt_text nvarchar(max), 
		logical_op nvarchar(128), 
		physical_op nvarchar(128), 
		output_list nvarchar(max), 
		avg_row_size float, 
		est_cpu float, 
		est_io float, 
		est_rows float, 
		est_rewinds float, 
		est_rebinds float, 
		est_subtree_cost float,
		warnings nvarchar(max))

	BEGIN TRY
		-- handle may be invalid now, or XML may be too deep to convert
		select @dbid = p.dbid, @objid = p.objectid, @plan = p.query_plan from sys.dm_exec_text_query_plan(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@plan_handle), @stmt_start_offset, @stmt_end_offset) as p
		select @xml_plan = convert(xml, @plan)

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		insert into @output 
		select nd.node_id,
			x.parent_node_id,
			case when @fDebug = 0x1 then 
							case 
								when x.parent_node_id is null then @plan 
								else convert(nvarchar(max), x.plan_node) 
							end
					else NULL
					end as relevant_xml_text,
			nd.stmt_text, 
			nd.logical_op, 
			nd.physical_op, 
			nd.output_list, 
			nd.avg_row_size, 
			nd.est_cpu, 
			nd.est_io, 
			nd.est_rows, 
			nd.est_rewinds, 
			nd.est_rebinds, 
			nd.est_subtree_cost,
			nd.warnings
		from (select 
				splan.row.query('.') as plan_node,
				splan.row.value('../../@NodeId', 'int') as parent_node_id
			from (select @xml_plan as query_plan) as p
				cross apply p.query_plan.nodes('//sp:RelOp') as splan (row)) as x
				outer apply MS_PerfDashboard.fn_ShowplanRowDetails(plan_node) as nd
		order by isnull(parent_node_id, -1) asc

		-- Statements such as WAITFOR, etc may not have a RelOp so just show the statement type if available
		if @@rowcount = 0
		begin
			;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
			insert into @output (stmt_text) select isnull(@xml_plan.value('(//@StatementType)[1]', 'nvarchar(max)'), N'Unknown Statement')
		end
	END TRY
	BEGIN CATCH
		select @error = ERROR_NUMBER()
-- 		select 
-- 			cast(NULL as int) as node_id, 
-- 			cast(NULL as int) as parent_node_id,
-- 			cast(NULL as nvarchar(max)) as relevant_xml_text,
-- 			cast(NULL as nvarchar(max)) as stmt_text,
-- 			cast(NULL as nvarchar(128)) as logical_op,
-- 			cast(NULL as nvarchar(128)) as physical_op,
-- 			cast(NULL as nvarchar(max)) as output_list,
-- 			cast(NULL as float) as avg_row_size,
-- 			cast(NULL as float) as est_cpu,
-- 			cast(NULL as float) as est_io,
-- 			cast(NULL as float) as est_rows,
-- 			cast(NULL as float) as est_rewinds,
-- 			cast(NULL as float) as est_rebinds,
-- 			cast(NULL as float) as est_subtree_cost,
-- 			cast(NULL as nvarchar(max)) as warnings
-- 		where 0 = 1
	END CATCH

	-- This may be an empty set if there was an exception caught above
	SELECT
		node_id,
		parent_node_id, 
		relevant_xml_text, 
		stmt_text, 
		logical_op, 
		physical_op, 
		output_list, 
		avg_row_size, 
		est_cpu, 
		est_io, 
		est_rows, 
		est_rewinds, 
		est_rebinds, 
		est_subtree_cost,
		warnings
	FROM @output
END
go

grant execute on MS_PerfDashboard.usp_TransformShowplanXMLToTable to public
go




/* 
 *
 *	Helper procedures for building showplan output.  These are called, indirectly, by MS_PerfDashboard.usp_TransformShowplanXMLToTable and because
 *	they belong to the same schema we do not need to grant EXECUTE permissions to users.  They are not intended to be called directly as they require
 *	proper context within the showplan XML in order to return meaningful output.
 *
 *
 */
if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildColumnReference'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildColumnReference
go

create function MS_PerfDashboard.fn_ShowplanBuildColumnReference(@node_data xml, @include_alias_or_table bit)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)
	declare @table nvarchar(256), @alias nvarchar(256), @column nvarchar(256)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @alias = @node_data.value('(./sp:ColumnReference/@Alias)[1]', 'nvarchar(256)'),
		@table = @node_data.value('(./sp:ColumnReference/@Table)[1]', 'nvarchar(256)'),
		@column = @node_data.value('(./sp:ColumnReference/@Column)[1]', 'nvarchar(256)')

	select @column = case when left(@column, 1) = N'[' and right(@column, 1) = N']' then @column else quotename(@column) end

	if @include_alias_or_table = 0x1 and coalesce(@alias, @table) is not null
	begin
		select @alias = case when left(@alias, 1) = N'[' and right(@alias, 1) = N']' then @alias else quotename(@alias) end
		select @table = case when left(@table, 1) = N'[' and right(@table, 1) = N']' then @table else quotename(@table) end

		select @output = case 
					when @alias is not null then @alias
					else @table
				end + N'.' + @column
	end
	else
	begin
		select @output = @column
	end

	return @output
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList
go

create function MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList (@node_data xml, @include_alias_or_table bit)
returns nvarchar(max)

as
begin
	declare @output nvarchar(max)

	declare @count int, @ctr int

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'', @ctr = 1, @count = @node_data.value('count(./sp:ColumnReference)', 'int')

	-- iterate over each element in the list
	while @ctr <= @count
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + case when @ctr > 1 then N', ' else N'' end + MS_PerfDashboard.fn_ShowplanBuildColumnReference(@node_data.query('./sp:ColumnReference[position() = sql:variable("@ctr")]'), @include_alias_or_table)

		select @ctr = @ctr + 1
	end

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList
go

create function MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = convert(nvarchar(max), @node_data.query('for $val in /sp:DefinedValue
				return concat(($val/sp:ColumnReference/@Column)[1], "=", ($val/sp:ScalarOperator/@ScalarString)[1], ",")'))

	declare @len int
	select @len = len(@output)
	if (@len > 0)
	begin
		select @output = left(@output, @len - 1)
	end

	return @output
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildOrderBy'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildOrderBy
go

create function MS_PerfDashboard.fn_ShowplanBuildOrderBy (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = convert(nvarchar(max), @node_data.query('for $col in /sp:OrderByColumn
					return concat(if (($col/sp:ColumnReference/@Alias)[1] > "") then concat(($col/sp:ColumnReference/@Alias)[1], ".") else if (($col/sp:ColumnReference/@Table)[1] > "") then concat(($col/sp:ColumnReference/@Table)[1], ".") else "", string(($col/sp:ColumnReference/@Column)[1]), if ($col/@Ascending = 1) then " ASC" else " DESC", ",")'))
	declare @len int
	select @len = len(@output)
	if (@len > 0)
	begin
		select @output = left(@output, @len - 1)
	end

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildRowset'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildRowset
go

create function MS_PerfDashboard.fn_ShowplanBuildRowset (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:Object'))

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildScalarExpression'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildScalarExpression
go

create function MS_PerfDashboard.fn_ShowplanBuildScalarExpression (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	select @output = N''

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @node_data.value('(./sp:ScalarOperator/@ScalarString)[1]', 'nvarchar(max)')

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList
go

create function MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = convert(nvarchar(max), @node_data.query('for $op in ./sp:ScalarOperator
					return concat(string($op/@ScalarString), ",")'))

	declare @len int
	select @len = len(@output)
	if (@len > 0)
	begin
		select @output = left(@output, @len - 1)
	end

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildScanRange'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildScanRange
go

create function MS_PerfDashboard.fn_ShowplanBuildScanRange (@node_data xml, @scan_type nvarchar(30))
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)
	set @output = N''

	declare @count int, @ctr int

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RangeColumns') = 1)
	begin	
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @ctr = 1, @count = @node_data.value('count(./sp:RangeColumns/sp:ColumnReference)', 'int')

		while @ctr <= @count
		begin
			;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
			select @output = @output + 
					case when @ctr > 1 then N' AND ' else '' end + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:RangeColumns/sp:ColumnReference[position() = sql:variable("@ctr")]'), 0x1)
					+ N' ' + 
				case UPPER(@scan_type) 
					when 'BINARY IS' then N'IS'
					when 'EQ' then N'='
					when 'GE' then N'>='
					when 'GT' then N'>'
					when 'IS' then N'IS'
					when 'IS NOT' then N'IS NOT'
					when 'IS NOT NULL' then N'IS NOT NULL'
					when 'IS NULL' then N'IS NULL'
					when 'LE' then N'<='
					when 'LT' then N'<'
					when 'NE' then N'<>'
				end
				 + N' '
				+ MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList(@node_data.query('./sp:RangeExpressions/sp:ScalarOperator[position() = sql:variable("@ctr")]'))

			select @ctr = @ctr + 1
		end
	end
	

	--if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RangeExpressions') = 1)
	--begin
	--	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	--	select @output = @output + N'(RANGE: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList(@node_data.query('./sp:RangeExpressions/*')) + N'))'
	--end

	return @output
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildSeekPredicates'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildSeekPredicates
go

create function MS_PerfDashboard.fn_ShowplanBuildSeekPredicates (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)
	declare @count int, @ctr int

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'', @ctr = 1, @count = @node_data.value('count(./sp:SeekPredicates/sp:SeekPredicate)', 'int')

	-- iterate over each element in the list
	while @ctr <= @count
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + case when @ctr > 1 then N' AND ' else N'' end + MS_PerfDashboard.fn_ShowplanBuildSeekPredicate(@node_data.query('./sp:SeekPredicates/sp:SeekPredicate[position() = sql:variable("@ctr")]/*'))

		select @ctr = @ctr + 1
	end

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildSeekPredicatesNew'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildSeekPredicatesNew
go

CREATE function [MS_PerfDashboard].[fn_ShowplanBuildSeekPredicatesNew] (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)
	declare @count int, @ctr int

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'', @ctr = 1, @count = @node_data.value('count(./sp:SeekPredicates/sp:SeekPredicateNew)', 'int')
	
	-- iterate over each element in the list
	while @ctr <= @count
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + case when @ctr > 1 then N' AND ' else N'' end + MS_PerfDashboard.fn_ShowplanBuildSeekPredicate(@node_data.query('./sp:SeekPredicates/sp:SeekPredicateNew/sp:SeekKeys[position() = sql:variable("@ctr")]/*'))

		select @ctr = @ctr + 1
	end

	return @output
end
go

if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildSeekPredicate'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildSeekPredicate
go

create function MS_PerfDashboard.fn_ShowplanBuildSeekPredicate (@node_data xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)
	set @output = N''

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IsNotNull') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + MS_PerfDashboard.fn_ShowplanBuildColumnReference(@node_data.query('./sp:IsNotNull/sp:ColumnReference'), 0x0) + N' IS NOT NULL'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Prefix') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + MS_PerfDashboard.fn_ShowplanBuildScanRange(@node_data.query('./sp:Prefix/*'), @node_data.value('(./sp:Prefix/@ScanType)[1]', 'nvarchar(100)'))
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:StartRange') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + case when datalength(@output) > 0 then N' AND ' else '' end + MS_PerfDashboard.fn_ShowplanBuildScanRange(@node_data.query('./sp:StartRange/*'), @node_data.value('(./sp:StartRange/@ScanType)[1]', 'nvarchar(100)'))
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:EndRange') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + case when datalength(@output) > 0 then N' AND ' else '' end + MS_PerfDashboard.fn_ShowplanBuildScanRange(@node_data.query('./sp:EndRange/*'), @node_data.value('(./sp:EndRange/@ScanType)[1]', 'nvarchar(100)'))
	end

	return @output
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildObject'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildObject
go

create function MS_PerfDashboard.fn_ShowplanBuildObject (@node_data xml)
returns nvarchar(max)
as
begin
	declare @object nvarchar(max)
	set @object = N''

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Server') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + @node_data.value('(./sp:Object/@Server)[1]', 'nvarchar(128)') + N'.'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Database') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + @node_data.value('(./sp:Object/@Database)[1]', 'nvarchar(128)') + N'.'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Schema') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + @node_data.value('(./sp:Object/@Schema)[1]', 'nvarchar(128)') + N'.'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Table') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + @node_data.value('(./sp:Object/@Table)[1]', 'nvarchar(128)')
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Index') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + N'.' + @node_data.value('(./sp:Object/@Index)[1]', 'nvarchar(128)')
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Object/@Alias') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @object = @object + N' AS ' + @node_data.value('(./sp:Object/@Alias)[1]', 'nvarchar(128)')
	end

	return @object
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanBuildWarnings'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanBuildWarnings
go

create function MS_PerfDashboard.fn_ShowplanBuildWarnings(@relop_node xml)
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	if (@relop_node.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RelOp/sp:Warnings') = 1)
	begin
		if (@relop_node.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RelOp/sp:Warnings[@NoJoinPredicate = 1]') = 1)
		begin
			select @output = N'NO JOIN PREDICATE'
		end
		
		if (@relop_node.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RelOp/sp:Warnings/sp:ColumnsWithNoStatistics') = 1)
		begin
			;with xmlnamespaces ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' as sp)
			select @output = case when @output is null then N'' else @output + N', ' end + N'NO STATS: ' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@relop_node.query('./sp:RelOp/sp:Warnings/sp:ColumnsWithNoStatistics/*'), 0x1)
		end
	end

	return @output
end
go




if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatAssert'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatAssert
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatAssert(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'Assert(' + @node_data.value('(./sp:Assert/sp:Predicate/sp:ScalarOperator/@ScalarString)[1]', 'nvarchar(max)') + N'))'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatBitmap'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatBitmap
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatBitmap(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'Bitmap(Hash Keys:(' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Bitmap/sp:HashKeys/sp:ColumnReference'), 0x1) + N'))'

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatComputeScalar'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatComputeScalar
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatComputeScalar(@node_data xml, @physical_op nvarchar(128))
returns nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @physical_op + N'(DEFINE: (' + MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList(@node_data.query('./sp:DefinedValues/*')) + N'))';

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatConcat'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatConcat
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatConcat(@node_data xml)
RETURNS nvarchar(max)
as
begin
	return N'Concatenation'
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatCollapse'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatCollapse
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatCollapse(@node_data xml)
RETURNS nvarchar(max)
as
begin
	return N'Collapse'
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatIndexScan'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatIndexScan
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatIndexScan(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)	

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @physical_op + N'(OBJECT: (' + MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:IndexScan/sp:Object')) + N')'
	
	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan/sp:SeekPredicates/sp:SeekPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', SEEK: (' + MS_PerfDashboard.fn_ShowplanBuildSeekPredicates(@node_data.query('./sp:IndexScan/sp:SeekPredicates')) + N')'
	end
	else if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan/sp:SeekPredicates/sp:SeekPredicateNew') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', SEEK: (' + MS_PerfDashboard.fn_ShowplanBuildSeekPredicatesNew(@node_data.query('./sp:IndexScan/sp:SeekPredicates')) + N')'
	end


	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan/sp:Predicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', WHERE: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:IndexScan/sp:Predicate/*')) + N')'
	end

	select @output = @output + N')'


	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan[@Lookup = 1]') = 1)
	begin
		select @output = @output + N' LOOKUP'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan[@Ordered = 1]') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N' ORDERED ' + ISNULL(@node_data.value('(./sp:IndexScan/@ScanDirection)[1]', 'nvarchar(128)'), '')
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan[@ForcedIndex = 1]') = 1)
	begin
		select @output = @output + N' FORCEDINDEX'
	end

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatConstantScan'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatConstantScan
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatConstantScan(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Constant Scan'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:ConstantScan/sp:Values') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'(VALUES: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpressionList(@node_data.query('./sp:ConstantScan/sp:Values/sp:Row/*')) + N'))'
	end

	return @output
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatDeletedInsertedScan'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatDeletedInsertedScan
go

-- Passed the Rowset element of XML showplan and extracts the Object details
CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatDeletedInsertedScan(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @physical_op + N'(' + MS_PerfDashboard.fn_ShowplanBuildRowset(@node_data) + N')'

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatFilter'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatFilter
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatFilter(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	declare @fStartup tinyint

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @fStartup = case when (@node_data.exist('./sp:Filter[@StartupExpression = 1]') = 1) then 1 else 0 end

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'Filter(WHERE: (' + 
		case when @fStartup = 1 then N'STARTUP EXPRESSION(' else N'' end + 
		MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Filter/sp:Predicate/*')) +
		case when @fStartup = 1 then N')' else N'' end + 
		N'))'

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatHashMatch'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatHashMatch
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatHashMatch(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Hash Match(' + @logical_op

	if (@logical_op = N'Aggregate')
	begin
		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:HashKeysBuild') = 1)
		begin
			;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
			select @output = @output + N', HASH:(' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Hash/sp:HashKeysBuild/sp:ColumnReference'), 0x1) + N')'
		end
	
		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:BuildResidual') = 1)
		begin
			;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
			select @output = @output + N', RESIDUAL:(' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Hash/sp:BuildResidual/*')) + N')'
		end

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', DEFINE: (' + MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList(@node_data.query('./sp:Hash/sp:DefinedValues/*')) + N')';
	end
	else
	begin
		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:HashKeysBuild') = 1)
		begin
			;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
			select @output = @output + N', HASH:(' + 
				MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Hash/sp:HashKeysBuild/sp:ColumnReference'), 0x1) + 
				N')=(' + 
				MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Hash/sp:HashKeysProbe/sp:ColumnReference'), 0x1) + N')'
		end
	
		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:BuildResidual') = 1) or
			(@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:ProbeResidual') = 1)
		begin
			declare @build_residual bit
	
			select @build_residual = 0x0, @output = @output + N', RESIDUAL:('
	
			if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:BuildResidual') = 1)
			begin
				;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
				select @output = @output + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Hash/sp:BuildResidual/*'))
				select @build_residual = 0x1
			end
	
			if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Hash/sp:ProbeResidual') = 1)
			begin
				;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
				select @output = @output + case when @build_residual = 0x1 then N' AND ' else '' end + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Hash/sp:ProbeResidual/*'))
			end

			select @output = @output + N')'
		end
	end

	select @output = @output + N')'

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatMerge'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatMerge
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatMerge(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'Merge Join(' + @logical_op + case when @node_data.exist('./sp:Merge[@ManyToMany = 1]') = 1 then N', MANY-TO-MANY'
			else N'' end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Merge/sp:InnerSideJoinColumns') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', MERGE: (' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Merge/sp:InnerSideJoinColumns/sp:ColumnReference'), 0x1) + N')=(' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Merge/sp:OuterSideJoinColumns/sp:ColumnReference'), 0x1) + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Merge/sp:Residual') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', RESIDUAL: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Merge/sp:Residual/*')) + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Merge/sp:PassThru') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', PASSTHRU: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Merge/sp:PassThru/*')) + N')'
	end

	select @output = @output + N')'

	return @output;
end
go




if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatNestedLoops'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatNestedLoops
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatNestedLoops(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Nested Loops(' + @logical_op

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops/sp:OuterReferences') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', OUTER REFERENCES:' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:NestedLoops/sp:OuterReferences/sp:ColumnReference'), 0x1)
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops/sp:Predicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', WHERE: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:NestedLoops/sp:Predicate/*')) + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops/sp:PassThru') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', PASSTHRU:(' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:NestedLoops/sp:PassThru/*')) + N')'
	end

	select @output = @output + N')'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops[@Optimized = 1]') = 1)
	begin
		select @output = @output + N' OPTIMIZED'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops[@WithOrderedPrefetch = 1]') = 1)
	begin
		select @output = @output + N' WITH ORDERED PREFETCH'
	end
	else if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:NestedLoops[@WithUnorderedPrefetch = 1]') = 1)
	begin
		select @output = @output + N' WITH UNORDERED PREFETCH'
	end

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatParallelism'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatParallelism
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatParallelism(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	select @output = N'Parallelism(' + @logical_op + N')'
	--TODO: Extend to show partitioning information, order by information	

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatSimpleUpdate'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatSimpleUpdate
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatSimpleUpdate(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @physical_op + N'(' + MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:Object'))

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:SetPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', SET: ' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:SetPredicate/*'))
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:SeekPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', WHERE: (' + MS_PerfDashboard.fn_ShowplanBuildSeekPredicate(@node_data.query('./sp:SeekPredicate/*')) + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatRemoteQuery'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatRemoteQuery
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatRemoteQuery(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Remote Query('

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteQuery/@RemoteSource') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'SOURCE: (' + @node_data.value('(./sp:RemoteQuery/@RemoteSource)[1]', 'nvarchar(256)') + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteQuery/@RemoteObject') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'OBJECT: (' + @node_data.value('(./sp:RemoteQuery/@RemoteObject)[1]', 'nvarchar(256)') + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteQuery/@RemoteQuery') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', QUERY: (' + @node_data.value('(./sp:RemoteQuery/@RemoteQuery)[1]', 'nvarchar(max)') + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatRemoteScan'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatRemoteScan
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatRemoteScan(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Remote Scan('

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteScan/@RemoteSource') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'SOURCE: (' + @node_data.value('(./sp:RemoteScan/@RemoteSource)[1]', 'nvarchar(256)') + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteScan/@RemoteObject') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'OBJECT: (' + @node_data.value('(./sp:RemoteScan/@RemoteObject)[1]', 'nvarchar(256)') + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatRemoteModify'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatRemoteModify
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatRemoteModify(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = @logical_op + N'('

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteModify/@RemoteSource') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'SOURCE: (' + @node_data.value('(./sp:RemoteModify/@RemoteSource)[1]', 'nvarchar(256)') + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteModify/@RemoteObject') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'OBJECT: (' + @node_data.value('(./sp:RemoteModify/@RemoteObject)[1]', 'nvarchar(256)') + N')'
	end


	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:RemoteModify/sp:SetPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'WHERE: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:RemoteModify/sp:SetPredicate/*')) + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatSort'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatSort
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatSort(@node_data xml, @logical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Sort('

	if @logical_op = N'Sort'
	begin
		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Sort[@Distinct = 1]') = 1)
		begin
			select @output = @output + N'DISTINCT '
		end

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'ORDER BY: (' + MS_PerfDashboard.fn_ShowplanBuildOrderBy(@node_data.query('./sp:Sort/sp:OrderBy/sp:OrderByColumn')) + N')'
	end
	else if @logical_op = N'TopN Sort'
	begin
		select @output = @output + N'TOP ' + @node_data.value('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; (./sp:TopSort/@Rows)[1]', 'nvarchar(50)') + N', '

		if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TopSort[@Distinct = 1]') = 1)
		begin
			select @output = @output + N'DISTINCT '
		end

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'ORDER BY: (' + MS_PerfDashboard.fn_ShowplanBuildOrderBy(@node_data.query('./sp:TopSort/sp:OrderBy/sp:OrderByColumn')) + N')'
	end
	else if @logical_op = N'Distinct Sort'
	begin
		select @output = @output + N'DISTINCT '

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'ORDER BY: (' + MS_PerfDashboard.fn_ShowplanBuildOrderBy(@node_data.query('./sp:Sort/sp:OrderBy/sp:OrderByColumn')) + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatSplit'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatSplit
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatSplit(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Split'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Split/sp:ActionColumn') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'(' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Split/sp:ActionColumn/sp:ColumnReference'), 0x1) + N')'
	end

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatStreamAggregate'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatStreamAggregate
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatStreamAggregate(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	declare @need_comma bit

	select @output = N'Stream Aggregate('

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:StreamAggregate/sp:GroupBy') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'GROUP BY: (' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:StreamAggregate/sp:GroupBy/sp:ColumnReference'), 0x1) + N')'
		select @need_comma = 0x1
	end

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @output + 
			case when @need_comma = 0x1 then N', ' else N'' end 
		+ N'DEFINE: (' + MS_PerfDashboard.fn_ShowplanBuildDefinedValuesList(@node_data.query('./sp:StreamAggregate/sp:DefinedValues/sp:DefinedValue')) + N')'

	select @output = @output + N')'

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatSegment'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatSegment
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatSegment(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Segment'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Segment/sp:GroupBy/sp:ColumnReference') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'(GROUP BY: ' + MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@node_data.query('./sp:Segment/sp:GroupBy/sp:ColumnReference'), 0x1) + N')'
	end

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatSpool'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatSpool
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatSpool(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = @physical_op

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Spool/sp:SeekPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'(' + MS_PerfDashboard.fn_ShowplanBuildSeekPredicate(@node_data.query('./sp:Spool/sp:SeekPredicate/*')) + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Spool[@Stack = 1]') = 1)
	begin
		select @output = @output + N' WITH STACK'
	end

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatTableScan'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatTableScan
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatTableScan(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Table Scan('

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @output + MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:TableScan/sp:Object'))

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TableScan/sp:Predicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', WHERE: (' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:TableScan/sp:Predicate/*')) + N')'
	end
	
	select @output = @output + N')'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TableScan[@Ordered = 1]') = 1)
	begin
		select @output = @output + N' ORDERED'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TableScan[@ForcedIndex = 1]') = 1)
	begin
		select @output = @output + N' FORCEDINDEX'
	end


	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatTop'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatTop
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatTop(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Top'

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Top/sp:TopExpression') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'(TOP EXPRESSION: ' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:Top/sp:TopExpression/*')) + N')'
	end

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatTVF'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatTVF
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatTVF(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)
	select @output = N'Table-valued Function('

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TableValuedFunction/sp:Object') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'OBJECT: (' + MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:TableValuedFunction/sp:Object')) + N')'
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:TableValuedFunction/sp:Predicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N', WHERE: ( ' + MS_PerfDashboard.fn_ShowplanBuildPredicate(@node_data.query('./sp:TableValuedFunction/sp:Predicate')) + N')'
	end

	select @output = @output + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatUDX'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatUDX
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatUDX(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = N'UDX(' + @node_data.value('(./sp:Extension/@UDXName)[1]', 'nvarchar(128)') + N')'

	return @output;
end
go


if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatUpdate'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatUpdate
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatUpdate(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @output = @physical_op + N'(' + MS_PerfDashboard.fn_ShowplanBuildObject(@node_data.query('./sp:Object/*'))

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:SetPredicate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + N'SET: ' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:SetPredicate/*'))
	end

	select @output = @output + N')'

	return @output;
end
go

if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatRIDLookup'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatRIDLookup
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatRIDLookup(@node_data xml)
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max) = '';

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:IndexScan') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @output + MS_PerfDashboard.fn_ShowplanFormatIndexScan(@node_data.query('./sp:IndexScan'), 'RID Lookup')
		select @output = @output + N')'
	end

	return @output;
end
go



if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanFormatGenericUpdate'), 'IsScalarFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanFormatGenericUpdate
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanFormatGenericUpdate(@node_data xml, @physical_op nvarchar(128))
RETURNS nvarchar(max)
as
begin
	declare @output nvarchar(max)

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:SimpleUpdate') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = MS_PerfDashboard.fn_ShowplanFormatSimpleUpdate(@node_data.query('./sp:SimpleUpdate/*'), @physical_op)
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:Update') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = MS_PerfDashboard.fn_ShowplanFormatUpdate(@node_data.query('./sp:Update/*'), @physical_op)
	end

	if (@node_data.exist('declare namespace sp="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; ./sp:ScalarInsert') = 1)
	begin
		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @output = @physical_op + '(' + MS_PerfDashboard.fn_ShowplanBuildScalarExpression(@node_data.query('./sp:ScalarInsert/sp:SetPredicate/*')) + ')'
	end

	return @output;
end
go


--
-- Created last since it depends on all the above functions for building/formatting the showplan
--
if OBJECTPROPERTY(object_id('MS_PerfDashboard.fn_ShowplanRowDetails'), 'IsTableFunction') = 1
	drop function MS_PerfDashboard.fn_ShowplanRowDetails
go

CREATE FUNCTION MS_PerfDashboard.fn_ShowplanRowDetails(@relop_node xml)
returns @node TABLE (node_id int, stmt_text nvarchar(max), logical_op nvarchar(128), physical_op nvarchar(128), output_list nvarchar(max), avg_row_size float, est_cpu float, est_io float, est_rows float, est_rewinds float, est_rebinds float, est_subtree_cost float, warnings nvarchar(max))
AS
begin
	declare @node_id int
	declare @output_list nvarchar(max)
	declare @stmt_text nvarchar(max)
	declare @logical_op nvarchar(128), @physical_op nvarchar(128)
	declare @avg_row_size float, @est_cpu float, @est_io float, @est_rows float, @est_rewinds float, @est_rebinds float, @est_subtree_cost float
	declare @relop_children xml

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @logical_op = @relop_node.value('(./sp:RelOp/@LogicalOp)[1]', 'nvarchar(128)'),
		@physical_op = @relop_node.value('(./sp:RelOp/@PhysicalOp)[1]', 'nvarchar(128)'),
		@relop_children = @relop_node.query('./sp:RelOp/*')

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	select @stmt_text =
		case 
			when @physical_op = N'Assert' then MS_PerfDashboard.fn_ShowplanFormatAssert(@relop_children)
			when @physical_op = N'Bitmap' then MS_PerfDashboard.fn_ShowplanFormatBitmap(@relop_children)
			when @physical_op in (N'Clustered Index Delete', N'Clustered Index Insert', N'Clustered Index Update', N'Clustered Index Merge', 
						N'Index Delete', N'Index Insert', N'Index Update', 
						N'Table Delete', N'Table Insert', N'Table Update') then MS_PerfDashboard.fn_ShowplanFormatGenericUpdate(@relop_children, @physical_op)
			when @physical_op in (N'Clustered Index Scan', N'Clustered Index Seek', 
						N'Index Scan', N'Index Seek') then MS_PerfDashboard.fn_ShowplanFormatIndexScan(@relop_children, @physical_op)
--			when @physical_op = N'Clustered Update' then 
			when @physical_op = N'Collapse' then N'Collapse'
			when @physical_op = N'Compute Scalar' then MS_PerfDashboard.fn_ShowplanFormatComputeScalar(@relop_children.query('./sp:ComputeScalar/*'), @physical_op)
			when @physical_op = N'Concatenation' then MS_PerfDashboard.fn_ShowplanFormatConcat(@relop_children)
			when @physical_op = N'Constant Scan' then MS_PerfDashboard.fn_ShowplanFormatConstantScan(@relop_children)
			when @physical_op = N'Deleted Scan' then MS_PerfDashboard.fn_ShowplanFormatDeletedInsertedScan(@relop_children.query('./sp:DeletedScan/*'), @physical_op)
			when @physical_op = N'Filter' then MS_PerfDashboard.fn_ShowplanFormatFilter(@relop_children)
--			when @physical_op = N'Generic' then 
			when @physical_op = N'Hash Match' then MS_PerfDashboard.fn_ShowplanFormatHashMatch(@relop_children, @logical_op)
			when @physical_op = N'Index Spool' then MS_PerfDashboard.fn_ShowplanFormatSpool(@relop_children, @physical_op)
			when @physical_op = N'Inserted Scan' then MS_PerfDashboard.fn_ShowplanFormatDeletedInsertedScan(@relop_children.query('./sp:InsertedScan/*'), @physical_op)
			when @physical_op = N'Log Row Scan' then N'Log Row Scan'
			when @physical_op = N'Merge Interval' then N'Merge Interval'
			when @physical_op = N'Merge Join' then MS_PerfDashboard.fn_ShowplanFormatMerge(@relop_children, @logical_op)
			when @physical_op = N'Nested Loops' then MS_PerfDashboard.fn_ShowplanFormatNestedLoops(@relop_children, @logical_op)
			when @physical_op = N'Online Index Insert' then N'Online Index Insert'
			when @physical_op = N'Parallelism' then MS_PerfDashboard.fn_ShowplanFormatParallelism(@relop_children, @logical_op)
			when @physical_op = N'Parameter Table Scan' then N'Parameter Table Scan'
			when @physical_op = N'Print' then N'Print'
			when @physical_op in (N'Remote Delete', N'Remote Insert', N'Remote Update') then MS_PerfDashboard.fn_ShowplanFormatRemoteModify(@relop_children, @logical_op)
			when @physical_op = N'Remote Scan' then MS_PerfDashboard.fn_ShowplanFormatRemoteScan(@relop_children)
			when @physical_op = N'Remote Query' then MS_PerfDashboard.fn_ShowplanFormatRemoteQuery(@relop_children)
			when @physical_op = N'RID Lookup' then MS_PerfDashboard.fn_ShowplanFormatRIDLookup(@relop_children)
			when @physical_op = N'Row Count Spool' then MS_PerfDashboard.fn_ShowplanFormatSpool(@relop_children, @physical_op)
			when @physical_op = N'Segment' then MS_PerfDashboard.fn_ShowplanFormatSegment(@relop_children)
			when @physical_op = N'Sequence' then N'Sequence'
			when @physical_op = N'Sequence Project' then MS_PerfDashboard.fn_ShowplanFormatComputeScalar(@relop_children.query('./sp:SequenceProject/*'), @physical_op)
			when @physical_op = N'Sort' then MS_PerfDashboard.fn_ShowplanFormatSort(@relop_children, @logical_op)
			when @physical_op = N'Split' then MS_PerfDashboard.fn_ShowplanFormatSplit(@relop_children)
			when @physical_op = N'Stream Aggregate' then MS_PerfDashboard.fn_ShowplanFormatStreamAggregate(@relop_children)
			when @physical_op = N'Switch' then N'Switch'
			when @physical_op = N'Table-valued function' then MS_PerfDashboard.fn_ShowplanFormatTVF(@relop_children)
			when @physical_op = N'Table Scan' then MS_PerfDashboard.fn_ShowplanFormatTableScan(@relop_children)
			when @physical_op = N'Table Spool' then MS_PerfDashboard.fn_ShowplanFormatSpool(@relop_children, @physical_op)
			when @physical_op = N'Table Merge' then N'Table Merge'
			when @physical_op = N'Top' then MS_PerfDashboard.fn_ShowplanFormatTop(@relop_children)
			when @physical_op = N'UDX' then MS_PerfDashboard.fn_ShowplanFormatUDX(@relop_children)
			else @physical_op + N'(' + @logical_op + N')'
		end	

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	insert @node (
		node_id,
		stmt_text, 
		logical_op, 
		physical_op, 
		output_list, 
		avg_row_size, 
		est_cpu, 
		est_io, 
		est_rows, 
		est_rewinds, 
		est_rebinds, 
		est_subtree_cost,
		warnings)
	values (
		@relop_node.value('(./sp:RelOp/@NodeId)[1]', 'int'),
		@stmt_text, 
		@logical_op, 
		@physical_op, 
		MS_PerfDashboard.fn_ShowplanBuildColumnReferenceList(@relop_node.query('./sp:RelOp/sp:OutputList/sp:ColumnReference'), 0x1),
		@relop_node.value('(./sp:RelOp/@AvgRowSize)[1]', 'float'),
		@relop_node.value('(./sp:RelOp/@EstimateCPU)[1]', 'float'),
		@relop_node.value('(./sp:RelOp/@EstimateIO)[1]', 'float'),
		@relop_node.value('(./sp:RelOp/@EstimateRows)[1]', 'float'), 
		@relop_node.value('(./sp:RelOp/@EstimateRewinds)[1]', 'float'), 
		@relop_node.value('(./sp:RelOp/@EstimateRebinds)[1]', 'float'), 
		@relop_node.value('(./sp:RelOp/@EstimatedTotalSubtreeCost)[1]', 'float'),
		MS_PerfDashboard.fn_ShowplanBuildWarnings(@relop_node)
		);

	return;
end
go

if object_id('MS_PerfDashboard.usp_DatabaseOverview', 'P') is not null
	drop procedure MS_PerfDashboard.usp_DatabaseOverview
go
create procedure MS_PerfDashboard.usp_DatabaseOverview
as
begin
	select d.name, d.database_id, d.compatibility_level, d.recovery_model_desc,
		s.[Data File(s) Size (KB)] / 1024.0 as [Data File(s) Size (MB)], 
		s.[Log File(s) Size (KB)] / 1024.0 as [Log File(s) Size (MB)],
		s.[Percent Log Used],
		d.is_auto_create_stats_on,
		d.is_auto_update_stats_on,
		d.is_auto_update_stats_async_on,
		d.is_parameterization_forced,
		d.page_verify_option_desc,
		d.log_reuse_wait_desc
	from sys.databases d
		left join (select * from (select instance_name as database_name, counter_name, cntr_value 
				from sys.dm_os_performance_counters 
				where object_name like '%:Databases%' and counter_name in ('Data File(s) Size (KB)', 'Log File(s) Size (KB)', 'Percent Log Used')
					and instance_name != '_Total') p 
					pivot (min(cntr_value) for counter_name in ([Data File(s) Size (KB)], [Log File(s) Size (KB)], [Percent Log Used])) as q) as s 
		on d.name = s.database_name
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_DatabaseOverview TO public
go


if object_id('MS_PerfDashboard.usp_LargeIOObjects', 'P') is not null
	drop procedure MS_PerfDashboard.usp_LargeIOObjects
go
create procedure MS_PerfDashboard.usp_LargeIOObjects
as
begin
	select db_name(d.database_id) as database_name, 
		quotename(object_schema_name(d.object_id, d.database_id)) + N'.' + quotename(object_name(d.object_id, d.database_id)) as object_name,
		d.database_id,
		d.object_id,
		d.page_io_latch_wait_count,
		d.page_io_latch_wait_in_ms,
		d.range_scans,
		d.index_lookups,
		case when mid.database_id is null then 'N' else 'Y' end as missing_index_identified
	from (select 
				database_id,
				object_id,
				row_number() over (partition by database_id order by sum(page_io_latch_wait_in_ms) desc) as row_number,
				sum(page_io_latch_wait_count) as page_io_latch_wait_count,
				sum(page_io_latch_wait_in_ms) as page_io_latch_wait_in_ms,
				sum(range_scan_count) as range_scans,
				sum(singleton_lookup_count) as index_lookups
			from sys.dm_db_index_operational_stats(NULL, NULL, NULL, NULL)
			where page_io_latch_wait_count > 0
			group by database_id, object_id ) as d
		left join (select distinct database_id, object_id from sys.dm_db_missing_index_details) as mid 
			on mid.database_id = d.database_id and mid.object_id = d.object_id
	where d.row_number <= 20
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_LargeIOObjects TO public
go



if object_id('MS_PerfDashboard.usp_DBFileIO', 'P') is not null
	drop procedure MS_PerfDashboard.usp_DBFileIO
go
create procedure MS_PerfDashboard.usp_DBFileIO
as
begin
	select
		m.database_id,
		db_name(m.database_id) as database_name,
		m.file_id,
		m.name as file_name, 
		m.physical_name, 
		m.type_desc,
		fs.num_of_reads, 
		fs.num_of_bytes_read, 
		fs.io_stall_read_ms, 
		fs.num_of_writes, 
		fs.num_of_bytes_written, 
		fs.io_stall_write_ms
	from sys.dm_io_virtual_file_stats(NULL, NULL) fs
		join sys.master_files m on fs.database_id = m.database_id and fs.file_id = m.file_id
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_DBFileIO TO public
go


if object_id('MS_PerfDashboard.usp_DmOsWaitStats', 'P') is not null
	drop procedure MS_PerfDashboard.usp_DmOsWaitStats
go
create procedure MS_PerfDashboard.usp_DmOsWaitStats
as
begin
	select 
	wait_type, 
	msdb.MS_PerfDashboard.fn_WaitTypeCategory(wait_type) as wait_category,
	waiting_tasks_count as num_waits, 
	wait_time_ms as wait_time,
	max_wait_time_ms
	from sys.dm_os_wait_stats
	where waiting_tasks_count > 0
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_DmOsWaitStats TO public
go


if object_id('MS_PerfDashboard.usp_MissingIndexes', 'P') is not null
	drop procedure MS_PerfDashboard.usp_MissingIndexes
go
create procedure MS_PerfDashboard.usp_MissingIndexes @showplan varchar(max)
as
begin
	WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	SELECT 
	index_node.value('(../@Impact)[1]', 'float') as index_impact,
	index_node.query('concat(
				string((./@Database)[1]), 
				".",
				string((./@Schema)[1]),
				".",
				string((./@Table)[1])
			)') as target_object_name,
	replace(convert(nvarchar(max), index_node.query('for $colgroup in ./sp:ColumnGroup,
				$col in $colgroup/sp:Column
				where $colgroup/@Usage = "EQUALITY"
   				return string($col/@Name)')), '] [', '],[') as equality_columns,
	replace(convert(nvarchar(max), index_node.query('for $colgroup in ./sp:ColumnGroup,
				$col in $colgroup/sp:Column
				where $colgroup/@Usage = "INEQUALITY"
   				return string($col/@Name)')), '] [', '],[') as inequality_columns,
	replace(convert(nvarchar(max), index_node.query('for $colgroup in .//sp:ColumnGroup,
				$col in $colgroup/sp:Column
				where $colgroup/@Usage = "INCLUDE"
   				return string($col/@Name)')), '] [', '],[') as included_columns
	from (select convert(xml, @showplan) as xml_showplan) as t
		outer apply t.xml_showplan.nodes('//sp:MissingIndexes/sp:MissingIndexGroup/sp:MissingIndex') as missing_indexes(index_node)
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_MissingIndexes TO public
go


if object_id('MS_PerfDashboard.usp_QueryText', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryText
go
create procedure MS_PerfDashboard.usp_QueryText @sql_handle varchar(8000), @stmt_start_offset int, @stmt_end_offset int
as
begin
	select * from msdb.MS_PerfDashboard.fn_QueryTextFromHandle(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@sql_handle), @stmt_start_offset, @stmt_end_offset);
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryText TO public
go


if object_id('MS_PerfDashboard.usp_MissingIndexStats', 'P') is not null
	drop procedure MS_PerfDashboard.usp_MissingIndexStats
go
create procedure MS_PerfDashboard.usp_MissingIndexStats @DatabaseID int, @ObjectID int
as
begin
	select d.database_id, d.object_id, d.index_handle, d.equality_columns, d.inequality_columns, d.included_columns, d.statement as fully_qualified_object,
	gs.* 
	from sys.dm_db_missing_index_groups g
		join sys.dm_db_missing_index_group_stats gs on gs.group_handle = g.index_group_handle
		join sys.dm_db_missing_index_details d on g.index_handle = d.index_handle
	where d.database_id = isnull(@DatabaseID , d.database_id) and d.object_id = isnull(@ObjectID, d.object_id)
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_MissingIndexStats TO public
go


if object_id('MS_PerfDashboard.usp_QueryAttributes', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryAttributes
go
create procedure MS_PerfDashboard.usp_QueryAttributes @sql_handle varchar(8000), @stmt_start_offset int, @stmt_end_offset int
as
begin
	select 
		qt.database_id,
		quotename(db_name(qt.database_id)) as database_name,
		qt.object_id,
		quotename(object_schema_name(qt.object_id, qt.database_id)) + N'.' + quotename(object_name(qt.object_id, qt.database_id)) as qualified_object_name,
		qt.encrypted,
		qt.query_text
	from msdb.MS_PerfDashboard.fn_QueryTextFromHandle(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@sql_handle), @stmt_start_offset, @stmt_end_offset) as qt
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryAttributes TO public
go



if object_id('MS_PerfDashboard.usp_ShowplanAttributes', 'P') is not null
	drop procedure MS_PerfDashboard.usp_ShowplanAttributes
go
create procedure MS_PerfDashboard.usp_ShowplanAttributes @plan_handle nvarchar(256), @stmt_start_offset int, @stmt_end_offset int
as
begin
	declare @plan_text nvarchar(max)
	declare @plan_xml xml
	declare @missing_index_count int
	declare @plan_guide_name nvarchar(128)
	declare @warnings_exist bit
	declare @plan_dbid smallint
	declare @plan_dbname nvarchar(128)

	begin try
		select @plan_dbid = convert(smallint, pa.value) from sys.dm_exec_plan_attributes(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@plan_handle)) as pa where pa.attribute = 'dbid'
		select @plan_dbname = quotename(db_name(@plan_dbid))

		--plan_handle may now be invalid, or xml could be > 128 levels deep such that conversion fails
		select @plan_text = p.query_plan from sys.dm_exec_text_query_plan(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@plan_handle), @stmt_start_offset, @stmt_end_offset) as p
		select @plan_xml = convert(xml, @plan_text)

		;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
		select @missing_index_count = @plan_xml.value('count(//sp:MissingIndexes/sp:MissingIndexGroup)', 'int'),
			@plan_guide_name = @plan_xml.value('(//sp:StmtSimple/@PlanGuideName)[1]', 'nvarchar(128)'),
			@warnings_exist = @plan_xml.exist('//sp:Warnings')
			
		-- TODO: warning for optimizer timeout/memory abort: @StatementOptmEarlyAbortReason
	end try
	begin catch
		select @plan_xml = NULL		--something required in catch block, and this does no harm
	end catch

	select 
		@plan_text as query_plan, 
		@plan_dbid as plan_database_id, 
		@plan_dbname as plan_database_name, 
		@missing_index_count as missing_index_count, 
		@plan_guide_name as plan_guide_name, 
		@warnings_exist as warnings_exist
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_ShowplanAttributes TO public
go



if object_id('MS_PerfDashboard.usp_PlanParameters', 'P') is not null
	drop procedure MS_PerfDashboard.usp_PlanParameters
go
create procedure MS_PerfDashboard.usp_PlanParameters @plan_handle nvarchar(256), @stmt_start_offset int, @stmt_end_offset int
as
begin
	declare @plan_xml xml
	begin try
		-- convert may fail due to exceeding 128 depth limit
		select @plan_xml = convert(xml, query_plan) from sys.dm_exec_text_query_plan(msdb.MS_PerfDashboard.fn_hexstrtovarbin(@plan_handle), @stmt_start_offset, @stmt_end_offset)
	end try
	begin catch
		select @plan_xml = NULL
	end catch

	;WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
	SELECT 
		parameter_list.param_node.value('(./@Column)[1]', 'nvarchar(128)') as param_name,
		parameter_list.param_node.value('(./@ParameterCompiledValue)[1]', 'nvarchar(max)') as param_compiled_value
	from (select @plan_xml as xml_showplan) as t
		outer apply t.xml_showplan.nodes('//sp:ParameterList/sp:ColumnReference') as parameter_list (param_node)
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_PlanParameters TO public
go



if object_id('MS_PerfDashboard.usp_QueryStatsTopN', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryStatsTopN
go
create procedure MS_PerfDashboard.usp_QueryStatsTopN @OrderBy_Criteria nvarchar(128)
as
begin
	select 
		query_rank,
		charted_value,
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		statement_start_offset,
		statement_end_offset,
		creation_time,
		last_execution_time,
		execution_count,
		plan_generation_num,
		total_worker_time,
		last_worker_time,
		min_worker_time,
		max_worker_time,
		total_physical_reads,
		last_physical_reads,
		min_physical_reads,
		max_physical_reads,
		total_logical_reads,
		last_logical_reads,
		min_logical_reads,
		max_logical_reads,
		total_logical_writes,
		last_logical_writes,
		min_logical_writes,
		max_logical_writes,
		total_clr_time,
		last_clr_time,
		min_clr_time,
		max_clr_time,
		total_elapsed_time,
		last_elapsed_time,
		min_elapsed_time,
		max_elapsed_time,
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text
	from (select s.*, row_number() over(order by charted_value desc, last_execution_time desc) as query_rank from
			 (select *, 
					CASE @OrderBy_Criteria
						WHEN 'Logical Reads' then total_logical_reads
						WHEN 'Physical Reads' then total_physical_reads
						WHEN 'Logical Writes' then total_logical_writes
						WHEN 'CPU' then total_worker_time / 1000
						WHEN 'Duration' then total_elapsed_time / 1000
						WHEN 'CLR Time' then total_clr_time / 1000
					END as charted_value 
				from sys.dm_exec_query_stats) as s where s.charted_value > 0) as qs
		cross apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) as qt
	where qs.query_rank <= 20     -- return only top 20 entries
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryStatsTopN TO public
go




if object_id('MS_PerfDashboard.usp_QueryStatsTopN1', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryStatsTopN1
go
create procedure MS_PerfDashboard.usp_QueryStatsTopN1 @OrderBy_Criteria nvarchar(128)
as
begin
	SELECT 
	query_text, 
	master.dbo.fn_varbintohexstr(query_hash) query_hash, 
	master.dbo.fn_varbintohexstr(sql_handle) sql_handle,
	statement_start_offset,
	statement_end_offset,
	querycount, 
	queryplanhashcount, 
	execution_count,
	total_elapsed_time,
	min_elapsed_time, 
	max_elapsed_time,
	average_elapsed_time,
	total_CPU_time, 
	min_CPU_time, 
	max_CPU_time, 
	average_CPU_time,
	total_logical_reads, 
	min_logical_reads, 
	max_logical_reads, 
	average_logical_reads,
	total_physical_reads, 
	min_physical_reads, 
	max_physical_reads, 
	average_physical_reads, 
	total_logical_writes, 
	min_logical_writes, 
	max_logical_writes, 
	average_logical_writes,
	total_clr_time, 
	min_clr_time, 
	max_clr_time, 
	average_clr_time,
	max_plan_generation_num,
	earliest_creation_time,
	query_rank,
	charted_value,
	master.dbo.fn_varbintohexstr(plan_handle) as plan_handle
	FROM   (SELECT s.*, 
				   Row_number() OVER(ORDER BY charted_value DESC) AS query_rank 
			FROM   (SELECT CASE @OrderBy_Criteria 
							 WHEN 'Logical Reads' THEN SUM(total_logical_reads) 
							 WHEN 'Physical Reads' THEN SUM(total_physical_reads) 
							 WHEN 'Logical Writes' THEN SUM(total_logical_writes) 
							 WHEN 'CPU' THEN SUM(total_worker_time) / 1000 
							 WHEN 'Duration' THEN SUM(total_elapsed_time) / 1000 
							 WHEN 'CLR Time' THEN SUM(total_clr_time) / 1000 
						   END AS charted_value, 
					   query_hash, 
					   MAX(sql_handle_1)				sql_handle, 
					   MAX(statement_start_offset_1)    statement_start_offset, 
					   MAX(statement_end_offset_1)      statement_end_offset, 
					   COUNT(*)							querycount, 
					   COUNT (DISTINCT query_plan_hash) queryplanhashcount, 
					   MAX(plan_handle_1)			plan_handle,
					   MIN(creation_time)				earliest_creation_time,
                 
					   SUM(execution_count)             execution_count, 
					   SUM(total_elapsed_time)          total_elapsed_time, 
					   min(min_elapsed_time)            min_elapsed_time, 
					   max(max_elapsed_time)            max_elapsed_time,
					   SUM(total_elapsed_time)/SUM(execution_count) average_elapsed_time, 
                       
					   SUM(total_worker_time)           total_CPU_time, 
					   min(min_worker_time)             min_CPU_time, 
					   max(max_worker_time)            max_CPU_time, 
					   SUM(total_worker_time)/SUM(execution_count) average_CPU_time, 

                       SUM(total_logical_reads)         total_logical_reads, 
                       min(min_logical_reads)           min_logical_reads, 
                       max(max_logical_reads)           max_logical_reads, 
                       SUM(total_logical_reads)/SUM(execution_count) average_logical_reads, 
                       
                       SUM(total_physical_reads)        total_physical_reads, 
                       min(min_physical_reads)         min_physical_reads, 
                       max(max_physical_reads)          max_physical_reads, 
                       SUM(total_physical_reads)/SUM(execution_count) average_physical_reads, 
                       
                       SUM(total_logical_writes)        total_logical_writes, 
                 
                       min(min_logical_writes)          min_logical_writes, 
                       max(max_logical_writes)          max_logical_writes, 
                       SUM(total_logical_writes)/SUM(execution_count) average_logical_writes, 
                       
                       SUM(total_clr_time)              total_clr_time, 
                       SUM(total_clr_time)/SUM(execution_count) average_clr_time, 
                       min(min_clr_time)                min_clr_time, 
                       max(max_clr_time)                max_clr_time, 
                       
                       MAX(plan_generation_num)         max_plan_generation_num
                FROM (
					-- Implement my own FIRST aggregate to get consistent values for sql_handle, start/end offsets of 
					-- an arbitrary first row for a given query_hash
                    SELECT 
						CASE when t.rownum = 1 THEN plan_handle ELSE NULL END as plan_handle_1,
						CASE WHEN t.rownum = 1 THEN sql_handle ELSE NULL END AS sql_handle_1, 
						CASE WHEN t.rownum = 1 THEN statement_start_offset ELSE NULL END AS statement_start_offset_1, 
						CASE WHEN t.rownum = 1 THEN statement_end_offset ELSE NULL END AS statement_end_offset_1, 
						* 
					FROM   (SELECT row_number() OVER (PARTITION BY query_hash ORDER BY sql_handle) AS rownum, * 
							FROM   sys.dm_exec_query_stats) AS t) AS t2 
					GROUP  BY query_hash
               ) AS s 
			WHERE  s.charted_value > 0
        ) AS qs
         
	CROSS APPLY msdb.MS_PerfDashboard.fn_QueryTextFromHandle(qs.sql_handle, 
		qs.statement_start_offset, qs.statement_end_offset) AS qt  
	where query_rank <= 20
	order by charted_value desc
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryStatsTopN1 TO public
go



if object_id('MS_PerfDashboard.usp_QueryStatsRecentActivity', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryStatsRecentActivity
go
create procedure MS_PerfDashboard.usp_QueryStatsRecentActivity @WithActivitySince datetime
as
begin
	select 
		query_rank,
		charted_value,
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		statement_start_offset,
		statement_end_offset,
		creation_time,
		last_execution_time,
		execution_count,
		plan_generation_num,
		total_worker_time,
		last_worker_time,
		min_worker_time,
		max_worker_time,
		total_physical_reads,
		last_physical_reads,
		min_physical_reads,
		max_physical_reads,
		total_logical_reads,
		last_logical_reads,
		min_logical_reads,
		max_logical_reads,
		total_logical_writes,
		last_logical_writes,
		min_logical_writes,
		max_logical_writes,
		total_clr_time,
		last_clr_time,
		min_clr_time,
		max_clr_time,
		total_elapsed_time,
		last_elapsed_time,
		min_elapsed_time,
		max_elapsed_time,
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text
	from (select s.*, row_number() over(order by charted_value desc, last_execution_time desc) as query_rank from
			 (select *, total_worker_time as charted_value 
				from sys.dm_exec_query_stats 
				where total_worker_time > 0 and last_execution_time > isnull(@WithActivitySince, cast('1900-01-01' as datetime))) as s) as qs
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) as qt
	where qs.query_rank <= 15     -- return only top 15 entries
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryStatsRecentActivity TO public
go



if object_id('MS_PerfDashboard.usp_SessionRequestActivity', 'P') is not null
	drop procedure MS_PerfDashboard.usp_SessionRequestActivity
go
create procedure MS_PerfDashboard.usp_SessionRequestActivity @WithActivitySince datetime, @IsUserProcess bit
as
begin
	select avg_request_cpu_per_ms * request_ms_in_window as request_recent_cpu_est,
		avg_session_cpu_per_ms * session_ms_in_window as session_recent_cpu_est,
		d.*
	from (select s.session_id,
		r.request_id,
		s.login_time,
	--	s.host_name,
		s.program_name,
		s.login_name,
		s.status as session_status,
		s.last_request_start_time,
		s.last_request_end_time,
		s.cpu_time as session_cpu_time,
		r.cpu_time as request_cpu_time,
	--	s.logical_reads as session_logical_reads,
	--	r.logical_reads as request_logical_reads,
		r.start_time as request_start_time,
		r.status as request_status,
		r.command,
		master.dbo.fn_varbintohexstr(r.sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(r.plan_handle) as plan_handle,
		r.statement_start_offset,
		r.statement_end_offset,
		case when r.start_time > getdate() then convert(float, r.cpu_time) / msdb.MS_PerfDashboard.fn_DatediffMilliseconds(r.start_time, getdate()) else convert(float, 1.0) end as avg_request_cpu_per_ms,
		isnull(msdb.MS_PerfDashboard.fn_DatediffMilliseconds(case when r.start_time < @WithActivitySince then @WithActivitySince else r.start_time end, getdate()), 0) as request_ms_in_window,
		case when s.login_time > getdate() then convert(float, s.cpu_time) / (msdb.MS_PerfDashboard.fn_DatediffMilliseconds(s.login_time, getdate())) else convert(float, 1.0) end as avg_session_cpu_per_ms,
		isnull(msdb.MS_PerfDashboard.fn_DatediffMilliseconds(case when s.login_time < @WithActivitySince then @WithActivitySince else s.login_time end, case when r.request_id is null then s.last_request_end_time else getdate() end), 0) as session_ms_in_window
	from sys.dm_exec_sessions s
		left join sys.dm_exec_requests as r on s.session_id = r.session_id
	where (s.last_request_end_time > @WithActivitySince or r.request_id is not null) and (s.is_user_process = @IsUserProcess or s.is_user_process=1)) as d
	where (avg_request_cpu_per_ms * request_ms_in_window) + (avg_session_cpu_per_ms * session_ms_in_window) > 1000.0
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_SessionRequestActivity TO public
go



if object_id('MS_PerfDashboard.usp_RequestDetails', 'P') is not null
	drop procedure MS_PerfDashboard.usp_RequestDetails
go
create procedure MS_PerfDashboard.usp_RequestDetails @include_system_processes bit
as
begin
	SELECT master.dbo.fn_varbintohexstr(sql_handle) AS sql_handle,  
		master.dbo.fn_varbintohexstr(plan_handle) AS plan_handle, 
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		r.session_id,
		r.request_id,
		r.start_time,
		r.status,
		r.statement_start_offset,
		r.statement_end_offset,
		r.database_id,
		r.blocking_session_id,
		r.wait_type,
		r.wait_time,
		r.wait_resource,
		r.last_wait_type,
		r.open_transaction_count,
		r.open_resultset_count,
		r.transaction_id,
		r.cpu_time,
		r.total_elapsed_time,
		r.scheduler_id,
		r.reads,
		r.writes,
		r.logical_reads,
		r.transaction_isolation_level,
		r.granted_query_memory,
		r.executing_managed_code
	FROM sys.dm_exec_requests AS r
		JOIN sys.dm_exec_sessions s on r.session_id = s.session_id
		outer APPLY msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) as qt
	WHERE s.is_user_process = CASE when @include_system_processes > 0 THEN s.is_user_process ELSE 1 END
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_RequestDetails TO public
go



if object_id('MS_PerfDashboard.usp_SessionData', 'P') is not null
	drop procedure MS_PerfDashboard.usp_SessionData
go
create procedure MS_PerfDashboard.usp_SessionData @session_id int
as
begin
	SELECT session_id, login_time, host_name, program_name, login_name, nt_domain, 
						  nt_user_name, status, cpu_time, memory_usage, total_scheduled_time, total_elapsed_time, last_request_start_time, 
						  last_request_end_time, reads, writes, logical_reads, is_user_process, text_size, language, date_format, date_first, quoted_identifier, arithabort, 
						  ansi_null_dflt_on, ansi_defaults, ansi_warnings, ansi_padding, ansi_nulls, concat_null_yields_null, transaction_isolation_level, lock_timeout, 
						  deadlock_priority, row_count, prev_error
	FROM sys.dm_exec_sessions
	WHERE session_id = @session_id
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_SessionData TO public
go



if object_id('MS_PerfDashboard.usp_SessionRequests', 'P') is not null
	drop procedure MS_PerfDashboard.usp_SessionRequests
go
create procedure MS_PerfDashboard.usp_SessionRequests @session_id int
as
begin
	select request_id, 
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		statement_start_offset, 
		statement_end_offset,
		qt.query_text,
		start_time,
		status,
		command,
		r.database_id,
		blocking_session_id,
		wait_type,
		wait_time,
		wait_resource,
		cpu_time,
		total_elapsed_time,
		open_transaction_count,
		transaction_id,
		logical_reads,
		reads,
		writes
	from sys.dm_exec_requests r
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) as qt
	where session_id = @session_id
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_SessionRequests   TO public
go




if object_id('MS_PerfDashboard.usp_LastBatchForIdleSession', 'P') is not null
	drop procedure MS_PerfDashboard.usp_LastBatchForIdleSession
go
create procedure MS_PerfDashboard.usp_LastBatchForIdleSession @session_id int
as
begin
	if not exists (select * from sys.dm_exec_requests where session_id = @session_id)
	begin
		select t.dbid, db_name(t.dbid) as database_name, t.objectid, object_name(t.dbid, t.objectid) as object_name, 
		case when t.encrypted = 0 then t.text else N'encrypted' end as last_query 
		from sys.dm_exec_connections c
			cross apply sys.dm_exec_sql_text(c.most_recent_sql_handle) as t
		where c.most_recent_session_id = @session_id
	end
	else
	begin
		select cast(NULL as smallint), cast (NULL as sysname), cast(NULL as int), cast(NULL as sysname), cast(NULL as nvarchar(max)) where 0 = 1
	end
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_LastBatchForIdleSession  TO public
go



if object_id('MS_PerfDashboard.usp_SessionDetails', 'P') is not null
	drop procedure MS_PerfDashboard.usp_SessionDetails
go
create procedure MS_PerfDashboard.usp_SessionDetails @include_system_processes bit
as
begin
	select session_id,
		login_name,
		host_name,
		program_name,
		nt_domain,
		nt_user_name,
		status,
		cpu_time,
		memory_usage,
		last_request_start_time,
		last_request_end_time,
		logical_reads,
		reads,
		writes,
		is_user_process
	from sys.dm_exec_sessions s
	WHERE s.is_user_process = CASE when @include_system_processes > 0 THEN s.is_user_process ELSE 1 END
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_SessionDetails TO public
go



if object_id('MS_PerfDashboard.usp_TraceEventColumns', 'P') is not null
	drop procedure MS_PerfDashboard.usp_TraceEventColumns
go
create procedure MS_PerfDashboard.usp_TraceEventColumns
as
begin
	select trace_id,
		status,
		case when row_number = 1 then path else NULL end as path,
		case when row_number = 1 then max_size else NULL end as max_size,
		case when row_number = 1 then start_time else NULL end as start_time,
		case when row_number = 1 then stop_time else NULL end as stop_time,
		max_files, 
		is_rowset, 
		is_rollover,
		is_shutdown,
		is_default,
		buffer_count,
		buffer_size,
		last_event_time,
		event_count,
		trace_event_id, 
		trace_event_name, 
		trace_column_id,
		trace_column_name,
		expensive_event	
	from 
		(SELECT t.id AS trace_id, 
			row_number() over (partition by t.id order by te.trace_event_id, tc.trace_column_id) as row_number, 
			t.status, 
			t.path, 
			t.max_size, 
			t.start_time,
			t.stop_time, 
			t.max_files, 
			t.is_rowset, 
			t.is_rollover,
			t.is_shutdown,
			t.is_default,
			t.buffer_count,
			t.buffer_size,
			t.last_event_time,
			t.event_count,
			te.trace_event_id, 
			te.name AS trace_event_name, 
			tc.trace_column_id,
			tc.name AS trace_column_name,
			case when te.trace_event_id in (23, 24, 40, 41, 44, 45, 51, 52, 54, 68, 96, 97, 98, 113, 114, 122, 146, 180) then cast(1 as bit) else cast(0 as bit) end as expensive_event
		FROM sys.traces t 
			CROSS apply ::fn_trace_geteventinfo(t .id) AS e 
			JOIN sys.trace_events te ON te.trace_event_id = e.eventid 
			JOIN sys.trace_columns tc ON e.columnid = trace_column_id) as x
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_TraceEventColumns TO public
go



if object_id('MS_PerfDashboard.usp_Blocking', 'P') is not null
	drop procedure MS_PerfDashboard.usp_Blocking
go
create procedure MS_PerfDashboard.usp_Blocking
as
begin
	with blocking_hierarchy (head_wait_resource, session_id, blocking_session_id, tree_level, request_id, transaction_id, 
		status, sql_handle, plan_handle, statement_start_offset, statement_end_offset, wait_type, wait_time, wait_resource, 
		program_name, seconds_active_idle, open_transaction_count, transaction_isolation_level) 
	as 
	(
		select 
			(select min(wait_resource) from sys.dm_exec_requests where blocking_session_id = s.session_id) as head_wait_resource, 
			s.session_id, 
			convert(smallint, NULL), 
			convert(int, 0), 
			r.request_id, 
			coalesce(r.transaction_id, st.transaction_id), 
			isnull(r.status, 'idle'), 
			r.sql_handle, 
			r.plan_handle, 
			r.statement_start_offset, 
			r.statement_end_offset, 
			r.wait_type, 
			r.wait_time, 
			r.wait_resource, 
			s.program_name,
			case when r.request_id is null then datediff(ss, s.last_request_end_time, getdate()) else datediff(ss, r.start_time, getdate()) end,
			convert(int, p.open_tran),
			coalesce(r.transaction_isolation_level, s.transaction_isolation_level)
		from sys.dm_exec_sessions s
			join sys.sysprocesses p on s.session_id = p.spid
			left join sys.dm_exec_requests r on s.session_id = r.session_id
			left join sys.dm_tran_session_transactions st on s.session_id = st.session_id
		where s.session_id in (select blocking_session_id from sys.dm_exec_requests) 
			and isnull(r.blocking_session_id, 0) = 0

		union all

		select b.head_wait_resource, 
			r.session_id, 
			r.blocking_session_id, 
			tree_level + 1, 
			r.request_id, 
			r.transaction_id, 
			r.status, 
			r.sql_handle, 
			r.plan_handle, 
			r.statement_start_offset, 
			r.statement_end_offset, 
			r.wait_type, 
			r.wait_time, 
			r.wait_resource, 
			NULL,
			NULL,
			r.open_transaction_count,
			r.transaction_isolation_level
		from sys.dm_exec_requests r
			join blocking_hierarchy b on r.blocking_session_id = b.session_id
	)
	select b.head_wait_resource,
		b.session_id, 
		b.request_id, 
		b.blocking_session_id, 
		b.program_name, 
		b.tree_level, 
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		master.dbo.fn_varbintohexstr(b.sql_handle) as sql_handle, 
		master.dbo.fn_varbintohexstr(b.plan_handle) as plan_handle, 
		b.statement_start_offset, 
		b.statement_end_offset, 
		b.status as session_or_request_status, 
		b.wait_type, 
		b.wait_time, 
		b.wait_resource, 
		b.transaction_id, 
		b.transaction_isolation_level,
		b.open_transaction_count,
		b.seconds_active_idle,
		t.name as transaction_name, 
		t.transaction_begin_time, 
		t.transaction_type, 
		t.transaction_state, 
		t.dtc_state, 
		t.dtc_isolation_level,
		st.enlist_count, 
		st.is_user_transaction, 
		st.is_local, 
		st.is_enlisted, 
		st.is_bound
	from blocking_hierarchy b
		left join sys.dm_tran_session_transactions st on st.transaction_id = b.transaction_id and st.session_id = b.session_id
		left join sys.dm_tran_active_transactions t on t.transaction_id = b.transaction_id
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(b.sql_handle, b.statement_start_offset, b.statement_end_offset) as qt
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_Blocking TO public
go


if object_id('MS_PerfDashboard.usp_RequestIoWaits', 'P') is not null
	drop procedure MS_PerfDashboard.usp_RequestIoWaits
go
create procedure MS_PerfDashboard.usp_RequestIoWaits @wait_type nvarchar(128)
as
begin
	select 
		session_id, 
		request_id, 
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		statement_start_offset, 
		statement_end_offset, 
		wait_type, 
		wait_time, 
		wait_resource,
		blocking_session_id
	from sys.dm_exec_requests r
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) as qt
	where msdb.MS_PerfDashboard.fn_WaitTypeCategory(wait_type) = @wait_type --N'Buffer IO'/N'Buffer Latch'
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_RequestIoWaits TO public
go



if object_id('MS_PerfDashboard.usp_LargestIoRequests', 'P') is not null
	drop procedure MS_PerfDashboard.usp_LargestIoRequests
go
create procedure MS_PerfDashboard.usp_LargestIoRequests
as
begin
	select top 20 
		r.session_id,
		r.request_id, 
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		r.statement_start_offset, 
		r.statement_end_offset, 
		r.logical_reads,
		r.reads,
		r.writes,
		r.wait_type, 
		r.wait_time, 
		r.wait_resource,
		r.blocking_session_id,
		case when r.logical_reads > 0 then (r.logical_reads - isnull(r.reads, 0)) / convert(float, r.logical_reads)
			else NULL
			end as cache_hit_ratio
	from sys.dm_exec_requests r
		join sys.dm_exec_sessions s on r.session_id = s.session_id
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(r.sql_handle, r.statement_start_offset, r.statement_end_offset) as qt
	where s.is_user_process = 0x1 and (r.reads > 0 or r.writes > 0)
	order by (r.reads + r.writes) desc
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_LargestIoRequests TO public
go





if object_id('MS_PerfDashboard.usp_RequestWaits', 'P') is not null
	drop procedure MS_PerfDashboard.usp_RequestWaits
go
create procedure MS_PerfDashboard.usp_RequestWaits
as
begin
	select r.session_id, 
		r.request_id, 
		master.dbo.fn_varbintohexstr(r.sql_handle) as sql_handle, 
		master.dbo.fn_varbintohexstr(r.plan_handle) as plan_handle, 
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		r.statement_start_offset,
		r.statement_end_offset,
		r.wait_time, 
		r.wait_type, 
		r.wait_resource,
		msdb.MS_PerfDashboard.fn_WaitTypeCategory(wait_type) as wait_category
	from sys.dm_exec_requests r
		join sys.dm_exec_sessions s on r.session_id = s.session_id
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(r.sql_handle, r.statement_start_offset, r.statement_end_offset) as qt
	where r.wait_type is not null and s.is_user_process = 0x1
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_RequestWaits TO public
go



if object_id('MS_PerfDashboard.usp_LatchStats', 'P') is not null
	drop procedure MS_PerfDashboard.usp_LatchStats
go
create procedure MS_PerfDashboard.usp_LatchStats
as
begin
	select 
		latch_class,
		waiting_requests_count,
		wait_time_ms,
		max_wait_time_ms
	from sys.dm_os_latch_stats
	where waiting_requests_count > 0
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_LatchStats TO public
go



if object_id('MS_PerfDashboard.usp_RequestsWithLatchWaits', 'P') is not null
	drop procedure MS_PerfDashboard.usp_RequestsWithLatchWaits
go
create procedure MS_PerfDashboard.usp_RequestsWithLatchWaits
as
begin
	select 
		r.session_id, 
		r.request_id, 
		master.dbo.fn_varbintohexstr(r.sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(r.plan_handle) as plan_handle,
		case when LEN(qt.query_text) < 2048 then qt.query_text else LEFT(qt.query_text, 2048) + N'...' end as query_text,
		r.statement_start_offset, 
		r.statement_end_offset, 
		r.wait_type, 
		r.wait_time, 
		r.wait_resource
	from sys.dm_exec_requests r
		outer apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(r.sql_handle, r.statement_start_offset, r.statement_end_offset) as qt
	where msdb.MS_PerfDashboard.fn_WaitTypeCategory(wait_type) = 'Latch'
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_RequestsWithLatchWaits TO public
go



if object_id('MS_PerfDashboard.usp_XEventSessions', 'P') is not null
	drop procedure MS_PerfDashboard.usp_XEventSessions
go
create procedure MS_PerfDashboard.usp_XEventSessions
as
begin
	select convert(bigint, address) xeaddress,
		case when row_num = 1 then session_name else NULL end as session_name,
		case when row_num = 1 then create_time else NULL end as create_time,
		case when row_num = 1 then target_name else NULL end as target_name,
		case when row_num = 1 then execution_count else NULL end as execution_count,
		case when row_num = 1 then execution_duration_ms else NULL end as execution_duration_ms,
		case when row_num = 1 then dropped_event_count else NULL end as dropped_event_count,
		case when row_num = 1 then buffer_policy_desc else NULL end as buffer_policy_desc,
		case when row_num = 1 then total_buffer_size else NULL end as total_buffer_size,
		event_name,
		action_name
		

	from (
		select s.address, ROW_NUMBER() over (partition by s.address order by sea.event_name, sea.action_name ) as row_num,
		s.name session_name ,s.create_time, st.target_name, st.execution_count, st.execution_duration_ms, 
		sea.action_name, sea.event_name, s.dropped_event_count, s.total_buffer_size, s.buffer_policy_desc
		from sys.dm_xe_sessions s 
		inner join sys.dm_xe_session_targets st
		  on s.address = st.event_session_address
		inner join sys.dm_xe_session_event_actions sea
		  on s.address = sea.event_session_address ) as inner_t
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_XEventSessions TO public
go



if object_id('MS_PerfDashboard.usp_QueryStatsDetails ', 'P') is not null
	drop procedure MS_PerfDashboard.usp_QueryStatsDetails 
go
create procedure MS_PerfDashboard.usp_QueryStatsDetails @query_hash varchar(64), @OrderBy_Criteria nvarchar(128)
as
begin
	select TOP 50
		db_name(qt.database_id) as database_name,
		qt.query_text,
		qt.encrypted,
		creation_time,
		last_execution_time,
		execution_count,
		plan_generation_num,
		total_worker_time,
		last_worker_time,
		min_worker_time,
		max_worker_time,
		total_physical_reads,
		last_physical_reads,
		min_physical_reads,
		max_physical_reads,
		total_logical_reads,
		last_logical_reads,
		min_logical_reads,
		max_logical_reads,
		total_logical_writes,
		last_logical_writes,
		min_logical_writes,
		max_logical_writes,
		total_clr_time,
		last_clr_time,
		min_clr_time,
		max_clr_time,
		total_elapsed_time,
		last_elapsed_time,
		min_elapsed_time,
		max_elapsed_time,
		master.dbo.fn_varbintohexstr(sql_handle) as sql_handle,
		master.dbo.fn_varbintohexstr(plan_handle) as plan_handle,
		statement_start_offset,
		statement_end_offset,
		CASE @OrderBy_Criteria 
							 WHEN 'Logical Reads' THEN total_logical_reads
							 WHEN 'Physical Reads' THEN total_physical_reads
							 WHEN 'Logical Writes' THEN total_logical_writes
							 WHEN 'CPU' THEN total_worker_time / 1000 
							 WHEN 'Duration' THEN total_elapsed_time / 1000 
							 WHEN 'CLR Time' THEN total_clr_time/ 1000 
			END as sort_value
	from sys.dm_exec_query_stats qs
	 cross apply msdb.MS_PerfDashboard.fn_QueryTextFromHandle(sql_handle, statement_start_offset, statement_end_offset) qt
	where query_hash = MS_PerfDashboard.fn_hexstrtovarbin(@query_hash)
	order by sort_value desc
end
go
GRANT EXECUTE ON MS_PerfDashboard.usp_QueryStatsDetails TO public
go

PRINT 'Script completed!';
go