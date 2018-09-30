<#
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfrp-api-clusters_get
#/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ServiceFabric/clusters/{clusterName}?api-version=2016-09-01
#>

param(
[object]$token = $global:token,
[string]$SubscriptionID = "$((Get-AzureRmSubscription).Id)",
[string]$baseURI = "https://management.azure.com" ,
[string]$suffixURI = "?api-version=2016-09-01" ,
[string]$resourceGroup,
[string]$clusterName
)


if($resourceGroup -and $clusterName)
{
    [string]$SubscriptionURI = $baseURI + "/subscriptions/$($SubscriptionID)/resourceGroups/$($resourceGroup)/providers/Microsoft.ServiceFabric/clusters/$($clusterName)" + $suffixURI
}
else
{
    [string]$SubscriptionURI = $baseURI + "/subscriptions/$($SubscriptionID)/providers/Microsoft.ServiceFabric/clusters" + $suffixURI
}


$uri = $SubscriptionURI 
$uri 


 $Body = @{
        'client_id'     = $applicationId
    }
$params = @{ 
    ContentType = 'application/x-www-form-urlencoded'
    Headers     = @{
        'authorization' = "Bearer $($token.access_token)" 
        'accept' = 'application/json'
    }
    Method      = 'Get' 
    uri         = $uri
    Body = $Body
} 

$params
$params.Body.client_id
$params.Headers.authorization

$response = Invoke-RestMethod @params -Verbose -Debug
$response | convertto-json 

$global:response = $response
$response
$global:response
$global:response.value.properties | ConvertTo-Json
