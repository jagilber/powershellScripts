<# 
.SYNOPSIS
remove sfazurefile.json from docker plugin
.LINK
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-plugin-remove.ps1","$pwd\sf-docker-plugin-remove.ps1");
.\sf-docker-plugin-remove.ps1 -whatIf -stopServices -stopProcesses;
#>

#[cmdletbinding()]
param(
    [string]$dockerRoot = 'c:\programdata\docker',
    [string]$pluginFile = 'sfazurefile.json',
    [ValidateSet('continue', 'stop', 'silentlycontinue')]
    [string]$errorAction = 'silentlycontinue',
    [ValidateSet('remove', 'rename')]
    [string]$action = 'remove',
    [switch]$stopServices,
    [string[]]$services = @('service fabric host service', 'Azure Service Fabric Node Bootstrap Agent'),
    [switch]$stopProcesses,
    [string[]]$processes = @('fabricdeployer','dockerd'),
    [switch]$whatIf,
    [switch]$force,
    [string]$dockerHost = 'http://localhost:2375/info'
)

function main() {
    clear-host;
    $error.Clear()
    $dockerInfo = invoke-webRequest -UseBasicParsing $dockerHost
    
    if ($error -or !$dockerInfo) {
        write-output "unable to connect to docker"
        $error.Clear()
    }
    else {
        $dockerObj = $dockerInfo | ConvertFrom-Json
        $dockerObj
        $dockerRoot = $dockerObj.DockerRootDir

    }

    write-output "getting files $dockerRoot $pluginFile"
    write-output "dir plugin: $(Get-ChildItem "$dockerRoot\plugins")"
    $pluginFiles = get-childitem -Path $dockerRoot -Filter $pluginFile -Recurse -ErrorAction $errorAction

    if (!$pluginFiles) {
        write-output "no files found matching $pluginFile"
        return
    }

    if ($stopServices) {
        foreach ($service in $services) {
            write-output "stopping $service"
            stop-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    if ($stopProcesses) {
        foreach ($process in $processes) {
            write-output "stopping $process"
            stop-process -name $process -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    foreach ($f in $pluginFiles) {
        $fileName = $f.FullName
        $isLocked = is-fileLocked $fileName
        write-output "$fileName locked:$($isLocked) content:$(get-content $fileName)"

        if (!$isLocked) {
            if ($action -ieq 'remove') {
                write-output "remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force"
                remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            elseif ($action -ieq 'rename') {
                write-output "rename-item -path $fileName -NewName `"$fileName.old`" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force"
                rename-item -path $fileName -NewName "$fileName.old" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            else {
                write-output "unknown action"
                return
            }
        }
    }

    if ($stopServices) {
        foreach ($service in ($services | sort-object)) {
            write-output "starting $service"
            start-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction
        }
    }
}

function is-fileLocked([string] $file) {
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false) {
        write-output "File does not exist:$($file)"
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
        write-output "File is locked:$($file)"
        return $true
    }
}

main