<#
.SYNOPSIS
    powershell script to connect to existing service fabric cluster with connect-servicefabriccluster cmdlet

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-connect.ps1" -outFile "$pwd/sf-connect.ps1";
    ./sf-connect.ps1 -clusterEndpoint <cluster endpoint fqdn> -thumbprint <thumbprint>
#>
using namespace System.Net;
using namespace System.Net.Sockets;
using namespace System.Net.Security;
using namespace System.Security.Cryptography.X509Certificates;

[cmdletbinding()]
param(
    $clusterendpoint = "cluster.location.cloudapp.azure.com", #"10.0.0.4:19000",
    $thumbprint,
    $subjectName,
    $resourceGroup,
    $clustername = $resourceGroup,
    [ValidateSet('LocalMachine', 'CurrentUser')]
    $storeLocation = "CurrentUser",
    $storeName = 'My',
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
    if(!$certCollection) {
        return
    }

    $publicIp = (Invoke-RestMethod https://ipinfo.io/json).ip
    write-host "current public ip:$publicIp" -ForegroundColor Green

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
        get-certValidationTcp -url $clusterFqdn -port $clusterEndpointPort -certCollection $certCollection
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
        -ServerCertThumbprint $thumbprint ``
        -StoreLocation $storeLocation ``
        -StoreName $storeName ``
        -X509Credential ``
        -FindType FindByThumbprint ``
        -FindValue $thumbprint ``
        -verbose" -ForegroundColor Green
    
        $error.Clear()
    # this sets wellknown local variable $ClusterConnection
    $result = Connect-ServiceFabricCluster `
        -ConnectionEndpoint $managementEndpoint `
        -ServerCertThumbprint $thumbprint `
        -StoreLocation $storeLocation `
        -StoreName $storeName `
        -X509Credential `
        -FindType FindByThumbprint `
        -FindValue $thumbprint `
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

    # set global so commands can be run outside of script
    $global:ClusterConnection = $ClusterConnection
    $currentVerbose = $VerbosePreference
    $currentDebug = $DebugPreference
    $VerbosePreference = $currentVerbose
    $DebugPreference = $currentDebug
}

function get-certValidationHttp([string] $url) {
    write-host "get-certValidationHttp:$($url)" -ForegroundColor Green
    $error.Clear()
    $webRequest = [Net.WebRequest]::Create($url)
    $webRequest.ServerCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
    $webRequest.Timeout = 1000 #ms

    try { 
        [void]$webRequest.GetResponse() 
        # return $null
    }
    catch [System.Exception] {
        Write-Verbose "get-certValidationHttp:first catch getresponse: $($url) $($error | Format-List * | out-string)`r`n$($_.Exception|Format-List *)" 
        $error.Clear()
    }
}

function get-certValidationTcp([string] $url, [int]  $port, [object]$certCollection) {
    # fabric doesnt use 3way handshake
    #get-systemFabric $url $port
    return
    #$ipAddress = [dns]::resolve($url).AddressList[0]
    write-host "get-certValidationTcp:$ipAddress $url" -ForegroundColor Green
    $error.Clear()
    $tcpClient = [Net.Sockets.TcpClient]::new($url, $port)
    #  $sslStream = [sslstream]::new($tcpClient.GetStream(),`
    #      $false,`
    #      [net.servicePointManager]::ServerCertificateValidationCallback,`
    #      $null)
    #  $sslStream = [sslstream]::new($tcpClient.GetStream(),`
    #      $false,`
    #      [System.Net.Security.RemoteCertificateValidationCallback]($global:securityCallback.ValidationCallback),`
    #      [System.Net.Security.LocalCertificateSelectionCallback]($global:securityCallback.LocalCallback))
    $sslStream = [system.net.security.sslstream]::new($tcpClient.GetStream(), $false)
    #$sslStream = [sslstream]::new($tcpClient.GetStream(),$false, [net.servicePointManager]::ServerCertificateValidationCallback)
    # $webRequest.ServerCertificateValidationCallback = [net.servicePointManager]::ServerCertificateValidationCallback
    # $webRequest.Timeout = 1000 #ms
    #$sslStream.AuthenticateAsClient($url)
    #$sslStream.AuthenticateAsClient('sfjagilber')
    try { 
        $sslAuthenticationOptions = [system.net.security.SslClientAuthenticationOptions]::new()
        $sslAuthenticationOptions.AllowRenegotiation = $true
        $sslAuthenticationOptions.CertificateRevocationCheckMode = 0
        $sslAuthenticationOptions.EncryptionPolicy = 1
        $sslAuthenticationOptions.EnabledSslProtocols = 3072 # tls 1.2 #(3072 -bor 12288)
        #$sslAuthenticationOptions.ClientCertificates = (get-clientCert $thumbprint $storeLocation)
        $sslAuthenticationOptions.ClientCertificates = [System.Security.Cryptography.X509Certificates.X509CertificateCollection]::new($certCollection)
        $sslAuthenticationOptions.LocalCertificateSelectionCallback = [System.Net.Security.LocalCertificateSelectionCallback]($global:securityCallback.LocalCallback)
        $sslAuthenticationOptions.RemoteCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback]($global:securityCallback.ValidationCallback)
        $sslAuthenticationOptions.TargetHost = $subjectName
        # $sslAuthenticationOptions.
        ## todo: not working
        # https://docs.microsoft.com/en-us/dotnet/api/system.net.security.sslstream.authenticateasclient?view=net-5.0
        write-host "sslAuthenticationOptions:$($sslAuthenticationOptions | convertto-json)" -ForegroundColor Cyan
        $sslStream.AuthenticateAsClient($sslAuthenticationOptions)

        #$sslStream.AuthenticateAsClient('sfjagilber') #($url)
        # [void]$webRequest.GetResponse() 
        # return $null
    }
    catch [System.Exception] {
        Write-Host "get-certValidationTcp:first catch getresponse: $url $($error | Format-List * | out-string)`r`n$($_.Exception|Format-List *)" 
        #$error.Clear()
    }
}

function get-systemFabric([string] $url, [int]  $port) {
    # creates $nuget object
    invoke-webRequest 'https://aka.ms/nuget-functions.ps1' | Invoke-Expression

    $systemFabricDll = $nuget.GetFiles("System.Fabric.dll")[-1]
    if (!$systemFabricDll) {
        $nuget.InstallPackage('Microsoft.ServiceFabric')
    }
    $systemFabricDll = $nuget.GetFiles("System.Fabric.dll")[-1]
    if (!$systemFabricDll) {
        wrrite-error "unable to find / load system.fabric. try running from machine with service fabric installed"
        return
    }
    
    add-type -path $systemFabricDll
    [fabric.x509credentials]$sfcredentials = [fabric.x509credentials]::new()

    $sfcredentials.FindType = 'FindByThumbprint'
    $sfcredentials.FindValue = $thumbprint
    $sfcredentials.StoreLocation = $storeLocation
    $sfcredentials.StoreName = $storeName
    $sfcredentials.RemoteCertThumbprints.Add($thumbprint)
    #$x509Name = [fabric.X509Name]::new('certificate name', $thumbprint)
    #$sfcredentials.RemoteX509Names.Add($x509Name)
    $sfcredentials

    # https://docs.microsoft.com/en-us/dotnet/api/system.fabric.fabricclient.-ctor?f1url=%3FappId%3DDev16IDEF1%26l%3DEN-US%26k%3Dk(System.Fabric.FabricClient.%2523ctor);k(DevLang-csharp)%26rd%3Dtrue&view=azure-dotnet
    [string[]]$hosts = @("$($url):$port")
    [fabric.fabricclient]$global:fc = [fabric.fabricclient]::new($sfcredentials, $hosts)
    $global:fc.ClusterManager.GetClusterManifestAsync().Result
}

function get-clientCert($thumbprint, $storeLocation, $storeName) {
    $pscerts = @(Get-ChildItem -Path Cert:\$storeLocation\$storeName -Recurse | Where-Object Thumbprint -eq $thumbprint)
    [collections.generic.list[System.Security.Cryptography.X509Certificates.X509Certificate]] $certCol = [collections.generic.list[System.Security.Cryptography.X509Certificates.X509Certificate]]::new()

    foreach ($cert in $pscerts) {
        [void]$certCol.Add([System.Security.Cryptography.X509Certificates.X509Certificate]::new($cert))
    }

    write-host "certcol: $($certCol | convertto-json)"

    if(!$certCol){
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
            [System.Security.Cryptography.X509Certificates.X509Certificate] LocalCallback(
                [object]$senderObject, 
                [string]$targetHost,
                [System.Security.Cryptography.X509Certificates.X509CertificateCollection]$certCol, 
                [System.Security.Cryptography.X509Certificates.X509Certificate]$remoteCert, 
                [string[]]$issuers
            ) {
                write-host "validation callback:sender:$($senderObject | out-string)" -ForegroundColor Cyan
                write-verbose "validation callback:sender:$($senderObject | convertto-json)"
        
                write-host "validation callback:targethost:$($targetHost | out-string)" -ForegroundColor Cyan
                write-verbose "validation callback:targethost:$($targetHost | convertto-json)"

                write-host "validation callback:certCol:$($certCol | Format-List * |out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:certCol:$($certCol | convertto-json)"
        
                write-host "validation callback:remotecert:$($remoteCert | Format-List * |out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:remotecert:$($remoteCert | convertto-json)"
        
                write-host "validation callback:issuers:$($issuers | out-string)" -ForegroundColor Cyan
                write-verbose  "validation callback:issuers:$($issuers | convertto-json)"
                return $remoteCert
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