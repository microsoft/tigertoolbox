<#
    .DESCRIPTION
    For all subscriptions accessible to the logged in user, enable Automatic Registration with SQL IaaS Agent Extension
    Equivalent to the GUI method of enablement shown here:
    https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-agent-extension-automatic-registration-all-vms?tabs=azure-cli
    
    .PREREQUISITES
    - The script needs to be run on Powershell 5.1 (Windows Only) and is incompatible with Powershell 6.x
    - The subscription whose VMs are to be registered, needs to be registered to Microsoft.SqlVirtualMachine resource provider first. This link describes
      how to register to a resource provider: https://docs.microsoft.com/azure/azure-resource-manager/resource-manager-supported-services
    - Run 'Connect-AzAccount' to first connect the powershell session to the azure account.
    - The Client credentials must have one of the following RBAC levels of access over the virtual machine being registered: Virtual Machine Contributor,Contributor or Owner
    - The user account running the script should have "Microsoft.SqlVirtualMachine/register/action" RBAC access over the subscriptions.
    - The user account running the script should have "Microsoft.Features/providers/features/register/action" RBAC access over the subscriptions.
    - The script requires Az powershell module (>=2.8.0) to be installed. Details on how to install Az module can be found 
      here : https://docs.microsoft.com/powershell/azure/install-az-ps?view=azps-2.8.0
      It specifically requires Az.Subscription module which comes as part of Az module (>=2.8.0) installation.
    - The script requires the EnableBySubscription script to be accessible and executable.

    .EXAMPLE
    Option 1: EnableAllSubscriptions
    Option 2: EnableSubscriptionList @('sub1guid','sub2guid',...)
    Option 3: EnableSubscriptionList [Enter] then enter paste in subscription guid when prompted
#>

using namespace System.Collections.Generic

function EnableAllSubscriptions (
) {
    
    $subscriptionIdList = [List[string]]@()

    # Get a list of all subscriptions to which the current user has access. 
    # NOTE: This step does not verify RBAC permissions. Subscriptions without adequate permission will output an error
    $subInAcc = Get-AzSubscription 

    # Build a string array containing the subscription GUIDs
    ForEach($sub in $subInAcc) 
    {
        $subName = $sub | Select-Object -ExpandProperty Name
        $subscriptionIdList.Add($sub)
    }

    # Pass the list of subs to the main function 
    EnableSubscriptionList -SubscriptionList $subscriptionIdList.ToArray()
}           
        
function EnableSubscriptionList {
    [CmdletBinding(DefaultParameterSetName = 'SubscriptionList')]
Param
(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $SubscriptionList
);

#Array of objects for storing failure subscriptionIds and failure reasons.
$FailedRegistrations = @();

# Register subscriptionIds to Automatic Registraion.
# https://docs.microsoft.com/th-th/powershell/azure/install-az-ps?view=azps-3.8.0#install-the-azure-powershell-module.
# Check if AzureRm is already installed and use that module if it is already available.
if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
    Write-Host "AzureRM is already installed. Registering using AzureRm commands";

    Write-Host "Please login to your account which have access to the listed subscriptions";
    $Output = Connect-AzureRmAccount -ErrorAction Stop;

    foreach ($SubscriptionId in $SubscriptionList) {
        Write-host "`n`n--------------------$SubscriptionId----------------------------`n`n";

        try {
            Write-Host "Setting powershell context to subscriptionid: $SubscriptionId";
            $Output = Set-AzureRmContext  -SubscriptionId $SubscriptionId -ErrorAction Stop;

            Write-Host "Registering subscription($SubscriptionId) to Microsoft.SqlVirtualMachine Resource provider";
            $Output = Register-AzureRmResourceProvider -ProviderNamespace Microsoft.SqlVirtualMachine -ErrorAction Stop;

            Write-Host "Registering subscription($SubscriptionId) to AFEC";
            $Output = Register-AzureRmProviderFeature -FeatureName BulkRegistration -ProviderNamespace Microsoft.SqlVirtualMachine -ErrorAction Stop;
        }
        Catch {
            $message = $_.Exception.Message;
            Write-Error "We failed due to complete $SubscriptionId operation because of the following reason: $message";

            # Store failed subscriptionId and failure reason.
            $FailedRegistration = @{ };
            $FailedRegistration.Add("SubscriptionId", $SubscriptionId);
            $FailedRegistration.Add("Errormessage", $message);
            $FailedRegistrations += New-Object -TypeName psobject -Property $FailedSubscriptionId;
        }
    };
    
} 
else {
    # Since AzureRm module is not availavle, we will use Az module.
    Write-Host "Installing Az powershell module if not installed already."
    Install-Module -Name Az -AllowClobber -Scope CurrentUser;

    Write-Host "Please login to your account which have access to the listed subscriptions";
    $Output = Connect-AzAccount -ErrorAction Stop;

    foreach ($SubscriptionId in $SubscriptionList) {
        Write-host "`n`n--------------------$SubscriptionId----------------------------`n`n"

        try {
            Write-Host "Setting powershell context to subscriptionid: $SubscriptionId";
            $Output = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop;

            Write-Host "Registering subscription($SubscriptionId) to Microsoft.SqlVirtualMachine Resource provider";
            $Output = Register-AzResourceProvider -ProviderNamespace Microsoft.SqlVirtualMachine -ErrorAction Stop;

            Write-Host "Registering subscription($SubscriptionId) to AFEC";
            $Output = Register-AzProviderFeature -FeatureName BulkRegistration -ProviderNamespace Microsoft.SqlVirtualMachine -ErrorAction Stop;
        }
        Catch {
            $message = $_.Exception.Message;
            Write-Error "We failed due to complete $SubscriptionId operation because of the following reason: $message";

            # Store failed subscriptionId and failure reason.
            $FailedRegistration = @{ };
            $FailedRegistration.Add("SubscriptionId", $SubscriptionId);
            $FailedRegistration.Add("Errormessage", $message);
            $FailedRegistrations += New-Object -TypeName psobject -Property $FailedSubscriptionId;
        }
    };
}

# Failed subscription registration and its reason will be stored in a csv file(RegistrationErrors.csv) for easy analysis.
# The file should be available in current directory where this .ps1 is executed
$FailedRegistrations | Export-Csv -Path RegistrationErrors.csv -NoTypeInformation
}


