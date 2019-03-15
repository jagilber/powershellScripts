
<#
Set-AzureRmVMCustomScriptExtension `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -VMName $vmName `
    -Name $extensionName `
    -FileUri "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/cert.ps1" `
    -Run ".\cert.ps1" `
    -Argument "-appId $clientId -appPassword $clientSecret -tenantId $tenantId -vaultname $vault -secretname $certUrl" `
    -ForceRerun $(new-guid).Guid

#>

[cmdletbinding()]
param(
    [parameter(mandatory = $true)]
    [string]$appId,
    [parameter(mandatory = $true)]
    [string]$appPassword,
    [parameter(mandatory = $true)]
    [string]$tenantId,
    [parameter(mandatory = $true)]
    [string]$vaultName,
    [parameter(mandatory = $true)]
    [string]$secretName
)

function log
{
    param([string]$message)
    "`n`n$(get-date -f o)  $message" 
}

log "script running..."

#  requires WMF 5.0
#  verify NuGet package
#
$nuget = get-packageprovider nuget -Force
if (-not $nuget -or ($nuget.Version -lt 2.8.5.22))
{
    log "installing nuget package..."
    install-packageprovider -name NuGet -minimumversion 2.8.5.201 -force
}

#  install AzureRM module
#  min need AzureRM.profile, AzureRM.KeyVault
#
if (-not (get-module AzureRM -ListAvailable))
{ 
    log "installing AzureRm powershell module..." 
    install-module AzureRM -force 
} 

#  log onto azure account
#
log "logging onto azure account with app id = $appId ..."

$creds = new-object Management.Automation.PSCredential ($appId, (convertto-securestring $appPassword -asplaintext -force))
## todo remove after test
#login-azurermaccount -credential $creds -serviceprincipal -tenantid $tenantId -confirm:$false

#  get the secret from key vault
#
log "getting secret '$secretName' from keyvault '$vaultName'..."
$secret = get-azurekeyvaultsecret -vaultname $vaultName -name $secretName
log "secret: $secret"

$cert = get-azurekeyvaultcertificate -vaultname $vaultName -name $secretName
log "cert: $cert"

$certCollection = New-Object Security.Cryptography.X509Certificates.X509Certificate2Collection

$bytes = [Convert]::FromBase64String($secret.SecretValueText)
$certCollection.Import($bytes, $null, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
	
add-type -AssemblyName System.Web
$password = [Web.Security.Membership]::GeneratePassword(38, 5)
$protectedCertificateBytes = $certCollection.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $password)

$pfxFilePath = join-path $env:TEMP "$([guid]::NewGuid()).pfx"
log "writing the cert as '$pfxFilePath'..."
[io.file]::WriteAllBytes($pfxFilePath, $protectedCertificateBytes)

#  get cert info
#
$selfsigned = $false
$wildcard = $false
$cert = $null
$foundcert = $false
$san = $false

# look for enhanced key usage having 'server authentication' and ca false
#
foreach ($cert in $certCollection)
{
    if (!($cert.Extensions.CertificateAuthority) -and $cert.EnhancedKeyUsageList -imatch "Server Authentication")
    {
        $foundcert = $true
        break
    }
}

	
#  apply certificate
#
if($foundcert)
{
}
else
{
    log "unable to find cert"
    return 1
}

<#
#  clean up
#  
if (test-path($pfxFilePath))
{
    log "running cleanup..."
    remove-item $pfxFilePath
}
#>
  
log "done."

