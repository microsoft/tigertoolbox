<#
.SYNOPSIS
    Check provided subscriptions with Automatic Registration feature. Output will be a table of subscription IDs and Registration Status
.DESCRIPTION
    Checking each subscription is a two step process:
        - Set the context to a subscription provided in subscription list or "all subscriptions"
        - Check subscription for the Automatic Registration feature.
    Prerequisites:
    - The user account running the script should have read access to all subscriptions in scope
    - Optional Switch -AddBulkScript will prepare a bulk registration script based on subscription IDs not enabled.
.EXAMPLE
    To review a list of Subscriptions
    .\Get-BulkRegistrationStatus.ps1 -SubscriptionList SubscriptionId1,SubscriptionId2
    To review all subscriptions
    .\Get-BulkRegistrationStatus.ps1
    To review all subscriptions and prepare Bulk Registration 
    .\Get-BulkRegistrationStatus.ps1 -AddBulkScript

#>
Param
(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [Guid[]]
    $SubscriptionList,
    [Parameter(Mandatory = $false)]
    [switch]
    $AddBulkScript

);

$WarningPreference='silentlycontinue'

#Array of objects for summary.
$Array = @();

#if all is select get all availible subscriptions
if ($SubscriptionList -eq $null) {$LookupSubscriptionList = $(Get-AzSubscription | Where-object {$_.State -ne "Disabled"})}
else {$LookupSubscriptionList = $SubscriptionList};

foreach ($SubscriptionId in $LookupSubscriptionList)
{

    Write-host "`n`n--------------------$SubscriptionId----------------------------`n`n"

    try {

            Write-Host "Setting powershell context to subscriptionid: $SubscriptionId";
            $Output = Set-AzContext -SubscriptionId $SubscriptionId;
            
            $Name = Get-AzSubscription -SubscriptionId $SubscriptionId | Select-Object -ExpandProperty name ;

            Write-Host "Checking subscription($SubscriptionId) for Microsoft.SqlVirtualMachine Resource provider";
    
            $Output = Get-AzProviderFeature -FeatureName BulkRegistration -ProviderNamespace Microsoft.SqlVirtualMachine  | Select-Object -ExpandProperty RegistrationState;
            Write-Host $SubscriptionId, $Output
            
            $message =$Output

            $i=1
        }

    catch 
    {
            $message = $_.Exception.Message;
            Write-Error "We failed due to complete $SubscriptionId operation because of the following reason: $message";
    }

    # Store  subscriptionId and Status.
    $Row = "" | select SubscriptionId, Name, Status
    $Row.SubscriptionID = $SubscriptionId
    $Row.Name = $Name
    $Row.Status = $message
    $Array +=$Row
};


#Display table of subscription IDs and status of bulk registration

Write-host "`n`n----------Summary of Auto Registration Status (Microsoft.SqlVirtualMachine Resource provider) ------------`n"
$Array | Format-Table


######################### Prepare Bulk Registration Script #################################

If ($AddBulkScript -eq $True)
{

    Write-host "`n --------- Bulk Registration Script ------------`n"

    if (($Array| Where-object {($_.Status -eq "NotRegistered")}).Count -eq 0)
        {
            write-host "All subscriptions are enabled."
        }
    else
        {

            $ofs =', '
            $tmp = $Array | Where Status -eq "NotRegistered" | Select-Object -ExpandProperty SubscriptionId

            Write-host "Download Bulk script from: https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-agent-extension-automatic-registration-all-vms?tabs=azure-cli#enable-for-multiple-subscriptions"
        
            Write-host "`n ----------------- Script --------------------`n"

            Write-host "Connect-AzAccount"
            Write-host ".\EnableBySubscription.ps1 $tmp" 

        }

}
