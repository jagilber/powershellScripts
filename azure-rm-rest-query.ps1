param(
    $token = $Global:token,
    $SubscriptionID = (Get-AzureRmContext).Subscription.Id,
    $apiVersion = "2016-09-01",
    $baseURI = "https://management.azure.com/subscriptions/$($SubscriptionID)/",
    $query,
    $arguments,
    [ValidateSet("get","post","put")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded','application/json')]
    $contentType = 'application/json',
    $clientid,
    $body=@{}
)

[net.servicePointManager]::Expect100Continue = $true
[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12
$uri = $baseURI + $query + "?api-version=" + $apiVersion + $arguments
$uri

if($contentType -imatch "json")
{
    $body = convertto-json $body
}

$body

$params = @{ 
    ContentType = $contentType
    Headers     = @{
        'authorization' = "Bearer $($Token.access_token)" 
        'accept' = 'application/json'
        'client_id' = $clientid
    }

    Method      = $method 
    uri         = $uri
    Body = $body
} 

$params

$response = Invoke-RestMethod @params -Verbose -Debug
$global:response = $response
write-host (ConvertTo-Json -Depth 99 ($global:response))
Write-Output $global:response
