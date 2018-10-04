#  Copyright (c) Microsoft Corporation.  All rights reserved.
#  
# THIS SAMPLE CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# WHETHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
# IF THIS CODE AND INFORMATION IS MODIFIED, THE ENTIRE RISK OF USE OR RESULTS IN
# CONNECTION WITH THE USE OF THIS CODE AND INFORMATION REMAINS WITH THE USER.

# The purpose of this script is 
# 1. Configure Firewall Exceptions for SQL
# 2. Configure SQL to Listen on TCP post 1500 and 1501 (DAC)
# 3. Change SQL to Use Mixed Mode Authentication 
# 4. Rename SA Account
Try
{
    Import-Module sqlps -DisableNameChecking
    # Setup the SQL Server Connectivity
    $TCPPort = "1500" 
    $DACPort = "1501"

    #This Section of the Code is to add a firewall exception for Ports 1500 and 1501
    Write-Host "************************  Configure Firewall Exceptions ********************* " -ForegroundColor DarkYellow 
    # Prepare the arguments for the NETSH command
    $Arguments = "advfirewall firewall add rule name = SQLPort dir = in protocol = tcp action = allow localport = " + $TCPPort + " remoteip = ANY profile = PUBLIC"
    # Execute the command silently
    $p = Start-Process netsh -ArgumentList $Arguments -wait -NoNewWindow -PassThru
    $p.HasExited
    $p.ExitCode
    # Prepare the arguments for the NETSH command
    $Arguments = "advfirewall firewall add rule name = SQLDACPort dir = in protocol = tcp action = allow localport = " + $DACPort + " remoteip = ANY profile = PUBLIC"
    # Execute the command silently
    $p = Start-Process netsh -ArgumentList $Arguments -wait -NoNewWindow -PassThru
    $p.HasExited
    $p.ExitCode

    Write-Host "************************  Configure TCP Ports ********************* " -ForegroundColor DarkYellow 
    # Create a SMO object
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | out-null
    $MachineObject = New-Object ('Microsoft.SqlServer.Management.Smo.WMI.ManagedComputer') $env:COMPUTERNAME
    $tcp = $MachineObject.GetSMOObject("ManagedComputer[@Name='" + (Get-Item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']")
    if ($tcp.IsEnabled -ne "True")
    {
        $tcp.IsEnabled = $true
        $tcp.alter
        $MachineObject.GetSMOObject($tcp.urn.Value + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = $TCPPort
        $tcp.alter()
    }
    else
    {
        $MachineObject.GetSMOObject($tcp.urn.Value + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = $TCPPort
        $tcp.alter()
    }

    Write-Host "************************  Configure Mixed Mode Authentication ********************* " -ForegroundColor DarkYellow
    $SQLObject = New-Object Microsoft.SqlServer.Management.Smo.Server($env:COMPUTERNAME)
    $SQLObject.Settings.LoginMode = [Microsoft.SqlServer.Management.SMO.ServerLoginMode]::Mixed
    $SQLObject.Alter()
    $SQLObject.Settings.Alter()

    Write-Host "************************  Rename SA Login ********************* " -ForegroundColor DarkYellow
    $SQL = "ALTER LOGIN sa WITH NAME = OptimusPrime"
    Invoke-SqlCmd -ServerInstance . -Query $SQL -Database "master"
    $SQL = "ALTER LOGIN OptimusPrime WITH Password = 'LS1setup!'"
    Invoke-SqlCmd -ServerInstance . -Query $SQL -Database "master"
    $SQL = "ALTER LOGIN OptimusPrime Enable"
    Invoke-SqlCmd -ServerInstance . -Query $SQL -Database "master"
}
Catch
{
      Write-Host "********** Erorr Configuring TCP/Firewall Options ************" -ForegroundColor Red
}