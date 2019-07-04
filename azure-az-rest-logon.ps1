<#
    script to authenticate for Azure Resource Manager REST API
    requires az* modules, setting up an azure ad application spn, and a self signed cert
    see azure-az-create-aad-application-spn.ps1 to setup the ad application and cert
    output is in $global:token and is used by .\azure-az-rest-query.ps1 script
#>

[cmdletbinding()]
param(
    [string]$certSubject,
    [string]$thumbPrint,
    [string]$certStore = "Cert:\CurrentUser\My",
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [switch]$force,
    [ValidateSet('arm', 'asm', 'graph')]
    [string]$logonType = "arm",
    [string]$resource,
    [string]$endpoint,
    [switch]$interactive
)

$ErrorActionPreference = "continue"
$error.Clear()
$aadDisplayName = "azure-az-rest-logon/$($env:Computername)"
$cert = $null
$resourceArg = $resource
$endpointArg = $endpoint

function main ()
{
    if (!(show-tokenInfo))
    {
        if (!$force)
        {
            Write-Warning "token has over 1/2 life left. use -force to force new token. returning"
            return $false
        }
        else
        {
            Write-Host "refreshing token..." -ForegroundColor Yellow
        }
    }

    if (!$tenantId)
    {
        if (!(check-az))
        {
            return $false
        }

        $tenantId = (Get-azContext).Tenant.Id
    }

    if (!$clientId)
    {
        if (!(check-az))
        {
            return $false
        }

        $clientIds = @((Get-azADApplication -DisplayNameStartWith $aadDisplayName).ApplicationId.Guid)
        $clientIds

        if ($clientIds.count -gt 1)
        {
            Write-Warning "multiple client ids / application ids found!!! trying first match only."
        }

        $clientId = $clientIds[0]
        
        if (!$clientId)
        {
            Write-Warning "clientid (applicationid) info not provided. exiting"
            return
        }
        
        Write-Warning "clientid (applicationid) info not provided. trying $($clientId)"
    }

    if (!$clientSecret)
    {
        foreach ($cert in Get-Certs)
        {
            if ((logon-rest $cert))
            {
                show-tokenInfo
                break
            }
        }
    }
    else 
    {
        logon-rest
        show-tokenInfo
    }
}

function acquire-token($resource, $endpoint)
{
    if($resourceArg)
    {
        $resource = $resourceArg
    }

    if($endpointArg)
    {
        $endpoint = $endpointArg
    }

    if($interactive)
    {
       $result = authorize-user -resource $resource -endpoint $endpoint
    }

    $result
    $error.clear()
    $Body = @{
        'resource'      = $resource
        'client_id'     = $clientId
        'grant_type'    = 'client_credentials'
        'client_secret' = $clientSecret
    }
    
    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers     = @{'accept' = '*/*'}
        Body        = $Body
        Method      = 'Post'
        URI         = $endpoint + "/token"
    }

    write-host ($body | convertto-json)
    write-host ($params | convertto-json)
    write-host $clientSecret
    $error.Clear()

    return Invoke-RestMethod @params -Verbose -Debug
}

function authorize-user($resource, $endpoint)
{
    $error.clear()
    $uri = $endpoint + "/authorize?&tenant=$tenantId&response_type=code&client_id=$clientId&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient"
    $params = @{
        Method      = 'Get'
        URI         = $uri
    }

    write-host ($params | convertto-json)
    #write-host $clientSecret
    $error.Clear()

    return Invoke-WebRequest @params -Verbose -Debug
}

function check-az()
{
    try
    {
        get-command connect-azaccount | Out-Null
    }
    catch [management.automation.commandNotFoundException]
    {
        if ((read-host "az not installed but is required for this script. is it ok to install?[y|n]") -imatch "y")
        {
            write-host "installing minimum required az modules..."
            install-module az.accounts
            install-module az.resources
            import-module az.accounts
            import-module az.resources
        }
        else
        {
            return $false
        }
    }

    if (Get-azContext)
    {
        return $true
    }

    if ($thumbPrint -and $clientId)
    {
        connect-azaccount -ServicePrincipal `
            -CertificateThumbprint $thumbPrint `
            -ApplicationId $clientId 
            #-TenantId $tenantId
    }
    else
    {
        if (!(connect-azaccount))
        {
            return $false
        }
    }

    return $true
}

function Get-Certs
{
    if ($thumbPrint)
    {
        $certs = @(Get-ChildItem $certStore | Where-Object Thumbprint -ieq $thumbPrint)
    }
    elseif ($certSubject)
    {
        $certs = @(Get-ChildItem $certStore | Where-Object Subject -imatch $certSubject)
    }
    else
    {
        $certSubject = $aadDisplayName
        Write-Warning "no cert info provided. trying $($certSubject)"
        $certs = @(Get-ChildItem $certStore | Where-Object {$_.Subject -imatch $certSubject -and $_.NotAfter -gt (get-date)})
    }
        
    if ($certs.count -gt 1)
    {
        $certs
        write-warning "multiple valid certs!"
    }

    return $certs
}

function logon-rest($cert)
{
    $error.Clear()

    if ($cert)
    {
        write-host ($cert | format-list *)
        # works if using thumbprint only
        $ClientSecret = [convert]::ToBase64String($cert.GetCertHash())
        write-host "clientsecret set to: $($clientSecret)"
        
        if ($cert.NotAfter -lt (get-date))
        {
            Write-Warning "cert is expired. run .\azure-az-create-aad-application-spn.ps1 to create new cert"
        }
    }

    $tokenEndpoint = "https://login.windows.net/$($tenantId)/oauth2" 
    $armResource = "https://management.azure.com/"
    $asmResource = "https://management.core.windows.net/"
    $graphResource = "https://graph.microsoft.com/"

    if ($logonType -eq "arm")
    {
        $token = acquire-token -resource $armResource -endpoint $tokenEndpoint
    }
    elseif ($logontype -eq "graph")
    {
        $tokenEndpoint = "https://login.microsoftonline.com/$($tenantId)/oauth2"
        $token = acquire-token -resource $graphResource -endpoint $tokenEndpoint
    }
    else
    {
        $token = acquire-token -resource $asmResource -endpoint $tokenEndpoint
    }

    if (!$error)
    {
        $global:token = $token
        Write-Output $global:token
        $global:clientId = $clientId
        write-host "$logonType access token output saved in `$global:token" -ForegroundColor Yellow
        write-host "clientid / applicationid saved in `$global:clientId" -ForegroundColor Yellow
        
        if ($ClientSecret)
        {
            $global:clientSecret = $clientSecret
            write-host "client secret saved in `$global:clientSecret" -ForegroundColor Yellow
        }
        
        return $true
    }
    else
    {
        $global:token = $null   
        return $false
    }
}

function show-tokenInfo()
{
    if ($global:token)
    {
        $currentToken = $global:token
        write-host "current token: $($currentToken)" -ForegroundColor Gray
        
        $epochDate = (get-date "1/1/1970")
        $epochTimeNow = [int64](([datetime]::UtcNow) - $epochDate).TotalSeconds
        $isExpired = $epochTimeNow -gt $currentToken.expires_on
        $outputColor = "Green"

        if ($isExpired)
        {
            $outputColor = "Red"
            $global:token = $null
        }

        $tokenLifetimeMinutes = [int]($currentToken.expires_in / 60)
        $notBefore = $epochDate.AddSeconds($currentToken.not_before).ToLocalTime()
        $notAfter = $epochDate.AddSeconds($currentToken.expires_on).ToLocalTime()
        $notBeforeUtc = $epochDate.AddSeconds($currentToken.not_before).ToString("o")
        $notAfterUtc = $epochDate.AddSeconds($currentToken.expires_on).ToString("o")
        $minutesLeft = $([int](($currentToken.expires_on - $epochTimeNow) / 60))

        write-host "current token info:" -ForegroundColor $outputColor
        write-host "`tepoch time now:`t$epochTimeNow" -ForegroundColor $outputColor
        write-host "`ttoken lifetime minutes:`t$tokenLifetimeMinutes" -ForegroundColor $outputColor
        write-host "`tnot before:`t$notBeforeUtc `t($notBefore)" -ForegroundColor $outputColor
        write-host "`tnot after:`t$notAfterUtc `t($notAfter)" -ForegroundColor $outputColor
        write-host "`tminutes left before expire:`t$minutesLeft" -ForegroundColor $outputColor
        write-host "`tis expired:`t$isExpired" -ForegroundColor $outputColor

        if (!$isExpired -and (($tokenLifetimeMinutes / $minutesLeft) -lt 2) -and !$force)
        {
            return $false
        }
    }

    return $true
}

main