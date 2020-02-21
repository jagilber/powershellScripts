# powershell test http listener for troubleshooting
# do a final client connect to free up close
[cmdletbinding()]
param(
    [int]$port = 80,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [switch]$isClient,
    [hashtable]$clientHeaders = @{ },
    [string]$clientBody = 'test message from client',
    [ValidateSet('GET','POST','HEAD')]
    [string]$clientMethod = "GET",
    [string]$absolutePath = '/'
)

$uri = "http://$($hostname):$port$absolutePath"
$http = $null

function main() {
    try {
        if ($isClient) {
            start-client
        }
        else {
            # start client so server can periodically resume without async
<#
            start-job -InitializationScript ([scriptblock]::Create("function start-client{$((get-command start-client -showCommandInfo| select Definition).Definition)}")) `
                -ScriptBlock { param($params); start-client -method GET -clientUri "$($params.uri)/clientcheck" } -ArgumentList @PSBoundParameters
            start-job -InitializationScript ([scriptblock]::Create("function start-server{$((get-command start-server -showCommandInfo| select Definition).Definition)}")) `
                -ScriptBlock { param($params); start-server } -ArgumentList @PSBoundParameters

            while(get-job) {
                foreach($job in get-job) {
                    write-host (Receive-Job -Job $job | convertto-json -Depth 5)
                    if($job.State -ine "running") {
                        Remove-Job -Job $job -Force
                    }
                }
                start-sleep -Seconds 1
            }
            #>
            start-server
        }

        Write-Host "$(get-date) Finished!";
    }
    finally {
        Get-Job | Remove-job -Force
        if ($http) {
            $http.Stop()
            $http.Close()
            $http.Dispose();
        }
    }
}

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [string]$method = $clientMethod, [string]$clientUri = $uri) {
    $iteration = 0

    while ($iteration -lt $count -or $count -eq 0) {
        $requestId = [guid]::NewGuid().ToString()
        write-verbose "request id: $requestId"
        if ($header.Count -lt 1) {
            $header = @{
                'accept'                 = 'application/json'
                #'authorization'          = "Bearer $(Token)"
                'content-type'           = 'text/html' #'application/json'
                'host'                   = $hostName
                'x-ms-app'               = [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
                'x-ms-user'              = $env:USERNAME
                'x-ms-client-request-id' = $requestId
            } 
        }

        $params = @{
            method  = $method
            uri     = $uri
            headers = $header
        }
        
        if ($method -ieq 'POST' -and ![string]::IsNullOrEmpty($body)) {
            $params += @{body = $body }
        }
        write-verbose ($header | convertto-json)
        Write-Verbose ($params | fl * | out-string)
    
        $error.clear()
        $result = Invoke-WebRequest -verbose @params
        write-host $result
        
        if ($error) {
            write-host "$($error | out-string)"
            $error.Clear()
        }
    
        start-sleep -Seconds 1
        $iteration++
    }
}

function start-server() {
    $iteration = 0
    $http = [net.httpListener]::new();
    $http.Prefixes.Add("http://$(hostname):$port/")
    $http.Prefixes.Add("http://*:$port/")
    $http.Start();
    $maxBuffer = 1024

    if ($http.IsListening) {
        write-host "http server listening. max buffer $maxBuffer"
        write-host "navigate to $($http.Prefixes)" -ForegroundColor Yellow
    }

    while ($iteration -lt $count -or $count -eq 0) {
        $context = $http.GetContext()
        [string]$html = $null
        if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/clientcheck') {
            write-host "$(get-date) clientcheck: $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Gray
        }
        elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
            write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
            $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            $html += $context | ConvertTo-Json -depth 99
        }
        elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/min') {
            write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
            $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
        }
        elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq $absolutePath) {
            write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
            $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            $html += $context | ConvertTo-Json -depth 99
        }
        elseif ($context.Request.HttpMethod -eq 'POST' -and $context.Request.RawUrl -eq '/') {
            $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            [byte[]]$inputBuffer = @(0) * $maxBuffer
            $context.Request.InputStream.Read($inputBuffer, 0, $maxBuffer)# $context.Request.InputStream.Length)
            $html += "INPUT STREAM: $(([text.encoding]::ASCII.GetString($inputBuffer)).Trim())`r`n"
            $html += $context | ConvertTo-Json -depth 99
        }

        if ($html) {
            write-host $html
            #respond to the request
            $buffer = [Text.Encoding]::UTF8.GetBytes($html)
            $context.Response.ContentLength64 = $buffer.Length
            $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $context.Response.OutputStream.Close()
        }
        
        $iteration++
    }
}

main