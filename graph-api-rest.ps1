<#
.SYNOPSIS
test graph rest script 

.NOTES
    https://myapps.microsoft.com/ <--- can only be accessed from 'work' account
    have to set 'api permissions' on app registration. add 'microsoft graph' 'application permissions'
    https://docs.microsoft.com/en-us/graph/auth-v2-user
    https://login.microsoftonline.com/common/adminconsent?client_id={client-id}
    https://login.microsoftonline.com/common/adminconsent?client_id=
    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow
    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
    https://login.microsoftonline.com/common/adminconsent?client_id=6731de76-14a6-49ae-97bc-6eba6914391e&state=12345&redirect_uri=http://localhost/myapp/permissions
    https://stackoverflow.com/questions/66106927/webview2-in-powershell-winform-gui
    BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))
    https://docs.microsoft.com/en-us/azure/active-directory/develop/sample-v2-code

    https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-protocols-oidc
    schema:
    https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/graph-api-rest.ps1" -outFile "$pwd\graph-api-rest.ps1";
    .\graph-api-rest.ps1
#>
[cmdletbinding()]
param(
    $tenantId = 'common',
    [ValidateSet('v1.0', 'beta')]
    $apiVersion = 'beta', #'v1.0'
    $graphApiUrl = "https://graph.microsoft.com/$apiVersion/$tenantId/",
    $query = 'applications', #'$metadata#applications',
    $clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e', # well-known ps aad client id generated on connect
    $clientSecret,
    [ValidateSet("get", "post")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded', 'application/json', 'application/xml', '*/*')]
    $contentType = 'application/json', # '*/*',
    $body = @{},
    $headers = @{'accept' = $contentType },
    $scope = 'user.read openid profile Application.Read.All', # 'https://graph.microsoft.com/.default', #'Application.Read.All offline_access user.read mail.read',
    [ValidateSet('urn:ietf:params:oauth:grant-type:device_code', 'client_credentials', 'authorization_code')]
    $grantType = 'urn:ietf:params:oauth:grant-type:device_code', #'client_credentials', #'authorization_code'
    $redirectUrl = 'http://localhost',
    [switch]$force
)

$global:logonResult = $null

function main() {
    if (!$clientId -and !$clientSecret) {
        write-error '$clientid and $clientSecret need to be specified'
        return
    }

    if (!$global:accessToken -or ($global:accessTokenExpiration -lt (get-date)) -or $force) {
        get-restAuth
        get-restToken
    }

    call-graphQuery
    write-host "use: `$global:restQuery"
}

function get-restAuth() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    write-host "auth request"
    $error.clear()
    $endpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode"

    $Body = @{
        'client_id' = $clientId
        'scope'     = $scope
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Body        = $Body
        Method      = 'post'
        URI         = $endpoint
    }
    
    write-host ($params | convertto-json)
    $error.Clear()

    $global:authresult = Invoke-RestMethod @params -Verbose -Debug
    write-host "auth result: $($global:authresult | convertto-json)"
    write-host "rest auth finished"
    return ($global:authresult -ne $null)
}

function get-restToken() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    # will fail on device code until complete
    $startTime = (get-date).AddSeconds($global:authresult.expires_in)

    write-host "rest logon"
    $global:logonResult = $null
    $error.clear()
    $endpoint = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    $headers = @{
        'content-type' = 'application/x-www-form-urlencoded'
        'accept'       = $contentType
    }

    $Body = @{
        'client_id'   = $clientId
        'device_code' = $global:authresult.device_code
        'grant_type'  = $grantType #'client_credentials' #'authorization_code'
    }

    $params = @{
        Headers = $headers 
        Body    = $Body
        Method  = 'Post'
        URI     = $endpoint
    }

    write-verbose ($params | convertto-json)

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
    #
    # call graph api
    #
    write-host "getting service fabric service connection"

    $adoAuthHeader = @{
        'authorization'     = "Bearer $global:accessToken"
        'content-type'      = $contentType
        'consistency-level' = 'eventually'
        'accept'            = $contentType
    }
    $parameters = @{
        Uri         = $graphApiUrl + $query
        Method      = $method
        Headers     = $adoAuthHeader
        Erroraction = 'continue'
        Body        = $body
    }

    write-host "graph connection parameters: $($parameters | convertto-json)"
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($parameters.Uri)) -headers $adoAuthHeader"
    $error.clear()
    $global:restQuery = invoke-restMethod @parameters
    write-host "rest result: $($global:restQuery| convertto-json)"

    if ($error) {
        write-error "exception: $($error | out-string)"
        return $null
    }

    return $global:restQuery
}

main