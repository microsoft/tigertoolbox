**Important options for executing BPCheck**

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
