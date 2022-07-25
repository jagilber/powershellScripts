<#
# example script to query service fabric api on localhost using self signed cert
# docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-index

[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-rest-api-self-signed.ps1" -outFile "$pwd/sf-rest-api-self-signed.ps1";
./sf-rest-api-self-signed.ps1

#>
param(
    $gatewayCertThumb = "xxxxx",
    $startTime = (get-date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ"),
    $endTime = (get-date).ToString("yyyy-MM-ddTHH:mm:ssZ"),
    $timeoutSec = 100,
    $apiVer = "6.2-preview",
    $gatewayHost = "https://localhost:19080",
    [ValidateSet('CurrentUser', 'LocalMachine')]
    $store = 'CurrentUser'
)

Clear-Host
$ErrorActionPreference = "continue"

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

function main() {
    $result = $Null
    $cert = Get-ChildItem -Path cert:\$store -Recurse | Where-Object Thumbprint -eq $gatewayCertThumb

    $eventArgs = "api-version=$($apiVer)&timeout=$($timeoutSec)&StartTimeUtc=$($startTime)&EndTimeUtc=$($endTime)"

    $url = "$($gatewayHost)/EventsStore/Cluster/Events?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null


    $url = "$($gatewayHost)/EventsStore/Nodes/Events?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null


    $url = "$($gatewayHost)/EventsStore/Applications/Events?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null


    $url = "$($gatewayHost)/EventsStore/Services/Events?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null


    $url = "$($gatewayHost)/EventsStore/Partitions/Events?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null

    $eventArgs = "api-version=$($apiVer)&timeout=$($timeoutSec)"
    $url = "$($gatewayHost)/ImageStore?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result.StoreFiles
    $result.StoreFolders
    $result = $Null

    $url = "$($gatewayHost)/$/GetClusterManifest?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    #$result |fl *
    $result.manifest
    $result = $Null

    $url = "$($gatewayHost)/$/GetClusterHealth?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result | Format-List *
    $result = $Null

    $url = "$($gatewayHost)/Nodes?$($eventArgs)"
    $result = call-rest -url $url -cert $cert
    $result.items | Format-List *
}

function call-rest($url,$cert){
    write-host "Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url" -ForegroundColor Cyan
    return Invoke-RestMethod  -TimeoutSec 30 -UseBasicParsing -Method Get -Certificate $cert -Uri $url
}
main