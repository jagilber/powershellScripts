# powershell test tcp listener for troubleshooting
# $client.Client.Shutdown([net.sockets.socketshutdown]::Both)
# do a final client connect to free up close
[cmdletbinding()]
param(
    [int]$port = 80,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [string]$testClientMessage = 'test message from client',
    [switch]$isClient,
    [hashtable]$clientHeaders = @{ },
    [string]$clientBody = "",
    [string]$absolutePath = "/"
)

$server = $null
$client = $null
$uri = "http://$($hostname):$port$absolutePath"
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
        if ($client) {
            $client.Close()
            $client.Dispose();
        }
        if ($server) {
            $server.Close()
            $server.Dispose();
        }
        if ($http) {
            $http.Stop();
        }
    }
}

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [string]$method = "GET") {
    $iteration = 0

    while ($iteration -lt $count -or $count -eq 0) {
        $requestId = [guid]::NewGuid().ToString()
        write-verbose "request id: $requestId"
        if ($header.Count -lt 1) {
            $header = @{
                'accept'                 = 'application/json'
                #'authorization'          = "Bearer $(Token)"
                #'content-type'           = 'application/json'
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
        write-verbose $body
    
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

    $client.Close()
}

function start-server() {
    $iteration = 0
    $http = [System.Net.HttpListener]::new();
    $http.Prefixes.Add($uri)
    $http.Prefixes.Add("http://$($env:computername):$port/")
    #foreach($ip in (Get-NetIPAddress).IPv4Address) {
    #    $http.Prefixes.Add("http://$($ip):$port/")
    #}
    $http.Start();

    if ($http.IsListening) {
        write-host "http server listening"
        write-host "navigate to $($http.Prefixes)" -ForegroundColor Yellow
    }

    while ($iteration -lt $count -or $count -eq 0) {
        $context = $http.GetContext()
        if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
            write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta

            [string]$html = "$(get-date) http server $($env:computername) received request:`r`n"
            $html += $context | ConvertTo-Json -depth 99
            write-host $html
            #respond to the request
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html) # convert htmtl to bytes
            $context.Response.ContentLength64 = $buffer.Length
            $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) #stream to broswer
            $context.Response.OutputStream.Close() # close the response
        
        }
        
        if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/some/form') {

            # We can log the request to the terminal
            write-host "$($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -f 'mag'

            [string]$html = ""

            #resposed to the request
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html) 
            $context.Response.ContentLength64 = $buffer.Length
            $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) 
            $context.Response.OutputStream.Close()
        }
        $iteration++
    }
}

main