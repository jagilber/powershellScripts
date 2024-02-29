# powershell test udp listener for troubleshooting
# do a final client connect to free up server receive

param(
    [int]$port = 9999,
    [int]$count = 0,
    [string]$hostName = 'localhost', # todo:currently needs to be an ip address
    [switch]$server,
    [string]$message = "Hello World"
)

$ErrorActionPreference = "Stop"

function main() {
    if ($server) {
        startServer
    }
    else {
        startClient
    }
}

function startClient() {
    try {    
        while ($iteration -lt $count -or $count -eq 0) {
            $iteration++
            $client = [net.sockets.udpClient]::new($hostName, $port);
            write-host "count: $iteration sending $message"
            [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($message);
            [void]$client.Send($sendBytes, $sendBytes.Length);
            Start-Sleep -Seconds 1
        }
           
    }
    catch [Exception] {
        write-host "exception:$($psitem | out-string)"
        Start-Sleep -Seconds 1
        startClient
    }
    finally {
        if ($client) {
            $client.Close();
        }
    }
}

function startServer() {
    try {
        #$remoteIpEndPoint = [net.ipEndPoint]::new([net.IPAddress]::Any, $port)
        #$localAddress = [net.ipAddress]::new(@(0, 0, 0, 0));
        $remoteIpEndPoint = [net.ipEndPoint]::new([net.ipAddress]::Any, 0)
        #$remoteIpEndPoint = [net.ipEndPoint]::new($localAddress, 0)

        $server = [net.sockets.udpClient]::new($port)
        write-host "server started on port $port"

        while ($iteration -lt $count -or $count -eq 0) {
            $iteration++
            [byte[]]$receiveBytes = $server.receive([ref]$remoteIpEndPoint)
            Write-Verbose "$(get-date) received message on port $port";

            $received = [text.encoding]::ASCII.GetString($receiveBytes)
            write-host "received: $received"
        }
    }
    catch [Exception] {
        write-host "exception. retrying:$($psitem | out-string)"
        Start-Sleep -Seconds 1
        if ($server) {
            #$server.Close();
        }
        startServer
    }
    finally {
        if ($server) {
           # $server.Stop();
           $server.Close();
        }
    }
}

main