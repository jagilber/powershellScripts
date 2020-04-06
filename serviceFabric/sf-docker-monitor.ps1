<#
.SYNOPSIS
monitor docker status
.LINK
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-monitor.ps1","$pwd\sf-docker-monitor.ps1");
.\sf-docker-monitor.ps1;
#>

param(
    $sleepSeconds = 30,
    [ValidateSet('continue','stop','silentlycontinue')]
    $errorAction = 'silentlycontinue'
)

function main() {
    
    docker version;
    docker info;
    
    while ($true) {
        clear-host;
        (get-date).tostring('o');
        write-host 'docker processes:'
        write-host ((get-process) -imatch 'docker'|select NPM,PM,WS,CPU,ID,StartTime|ft * -AutoSize|out-string)

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