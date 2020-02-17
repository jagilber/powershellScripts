# powershell test tcp listener for troubleshooting
# $script:client.Client.Shutdown([net.sockets.socketshutdown]::Both)
# do a final client connect to free up close

param(
    [int]$port = 9999,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [string]$testClientMessage = 'test message from client',
    [switch]$isClient
)

$script:server = $null
$script:client = $null

function main() {
    try {
        write-host "use following client commands to test:" -ForegroundColor Green
        write-host "`$script:client = new-object net.sockets.tcpClient"
        write-host "`$script:client.Connect('$hostName', $port)"
        #write-host "`$sendBytes = [text.encoding]::ASCII.GetBytes('client connection');"
        #write-host "`$script:client.Client.Send(`$sendBytes)"

        if($isClient) {
            start-client
        }
        else {
            start-server
        }

        Write-Host "$(get-date) Finished!";
    }
    finally {
        if($script:client) {
            $script:client.Close()
            $script:client.Dispose();
        }
        if ($script:server) {
            $script:server.Close()
            $script:server.Dispose();
        }
        if ($listener) {
            $listener.Stop();
        }
    }
}

function start-client() {
    $iteration = 0
    $script:client = new-object net.sockets.tcpClient
    $sendBytes = [text.encoding]::ASCII.GetBytes($testClientMessage);
    [byte[]]$buffer = @(0) * $script:client.ReceiveBufferSize
    $script:client.Connect($hostName, $port);

    while ($iteration -lt $count -or $count -eq 0) {
        
        $script:client.Client.Send($sendBytes)

        $script:client.Client.receive($buffer)
        Write-Host "$i : $(([text.encoding]::ASCII.GetString($buffer)).Trim())"
        $buffer.Clear()
        #$script:client.Close()
        start-sleep -Seconds 1
        $iteration++
    }

    $script:client.Close()
}

function start-server() {
    $iteration = 0
    $listener = [net.sockets.tcpListener]$port;
    $listener.Start();
    $script:server = $listener.AcceptSocket();     

    while ($iteration -lt $count -or $count -eq 0) {
        Write-Host "$(get-date) listening on port $port";
        #$script:server = $listener.AcceptTcpClient();
        $responseString = "$(get-date) client connected on port $port";
        $script:server | ConvertTo-Json -Depth 99
        $listener | ConvertTo-Json -Depth 99
        $responseString += "`r`nwaiting for client send bytes to be sent...`r`n"

        [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($responseString);
        $i = $script:server.Send($sendBytes);
        Write-Host "$i : $responseString"

        [byte[]]$buffer = @(0) * $script:server.ReceiveBufferSize
        $script:server.receive($buffer)
        $i = $script:server.Send($buffer);
        Write-Host "$i : $(([text.encoding]::ASCII.GetString($buffer)).Trim())"
        ([text.encoding]::ASCII.GetString($buffer)).Trim()
        $buffer.Clear()
        $iteration++
    }
    
    $script:server.Close();
}

main