**usp_WhatsUp**

**Purpose:** Understand what's up with your SQL Server and get all sorts of useful troubleshooting information such as:
-  A snapshot on running sessions/requests; 
-  Current blocking information; 
-  Optionally, SP/Query/Trigger/Function execution stats.

In the output, you will find the following information in 6 sections:
-  Uptime Information
-  Running Sessions/Requests Report including resource usage, running statement, execution plan, blocking resource, waits and other relevant information.
-  Waiter and Blocking Report, including information on head blocker and blocking chains.
-  Stored procedure execution statistics.
-  Query execution statistics.
-  Trigger execution statistics.
-  Function execution statistics.

**Change log:**
-  2012-09-10 Added extra information
-  2013-02-02 Added extra information
-  2013-04-12 Added page type information (PFS; GAM or SGAM) when wait type is PAGELATCH_ or PAGEIOLATCH_ .
-  2013-05-23 Fixed parse page issue
-  2013-09-16 Added mem grants information
-  2013-10-17 Added statements to blocking and blocked sections, fixed head blocker info 
-  2013-12-09 Fixed blocking section showing non-blocked sessions also
-  2014-02-04 Fixed conversion issue with blocking section
-  2014-04-09 Added information to blocking section, and fixed conversion issue
-  2014-12-09 Handle illegal characters in XML conversion
-  11/16/2016 Added support for SQL Server 2016 SP1 and live query plan snapshot.
-  12/2/2016 Fixed transport-level error issue with SQL Server 2016 SP1.
-  2/16/2016 Added NOLOCK hints.
-  3/28/2017 Fixed missing characters in offset fetches.
-  10/11/2017 Commented out stored procedure/query stats section to optimize for in-flight requests.
-  10/20/2017 Added Query stats section and support for sys.dm_exec_query_statistics_xml.
-  04/02/2019 Added support for sys.dm_exec_query_plan_stats and trigger/function stats section.
-  04/08/2019 Made into a stored procedure usp_whatsup instead of adhoc script for ease of use.
-  04/09/2019 Fixes to the adhoc to sproc conversion:
   -  Changed the variable @sqlcmd NVARCHAR(500) to VARCHAR(8000) to prevent "Common table expression defined but not used." error (Thanks Kin Shah (https://dba.stackexchange.com/users/8783/kin));
   -  Removed the extra "," that was throwing parsing error (Thanks Kin Shah (https://dba.stackexchange.com/users/8783/kin));
   -  Added create proc and alter note to allow new changes to the SP if the SP is already present (Thanks Kin Shah (https://dba.stackexchange.com/users/8783/kin));
   -  Changed parameter @uptime to @uptimesql (Thanks Kin Shah (https://dba.stackexchange.com/users/8783/kin));
   -  Fixed unbound column in Function stats section;
   -  Added more information to Query stats section.
-  04/15/2019 Added support for input buffer DMF.
-  04/17/2019 Fixed function stats query failing in SQL Server 2012 and 2014.
