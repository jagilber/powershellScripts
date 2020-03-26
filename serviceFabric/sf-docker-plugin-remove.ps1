# remove sfazurefiles.json from docker plugin
# (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-plugin-remove.ps1","$pwd\sf-docker-plugin-remove.ps1");
# .\sf-docker-plugin-remove.ps1 -whatIf;

#[cmdletbinding()]
param(
    [string]$fileFilter = 'c:\programdata\docker\sf*.json',
    [ValidateSet('continue', 'stop', 'silentlycontinue')]
    [string]$errorAction = 'silentlycontinue',
    [ValidateSet('remove', 'rename')]
    [string]$action = 'remove',
    [switch]$stopServices,
    [string[]]$services = @('service fabric host service','Azure Service Fabric Node Bootstrap Agent'),
    [switch]$stopProcesses,
    [string[]]$processes = @('dockerd','fabricdeployer'),
    [switch]$whatIf,
    [switch]$force
)

function main() {
    clear-host;
    $pluginFiles = get-childitem $fileFilter -Recurse -ErrorAction $errorAction

    if(!$pluginFiles){
        Write-Host "no files found matching $fileFilter" -ForegroundColor Green
        return
    }

    if($stopServices) {
        foreach($service in $services) {
            write-host "stopping $service" -ForegroundColor Yellow
            stop-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    if($stopProcesses) {
        foreach($process in $processes) {
            write-host "stopping $process" -ForegroundColor Yellow
            stop-process -name $process -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    foreach ($f in $pluginFiles) {
        $fileName = $f.FullName
        $isLocked = is-fileLocked $fileName
        write-host "$fileName locked:$($isLocked) content:$(get-content $fileName)"

        if(!$isLocked) {
            if($action -ieq 'remove'){
                write-host "remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force" -ForegroundColor Yellow
                remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            elseif($action -ieq 'rename'){
                write-host "rename-item -path $fileName -NewName `"$fileName.old`" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force" -ForegroundColor Yellow
                rename-item -path $fileName -NewName "$fileName.old" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            else {
                write-error "unknown action"
                return
            }
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

main