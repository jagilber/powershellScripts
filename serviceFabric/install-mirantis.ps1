<#
.SYNOPSIS
    example script to install docker on virtual machine scaleset using custom script extension
    use custom script extension in ARM template
    save file to url that vmss nodes have access to during provisioning
    
.NOTES
    v 1.0
    use: https://docker.microsoft.com/download to get download links

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/Azure/Service-Fabric-Troubleshooting-Guides/master/Scripts/install-mirantis.ps1" -outFile "$pwd\install-mirantis.ps1";

#>
param(
    [string]$mirantisInstallUrl = 'https://get.mirantis.com/install.ps1',
    [version]$version = '0.0.0.0',
    [bool]$registerEvent = $true,
    [string]$registerEventSource = 'CustomScriptExtensionPS',
    [switch]$restart
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

function main() {
    $installLog = "$psscriptroot\install.log"
    $transcriptLog = "$psscriptroot\transcript.log"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (!$isAdmin) {
        Write-Warning "restart script as administrator"
        return
    }
    
    register-event

    Start-Transcript -Path $transcriptLog

    $installFile = "$psscriptroot\$([io.path]::GetFileName($mirantisInstallUrl))"
    write-host "installation file:$installFile"

    if (!(test-path $installFile)) {
        "Downloading [$url]`nSaving at [$installFile]" 
        write-host "$result = Invoke-WebRequest -Uri $mirantisInstallUrl -OutFile $installFile"
        $result = Invoke-WebRequest -Uri $mirantisInstallUrl -OutFile $installFile
        write-host "invoke-webrequest result:$($result | Format-List *)"
    }

    $currentVersions = execute-script -script $installFile -arguments '-showVersions 6>&1'
    write-host "current versions: $currentVersions"
    
    $currentDockerVersions = @($currentVersions[0].ToString().TrimStart('docker:').Replace(" ", "").Split(","))
    write-host "current docker versions: $currentDockerVersions"
    $latestDockerVersion = get-latestVersion -versions $currentDockerVersions
    write-host "latest docker version: $latestDockerVersion"

    if ($version -ieq [version]::new(0, 0, 0, 0).Version) {
        $version = $latestDockerVersion
    }

    $currentContainerDVersions = @($currentVersions[1].ToString().TrimStart('containerd:').Replace(" ", "").Split(","))
    write-host "current containerd versions: $currentContainerDVersions"

    $installedVersion = get-dockerVersion

    if ($installedVersion -ge $version) {
        write-event "docker $installedVersion already installed"
        return
    }

    $result = execute-script -script $installFile -arguments '-verbose 6>&1'

    write-host "install result:$($result | Format-List * | out-string)"
    Write-Host "installed docker version final:$(get-dockerVersion)"
    write-host "install log:`r`n$(Get-Content -raw $installLog)"
    write-host "restarting OS:$restart"

    Stop-Transcript
    write-event (get-content -raw $transcriptLog)

    if ($restart) {
        Restart-Computer -Force
    }

    return $result
}

function register-event() {
    try {
        if ($registerEvent) {
            if (!(get-eventlog -LogName 'Application' -Source $registerEventSource -ErrorAction silentlycontinue)) {
                New-EventLog -LogName 'Application' -Source $registerEventSource
            }
        }
    }
    catch {
        write-host "exception:$($error | out-string)"
        $error.clear()
    }
}

function write-event($data) {
    write-host $data

    try {
        if ($registerEvent) {
            Write-EventLog -LogName 'Application' -Source $registerEventSource -Message $data -EventId 1000
        }
    }
    catch {
        $error.Clear()
    }
}

function execute-script([string]$script, [string] $arguments) {
    write-host "
        Invoke-Expression -Command `"$script $arguments`"
    "
    return Invoke-Expression -Command "$script $arguments"
}

function get-dockerVersion() {
    $dockerExe = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    if ((test-path $dockerExe)) {
        $dockerInfo = (. $dockerExe version)
        $installedVersion = [version][regex]::match($dockerInfo, 'Version:\s+?(\d.+?)\s').groups[1].value
    }
    else {
        $installedVersion = [version]::new(0, 0, 0, 0).Version
    }
    
    write-host "installed docker version:$installedVersion"
    return $installedVersion
}

function get-latestVersion([string[]] $versions) {
    $latestVersion = [version]::new()
    
    if (!$versions) {
        return [version]::new(0, 0, 0, 0).Version
    }
    foreach ($version in $versions) {
        try {
            $currentVersion = [version]::new($version)
            if ($currentVersion -gt $latestVersion) {
                $latestVersion = $currentVersion
            }
        }
        catch {
            continue
        }
    }

    return $latestVersion
}

main
