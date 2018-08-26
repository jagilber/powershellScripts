# example script to query service fabric api on localhost using self signed cert
# docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-index

param(
    $gatewayCertThumb = "xxxxx",
    $startTime = (get-date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ"),
    $endTime = (get-date).ToString("yyyy-MM-ddTHH:mm:ssZ"),
    $timeoutSec = 100,
    $apiVer = "6.2-preview",
    $gatewayHost = "https://localhost:19080"
)

Clear-Host
$ErrorActionPreference = "continue"
$result = $Null
$cert = Get-ChildItem -Path cert: -Recurse | Where-Object Thumbprint -eq $gatewayCertThumb

# to bypass self-signed cert 
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;

    public class IDontCarePolicy : ICertificatePolicy {
            public IDontCarePolicy() {}
            public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate cert,
            WebRequest wRequest, int certProb) {
            return true;
        }
    }
"@

[System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy 

$eventArgs = "api-version=$($apiVer)&timeout=$($timeoutSec)&StartTimeUtc=$($startTime)&EndTimeUtc=$($endTime)"

$url = "$($gatewayHost)/EventsStore/Cluster/Events?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null


$url = "$($gatewayHost)/EventsStore/Nodes/Events?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null


$url = "$($gatewayHost)/EventsStore/Applications/Events?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null


$url = "$($gatewayHost)/EventsStore/Services/Events?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null


$url = "$($gatewayHost)/EventsStore/Partitions/Events?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null

$eventArgs = "api-version=$($apiVer)&timeout=$($timeoutSec)"
$url = "$($gatewayHost)/ImageStore?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result.StoreFiles
$result.StoreFolders
$result = $Null

$url = "$($gatewayHost)/$/GetClusterManifest?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
#$result |fl *
$result.manifest
$result = $Null

$url = "$($gatewayHost)/$/GetClusterHealth?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result |fl *
$result = $Null

$url = "$($gatewayHost)/Nodes?$($eventArgs)"
$result = Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
$result.items | fl *
