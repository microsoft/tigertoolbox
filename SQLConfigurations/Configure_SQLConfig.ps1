#  Copyright (c) Microsoft Corporation.  All rights reserved.
#  
# THIS SAMPLE CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# WHETHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# IF THIS CODE AND INFORMATION IS MODIFIED, THE ENTIRE RISK OF USE OR RESULTS IN
# CONNECTION WITH THE USE OF THIS CODE AND INFORMATION REMAINS WITH THE USER.

# The purpose of this script is 
# 1. Configure the SQL Configuration Options - Max Server Memory, MAXDOP, Remote Admin Connection
# 2. Enable/Disable the following on the Model Database
#   2a. AutoShrink, AutoClose, Limit Autogrow
Try
{
        Write-Host "*************************  SQL Configuration Options *************************"
        $TSQLScript1 = "
        exec sp_configure 'show advanced options',1;
        reconfigure with override"
        $TSQLScript2 = "
        exec sp_configure 'remote admin connections',1;
        reconfigure with override"
        $TSQLScript3 = "
        exec sp_configure 'max server memory (MB)',5000;
        reconfigure with override"
        $TSQLScript4 = "
        exec sp_configure 'max degree of parallelism',1;
        reconfigure with override"

        # Execute the T-SQL script against the SQL Server instance
        Invoke-SqlCmd -ServerInstance . -Query $TSQLScript1 -Database "master"
        Invoke-SqlCmd -ServerInstance . -Query $TSQLScript2 -Database "master" 
        Invoke-SqlCmd -ServerInstance . -Query $TSQLScript3 -Database "master" 
        Invoke-SqlCmd -ServerInstance . -Query $TSQLScript4 -Database "master" 

        Write-Host "*************************  Model Database Options *************************"
        
        Invoke-SQLcmd -Query "ALTER DATABASE MODEL SET AUTO_CREATE_STATISTICS ON (INCREMENTAL = ON );" -ServerInstance . -Database "master" 
        Invoke-SQLcmd -Query "ALTER DATABASE MODEL SET AUTO_UPDATE_STATISTICS ON;" -ServerInstance . -Database "master" 
        Invoke-SQLcmd -Query "ALTER DATABASE MODEL SET AUTO_UPDATE_STATISTICS_ASYNC OFF;" -ServerInstance . -Database "master" 
        Invoke-SQLcmd -Query "ALTER DATABASE MODEL SET AUTO_SHRINK OFF;" -ServerInstance . -Database "master" 
        Invoke-SQLcmd -Query "ALTER DATABASE MODEL SET AUTO_CLOSE OFF;" -ServerInstance . -Database "master" 
}
Catch
{
      Write-Host "********** Erorr Configuring SQL Config Options ************" -ForegroundColor Red
}