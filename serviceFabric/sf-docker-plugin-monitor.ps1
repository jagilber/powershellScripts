<# monitor docker status
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-plugin-monitor.ps1","$pwd\sf-docker-plugin-monitor.ps1");
.\sf-docker-plugin-monitor.ps1 -whatIf;
#>

param(
    $sleepSeconds = 0,
    $fileFilter = 'c:\programdata\docker\sf*.json',
    [switch]$useHandle,
    [ValidateSet('continue','stop','silentlycontinue')]
    $errorAction = 'silentlycontinue'
)

function main() {
    if ($useHandle) {
        get-sysinternalsExe
    }
    
    docker version;
    docker info;
    
    while ($true) {
        clear-host;
        (get-process) -imatch 'fabric|docker|azure';
        (netstat -bna) -imatch '19100';
        (get-date).tostring('o');
        docker ps;
        docker images;
        #docker stats;
        foreach ($f in (get-childitem $fileFilter -Recurse -ErrorAction $errorAction)) {
            if ($useHandle) {
                write-host ".\handle.exe -u $($f.FullName) -nobanner"
                write-host "handle:$(.\handle.exe -u $($f.FullName) -nobanner)"
            }

            write-host "$($f.FullName) locked:$(is-fileLocked $f.FullName) content:$(get-content $f.FullName)"
        }

        if ($sleepSeconds -gt 0) {
            start-sleep -seconds $sleepSeconds;
        }
        else {
            return
        }
    }
}

function is-fileLocked([string] $file) {
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false) {
        write-warning "File does not exist:$($file)"
        return $false
    }
  
    try {
        $fileStream = $fileInfo.Open([IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        if ($fileStream) {
            $fileStream.Close()
        }
 
        write-verbose "File is NOT locked:$($file)"
        return $false
    }
    catch {
        # file is locked by a process.
        write-warning "File is locked:$($file)"
        return $true
    }
}

function get-sysinternalsExe() {
    param(
        $sysinternalsExe = "handle.exe",
        $sysinternalsCustomExe
    )

    [net.ServicePointManager]::Expect100Continue = $true
    [net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

    if (!$sysinternalsCustomExe) { $sysinternalsCustomExe = $sysinternalsExe }

    if (!(test-path $sysinternalsCustomExe)) {
        write-host "(new-object net.webclient).DownloadFile('http://live.sysinternals.com/$sysinternalsCustomExe','$pwd\$sysinternalsCustomExe')"
        (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$sysinternalsCustomExe", "$pwd\$sysinternalsCustomExe")
        . .\$sysinternalsCustomExe -accepteula
    }
}

main