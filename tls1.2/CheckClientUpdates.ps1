# Helper functions to check if TLS 1.2 updates are required
# Script currently supports checking for the following:
# a. Check if SQL Server Native Client can support TLS 1.2
# b. Check if Microsoft ODBC Driver for SQL Server can support TLS 1.2
# This script is restricted to work on x64 and x86 platforms 
Function Check-Sqlncli()
{
    # Fetch the different Native Client installations found on the machine
    $sqlncli = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*Native Client*"} | Select Name,Version
    # Check and report if an update is required for each entry found
    foreach ($cli in $sqlncli)
    {
        # SQL Server 2012 and 2014
        if ($cli.Version.Split(".")[2] -lt 6538 -and $cli.Version.Split(".")[0] -eq 11)
        {
            Write-Host $cli.Name "with version" $cli.Version " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        # SQL Server 2008
        elseif ($cli.Version.Split(".")[2] -lt 6543  -and $cli.Version.Split(".")[1] -eq 0 -and $cli.Version.Split(".")[0] -eq 10) 
        {
            Write-Host $cli.Name "with version" $cli.Version " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        # SQL Server 2008 R2
        elseif ($cli.Version.Split(".")[2] -lt 6537 -and $cli.Version.Split(".")[1] -eq 50 -and $cli.Version.Split(".")[0] -eq 10)
        {
            Write-Host $cli.Name "with version" $cli.Version " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        else
        {
            Write-Host $cli.Name "with version" $cli.Version " supports TLS 1.2" -ForegroundColor Green
        }
    }
}

Function Check-SqlODBC()
{
    # Fetch the different MS SQL ODBC installations found on the machine
    $sqlodbc = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*ODBC*"} | Select Name,Version
    # Check and report if an update is required for each entry found
    foreach ($cli in $sqlodbc)
    {
        # SQL Server 2012 and 2014
        if ($cli.Version.Split(".")[2] -lt 4219 -and $cli.Version.Split(".")[0] -eq 12)
        {
            Write-Host $cli.Name "with version" $cli.Version " needs to be updated to use TLS 1.2" -ForegroundColor Red
        }
        else
        {
            Write-Host $cli.Name "with version" $cli.Version " supports TLS 1.2" -ForegroundColor Green
        }
    }
}

# Call the functions
Check-Sqlncli
Check-SqlODBC
