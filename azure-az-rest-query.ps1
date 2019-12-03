<#
https://docs.microsoft.com/en-us/rest/api/
https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines
.\azure-az-rest-query.ps1 -query resources
.\azure-az-rest-query.ps1 -query resourceGroups
.\azure-az-rest-query.ps1 -query providers/Microsoft.Compute
#>

param(
    $token = $global:token,
    $SubscriptionID = (Get-azContext).Subscription.Id,
    $apiVersion = "2019-03-01",
    $baseURI = "https://management.azure.com/subscriptions/$($SubscriptionID)/",
    $query,
    $arguments,
    [ValidateSet("get","post","put")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded','application/json','application/xml')]
    $contentType = 'application/x-www-form-urlencoded',
    $clientid = $global:clientId,
    $body=@{},
    $headers=@{}
)

$epochTime = [int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds

if(!$token)
{
    write-warning "supply token for token argument or run azure-az-rest-logon.ps1 to generate bearer token"
    return
}
elseif($token.expires_on -le $epochTime)
{
    $token
    write-warning "expired token. run azure-az-rest-logon.ps1 to generate bearer token"
    $global:token = $null
    return
}

if($apiVersion)
{
    $uri = $baseURI + $query + "?api-version=" + $apiVersion + $arguments
}
else
{
    $uri = $baseURI + $query + $arguments
}

$uri

if($contentType -imatch "json")
{
    $body = convertto-json $body
}

$body

if($headers.Count -lt 1)
{
    $headers = @{
        'authorization' = "Bearer $($Token.access_token)" 
        'accept' = "*/*" #'application/json'
        'client_id' = $clientid
    }
}

$params = @{ 
    ContentType = $contentType
    Headers = $headers
    Method = $method 
    uri = $uri
    Body = $body
} 

$params
$error.Clear()
$response = Invoke-RestMethod @params -Verbose -Debug
#$response = Invoke-WebRequest @params -Verbose -Debug
$global:response = $response
write-host (ConvertTo-Json -Depth 99 ($global:response))
Write-Output $global:response
write-host "output saved in `$global:response" -ForegroundColor Yellow

if($error)
{
    return 1
}
