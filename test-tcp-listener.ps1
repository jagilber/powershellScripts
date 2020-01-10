# powershell test tcp listener for troubleshooting

param(
    $port = 9999,
    $count = 0,
    $hostName = 'localhost'
)

try {
    $listener = [net.sockets.tcpListener]$port;
    $listener.Start();
    write-host "use following client commands to test:" -ForegroundColor Green
    write-host "`$client = new-object net.sockets.tcpClient"
    write-host "`$client.Connect('$hostName', $port)"
    #write-host "`$sendBytes = [text.encoding]::ASCII.GetBytes('client connection');"
    #write-host "`$client.Client.Send(`$sendBytes)"
    $iteration = 0

    while ($iteration -lt $count -or $count -eq 0) {
        Write-Host "$(get-date) listening on port $port";
        #$server = $listener.AcceptTcpClient();
        $server = $listener.AcceptSocket();        
        $server | ConvertTo-Json -Depth 99
        $listener | ConvertTo-Json -Depth 99

        $responseString = "$(get-date) client connected on port $port";
        [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($responseString);
        $i = $server.Send($sendBytes);
        Write-Host "$i : $responseString"

        $server.Close();
        $iteration++
    }

    Write-Host "$(get-date) Finished!";
}
finally {
    if ($server) {
        $server.Dispose();
    }
    if ($listener) {
        $listener.Stop();
    }
}