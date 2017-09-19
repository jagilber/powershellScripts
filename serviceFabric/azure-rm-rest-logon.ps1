<#
.\azure-rm-rest-logon.ps1 -certSubject "azure-rm-rest-logon" -applicationId "2b79cbdf-424f-48d2-a569-26ff7deb8625"
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


function main ()
{
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

    $data = $null
    $cert = $null

    if ($ClientSecret)
    {
        
    }
    elseif ($thumbPrint)
    {
        $cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -ieq $thumbPrint)
    }
    elseif ($certSubject)
    {
        $cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -imatch $certSubject)
    }
    else
    {
        $certSubject = [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
        Write-Warning "no cert info provided. trying $($certSubject)"
        $cert = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -imatch $certSubject)
    }

    #$keyValue = [Convert]::ToBase64String($cert.GetRawCertData())
    #$clientSecret = $keyValue

    #$pwd = ConvertTo-SecureString -String $credentials.Password -Force -AsPlainText
    #Export-PfxCertificate -cert "cert:\currentuser\my\$thumbprint" -FilePath $pfxPath -Password $pwd
    #            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate($pfxPath, $pwd)
    #            $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
    #            $clientsecret = $keyValue

    if ($cert)
    {
        $data = $cert.Thumbprint
        # works if using thumbprint only
        $enc = [text.encoding]::UTF8
        $bytes = $enc.GetBytes($data)
        $ClientSecret = [convert]::ToBase64String($bytes)
    }

    $tokenEndpoint = "https://login.windows.net/$($tenantId)/oauth2/token" 
    $armResource = "https://management.core.windows.net/"
    #$armResource = "https://graph.windows.net/"

    $Body = @{
        'resource'      = $armResource
        'client_id'     = $applicationId
        'grant_type'    = 'client_credentials'
        'client_secret' = $clientSecret
    }
    
    $params = @{
        ContentType = 'application/x-www-form-urlencoded' #'application/json'
        Headers     = @{'accept' = 'application/json'}
        Body        = $Body
        Method      = 'Post'
        URI         = $tokenEndpoint
    }

    $body
    $params
    $clientSecret

    $token = Invoke-RestMethod @params -Verbose -Debug
    #$token = Invoke-RestMethod @params -CertificateThumbprint $thumbPrint -Certificate $cert
    #$token | select-object access_token, @{L='Expires';E={[timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($_.expires_on))}} | Format-List *
    $token | format-list *
    $global:token = $token
}

main