<#
.SYNOPSIS
    powershell script to manage existing ADO managed service fabric cluster service connection server thumbprint
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
    ./sf-managed-ado-connection.ps1
#>
[cmdletbinding()]
param(

)
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
#$verbosePreference = $debugpreference = 'continue'
$psversiontable
$connectionName = $env:connectionName
[environment]::getenvironmentvariables().getenumerator() | Sort-Object Name
#
# get current ado sf connection
#
write-host "getting service fabric service connection"
$url = "$env:SYSTEM_COLLECTIONURI/$env:SYSTEM_TEAMPROJECTID/_apis/serviceendpoint/endpoints"
$adoAuthHeader = @{
    'authorization' = "Bearer $env:accessToken"
    'content-type'  = 'application/json'
}
$bodyParameters = @{
    'type'          = 'servicefabric'
    'api-version'   = '7.1-preview.4'
    'endpointNames' = $connectionName
}
$parameters = @{
    Uri         = $url
    Method      = 'GET'
    Headers     = $adoAuthHeader
    Erroraction = 'continue'
    Body        = $bodyParameters
}
write-host "ado connection parameters: $($parameters | convertto-json)"
write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($url)) -headers $adoAuthHeader"
$error.clear()
$adoConnection = invoke-RestMethod @parameters
write-host "ado connection result: $($adoConnection | convertto-json)"
if ($error) {
    throw #(Get-VstsLocString -Key ADOAuthFailure -ArgumentList ($adoConnection | convertto-json))
}
write-host "ado connection: $($adoConnection.value)"
$serviceConnection = @($adoConnection.value)[0]
$serviceConnectionName = $serviceConnection.id
$adoServerCertThumbprint = $serviceConnection.Authorization.Parameters.servercertthumbprint
write-host "adoServerCertThumbprint: $adoServerCertThumbprint"
write-host "adoServerCertThumbprint length: $($adoServerCertThumbprint.length)"
write-host "serviceConnectionName: $serviceConnectionName"
write-host "serviceConnection certificate length: $($serviceConnection.Authorization.Parameters.Certificate.length)"
#
# get cert from keyvault
#
# From https://docs.microsoft.com/en-us/powershell/module/az.keyvault/get-azkeyvaultcertificate?view=azps-5.8.0
# Export new Key Vault Certificate as PFX
try {
    $securePassword = $null
    if ($serviceConnection.Authorization.Parameters.CertificatePassword) {
        $securePassword = $serviceConnection.Authorization.Parameters.CertificatePassword | ConvertTo-SecureString -AsPlainText -Force
    }

    write-host "get-azkeyvaultCertificate -vaultName $env:keyVaultName -name $env:certificateName"
    $certificate = get-azkeyvaultCertificate -vaultName $env:keyVaultName -name $env:certificateName
    write-host "get-azkeyvaultCertificate result: $($certInfo | convertto-json)"
    $secret = Get-AzKeyVaultSecret -VaultName $env:keyVaultName -Name $certificate.Name -AsPlainText;
    $secretByte = [Convert]::FromBase64String($secret)
    $x509Cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($secretByte, "", "Exportable,PersistKeySet")
    $type = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx
    $pfxFileByte = $x509Cert.Export($type, $securePassword);
    $pfxCertBase64 = [System.Convert]::ToBase64String($pfxFileByte)
    write-host "pfxcertbase64: $pfxCertBase64"
    write-host "certInfo length:$($certificate.length)"
}
catch {
    throw #(Get-VstsLocString -Key ErrorOnCertificateImport -ArgumentList $_)
}
#
# get current sfmc server thumbprint
#
if (!(get-azresourcegroup)) {
    write-error "unable to enumerate resource groups"
    return
}

$serviceConnectionFqdn = $serviceConnection.url.replace('tcp://', '').replace(':19000', '')
write-host "`$cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn"
$cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn

if (!($cluster)) {
    write-error "unable to find cluster for fqdn: $serviceConnectionFqdn"
    return
}
$cluster | ConvertTo-Json -Depth 99
$clusterId = $cluster.Id
write-host "(Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints" -ForegroundColor Green
$serverThumbprint = @((Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints)[0]

if (!$serverThumbprint) {
    write-error "unable to get server thumbprint"
    return
}
else {
    write-host "server thumbprint:$serverThumbprint" -ForegroundColor Cyan
}
if ($serverThumbprint -eq $global:clusterCertificateThumbprint) {
    write-host "certificate thumbprints match. returning."
    return $true
}
if($adoServerCertThumbprint -ieq $serverThumbprint) {
    write-host "$adoServerCertThumbprint -ieq $serverThumbprint `r`n returning"
    return
}
else {
    write-host "$adoServerCertThumbprint -ne $serverThumbprint `r`n continuing"
}
#
# update auth params
#
$authorizationParameters = @{
    certLookup           = $serviceConnection.Authorization.Parameters.CertLookup
    servercertthumbprint = $serverThumbprint
    certificate          = $pfxCertBase64
    certificatePassword  = $serviceConnection.Authorization.Parameters.CertificatePassword
}
write-host "new authorization parameters:$($authorizationParameters|convertto-json)"
$serviceConnection.authorization.parameters = $authorizationParameters

$adoAuthHeader = @{
    'authorization' = "Bearer $env:accessToken"
    'content-type'  = 'application/json'
}
$url = "$env:SYSTEM_COLLECTIONURI/$env:SYSTEM_TEAMPROJECTID/_apis/serviceendpoint/endpoints"
$url += "/$($serviceConnectionName)?api-version=7.1-preview.4"
$parameters = @{
    Uri         = $url
    Method      = 'PUT'
    Headers     = $adoAuthHeader
    Erroraction = 'continue'
    Body        = ($serviceConnection | convertto-json -compress -depth 99)
}
write-host "new service connection parameters: $($parameters | convertto-json -Depth 99)"
write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($url)) -headers $adoAuthHeader"

$error.clear()
try {
    $result = invoke-restMethod @parameters
    if ($error) {
        write-error "error updating service endpoint $($error)"
        throw (Get-VstsLocString -Key ADOUpdateFailure -ArgumentList ($result | convertto-json))
    }
    else {
        write-host "endpoint updated successfully"
    }

    write-host "ado update result: $($result | convertto-json)"
}
catch {
    write-host "update exception $($_)`r`n$($error | out-string)"
}
try {
    $auth = $serviceConnection.Authorization
    write-host "executing task.setvariable for endpoint auth: $($auth|convertto-json)"
    #write-host "##vso[task.setvariable variable=ENDPOINT_AUTH_$serviceConnectionName;issecret=true;isreadonly=true;isoutput=true]$($auth|convertto-json -depth 99 -compress)"
    write-host "##vso[task.setvariable variable=ENDPOINT_AUTH_$serviceConnectionName;]$($auth|convertto-json -depth 99 -compress)"
    if ($error) {
        write-warning "error updating env var: $($error | out-string)"
    }
}
catch { 
    write-host "exception $($error | out-string)" 
}
