---
title: "Upgrading Databases by using the Query Tuning Assistant"
ms.date: "11/21/2018"
author: pelopes
---
# Upgrading Database Compatibility Level using QTA Lab 

## Intro - Defining the problem and goal
When migrating from an older version of SQL Server and [upgrading the database compatibility level](https://docs.microsoft.com/sql/relational-databases/databases/view-or-change-the-compatibility-level-of-a-database) to the latest available, a workload may be exposed to the risk of performance regression. 

Starting with SQL Server 2016, all query optimizer changes are gated to the latest database compatibility level, which in combination with Query Store gives you a great level of control over the query performance in the upgrade process if the upgrade follows the recommended workflow seen below. 

![Recommended database upgrade workflow using Query Store](https://docs.microsoft.com/sql/relational-databases/performance/media/query-store-usage-5.png "Recommended database upgrade workflow using Query Store") 

This control over upgrades was further improved with SQL Server 2017 where [Automatic Tuning](https://docs.microsoft.com/sql/relational-databases/automatic-tuning/automatic-tuning.md) was introduced and allows automating the last step in the recommended workflow above.

Starting with SSMS v18, the new **Query Tuning Assistant (QTA)** feature will guide users through the recommended workflow to keep performance stability during database upgrades. See below how QTA essentially only changes the last steps of the recommended workflow for upgrading the compatibility level using Query Store seen above. Instead of having the option to choose between the currently inneficient execution plan and the last known good execution plan, QTA presents tuning options that are specific for the selected regressed queries, to create a new improved state with tuned execution plans.

![Recommended database upgrade workflow using QTA](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-usage.png "Recommended database upgrade workflow using QTA")

Note that QTA does not generate user workload so users must ensure that a representative test workload can be executed on the target instance. 

## Pre Lab

(Place holder for database restore/attach + SSMS install)

## Lab

### 1. Configure an upgrade session

1.  In SSMS, open the Object Explorer and connect to your local SQL Server instance.

2.  For the database that is intended to upgrade the database compatibility level (AdventureWorks2012DW), right-click the database name, select **Tasks**, select **Database Upgrade**, and click on **New Database Upgrade Session**.

3.  In the **Setup** window, configure Query Store to capture the equivalent of one full business cycle of worload data to analyze and tune. 
    -  Enter **1** as the expected workload duration in days (minimum is 1 day). This will be used to propose recommended Query Store settings to tentatively allow the entire baseline to be collected. Capturing a good baseline is important to ensure any regressed queries found after changing the database compatibility level are able to be analyzed. 
    -  Set the intended target database compatibility level to **140**. This is the setting that the user database should be at, after the QTA workflow has completed. 
    -  Once complete, click **Next**.
    
       ![New database upgrade session setup window](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-new-session-setup.png "New database upgrade setup window")  
  
4.  In the **Settings** window, two columns show the **Current** state of Query Store in the targeted database, as well as the **Recommended** settings. Click on the **Recommended** button (if not selected by default). 

       ![New database upgrade settings window](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-new-session-settings.png "New database upgrade settings window")

5.  The **Tuning** window concludes the session configuration, and instructs on next steps to open and proceed with the session. Once complete, click **Finish**.

    ![New database upgrade tuning window](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-new-session-tuning.png "New database upgrade tuning window")

### 2. Executing the database upgrade workflow
1.  For the database that is intended to upgrade the database compatibility level (AdventureWorks2012DW), right-click the database name, select **Tasks**, select **Database Upgrade**, and click on **Monitor Sessions**.

2.  The **session management** page lists current and past sessions for the database in scope. Select the desired session, and click on **Details**.
    
    ![QTA Session Management page](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-session-management.png "QTA Session Management page")

3.  The entry point for a new session is the **Data Collection** step. 

    > [!NOTE]
    > The **Sessions** button returns to the **session management** page, leaving the active session as-is.

    This step has 3 substeps:

    1.  **Baseline Data Collection** requests the user to run the representative workload cycle, so that Query Store can collect a baseline. Once that workload has completed, check the **Done with workload run** and click **Next**.

        > [!NOTE]
        > The QTA window can be closed while the workload runs. Returning to the session that remains in active state at a later time will resume from the same step where it was left off. 

        ![QTA Step 2 Substep 1](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step2-substep1.png "QTA Step 2 Substep 1")

    2.  **Upgrade Database** will prompt for permission to upgrade the database compatibility level to the desired target. To proceed to the next substep, click **Yes**.

        ![QTA Step 2 Substep 2 - Upgrade database compatibility level](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step2-substep2-prompt.png "QTA Step 2 Substep 2 - Upgrade database compatibility level")

        The following page confirms that the database compatibility level was successfully upgraded.

        ![QTA Step 2 Substep 2](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step2-substep2.png "QTA Step 2 Substep 2")

    3.  **Observed Data Collection** requests the user to re-run the representative workload cycle, so that Query Store can collect a comparative baseline that will be used to search for optimization opportunities. As the workload executes, use the **Refresh** button to keep updating the list of regressed queries, if any were found. Change the **Queries to show** value to limit the number of queries displayed. The order of the list is affected by the **Metric** (Duration or CpuTime) and the **Aggregation** (Average is default). Also select how many **Queries to show**. Once that workload has completed, check the **Done with workload run** and click **Next**.

        ![QTA Step 2 Substep 3](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step2-substep3.png "QTA Step 2 Substep 3")

        The list contains the following information:
        -  **Query ID** 
        -  **Query Text**: [!INCLUDE[tsql](https://docs.microsoft.com/sql/includes/tsql-md.md)] statement that can be expanded by clicking the **...** button.
        -  **Runs**: Displays the number of executions of that query for the entore workload collection.
        -  **Baseline Metric**: The selected metric (Duration or CpuTime) in ms for the baseline data collection before the database compatibility upgrade.
        -  **Observed Metric**: The selected metric (Duration or CpuTime) in ms for the data collection after the database compatibility upgrade.
        -  **% Change**: Percentual change for the selected metric between the before and after database compatibility upgrade state. A negative number represents the amount of measured regression for the query.
        -  **Tunable**: *True* or *False* depending on whether the query is eligible for experimentation.

4.  **View Analysis** allows selection of which queries to experiment and find optimization opportunities. The **Queries to show** value becomes the scope of eligible queries to experiment on. Once the desired queries are checked, click **Next** to start experimentation.  

    > [!NOTE]
    > Queries with Tunable = False cannot be selected for experimentation.   
 
    > [!IMPORTANT]
    > A prompt advises that once QTA moves to the experimentation phase, returning to the View Analysis page will not be possible.   
    > If you don't select all eligible queries before moving to the experimentation phase, you need to create a new session at a later time, and repeat the workflow. This requires reset of database compatibility level to the previous value.

    ![QTA Step 3](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step3.png "QTA Step 3")

5.  **View Findings** allows selection of which queries to deploy the proposed optimization as a plan guide. 

    The list contains the following information:
    -  **Query ID** 
    -  **Query Text**: [!INCLUDE[tsql](https://docs.microsoft.com/sql/includes/tsql-md.md)] statement that can be expanded by clicking the **...** button.
    -  **Status**: Displays the current experimentation state for the query.
    -  **Baseline Metric**: The selected metric (Duration or CpuTime) in ms for the query as executed in **Step 2 Substep 3**, representing the regressed query after the database compatibility upgrade.
    -  **Observed Metric**: The selected metric (Duration or CpuTime) in ms for the query after experimentation, for a good enough proposed optimization.
    -  **% Change**: Percentual change for the selected metric between the before and after experimentation state, representing the amount of measured improvement for the query with the proposed optimization.
    -  **Query Option**: Link to the proposed hint that improves query execution metric.
    -  **Can Deploy**: *True* or *False* depending on whether the proposed query optimization can be deployed as a plan guide.

    ![QTA Step 4](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step4.png "QTA Step 4")

6.  **Verification** shows the deployment status of previously selected queries for this session. The list in this page differs from the previous page by changing the **Can Deploy** column to **Can Rollback**. This column can be *True* or *False* depending on whether the deployed query optimization can be rolled back and its plan guide removed.

    ![QTA Step 5](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step5.png "QTA Step 5")

    If at a later date there is a need to rollback on a proposed optimization, then select the relevant query and click **Rollback**. That query plan guide is removed and the list updated to remove the rolled back query. Note in the picture below that query 8 was removed.

    ![QTA Step 5 - Rollback](https://docs.microsoft.com/sql/relational-databases/performance/media/qta-step5-rollback.png "QTA Step 5 - Rollback") 

    > [!NOTE]
    > Deleting a closed session does **not** delete any previously deployed plan guides.   
    > If you delete a session that had deployed plan guides, then you cannot use QTA to rollback.    
    > Instead, search for plan guides using the [sys.plan_guides](https://docs.microsoft.com/sql/relational-databases/system-catalog-views/sys-plan-guides-transact-sql.md) system table, and delete manually using [sp_control_plan_guide](https://docs.microsoft.com/sql/relational-databases/system-stored-procedures/sp-control-plan-guide-transact-sql.md).  
  
## Permissions  
Requires membership of **db_owner** role membership.
  
## See Also  
 [Compatibility Levels and SQL Server Upgrades](https://docs.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-compatibility-level.md#compatibility-levels-and-sql-server-upgrades)    
 [Performance Monitoring and Tuning Tools](https://docs.microsoft.com/sql/relational-databases/performance/performance-monitoring-and-tuning-tools.md)     
 [Monitoring Performance By Using the Query Store](https://docs.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store.md)     
 [Change the Database Compatibility Mode and Use the Query Store](https://docs.microsoft.com/sql/database-engine/install-windows/change-the-database-compatibility-mode-and-use-the-query-store.md)       
 [Trace flags](https://docs.microsoft.com/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql.md)    
 [USE HINT query hints](https://docs.microsoft.com/sql/t-sql/queries/hints-transact-sql-query.md#use_hint)     
 [Cardinality Estimator](https://docs.microsoft.com/sql/relational-databases/performance/cardinality-estimation-sql-server.md)     
 [Automatic Tuning](https://docs.microsoft.com/sql/relational-databases/automatic-tuning/automatic-tuning.md)      
