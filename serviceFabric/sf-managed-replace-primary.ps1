<#
.SYNOPSIS
    powershell script to connect to replace managed service fabric cluster primary nodetype 

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-replace-primary.ps1" -outFile "$pwd/sf-managed-replace-primary.ps1";
    ./sf-managed-replace-primary.ps1 -clusterEndpoint <cluster endpoint fqdn> -thumbprint <thumbprint>
#>
param(
    [string]$resourceGroupName = '',
    [string]$json = "$pwd\current.json",
    [string]$clusterName = $resourceGroupName, #"mysfcluster",
    [string]$newNodeTypeName = "nt2",
    [string]$oldNodeTypeName = "nt1",
    [string]$vmSize = "Standard_D2_v2",
    [int]$instanceCount = 5,
    [bool]$isPrimary = $true,
    [switch]$whatIf
)
$ErrorActionPreference = 'Stop'
#export template
export-azresourcegroup -SkipAllParameterization -ResourceGroupName $resourceGroupName -Path $json #-Force

write-host "New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName ``
    -ClusterName $clusterName ``
    -Name $newNodeTypeName ``
    -InstanceCount $instanceCount ``
    -vmSize $vmSize ``
    -primary:$isPrimary
"

if (!$whatIf) {
    # add new node type
    New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName `
        -ClusterName $clusterName `
        -Name $newNodeTypeName `
        -InstanceCount $instanceCount `
        -vmSize $vmSize `
        -primary:$isPrimary
}

write-host "Remove-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName ``
    -ClusterName $clusterName ``
    -Name $oldNodeTypeName
"

if (!$whatIf) {
    # remove old node type
    Remove-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroupName `
        -ClusterName $clusterName `
        -Name $oldNodeTypeName
}

write-host 'finished'
