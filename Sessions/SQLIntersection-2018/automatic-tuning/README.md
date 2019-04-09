This is a repro package to demonstrate the Automatic Tuning (Auto Plan Correction) in SQL Server 2017. 
This feature is using telemtry from the Query Store feature we launched with Azure SQL Database and SQL Server 2016 to provide built-in intelligence.

This repro assumes the following:

- SQL Server 2017 installed (pick at minimum Database Engine) on Windows. This feature requires Developer or Enterprise Edition.
- You have installed SQL Server Management Studio or SQL Operations Studio (https://docs.microsoft.com/en-us/sql/sql-operations-studio/download)
- You have downloaded the RML Utilities from https://www.microsoft.com/en-us/download/details.aspx?id=4511.
- These demos use a named instance called SQL2017. You will need to edit the .cmd scripts which connect to SQL Server to change to a default instance or whatever named instance you have installed.

0. Install ostress from the package RML_Setup_AMD64.msi. Add C:\Program Files\Microsoft Corporation\RMLUtils to your path.

1. Restore the WideWorldImporters database backup to your SQL Server 2017 instance. The WideWorldImporters can be found in https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers

2. Run Scenario.cmd to customize the WideWorldImporters database and start the demo. Leave it running...

3. Setup Performance Monitor on Windows to track SQL Statistics/Batch Requests/sec

4. While Scenario.cmd is running, run Regression.cmd (you may need to run this a few times for timing reasons). Notice the drop in batch requests/sec which shows a performance regression in your workload.

5. Load recommendations.sql into SQL Server Management Studio or SQL Operations Studio and review the results. Notice the time difference under the reason column and value of state_transition_reason which should be AutomaticTuningOptionNotEnabled. This means we found a regression but are recommending it only, not automatically fixing it. The script column shows a query that could be used to fix the problem.

6. Stop Scenario.cmd workload by pressing CTRL+C, and then choose "N" when prompted to terminate the batch.

7. Now let's see what happens with automatic plan correction which uses this command in SQL Server 2017:

ALTER DATABASE <db>
SET AUTOMATIC_TUNING ( FORCE_LAST_GOOD_PLAN = ON )

8. Run Auto_tune.cmd which uses the above command to set automatic plan correct ON for WideWorldImporters, and starts same workload as Scenario.cmd

9. Repeat steps 4-6 as above. In Performance Monitor you will see the batch requests/sec dip but within a second go right back up. This is because SQL Server detected the regression and automatically reverted to "last known good" or the last known good query plan as found in the Query Store. Note in the output of recommendations.sql the state_transition_reason now says LastGoodPlanForced.