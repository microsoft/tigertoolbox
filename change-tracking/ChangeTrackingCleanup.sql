
-- Loop to invoke manual cleanup procedure for cleaning up change tracking tables in a database

-- Fetch the tables enabled for Change Tracking
select identity(int, 1,1) as TableID, (SCHEMA_NAME(tbl.Schema_ID) +'.'+ object_name(ctt.object_id)) as TableName
into #CT_Tables
from sys.change_tracking_tables  ctt
INNER JOIN sys.tables tbl
ON tbl.object_id = ctt.object_id

-- Set up the variables
declare @start int = 1, @end int = (select count(*) from #CT_Tables), @tablename varchar(255)
while (@start <= @end)
begin	
	-- Fetch the table to be cleaned up
	select @tablename = TableName from #CT_Tables where TableID = @start
	-- Execute the manual cleanup stored procedure
	exec sp_flush_CT_internal_table_on_demand @tablename 
	-- Increment the counter
	set @start = @start + 1
end
drop table #CT_Tables
