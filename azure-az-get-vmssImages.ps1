<#
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-get-vmssImages.ps1" -outFile "$pwd/azure-az-get-vmssImages.ps1";
    ./azure-az-get-vmssImages.ps1 -resourceGroupName <resource group name> -nodeTypeName <node type name>
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [string]$clusterName = $resourceGroupName,
    [string]$nodeTypeName,
    [string]$publisherName = 'MicrosoftWindowsServer',
    [string]$offer = 'WindowsServer',
    [string]$sku,
    [int]$instanceId = -1
)

function main() {
    if (!(check-module)) { return }

    $targetImageReference = $latestVersion = [version]::new(0, 0, 0, 0)
    $isLatest = $false
    $versionsBack = 0

    $location = (Get-AzResourceGroup -Name $resourceGroupName).Location
    $cluster = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -ResourceName $clusterName -ExpandProperties -ErrorAction SilentlyContinue

    if (!$cluster) {
        write-host "checking for managed cluster"
        $cluster = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/managedclusters -ResourceName $clusterName -ExpandProperties
        $resourceGroupName = "SFC_$($cluster.Properties.clusterid)"
        $nodeTypes = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachineScaleSets -ExpandProperties
        $cluster.Properties | Add-Member -MemberType NoteProperty -Name 'nodeTypes' -Value $nodeTypes
    } 
    if (!$cluster) {
        write-error "cluster not found. specify -clusterName`r`n$($error | out-string)"
        exit
    }

    if (!$nodeTypeName) {
        write-host "node type name not specified. using first node type name: $($cluster.Properties.nodeTypes[0].name)" -ForegroundColor Yellow
        $nodeTypeName = $cluster.Properties.nodeTypes[0].name
    }

    $vmssHistory = @(Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName -OSUpgradeHistory)[0]

    if ($vmssHistory) {
        $targetImageReference = $vmssHistory.Properties.TargetImageReference
    }
    else {
        write-host "vmssHistory not found. checking current image reference"
        $vmssHistory = Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName
        $targetImageReference = $vmssHistory.VirtualMachineProfile.StorageProfile.ImageReference
    }

    $targetImageReference = $targetImageReference | convertto-json | convertfrom-json

    if (!$targetImageReference -or $instanceId -gt -1) {
        write-host "checking instance $instanceId"
        $vmssVmInstance = get-azvmssvm -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -InstanceId $instanceId
        $targetImageReference = $vmssVmInstance.StorageProfile.ImageReference
    }
    elseif (!$targetImageReference.ExactVersion) {
        if ($instanceId -lt 0) { $instanceId = 0 }
        write-host "targetImageReference ExactVersion not found. checking instance $instanceId"
        $vmssVmInstance = get-azvmssvm -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -InstanceId $instanceId
        $targetImageReference.ExactVersion = @($vmssVmInstance.StorageProfile.ImageReference.ExactVersion)[0]
    }

    if (!$targetImageReference) {
        write-error "current vm image version not found."
        #return
    }
    else {
        write-host "current running image on node type: " -ForegroundColor Green
        $targetImageReference
        $publisherName = $targetImageReference.Publisher
        $offer = $targetImageReference.Offer
        $sku = $targetImageReference.Sku
        $runningVersion = ($targetImageReference.ExactVersion, $targetImageReference.Version | select-object -first 1)
        if ($runningVersion -ieq 'latest') {
            write-host "running version is 'latest'"
            $isLatest = $true
            $runningVersion = [version]::new(0, 0, 0, 0)
        }    
    }
    
    write-host "Get-AzVmImage -Location $location -PublisherName $publisherName -offer $offer -sku $sku" -ForegroundColor Cyan
    $imageSkus = Get-AzVmImage -Location $location -PublisherName $publisherName -offer $offer -sku $sku
    $orderedSkus = [collections.generic.list[version]]::new()

    foreach ($image in $imageSkus) {
        [void]$orderedSkus.Add([version]::new($image.Version)) 
    }

    $orderedSkus = $orderedSkus | Sort-Object
    write-host "available versions: " -ForegroundColor Green
    $orderedSkus.foreach{ $psitem.ToString() }

    foreach ($sku in $orderedSkus) {
        if ([version]$sku -gt [version]$runningVersion) { $versionsBack++ }
        if ([version]$latestVersion -lt [version]$sku) { $latestVersion = $sku }
    }

    write-host
    
    if ($isLatest) {
        write-host "published latest version: $latestVersion running version: 'latest'" -ForegroundColor Cyan
    }
    elseif ($versionsBack -gt 1) {
        write-host "published latest version: $latestVersion is $versionsBack versions newer than current running version: $runningVersion" -ForegroundColor Red
    }
    elseif ($versionsBack -eq 1) {
        write-host "published latest version: $latestVersion is one version newer than current running version: $runningVersion" -ForegroundColor Yellow
    }
    else {
        write-host "current running version: $runningVersion is same or newer than published latest version: $latestVersion" -ForegroundColor Green
    }
}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-warning "azure module for Connect-AzAccount not installed."

        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.compute
            install-module az.resources

            if(!(get-module az.accounts)) { import-module az.accounts }
            if(!(get-module az.compute)) { import-module {az.compute}
            if(!(get-module az.resources)) { import-module {az.resources}
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    if(!(get-azResourceGroup)){
        Connect-AzAccount
    }

    if(!@(get-azResourceGroup).Count -gt 0){
        return $false
    }

    return $true
}

main
