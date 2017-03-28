# Helper functions to check if TLS 1.2 updates are required
# Script currently supports checking for the following:
# a. Check if SQL Server Native Client can support TLS 1.2
# b. Check if Microsoft ODBC Driver for SQL Server can support TLS 1.2
# This script is restricted to work on x64 and x86 platforms 

<#
    Fix list:
    v1.1: 
        Edit to use Win32Reg_AddRemovePrograms based on Issue reported by codykonior (Issue #20)
    v1.2: 
        Fixes to use Windows Registry as suggested by modsqlguy as an alternative (Issue #22)
        Fixes to account for 10.51.x version numbers for SQL Server 2008 R2 as reported by modsqlguy (Issue #23)
#>
Function Check-Sqlncli
{
    # Fetch the different Native Client installations found on the machine
    $sqlncli = Get-InstalledPrograms | Where-Object {$_.DisplayName -like "*Native Client*" -and $_.Publisher -like "*Microsoft*"} | Select DisplayName,DisplayVersion
    # Check and report if an update is required for each entry found
    foreach ($cli in $sqlncli)
    {
        # SQL Server 2012 and 2014
        if ($cli.DisplayVersion.Split(".")[2] -lt 6538 -and $cli.DisplayVersion.Split(".")[0] -eq 11)
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        # SQL Server 2008
        elseif ($cli.DisplayVersion.Split(".")[2] -lt 6543  -and $cli.DisplayVersion.Split(".")[1] -eq 0 -and $cli.DisplayVersion.Split(".")[0] -eq 10) 
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        # SQL Server 2008 R2
        elseif ($cli.DisplayVersion.Split(".")[2] -lt 6537 -and ($cli.DisplayVersion.Split(".")[1] -eq 50 -or $cli.DisplayVersion.Split(".")[1] -eq 51) -and $cli.DisplayVersion.Split(".")[0] -eq 10)
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        else
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " supports TLS 1.2" -ForegroundColor Green
        }
    }
}

Function Check-SqlODBC($server)
{
    # Fetch the different MS SQL ODBC installations found on the machine
    #$sqlodbc = Get-WmiObject -Class Win32reg_AddRemovePrograms | Where-Object {$_.DisplayName -like "*ODBC*" -and $_.Publisher -like "*Microsoft*"} | Select DisplayName,Version
    
    $sqlodbc = Get-InstalledPrograms | Where-Object {$_.DisplayName -like "*ODBC*" -and $_.Publisher -like "*Microsoft*"} | Select DisplayName,DisplayVersion
    # Check and report if an update is required for each entry found
    foreach ($cli in $sqlodbc)
    {
        # SQL Server 2012 and 2014
        if ($cli.DisplayVersion.Split(".")[2] -lt 4219 -and $cli.DisplayVersion.Split(".")[0] -eq 12)
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        else
        {
            Write-Host $cli.DisplayName "with version" $cli.DisplayVersion " supports TLS 1.2" -ForegroundColor Green
        }
    }
}

<#
  Get-InstalledPrograms code snippet is from https://blogs.technet.microsoft.com/heyscriptingguy/2011/11/13/use-powershell-to-quickly-find-installed-software/ 
#>
Function Get-InstalledPrograms()
{
    $array = @()
    
    #Define the variable to hold the location of Currently Installed Programs
    $UninstallKey=”SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall” 
    #Create an instance of the Registry Object and open the HKLM base key
    $reg=[microsoft.win32.registrykey]::OpenRemoteBaseKey(‘LocalMachine’, $env:COMPUTERNAME) 
    #Drill down into the Uninstall key using the OpenSubKey Method
    $regkey=$reg.OpenSubKey($UninstallKey) 
    #Retrieve an array of string that contain all the subkey names
    $subkeys=$regkey.GetSubKeyNames() 
    #Open each Subkey and use GetValue Method to return the required values for each
    foreach($key in $subkeys)
    {
        $thisKey=$UninstallKey+”\\”+$key 
        $thisSubKey=$reg.OpenSubKey($thisKey) 
        $obj = New-Object PSObject
        $obj | Add-Member -MemberType NoteProperty -Name “ComputerName” -Value $env:COMPUTERNAME
        $obj | Add-Member -MemberType NoteProperty -Name “DisplayName” -Value $($thisSubKey.GetValue(“DisplayName”))
        $obj | Add-Member -MemberType NoteProperty -Name “DisplayVersion” -Value $($thisSubKey.GetValue(“DisplayVersion”))
        $obj | Add-Member -MemberType NoteProperty -Name “InstallLocation” -Value $($thisSubKey.GetValue(“InstallLocation”))
        $obj | Add-Member -MemberType NoteProperty -Name “Publisher” -Value $($thisSubKey.GetValue(“Publisher”))
        $array += $obj
    } 
    return $array
   
}

# Call the functions

Check-Sqlncli $env:COMPUTERNAME
Check-SqlODBC $env:COMPUTERNAME
