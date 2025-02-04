<#
.SYNOPSIS
    powershell script to connect to existing managed service fabric cluster with connect-servicefabriccluster cmdlet
{{cluster id}}.sfmc.azclient.ms
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-connect.ps1" -outFile "$pwd/sf-managed-connect.ps1";
    ./sf-managed-connect.ps1 -clusterEndpoint <cluster endpoint fqdn> -thumbprint <thumbprint>
#>
using namespace System.Net;
using namespace System.Net.Sockets;
using namespace System.Net.Security;
using namespace System.Security.Cryptography.X509Certificates;

[cmdletbinding()]
param(
    $clusterEndpoint = "cluster.location.cloudapp.azure.com", #"10.0.0.4:19000",
    [Parameter(Mandatory = $true)]
    $thumbprint,
    #[Parameter(Mandatory = $true)]
    $resourceGroup,
    $clustername = $resourceGroup,
    [ValidateSet('LocalMachine', 'CurrentUser')]
    $storeLocation = "CurrentUser",
    $storeName = 'My',
    $clusterEndpointPort = 19000,
    $clusterExplorerPort = 19080,
    $subscriptionId
)

#Add-azAccount
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

function main() {
    $StartTime = (Get-Date)
    write-host "starting:$startTime"
    set-callback
    $error.Clear()
    if (!(get-command Connect-ServiceFabricCluster)) {
        import-module servicefabric
        if (!(get-command Connect-ServiceFabricCluster)) {
            write-error "unable to import servicefabric powershell module. try executing script from a working node."
            return
        }
    }

    $certCollection = get-clientCert -thumbprint $thumbprint -storeLocation $storeLocation -storeName $storeName
    if (!$certCollection) {
        return
    }

    $findValue = $thumbprint
    $findType = 'FindByThumbprint'
    
    $publicIp = (Invoke-RestMethod https://ipinfo.io/json).ip
    write-host "current public ip:$publicIp" -ForegroundColor Green

    $managementEndpoint = $clusterEndpoint
    $currentVerbose = $VerbosePreference
    $currentDebug = $DebugPreference
    $VerbosePreference = "continue"
    $DebugPreference = "continue"
    $global:ClusterConnection = $null

    # authenticate
    try {
        get-command connect-azaccount | Out-Null
    }
    catch [management.automation.commandNotFoundException] {
        if ((read-host "az not installed but is required for this script. is it ok to install?[y|n]") -imatch "y") {
            write-host "installing minimum required az modules..."
            install-module az.accounts
            install-module az.resources
            install-module az.servicefabric
            
            import-module az.accounts
            import-module az.resources
            import-module az.servicefabric
        }
        else {
            return 1
        }
    }

    if (!(@(Get-AzResourceGroup).Count)) {
        connect-azaccount

        if (!(Get-azResourceGroup)) {
            Write-Warning "unable to authenticate to az. returning..."
            return 1
        }
    }

    $global:cluster = $null

    if($resourceGroup -and $clustername) {
        write-host "Get-azServiceFabricManagedCluster -ResourceGroupName $resourceGroup -Name $clustername" -ForegroundColor Green
        $cluster = Get-azServiceFabricManagedCluster -ResourceGroupName $resourceGroup -Name $clustername
        $managementEndpoint = $cluster.Fqdn
    }
    else {
        write-host "Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $clusterEndpoint.replace(":19000", "")" -ForegroundColor Green
        $cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $clusterEndpoint.replace(":19000", "")
    }

    # $global:cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $clusterEndpoint.replace(":19000", "")
    if (!$cluster) {
        write-error "unable to find cluster $clusterEndpoint"
        return
    }

    $cluster | ConvertTo-Json -Depth 99

    if (!$subscriptionId) {
        $subscriptionId = (get-azcontext).Subscription.id
    }

    $clusterId = $cluster.Id
    write-host "(Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints" -ForegroundColor Green
    $serverThumbprint = (Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints

    if (!$serverThumbprint) {
        write-error "unable to get server thumbprint"
        return
    }
    else {
        write-host "using server thumbprint:$serverThumbprint" -ForegroundColor Cyan
    }

    if ($managementEndpoint -inotmatch ':\d{2,5}$') {
        $managementEndpoint = "$($managementEndpoint):$($clusterEndpointPort)"
    }

    $managementEndpoint = $managementEndpoint.Replace("19080", "19000").Replace("https://", "")
    $clusterFqdn = [regex]::match($managementEndpoint, "(?:http.//|^)(.+?)(?:\:|$|/)").Groups[1].Value

    $VerbosePreference = "silentlycontinue"
    $DebugPreference = "silentlycontinue"
    
    $result = Test-NetConnection -ComputerName $clusterFqdn -Port $clusterEndpointPort
    write-host ($result | out-string)

    if ($result.tcpTestSucceeded) {
        write-host "able to connect to $($clusterFqdn):$($clusterEndpointPort)" -ForegroundColor Green
        get-certValidationTcp -url $clusterFqdn -port $clusterEndpointPort
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
        get-certValidationHttp -url "https://$($clusterFqdn):$($clusterExplorerPort)/Explorer/index.html#/"
    }
    else {
        write-error "unable to connect to $($clusterFqdn):$($clusterExplorerPort)"
    }

    write-host "Connect-ServiceFabricCluster -ConnectionEndpoint $managementEndpoint ``
        -ServerCertThumbprint $serverThumbprint ``
        -StoreLocation $storeLocation ``
        -StoreName $storeName ``
        -X509Credential ``
        -FindType $findType ``
        -FindValue $findValue ``
        -verbose" -ForegroundColor Green

    $error.Clear()
    # this sets wellknown local variable $ClusterConnection
    $result = Connect-ServiceFabricCluster `
        -ConnectionEndpoint $managementEndpoint `
        -ServerCertThumbprint $serverThumbprint `
        -StoreLocation $storeLocation `
        -StoreName $storeName `
        -X509Credential `
        -FindType $findType `
        -FindValue $findValue `
        -Verbose
        
    $result
    write-host "Get-ServiceFabricClusterConnection" -ForegroundColor Green

    write-host "============================" -ForegroundColor Green
    Get-ServiceFabricClusterConnection
    $DebugPreference = "silentlycontinue"

    if (!$result -or $error) {
        write-warning "error detected. pausing to capture window events"
        start-sleep -seconds 10
        #$StartTime = (Get-Date).AddMinutes(-1)
        $EndTime = (get-date)
        $level = @(0..5)
        $data = ''
        write-host "
            `$global:events = Get-WinEvent -Oldest -Force -FilterHashtable @{
                Logname   = 'Microsoft-ServiceFabric*'
                StartTime = $StartTime
                EndTime   = $EndTime
                Level     = $level
                Data      = $data
            }
        "
        $global:events = Get-WinEvent -Oldest -Force -FilterHashtable @{
            Logname   = 'Microsoft-ServiceFabric*'
            StartTime = $StartTime
            EndTime   = $EndTime
            Level     = $level
            Data      = $data
        }
        
        write-host "service fabric windows events:"
        $global:events
    }

    #write-host "get-event"
    #Get-Event

    # set global so commands can be run outside of script
    $global:ClusterConnection = $ClusterConnection
    $currentVerbose = $VerbosePreference
    $currentDebug = $DebugPreference
    $VerbosePreference = $currentVerbose
    $DebugPreference = $currentDebug

    write-host "finished"
}

function get-certValidationHttp([string] $url) {
    write-host "get-certValidationHttp:$($url) $($certFile)" -ForegroundColor Green
    $error.Clear()
    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.ServerCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
    $webRequest.Timeout = 1000 #ms

    try { 
        [void]$webRequest.GetResponse() 
        # return $null
    }
    catch [System.Exception] {
        Write-Verbose "get-certValidationHttp:first catch getresponse: $($url) $($certFile) $($error | Format-List * | out-string)`r`n$($_.Exception|Format-List *)" 
        $error.Clear()
    }
}

function get-certValidationTcp([string] $url, [int]  $port) {
    write-host "get-certValidationTcp:$($url) $($certFile)" -ForegroundColor Green
    $error.Clear()
    $tcpClient = [Net.Sockets.TcpClient]::new($url, $port)
    # $sslStream = [sslstream]::new($tcpClient.GetStream(),`
    #     $true,`
    #     [net.servicePointManager]::ServerCertificateValidationCallback,`
    #     $null)
    $sslStream = [sslstream]::new($tcpClient.GetStream(), $false)
    # $webRequest.ServerCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
    # $webRequest.Timeout = 1000 #ms

    try { 
        $sslAuthenticationOptions = [SslClientAuthenticationOptions]::new()
            
        $sslAuthenticationOptions.AllowRenegotiation = $true
        $sslAuthenticationOptions.CertificateRevocationCheckMode = 0
        $sslAuthenticationOptions.EncryptionPolicy = 1
        $sslAuthenticationOptions.RemoteCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
        $sslAuthenticationOptions.TargetHost = $url
        # $sslAuthenticationOptions.
        ## todo: not working
        # https://docs.microsoft.com/en-us/dotnet/api/system.net.security.sslstream.authenticateasclient?view=net-5.0
        $sslStream.AuthenticateAsClient($sslAuthenticationOptions)

        #$sslStream.AuthenticateAsClient('sfjagilber') #($url)
        # [void]$webRequest.GetResponse() 
        # return $null
    }
    catch [System.Exception] {
        Write-Host "get-certValidationTcp:first catch getresponse: $($url) $($error | Format-List * | out-string)`r`n$($_.Exception|Format-List *)" 
        $error.Clear()
    }
}

function get-clientCert($thumbprint, $storeLocation, $storeName) {
    $pscerts = @(Get-ChildItem -Path Cert:\$storeLocation\$storeName -Recurse | Where-Object Thumbprint -eq $thumbprint)
    [collections.generic.list[System.Security.Cryptography.X509Certificates.X509Certificate]] $certCol = [collections.generic.list[System.Security.Cryptography.X509Certificates.X509Certificate]]::new()

    foreach ($cert in $pscerts) {
        [void]$certCol.Add([System.Security.Cryptography.X509Certificates.X509Certificate]::new($cert))
    }

    write-host "certcol: $($certCol | convertto-json)"

    if (!$certCol) {
        write-error "certificate with thumbprint:$thumbprint not found in certstore:$storeLocation\$storeName"
        return $null
    }

    Write-host "certificate with thumbprint:$thumbprint found in certstore:$storeLocation\$storeName" -ForegroundColor Green
    return $certCol.ToArray()
}

function set-callback() {
    if ($PSVersionTable.PSEdition -ieq 'core') {
        class SecurityCallback {
            [bool] ValidationCallback(
                [object]$senderObject, 
                [System.Security.Cryptography.X509Certificates.X509Certificate]$cert, 
                [System.Security.Cryptography.X509Certificates.X509Chain]$chain, 
                [System.Net.Security.SslPolicyErrors]$policyErrors
            ) {
                write-host "validation callback:sender:$($senderObject | out-string)" -ForegroundColor Cyan
                write-verbose "validation callback:sender:$($senderObject | convertto-json)"
        
                write-host "validation callback:cert:$($cert | Format-List * |out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:cert:$($cert | convertto-json)"
        
                write-host "validation callback:chain:$($chain | Format-List * |out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:chain:$($chain | convertto-json)"
        
                write-host "validation callback:errors:$($policyErrors | out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:errors:$($policyErrors | convertto-json)"
                return $true
            }
        }

        [SecurityCallback]$global:securityCallback = [SecurityCallback]::new()
        [net.servicePointManager]::ServerCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback]($global:securityCallback.ValidationCallback)
    }
    else {
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
}

main