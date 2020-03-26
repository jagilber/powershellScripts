# script to monitor docker named pipe
# (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-namedpipe-connect.ps1","$pwd\sf-docker-namedpipe-connect.ps1");
# .\sf-docker-namedpipe-connect.ps1;

$ErrorActionPreference = 'continue'
while ($true) {
    try {
        Start-Sleep -Seconds 1
        [io.pipes.NamedPipeClientStream] $pipeClient = new-object io.pipes.NamedPipeClientStream(".", "docker_engine", [io.pipes.PipeDirection]::InOut)
        Write-host "Attempting to connect to pipe..."
        $pipeClient.Connect(10000)
        write-host "access control: $($pipeClient.GetAccessControl() | fl * | out-string)"
        write-host "access: $($pipeClient.GetAccessControl().Access | fl * | out-string)"
        write-host "pipeclient: `r`n$($pipeClient | convertto-json -depth 99)"
    }
    catch { 
        Write-Warning 'unable to connect'
    }
    finally {
        if ($pipeClient) {
            $pipeClient.Close()
        }
    }
} 
