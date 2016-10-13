
# TLS 1.2 
This section contains a PowerShell script which you can execute on your machines to determine which client drivers need to be updated to support TLS 1.2 for SQL Server.


### CheckClientUpdates.ps1
The PowerShell Script currently supports the following:
* Check if SQL Server Native Client can support TLS 1.2
* Check if Microsoft ODBC Driver for SQL Server can support TLS 1.2
This script is restricted to work on x64 and x86 platforms 

More information about TLS 1.2 can be found in [KB3135244](https://support.microsoft.com/en-us/kb/3135244). A recorded webinar on what TLS 1.2 means for SQL Server is available on our [Release Services blog](https://blogs.msdn.microsoft.com/sqlreleaseservices/tls-1-2-support-for-sql-server-2008-2008-r2-2012-and-2014/) along with additional documentation on known issues  .
