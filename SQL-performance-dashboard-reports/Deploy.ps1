<# This script is intented to help automate Steps 2-7 for downloading & deploying the SQL Server Performance Dashboard Reports 
    https://blogs.msdn.microsoft.com/sql_server_team/sql-server-performance-dashboard-reports-unleashed-for-enterprise-monitoring/ #> 

<# If the ReportingServicesTools is not present, download the ReportingServicesTools module from GitHib #>
try {Import-Module ReportingServicesTools -ErrorAction Stop} catch {Invoke-Expression (Invoke-WebRequest https://aka.ms/rstools)} finally {Import-Module ReportingServicesTools}

<# Setting our GitHub resources to variables #>
$ZipURL = "https://github.com/Microsoft/tigertoolbox/raw/master/SQL-performance-dashboard-reports/SQL%20Server%20Performance%20Dashboard%20Reporting%20Solution.zip"
$SQLURL = 'https://github.com/Microsoft/tigertoolbox/raw/master/SQL-performance-dashboard-reports/setup.sql'

<# Where to place the files when they are downloaded
   $ZipFile will go to the current users 'Downloads' folder.
   $ReportsBaseFolder is where the SSRS Solution will be unzipped to. 
       You could change this to somewhere else like "$($env:USERPROFILE)\Documents\Visual Studio 2015\Projects"
   $SQLFile is the Setup.SQL that must be run on each SQL Server before these reports can work. #>
$ZipFile = "$($env:USERPROFILE)\Downloads\SQLServerPerformanceDashboardReportingSolution.zip"
$ReportsBaseFolder = 'C:\SQL Server Performance Dashboard'
$SQLFile = "$($ReportsBaseFolder)\Setup.SQL"

<# SSRS Instance, this is where the reports will be rendered from.
    You probably need to change this to something like 'http://MyReportServer/ReportServer'.  If you have a named SSRS instance 'http://MyReportServer/ReportServer_SQL2016'  #>
$SSRSInstance = 'http://localhost/ReportServer'
$NewSSRSReportFolder = 'SQL Server Performance Dashboard'

<# Start up a web client and download the GitHub resources #>
$webclient = New-Object system.net.webclient
$webclient.DownloadFile($ZipURL,$ZipFile)

<# UnZip the Reporting Solution Zip file #>
Expand-Archive $ZipFile -DestinationPath $ReportsBaseFolder

<# Now that the reports are unzipped, download the SQL file to that same directory #>
$webclient.DownloadFile($SQLURL,$SQLFile)

<# Deploy the dashboard reports to the $NewSSRSReportFolder ('SQL Server Performance Dashboard') folder of an SSRS instance
    Note: We are creating the folder using New-RsFolder, you may need to skip this step if you’ve already run it once. #>
New-RsFolder -ReportServerUri $SSRSInstance -Path / -Name $NewSSRSReportFolder

Write-RsFolderContent -ReportServerUri $SSRSInstance -Path "$($ReportsBaseFolder)\SQL Server Performance Dashboard\" -Destination /$NewSSRSReportFolder

<# Loop through Registered Servers & deploy the Setup.SQL file to each instance
    You can also use a Central Management Server to list your SQL servers by swapping 'Database Engine Server Group' for 'Central Management Server Group'  #>
foreach ($RegisteredSQLs IN dir -recurse SQLSERVER:\SQLRegistration\'Database Engine Server Group'\ | where {$_.Mode -ne 'd'} )
{
Invoke-Sqlcmd -ServerInstance $RegisteredSQLs.Name -Database msdb -InputFile $SQLFile
}

<# Go to SSRS and make sure everythng works
    You URL should look something like http://localhost/Reports/report/SQL%20Server%20Performance%20Dashboard/performance_dashboard_main
    Continur with Setp #8 back at https://blogs.msdn.microsoft.com/sql_server_team/sql-server-performance-dashboard-reports-unleashed-for-enterprise-monitoring/  #>
Start-Process "$($SSRSInstance -replace 'Server', 's')/report/$($NewSSRSReportFolder)/performance_dashboard_main"

