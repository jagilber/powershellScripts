<#
test graph rest script 
https://myapps.microsoft.com/ <--- can only be accessed from 'work' account
have to set 'api permissions' on app registration. add 'microsoft graph' 'application permissions'
https://docs.microsoft.com/en-us/graph/auth-v2-user
https://login.microsoftonline.com/common/adminconsent?client_id={client-id}
https://login.microsoftonline.com/common/adminconsent?client_id=
https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow
https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
https://login.microsoftonline.com/common/adminconsent?client_id=6731de76-14a6-49ae-97bc-6eba6914391e&state=12345&redirect_uri=http://localhost/myapp/permissions
#>
#using namespace System.Windows.Forms
#using namespace System.Drawing

param(
    $tenantId = 'common',
    [ValidateSet('v1.0', 'beta')]
    $apiVersion = 'beta', #'v1.0'
    $graphApiUrl = "https://graph.microsoft.com/$apiVersion/$tenantId/",
    $query = 'applications', #'$metadata#applications',
    $clientId,
    $clientSecret,
    [ValidateSet("get", "post", "put")]
    $method = "get",
    [ValidateSet('application/x-www-form-urlencoded', 'application/json', 'application/xml', '*/*')]
    $contentType = 'application/json', # '*/*',
    $body = @{},
    $headers = @{'accept' = $contentType },
    $scope = 'https://graph.microsoft.com/.default', #'Application.Read.All offline_access user.read mail.read',
    $grantType = 'client_credentials', #'authorization_code'
    $redirectUrl = 'http://localhost/',
    $force
)

function main() {
    if (!$clientId -and !$clientSecret) {
        write-error '$clientid and $clientSecret need to be specified'
        return
    }

    if (!$global:accessToken -or $force) {
        get-restToken
    }

    call-graphQuery
}

function get-restAuth() {
    # able to display but only throws errors 
    # requires app registration api permissions with 'devops' added
    # so cannot use internally
    write-host "auth request"
    $global:result = $null
    $error.clear()
    $endpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize"
    $headers = @{
        'content-type' = 'application/x-www-form-urlencoded'
    }

    $Body = @{
        'client_id'     = $clientId
        'response_type' = 'code'
        'state'         = '12345'
        'scope'         = $scope
        'response_mode' = 'query'
        'prompt'        = 'none' #'consent' #'admin_consent'# 'consent' #'select_account' #'none'
        'client_secret' = $clientSecret
        'redirect_uri'  = $redirectUrl #"https://login.microsoftonline.com/common/oauth2/nativeclient" #"urn:ietf:wg:oauth:2.0:oob"#$redirectUrl
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        #   Headers     = $headers 
        Body        = $Body
        Method      = 'get'
        URI         = $endpoint
    }

    write-host ($body | convertto-json)
    write-host ($params | convertto-json)
    write-host $clientSecret
    $error.Clear()

    $global:authresult = Invoke-WebRequest @params -Verbose -Debug
    write-host "auth result: $($global:authresult)"
    write-host "rest auth finished"
    #    $global:authresult.Content | out-file c:\temp\test.html
    #todo unable to get dialog to work correctly. not sure if its due to js or trusted sites or way im testing
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing 

    [xml]$xaml = @"
   <Window 
       xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       xmlns:local="clr-namespace:WpfApp2"
       x:Name="Window" Title="$($MyInvocation.ScriptName)" WindowStartupLocation = "CenterScreen" ResizeMode="CanResize"
       ShowInTaskbar = "True" Background = "lightgray" Width="1200" Height="800"> 
        <WebBrowser Name='WebBrowser1'/>
   </Window>
"@

    #Source="file://c:/temp/test.html"
    $Reader = (New-Object System.Xml.XmlNodeReader $xaml) 
    $Form = [Windows.Markup.XamlReader]::Load($reader) 

    #AutoFind all controls
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]")  | ForEach-Object { 
        New-Variable -Name $_.Name -Value $Form.FindName($_.Name) -Force 
    }
    $content = $global:authresult.Content
    $WebBrowser1.navigatetostring($content)

    [void]$Form.ShowDialog() 
    # # Load the WinForms assembly.
    # Add-Type -AssemblyName System.Windows.Forms

    # # Create a form.
    # $form = [Form] @{
    #     ClientSize = [Point]::new(1000, 1000)
    #     Text       = "WebBrowser-Control Demo"
    # }

    # # Create a web-browser control, make it as large as the inside of the form,
    # # and assign the HTML text.
    # $global:webBrowser = [WebBrowser] @{
    #     ClientSize   = $form.ClientSize
    #     DocumentText = $global:authresult.Content
    # }

    # # Add the web-browser control to the form...
    # $form.Controls.Add($global:webBrowser)

    # # ... and display the form as a dialog (synchronously).
    # $form.ShowDialog()

    # # Clean up.
    # $form.Dispose()
    return ($global:authresult -ne $null)
}

function get-restToken() {
    # requires app registration api permissions with 'devops' added
    # so cannot use internally

    write-host "rest logon"
    $global:result = $null
    $error.clear()
    $endpoint = "https://login.windows.net/$tenantId/oauth2/v2.0/token"
    $headers = @{
        'host'         = 'login.microsoftonline.com'
        'content-type' = 'application/x-www-form-urlencoded'
        'accept'       = '*/*'
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
    $global:result = invoke-restMethod @parameters
    write-host "rest result: $($global:result | convertto-json)"

    if ($error) {
        write-error "exception: $($error | out-string)"
        return $null
    }

    return $global:result
}

main