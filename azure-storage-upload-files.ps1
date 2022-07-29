<#
.SYNOPSIS
    powershell script to copy local folder structure to azure storage account
    returns sas
    https://docs.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-powershell

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-upload-files.ps1" -outFile "$pwd\azure-storage-upload-files.ps1";
    .\azure-storage-upload-files.ps1 -resourceGroupName {{ resource group name }} -path {{ path to folder containing files to upload}}

#>

[cmdletbinding()]
param (
    [string]$resourceGroupName = 'fabriclogs-standalone',
    [string]$containerName = 'fabriclogs-220000000000000',
    [string]$storageAccountName = "sflogs$($resourceGroupName.gethashcode())", # [toLower( concat('sflogs', uniqueString(resourceGroup().id),'2'))]
    [string]$location = 'eastus',
    [string]$path,
    [switch]$detail,
    [switch]$force
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference

function main() {
    write-host "starting"
    write-host "resource group name: $resourceGroupName" -ForegroundColor Cyan
    write-host "container name: $containerName" -ForegroundColor Cyan
    write-host "storage account name: $storageAccountName" -ForegroundColor Cyan
    write-host "path: $path" -ForegroundColor Cyan

    if ($detail) {
        $ErrorActionPreference = 'continue'
        $VerbosePreference = 'continue'
    }

    if (!$path -or !(test-path $path)) {
        write-error "verify `$path. path not found: $path"
        return
    }

    if (!(check-module)) {
        return
    }
    
    if (!(@(Get-AzResourceGroup).Count)) {
        write-host "connecting to azure"
        Connect-AzAccount
    }

    $global:startTime = get-date

    if (!$resourceGroupName -or !$location) {
        write-error 'specify resourceGroupName and location'
        return
    }

    if ((Get-AzResourceGroup $resourceGroupName)) {
        write-host "resource group already exists: $resourceGroupName" -ForegroundColor Yellow
    }
    else {
        write-host "creating resource group: $resourceGroupName" -ForegroundColor Green
        New-AzResourceGroup -Name $resourceGroupName -Location $location
    }

    if ((Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName)) {
        write-host "storage account already exists: $storageAccountName" -ForegroundColor Yellow
    }
    else {
        write-host "creating storage account: $storageAccountName" -ForegroundColor Green
        New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -Location $location -SkuName Standard_LRS
    }

    $global:sas = get-sas
    $context = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $global:sas
    write-host "storage context: $context"

    if ((Get-AzStorageContainer $containerName -Context $context)) {
        write-host "container already exists: $containerName" -ForegroundColor Yellow
    }
    else {
        write-host "creating container: $containerName" -ForegroundColor Green
        New-AzStorageContainer -Name $containerName -Context $context
    }

    if (!(upload-files -path $path)) {
        return
    }

    #Write-Progress -Completed -Activity "complete"
    write-host "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
    write-host "sas:$($global:sas)"
    write-host 'finished.' -ForegroundColor Cyan
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
            install-module az.resources
            install-module az.storage

            import-module az.accounts
            import-module az.resources
            import-module az.storage
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    return $true
}

function get-sas() {
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $blobUri = $storageAccount.Context.BlobEndPoint
    write-host "creating sas for $blobUri" -ForegroundColor Green
    $service = 'blob'
    $resourceType = @('service', 'container', 'object')
    $permission = 'racwdlup'
    $expirationHours = 24

    write-host "New-AzStorageAccountSASToken -Service $($service -join ',') `
        -ResourceType $($resourceType -join ',') `
        -StartTime $((get-date).AddMinutes(-1)) `
        -ExpiryTime $((get-date).AddHours($expirationHours)) `
        -Context [$($storageAccount.context)]$($blobUri) `
        -Protocol HttpsOnly `
        -Permission $permission
    " -ForegroundColor Cyan

    $sas = New-AzStorageAccountSASToken -Service $service `
        -ResourceType $resourceType `
        -StartTime (get-date).AddMinutes(-1) `
        -ExpiryTime (get-date).AddHours($expirationHours) `
        -Context $storageAccount.context `
        -Protocol HttpsOnly `
        -Permission $permission
    write-host "returning sas: $sas"
    return $sas
}

function upload-files() {
    # copy files
    write-host "enumerating files in path: $path"
    $files = @(Get-ChildItem -Recurse -Path $path)
    if (!$files) {
        write-error "no files found"
        return $false
    }
    foreach ($file in $files) {
        write-host "checking file: $($file)"
        $relativeFile = $file.fullname.replace($path, '').replace('\', '/')
        write-host "relative path: $relativeFile"
        upload-blob -containerName $containerName -context $context -file $file -blobUri $relativeFile
    }
}

function upload-blob($containerName, $context, $file, $blobUri) {
    # upload another file to the Cool access tier
    $BlobHT = @{
        File             = $file.fullname
        Container        = $ContainerName
        Blob             = $blobUri
        Context          = $Context
        StandardBlobTier = 'Cool'
    }
    write-host "Set-AzStorageBlobContent $($BlobHT | convertto-json)"
    Set-AzStorageBlobContent @BlobHT
}

main
$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference

