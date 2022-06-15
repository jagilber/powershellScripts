<#
test ado rest script using pat
ado auth not using pat uses rbac and 'api permissions' needes to be modified on app registation to add 'devops' permissions before token will work
#>

param(
    $tenantId = '',
    $apiVersion = 'v1.0', #'beta'
    $graphApiUrl = "https://graph.microsoft.com/v1.0/$tenantId/",
    $query = '',
    $clientId,
    $clientSecret,
    $pat,
    [ValidateSet("get", "post", "put")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded', 'application/json', 'application/xml')]
    $contentType = 'application/json',
    $body = @{
        'type'          = 'servicefabric'
        'api-version'   = $apiVersion
        'endpointNames' = 'serviceFabricConnection'
    },
    $headers = @{'accept' = '*/*' },
    $scope = 'user.read mail.read'
)

function main() {
    if (!(!$pat -or !(!$cliendId -or !$clientSecret)) -or !$organization -or !$project) {
        write-error '$pat or $clientid and $clientSecret, $organization, and $project all need to be specified'
        return
    }
    $global:accessToken = $null
    if (!$pat) {
        if (get-restAuthToken) {
            get-restSfConnection
        }
    }
    else {
        get-restSfConnection
    }
}

function get-restAuthToken() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    $global:accessToken = $null
    write-host "rest logon"
    $global:result = $null
    $error.clear()
    $endpoint = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    #$endpoint = "https://app.vssps.visualstudio.com/oauth2/token"
    $headers = @{
        'host'         = 'login.microsoftonline.com'
        'content-type' = 'application/x-www-form-urlencoded'
    }

    $Body = @{
        'client_id'     = $clientId
        #'scope'         = [web.httpUtility]::urlencode('https://graph.microsoft.com/.default') #$scope
        #'scope' = [web.httpUtility]::urlencode("https://graph.microsoft.com/$clientId/.default") #$scope
        #'scope' = "https://graph.microsoft.com/$clientId/.default" #$scope
        #'scope' = "/.default" #$scope
        'scope' = ".default"
        'grant_type'    = 'client_credentials' #'authorization_code' #'client_credentials'
        'client_secret' = $clientSecret
        'redirect_uri' = [web.httpUtility]::urlencode('http://localhost/')
    }
    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers     = $headers 
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
    write-host "rest logon finished"
    $global:accessToken = $result.access_token

    return ($global:accessToken -ne $null)
}

function get-restSfConnection () {
    #
    # get current ado sf connection
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
    write-host "invoke-restMethod -uri $([system.web.httpUtility]::UrlDecode($url)) -headers $adoAuthHeader"
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