$token = $Global:token
$SubscriptionID = (Get-AzureRmSubscription).SubscriptionId
$baseURI = "https://management.azure.com" 
$suffixURI = "?api-version=2016-09-01" 
$SubscriptionURI = $baseURI + "/subscriptions/$($SubscriptionID)" + $suffixURI
$uri = $SubscriptionURI 
 $Body = @{
        'client_id'     = $applicationId
    }
$params = @{ 
    ContentType = 'application/x-www-form-urlencoded'
    Headers     = @{
        'authorization' = "Bearer $($Token.access_token)" 
    }
    Method      = 'Get' 
    uri         = $uri
    Body = $Body
} 
$response = Invoke-RestMethod @params 
$response | convertto-json 
