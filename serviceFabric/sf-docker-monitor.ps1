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
        (get-process) -imatch 'docker';

        write-host 'docker port:'
        (netstat -bna) -imatch '2375';
        
        write-host 'docker ps:'
        docker ps;

        write-host 'docker images:'
        docker images;

        #docker stats;
        write-host 'Get-NetNatStaticMapping:'
        Get-NetNatStaticMapping

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