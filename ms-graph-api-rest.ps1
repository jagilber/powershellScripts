<#
.SYNOPSIS
    microsoft graph rest api script 

.NOTES
    https://myapps.microsoft.com/ <--- can only be accessed from 'work' account
    have to set 'api permissions' on app registration. add 'microsoft graph' 'application permissions'
    https://docs.microsoft.com/en-us/graph/auth-v2-user
    https://login.microsoftonline.com/common/adminconsent?client_id={client-id}
    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow
    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
    
    https://docs.microsoft.com/en-us/azure/active-directory/develop/sample-v2-code

    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-protocols-oidc
    schema:
    https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/ms-graph-api-rest.ps1" -outFile "$pwd\ms-graph-api-rest.ps1";
    .\ms-graph-api-rest.ps1
#>
[cmdletbinding()]
param(
    $tenantId = 'common',
    [ValidateSet('v1.0', 'beta')]
    $apiVersion = 'beta', #'v1.0'
    $graphApiUrl = "https://graph.microsoft.com/$apiVersion/$tenantId/",
    $query = 'applications', #'$metadata#applications',
    $clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e', # well-known ps graph client id generated on connect
    $clientSecret,
    [ValidateSet("get", "post")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded', 'application/json', 'application/xml', '*/*')]
    $contentType = 'application/json', # '*/*',
    $body = @{},
    $accessToken = $global:accessToken,
    $headers = @{
        'authorization'    = "Bearer $accessToken"
        'accept'           = $contentType
        'consistencylevel' = 'eventual'
        'content-type'     = $contentType
    },
    $scope = 'user.read openid profile Application.ReadWrite.All User.ReadWrite.All Directory.ReadWrite.All', # 'https://graph.microsoft.com/.default', #'Application.Read.All offline_access user.read mail.read',
    [ValidateSet('urn:ietf:params:oauth:grant-type:device_code', 'client_credentials', 'authorization_code')]
    $grantType = 'urn:ietf:params:oauth:grant-type:device_code', #'client_credentials', #'authorization_code'
    #$redirectUrl = 'http://localhost',
    [switch]$force
)

$global:logonResult = $null

function main() {
    if (!$clientId -and !$clientSecret) {
        write-error '$clientid and $clientSecret need to be specified'
        return
    }

    if (!$global:accessToken -or ($global:accessTokenExpiration -lt (get-date)) -or $force) {
        get-restToken
    }

    call-graphQuery
    write-host "use: `$global:restResults" -ForegroundColor Cyan
}

function get-restAuth() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    write-host "auth request" -ForegroundColor Green
    $error.clear()
    $uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode"

    $Body = @{
        'client_id' = $clientId
        'scope'     = $scope
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Body        = $Body
        Method      = 'post'
        URI         = $uri
    }
    
    Write-Verbose ($params | convertto-json)
    $error.Clear()
    write-host "invoke-restMethod $uri" -ForegroundColor Cyan
    $global:authresult = Invoke-RestMethod @params -Verbose -Debug
    write-host "auth result: $($global:authresult | convertto-json)"
    write-host "rest auth finished"

    return ($global:authresult -ne $null)
}

function get-restToken() {
    # requires app registration api permissions with 'devops' added
    # will retry on device code until complete

    write-host "token request" -ForegroundColor Green
    $global:logonResult = $null
    $error.clear()
    $uri = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    $headers = @{
        'content-type' = 'application/x-www-form-urlencoded'
        'accept'       = $contentType
    }

    if ($grantType -ieq 'urn:ietf:params:oauth:grant-type:device_code') {
        get-restAuth
        $Body = @{
            'client_id'   = $clientId
            'device_code' = $global:authresult.device_code
            'grant_type'  = $grantType 
        }
    }
    elseif ($grantType -ieq 'client_credentials') {
        $Body = @{
            'client_id'     = $clientId
            'client_secret' = $clientSecret
            'grant_type'    = $grantType 
        }
    }
    elseif ($grantType -ieq 'authorization_code') {
        get-restAuth
        $Body = @{
            'client_id'  = $clientId
            'code'       = $global:authresult.code
            'grant_type' = $grantType 
        }
    }

    $params = @{
        Headers = $headers 
        Body    = $Body
        Method  = 'Post'
        URI     = $uri
    }

    write-verbose ($params | convertto-json)
    write-host "invoke-restMethod $uri" -ForegroundColor Cyan

    $startTime = (get-date).AddSeconds($global:authresult.expires_in)

    while ($startTime -gt (get-date)) {
        $error.Clear()

        try {
            $global:logonResult = Invoke-RestMethod @params -Verbose -Debug
            write-host "logon result: $($global:logonResult | convertto-json)"
            $global:accessToken = $global:logonResult.access_token
            $global:accessTokenExpiration = ((get-date).AddSeconds($global:logonResult.expires_in))
            return ($global:accessToken -ne $null)
        }
        catch [System.Exception] {
            $errorMessage = ($_ | convertfrom-json)

            if ($errorMessage -and ($errorMessage.error -ieq 'authorization_pending')) {
                write-host "waiting for device token result..." -ForegroundColor Yellow
                write-host "$($global:authresult.message)" -ForegroundColor Green
                start-sleep -seconds $global:authresult.interval
            }
            else {
                write-host "exception: $($error | out-string)`r`n this: $($_)`r`n"
                write-host "logon error: $($errorMessage | convertto-json)"
                write-host "breaking"
                break
            }
        }
    }

    write-host "rest logon returning"
    return ($global:accessToken -ne $null)
}

function call-graphQuery () {
    write-host "executing graph query" -ForegroundColor Green

    $adoAuthHeader = $headers.Clone()
    $adoAuthHeader.authorization = "Bearer $global:accessToken"
    $uri = $graphApiUrl + $query
    $global:restResults = [collections.ArrayList]::new()

    while ($true) {
        $parameters = @{
            Uri         = $uri
            Method      = $method
            Headers     = $adoAuthHeader
            Erroraction = 'continue'
            Body        = $body
        }

        Write-Verbose "graph connection parameters: $($parameters | convertto-json)"
        write-host "invoke-restMethod $uri" -ForegroundColor Cyan
        
        $error.clear()
        $global:restQuery = invoke-restMethod @parameters
        [void]$global:restResults.Add($global:restQuery.value)
        write-host "rest result: $($global:restQuery| convertto-json)"

        if ($error) {
            write-error "exception: $($error | out-string)"
            return $null
        }

        if (!($restQuery.'@odata.nextLink')) {
            write-verbose "no next link"
            break
        }
        else {
            $uri = $restQuery.'@odata.nextLink'
        }
    }
    return $global:restResults
}

main