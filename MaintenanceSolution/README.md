More information at http://aka.ms/MaintenanceSolution

Good maintenance (or lack thereof) may be the difference between good and bad performance. 
Following up on that train of though, over the years I've used this solution to automate maintenance tasks in SQL Server (except for backup, which is usually handled using dedicated backup solutions/agents). 
With these scripts, within a couple minutes you can deploy a comprehensive set of SQL Agent jobs that will get the required work done.

Here's the detail on what these steps do:

- **0_database_server_options**:
  - Change the Errorlog file limitation from 8 to 15.
  - Changes a few sys.configurations such as “Backup compression default”, enable “remote admin connections” and optionally “Optimize for Ad Hoc workloads”.
  - Changes the model data and log files to autogrow 100MB (generalization better than the default).
  - Removes AUTO_CLOSE and AUTO_SHRINK database options from all databases.
  - Changes whatever page verify setting to CHECKSUM.
  - Sets proper MaxDOP setting for server in scope.
  - Sets proper Max Server Memory setting for **one standalone** instance in current server. Comment out if not your scenario.

- **1_DatabaseMail_Config** (only run if you want to have email based alerts, and Database Mail is not already configured).
  - Just edit the script and enter the proper account information in the configuration variables near the top and run it. Replace with the information for your account.
  - Creates a Database Mail profile. Usually there is a distribution list for the DBAs, so I‘m keen on using that address.
  - Creates an operator using that Database Mail profile.

- **AdaptiveIndexDefrag** deployed from http://aka.ms/AdaptiveIndexDefrag

- **3_job_AdaptiveIndexDefrag**
  - Creates a daily job for the AdaptiveIndexDefrag procedure, named “Daily Index Defrag”. It will also notify the previously created operator on the job outcome.
  - Find some of the most common (default) names for Microsoft shipped databases (step “DB Exceptions”), to add the to the permanent exclusion list, if not already there. For example, SharePoint grooms its own databases, so we shou.ld exclude them from any other automated maintenance task. If the AdaptiveIndexDefrag procedure was NOT created in MSDB, simply replace all references to MSDB for whatever database name you chose.
  - Execute the AdaptiveIndexDefrag procedure (step “Daily Index Defrag”).
  - Purge all historic log data for the index defrag executions using default 90 days (step “Purge Log”).

- **4_job_AdaptiveCycleErrorlog**
  - Creates a job named “Daily Cycle Errorlog” to keep a manageable ErrorLog file size. 
  - Runs daily, but will only cycle the Errorlog when its size is over 20MB or its age over 15 days.

- **5_job_Maintenance** (or 5_job_Maintenance_MEA - for MEA region weekends are different)
  - Creates the job “Weekly Maintenance”, and "usp_CheckIntegrity" stored procedure to handle the logic and a view in MSDB that allows to quickly check the output for each job step, XML formatted so that it’s easier to view. 
  - The weekly actions aim to execute on Fridays for MEA and Sundays for the rest of the world.
  - Job will:
    - Weekly DBCC CHECKDB on all online, read-write user databases below 1TB.
    - Daily combination of DBCC CHECKALLOC, DBCC CHECKCATALOG, DBCC CHECKTABLE (depending on VLDB setting) on all online, read-write user databases over 1TB.
    - Weekly execution of DBCC UPDATEUSAGE on all online, read-write databases up to 4GB.
    - Weekly execution of sp_createstats with indexonly.
    - Weekly purge of all MSDB job history over 30d.
    - Weekly purge of all maintenance plan text reports over 30d (uf you are still using package based maintenance plans).
    
    > **NOTE**: Carefully review the parameters of usp_CheckIntegrity to configure what best suits your specific system.
    
- **6_Agent_Alerts** (Optional if you do not have other ways of being alerted for important errors being logged)
  - Creates SQL Agent based alerts, covering the following error codes and severities:
    - Severity 10: Error(s) 825, 833, 855, 856, 3452, 3619, 17179, 17883, 17884, 17887, 17888, 17890 and 28036
    - Severity 16: Error(s) 2508, 2511, 3271, 5228, 5229, 5242, 5243, 5250, 5901, 17130 and 17300
    - Severity 17: Error(s) 802, 845, 1101, 1105, 1121, 1214 and 9002
    - Severity 19: Error(s) 701
    - Severity 20: Error(s) 3624
    - Severity 21: Error(s) 605
    - Severity 22: Error(s) 5180 and 8966
    - Severity 23: Error(s) 5572 and 9100
    - Severity 24: Error(s) 823, 824 and 832
