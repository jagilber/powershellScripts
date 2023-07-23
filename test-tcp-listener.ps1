# powershell test tcp listener for troubleshooting
# $client.Client.Shutdown([net.sockets.socketshutdown]::Both)
# do a final client connect to free up close

param(
    [int]$port = 9999,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [switch]$server
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
            $client = [net.sockets.tcpClient]::new($hostName, $port);
            $stream = $null
            $writer = $null
            $reader = $null
                        
            $iteration++
            $received = $null
            if ($client.Connected) {
                write-host "client connected"
                $stream = $client.GetStream();
                $writer = [io.streamWriter]::new($stream);
                $reader = [io.streamReader]::new($stream);
                $writer.AutoFlush = $true;
                write-host "sending `"Hello World`""
                $writer.WriteLine("Hello World");    
            }
            else {
                write-host "client not active"
                $client.close()
                continue
            }


            while (!$received) {
                if ($client.Available -gt 0) {
                    write-host "client available"
                    $received = $reader.ReadLine()
                    Write-Host "received: $received"                 
                }
                else {
                    start-sleep -seconds 1
                }
            }
            # else {
            #     Write-Host "Failure"
            #     start-sleep -seconds 1
            #     continue
            # }
        }
        $client.Close();    
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
    
        $localAddress = [net.IPAddress]::new(@(0, 0, 0, 0));
        $server = [net.sockets.tcpListener]::new($localAddress, $port);
        $server.Start();

        while ($iteration -lt $count -or $count -eq 0) {
            $iteration++
            Write-Host "$(get-date) listening on port $port";
            if ($server.Pending()) {
                Write-Host "$(get-date) pending connection on port $port";
            }
            else {
                Write-Host "$(get-date) no pending connection on port $port";
                #   start-sleep -seconds 1
                #   continue
            }

            [byte[]]$buffer = @(0) * 65536

            $client = $server.AcceptTcpClient();
            $stream = $client.GetStream();
            
            $writer = [io.streamWriter]::new($stream);
            $reader = [io.streamReader]::new($stream);
            $writer.AutoFlush = $true;

            $sb = [text.StringBuilder]::new()
            
            $sb.AppendLine("$(get-date) client connected on port $port")
            $sb.AppendLine(($client | ConvertTo-Json)) #-Depth 99
            $sb.AppendLine(($server | ConvertTo-Json)) #-Depth 99
            $sb.AppendLine("waiting for client send bytes to be sent...")


            #$bytes = $reader.Read($buffer, 0, $buffer.Length);
            $requestString = $reader.ReadLine()
            write-host "requestString: $requestString"
            $sb.AppendLine("$(get-date) received $bytes bytes from client")
            #Write-Host "$i : $(([text.encoding]::ASCII.GetString($buffer)).Trim())"
            $buffer.Clear()

            $responseString = $sb.ToString()
            [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($responseString);
            #Write-Host "$i : $responseString"
            write-host $responseString
            #$writer.Write($sendBytes, 0, $sendBytes.Length);
            $writer.WriteLine($responseString);
        }
    
        $client.Close();
    }
    catch [Exception] {
        write-host "exception:$($psitem | out-string)"
        Start-Sleep -Seconds 1
        if ($client) {
            $client.Close();
        }
        if ($server) {
            $server.Stop();
        }
        if ($stream) {
            $stream.Close()
        }
        startServer
    }
    finally {
        if ($client) {
            $client.Close();
        }
        if ($server) {
            $server.Stop();
        }
        if ($stream) {
            $stream.Close()
        }
    }
}

main