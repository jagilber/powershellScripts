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
    $keyvaultName = "mykeyvault",
    $x509CertificateName = "myclustercert",
    $clusterHttpConnectionEndpoint = 'https://mycluster.eastus.cloudapp.azure.com:19080',
    $x509Certificate = $null,
    $absolutePath = '/$/GetClusterHealth',
    $apiVersion = '9.1',
    $timeoutSeconds = '10'  
)

$sfHttpModule = 'Microsoft.ServiceFabric.Powershell.Http'
$isCloudShell = $PSVersionTable.Platform -ieq 'Unix'

function main() {
    $publicip = @((Invoke-RestMethod https://ipinfo.io/json).ip)
    write-host "publicip: $publicip"

    if (!$x509Certificate -and !$global:x509Certificate) {

        if (!$isCloudShell) {
            write-host "get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Subject -ieq CN=$x509CertificateName"
            $x509Certificate = Get-ChildItem -Path Cert:\ -Recurse | Where-Object Subject -ieq "CN=$x509CertificateName"
            if (!$x509Certificate) {
                write-host "failed to get certificate for thumbprint from local store: $x509CertificateName" -foregroundColor red
            }
        }

        if (!$x509Certificate) {
            write-host "get certificate from keyvault: $keyvaultName/$x509CertificateName"
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
    }

    $global:x509Certificate = $x509Certificate
    write-host "found certificate for: $x509CertificateName" -foregroundColor yellow
    write-host "subject: $($x509Certificate.Subject)" -foregroundColor yellow
    write-host "issuer: $($x509Certificate.Issuer)" -foregroundColor yellow
    write-host "issue date: $($x509Certificate.NotBefore)" -foregroundColor yellow
    write-host "expiration date: $($x509Certificate.NotAfter)" -foregroundColor yellow
    write-host "thumbprint: $($x509Certificate.Thumbprint)" -foregroundColor yellow

    if (!(get-module $sfHttpModule)) {
        if (!(get-module -ListAvailable $sfHttpModule)) {
            Install-Module -Name $sfHttpModule -AllowPrerelease -Force
        }
        Import-Module $sfHttpModule
    }
    
    if (!(get-module $sfHttpModule)) {
        throw "$sfHttpModule not found"
    }

    $result = invoke-request -endpoint $clusterHttpConnectionEndpoint `
        -absolutePath $absolutePath `
        -x509certificate $x509Certificate
        
    $resultJson = ConvertFrom-Json $result.Content
    $resultJson = ConvertTo-Json $resultJson -Depth 99
    write-host "result: $resultJson"

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
    
    $availableCommands = (get-command -module $sfHttpModule | Where-Object name -inotmatch 'mesh' | Select-Object name).name
    write-host "available commands:`r`n $($availableCommands | out-string)" -foregroundcolor cyan
    if (!($global:SFHttpClusterConnection)) {
        $global:SFHttpClusterConnection = $SFHttpClusterConnection
    }
    
    write-host "cluster connection:`$global:SFHttpClusterConnection`r`n$($global:SFHttpClusterConnection | out-string)" -foregroundcolor cyan
    write-host "Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint ``
    -ServerCertThumbprint $($x509Certificate.Thumbprint) ``
    -X509Credential ``
    -ClientCertificate `$global:x509Certificate ``
    -verbose
    "  -foregroundcolor Green
    
}

function invoke-request($endpoint, $absolutePath, $x509Certificate) {
    $baseUrl = "$endpoint{0}?api-version=$apiVersion&timeout=$timeoutSeconds" -f $absolutePath
    if ($isCloudShell) {
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

main
