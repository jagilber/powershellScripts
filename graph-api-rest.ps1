<#
test graph rest script 
https://docs.microsoft.com/en-us/graph/auth-v2-user
https://login.microsoftonline.com/common/adminconsent?client_id={client-id}
https://login.microsoftonline.com/common/adminconsent?client_id=
#>

param(
    $tenantId = '',
    [ValidateSet('v1.0', 'beta')]
    $apiVersion = 'v1.0', #'beta'
    $graphApiUrl = "https://graph.microsoft.com/$apiVersion/",#$tenantId/",
    $query = '$metadata',# 'applications', #'$metadata#applications',
    $clientId,
    $clientSecret,
    $pat,
    [ValidateSet("get", "post", "put")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded', 'application/json', 'application/xml', '*/*')]
    $contentType = 'application/json', # '*/*',
    $body = @{},
    $headers = @{'accept' = $contentType },
    $scope = "https://graph.microsoft.com/.default",#'Application.Read.All offline_access user.read mail.read', #'.default', #'user_impersonation', 
    $grantType = 'client_credentials', #'authorization_code'
    $redirectUrl = [web.httpUtility]::urlencode('http://localhost/myapp')#('graphApiApp://auth')#('http://localhost/')#('graphApiApp://auth') #('http://localhost/') #('https://localhost/myapp')#
)

function main() {
    if (!(!$pat -or !(!$clientId -or !$clientSecret)) -or !$organization -or !$project) {
        write-error '$pat or $clientid and $clientSecret, $organization, and $project all need to be specified'
        return
    }
    $global:accessToken = $null
    if (!$pat) {
        #if (get-restAuth -and get-restToken) {
        if (get-restToken) {
            call-graphQuery
        }
    }
    else {
        call-graphQuery
    }
}

function get-restAuth() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    $global:accessToken = $null
    write-host "auth request"
    $global:result = $null
    $error.clear()
    #$endpoint = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    $endpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize"
    $headers = @{
        #'host'         = 'login.microsoftonline.com'
        'content-type' = 'application/x-www-form-urlencoded'
    }

    $Body = @{
        'client_id'     = $clientId
        'response_type' = 'code'
        'state'         = '12345'
        'scope'         = $scope
        'response_mode' = 'query'
        #'grant_type'    = $grantType #'client_credentials' #'authorization_code'
        'client_secret' = $clientSecret
        'redirect_uri'  = $redirectUrl #"urn:ietf:wg:oauth:2.0:oob"#$redirectUrl
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        #   Headers     = $headers 
        Body        = $Body
        Method      = 'Post'
        URI         = $endpoint
    }

    write-host ($body | convertto-json)
    write-host ($params | convertto-json)
    write-host $clientSecret
    $error.Clear()

    $result = Invoke-RestMethod @params -Verbose -Debug
    write-host "result: $($result | convertto-json)"
    write-host "rest auth finished"
    #$global:accessToken = $result.access_token
    $result | out-file c:\temp\test.txt
    return ($result -ne $null)
}

function get-restToken() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    $global:accessToken = $null
    write-host "rest logon"
    $global:result = $null
    $error.clear()
    $endpoint = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    $headers = @{
        'host'         = 'login.microsoftonline.com'
        'content-type' = 'application/x-www-form-urlencoded'
    }

    $Body = @{
        'client_id'     = $clientId
        'scope'         = $scope
        'grant_type'    = $grantType #'client_credentials' #'authorization_code'
        'client_secret' = $clientSecret
        'redirect_uri'  = $redirectUrl #"urn:ietf:wg:oauth:2.0:oob"#$redirectUrl
    }

    $params = @{
        #    ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers 
        Body    = $Body
        Method  = 'Post'
        URI     = $endpoint
    }

    write-host ($body | convertto-json)
    write-host ($params | convertto-json)
    write-host $clientSecret
    $error.Clear()

    $result = Invoke-RestMethod @params -Verbose -Debug
    write-host "result: $($result | convertto-json)"
    write-host "rest logon finished"
    $global:accessToken = $result.access_token

    return ($global:accessToken -ne $null)
}

function call-graphQuery () {
    #
    # call graph api
    #
    write-host "getting service fabric service connection"

    if ($pat) {
        $base64pat = [Convert]::ToBase64String([System.Text.ASCIIEncoding]::ASCII.GetBytes([string]::Format("{0}:{1}", "", $pat)));
        $adoAuthHeader = @{
            'authorization' = "Basic $base64pat"
            'content-type'  = $contentType
        }
    }
    else {
        $adoAuthHeader = @{
            'authorization' = "Bearer $global:accessToken"
            'content-type'  = $contentType
        }
    }
    
    $parameters = @{
        Uri         = $graphApiUrl + $query
        Method      = $method
        Headers     = $adoAuthHeader
        Erroraction = 'continue'
        Body        = $body
    }

    write-host "ado connection parameters: $($parameters | convertto-json)"
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($parameters.Uri)) -headers $adoAuthHeader"
    $error.clear()
    $global:result = invoke-RestMethod @parameters
    write-host "rest result: $($global:result | convertto-json)"

    if ($error) {
        write-error "exception: $($error | out-string)"
        return $null
    }

    return $global:result
}

main