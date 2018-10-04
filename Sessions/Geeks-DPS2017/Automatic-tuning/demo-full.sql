use wideworldimporters
go

/********************************************************
*	SETUP - clear everything
********************************************************/
EXEC [dbo].[initialize]


/********************************************************
*	PART I
*	Plan regression identification.
********************************************************/

-- 1. Start workload - execute procedure 30 times:
-- Confirm that execution time is (3 sec total)
begin
declare @packagetypeid int = 7;
exec dbo.report @packagetypeid
end
go 30

-- 2. Execute procedure that causes plan regression
exec dbo.regression

-- 3. Start workload again - verify that is slower.
-- Execution time should be (8secs in total)
-- Notice we only ran it 20 times and it was still 50%+ slower
begin
declare @packagetypeid int = 7;
exec dbo.report @packagetypeid
end
go 20

-- 4. Find recommendation recommended by database:

SELECT reason, score,
	JSON_VALUE(state, '$.currentValue') state,
	JSON_VALUE(state, '$.reason') state_transition_reason,
    JSON_VALUE(details, '$.implementationDetails.script') script,
    planForceDetails.*
FROM sys.dm_db_tuning_recommendations
  CROSS APPLY OPENJSON (Details, '$.planForceDetails')
    WITH (  [query_id] int '$.queryId',
            [new plan_id] int '$.regressedPlanId',
            [recommended plan_id] int '$.recommendedPlanId'
          ) as planForceDetails;

-- Note: User can apply script and force the recommended plan to correct the error.
-- In part II will be shown better approach - automatic tuning.

/********************************************************
*	PART II
*	Automatic tuning
********************************************************/

/********************************************************
*	RESET - clear everything
********************************************************/
DBCC FREEPROCCACHE;
ALTER DATABASE current SET QUERY_STORE CLEAR ALL;

-- Enable automatic tuning on the database:
ALTER DATABASE current
SET AUTOMATIC_TUNING ( FORCE_LAST_GOOD_PLAN = ON);

-- Verify that actual state on FLGP is ON:
SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;


-- 1. Start workload - execute procedure 30 times like in the phase I
-- Execution should be around 3-4 secs again.
begin
declare @packagetypeid int = 7;
exec dbo.report @packagetypeid
end
go 30

-- 2. Execute the procedure that causes plan regression
exec dbo.regression

-- 3. Start workload again - verify that it is slower.
-- Execution should be again 50%+ slower with only 20 executions
begin
declare @packagetypeid int = 7;
exec dbo.report @packagetypeid
end
go 20

-- 4. Find recommendation that returns query perf regression
-- and check is it in Verifying state:
SELECT reason, score,
	JSON_VALUE(state, '$.currentValue') state,
	JSON_VALUE(state, '$.reason') state_transition_reason,
    JSON_VALUE(details, '$.implementationDetails.script') script,
    planForceDetails.*
FROM sys.dm_db_tuning_recommendations
  CROSS APPLY OPENJSON (Details, '$.planForceDetails')
    WITH (  [query_id] int '$.queryId',
            [new plan_id] int '$.regressedPlanId',
            [recommended plan_id] int '$.recommendedPlanId'
          ) as planForceDetails;
	  
-- 5. Wait until recommendation is applied and start workload again - verify that it is faster.
-- Execution should be back to normal execution
begin
declare @packagetypeid int = 7;
exec dbo.report @packagetypeid
end
go 20
-- Open query store dialogs in SSMS and show that better plan is forced looking at the Top Resource Consuming Queries Report