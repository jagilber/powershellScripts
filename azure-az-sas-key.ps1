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
    $expirationDays = 7
)

$accounts = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName) | where-object StorageAccountName -imatch $storageAccountName
$saskeys = [collections.arraylist]::new()

foreach ($account in $accounts) {
    $blobUri = $account.Context.BlobEndPoint

    $sas = New-AzStorageAccountSASToken -Service $service `
        -ResourceType $resourceType `
        -StartTime (get-date).AddMinutes(-1) `
        -ExpiryTime (get-date).AddDays($expirationDays) `
        -Context $account.context `
        -Protocol HttpsOnly `
        -Permission $permission
    $sas
    $saskeys.Add("$blobUri$sas")
}

write-host "saskeys:" -ForegroundColor Yellow
$saskeys 