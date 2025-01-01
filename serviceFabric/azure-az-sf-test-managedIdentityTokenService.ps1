<#
.SYNOPSIS
tests service fabric managed identity token service and azure metadata instance

.DESCRIPTION
This script is used to test the service fabric managed identity token service and the azure metadata instance. It will attempt to retrieve a secret from a key vault using the managed identity token service.

.PARAMETER secretUrl
  The URL of the secret in the key vault.

.PARAMETER identityHeader
  The identity header to use for the request.

.PARAMETER identityEndpoint
  The identity endpoint to use for the request.

.PARAMETER identityServerThumbprint
  The thumbprint of the identity server certificate.

.PARAMETER identityApiVersion
  The version of the identity API to use.

.PARAMETER resource
  The resource to request a token for.

.PARAMETER useMetadataEndpoint
  Use the metadata endpoint instead of the identity endpoint.

.EXAMPLE
  .\azure-az-sf-test-managedIdentityTokenService.ps1 -secretUrl 'https://<keyvault>.vault.azure.net/secrets/<secretName>/<secretVersion>'

.EXAMPLE
  .\azure-az-sf-test-managedIdentityTokenService.ps1 -useMetadataEndpoint

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-az-sf-test-managedIdentityTokenService.ps1" -outFile "$pwd/azure-az-sf-test-managedIdentityTokenService.ps1";
    ./azure-az-sf-test-managedIdentityTokenService.ps1

#>
param(
  $secretUrl = 'https://<keyvault>.vault.azure.net/secrets/<secretName>/<secretVersion>',
  $identityHeader = $env:IDENTITY_HEADER, # 'eyAidHlwIiA...'
  $identityEndpoint = $env:IDENTITY_ENDPOINT, #'https://10.0.0.4:2377/metadata/identity/oauth2/token'
  $identityServerThumbprint = $env:IDENTITY_SERVER_THUMBPRINT,
  $identityApiVersion = $env:IDENTITY_API_VERSION, # '2020-05-01' # 2448 has 2024-06-11
  $resource = 'https%3A%2F%2Fvault.azure.net',
  $resourceApiVersion = '2016-10-01',
  [switch]$useMetadataEndpoint
)

#$cert = (dir Cert:\LocalMachine\My\$env:IDENTITY_SERVER_THUMBPRINT)
$useCore = $PSVersionTable.PSEdition -ieq 'core'
$metadataIp = '169.254.169.254'
$irmArgs = @{}
[environment]::GetEnvironmentVariables().getEnumerator() | sort-object Name
$hasPolicy = !$useCore -and [System.Net.ServicePointManager]::CertificatePolicy.gettype() -eq [IDontCarePolicy]

function main() {
  $error.clear()

  if (!$useCore -and !$hasPolicy) {
    # -and ($null -eq [IDontCarePolicy])) {
    write-console 'adding type'
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
  
  if ($useMetadataEndpoint) {
    # container will need a static route to the host to reach the metadata endpoint
    if (!(tnc $metadataIp -p 80).TcpTestSucceeded) {
      route print
      $ipconfiguration = Get-NetIPConfiguration
      $interfaceAlias = $ipconfiguration.InterfaceAlias
      $defaultGateway = $ipconfiguration.IPv4DefaultGateway.NextHop
        
      Write-Warning "unable to connect to $metadataIp . adding static route to host with new-netRoute.
        New-NetRoute -DestinationPrefix '$metadataIp/32' -AddressFamily IPv4 -InterfaceAlias '$($interfaceAlias)' -NextHop '$($defaultGateway)'"
      New-NetRoute -DestinationPrefix "$metadataIp/32" -AddressFamily IPv4 -InterfaceAlias "$($interfaceAlias)" -NextHop "$($defaultGateway)"
        
      if (!(tnc $metadataIp -p 80).TcpTestSucceeded) {
        Write-Warning "unable to connect to $metadataIp. returning."
        return
      }
    }

    $identityEndpoint = "http://$metadataIp/metadata/identity/oauth2/token"
    # $identityApiVersion = '2018-02-01'
  
    $irmArgs = @{
      uri     = "$($identityEndpoint)?api-version=2018-02-01&resource=$($resource)"
      method  = 'get'
      headers = @{'Metadata' = 'true' } 
    }
  }
  else {
    $header = @{
      "Secret" = $identityHeader
    }
    
    $irmArgs = @{
      method  = 'get'
      uri     = "$($identityEndpoint)?api-version=$($identityApiVersion)&resource=$($resource)"
      headers = $header
      #certificateThumbprint = $cert
    }
    if ($useCore) {
      [void]$irmArgs.Add("SkipCertificateCheck", $true)
      [void]$irmArgs.Add("SkipHttpErrorCheck", $true)
    }
  }

  write-console "invoke-restMethod $($irmArgs | convertto-json)" -foregroundColor Cyan
  $response = invoke-restmethod @irmArgs

  write-console "response $($response | convertto-json)" -ForegroundColor Cyan
  if ($error) {
    write-console "error $($error | out-string)" -ForegroundColor Red
  }
  
  if ($response.error) {
    write-console "error $($response.error | convertto-json)" -ForegroundColor Red
    return
  }

  $bearertoken = "Bearer " + $response.access_token
  write-console "$bearertoken" -ForegroundColor Cyan

  if(!$bearertoken) {
    write-console "no bearer token" -ForegroundColor Red
    return
  }

  write-console "Invoke-RestMethod -Uri '$($secretUrl)?api-version=$($resourceApiVersion)' ``
      -Method GET ``
      -Headers @{Authorization = $bearertoken }" -foregroundColor Cyan

  $result = Invoke-RestMethod -Uri "$($secretUrl)?api-version=$($resourceApiVersion)" `
    -Method GET `
    -Headers @{Authorization = $bearertoken }

  write-console "result $($result | convertto-json)" -ForegroundColor Cyan
}

function write-console($message, $foregroundColor = 'White') {
  $message = "$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.ffff')) $message"
  write-host $message -ForegroundColor $foregroundColor
}

main