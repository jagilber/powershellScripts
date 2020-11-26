<#
.SYNOPSIS
    powershell script to update (patch) existing azure arm template resource settings similar to resources.azure.com

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-vmss-snapshot.ps1" -outFile "$pwd\azure-az-vmss-snapshot.ps1";
    .\azure-az-vmss-snapshot.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }}

.DESCRIPTION  
    powershell script to update (patch) existing azure arm template resource settings similar to resources.azure.com.

.NOTES  
    File Name  : azure-az-vmss-snapshot.ps1
    Author     : jagilber
    Version    : 201110
    History    : 

.EXAMPLE 
    .\azure-az-vmss-snapshot.ps1 -resourceGroupName clusterresourcegroup

#>

[cmdletbinding()]
param (
    #[Parameter(Mandatory=$true)]
    [string]$resourceGroupName = '',
    #[Parameter(Mandatory=$true)]
    [string]$location = '',
    [string]$vmssName = 'nt0',
    [int]$instanceId = 0,
    [string]$secretUrl = '',
    [string]$vaultResourceId = '',
    [string]$keyUrl = '',
    [string]$snapshotName = "$resourceGroupName-$vmssName-$instanceId-snapshot-$((get-date).tostring('yyMMddHHmmss'))",
    [bool]$encrypt = $false
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2

function main () {
    write-host "starting"

    write-host "New-AzSnapshotConfig -Location $location `
    -DiskSizeGB 100 `
    -AccountType Standard_LRS `
    -OsType Windows `
    -CreateOption Empty `
    -EncryptionSettingsEnabled $encrypt" -f green

    $snapshotconfig = New-AzSnapshotConfig -Location $location `
        -DiskSizeGB 100 `
        -AccountType Standard_LRS `
        -OsType Windows `
        -CreateOption Empty `
        -EncryptionSettingsEnabled $encrypt;

    if ($encrypt) {
        write-host "Set-AzSnapshotDiskEncryptionKey -Snapshot $snapshotconfig `
            -SecretUrl $secretUrl `
            -SourceVaultId $vaultResourceId" -f green

        $snapshotconfig = Set-AzSnapshotDiskEncryptionKey -Snapshot $snapshotconfig `
            -SecretUrl $secretUrl `
            -SourceVaultId $vaultResourceId;

        write-host "Set-AzSnapshotKeyEncryptionKey -Snapshot $snapshotconfig `
        -KeyUrl $keyUrl `
        -SourceVaultId $vaultResourceId" -f green

        $snapshotconfig = Set-AzSnapshotKeyEncryptionKey -Snapshot $snapshotconfig `
            -KeyUrl $keyUrl `
            -SourceVaultId $vaultResourceId;
    }

    write-host "New-AzSnapshot -ResourceGroupName $resourceGroupName `
    -SnapshotName $snapshotName `
    -Snapshot $snapshotconfig" -f green

    $global:snapshot = New-AzSnapshot -ResourceGroupName $resourceGroupName `
        -SnapshotName $snapshotName `
        -Snapshot $snapshotconfig;

    $global:snapshot | convertto-json

    write-host "Get-AzSnapshot -ResourceGroupName" -f green

    Get-AzSnapshot -ResourceGroupName
    
    write-host "results stored in `$global:snapshot" -f cyan
}

main

