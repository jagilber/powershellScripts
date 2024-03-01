<#
# powershell test udp listener for troubleshooting
# do a final client connect to free up server receive

# usage:
# .\test-udp-listener.ps1 -server
# .\test-udp-listener.ps1 -port 514 -count 10 -server
# .\test-udp-listener.ps1 -port 514 -count 10 -remoteAddress

#>

[cmdletbinding()]
param(
    [int]$port = 514,
    [int]$count = 0,
    [string]$remoteAddress = $env:computername, 
    [string]$localAddress,
    [switch]$server,
    [string]$message = "Hello World"
)

function main() {
    if ($server) {
        startServer
    }
    else {
        startClient
    }
}

function get-localAddress() {
    if (!$localAddress) {
        $ipAddress = [net.ipaddress]::Any
    }
    else {
        $resolution = [net.dns]::Resolve($localAddress)
        write-verbose "resolution: $($resolution | out-string)"
        $addressList = $resolution.AddressList
        write-verbose "addressList: $($addressList | out-string)"
        $ipAddress = $addressList | Where-Object ipaddresstostring -ieq $localAddress
        write-verbose "ipAddress: $($ipAddress | out-string)"

        if (!$ipAddress -or ($ipAddress.gettype() -ne [net.ipaddress])) {
            write-host "local ip address '$localAddress' not resolved. using 'Any'`r`n$($addressList.IPAddressToString | out-string)"
            $ipAddress = [net.ipaddress]::Any
        }
    }
    write-host "binding to ipAddress: $($ipAddress.IPAddressToString)"
    return $ipAddress
}

function startClient() {
    try {    
        $localIpEndPoint = [net.ipEndPoint]::new((get-localAddress), 0)
        while ($iteration -lt $count -or $count -eq 0) {
            $iteration++
            $client = [net.sockets.udpClient]::new($localIpEndPoint)
            $iterationMessage = "count: $iteration sending $message"
            write-host $iterationMessage

            [byte[]]$sendBytes = [text.encoding]::ASCII.GetBytes($iterationMessage);
            [void]$client.Send($sendBytes, $sendBytes.Length, $remoteAddress, $port);
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
        $localIpEndPoint = [net.ipEndPoint]::new((get-localAddress), 0)
        $server = [net.sockets.udpClient]::new($port)
        write-host "server started on port $port"

        while ($iteration -lt $count -or $count -eq 0) {
            $iteration++
            [byte[]]$receiveBytes = $server.receive([ref]$localIpEndPoint)
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