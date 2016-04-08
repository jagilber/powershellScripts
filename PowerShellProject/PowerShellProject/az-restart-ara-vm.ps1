#Add-AzureAccount
#Get-AzureSubscription
$sub = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Set-AzureSubscription -SubscriptionId $sub
$raCollections = Get-AzureRemoteAppCollection

foreach($raCollection in Get-AzureRemoteAppCollection)
{

    Write-Host $raCollection.Name
    $raSessions = Get-AzureRemoteAppSession -CollectionName $raCollection.Name
    $raSessions

    $id = Restart-AzureRemoteAppVM  -CollectionName $raCollection.Name -UserUpn jagilber@microsoft.com
    $id
}


Get-AzureRemoteAppOperationResult 