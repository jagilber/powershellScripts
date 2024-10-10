<#
tests service fabric managed identity token service and azure metadata instance
#>
param(
  $secretUrl = 'https://<keyvault>.vault.azure.net/secrets/<secretName>/<secretVersion>',
  $identityHeader = $env:IDENTITY_HEADER, # 'eyAidHlwIiA...'
  $identityEndpoint = $env:IDENTITY_ENDPOINT, #'https://10.0.0.4:2377/metadata/identity/oauth2/token'
  $identityServerThumbprint = $env:IDENTITY_SERVER_THUMBPRINT,
  $identityApiVersion = $env:IDENTITY_API_VERSION, # '2020-05-01'
  $resource = 'https%3A%2F%2Fvault.azure.net',
  [switch]$useMetadataEndpoint
)

#$cert = (dir Cert:\LocalMachine\My\$env:IDENTITY_SERVER_THUMBPRINT)
$useCore = $PSVersionTable.PSEdition -ieq 'core'
$metadataIp = '169.254.169.254'

if (!$useCore) {
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
  $identityApiVersion = '2018-02-01'
  $response = invoke-restmethod -Uri "$($identityEndpoint)?api-version=$($identityApiVersion)&resource=$($resource)" `
    -Method 'get' `
    -Headers @{'Metadata' = 'true' }
}
else {
  $header = @{
    "Secret" = $env:IDENTITY_HEADER
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
  
  $response = invoke-restmethod @irmArgs
}

$response
$bearertoken = "Bearer " + $response.access_token
write-host "$bearertoken" -ForegroundColor Cyan

$result = Invoke-RestMethod -Uri "$($secretUrl)?api-version=2016-10-01" `
  -Method GET `
  -Headers @{Authorization = $bearertoken }

write-host "result $($result | convertto-json)" -ForegroundColor Cyan
