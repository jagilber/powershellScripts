<#
.SYNOPSIS
    powershell script to manage existing ADO managed service fabric cluster service connection server thumbprint

.NOTES
    - service fabric managed cluster 'client' certificate has to be in azure key vault
    - ADO AzurePowershell task must pass the following inputs:
        azureSubscription
    - ADO AzurePowershell task must pass the following variables:
        azureSubscriptionName: 
        sfmcCertificateName: 
        sfmcKeyVaultName: 
        sfmcServiceConnectionName: 

Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
MIT License
Copyright (c) Microsoft Corporation. All rights reserved.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://aka.ms/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
    ./sf-managed-ado-connection.ps1

.EXAMPLE
# build pipeline yaml example
variables:
  System.Debug: true
  azureSubscriptionName: 
  sfmcCertificateName: 
  sfmcKeyVaultName: 
  sfmcServiceConnectionName: 

steps:
  - task: AzurePowerShell@5
    inputs:
      azureSubscription: $(azureSubscriptionName)
      ScriptType: "InlineScript"
      Inline: |
        write-host "starting inline"
        [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
        invoke-webRequest "https://aka.ms/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
        ./sf-managed-ado-connection.ps1
        write-host "finished inline"
      errorActionPreference: continue
      azurePowerShellVersion: LatestVersion
    env:
      sfmcCertificateName: $(sfmcCertificateName)
      sfmcKeyVaultName: $(sfmcKeyVaultName)
      sfmcServiceConnectionName: $(sfmcServiceConnectionName)
      system_accessToken: $(System.AccessToken)

.EXAMPLE
# release pipeline yaml pseudo example
# uses variables:
#  sfmcCertificateName
#  sfmcKeyvaultName
#  sfmcServiceConnectionName

steps:
- task: AzurePowerShell@5
  displayName: 'Azure PowerShell script: InlineScript'
  inputs:
    azureSubscription: 
    ScriptType: InlineScript
    Inline: |
     write-host "starting inline"
     [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
     invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
      ./sf-managed-ado-connection.ps1
      write-host "finished inline"
    errorActionPreference: continue
    azurePowerShellVersion: LatestVersion
    pwsh: true
#>

[cmdletbinding()]
param(
    $apiVersion = '7.1-preview.4',
    $accessToken = $env:SYSTEM_ACCESSTOKEN,
    $sfmcServiceConnectionName = $env:SFMCSERVICECONNECTIONNAME,
    $keyVaultName = $env:SFMCKEYVAULTNAME,
    $certificateName = $env:SFMCCERTIFICATENAME,
    $writeDebug = ($env:SYSTEM_DEBUG -ieq 'true')
)

$PSModuleAutoLoadingPreference = 2

function main() {
    write-host "starting script:$([datetime]::now.tostring('o'))"

    if ($writeDebug) {
        $DebugPreference = $VerbosePreference = 'continue'
        $psversiontable
        [environment]::getenvironmentvariables().getenumerator() | Sort-Object Name    
    }

    $adoRestEndpointUrl = "$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI/$env:SYSTEM_TEAMPROJECTID/_apis/serviceendpoint/endpoints"
    $serviceConnection = get-adoSfConnection -adoRestEndpointUrl $adoRestEndpointUrl
    $adoServerCertThumbprint = $serviceConnection.Authorization.Parameters.servercertthumbprint

    write-verbose "adoServerCertThumbprint: $adoServerCertThumbprint"
    write-host "adoServerCertThumbprint length: $($adoServerCertThumbprint.length)"
    write-host "serviceConnection certificate length: $($serviceConnection.Authorization.Parameters.Certificate.length)"

    $serverThumbprint = get-sfmcArmServerThumbprint -serviceConnection $serviceConnection
    
    if ($adoServerCertThumbprint -ieq $serverThumbprint) {
        write-host "certificate thumbprints match. returning."
        write-verbose "$adoServerCertThumbprint -ieq $serverThumbprint"
        return
    }
    else {
        write-host "certificate thumbprints do not match. continuing."
        write-verbose "$adoServerCertThumbprint -ne $serverThumbprint"
    }

    $pfxCertBase64 = get-azKvPfxCertificateBase64 -serviceConnection $serviceConnection

    update-adoSfConnection -adoRestEndpointUrl $adoRestEndpointUrl `
        -serviceConnection $serviceConnection `
        -serverThumbprint $serverThumbprint `
        -pfxCertBase64 $pfxCertBase64
    write-host "finished script:$([datetime]::now.tostring('o'))"
}

function get-adoSfConnection ($adoRestEndpointUrl) {
    #
    # get current ado sf connection
    #
    write-host "getting service fabric service connection"
    
    $adoAuthHeader = @{
        'authorization' = "Bearer $accessToken"
        'content-type'  = 'application/json'
    }

    $bodyParameters = @{
        'type'          = 'servicefabric'
        'api-version'   = $apiVersion
        'endpointNames' = $sfmcServiceConnectionName
    }

    $parameters = @{
        Uri         = $adoRestEndpointUrl
        Method      = 'GET'
        Headers     = $adoAuthHeader
        Erroraction = 'continue'
        Body        = $bodyParameters
    }

    write-verbose "ado connection parameters: $($parameters | convertto-json)"
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($adoRestEndpointUrl)) -headers $adoAuthHeader"
   
    $error.clear()
    $adoConnection = invoke-RestMethod @parameters
    write-host "ado connection result: $($adoConnection | convertto-json)"

    if ($error) {
        write-error "exception: $($error | out-string)"
        return $null
    }

    write-host "ado connection: $($adoConnection.value)"
    $serviceConnection = @($adoConnection.value)[0]
    return $serviceConnection
}

function get-azKvPfxCertificateBase64($serviceConnection) {
    #
    # get cert from keyvault
    #
    # Export Key Vault Certificate as PFX
    try {
        $securePassword = $null
        if ($serviceConnection.Authorization.Parameters.CertificatePassword) {
            $securePassword = $serviceConnection.Authorization.Parameters.CertificatePassword | ConvertTo-SecureString -AsPlainText -Force
        }

        write-host "get-azkeyvaultCertificate -vaultName $keyVaultName -name $certificateName"
        $certificate = get-azkeyvaultCertificate -vaultName $keyVaultName -name $certificateName
        write-verbose "get-azkeyvaultCertificate result: $($certificate | convertto-json)"

        $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $certificate.Name -AsPlainText;
        $secretByte = [Convert]::FromBase64String($secret)
        $x509Cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($secretByte, "", "Exportable,PersistKeySet")
        $type = [Security.Cryptography.X509Certificates.X509ContentType]::Pfx
        $pfxFileByte = $x509Cert.Export($type, $securePassword);
        $pfxCertBase64 = [Convert]::ToBase64String($pfxFileByte)

        write-verbose "pfxcertbase64: $pfxCertBase64"
        write-host "certInfo length:$($certificate.length)"
    }
    catch {
        write-error "exception: $($error | out-string)"
    }
    finally {
        $securePassword = $null
        $certificate = $null
        $secret = $null
        $secretByte = $null
        $x509Cert = $null
        $type = $null
        $pfxFileByte = $null
    }
    return $pfxCertBase64
}

function get-sfmcArmServerThumbprint($serviceConnection) {
    #
    # get current sfmc server thumbprint
    #
    if (!(get-azresourcegroup)) {
        write-error "unable to enumerate resource groups"
        return
    }
    
    $serviceConnectionFqdn = [regex]::Match($serviceConnection.url, "tcp://(.+?):").Groups[1].Value
    write-host "`$cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn"
    $cluster = Get-azServiceFabricManagedCluster | Where-Object Fqdn -imatch $serviceConnectionFqdn

    if (!($cluster)) {
        write-error "unable to find cluster for fqdn: $serviceConnectionFqdn"
        return
    }

    write-verbose "get-servicefabricmanagedcluster result $($cluster | ConvertTo-Json -Depth 99)"
    $clusterId = $cluster.Id
    write-host "(Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints"
    $serverThumbprint = @((Get-AzResource -ResourceId $clusterId).Properties.clusterCertificateThumbprints)[0]

    if (!$serverThumbprint) {
        write-error "unable to get server thumbprint"
        return $false
    }
    else {
        write-verbose "server thumbprint:$serverThumbprint"
    }
    return $serverThumbprint
}

function update-adoSfConnection($adoRestEndpointUrl, $serviceConnection, $serverThumbprint, $pfxCertBase64) {
    #
    # update auth params
    #
    $serviceConnectionName = $serviceConnection.id
    write-host "serviceConnectionName: $serviceConnectionName"

    $authorizationParameters = @{
        certLookup           = $serviceConnection.Authorization.Parameters.CertLookup
        servercertthumbprint = $serverThumbprint
        certificate          = $pfxCertBase64
        certificatePassword  = $serviceConnection.Authorization.Parameters.CertificatePassword
    }

    write-verbose "new authorization parameters:$($authorizationParameters|convertto-json)"
    $serviceConnection.authorization.parameters = $authorizationParameters

    $adoAuthHeader = @{
        'authorization' = "Bearer $accessToken"
        'content-type'  = 'application/json'
    }

    $adoRestEndpointUrl += "/$($serviceConnectionName)?api-version=$apiVersion"
    $parameters = @{
        Uri         = $adoRestEndpointUrl
        Method      = 'PUT'
        Headers     = $adoAuthHeader
        Erroraction = 'continue'
        Body        = ($serviceConnection | convertto-json -compress -depth 99)
    }

    write-verbose "new service connection parameters: $($parameters | convertto-json -Depth 99)"
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($adoRestEndpointUrl)) -headers $adoAuthHeader"

    $error.clear()

    try {
        $result = invoke-restMethod @parameters
        if ($error) {
            write-error "error updating service endpoint $($error)"
            return $null    
        }
        else {
            write-host "endpoint updated successfully"
        }

        write-verbose "ado update result: $($result | convertto-json)"
    }
    catch {
        write-host "update exception $($_)`r`n$($error | out-string)"
    }

    try {
        $auth = $serviceConnection.Authorization
        write-host "executing task.setvariable for endpoint auth: $($auth|convertto-json)"
        write-host "##vso[task.setvariable variable=ENDPOINT_AUTH_$serviceConnectionName;]$($auth|convertto-json -depth 99 -compress)"
        if ($error) {
            write-warning "error updating env var: $($error | out-string)"
            return $null
        }
        return $true
    }
    catch { 
        write-host "exception $($error | out-string)"
        return $null
    }
}

main