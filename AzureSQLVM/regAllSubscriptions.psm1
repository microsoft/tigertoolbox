<#
    .SYNOPSIS
    For all subscriptions accessible to the logged in user, ebable SQL IaaS extention at the sbubscrption level.

    .DESCRIPTION
    Identify and register all Azure VM running SQL Server on Windows for all the subscriptions which are accessible to the user.
    The cmdlet generates a list of available sunscriptions and invokes the bulk registration script to register all Azure VMs registers the VMs running SQL Server on Windows with SQL VM Resource provider

    Prerequisites:
    - The script needs to be run on Powershell 5.1 (Windows Only) and is incompatible with Powershell 6.x
    - The subscription whose VMs are to be registered, needs to be registered to Microsoft.SqlVirtualMachine resource provider first. This link describes
      how to register to a resource provider: https://docs.microsoft.com/azure/azure-resource-manager/resource-manager-supported-services
    - Run 'Connect-AzAccount' to first connect the powershell session to the azure account.
    - The Client credentials must have one of the following RBAC levels of access over the virtual machine being registered: Virtual Machine Contributor,
      Contributor or Owner
    - The script requires Az powershell module (>=2.8.0) to be installed. Details on how to install Az module can be found 
      here : https://docs.microsoft.com/powershell/azure/install-az-ps?view=azps-2.8.0
      It specifically requires Az.Subscription module which comes as part of Az module (>=2.8.0) installation.
    - The script requires the EnableBySubscription script to be accessible and executable.
#>

function RegAllSubscriptions(
) {
    $subscriptionNameList = [System.Collections.ArrayList]@()
    $subscriptionIdList = [System.Collections.ArrayList]@()
        $subInAcc = Get-AzSubscription 
       ForEach($sub in $subInAcc) 
       {
            $subName = $sub | Select-Object -ExpandProperty Name
            $tmp = $subscriptionNameList.Add('"'+$subName+'"') 
            $subId = $sub | Select-Object -ExpandProperty Id
            $tmp1 = $subscriptionIdList.Add('"'+$subId+'"')
        }
    EnableBySubscription -SubscriptionList $subscriptionIdList
    write-output "Subscription List : "
    return , $subscriptionList
}           
        