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

    write-host "New-AzStorageAccountSASToken -Service $($service -join ',') `
        -ResourceType $($resourceType -join ',') `
        -StartTime $((get-date).AddMinutes(-1)) `
        -ExpiryTime $((get-date).AddHours($expirationHours)) `
        -Context [$($account.context)]$($blobUri) `
        -Protocol HttpsOnly `
        -Permission $permission
    " -ForegroundColor Cyan

    $sas = New-AzStorageAccountSASToken -Service $service `
        -ResourceType $resourceType `
        -StartTime (get-date).AddMinutes(-1) `
        -ExpiryTime (get-date).AddHours($expirationHours) `
        -Context $account.context `
        -Protocol HttpsOnly `
        -Permission $permission
    $sas
    $saskeys.Add("$blobUri$sas")
}

write-host "saskeys:" -ForegroundColor Yellow
$saskeys 