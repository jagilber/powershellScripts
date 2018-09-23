<#
a4ad335c-65e5-469c-9df5-03ca816fb82b
13a5b24bd00cb110ef4b36a141c87483661f5bef
.\azure-rm-rest-logon.ps1 -certSubject "azure-rm-rest-logon" -applicationId "2b79cbdf-424f-48d2-a569-26ff7deb8625"
#>

[cmdletbinding()]
param(
    [string]$certSubject,
    [string]$thumbPrint,
    [string]$applicationId,
    [string]$clientSecret,
    [string]$tenantId
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

        $tenantId = (Get-AzureRmContext).Tenant.Id
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

    if ($cert)
    {
        $data = $cert.Thumbprint
        # works if using thumbprint only
        $enc = [text.encoding]::UTF8
        $bytes = $enc.GetBytes($data)
        $ClientSecret = [convert]::ToBase64String($bytes)
        $ClientSecret = [convert]::ToBase64String($cert.GetCertHash())
        write-host "clientsecret set to: $($clientSecret)"
    }

    $tokenEndpoint = "https://login.windows.net/$($tenantId)/oauth2/token" 
    $armResource = "https://management.core.windows.net/"

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
    $token | format-list *
    $global:token = $token
}

main