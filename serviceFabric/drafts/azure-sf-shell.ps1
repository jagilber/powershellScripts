<#
.SYNOPSIS
    Connect to a Service Fabric cluster using Azure Cloud Shell
.DESCRIPTION
    Connect to a Service Fabric cluster using Azure Cloud Shell
.EXAMPLE

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-sf-shell.ps1" -outFile "$pwd/azure-sf-shell.ps1";
./azure-sf-shell.ps1 -keyVaultName <key vault name> -x509CertificateName <certificate name> -clusterHttpConnectionEndpoint <cluster endpoint> -absolutePath <absolute path> -apiVersion <api version> -timeoutSeconds <timeout seconds>

#>
param(
    [string]$keyvaultName = "mykeyvault",
    [string]$x509CertificateName = "myclustercert",
    [string]$clusterHttpConnectionEndpoint = 'https://mycluster.eastus.cloudapp.azure.com:19080',
    [Security.Cryptography.X509Certificates.X509Certificate2]$x509Certificate = $null,
    [string]$absolutePath = '', #'/$/GetClusterHealth',
    [string]$apiVersion = '9.1',
    [string]$timeoutSeconds = '10',
    [switch]$loadOnly
)

$global:sfHttpModule = 'Microsoft.ServiceFabric.Powershell.Http'
$global:isCloudShell = $PSVersionTable.Platform -ieq 'Unix'
$global:clusterHttpConnectionEndpoint = $clusterHttpConnectionEndpoint
$global:apiVersion = $apiVersion
$global:timeoutSeconds = $timeoutSeconds

function main() {
    $publicip = @((Invoke-RestMethod https://ipinfo.io/json).ip)
    write-host "publicip: $publicip"

    if (!(get-azresourcegroup)) {
        write-host "connect-azaccount"
        Connect-AzAccount -UseDeviceAuthentication
    }

    if (!$x509Certificate -and !$global:x509Certificate) {

        if (!$global:isCloudShell) {
            write-host "get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Subject -ieq CN=$x509CertificateName"
            $x509Certificate = Get-ChildItem -Path Cert:\ -Recurse | Where-Object Subject -ieq "CN=$x509CertificateName"
            if (!$x509Certificate) {
                write-host "failed to get certificate for thumbprint from local store: $x509CertificateName" -foregroundColor red
            }
        }

        if (!$x509Certificate) {
            write-host "Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $x509CertificateName"
            $kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $x509CertificateName
            if (!$kvCertificate) {
                throw "Certificate not found in keyvault"
            }
            $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $kvCertificate.Name -AsPlainText;
            $secretByte = [Convert]::FromBase64String($secret)
            $x509Certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($secretByte, "", "Exportable,PersistKeySet")
        }

        if (!$x509Certificate) {
            throw "failed to get certificate for thumbprint from keyvault: $x509CertificateName"
        }
        $global:x509Certificate = $x509Certificate
    }
    elseif (!$x509Certificate) {
        $x509Certificate = $global:x509Certificate
    }

    write-host "found certificate for: $x509CertificateName" -foregroundColor yellow
    write-host "subject: $($x509Certificate.Subject)" -foregroundColor yellow
    write-host "issuer: $($x509Certificate.Issuer)" -foregroundColor yellow
    write-host "issue date: $($x509Certificate.NotBefore)" -foregroundColor yellow
    write-host "expiration date: $($x509Certificate.NotAfter)" -foregroundColor yellow
    write-host "thumbprint: $($x509Certificate.Thumbprint)" -foregroundColor yellow

    if (!(get-module $global:sfHttpModule)) {
        if (!(get-module -ListAvailable $global:sfHttpModule)) {
            Install-Module -Name $global:sfHttpModule -AllowPrerelease -Force
        }
        Import-Module $global:sfHttpModule
    }
    
    if (!(get-module $global:sfHttpModule)) {
        throw "$global:sfHttpModule not found"
    }

    $result = test-connection -tcpEndpoint $clusterHttpConnectionEndpoint
    if ($error -or !$result) {
        write-host "make sure this ip is allowed is able to connect to cluster endpoint: $publicip"
        write-error "error: $error"
        return
    }
    
    $error.clear()
    if (!(Test-SFClusterConnection)) {
        Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint `
            -ServerCertThumbprint $x509Certificate.Thumbprint `
            -X509Credential `
            -ClientCertificate $x509Certificate `
            -verbose
        if ($error) {
            write-host "error connecting to cluster: $error"
            return
        }
    }
    
    $global:availableCommands = (get-command -module $global:sfHttpModule | Where-Object name -inotmatch 'mesh' | Select-Object name).name
    write-host "available commands:stored in `$global:availableCommands`r`n $($global:availableCommands | out-string)" -foregroundcolor cyan
    if (!($global:SFHttpClusterConnection)) {
        $global:SFHttpClusterConnection = $SFHttpClusterConnection
    }
    
    write-host "current cluster connection:`$global:SFHttpClusterConnection`r`n$($global:SFHttpClusterConnection | out-string)" -foregroundcolor cyan
    write-host "use function 'Connect-SFCluster' to reconnect to a cluster. example:" -foregroundcolor green
    write-host "Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint ``
    -ServerCertThumbprint $($x509Certificate.Thumbprint) ``
    -X509Credential ``
    -ClientCertificate `$global:x509Certificate ``
    -verbose
    "  -foregroundcolor Green
    
    write-host "use function 'invoke-request' to make rest requests to the cluster. example:invoke-requeust -absolutePath '/$/GetClusterHealth'" -foregroundcolor green
    if ($absolutePath) {
        invoke-request -absolutePath $absolutePath
    }
}

function test-connection($tcpEndpoint) {
    # works for windows and linux powershell since linux doesn't have Test-NetConnection
    $error.clear()
    $tcpClient = $null
    try {
        $match = [regex]::match($tcpEndpoint, '^(?:http.?://)?(?<hostName>[^:]+?):(?<port>\d+)$');
        $hostName = $match.Groups['hostName'].Value
        $port = $match.Groups['port'].Value
        $portTestSucceeded = $false
        if (!$port) {
            throw "test-connection:invalid tcp endpoint port: $tcpEndpoint"
        }
        if (!$hostName) {
            throw "test-connection:invalid tcp endpoint: $tcpEndpoint"
        }
        $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
        $tcpClient.SendTimeout = $tcpClient.ReceiveTimeout = 20000
        [IAsyncResult]$asyncResult = $tcpClient.BeginConnect($hostName, $port, $null, $null)

        if ($asyncResult.AsyncWaitHandle.WaitOne(3000, $false) -and $tcpClient.Connected) {
            $portTestSucceeded = $true
        }

        write-host "test-connection: computer:$hostName port:$port result:$portTestSucceeded"
        $tcpClient.Dispose()
        return $portTestSucceeded
    }
    catch {
        write-host "test-connection:exception:$($PSItem | out-string)"
        return $false
    }
    finally {
        if ($tcpClient) {
            $tcpClient.Dispose()
        }
    }
}

function invoke-request($absolutePath, 
    $endpoint = $global:clusterHttpConnectionEndpoint, 
    $x509Certificate = $global:x509Certificate, 
    $apiVersion = $global:apiVersion, 
    $timeoutSeconds = $global:timeoutSecondsl) {

    if (!$endpoint) {
        write-error "endpoint not specified"
        return $null
    }
    if (!$x509Certificate) {
        write-error "x509Certificate not specified"
        return $null
    }
    if (!$apiVersion) {
        $global:apiVersion = "6.0"
    }
    if (!$timeoutSeconds) {
        $global:timeoutSeconds = 60
    }

    $baseUrl = "$endpoint{0}?api-version=$apiVersion&timeout=$timeoutSeconds" -f $absolutePath

    if ($PSVersionTable.Platform -ieq 'Unix') {
        # cloud shell
        write-host "Invoke-WebRequest -Uri '$baseUrl' -certificate `$global:x509Certificate -SkipCertificateCheck -timeoutSec $timeoutSeconds" -ForegroundColor Cyan #-SkipHttpErrorCheck"
        $result = Invoke-WebRequest -Uri $baseUrl -certificate $x509Certificate -SkipCertificateCheck -timeoutSec $timeoutSeconds

    }
    else {
        # windows seems to want both certificate and certificate thumbprint
        write-host "Invoke-WebRequest -Uri '$baseUrl' -certificate `$global:x509Certificate -CertificateThumbprint $($x509Certificate.Thumbprint) -SkipCertificateCheck -timeoutSec $timeoutSeconds" -ForegroundColor Cyan #-SkipHttpErrorCheck"
        $result = Invoke-WebRequest -Uri $baseUrl -certificate $x509Certificate -CertificateThumbprint $x509Certificate.Thumbprint -SkipCertificateCheck -timeoutSec $timeoutSeconds
    
    }
    
    write-verbose $result | convertfrom-json | convertto-json -depth 99
    return $result
}

if(!$loadOnly) {
    main
    write-host 'loading functions'
    . ./azure-sf-shell.ps1 -loadonly
}
else {
    write-verbose "load only"
}


