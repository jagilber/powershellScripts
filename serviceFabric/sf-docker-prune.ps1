<# 
.SYNOPSIS
    attempt to prune docker images on service fabric node
    see: https://docs.docker.com/config/pruning/
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-prune.ps1" -outFile "$pwd\sf-docker-prune.ps1";
    .\sf-docker-prune.ps1 -whatIf -stopServices -stopProcesses;
#>

#[cmdletbinding()]
param(
    [string]$dockerRoot = 'c:\programdata\docker',
    [ValidateSet('continue', 'stop', 'silentlycontinue')]
    [string]$errorAction = 'continue',
    [ValidateSet('system', 'image', 'container', 'volume', 'network')]
    [string]$action = 'image',
    [string]$lastUsedHoursCron = '72h',
    [switch]$stopServices,
    [string[]]$services = @('service fabric host service', 'Azure Service Fabric Node Bootstrap Agent'),
    [switch]$stopProcesses,
    [string[]]$processes = @('fabricdeployer', 'dockerd'),
    [switch]$whatIf,
    [switch]$force,
    [string]$dockerHost = 'http://localhost:2375/info'
)

$filter = "--filter until=$lastUsedHoursCron"

function main() {
    clear-host;
    $error.Clear()
    write-output "$(get-date):starting"
    $dockerInfo = invoke-webRequest -UseBasicParsing $dockerHost
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    write-output "isadmin:$isAdmin"
    
    if ($error -or !$dockerInfo) {
        write-output "unable to connect to docker"
        $error.Clear()
    }
    else {
        $dockerObj = $dockerInfo | ConvertFrom-Json
        $dockerObj
        $dockerRoot = $dockerObj.DockerRootDir
    }

    write-output "docker info: $(docker system info)"
    write-output "docker version: $(docker version)"
    write-output "docker volume ls: $(docker volume ls)"
    write-output "docker disk space used: $(docker system df)"
    write-output "docker container: $(docker ps -a)"
    write-output "docker image: $(docker images -a)"
    write-output "docker network: $(docker network ls)"
    write-output "dir windowsFilter: $(Get-ChildItem "$dockerRoot\windowsFilter" -Directory)"
    write-output "dir containers: $(Get-ChildItem "$dockerRoot\containers" -Directory)"
    write-output "dir image: $(Get-ChildItem "$dockerRoot\image" -Directory)"
    write-output "process list: $(get-process | out-string)"

    if ((Get-ChildItem "\\?\$pwd")) { 
        $dockerRoot = "\\?\$dockerRoot"
    }
    
    write-output "getting images: docker images $filter"
    $images = docker images $filter
    
    if (!$images) {
        write-output "no images found matching: docker images $filter"
        if(!$whatIf) {
            return
        }
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

    switch ($action) {
        "container" {
            prune-container
        }
        "image" {
            prune-image
        }
        "network" {
            prune-network
        }
        "system" {
            prune-system
        }
        "volume" {
            prune-volume
        }
    }

    if ($stopServices) {
        foreach ($service in ($services | sort-object)) {
            write-output "starting $service"
            start-service -name $service -WhatIf:$whatIf -ErrorAction $errorAction
        }
    }

    write-output "process list: $(get-process | out-string)"
    write-output "$(get-date):finished"
}

function prune-container() {
    write-output "checking containers"

    if (!$whatIf) {
        if ($force) {
            write-output "docker $action prune --force $filter"
            $result = docker $action prune --force $filter
            write-output $result
        }
        else {
            write-output "docker $action prune $filter"
            $result = docker $action prune $filter
            write-output $result
        }
    }

    write-output "docker ps -a"
    $result = docker ps -a
    write-output $result

}

function prune-image() {
    write-output "checking images"

    if (!$whatIf) {
        if ($force) {
            write-output "docker $action prune -a --force $filter"
            $result = docker $action prune -a --force $filter
            write-output $result
        }
        else {
            write-output "docker $action prune -a $filter"
            $result = docker $action prune -a $filter
            write-output $result
        }
    }

    write-output "docker $action -a"
    $result = docker $action -a
    write-output $result
}

function prune-network() {
    write-output "checking network"

    if (!$whatIf) {
        if ($force) {
            write-output "docker $action prune --force $filter"
            $result = docker $action prune --force $filter
            write-output $result
        }
        else {
            write-output "docker $action prune $filter"
            $result = docker $action prune $filter
            write-output $result
        }
    }

    write-output "docker $action ls"
    $result = docker $action ls
    write-output $result
}
function prune-system() {
    write-output "pruning system"

    if (!$whatIf) {
        if ($force) {
            write-output "docker $action prune -a --volumes --force $filter"
            $result = docker $action prune -a --volumes --force $filter
            write-output $result
        }
        else {
            write-output "docker $action prune -a --volumes $filter"
            $result = docker $action prune -a --volumes $filter
            write-output $result
        }
    }

    write-output "docker $action info"
    $result = docker $action info
    write-output $result
}
function prune-volume() {
    write-output "checking volumes"

    if (!$whatIf) {
        if ($force) {
            write-output "docker $action prune --force $filter"
            $result = docker $action prune --force $filter
            write-output $result
        }
        else {
            write-output "docker $action prune $filter"
            $result = docker $action volume $filter
            write-output $result
        }
    }

    write-output "docker $action ls"
    $result = docker $action ls
    write-output $result
}

main