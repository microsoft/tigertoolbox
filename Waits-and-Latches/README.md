**Purpose:** Identify where your system is hurting using wait and latch stats, categorizing the most common wait types and latch classes.

In the output for view_Waits.sql, you will find the following information in 4 sections:
-  Uptime Information
-  Waits over last xx seconds (default is 60s).
-  Waits since server last restarted or DMV was manually cleared using DBCC SQLPERF("sys.dm_os_wait_stats",CLEAR).
-  Current waiting tasks.

In the output for view_Latches.sql, you will find the following information in 3 sections:
-  Uptime Information
-  Latches over last xx seconds (default is 60s).
-  Latches since server last restarted or DMV was manually cleared using DBCC SQLPERF("sys.dm_os_latch_stats",CLEAR).