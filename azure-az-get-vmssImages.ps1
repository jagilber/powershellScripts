<#
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-get-vmImages.ps1" -outFile "$pwd/azure-az-get-vmImages.ps1";
    ./azure-az-get-vmImages.ps1 -resourceGroupName <resource group name> -nodeTypeName <node type name>
#>
param(
    [Parameter(Mandatory = $true)]
    $resourceGroupName = '',
    [Parameter(Mandatory = $true)]
    $nodeTypeName = '',
    $location = ''
)

Import-Module -Name Az.Compute
Import-Module -Name Az.Resources

function main() {
    $targetImageReference = $latestVersion = [version]::new(0, 0, 0, 0)
    $isLatest = $false
    $versionsBack = 0

    if (!$location) {
        $location = (Get-AzResourceGroup -Name $resourceGroupName).Location
    }

    $vmssHistory = @(Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName -OSUpgradeHistory)[0]

    if ($vmssHistory) {
        $targetImageReference = $vmssHistory.Properties.TargetImageReference
    }
    else {
        write-warning "vmssHistory not found. checking current image reference"
        $vmssHistory = Get-AzVmss -ResourceGroupName $resourceGroupName -Name $nodeTypeName
        $targetImageReference = $vmssHistory.VirtualMachineProfile.StorageProfile.ImageReference
    }

    $targetImageReference = $targetImageReference | convertto-json | convertfrom-json

    if (!$targetImageReference) {
        write-warning "vmssHistory not found. checking instance 0"
        $vmssVmInstance = get-azvmssvm -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -InstanceId 0
        $targetImageReference = $vmssVmInstance.StorageProfile.ImageReference
    }
    elseif (!$targetImageReference.ExactVersion) {
        write-warning "targetImageReference ExactVersion not found. checking instance 0"
        $vmssVmInstance = get-azvmssvm -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -InstanceId 0
        $targetImageReference.ExactVersion = $vmssVmInstance.StorageProfile.ImageReference.ExactVersion
    }

    if (!$targetImageReference) {
        write-error "current vm image version not found. exiting"
        #return
    }
    else {
        write-host "current running image on node type: " -ForegroundColor Green
        $targetImageReference
        $publisherName = $targetImageReference.Publisher
        $offer = $targetImageReference.Offer
        $sku = $targetImageReference.Sku
        $runningVersion = $targetImageReference.Version
        if ($runningVersion -ieq 'latest') {
            write-host "running version is 'latest'"
            $isLatest = $true
            $runningVersion = [version]::new(0, 0, 0, 0)
        }    
    }

    if ($publisherName -and $offer -and $sku) {
        write-host "Get-AzVmImage -Location $location -PublisherName $publisherName -offer $offer -sku $sku" -ForegroundColor Cyan
        $images = Get-AzVmImage -Location $location -PublisherName $publisherName -offer $offer -sku $sku
        write-host "available versions: " -ForegroundColor Green
        $images | format-table -Property Version, Skus, Offer, PublisherName
    
        foreach ($image in $images) {
            if ([version]$latestVersion -gt [version]$runningVersion) { $versionsBack++ }
            if ([version]$latestVersion -lt [version]$image.Version) { $latestVersion = $image.Version }
        }
    
        if ($isLatest) {
            write-host "published latest version: $latestVersion running version: 'latest'" -ForegroundColor Cyan
        }
        elseif ($versionsBack -gt 1) {
            write-host "published latest version: $latestVersion is $versionsBack versions newer than current running version: $runningVersion" -ForegroundColor Red
        }
        elseif ($versionsBack -eq 1) {
            write-host "published latest version: $latestVersion is newer than current running version: $runningVersion" -ForegroundColor Yellow
        }
        else {
            write-host "current running version: $runningVersion is same or newer than published latest version: $latestVersion" -ForegroundColor Green
        }
    }
    else {
        write-warning "publisherName, offer, and sku not found. exiting"
    }
}

main