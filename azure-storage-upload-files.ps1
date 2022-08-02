<#
.SYNOPSIS
    powershell script to copy local folder structure to azure storage account
    returns sas
    https://docs.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-powershell

.PARAMETER resourceGroupName
    azure resource group name to temporarily store trace data
.PARAMETER containerName
    name of azure storage container
    expected format of fabriclogs-{{guid}}
    default fabriclogs-00000000-0000-0000-0000-000000000000
.PARAMETER storageAccountName
    name of azure storage account to temporarily store trace data
    expected name should be case number
.PARAMETER location
    name of azure location for resource group and storage account
.PARAMETER path
    path to local trace data. 
    expected $path subfolder structure: \{{node name}}\{{file type}}\{{.dtr|.etl|.zip trace file}}
.PARAMETER detail
    switch to enable verbose output
.PARAMETER sasExpirationHours
    number of hours before sas expiration
    default 24

.EXAMPLE
    expected $path subfolder structure: \{{node name}}\{{file type}}\{{.dtr|.etl|.zip trace file}}
    
    example $path: C:\temp\fabriclogs-692a8920-f760-4cc5-99fe-df48fbffc0c0 
    example file: C:\temp\fabriclogs-692a8920-f760-4cc5-99fe-df48fbffc0c0\_nt0_1\Fabric\d8511df4d4a1fb61dd6b829752e17ac5_fabric_traces_9.0.1048.9590_133033481041665715_36_00637946569006952231_0000000000.dtr

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-upload-files.ps1" -outFile "$pwd\azure-storage-upload-files.ps1";
    .\azure-storage-upload-files.ps1 -resourceGroupName {{resource group name}} -path {{path to folder containing files to upload}} -location {{location}}
#>

[cmdletbinding()]
param (
    [string]$resourceGroupName = 'fabriclogs-standalone',
    [string]$containerName = "fabriclogs-00000000-0000-0000-0000-000000000000", #"fabriclogs-$((get-date).tostring('yyMMddhh-mmss-ffff') + [guid]::NewGuid().tostring().Substring(18))",
    [string]$storageAccountName = "2200000000000000", #"sflogs$([math]::abs($containerName.gethashcode()))",
    [string]$location = 'eastus',
    [string]$path,
    [switch]$detail,
    [string]$sasExpirationHours = 24
)

set-strictMode -Version 3.0
$PSModuleAutoLoadingPreference = 2
$currentErrorActionPreference = $ErrorActionPreference
$currentVerbosePreference = $VerbosePreference
$global:fileCounter = 0

function main() {

    write-host "starting"
    write-parameters

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

    $global:sas = get-sas -expirationHours $sasExpirationHours
    $global:context = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $global:sas
    write-host "storage context: $global:context"

    if ((Get-AzStorageContainer $containerName -Context $global:context)) {
        write-host "container already exists: $containerName" -ForegroundColor Yellow
    }
    else {
        write-host "creating container: $containerName" -ForegroundColor Green
        New-AzStorageContainer -Name $containerName -Context $global:context
    }

    upload-files -path $path
    $global:bloburi = $global:context.StorageAccount.BlobEndPoint.AbsoluteUri + $containerName + $global:sas

    #Write-Progress -Completed -Activity "complete"
    write-host "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes`r`n"
    write-parameters
    write-host "sas:$($global:sas)" -ForegroundColor Cyan
    write-host "bloburi+sas:$($global:bloburi)" -ForegroundColor Green
    write-host "finished $(get-date)"
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

function get-sas($expirationHours) {
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $blobUri = $storageAccount.Context.BlobEndPoint
    write-host "creating sas for $blobUri" -ForegroundColor Green
    $service = 'blob'
    $resourceType = @('service', 'container', 'object')
    $permission = 'racwdlup'

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
        if (!($file.Attributes -imatch 'directory')) {
            write-host "checking file: $($file)"
            $relativeFile = $file.fullname.replace($path, '').replace('\', '/').TrimStart('/')
            write-host "relative path: $relativeFile"
            # temp until new collectsfdata build is pushed
            #$relativeFile = ([io.path]::GetDirectoryName($relativeFile).trim("\/") + "/" + $fileCounter + [io.path]::GetExtension($relativeFile)).replace('\', '/').Trim('/')
            
            if ($file.extension -ieq '.zip') {
                $tempFolder = $file.fullname.replace($file.extension,'') # "$path/$([io.path]::getfilenamewithoutextension($relativeFile))"
                if (!(test-path $tempFolder)) {
                    Expand-Archive -Path $file.fullname -DestinationPath $tempFolder -Force
                }
                # temp upload-blob -containerName $containerName -context $context -file $file.fullname -blobUri $relativeFile
                $tempFile = @(get-childitem -path $tempFolder)[0].fullname
                $newFileName = "$fileCounter$([io.path]::GetExtension($tempFile).replace('\', '/').Trim('/'))"
                rename-item -path $tempFile -NewName $newFileName
                $tempFile = @(get-childitem -path $tempFolder)[0].fullname
                $relativeFile = ([io.path]::GetDirectoryName($relativeFile).trim("\/") + "/" + $fileCounter + [io.path]::GetExtension($tempFile)).replace('\', '/').Trim('/')
                upload-blob -containerName $containerName -context $context -file $tempfile -blobUri $relativeFile
                remove-item -Path $tempFolder -Force -recurse
            }
            else {
                $tempFile = $file.fullname
                upload-blob -containerName $containerName -context $context -file $tempfile -blobUri $relativeFile
            }
            $global:fileCounter++
        }
    }
}

function upload-blob($containerName, $context, $file, $blobUri) {
    $BlobHT = @{
        File             = $file
        Container        = $ContainerName
        Blob             = $blobUri
        Context          = $Context
        StandardBlobTier = 'Cool'
        MetaData         = @{LastModified = '2022-08-02T14:00:00' }
    }

    write-host "Set-AzStorageBlobContent $($BlobHT | convertto-json)"
    Set-AzStorageBlobContent @BlobHT -Force
}

function write-parameters() {
    write-host "path: $path" -ForegroundColor Cyan
    write-host "total files: $global:fileCounter" -ForegroundColor Cyan
    write-host "resource group name: $resourceGroupName" -ForegroundColor Cyan
    write-host "container name: $containerName" -ForegroundColor Cyan
    write-host "storage account name: $storageAccountName" -ForegroundColor Cyan
    write-host "sas expiration hours: $sasExpirationHours ($((get-date).AddHours($sasExpirationHours).ToString('o')))" -ForegroundColor Yellow
}

main
$ErrorActionPreference = $currentErrorActionPreference
$VerbosePreference = $currentVerbosePreference
