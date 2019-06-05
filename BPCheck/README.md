# BPCheck - SQL Best Practices and Performance checks

## Purpose:
Checks SQL Server in scope for some of most common skewed Best Practices and performance issues. 
Valid from SQL Server 2005 onwards. By default all databases in the SQL Server instance are eligible for the several database specific checks, and you may use the optional parameter to narrow these checks to specific databases.
All checks marked with an asterisk can be disabled by @ptocheck parameter. Check the PARAMETERS.md file or script header for all usage parameters.

## Parameters for executing BPCheck
- **@duration** Sets the number of seconds between data collection points regarding perf counters, waits and latches. Duration must be between 10s and 255s (4m 15s), with a default of 90s.
- **@ptochecks** Set to OFF if you want to skip more performance tuning and optimization oriented checks. Uncomment **@custompath** below and set the custom desired path for .ps1 files. If not, default location for .ps1 files is the Log folder.
- **@allow_xpcmdshell** Set to OFF if you want to skip checks that are dependant on xp_cmdshell. Note that original server setting for xp_cmdshell would be left unchanged if tests were allowed.
- **@spn_check** Set to OFF if you want to skip SPN checks.
- **@diskfrag** Set to ON if you want to check for disk physical fragmentation. Can take some time in large disks. Requires elevated privileges.
- **@ixfrag** Set to ON if you want to check for index fragmentation. Can take some time to collect data depending on number of databases and indexes, as well as the scan mode chosen in @ixfragscanmode.
- **@ixfragscanmode** Set to the scanning mode you prefer. More detail on scanning modes available at http://msdn.microsoft.com/en-us/library/ms188917.aspx
- **@logdetail** Set to OFF if you want to get just the summary info on issues in the Errorlog, rather than the full detail.
- **@bpool_consumer** Set to OFF if you want to list what are the Buffer Pool Consumers from Buffer Descriptors. Mind that it may take some time in servers with large caches.
- **@gen_scripts** Set to ON if you want to generate index related scripts. These include drops for Duplicate, Redundant, Hypothetical and Rarely Used indexes, as well as creation statements for FK and Missing Indexes.
- **@dbScope** Set to the appropriate list of database IDs if there's a need to have a specific scope for database specific checks. Valid input should be numeric value(s) between single quotes, as follows: '1,6,15,123'. Leave NULL for all databases.

## Detail on output sections:
Contains the following informational sections:
- Uptime
- Windows Version and Architecture
- HA Information
- Linked servers info
- Instance info
- Buffer Pool Extension info
- Resource Governor info
- Logon triggers
- Database Information
- Database file autogrows last 72h
- Database triggers
- Enterprise features usage
- System Configuration

And performs the following checks:
- Processor
  - Number of available Processors for this instance vs. MaxDOP setting
  - Processor Affinity in NUMA architecture
  - HP Logical Processor issue (https://support.hpe.com/hpsc/doc/public/display?docId=emr_na-c04650594)
  - Additional Processor information
- Memory
  - Server Memory
  - RM Task *
  - Clock hands *
  - Buffer Pool Consumers from Buffer Descriptors *
  - Memory Allocations from Memory Clerks *
  - Memory Consumers from In-Memory OLTP Engine *
  - Memory Allocations from In-Memory OLTP Engine *
  - OOM
  - LPIM
- Pagefile
  - Pagefile
- I/O
  - I/O Stall subsection (wait for 5s) *
  - Pending disk I/O Requests subsection (wait for a max of 5s) *
- Server
  - Power plan
  - NTFS block size in volumes that hold database files <> 64KB
  - Disk Fragmentation Analysis (if enabled)
  - Cluster Quorum Model
  - Cluster QFE node equality
  - Cluster NIC Binding order
- Service Accounts
  - Service Accounts Status
  - Service Accounts and SPN registration
- Instance
  - Recommended build check
  - Backups
  - Global trace flags
  - System configurations
  - IFI
  - Full Text Configurations
  - Deprecated and Discontinued feature usage
  - Default data collections (default trace, blackbox trace, SystemHealth xEvent session, spserverdiagnostics xEvent session) *
- Database and tempDB
  - User objects in master
  - DBs with collation <> master
  - DBs with skewed compatibility level
  - User DBs with non-default options
  - DBs with Sparse files
  - DBs Autogrow in percentage
  - DBs Autogrowth > 1GB in Logs or Data (when IFI is disabled)
  - VLF
  - Data files and Logs / tempDB and user Databases / Backups and Database files in same volume (Mountpoint aware)
  - tempDB data file configurations
  - tempDB Files autogrow of equal size
- Performance
  - Perf counters, Waits and Latches (wait for XXs) *
  - Worker thread exhaustion *
  - Blocking Chains *
  - Plan use ratio *
  - Hints usage *
  - Cached Query Plans issues *
  - Declarative Referential Integrity - Untrusted Constraints
- Indexes and Statistics
  - Statistics update *
  - Statistics sampling *
  - Hypothetical objects *
  - Row Index Fragmentation Analysis (if enabled) *
  - CS Index Health Analysis (if enabled) *
  - XTP Index Health Analysis (if enabled) *
  - Duplicate or Redundant indexes *
  - Unused and rarely used indexes *
  - Indexes with large keys (> 900 bytes) *
  - Indexes with fill factor < 80 pct *
  - Disabled indexes *
  - Non-unique clustered indexes *
  - Clustered Indexes with GUIDs in key *
  - Foreign Keys with no Index *
  - Indexing per Table *
  - Missing Indexes *
- Naming Convention
  - Objects naming conventions
- Security
  - Password check
- Maintenance and Monitoring
  - SQL Agent alerts for severe errors
  - DBCC CHECKDB, Direct Catalog Updates and Data Purity
  - AlwaysOn/Mirroring automatic page repair
  - Suspect pages
  - Replication Errors
  - Errorlog based checks
  - System health checks

## IMPORTANT pre-requisites:
- Only a sysadmin/local host admin will be able to perform all checks.
- If you want to perform all checks under non-sysadmin credentials, then that login must be:
  - Member of serveradmin server role or have the ALTER SETTINGS server permission; 
  - Member of MSDB SQLAgentOperatorRole role, or have SELECT permission on the sysalerts table in MSDB;
  - Granted EXECUTE permissions on the following extended sprocs to run checks: spOACreate, spOADestroy, spOAGetErrorInfo, xpenumerrorlogs, xpfileexist and xpregenumvalues;
  - Granted EXECUTE permissions on xp_msver;
  - Granted the VIEW SERVER STATE permission;
  - Granted the VIEW DATABASE STATE permission;
  - A xp_cmdshell proxy account should exist to run checks that access disk or OS security configurations.
  - Member of securityadmin role, or have EXECUTE permissions on sp_readerrorlog. 
  - Otherwise some checks will be bypassed and warnings will be shown.
- Powershell must be installed to run checks that access disk configurations, as well as allow execution of unsigned scripts.
