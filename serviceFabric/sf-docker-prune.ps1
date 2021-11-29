<# 
.SYNOPSIS
    attempt to prune docker images on service fabric node
    see: https://docs.docker.com/config/pruning/
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-docker-prune.ps1" -outFile "$pwd\sf-docker-prune.ps1";
    .\sf-docker-prune.ps1 -whatIf;
#>

#[cmdletbinding()]
param(
    [string]$imageFilter = '',
    [ValidateSet('system', 'image', 'container', 'volume', 'network')]
    [string]$action = 'image',
    [string]$lastUsedHoursCron = '72h',
    [string]$dockerRoot = 'c:\programdata\docker',
    [ValidateSet('continue', 'stop', 'silentlycontinue')]
    [string]$errorAction = 'continue',
    [string]$services = '[
        {
          "name": "FabricHostSvc",
          "restart": true,
          "startuptype": "manual"
        },
        {
          "name": "FabricInstallerSvc",
          "restart": false,
          "startuptype": "manual"
        },
        {
            "name": "ServiceFabricNodeBootstrapAgent",
            "restart": false,
            "startuptype": "automatic"
        },
        {
            "name": "ServiceFabricNodeBootstrapUpgradeAgent",
            "restart": false,
            "startuptype": "automatic"
        }
      ]',
    [string[]]$processes = @('fabricdeployer', 'dockerd'),
    [switch]$whatIf,
    [switch]$force,
    [string]$dockerHost = 'http://localhost:2375/info'
)

$filter = "--filter `"until=$lastUsedHoursCron`""
$forceSwitch = $null
$servicesTable = convertfrom-json $services

function main() {
    clear-host;
    $error.Clear()
    write-output "$(get-date):starting"

    if ($force) {
        $forceSwitch = "--force "
    }
    
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

    write-config

    if ((Get-ChildItem "\\?\$pwd")) { 
        $dockerRoot = "\\?\$dockerRoot"
    }
    
    write-output "getting images: docker images -a -q $imageFilter"
    $images = Invoke-Expression "docker images -a -q $imageFilter"
    $images

    if (!$images) {
        write-output "no images found matching: docker images -a -q $imageFilter"
        if (!$whatIf -and !$force) {
            return
        }
    }

    foreach ($service in $servicesTable) {
        write-output "setting $($service.name) to $($service.startuptype)"
        set-service -name $service.name -StartupType Disabled -WhatIf:$whatIf -ErrorAction $errorAction

        write-output "stopping $($service.name)"
        stop-service -name $service.name -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
    }

    foreach ($process in $processes) {
        write-output "stopping $process"
        stop-process -name $process -WhatIf:$whatIf -ErrorAction $errorAction -Force:$force
    }

    write-output "start-service docker"
    start-service docker -WhatIf:$whatIf
    $result = $null

    while ((get-service -Name docker).Status -ine 'running') {
        write-output "waiting for docker to start"
        Start-Sleep -seconds 1
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

    write-output "stop-service docker"
    stop-service docker -WhatIf:$whatIf -Force:$force
    $result = $null

    while ((get-service -Name docker).Status -ine 'stopped') {
        write-output "waiting for docker to stop"
        Start-Sleep -seconds 1
    }

    foreach ($service in ($servicesTable | sort-object)) {
        write-output "setting $($service.name) to $($service.startuptype)"
        set-service -name $service.name -StartupType $service.startuptype -WhatIf:$whatIf -ErrorAction $errorAction

        if ($service.restart) {
            write-output "starting $($service.name)"
            start-service -name $service.name -WhatIf:$whatIf -ErrorAction $errorAction
        }
    }

    while (!(get-process -Name dockerd)) {
        write-output "waiting for dockerd to start from fabrichost"
        Start-Sleep -seconds 1
    }

    write-output "process list: $(get-process | out-string)"
    write-config
    write-output "$(get-date):finished"
}

function prune-container() {
    write-output "checking container"
    write-output "docker container prune $forceSwitch$filter"

    if (!$whatIf) {
        Invoke-Expression "docker container prune $forceSwitch$filter"
    }
}

function prune-image() {
    write-output "checking images"
    write-output "docker image prune -a $forceSwitch$filter"

    if (!$whatIf) {
        Invoke-Expression "docker image prune -a $forceSwitch$filter"
    }
}

function prune-network() {
    write-output "checking network"
    write-output "docker network prune $forceSwitch$filter"

    if (!$whatIf) {
        Invoke-Expression "docker network prune $forceSwitch$filter"
    }
}
function prune-system() {
    write-output "pruning system"
    write-output "docker system prune -a --volumes $forceSwitch"

    if (!$whatIf) {
        Invoke-Expression "docker system prune -a --volumes $forceSwitch"
    }
}
function prune-volume() {
    write-output "checking volumes"
    write-output "docker volume prune $forceSwitch$filter"

    if (!$whatIf) {        
        Invoke-Expression "docker volume prune $forceSwitch$filter"
    }
}

function write-config() {
    write-output "docker info: "
    docker system info
    write-output "docker version: "
    docker version
    write-output "docker volume ls: "
    docker volume ls
    write-output "docker disk space used: "
    docker system df
    write-output "docker container: "
    docker ps -a
    write-output "docker image: "
    docker images -a
    write-output "docker network: "
    docker network ls

    write-output "dir windowsFilter: "
    (Get-ChildItem "$dockerRoot\windowsFilter" -Directory).FullName
    write-output "dir containers: "
    (Get-ChildItem "$dockerRoot\containers" -Directory).FullName
    write-output "dir image: "
    (Get-ChildItem "$dockerRoot\image" -Directory).FullName
    write-output "process list: "
    get-process | out-string

}

main