use wideworldimporters
go
dbcc dropcleanbuffers
go
exec dbo.report 7
go
select * from sys.query_store_wait_stats
go
select * from sys.query_store_runtime_stats
go
-- Show me which queries waited on PAGEIOLATCH and how much average wait time
-- was on the latch vs overal duration
select qt.query_sql_text, qrs.avg_duration, qws.avg_query_wait_time_ms
from sys.query_store_query_text qt
join sys.query_store_query qq
on qt.query_text_id = qq.query_text_id
join sys.query_store_plan qsp
on qsp.query_id = qq.query_id
join sys.query_store_runtime_stats qrs
on qrs.plan_id = qsp.plan_id
join sys.query_store_wait_stats qws
on qws.plan_id = qsp.plan_id
and qws.wait_category = 6
go
select wait_category_desc, count(*), avg(avg_query_wait_time_ms) avg_wait_time_ms
from sys.query_store_wait_stats
group by wait_category_desc
go