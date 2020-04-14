<#
.SYNOPSIS
monitor docker status
.LINK
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-monitor.ps1","$pwd\sf-docker-monitor.ps1");
.\sf-docker-monitor.ps1;
#>

param(
    $sleepSeconds = 60
)

function main() {
    write-host 'docker version:'
    write-host (docker version | out-string)

    write-host 'docker info:'
    write-host (docker info | out-string)
    $currentProcesses = (get-process) -imatch 'docker'

    while ($true) {
        clear-host;
        (get-date).tostring('o');

        $newProcesses = (get-process) -imatch 'docker'
        $diffIds = (Compare-Object -ReferenceObject $currentProcesses -DifferenceObject $newProcesses -Property Id).Id
        $currentDiffProcesses = $currentProcesses | ? Id -imatch ($diffIds -join '|')

        if ($diffIds) {
            write-host 'different docker processes:'
            write-warning ($currentDiffProcesses | select NPM, PM, WS, CPU, ID, StartTime, ProcessName,ExitTime,ExitCode | ft * -AutoSize | out-string)
            $diffProcesses += $currentDiffProcesses
            $currentProcesses = $newProcesses
        }

        if ($diffProcesses) {
            write-host 'previous docker processes:'
            write-host ($diffProcesses | select NPM, PM, WS, CPU, ID, StartTime, ProcessName,ExitTime,ExitCode | ft * -AutoSize | out-string)
        }
        
        write-host 'current docker processes:'
        write-host ($currentProcesses | select NPM, PM, WS, CPU, ID, StartTime, ProcessName | ft * -AutoSize | out-string)

        write-host 'docker port:'
        write-host ((netstat -bna) -imatch '2375' | out-string)
        
        write-host 'docker ps:'
        write-host (docker ps | out-string)

        write-host 'docker images:'
        write-host (docker images | out-string)

        #docker stats;
        write-host 'Get-NetNatStaticMapping:'
        write-host (Get-NetNatStaticMapping | out-string)

        if ($sleepSeconds -gt 0) {
            write-host "sleeping $sleepSeconds seconds"
            start-sleep -seconds $sleepSeconds;
        }
        else {
            write-host "finished"
            return
        }
    }
}

main