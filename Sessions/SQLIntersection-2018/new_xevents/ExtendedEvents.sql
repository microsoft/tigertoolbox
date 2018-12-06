-- LWP related extended events Demo

CREATE EVENT SESSION [PerfStats_Node] ON SERVER
ADD EVENT sqlserver.query_thread_profile(
ACTION(sqlos.scheduler_id,sqlserver.database_id,sqlserver.is_system,sqlserver.plan_handle,sqlserver.query_hash_signed,sqlserver.query_plan_hash_signed,sqlserver.server_instance_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.sql_text))
--ADD TARGET package0.ring_buffer(SET max_memory=(25600))
ADD TARGET package0.event_file(SET filename=N'C:\IP\Tiger\SQL Intersection\SQL Intersection Winter 2018\Gems to Help You Troubleshoot Query Performance\new_xevents\PerfStats_Node.xel',max_file_size=(50),max_rollover_files=(2))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

USE AdventureWorks2016CTP3
GO

DROP EVENT SESSION [PerfStats_Node] ON SERVER 
GO
ALTER EVENT SESSION [PerfStats_Node] ON SERVER STATE = start;  
GO  

-- Execute plan with many nodes
SELECT e.[BusinessEntityID], 
       p.[Title], 
       p.[FirstName], 
       p.[MiddleName], 
       p.[LastName], 
       p.[Suffix], 
       e.[JobTitle], 
       pp.[PhoneNumber], 
       pnt.[Name] AS [PhoneNumberType], 
       ea.[EmailAddress], 
       p.[EmailPromotion], 
       a.[AddressLine1], 
       a.[AddressLine2], 
       a.[City], 
       sp.[Name] AS [StateProvinceName], 
       a.[PostalCode], 
       cr.[Name] AS [CountryRegionName], 
       p.[AdditionalContactInfo] 
FROM   [HumanResources].[Employee] AS e 
       INNER JOIN [Person].[Person] AS p 
       ON RTRIM(LTRIM(p.[BusinessEntityID])) = RTRIM(LTRIM(e.[BusinessEntityID])) 
       INNER JOIN [Person].[BusinessEntityAddress] AS bea 
       ON RTRIM(LTRIM(bea.[BusinessEntityID])) = RTRIM(LTRIM(e.[BusinessEntityID])) 
       INNER JOIN [Person].[Address] AS a 
       ON RTRIM(LTRIM(a.[AddressID])) = RTRIM(LTRIM(bea.[AddressID])) 
       INNER JOIN [Person].[StateProvince] AS sp 
       ON RTRIM(LTRIM(sp.[StateProvinceID])) = RTRIM(LTRIM(a.[StateProvinceID])) 
       INNER JOIN [Person].[CountryRegion] AS cr 
       ON RTRIM(LTRIM(cr.[CountryRegionCode])) = RTRIM(LTRIM(sp.[CountryRegionCode])) 
       LEFT OUTER JOIN [Person].[PersonPhone] AS pp 
       ON RTRIM(LTRIM(pp.BusinessEntityID)) = RTRIM(LTRIM(p.[BusinessEntityID])) 
       LEFT OUTER JOIN [Person].[PhoneNumberType] AS pnt 
       ON RTRIM(LTRIM(pp.[PhoneNumberTypeID])) = RTRIM(LTRIM(pnt.[PhoneNumberTypeID])) 
       LEFT OUTER JOIN [Person].[EmailAddress] AS ea 
       ON RTRIM(LTRIM(p.[BusinessEntityID])) = RTRIM(LTRIM(ea.[BusinessEntityID]))
GO

ALTER EVENT SESSION [PerfStats_Node] ON SERVER STATE = stop;  
GO 

-- Choose any event and let's open the associated cached plan.
-- I want to see which operator this one is, and where in the plan it sits

SELECT qp.query_plan 
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE CAST(qs.query_plan_hash AS BIGINT) = -832496756154281217
GO

-- How will I search for my node_id? Use showplan search in SSMS.

-------------------------------

-- Now for a new event. A LWP-based "query_post_execution_showplan"

DROP EVENT SESSION [PerfStats_LWP_Plan] ON SERVER 
GO
CREATE EVENT SESSION [PerfStats_LWP_Plan] ON SERVER
ADD EVENT sqlserver.query_plan_profile(
ACTION(sqlos.scheduler_id,sqlserver.database_id,sqlserver.is_system,sqlserver.plan_handle,sqlserver.query_hash_signed,sqlserver.query_plan_hash_signed,sqlserver.server_instance_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.sql_text))
--ADD TARGET package0.ring_buffer(SET max_memory=(25600))
ADD TARGET package0.event_file(SET filename=N'C:\IP\Tiger\SQL Intersection\SQL Intersection Winter 2018\Gems to Help You Troubleshoot Query Performance\new_xevents\PerfStats_LWP_Plan.xel',max_file_size=(50),max_rollover_files=(2))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

ALTER EVENT SESSION [PerfStats_LWP_Plan] ON SERVER STATE = start;  
GO   

-- Let's run the following query
SELECT e.[BusinessEntityID], 
       p.[Title], 
       p.[FirstName], 
       p.[MiddleName], 
       p.[LastName], 
       p.[Suffix], 
       e.[JobTitle], 
       pp.[PhoneNumber], 
       pnt.[Name] AS [PhoneNumberType], 
       ea.[EmailAddress], 
       p.[EmailPromotion], 
       a.[AddressLine1], 
       a.[AddressLine2], 
       a.[City], 
       sp.[Name] AS [StateProvinceName], 
       a.[PostalCode], 
       cr.[Name] AS [CountryRegionName], 
       p.[AdditionalContactInfo] 
FROM   [HumanResources].[Employee] AS e 
       INNER JOIN [Person].[Person] AS p 
       ON RTRIM(LTRIM(p.[BusinessEntityID])) = RTRIM(LTRIM(e.[BusinessEntityID])) 
       INNER JOIN [Person].[BusinessEntityAddress] AS bea 
       ON RTRIM(LTRIM(bea.[BusinessEntityID])) = RTRIM(LTRIM(e.[BusinessEntityID])) 
       INNER JOIN [Person].[Address] AS a 
       ON RTRIM(LTRIM(a.[AddressID])) = RTRIM(LTRIM(bea.[AddressID])) 
       INNER JOIN [Person].[StateProvince] AS sp 
       ON RTRIM(LTRIM(sp.[StateProvinceID])) = RTRIM(LTRIM(a.[StateProvinceID])) 
       INNER JOIN [Person].[CountryRegion] AS cr 
       ON RTRIM(LTRIM(cr.[CountryRegionCode])) = RTRIM(LTRIM(sp.[CountryRegionCode])) 
       LEFT OUTER JOIN [Person].[PersonPhone] AS pp 
       ON RTRIM(LTRIM(pp.BusinessEntityID)) = RTRIM(LTRIM(p.[BusinessEntityID])) 
       LEFT OUTER JOIN [Person].[PhoneNumberType] AS pnt 
       ON RTRIM(LTRIM(pp.[PhoneNumberTypeID])) = RTRIM(LTRIM(pnt.[PhoneNumberTypeID])) 
       LEFT OUTER JOIN [Person].[EmailAddress] AS ea 
       ON RTRIM(LTRIM(p.[BusinessEntityID])) = RTRIM(LTRIM(ea.[BusinessEntityID]))
OPTION (RECOMPILE, USE HINT('QUERY_PLAN_PROFILE'))
GO

ALTER EVENT SESSION [PerfStats_LWP_Plan] ON SERVER STATE = stop;  
GO 

-- Let's see the event and what it provides