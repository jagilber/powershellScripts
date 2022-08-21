<#
# example script to disable service fabric node using sf rest
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-api-disablenode

[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-rest-disable-node.ps1" -outFile "$pwd/sf-rest-disable-node.ps1";
./sf-rest-disable-node.ps1

#>
param(
    [Parameter(Mandatory = $true)]
    $gatewayHost = "https://localhost:19080",
    [Parameter(Mandatory = $true)]
    $gatewayCertThumb = "xxxxx",
    [Parameter(Mandatory = $true)]
    $nodeName,
    [ValidateSet('Pause', 'Restart', 'RemoveData')]
    [Parameter(Mandatory = $true)]
    $deactivationIntent,
    $timeoutSec = 100,
    $apiVer = "6.2-preview",
    [ValidateSet('CurrentUser', 'LocalMachine')]
    $store = 'CurrentUser',
    $certificatePath = '',
    $certificatePassword = ''
)

Clear-Host
$ErrorActionPreference = "continue"
$VerbosePreference = 'continue'
$clusterEndpointPort = '19080'

function main() {
    if ($PSVersionTable.PSEdition -ine 'core') {
        set-callback
    }

    $managementEndpoint = $gatewayHost.Replace("19000", "19080").Replace("https://", "")
    $clusterFqdn = [regex]::match($managementEndpoint, "(?:http.//|^)(.+?)(?:\:|$|/)").Groups[1].Value

    if ($managementEndpoint -inotmatch ':\d{2,5}$') {
        $managementEndpoint = "$($managementEndpoint):$($clusterEndpointPort)"
    }
    else {
        $clusterEndpointPort = [regex]::match($managementEndpoint, ':(\d{2,5})$').Groups[1].Value
    }
    
    write-host "Test-NetConnection -ComputerName $clusterFqdn -Port $clusterendpointPort" -ForegroundColor Cyan
    $result = Test-NetConnection -ComputerName $clusterFqdn -Port $clusterendpointPort
    write-host ($result | out-string)
    
    if (!$result) {
        write-error "unable to connect to $managementEndpoint"
        return
    }

    $result = $Null
    $error.Clear()

    if ($certificatePath -and (test-path $certificatePath)) {
        $cert = [security.cryptography.x509Certificates.x509Certificate2]::new($certificatePath, $certificatePassword);
    }
    else {
        $cert = Get-ChildItem -Path cert:\$store -Recurse | Where-Object Thumbprint -eq $gatewayCertThumb
    }

    if (!$cert) {
        write-error "unable to find cert $gatewayCertThumb"
        return
    }

    $eventArgs = "api-version=$($apiVer)&timeout=$($timeoutSec)"
    $checkUrl = "$($gatewayHost)/Nodes/$($nodeName)?$($eventArgs)"
    
    if (!(check-nodeStatus -url $checkUrl)) {
        return
    }

    write-host "disabling node:$nodeName"
    $url = "$($gatewayHost)/Nodes/$($nodeName)/$/Deactivate?$($eventArgs)"

    # Pause, Restart, RemoveData
    $body = @{ DeactivationIntent = $deactivationIntent } | convertto-json

    $global:result = call-rest -url $url -cert $cert -method post -body $body
    if ($global:result.StatusCode -ne 200) {
        write-host "$($global:result)" -ForegroundColor Red
        write-host "disable failed" -ForegroundColor Red
    }
    else {
        write-host "$($global:result)" -ForegroundColor Cyan
        write-host "disable successful" -ForegroundColor Green
    }

    check-nodeStatus -url $checkUrl
}

function call-rest($url, $cert, $method, $body) {
    if ($PSVersionTable.PSEdition -ieq 'core') {
        write-host "Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing -Method $method -body $body -Certificate $($cert.thumbprint) -SkipCertificateCheck -SkipHttpErrorCheck" -ForegroundColor Cyan
        return Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing -Method $method -body $body -Certificate $cert -SkipCertificateCheck -SkipHttpErrorCheck
    }
    else {
        write-host "Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing -Method $method -body $body -Certificate $($cert.thumbprint)" -ForegroundColor Cyan
        return Invoke-WebRequest -Uri $url -TimeoutSec 30 -UseBasicParsing -Method $method -body $body -Certificate $cert
    }
}

function check-nodeStatus($url) {
    # verify node name as post will not return error for bad node name
    $global:result = call-rest -url $url -cert $cert -method get
    if ($global:result.StatusCode -ne 200) {
        write-error "unable to find node: $nodeName"
        return $false
    }

    write-host "current node status:`r`n$($global:result | convertfrom-json | convertto-json)" -ForegroundColor Cyan
    return $true
}

function set-callback() {
    add-type @"
    using System;
    using System.Net;
    using System.Security.Cryptography.X509Certificates;

    public class IDontCarePolicy : ICertificatePolicy {
            public IDontCarePolicy() {}
            public bool CheckValidationResult(ServicePoint sPoint, X509Certificate cert, WebRequest wRequest, int certProb) {
            Console.WriteLine(cert);
            Console.WriteLine(cert.Issuer);
            Console.WriteLine(cert.Subject);
            Console.WriteLine(cert.GetCertHashString());
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy 

}

main