<#
.SYNOPSIS
    powershell script to connect to existing service fabric cluster with connect-servicefabriccluster cmdlet

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-connect.ps1" -outFile "$pwd/sf-connect.ps1";
    ./sf-connect.ps1 -clusterEndpoing <cluster endpoint fqdn> -thumbprint <thumbprint>
#>
[cmdletbinding()]
param(
    $clusterendpoint = "cluster.location.cloudapp.azure.com", #"10.0.0.4:19000",
    $thumbprint,
    $resourceGroup,
    $clustername = $resourceGroup,
    [ValidateSet('LocalMachine', 'CurrentUser')]
    $storeLocation = "CurrentUser",
    $clusterendpointPort = 19000,
    $clusterExplorerPort = 19080
)

# proxy test
#$proxyString = "http://127.0.0.1:5555"
#$proxyUri = new-object System.Uri($proxyString)
#[Net.WebRequest]::DefaultWebProxy = new-object System.Net.WebProxy ($proxyUri, $true)
#$proxy = [System.Net.CredentialCache]::DefaultCredentials
#[System.Net.WebRequest]::DefaultWebProxy.Credentials = $proxy
#Add-azAccount

$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

class SecurityCallback {
    [bool] ValidationCallback(
            [object]$result, 
            [System.Security.Cryptography.X509Certificates.X509Certificate]$cert, 
            [System.Security.Cryptography.X509Certificates.X509Chain]$chain, 
            [System.Net.Security.SslPolicyErrors]$policyErrors
        ) {
        write-host "validation callback:result:$($result | out-string)" -ForegroundColor Cyan
        write-verbose "validation callback:result:$($result | convertto-json)"
        
        write-host "validation callback:cert:$($cert | Format-List * |out-string)" -ForegroundColor Cyan
        write-verbose  "validation callback:cert:$($cert | convertto-json)"
        
        write-host "validation callback:chain:$($chain | Format-List * |out-string)" -ForegroundColor Cyan
        write-verbose  "validation callback:chain:$($chain | convertto-json)"
        
        write-host "validation callback:errors:$($policyErrors | out-string)" -ForegroundColor Cyan
        write-verbose  "validation callback:errors:$($policyErrors | convertto-json)"
        return $true
    }
}

[SecurityCallback]$securityCallback = [SecurityCallback]::new()
[net.servicePointManager]::ServerCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback]($securityCallback.ValidationCallback)

function main() {
    $error.Clear()
    if (!(get-command Connect-ServiceFabricCluster)) {
        import-module servicefabric
        if (!(get-command Connect-ServiceFabricCluster)) {
            write-error "unable to import servicefabric powershell module. try executing script from a working node."
            return
        }
    }

    $managementEndpoint = $clusterEndpoint
    $currentVerbose = $VerbosePreference
    $currentDebug = $DebugPreference
    $VerbosePreference = "continue"
    $DebugPreference = "continue"
    $global:ClusterConnection = $null

    if ($resourceGroup -and $clustername) {
        $cluster = Get-azServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clustername
        $managementEndpoint = $cluster.ManagementEndpoint
        $thumbprint = $cluster.Certificate.Thumbprint
        $global:cluster | ConvertTo-Json -Depth 99
    }

    if ($managementEndpoint -inotmatch ':\d{2,5}$') {
        $managementEndpoint = "$($managementEndpoint):$($clusterEndpointPort)"
    }

    $managementEndpoint = $managementEndpoint.Replace("19080", "19000").Replace("https://", "")
    $clusterFqdn = [regex]::match($managementEndpoint, "(?:http.//|^)(.+?)(?:\:|$|/)").Groups[1].Value

    $VerbosePreference = "silentlycontinue"
    $DebugPreference = "silentlycontinue"
    
    $result = Test-NetConnection -ComputerName $clusterFqdn -Port $clusterendpointPort
    write-host ($result | out-string)

    if ($result.tcpTestSucceeded) {
        write-host "able to connect to $($clusterFqdn):$($clusterEndpointPort)" -ForegroundColor Green
    }
    else {
        write-error "unable to connect to $($clusterFqdn):$($clusterEndpointPort)"
    }

    $result = Test-NetConnection -ComputerName $clusterFqdn -Port $clusterExplorerPort
    write-host ($result | out-string)

    $VerbosePreference = "continue"
    $DebugPreference = "continue"

    if ($result.tcpTestSucceeded) {
        write-host "able to connect to $($clusterFqdn):$($clusterExplorerPort)" -ForegroundColor Green
        get-certValidation -url "https://$($clusterFqdn):$($clusterExplorerPort)/Explorer/index.html#/"
    }
    else {
        write-error "unable to connect to $($clusterFqdn):$($clusterExplorerPort)"
    }

    write-host "Connect-ServiceFabricCluster -ConnectionEndpoint $managementEndpoint `
        -ServerCertThumbprint $thumbprint `
        -StoreLocation $storeLocation `
        -X509Credential `
        -FindType FindByThumbprint `
        -FindValue $thumbprint `
        -verbose" -ForegroundColor Green

    # this sets wellknown local variable $ClusterConnection
    Connect-ServiceFabricCluster `
        -ConnectionEndpoint $managementEndpoint `
        -ServerCertThumbprint $thumbprint `
        -StoreLocation $storeLocation `
        -X509Credential `
        -FindType FindByThumbprint `
        -FindValue $thumbprint `
        -Verbose


    write-host "Get-ServiceFabricClusterConnection" -ForegroundColor Green

    write-host "============================" -ForegroundColor Green
    Get-ServiceFabricClusterConnection
    $DebugPreference = "silentlycontinue"

    # set global so commands can be run outside of script
    $global:ClusterConnection = $ClusterConnection
    $currentVerbose = $VerbosePreference
    $currentDebug = $DebugPreference
    $VerbosePreference = $currentVerbose
    $DebugPreference = $currentDebug
}

function get-certValidation([string] $url) {
    write-host "get-cert:$($url) $($certFile)" -ForegroundColor Green
    $error.Clear()
    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.ServerCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
    $webRequest.Timeout = 1000 #ms

    try { 
        [void]$webRequest.GetResponse() 
        # return $null
    }
    catch [System.Exception] {
        Write-Verbose "get-cert:first catch getresponse: $($url) $($certFile) $($error | Format-List * | out-string)`r`n$($_.Exception|Format-List *)" 
        $error.Clear()
    }
}

main