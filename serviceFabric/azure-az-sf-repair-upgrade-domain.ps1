<#
.SYNOPSIS
    use Repair-AzVmssServiceFabricUpdateDomain to clear any active mr jobs on service fabric scaleset
    https://docs.microsoft.com/en-us/powershell/module/az.compute/repair-azvmssservicefabricupdatedomain?view=azps-4.7.0

    .LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-repair-upgrade-domain.ps1" -outFile "$pwd\azure-az-sf-repair-upgrade-domain.ps1";
    .\azure-az-sf-repair-upgrade-domain.ps1 -resourceGroupName {{ resource group name }} -vmScaleSetName {{ vm scaleset name }}
#>

param(
    [Parameter(Mandatory = $true)]
    $resourceGroupName = '',
    [Parameter(Mandatory = $true)]
    $vmScaleSetName = '',
    $platformUpdateDomain = ''
)

$PSModuleAutoLoadingPreference = 2

if (!(get-module az.accounts)) {
    import-module az.accounts
}
if (!(get-module az.compute)) {
    import-module az.compute
}

if (!(get-azcontext)) {
    Connect-AzAccount
}

$updateDomains = @($platformUpdateDomain)

if (!$platformUpdateDomain) {
    $updateDomains = @(0..(get-azvmss -ResourceGroupName $resourceGroupName -name $vmScaleSetName).Sku.Capacity)
}

foreach ($updateDomain in $updateDomains) {

    write-host "Repair-AzVmssServiceFabricUpdateDomain -ResourceGroupName $resourceGroupName `
        -VMScaleSetName $vmScaleSetName `
        -PlatformUpdateDomain $updateDomain
    "
    Repair-AzVmssServiceFabricUpdateDomain -ResourceGroupName $resourceGroupName `
        -VMScaleSetName $vmScaleSetName `
        -PlatformUpdateDomain $updateDomain

}
