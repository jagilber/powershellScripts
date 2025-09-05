<# generate sas key #>
param(
    [Parameter(Mandatory = $true)]
    $resourceGroupName = '',
    $storageAccountName = '.',
    [ValidateSet('blob', 'file', 'table', 'queue')]
    $service = @('blob', 'file', 'table', 'queue'),
    [ValidateSet('service', 'container', 'object')]
    $resourceType = @('service', 'container', 'object'),
    $permission = 'racwdlup',
    $expirationHours = 8
)

$PSModuleAutoLoadingPreference = 2
write-host "Get-AzStorageAccount -ResourceGroupName $resourceGroupName" -ForegroundColor Cyan

$accounts = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName) | where-object StorageAccountName -imatch $storageAccountName
$saskeys = [collections.arraylist]::new()

foreach ($account in $accounts) {
    $blobUri = $account.Context.BlobEndPoint
    write-host "creating sas for $blobUri" -ForegroundColor Green

    # Get storage account keys to create proper context
    write-host "Getting storage account keys for $($account.StorageAccountName)" -ForegroundColor Yellow
    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $account.StorageAccountName
    $storageContext = New-AzStorageContext -StorageAccountName $account.StorageAccountName -StorageAccountKey $keys[0].Value

    write-host "New-AzStorageAccountSASToken -Service $($service -join ',') ``
        -ResourceType $($resourceType -join ',') ``
        -StartTime $((get-date).AddMinutes(-1)) ``
        -ExpiryTime $((get-date).AddHours($expirationHours)) ``
        -Context [StorageContext]$($blobUri) ``
        -Protocol HttpsOnly ``
        -Permission $permission
    " -ForegroundColor Cyan

    $sas = New-AzStorageAccountSASToken -Service $service `
        -ResourceType $resourceType `
        -StartTime (get-date).AddMinutes(-1) `
        -ExpiryTime (get-date).AddHours($expirationHours) `
        -Context $storageContext `
        -Protocol HttpsOnly `
        -Permission $permission
    
    # Ensure proper URL formatting with ? separator
    if ($sas.StartsWith('?')) {
        $sasUrl = "$($blobUri)$sas"
    } else {
        $sasUrl = "$($blobUri)?$sas"
    }
    
    write-host "Generated SAS URL: $sasUrl" -ForegroundColor Green
    $saskeys.Add($sasUrl)
}

$global:saskeys = $saskeys
write-host "`$global:saskeys" -ForegroundColor Yellow
$saskeys 
