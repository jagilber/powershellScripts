<#
.SYNOPSIS
    use Repair-AzVmssServiceFabricUpdateDomain to clear any active mr jobs on service fabric scaleset
    https://docs.microsoft.com/en-us/powershell/module/az.compute/repair-azvmssservicefabricupdatedomain?view=azps-4.7.0
.FUNCTIONALITY
    Clear any active mr jobs on service fabric scaleset
    ReRun on all update domains until error like below is returned:
    Repair-AzVmssServiceFabricUD -ResourceGroupName <resource group> -VMScaleSetName nt0 -PlatformUpdateDomain 0
        Repair-AzVmssServiceFabricUpdateDomain: Cannot perform ForceRecoveryServiceFabricPlatformUpdateDomainWalk as there is no update pending.
        ErrorCode: OperationNotAllowed
        ErrorMessage: Cannot perform ForceRecoveryServiceFabricPlatformUpdateDomainWalk as there is no update pending.
        ErrorTarget: 
        StatusCode: 409
        ReasonPhrase: 
.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-repair-upgrade-domain.ps1" -outFile "$pwd\azure-az-sf-repair-upgrade-domain.ps1";
    .\azure-az-sf-repair-upgrade-domain.ps1 -resourceGroupName {{ resource group name }} -vmScaleSetName {{ vm scaleset name }}
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName = '',
    [Parameter(Mandatory = $true)]
    [string]$vmScaleSetName = '',
    [ValidateSet('-1', '0', '1', '2', '3', '4', '5')]
    [int]$platformUpdateDomain = 0,
    [switch]$force,
    [int]$sleeptime = 10,
    [switch]$checkForUpdates = $false
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'

if (!(get-module az.accounts)) {
    import-module az.accounts
}
if (!(get-module az.compute)) {
    import-module az.compute
}

if (!(@(Get-AzResourceGroup).Count)) {
    Connect-AzAccount
}


$updateDomain = 0
$maxUpdateDomain = (get-azvmss -ResourceGroupName $resourceGroupName -name $vmScaleSetName).PlatformFaultDomainCount

if ($platformUpdateDomain) {
    $updateDomain = $platformUpdateDomain
    $maxUpdateDomain = $platformUpdateDomain
    write-host "Repairing update domain $updateDomain only."
}

if ($checkForUpdates) {
    $updateDomain = -1
}

for ($updateDomain; $updateDomain -le $maxUpdateDomain) {
    $error.Clear()
    write-host "Repair-AzVmssServiceFabricUpdateDomain -ResourceGroupName $resourceGroupName `
        -VMScaleSetName $vmScaleSetName `
        -PlatformUpdateDomain $updateDomain
    "
    $result = Repair-AzVmssServiceFabricUpdateDomain -ResourceGroupName $resourceGroupName `
        -VMScaleSetName $vmScaleSetName `
        -PlatformUpdateDomain $updateDomain `
        -ErrorAction SilentlyContinue

    if ($checkForUpdates) {
        if ($error -and ($error | out-string) -imatch "'platformUpdateDomain' is out of range.") {
            write-host "there is an update pending. exiting."
        }
        
        if ($error -and ($error | out-string) -imatch "Cannot perform ForceRecoveryServiceFabricPlatformUpdateDomainWalk as there is no update pending.") {
            write-host "there is no update pending. exiting."
        }
        return
    }
    write-host "Result: $($result | Out-String)"
    
    if (!$result -or $error) {
        write-host "Error occurred: $($error | Out-String)"
        $updateDomain++
        if ($force) {
            write-host "Continuing to next update domain."
            continue
        }
        else {
            write-host "Stopping due to error. Use -force to continue processing."
            break
        }
    }

    write-host "Successfully repaired update domain $updateDomain"
    if ($result.NextPlatformUpdateDomain -eq $null) {
        write-host "No more update domains to process."
        break
    }
    else {
        write-host "Next platform update domain: $($result.NextPlatformUpdateDomain)"
        $updateDomain = $result.NextPlatformUpdateDomain
    }   
    write-host "start-sleep $sleeptime" # Adding a delay to avoid overwhelming the service
    Start-Sleep -Seconds $sleeptime
}

if ($updateDomain -ge $maxUpdateDomain) {
    write-host "All update domains processed successfully."
}
else {
    write-host "Processing stopped at update domain $updateDomain."
}
