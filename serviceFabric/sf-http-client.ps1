<#
.SYNOPSIS
    Connect to a Service Fabric cluster using Azure Cloud Shell. can use local or remote certificate in keyvault.
.DESCRIPTION
    Connect to a Service Fabric cluster using Azure Cloud Shell local or remote.

.NOTES
    File Name: sf-http-client.ps1
    Author   : jagilber
    Requires : PowerShell Version 5.1 or greater
        231010 - rename argument -x509CertificateName to -certificateName
        231009 - rename to sf-http-client.ps1
        231008 - add base64 certificate support

.PARAMETER clusterHttpConnectionEndpoint
        the cluster endpoint to connect to. example: https://mycluster.eastus.cloudapp.azure.com:19080

.PARAMETER certificateName
        the certificate name stored in keyvault. example: sfclustercert

.PARAMETER keyvaultName
        the keyvault name where the certificate is stored. example: sfclusterkeyvault

.PARAMETER keyvaultSecretVersion
        the keyvault secret version. example: 96e530c3d22b43228eb1d...

.PARAMETER certificateBase64
        the base64 encoded certificate. example: MIIKQAIBAzCCCfwGCSqGSIb3DQEHAaCCCe0Eggnp...

.PARAMETER x509Certificate
        the certificate object. example: $x509Certificate = get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Subject -ieq CN=$certificateName

.PARAMETER absolutePath
        the absolute path to the rest endpoint. example: /$/GetClusterHealth

.PARAMETER apiVersion
        the api version to use. default: 9.1

.EXAMPLE
    ./sf-http-client.ps1 -keyVaultName sfclusterkeyvault -certificateName sfclustercert -clusterHttpConnectionEndpoint https://mycluster.eastus.cloudapp.azure.com:19080
    example connection to a cluster using a certificate stored in keyvault. requires -keyVaultName, -certificateName

.EXAMPLE
    ./sf-http-client.ps1 -keyVaultName sfclusterkeyvault -certificateName sfclustercert -keyvaultSecretVersion "96e530c3d22b4322..." -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com
    example connection to a cluster using a certificate stored in keyvault. requires -keyVaultName, -certificateName, -keyvaultSecretVersion

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint https://mycluster.eastus.cloudapp.azure.com:19080 -certificateBase64 "MIIKQAIBAzCCCfwGCSqGSIb3DQEHAaCCCe0Eggnp..."
    example connection to a cluster using a base64 encoded certificate. this is useful for cloud shell since it doesn't have access to local certificate store.
    example command to create base64 string from powershell: [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("C:\path\to\certificate.pfx"))

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -x509Certificate $x509Certificate
    example connection to a cluster using a certificate object. this is useful for cloud shell since it doesn't have access to local certificate store.
    example command to create certificate object from local cert store in powershell: 
        $x509Certificate = get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Subject -ieq CN=$certificateName

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint https://mycluster.eastus.cloudapp.azure.com:19080 -certificateName sfclustercert
    example connection to a cluster using a certificate stored in local certificate store on windows. requires -certificateName

.EXAMPLE
    ./sf-http-client.ps1 -absolutePath /$/GetClusterHealth
    example rest request to the cluster. requires -clusterHttpConnectionEndpoint to be set in a previous command.

.LINK
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-http-client.ps1" -outFile "$pwd/sf-http-client.ps1";
./sf-http-client.ps1 -examples

#>
[CmdletBinding(DefaultParameterSetName = "default")]
param(
    #[Parameter(Mandatory = $true)]
    [Parameter(ParameterSetName = "keyvault")]
    [Parameter(ParameterSetName = "local")]
    [Parameter(ParameterSetName = "default")]
    [string]$clusterHttpConnectionEndpoint, # = $null, #'https://mycluster.eastus.cloudapp.azure.com:19080',
        
    [Parameter(ParameterSetName = "keyvault")]
    [Parameter(ParameterSetName = "local")]
    [Parameter(ParameterSetName = "default")]
    [string]$certificateName = '', #"myclustercert",

    [Parameter(ParameterSetName = "keyvault")]
    [string]$keyvaultName = '', #"mykeyvault",

    [Parameter(ParameterSetName = "local")]
    [Security.Cryptography.X509Certificates.X509Certificate2]$x509Certificate = $null,
    
    [Parameter(ParameterSetName = "local")]
    [string]$certificateBase64 = '', # [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("C:\path\to\certificate.pfx"))
    
    [Parameter(ParameterSetName = "keyvault")]
    [string]$keyvaultSecretVersion = $null, # 96e530c3d22b43228eb1d...
    
    [Parameter(ParameterSetName = "rest")]
    [string]$absolutePath = '', #'/$/GetClusterHealth',

    [string]$apiVersion = '9.1',
    
    [string]$timeoutSeconds = '10',

    [switch]$examples
)

$global:sfHttpModule = 'Microsoft.ServiceFabric.Powershell.Http'
$global:isCloudShell = $PSVersionTable.Platform -ieq 'Unix'
$global:apiVersion = $apiVersion
$global:timeoutSeconds = $timeoutSeconds
$scriptName = "$psscriptroot/$($MyInvocation.MyCommand.Name)"

function main() {

    if ($examples) {
        get-help $scriptName -examples
        return
    }

    if ($clusterHttpConnectionEndpoint) {
        if (!($clusterHttpConnectionEndpoint -imatch '^http')) {
            write-host "adding https to clusterHttpConnectionEndpoint: $clusterHttpConnectionEndpoint"
            $clusterHttpConnectionEndpoint = "https://$clusterHttpConnectionEndpoint"
        }
        if (!($clusterHttpConnectionEndpoint -imatch ':\d+$')) {
            write-host "adding port 19080 to clusterHttpConnectionEndpoint: $clusterHttpConnectionEndpoint"
            $clusterHttpConnectionEndpoint = "$($clusterHttpConnectionEndpoint):19080"
        }

        $global:clusterHttpConnectionEndpoint = $clusterHttpConnectionEndpoint
        write-host "clusterHttpConnectionEndpoint: $clusterHttpConnectionEndpoint"
    }
    if (!$global:clusterHttpConnectionEndpoint) {
        write-error "execute script with value for -clusterHttpConnectionEndpoint"
        return
    }

    $publicip = @((Invoke-RestMethod https://ipinfo.io/json).ip)
    write-host "publicip: $publicip"

    if (!(get-certificateInfo)) {
        return
    }

    if (!(get-module $global:sfHttpModule)) {
        if (!(get-module -ListAvailable $global:sfHttpModule)) {
            Install-Module -Name $global:sfHttpModule -AllowPrerelease -Force
        }
        Import-Module $global:sfHttpModule
    }
    
    if (!(get-module $global:sfHttpModule)) {
        throw "$global:sfHttpModule not found"
    }

    if ($absolutePath) {
        invoke-request -absolutePath $absolutePath
        return
    }

    $result = test-connection -tcpEndpoint $clusterHttpConnectionEndpoint
    if ($error -or !$result) {
        write-host "make sure this ip is allowed to connect to cluster endpoint: $publicip" -ForegroundColor Cyan
        write-error "error: $error"
        return
    }
    
    $error.clear()
    if (!(Test-SFClusterConnection)) {
        Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint `
            -ServerCertThumbprint $global:x509Certificate.Thumbprint `
            -X509Credential `
            -ClientCertificate $global:x509Certificate `
            -verbose
        if ($error) {
            write-host "error connecting to cluster: $error"
            return
        }
    }

    if (!($global:SFHttpClusterConnection)) {
        $global:SFHttpClusterConnection = $SFHttpClusterConnection
    }

    $global:sfHttpCommands = (get-command -module $global:sfHttpModule | Where-Object name -inotmatch 'mesh' | Select-Object name).name
    write-host "current cluster connection:`$global:SFHttpClusterConnection`r`n$($global:SFHttpClusterConnection | out-string)" -foregroundcolor cyan
    write-host "available commands:stored in `$global:sfHttpCommands`r`n $($global:sfHttpCommands | out-string)" -foregroundcolor cyan

    write-host "use function 'Connect-SFCluster' to reconnect to a cluster. example:" -foregroundcolor green
    write-host "Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint ``
        -ServerCertThumbprint $($global:x509Certificate.Thumbprint) ``
        -X509Credential ``
        -ClientCertificate `$global:x509Certificate ``
        -verbose
        "  -foregroundcolor Green
    
    #write-host "use function 'invoke-request' to make rest requests to the cluster. example:invoke-request -absolutePath '/$/GetClusterHealth'" -foregroundcolor green
    write-host "use script with -absolutePath argument to make rest requests to the cluster. example:./sf-http-client.ps1 -absolutePath '/$/GetClusterHealth'" -foregroundcolor green
}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue
    
    if ($error) {
        $error.clear()
        write-warning "azure module for Connect-AzAccount not installed."

        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.resources
            install-module az.keyvault

            import-module az.accounts
            import-module az.resources
            import-module az.keyvault
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    if(!(get-azResourceGroup)){
        Connect-AzAccount
    }

    if(!@(get-azResourceGroup).Count -gt 0){
        return $false
    }

    return $true
}

function get-certificateInfo() {
    write-host "getting certificate info"

    if (!$x509Certificate -and !$global:x509Certificate) {
        if ($certificateBase64) {
            write-host "certificateBase64 specified. converting to certificate object"
            $secretByte = [System.Convert]::FromBase64String($certificateBase64)
            $x509Certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($secretByte, "", "Exportable,PersistKeySet")
        }
        elseif ($keyvaultName) {
            write-host "x509Certificate not specified. looking for certificate in keyvault: $keyvaultName"

            if (!(check-module)) {
                throw "failed to import az modules"
            }
        
            if (!(get-azresourcegroup)) {
                write-host "connect-azaccount"
                Connect-AzAccount -UseDeviceAuthentication
            }

            if ($keyvaultName -and $certificateName -and $keyvaultSecretVersion) {
                write-host "Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName -Version $keyvaultSecretVersion"
                $kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName -Version $keyvaultSecretVersion
            }        
            elseif ($keyvaultName -and $certificateName) {
                write-host "Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName"
                $kvCertificate = Get-AzKeyVaultCertificate -VaultName $keyvaultName -Name $certificateName
            }
            else {
                throw "keyvaultName and x509CertificateName not specified"
            }

            if (!$kvCertificate) {
                throw "Certificate not found in keyvault"
            }

            $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $kvCertificate.Name -AsPlainText;
            $secretByte = [Convert]::FromBase64String($secret)
            $x509Certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($secretByte, "", "Exportable,PersistKeySet")

        }
        elseif ($certificateName) {
            if ($global:isCloudShell) {
                write-host "cloud shell / unix"
                if (!$certificateBase64) {
                    throw "for cloudshell/linux systems not using keyvault, provide value for -certificateBase64"
                }
            }
            else {
                write-host "not cloud shell"
                write-host "get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Subject -ieq CN=$certificateName"
                $x509Certificate = Get-ChildItem -Path Cert:\ -Recurse | Where-Object Subject -ieq "CN=$certificateName"
                if (!$x509Certificate) {
                    write-host "failed to get certificate for thumbprint from local store: $certificateName" -foregroundColor red
                }
            }
        }
    }
    elseif (!$x509Certificate) {
        $x509Certificate = $global:x509Certificate
    }

    write-host "found certificate for: $certificateName" -foregroundColor yellow
    write-host "subject: $($x509Certificate.Subject)" -foregroundColor yellow
    write-host "issuer: $($x509Certificate.Issuer)" -foregroundColor yellow
    write-host "issue date: $($x509Certificate.NotBefore)" -foregroundColor yellow
    write-host "expiration date: $($x509Certificate.NotAfter)" -foregroundColor yellow
    write-host "thumbprint: $($x509Certificate.Thumbprint)" -foregroundColor yellow
    if (!$x509Certificate) {
        throw "failed to get certificate for thumbprint from keyvault: $certificateName"
    }

    $global:x509Certificate = $x509Certificate
    return $true
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

        if($portTestSucceeded){
            write-host "test-connection: computer:$hostName port:$port result:$portTestSucceeded" -ForegroundColor Green
        }
        else {
            write-error "test-connection: computer:$hostName port:$port result:$portTestSucceeded"
        }
        
        $tcpClient.Dispose()
        return $portTestSucceeded
    }
    catch [Exception] {
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
    $timeoutSeconds = $global:timeoutSeconds) {

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

if ($global:clusterHttpConnectionEndpoint -and $absolutePath) {
    invoke-request -absolutePath $absolutePath
}
else {
    main
}
