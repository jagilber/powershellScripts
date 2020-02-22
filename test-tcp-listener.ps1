# powershell test tcp listener for troubleshooting
# $client.Client.Shutdown([net.sockets.socketshutdown]::Both)
# do a final client connect to free up close

param(
    [int]$port = 9999,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [bool]$isClient
)

function main() {
try {
    $listener = [net.sockets.tcpListener]$port;
    $listener.Start();
    $script:server = $listener.AcceptSocket();     

    while ($iteration -lt $count -or $count -eq 0) {
        Write-Host "$(get-date) listening on port $port";
        #$server = $listener.AcceptTcpClient();
        $server = $listener.AcceptSocket();        

        $responseString = "$(get-date) client connected on port $port";
        $responseString += $server | ConvertTo-Json -Depth 99
        $responseString += $listener | ConvertTo-Json -Depth 99
        $responseString += "waiting for client send bytes to be sent..."

        [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($responseString);
        $i = $script:server.Send($sendBytes);
        Write-Host "$i : $responseString"

        [byte[]]$buffer = @(0) * 65536
        $server.receive($buffer)
        $i = $server.Send($buffer);
        Write-Host "$i : $(([text.encoding]::ASCII.GetString($buffer)).Trim())"
        
        $buffer.Clear()

        $server.Close();
        $iteration++
    }
    
    $script:server.Close();
}
finally {
    if ($server) {
        $server.Dispose();
    }
    if ($listener) {
        $listener.Stop();
    }
}
}

main