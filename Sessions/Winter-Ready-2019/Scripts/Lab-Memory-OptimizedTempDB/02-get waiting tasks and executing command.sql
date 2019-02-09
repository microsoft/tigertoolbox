-- Get a quick view : status of requests and waits
SELECT 
er.session_id, er.status, er.wait_type, er.wait_resource, er.blocking_session_id,er.command, 
    SUBSTRING(st.text, (er.statement_start_offset/2)+1,   
        ((CASE er.statement_end_offset  
          WHEN -1 THEN DATALENGTH(st.text)  
         ELSE er.statement_end_offset  
         END - er.statement_start_offset)/2) + 1) AS statement_text,
er.last_wait_type
FROM sys.dm_exec_requests AS er
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS st 
WHERE er.wait_type IS NOT NULL 
--OR er.last_wait_type IS NOT NULL
ORDER BY wait_resource ASC