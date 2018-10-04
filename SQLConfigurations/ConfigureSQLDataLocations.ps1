#  Copyright (c) Microsoft Corporation.  All rights reserved.
#  
# THIS SAMPLE CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# WHETHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# IF THIS CODE AND INFORMATION IS MODIFIED, THE ENTIRE RISK OF USE OR RESULTS IN
# CONNECTION WITH THE USE OF THIS CODE AND INFORMATION REMAINS WITH THE USER.

# The purpose of this script is 
# 1. Move all Data Files to E Drive of the Server 
# 2. Move all Log Files to F Drive of the Server 
# 3. Move Error Log and TraceFiles to E Drive of the Server 
# 4. Configure TempDB on the D Drive of the Server 
# 5. Configure backup on the F Drive of the Server
Try
{
    Import-Module sqlps -DisableNameChecking
    $SMOWmiserver = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $env:COMPUTERNAME         
    $ChangeService=$SMOWmiserver.Services | where {$_.name -eq "MSSQLSERVER"} 
    If($ChangeService.ServiceState -eq "Stopped")
    {
        $ChangeService.Start()
    }
    #Give Time for the Service to Start.
    start-sleep -Seconds 5

    Write-Host "****************Configuring the TempDB location and Files *********************"
    $TSQLScript = ""
    $TSQLScript = " ALTER DATABASE tempdb MODIFY FILE ( NAME = N'tempdev',FILENAME = N'D:\tempdev.mdf' , SIZE = 500MB , FILEGROWTH = 50MB) 
                    GO
                    ALTER DATABASE tempdb MODIFY FILE (NAME = N'templog', FILENAME = N'D:\templog.ldf', SIZE = 500MB, FILEGROWTH = 10MB)
                    Go
                    ALTER DATABASE tempdb Add FILE ( NAME = N'tempdev2',FILENAME = N'D:\tempdev2.ndf' , SIZE = 500MB , FILEGROWTH = 50MB)
                    GO
                    "
    # Execute the T-SQL script against the SQL Server instance
    Invoke-SqlCmd -ServerInstance . -Query $TSQLScript -Database "master" -verbose -QueryTimeout 0 | Out-File -filePath "C:\logs.txt"

    #Create Folders for the Data, Logs and Trace Files
    $datapath = "F:\Data\"
    $logpath = "G:\Logs\"
    $ErrorLog = "F:\ErrorLogs\"
    $BackupPath = "G:\Backups"

    [IO.Directory]::CreateDirectory($datapath)
    [IO.Directory]::CreateDirectory($logpath)
    [IO.Directory]::CreateDirectory($ErrorLog)
    [IO.Directory]::CreateDirectory($BackupPath)

    Write-Host "**************** Configuring Default Locations for the Server ************"
    $ChangeService.Refresh()
    $StartupPram = $ChangeService.StartupParameters.Split(';')
    $MasterDataFile = $StartupPram[0].Substring(2)
    $MasterLogFile = $StartupPram[2].Substring(2)
    # Stop SQL and Move the Master MDF/LDF Files
    $ChangeService.Stop()
    Start-Sleep 5
    [IO.File]::Copy($MasterDataFile, "F:\Data\Master.mdf")
    [IO.File]::Copy($MasterLogFile, "G:\Logs\Mastlog.ldf")
    #$ChangeService.StartupParameters = "-dE:\Data\Master.mdf;-eE:\ErrorLogs\Errorlog;-lF:\Logs\Mastlog.ldf"
    $ChangeService.Refresh()
    $ChangeService.Start()
    While ($ChangeService.ServiceState -ne "Running")
    {
        $ChangeService.Refresh()
    }
    #Change the Startup parameters and Instance Properties to reflect new locations
    $SQLObject = New-Object Microsoft.SqlServer.Management.Smo.Server($env:COMPUTERNAME)
    $SQLObject.Settings.BackupDirectory = $BackupPath
    $SQLObject.Settings.DefaultFile = $datapath
    $SQLObject.Settings.DefaultLog = $logpath
    $SQLObject.Alter()
    $SQLObject.Settings.Alter()
    
    #Change the SQL Server Startup Parameters -
    

    Write-Host "********* Moving the System DB's to the Data Drives **********"
    $CurrentFileLocations = $MasterDataFile.Substring(0,$MasterDataFile.Length-10)
    $SQLQuery = "ALTER DATABASE Model MODIFY FILE ( NAME = modeldev , FILENAME = 'F:\Data\model.mdf')
                Go
                ALTER DATABASE Model MODIFY FILE ( NAME = modellog , FILENAME = 'G:\Logs\modellog.ldf')
                Go
                ALTER DATABASE MSDB MODIFY FILE ( NAME = MSDBData , FILENAME = 'F:\Data\MSDBData.mdf')
                Go
                ALTER DATABASE MSDB MODIFY FILE ( NAME = MSDBLog , FILENAME = 'G:\Logs\MSDBLog.ldf')
                Go
                "
    Invoke-SqlCmd -ServerInstance . -Query $SQLQuery -Database "master" -verbose -QueryTimeout 0 | Out-File -filePath "C:\logs.txt"

    #Stop and Restart SQL for the values to take effect
    $ChangeService.Stop()
    Start-Sleep 30
    
    [IO.File]::Copy($CurrentFileLocations+"model.mdf", "F:\Data\model.mdf")
    [IO.File]::Copy($CurrentFileLocations+"modellog.ldf", "G:\Logs\modellog.ldf")
    [IO.File]::Copy($CurrentFileLocations+"MSDBData.mdf", "F:\Data\MSDBData.mdf")
    [IO.File]::Copy($CurrentFileLocations+"MSDBLog.ldf", "G:\Logs\MSDBLog.ldf")

    $ChangeService.Refresh()
    $ChangeService.Start()
    Start-Sleep 5
    While ($ChangeService.ServiceState -ne "Running")
    {
        $ChangeService.Refresh()
        $ChangeService.ServiceState
    }
    #Closing Try Block
}
Catch
{
    Write-Host "********** Erorr in configuration of the SQL Data Locations ************" -ForegroundColor Red
}