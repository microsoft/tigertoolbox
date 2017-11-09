#  Copyright (c) Microsoft Corporation.  All rights reserved.
#  
# THIS SAMPLE CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# WHETHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# IF THIS CODE AND INFORMATION IS MODIFIED, THE ENTIRE RISK OF USE OR RESULTS IN
# CONNECTION WITH THE USE OF THIS CODE AND INFORMATION REMAINS WITH THE USER.

# The purpose of this script is to configure the SQL Server startup account and also enable 
# LPIM and IFI for the account.
# We would create a local user on the machine and use that as the startup account for SQL.
# For simplicity the account would be added to the builtin Administrator group.
Try
{
    $connect = [ADSI]"WinNT://localhost"
    $user = $connect.Create("User","SQLServiceAccount")
    $user.SetPassword("LS1setup!")
    $user.setinfo()
    $user.description = "SQL Server Startup Account"
    $user.SetInfo()
    #Add Account to the Admin Group
    $Admingroup = [ADSI]("WinNT://"+$env:COMPUTERNAME +"/administrators,group")
    $AdminGroup.Add("WinNT://"+$env:ComputerName +"/SQLServiceAccount,user")

    #Now Change SQL Server Startup Account and Restart the services.
    Import-Module sqlps -DisableNameChecking
    Start-Sleep -Seconds 10
    $SMOWmiserver = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $env:COMPUTERNAME
    $ChangeService=$SMOWmiserver.Services | where {$_.name -eq "MSSQLSERVER"}
    $UName=$env:COMPUTERNAME + "\SQLServiceAccount"
    $PWord="LS1setup!"            
    $ChangeService.SetServiceAccount($UName, $PWord)
}
Catch
{ 
  Write-Host "***Erorr Configuring the SQL Startup Account****" -ForegroundColor Red
}






