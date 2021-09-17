<#
.SYNOPSIS
    Register provided subscriptions with Automatic Registraion feature. Failed registration information will be stored in RegistrationErrors.csv
    file in the current directory where this script is executed. RegistrationErrors.csv will be empty when there are no errors in subscription registration.
.DESCRIPTION
    Registering each subscription is a two step process:
        -Register subscription to Microsoft.SqlVirtualMachine Resource provider.
        -Register subscription to the Automatic Registraion feature.
    By default (no subscriptions are specified), all subscription in the account will be registered.
    Prerequisites:
    - The user account running the script should have "Microsoft.SqlVirtualMachine/register/action" RBAC access over the subscriptions.
    - The user account running the script should have "Microsoft.Features/providers/features/register/action" RBAC access over the subscriptions.

.EXAMPLE
    To register list of Subscriptions
    .\EnableBySubscription.ps1 -SubscriptionList SubscriptionId1,SubscriptionId2
    To register all subscriptions the user account has access to
    .\EnableBySubscription.ps1

#>
Param
(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [Guid[]]$SubscriptionList
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
    
    If (!$SubscriptionList) {
        [Guid[]]$SubscriptionList = $null
        Get-AzureRmSubscription | ForEach-Object -Process {$SubscriptionList += $_.Id}
    }

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
    
    If (!$SubscriptionList) {
        [Guid[]]$SubscriptionList = $null
        Get-AzSubscription | ForEach-Object -Process {$SubscriptionList += $_.Id}
    }

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
