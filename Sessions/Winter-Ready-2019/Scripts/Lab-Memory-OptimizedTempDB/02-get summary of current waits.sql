-- Get aggregated information about waits happening now
select wait_type, resource_description, 
count(*) as waiting_tasks, avg(wait_duration_ms) as waiting_time 
from sys.dm_os_waiting_tasks
where resource_description is not null
group by wait_type, resource_description 
order by 3 desc
go
