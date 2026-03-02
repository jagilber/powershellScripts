<#
.SYNOPSIS
    Connect to a Service Fabric cluster from windows or linux powershell without Service Fabric SDK

.DESCRIPTION
    Can be used from windows or linux powershell.
    Can be used from Azure Cloud Shell local or remote.
    Certificate can be stored in local certificate store, keyvault, or provided as a base64 encoded string.

.NOTES
    File Name: sf-http-client.ps1
    Author   : jagilber
    Requires : PowerShell Version 5.1 or greater
        231011 - fix rest query
        
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

.PARAMETER validateOnly
        validates certificate EKU, chain, expiration, and private key without connecting to the cluster.

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

.EXAMPLE
    ./sf-http-client.ps1 -absolutePath "/EventsStore/Nodes/Events" -queryParameters @{StartTimeUtc=$eventStartTime;EndTimeUtc=$eventStopTime}

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateName sfclustercert -validateOnly
    validates certificate EKU (server/client authentication), chain, expiration, and private key access without connecting to cluster.

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateName sfclustercert
    example connection where server certificate differs from client certificate.
    the script automatically retrieves the server certificate from the cluster endpoint via TLS handshake.
    if the server cert thumbprint differs from the client cert, the server cert thumbprint is used for -ServerCertThumbprint
    and -ServerCommonName is set to the server certificate CN for proper TLS validation.
    EKU requirements: client certificate needs 'Client Authentication' (1.3.6.1.5.5.7.3.2).
    server certificate needs 'Server Authentication' (1.3.6.1.5.5.7.3.1). certificates with no EKU extension allow all purposes.

.EXAMPLE
    ./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateName sfclustercert
    example connection where the cluster uses a self-signed server certificate.
    the script detects self-signed certificates (subject == issuer) and automatically adds the server certificate
    to CurrentUser\Root trusted store via certutil for TLS validation. this avoids certificate chain trust errors
    when the server certificate is not signed by a well-known CA.

.EXAMPLE
    Connect-SFCluster -ConnectionEndpoint https://mycluster.eastus.cloudapp.azure.com:19080 `
        -ServerCertThumbprint <serverCertThumbprint> `
        -X509Credential `
        -FindType FindByThumbprint `
        -FindValue <clientCertThumbprint> `
        -StoreLocation CurrentUser `
        -StoreName My `
        -ServerCommonName mycluster.eastus.cloudapp.azure.com
    example reconnect command using Connect-SFCluster directly after initial connection.
    use -ServerCertThumbprint with the server certificate thumbprint (not client) when they differ.
    use -ServerCommonName with the server certificate CN for TLS hostname validation.
    the script outputs this reconnect command with actual values after a successful connection.

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

    [Parameter(ParameterSetName = "rest")]
    [hashtable]$queryParameters = @{},

    [string]$apiVersion = '9.1',

    [string]$timeoutSeconds = '10',

    [switch]$examples,

    [switch]$validateOnly
)

$global:sfHttpModule = 'Microsoft.ServiceFabric.Powershell.Http'
$global:isCloudShell = $PSVersionTable.Platform -ieq 'Unix'
$global:apiVersion = $apiVersion
$global:timeoutSeconds = $timeoutSeconds
$scriptName = "$psscriptroot/$($MyInvocation.MyCommand.Name)"
$eventStartTimeUtc = (get-date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$eventEndTimeUtc = (get-date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

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
            Install-Module -Name $global:sfHttpModule -AllowPrerelease -AllowClobber -Force
        }
        Import-Module $global:sfHttpModule
    }

    if (!(get-module $global:sfHttpModule)) {
        throw "$global:sfHttpModule not found"
    }

    if ($validateOnly) {
        write-host "certificate validation complete. exiting." -foregroundColor cyan
        return
    }

    if ($absolutePath) {
        invoke-request -absolutePath $absolutePath -queryParameters $queryParameters
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
        # get the actual server certificate from the endpoint
        $serverCert = get-serverCertificate -endpoint $clusterHttpConnectionEndpoint
        $serverCertThumbprint = $global:x509Certificate.Thumbprint

        if ($serverCert) {
            $serverCertThumbprint = $serverCert.Thumbprint
            write-host "server certificate thumbprint: $serverCertThumbprint" -foregroundColor cyan
            write-host "server certificate subject: $($serverCert.Subject)" -foregroundColor cyan

            if ($serverCertThumbprint -ne $global:x509Certificate.Thumbprint) {
                write-host "NOTE: server certificate thumbprint differs from client certificate thumbprint." -foregroundColor yellow
            }

            # for self-signed server certificates, install to trusted root store using certutil (non-interactive)
            if ($serverCert.Subject -eq $serverCert.Issuer) {
                $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("Root", "CurrentUser")
                $rootStore.Open("ReadOnly")
                $inStore = $rootStore.Certificates | Where-Object Thumbprint -eq $serverCertThumbprint
                $rootStore.Close()

                if (!$inStore) {
                    write-host "self-signed server certificate not in trusted root store. adding to CurrentUser\Root for TLS validation." -ForegroundColor Yellow
                    $tempCer = [System.IO.Path]::GetTempFileName() + ".cer"
                    try {
                        [System.IO.File]::WriteAllBytes($tempCer, $serverCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
                        $certutilResult = certutil -user -addstore Root $tempCer 2>&1
                        write-host "certutil result: $certutilResult" -ForegroundColor Gray
                    }
                    finally {
                        if (Test-Path $tempCer) { Remove-Item $tempCer -Force }
                    }
                }
            }
        }

        $connectParams = @{
            ConnectionEndpoint   = $clusterHttpConnectionEndpoint
            ServerCertThumbprint = $serverCertThumbprint
            X509Credential       = $true
            FindType             = 'FindByThumbprint'
            FindValue            = $global:x509Certificate.Thumbprint
            StoreLocation        = 'CurrentUser'
            StoreName            = 'My'
            Verbose              = $true
        }

        if ($serverCert) {
            $serverCommonName = $serverCert.GetNameInfo('SimpleName', $false)
            write-host "using ServerCommonName: $serverCommonName" -foregroundColor cyan
            $connectParams['ServerCommonName'] = $serverCommonName
        }

        Connect-SFCluster @connectParams
        if ($error -or !(Test-SFClusterConnection)) {
            write-host "Connect-SFCluster failed. falling back to direct REST calls." -foregroundColor yellow
            write-host "use: .\sf-http-client.ps1 -absolutePath '/`$/GetClusterHealth'" -foregroundColor cyan
            $error.clear()
            $healthResult = invoke-request -absolutePath '/$/GetClusterHealth'
            if ($healthResult) {
                write-host "direct REST connection successful. cluster health:" -foregroundColor green
                $healthResult | convertto-json -depth 5
            }
            return
        }
    }

    if (!($global:SFHttpClusterConnection)) {
        $global:SFHttpClusterConnection = $SFHttpClusterConnection
    }

    # retrieve server cert for reconnect example if not already fetched
    if (!$serverCert) {
        $serverCert = get-serverCertificate -endpoint $clusterHttpConnectionEndpoint
    }

    $global:sfHttpCommands = (get-command -module $global:sfHttpModule | Where-Object name -inotmatch 'mesh' | Select-Object name).name

    write-host "use script with -absolutePath argument to make rest requests to the cluster. example:./sf-http-client.ps1 -absolutePath '/$/GetClusterHealth'"
    write-host "current cluster connection:`$global:SFHttpClusterConnection`r`n$($global:SFHttpClusterConnection | out-string)" -foregroundcolor cyan
    write-host "available commands:stored in `$global:sfHttpCommands`r`n $($global:sfHttpCommands | out-string)" -foregroundcolor cyan

    write-host "Get-SFClusterVersion | convertto-json"
    Get-SFClusterVersion | convertto-json

    write-host "example commands:" -ForegroundColor Blue
    write-host "`t.\sf-http-client.ps1 -absolutePath '/EventsStore/Nodes/Events' -queryParameters @{StartTimeUtc='$eventStartTime';EndTimeUtc='$eventStopTime'}" -foregroundColor Blue
    write-host "`tGet-SFClusterEventList -StartTimeUtc '$eventStartTimeUtc' -EndTimeUtc '$eventEndTimeUtc'" -foregroundColor Blue
    write-host "`tRestart-SFNode -NodeName _nt0_2 -NodeInstanceId 0 # <-always 0" -foregroundColor Blue
    write-host "`tDisable-SFNode -NodeName _nt0_2 -DeactivationIntent Restart -Force" -foregroundColor Blue
    write-host "`tGet-SFApplication | Get-SFService" -foregroundColor Blue
    write-host "`t`$applications = Get-SFApplication" -foregroundColor Blue
    write-host "`t`$services = @(`$applications).ForEach{Get-SFService -ApplicationId `$psitem.applicationId}" -foregroundColor Blue
    write-host "`t`$partitions = @(`$services).ForEach{Get-SFPartition -ServiceId `$psitem.ServiceId}" -foregroundColor Blue
    write-host "`t`$replicas = @(`$partitions).ForEach{Get-SFReplica -PartitionId `$psitem.partitionId}" -foregroundColor Blue
    write-host
    write-host "successfully connected to cluster. use function 'Connect-SFCluster' to reconnect to cluster if needed. example:" -foregroundcolor White
    $reconnectExample = "Connect-SFCluster -ConnectionEndpoint $clusterHttpConnectionEndpoint ``
        -ServerCertThumbprint $(if ($serverCert) { $serverCert.Thumbprint } else { $global:x509Certificate.Thumbprint }) ``
        -X509Credential ``
        -FindType FindByThumbprint ``
        -FindValue $($global:x509Certificate.Thumbprint) ``
        -StoreLocation CurrentUser ``
        -StoreName My"
    if ($serverCert) {
        $reconnectExample += " ``
        -ServerCommonName $($serverCert.GetNameInfo('SimpleName', $false))"
    }
    write-host "$reconnectExample ``
        -verbose
        "  -foregroundcolor Gray
    write-host "enter 'help *-SF*' to see list of available commands" -foregroundcolor White
}

function get-serverCertificate($endpoint) {
    try {
        $match = [regex]::match($endpoint, '^(?:http.?://)?(?<hostName>[^:]+?):(?<port>\d+)$')
        $hostName = $match.Groups['hostName'].Value
        $port = $match.Groups['port'].Value

        $tcpClient = [Net.Sockets.TcpClient]::new($hostName, [int]$port)
        $sslStream = [Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { $true })
        $sslStream.AuthenticateAsClient($hostName)
        $serverCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($sslStream.RemoteCertificate)
        $sslStream.Dispose()
        $tcpClient.Dispose()
        return $serverCert
    }
    catch {
        write-host "unable to retrieve server certificate: $($_.Exception.Message)" -foregroundColor yellow
        return $null
    }
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

            if(!(get-module az.accounts)) { import-module az.accounts }
            if(!(get-module az.keyvault)) { import-module az.keyvault}
            if(!(get-module az.resources)) { import-module az.resources}
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    if (!@(get-azResourceGroup).Count -gt 0) {
        Connect-AzAccount
    }

    if (!@(get-azResourceGroup).Count -gt 0) {
        return $false
    }

    return $true
}

function get-certificateInfo() {
    write-host "getting certificate info"
    $global:x509Certificate = $null

    if (!$x509Certificate) {
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
                write-host "get-childitem -Path Cert:\ -Recurse | Where-Object Subject -ieq CN=$certificateName"
                $certs = @(Get-ChildItem -Path Cert:\ -Recurse | Where-Object Subject -ieq "CN=$certificateName")
                if ($certs.Count -gt 1) {
                    write-host "found $($certs.Count) certificates matching CN=$certificateName. selecting most recent non-expired cert with private key." -foregroundColor yellow
                    $x509Certificate = $certs | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } | Sort-Object NotBefore -Descending | Select-Object -First 1
                    if (!$x509Certificate) {
                        write-host "no non-expired certificates with private key found. selecting most recent with private key." -foregroundColor yellow
                        $x509Certificate = $certs | Where-Object { $_.HasPrivateKey } | Sort-Object NotBefore -Descending | Select-Object -First 1
                    }
                    if (!$x509Certificate) {
                        write-host "no certificates with private key found. selecting most recent non-expired." -foregroundColor yellow
                        $x509Certificate = $certs | Where-Object { $_.NotAfter -gt (Get-Date) } | Sort-Object NotBefore -Descending | Select-Object -First 1
                    }
                    if (!$x509Certificate) {
                        $x509Certificate = $certs | Sort-Object NotBefore -Descending | Select-Object -First 1
                    }
                }
                elseif ($certs.Count -eq 1) {
                    $x509Certificate = $certs[0]
                }
                if (!$x509Certificate) {
                    write-host "failed to get certificate from local store: CN=$certificateName" -foregroundColor red
                }
            }
        }
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

    validate-certificate -cert $x509Certificate
    $global:x509Certificate = $x509Certificate
    return $true
}

function validate-certificate([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert) {
    $hasErrors = $false
    $serverAuthOid = '1.3.6.1.5.5.7.3.1'
    $clientAuthOid = '1.3.6.1.5.5.7.3.2'

    # check expiration
    if ($cert.NotAfter -lt (Get-Date)) {
        write-warning "CERTIFICATE EXPIRED: $($cert.NotAfter). thumbprint: $($cert.Thumbprint)"
        $hasErrors = $true
    }
    elseif ($cert.NotAfter -lt (Get-Date).AddDays(30)) {
        write-warning "CERTIFICATE EXPIRES SOON: $($cert.NotAfter). thumbprint: $($cert.Thumbprint)"
    }

    # check EKU
    $ekuExtension = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] }
    if ($ekuExtension) {
        $ekuOids = @($ekuExtension.EnhancedKeyUsages | ForEach-Object { $_.Value })
        $hasServerAuth = $ekuOids -contains $serverAuthOid
        $hasClientAuth = $ekuOids -contains $clientAuthOid

        write-host "EKU: $($ekuExtension.EnhancedKeyUsages | ForEach-Object { "$($_.FriendlyName) ($($_.Value))" })" -foregroundColor yellow

        if (!$hasClientAuth) {
            write-host "NOTE: certificate does not have Client Authentication EKU ($clientAuthOid). SF supports server-only EKU configs but some client operations may require Client Authentication EKU. thumbprint: $($cert.Thumbprint)" -foregroundColor darkyellow
        }
        if (!$hasServerAuth) {
            write-host "NOTE: certificate does not have Server Authentication EKU ($serverAuthOid). thumbprint: $($cert.Thumbprint)" -foregroundColor darkyellow
        }
    }
    else {
        write-host "EKU: (none - all purposes allowed)" -foregroundColor yellow
    }

    # check certificate chain
    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
    $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
    $chainBuilt = $chain.Build($cert)

    write-host "certificate chain valid: $chainBuilt" -foregroundColor $(if ($chainBuilt) { 'green' } else { 'red' })
    foreach ($element in $chain.ChainElements) {
        write-host "  chain element: $($element.Certificate.Subject) (thumbprint: $($element.Certificate.Thumbprint))" -foregroundColor yellow
    }

    if (!$chainBuilt) {
        foreach ($status in $chain.ChainStatus) {
            write-warning "CHAIN ERROR: $($status.StatusInformation.Trim()) ($($status.Status))"
        }
        $hasErrors = $true
    }

    # check private key access
    if (!$cert.HasPrivateKey) {
        write-warning "CERTIFICATE HAS NO PRIVATE KEY. client certificate authentication requires a private key. thumbprint: $($cert.Thumbprint)"
        $hasErrors = $true
    }
    else {
        write-host "private key: present" -foregroundColor green
    }

    $chain.Dispose()

    if ($hasErrors) {
        write-host "certificate validation completed with errors. review warnings above." -foregroundColor red
    }
    else {
        write-host "certificate validation passed." -foregroundColor green
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

        if ($portTestSucceeded) {
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
    $queryParameters = @{},
    $endpoint = $global:clusterHttpConnectionEndpoint,
    $x509Certificate = $global:x509Certificate,
    $apiVersion = $global:apiVersion,
    $timeoutSeconds = $global:timeoutSeconds) {

    $queryParameterString = ''

    if (!$absolutePath) {
        write-error "absolutePath not specified"
        return $null
    }
    if ($queryParameters) {
        foreach ($queryParameter in $queryParameters.GetEnumerator()) {
            $queryParameterString += "&$($queryParameter.Name)=$($queryParameter.Value)"
        }
    }
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

    $baseUrl = "$($endpoint)/$($absolutePath)?api-version=$($apiVersion)&timeout=$($timeoutSeconds)$($queryParameterString)"

    write-host "Invoke-RestMethod -Uri '$baseUrl' -certificate `$x509Certificate -SkipCertificateCheck -timeoutSec $timeoutSeconds" -ForegroundColor Cyan #-SkipHttpErrorCheck"
    $result = Invoke-RestMethod -Uri $baseUrl -certificate $x509Certificate -SkipCertificateCheck -timeoutSec $timeoutSeconds

    write-verbose $result | convertfrom-json | convertto-json -depth 99
    return $result
}

if ($global:clusterHttpConnectionEndpoint -and $absolutePath) {
    invoke-request -absolutePath $absolutePath -queryParameters $queryParameters
}
else {
    main
}
