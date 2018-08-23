# example script to query service fabric api on localhost using self signed cert
# docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-index

Clear-Host
$ErrorActionPreference = "continue"
$result = $Null
$gatewayCertThumb = "CC6DBA5F0BE761AD6ED7F27485CBDC74355E5F0D"
$cert = Get-ChildItem -Path cert: -Recurse | Where-Object Thumbprint -eq $gatewayCertThumb
$startTime = ([datetime]"8/14/2018").ToString("yyyy-MM-ddTHH:mm:ssZ")
$endTime = ([datetime]"8/22/2018").ToString("yyyy-MM-ddTHH:mm:ssZ")

$timeoutSec = 100
$apiVer = "6.2-preview"
$host = "https://localhost:19080"

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

$url = "$($host)/EventsStore/Cluster/Events?$($eventArgs)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result

$url = "$($host)/EventsStore/Nodes/Events?$($eventArgs)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result

$url = "$($host)/EventsStore/Applications/Events?$($eventArgs)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result

$url = "$($host)/EventsStore/Services/Events?$($eventArgs)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result

$url = "$($host)/EventsStore/Partitions/Events?$($eventArgs)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result

$url = "$($host)/ImageStore?api-version=$($apiVer)&timeout=$($timeoutSec)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result
$result.StoreFiles
$result.StoreFolders


$url = "$($host)/$/GetClusterManifest?api-version=$($apiVer)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
#$result
$result.manifest
$result = $Null

$url = "$($host)/$/GetClusterHealth?api-version=$($apiVer)"
$result = Invoke-RestMethod -Method Get -Certificate $cert -Uri $url
$result
