We have found an issue where if you are using Query Store feature with SQL Server 2017 CU2, and later upgrade to SQL Server 2017 CU3 (or higher when available), an attempt to use the stored showplan fails. This includes the ability to force a specific plan captured by Query Store while SQL Server 2017 CU2 (14.0.3008.27) was installed, while already running with CU3 (14.0.3015.40) or a newer build.

As such, to assist DBAs in removing any of the affected plans collected while SQL Server 2017 CU2 was installed, we have created this T-SQL script to remove only the affected plans in Query Store. Execute it immediately after upgrading from SQL Server 2017 CU2 to SQL Server 2017 CU3 or a newer CU. If you are upgrading already from SQL Server 2017 CU3 or a newer build, executing the script is not needed.

**Note:** Any query plans captured by Query Store in versions prior to 14.0.3008.27 are not affected. Only plans captured in 14.0.3008.27. Therefore the script will only remove plans from the Query Store that match SQL Server 2017 CU2 (build 14.0.3008.27).

**Note2:** While Query Store is also available in SQL Server 2016 and 2019, these versions are not affected in any build.
