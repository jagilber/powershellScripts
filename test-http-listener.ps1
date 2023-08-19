<#
.SYNOPSIS
 powershell test http listener for troubleshooting
 
.DESCRIPTION
 powershell test http listener for troubleshooting
 do a final client connect to free up close

.EXAMPLE
    .\test-static-client-port-http.ps1
.EXAMPLE
    .\test-static-client-port-http.ps1 -server -asjob
.EXAMPLE
    .\test-static-client-port-http.ps1 -server -asjob -serverPort 8080
.EXAMPLE
    .\test-static-client-port-http.ps1 -server -asjob -serverPort 8080 -clientMethod POST -clientBody "test message from client"
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/test-http-listener.ps1" -outFile "$pwd/test-http-listener.ps1";
    help .\test-http-listener.ps1 -examples
#>
using namespace System.Threading.Tasks;
[cmdletbinding()]
param(
    [int]$port = 80,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [switch]$server,
    [hashtable]$clientHeaders = @{ },
    [string]$clientBody = 'test message from client',
    [ValidateSet('GET', 'POST', 'HEAD')]
    [string]$clientMethod = "GET",
    [string]$absolutePath = '/',
    [switch]$useClientProxy,
    [bool]$asJob = $true,
    [string]$key = [guid]::NewGuid().ToString(),
    [string]$logFile
)

$uri = "http://$($hostname):$port$absolutePath"
$http = $null
$scriptParams = $PSBoundParameters
$httpClient = $null
$httpClientHandler = $null
# older ps doesnt handle this always so add explicitly
Add-Type -AssemblyName System.Net.Http

function main() {
    try {
        if (!$server) {
            start-client
        }
        else {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

            if (!$isAdmin) {
                Write-Error "restart script as administrator for http 'server'"
                return
            }
            # start as job so server can exit gracefully after 2 minutes of cancellation
            write-log "main:server:host: $($host |convertto-json -depth 2) asjob:$asjob"
            write-log "main:server:myinvocation: $($myinvocation |convertto-json -depth 2) asjob:$asjob"
            if ($host.Name -ieq "ServerRemoteHost") {
                #if ($false) {
                # called on foreground thread only
                $asjob = $false
                write-log "main:server:host: $($host.Name) asjob:$asjob" -ForegroundColor Cyan
                start-server -asjob $asjob
            }
            else {
                write-log "main:server:host: $($host.Name) asjob:$asjob" -ForegroundColor Cyan
                start-server -asJob $asjob
            }
        }

        write-log "$(get-date) Finished!";
    }
    finally {
        Get-Job | Remove-job -Force
        if ($httpClientHandler) {
            $httpClientHandler.Dispose()
        }
        if ($http) {
            $http.Stop()
            $http.Close()
            $http.Dispose();
        }
    }
}

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [net.http.httpMethod]$method = [net.http.httpmethod]::new($clientMethod), [string]$clientUri = $uri) {
    $iteration = 0
    $httpClientHandler = [net.http.httpClientHandler]::new()
    $httpClientHandler.AllowAutoRedirect = $true
    $httpClientHandler.AutomaticDecompression = [net.decompressionmethods]::GZip
    $httpClientHandler.UseCookies = $false
    $httpClientHandler.UseDefaultCredentials = $false
    $httpClientHandler.UseProxy = $false
    $clientUri = [uri]::EscapeUriString($clientUri)
    $result = $null

    if ($useClientProxy) {
        $proxyPort = $port++
        start-server -asjob -serverPort $proxyPort
        $httpClientHandler.UseProxy = $true
        $httpClientHandler.Proxy = net.webproxy("http://localhost:$proxyPort/", $false)
    }

    $httpClient = [net.http.httpClient]::new($httpClientHandler)

    while ($iteration -lt $count -or $count -eq 0) {
        try {
            $requestId = [guid]::NewGuid().ToString()
            write-log "request id: $requestId"
            $requestMessage = [net.http.httpRequestMessage]::new($method, $clientUri )
            $responseMessage = $null; #[net.http.httpResponseMessage]::new()

            if ($method -ine [net.http.httpMethod]::Get) {
                $httpContent = [net.http.stringContent]::new([string]::Empty, [text.encoding]::ascii, 'text/html')
                $requestMessage.Content = $httpContent
                $responseMessage = $httpClient.SendAsync($requestMessage)
            }
            else {
                $httpContent = [net.http.stringContent]::new([string]::Empty, [text.encoding]::ascii, 'text/html')
                $responseMessage = $httpClient.GetAsync($requestMessage.RequestUri, 0)
            }

            if ($header.Count -lt 1) {
                $requestMessage.Headers.Accept.TryParseAdd('application/json')
                $requestMessage.Headers.Add('client', $env:COMPUTERNAME)
                #$requestMessage.Headers.Add('host',$hostname)
                $requestMessage.Headers.Add('x-ms-app', [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName))
                $requestMessage.Headers.Add('x-ms-user', $env:USERNAME)
                $requestMessage.Headers.Add('x-ms-client-request-id', $requestId)
            }

            $result = $responseMessage.Result
            $resultContent = $result.Content.ReadAsStringAsync().Result

            write-log "result content: $resultContent" -ForegroundColor Cyan

            write-verbose "result: $($result | convertto-json)"
            #write-log ($httpClient | fl * | convertto-json -Depth 99)
            write-verbose ($responseMessage | convertto-json)
            #$requestMessage.
            Write-Verbose ($httpClient | convertto-json)
            #pause
        
            if ($error) {
                write-log "$($error | out-string)"
                $error.Clear()
            }
        }
        catch {
            Write-Warning "exception reading from server`r`n$($_)"
        }

        start-sleep -Seconds 1
        $iteration++
    }
}

function start-server([bool]$asjob, [int]$serverPort = $port) {
    write-log "enter:start-server:asjob:$asJob port:$serverPort"
    if ($asjob) {
        start-job -ScriptBlock { 
            param($script, $params)
            write-log "enter:start-server backgroundjob:pid:$pid script:$script params:$params"
            . $script @params 
        } -ArgumentList $MyInvocation.ScriptName, $scriptParams

        while (get-job) {
            foreach ($job in get-job) {
                $jobInfo = Receive-Job -Job $job | convertto-json -Depth 5
                if ($jobInfo) { 
                    write-log $job.State
                    write-verbose $jobInfo 
                }
                #if ($job.State -ine "running") {
                if ($job.State -imatch "complete" -or $job.State -imatch "fail") {
                    Remove-Job -Job $job -Force
                }
            }
            start-sleep -Seconds 1
        }

    }

    # need admin access to set urlacl. maybe use tcp instead?
    # write-log "netsh http add urlacl url=http://+:$serverPort/ user=everyone listen=yes"
    # start-process -Verb runas -FilePath 'cmd.exe' -ArgumentList '/c netsh http add urlacl url=http://+:$serverPort/ user=everyone listen=yes'

    write-log "start-server:creating listener"
    $iteration = 0
    $http = [net.httpListener]::new();
    $http.Prefixes.Add("http://$(hostname):$serverPort/")
    $http.Prefixes.Add("http://+:$serverPort/")
    # https://learn.microsoft.com/en-us/windows/win32/http/add-urlacl
    $http.Start();
    $maxBuffer = 10240

    if ($http.IsListening) {
        write-log "http server listening. max buffer $maxBuffer"
        write-log "navigate to $($http.Prefixes)" -ForegroundColor Green
        if ($key) {
            if ([uri]::IsWellFormedUriString($key, [urikind]::Absolute)) {
                write-log "key is uri. downloading key" -ForegroundColor Green
                [net.servicePointManager]::Expect100Continue = $true; [net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
                $key = invoke-restMethod $key
            }
        }

        if ($key) {
            write-log "use key: $key" -ForegroundColor Yellow
        }
    }

    while ($iteration -lt $count -or $count -eq 0) {
        try {
            $context = $http.GetContext()
            if ($key) {
                $clientKey = $context.Request.QueryString.GetValues('key')
                if ($clientKey -ine $key) {
                    write-log "invalid key: $clientKey"
                    $context.Response.Close()
                    continue
                }
                write-log "valid key: $clientKey"
            }
            [hashtable]$requestHeaders = @{ }
            [string]$requestHeadersString = ""

            foreach ($header in $context.Request.Headers.AllKeys) {
                $requestHeaders.Add($header, @($context.Request.Headers.GetValues($header)))
                $requestHeadersString += "$($header):$(($context.Request.Headers.GetValues($header)) -join ';'),"
            }

            [string]$html = $null
            write-log "$(get-date) http server $($context.Request.UserHostAddress) received $($context.Request.HttpMethod) request:`r`n"
            write-verbose "request: $($context.Request | ConvertTo-Json)"

            if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
                write-log "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += "`r`nREQUEST HEADERS:`r`n$($requestHeaders | out-string)`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -ieq '/health') {
                write-log "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = @{"ApplicationHealthState" = "Healthy" } | convertto-json
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -ieq '/min') {
                write-log "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += "`r`nREQUEST HEADERS:`r`n$($requestHeaders | out-string)`r`n"
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl.StartsWith('/ps')) {
                write-log "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                #$html += $context | ConvertTo-Json # -depth 99
                $cmd = $context.Request.QueryString.GetValues('cmd') -join ' '
                write-log "invoke-expression $cmd"
                $result = convertto-json (invoke-expression $cmd); # -depth 99;
                write-log "result: $result"
                $html += $result
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -ieq $absolutePath) {
                write-log "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            elseif ($context.Request.HttpMethod -eq 'POST' -and $context.Request.RawUrl -ieq '/') {
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                [byte[]]$inputBuffer = @(0) * $maxBuffer
                $context.Request.InputStream.Read($inputBuffer, 0, $maxBuffer)# $context.Request.InputStream.Length)
                $html += "INPUT STREAM: $(([text.encoding]::ASCII.GetString($inputBuffer)).Trim())`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            else {
                #$html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                write-log "$($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
            }

            if ($html) {
                write-log $html
                #respond to the request
                $buffer = [Text.Encoding]::ASCII.GetBytes($html)
                $context.Response.ContentLength64 = $buffer.Length
                write-log "sending $($context.Response.ContentLength64) bytes"
                $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            else {
                # head
                $context.Response.Headers.Add("requestHeaders", $requestHeadersString)    
            }
        
            $context.Response.OutputStream.Close()
            $context.Response.Close()
            $iteration++
        }
        catch {
            Write-Warning "error $psitem`r`n$($psitem.ScriptStackTrace)"
        }
        finally {
            if ($context.Response.IsClientConnected) {
                $context.Response.Close()
            }
        }
    }
}

function write-log([string]$message, [consoleColor]$foregroundColor = [consoleColor]::White) {
    write-host "$(get-date) $message" -ForegroundColor $foregroundColor
    if ($logFile) {
        $message | out-file $logFile -append
    }
}

main
