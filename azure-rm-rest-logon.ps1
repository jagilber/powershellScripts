<#

#>

[cmdletbinding()]
param(
    [string]$certSubject,
    [string]$thumbPrint,
    [string]$applicationId,
    [string]$clientSecret,
    [string]$tenantId#,
    #   [string]$pfxPath = "$($env:temp)\$($aadDisplayName).pfx",
    #   [pscredential]$credentials = (get-credential)
)

$ErrorActionPreference = "stop"
$error.Clear()

#if (!$thumbPrint)
#{
#    Write-Error "need thumbprint to authenticate to rest. use azure-rm-create-aad-application-spn.ps1 to create aad spn for cert logon to azure for script"
#    exit 1
#}

if (!$tenantId)
{
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        Add-AzureRmAccount -ServicePrincipal `
            -CertificateThumbprint $thumbPrint `
            -ApplicationId $applicationId 
        #-TenantId $tenantId
    }

    $tenantId = (Get-AzureRmSubscription).TenantId
}

if ($thumbPrint)
{
    $cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -ieq $thumbPrint)
}
elseif ($certSubject)
{
    $cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -imatch $certSubject)
}
else
{
    Write-Warning "no cert info provided"
}

#$keyValue = [Convert]::ToBase64String($cert.GetRawCertData())
#$clientSecret = $keyValue

#$pwd = ConvertTo-SecureString -String $credentials.Password -Force -AsPlainText
#Export-PfxCertificate -cert "cert:\currentuser\my\$thumbprint" -FilePath $pfxPath -Password $pwd
#            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate($pfxPath, $pwd)
#            $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
#            $clientsecret = $keyValue
$enc = [system.Text.Encoding]::UTF8
$bytes = $enc.GetBytes($cert.Thumbprint)
$ClientSecret = [System.Convert]::ToBase64String($bytes)


$tokenEndpoint = "https://login.windows.net/$($tenantId)/oauth2/token" 
$armResource = "https://management.core.windows.net/"


$Body = @{
    'resource'      = $armResource
    'client_id'     = $applicationId
    'grant_type'    = 'client_credentials'
    'client_secret' = $ClientSecret
}
#$body = "<Binary>-----BEGIN CERTIFICATE-----`n$($clientSecret)`n-----END CERTIFICATE-----</Binary>"
$params = @{
    ContentType = 'application/x-www-form-urlencoded'
    Headers     = @{'accept' = 'application/json'}
    Body        = $Body
    Method      = 'Post'
    URI         = $tokenEndpoint
}

$params
$clientSecret

$token = Invoke-RestMethod @params
#$token = Invoke-RestMethod @params -CertificateThumbprint $thumbPrint -Certificate $cert

#$token | select-object access_token, @{L='Expires';E={[timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($_.expires_on))}} | Format-List *
$token | fl *
$global:token = $token