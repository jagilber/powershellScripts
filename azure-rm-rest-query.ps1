<#
https://docs.microsoft.com/en-us/rest/api/
https://docs.microsoft.com/en-us/rest/api/compute/virtualmachines
.\azure-rm-rest-query.ps1 -query resources
.\azure-rm-rest-query.ps1 -query resourceGroups
.\azure-rm-rest-query.ps1 -query providers/Microsoft.Compute
#>

param(
    $token = $global:token,
    $SubscriptionID = (Get-AzureRmContext).Subscription.Id,
    $apiVersion = "2016-09-01",
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
    write-warning "supply token for token argument or run azure-rm-rest-logon.ps1 to generate bearer token"
    return
}
else 
{
    if($token.expires_on -le $epochTime)
    {
        $token
        write-warning "expired token. run azure-rm-rest-logon.ps1 to generate bearer token"
        $global:token = $null
        return
    }
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

if($headers.count -gt 0)
{
    <#
    #.\azure-rm-rest-query.ps1 -baseURI https://management.core.windows.net/bedf79d7-6500-409e-b475-c4d0003bb6a7/services/hostedservices -token $global:token -headers @{"x-ms-version" = "2014-05-01" } -apiVersion $null
    if(!$headers.contains('authorization'))
    {
        $headers.Add('authorization',"Bearer $($Token.access_token)")
    }
    if(!$headers.contains('accept'))
    {
        $headers.Add('accept',$contentType)
    }
    if(!$headers.contains('client_id'))
    {
        $headers.Add('client_id', $clientid)
    }
    #>
}
else
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
$global:response = $response
write-host (ConvertTo-Json -Depth 99 ($global:response))
Write-Output $global:response
write-host "output saved in `$global:response" -ForegroundColor Yellow

if($error)
{
    exit 1
}
