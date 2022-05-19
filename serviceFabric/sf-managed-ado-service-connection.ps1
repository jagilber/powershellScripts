<#
.SYNOPSIS
    # service fabric managed cluster azure dev ops mitigation task for service fabric service connection using certificate authentication
    # sfmc uses a 'server thumbprint' managed by cluster that rotates regularly
    # this thumbprint is needed to connect to cluster 
    # currently there is no method to keep server thumbprint in sync with static connection information in ado
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-ado-service-connection.ps1" -outFile "$pwd/sf-managed-ado-service-connection.ps1";
    ./sf-managed-ado-service-connection.ps1
#>
[environment]::getenvironmentvariables()
#
# get service fabric service connection
#
$url = "$(System.CollectionUri)/$env:SYSTEM_TEAMPROJECTID/_apis/serviceendpoint/endpoints"
$adoAuthHeader = @{
    'authorization' = "Bearer $env:SYSTEM_ACCESSTOKEN"
    'content-type' = 'application/json'
}
$bodyParameters = @{
    'type'          = 'servicefabric'
    'api-version'   = '7.1-preview.4'
    'endpointNames' = $env:connectionName
}
$parameters = @{
    Uri         = $url
    Method      = 'GET'
    Headers     = $adoAuthHeader
    Erroraction = 'continue'
    Body        = $bodyParameters
}
write-host ($parameters | convertto-json)
write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($url)) -headers $adoAuthHeader"

$result = invoke-RestMethod @parameters
$result | Format-List *
write-host ($result | convertto-json)
$result.value | ConvertTo-Json

if ($result.value.count -gt 1) {
    write-error "more than one service connection found"
    return
}
if ($result.value.count -lt 1) {
    write-error "service connection not found"
    return
}
#
# get current sfmc server thumbprint
#
if (!(get-azresourcegroup)) {
    write-error "unable to enumerate resource groups"
    return
}
$serviceConnection = $result.value
$serviceConnectionThumbprint = $serviceConnection.authorization.parameters.servercertthumbprint
write-host "service connection thumbprint:$serviceConnectionThumbprint" -ForegroundColor Cyan

$serviceConnectionId = $serviceConnection.Id
$serviceConnectionFqdn = $serviceConnection.url.replace('tcp://', '')
write-host "$cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn"
$cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn

if (!$cluster) {
    write-error "unable to find cluster $clusterEndpoint"
    return
}
$cluster | ConvertTo-Json -Depth 99
$clusterId = $cluster.Id
write-host "(Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints" -ForegroundColor Green
$serverThumbprint = @((Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints)[0]

if (!$serverThumbprint) {
    write-error "unable to get server thumbprint"
    return
}
else {
    write-host "server thumbprint:$serverThumbprint" -ForegroundColor Cyan
}
#
# compare thumb from cluster vs connection
#
write-host "checking thumbprints:
    service connection thumbprint:$serviceConnectionThumbprint
    server thumbprint:$serverThumbprint
"
if ($serviceConnectionThumbprint -ieq $serverThumbprint) {
    return
}
else {
    write-warning "service connection server thumbprint has changed. attempting to update"
    $url += "/$($serviceConnectionId)?api-version=7.1-preview.4"
    write-host "$serviceConnection.authorization.parameters.servercertthumbprint = $serverThumbprint"
    $serviceConnection.authorization.parameters.servercertthumbprint = $serverThumbprint
    $parameters = @{
        Uri         = $url
        Method      = 'PUT'
        Headers     = $adoAuthHeader
        Erroraction = 'continue'
        Body        = ($serviceConnection | convertto-json -compress -depth 99)
    }
    write-host ($parameters | convertto-json)
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($url)) -headers $adoAuthHeader"
    $error.clear()
    $result = invoke-RestMethod @parameters
    $result | Format-List *
    write-host ($result | convertto-json -Depth 99)
    if ($error) {
        write-error "error updating service endpoint $($error)"
    }
    else {
        write-host "endpoint updated successfully"
    }
}
write-host "finished"