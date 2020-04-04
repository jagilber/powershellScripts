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
    [string]$errorAction = 'continue',
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
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    write-output "isadmin:$isAdmin"
    
    if ($error -or !$dockerInfo) {
        write-output "$(get-date):unable to connect to docker"
        $error.Clear()
    }
    else {
        $dockerObj = $dockerInfo | ConvertFrom-Json
        $dockerObj
        $dockerRoot = $dockerObj.DockerRootDir
    }

    write-output "$(get-date):process list: $(get-process | out-string)"
    write-output "$(get-date):docker volume ls: $(docker volume ls)"
    write-output "$(get-date):dir plugin: $(Get-ChildItem "$dockerRoot\plugins")"

    if((Get-ChildItem "\\?\$pwd")) { 
        $dockerRoot = "\\?\$dockerRoot"
    }
    
    write-output "$(get-date):getting files: $dockerRoot $pluginFile"
    $pluginFiles = get-childitem -Path $dockerRoot -Filter $pluginFile -Recurse -ErrorAction $errorAction

    if (!$pluginFiles) {
        write-output "$(get-date):no files found matching $pluginFile"
        prune-volume
        return
    }

    if ($stopServices) {
        foreach ($service in $services) {
            write-output "$(get-date):stopping $service"
            stop-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    if ($stopProcesses) {
        foreach ($process in $processes) {
            write-output "$(get-date):stopping $process"
            stop-process -name $process -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
        }
    }

    foreach ($f in $pluginFiles) {
        $fileName = $f.FullName
        $isLocked = is-fileLocked $fileName
        write-output "$(get-date):$fileName locked:$($isLocked) content:$(get-content $fileName)"

        if (!$isLocked) {
            if ($action -ieq 'remove') {
                write-output "$(get-date):remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force"
                remove-item $fileName -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            elseif ($action -ieq 'rename') {
                write-output "$(get-date):rename-item -path $fileName -NewName `"$fileName.old`" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force"
                rename-item -path $fileName -NewName "$fileName.old" -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
            }
            else {
                write-output "$(get-date):unknown action"
                return
            }
        }
    }

    prune-volume

    if ($stopServices) {
        foreach ($service in ($services | sort-object)) {
            write-output "$(get-date):starting $service"
            start-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction
        }
    }

    write-output "$(get-date):process list: $(get-process | out-string)"
}

function is-fileLocked([string] $file) {
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false) {
        write-output "$(get-date):File does not exist:$($file)"
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
        write-output "$(get-date):File is locked:$($file)"
        return $true
    }
}

function prune-volume() {
    write-output "$(get-date):docker volume ls"
    docker volume ls

    write-output "$(get-date):docker volume prune"
    if(!$whatIf){
        if($force) {
            docker volume prune --force
        }
        else {
            docker volume prune
        }
    }
}

main