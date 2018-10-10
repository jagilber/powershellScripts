<#
a4ad335c-65e5-469c-9df5-03ca816fb82b
13a5b24bd00cb110ef4b36a141c87483661f5bef
.\azure-rm-rest-logon.ps1 -certSubject "azure-rm-rest-logon" -clientId "2b79cbdf-424f-48d2-a569-26ff7deb8625"
#>

[cmdletbinding()]
param(
    [string]$certSubject,
    [string]$thumbPrint,
    [string]$clientId,
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
                -ApplicationId $clientId 
            #-TenantId $tenantId
        }

        $tenantId = (Get-AzureRmContext).Tenant.Id
    }

    $data = $null
    $cert = $null

    if (!$clientId)
    {
        $baseScriptName = [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
        $clientId = ((Get-AzureRmADApplication -DisplayNameStartWith ($baseScriptName)))[0].ApplicationId.Guid
        
        if (!$clientId)
        {
            Write-Warning "clientid (applicationid) info not provided. exiting"
            return
        }
        
        Write-Warning "clientid (applicationid) info not provided. trying $($clientId)"
    }

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
        'resource' = $armResource
        'client_id' = $clientId
        'grant_type' = 'client_credentials'
        'client_secret' = $clientSecret
    }
    
    $params = @{
        ContentType = 'application/x-www-form-urlencoded' #'application/json'
        Headers = @{'accept' = 'application/json'}
        Body = $Body
        Method = 'Post'
        URI = $tokenEndpoint
    }

    $body
    $params
    $clientSecret
    $error.Clear()
    $token = Invoke-RestMethod @params -Verbose -Debug
    
    if (!$error)
    {
        $global:token = $token
        Write-Output $global:token
        $global:clientId = $clientId
        write-host "access token output saved in `$global:token" -ForegroundColor Yellow
        write-host "clientid / applicationid saved in `$global:clientId" -ForegroundColor Yellow
    }
    else
    {
        $global:token = $null   
    }
}

main