SET NOCOUNT ON
Use <source database to be cloned>
go

--IF EXISTS(select * from sys.databases where name='db2')
--ALTER DATABASE db2 set single_user with rollback immediate;
--DROP DATABASE db2;

declare @out table(id int identity(1,1),s sysname, o sysname, i sysname, stats_stream varbinary(max), rows bigint, pages bigint)
declare @dbcc table(stats_stream varbinary(max), rows bigint, pages bigint)
declare c cursor for 
       select object_schema_name(object_id) s, object_name(object_id) o, name i
       from sys.indexes 
       where type_desc in ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
declare @s sysname, @o sysname, @i sysname
open c 
fetch next from c into @s, @o, @i
while @@FETCH_STATUS = 0 begin
       declare @showStats nvarchar(max) = N'DBCC SHOW_STATISTICS("' + quotename(@s) + '.' + quotename(@o) + '", ' + quotename(@i) + ') with stats_stream'
       insert @dbcc exec sp_executesql @showStats
       insert @out select @s, @o, @i, stats_stream, rows, pages from @dbcc
       delete @dbcc
       fetch next from c into @s, @o, @i
end
close c
deallocate c


declare @sql nvarchar(max);
declare @id int;

select top 1 @id=id,@sql= 
'UPDATE STATISTICS ' + quotename(s) + '.' + quotename(o)  + '(' + quotename(i) 
+ ') with stats_stream = ' + convert(nvarchar(max), stats_stream, 1) 
+ ', rowcount = ' + convert(nvarchar(max), rows) + ', pagecount = '  + convert(nvarchar(max), pages)
from @out

WHILE (@@ROWCOUNT <> 0)
BEGIN
	exec sp_executesql @sql
	delete @out where id = @id
	select top 1 @id=id,@sql= 
	'UPDATE STATISTICS ' + quotename(s) + '.' + quotename(o)  + '(' + quotename(i) 
	+ ') with stats_stream = ' + convert(nvarchar(max), stats_stream, 1) 
	+ ', rowcount = ' + convert(nvarchar(max), rows) + ', pagecount = '  + convert(nvarchar(max), pages)
	from @out
END
dbcc clonedatabase('source database','target clone database')
