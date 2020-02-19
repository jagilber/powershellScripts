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
    [ValidateSet('GET', 'POST')]
    [string]$clientMethod = "GET",
    [string]$absolutePath = "/"
)

$uri = "http://$($hostname):$port$absolutePath"
$http = $null

function main() {
    try {
        if ($isClient) {
            start-client
        }
        else {
            start-server
        }

        Write-Host "$(get-date) Finished!";
    }
    finally {
        if ($http) {
            $http.Stop()
            $http.Close()
            $http.Dispose();
        }
    }
}

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [string]$method = $clientMethod) {
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
            method = $method
            uri = $uri
            headers = $header
        }
        
        if($method -ine "GET" -and ![string]::IsNullOrEmpty($body)) {
            $params += @{body=$body}
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
    $http.Prefixes.Add("http://$(hostname):$port$absolutePath")
    $http.Prefixes.Add("http://*:$port$absolutePath")
    $http.Start();
    $maxBuffer = 1024

    if ($http.IsListening) {
        write-host "http server listening. max buffer $maxBuffer"
        write-host "navigate to $($http.Prefixes)" -ForegroundColor Yellow
    }

    while ($iteration -lt $count -or $count -eq 0) {
        $context = $http.GetContext()
        if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
            write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta

            [string]$html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            $html += $context | ConvertTo-Json -depth 99
            write-host $html
            #respond to the request
            $buffer = [Text.Encoding]::UTF8.GetBytes($html)
            $context.Response.ContentLength64 = $buffer.Length
            $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $context.Response.OutputStream.Close()
        
        }
        
        if ($context.Request.HttpMethod -eq 'POST' -and $context.Request.RawUrl -eq '/') {
            [string]$html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            [byte[]]$inputBuffer = @(0) * $maxBuffer
            $context.Request.InputStream.Read($inputBuffer, 0, $maxBuffer)# $context.Request.InputStream.Length)
            $html += "INPUT STREAM: $(([text.encoding]::ASCII.GetString($inputBuffer)).Trim())`r`n"
            $html += $context | ConvertTo-Json -depth 99
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