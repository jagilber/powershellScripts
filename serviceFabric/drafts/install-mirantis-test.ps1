<#
.SYNOPSIS
    example script to install docker on virtual machine scaleset using custom script extension
    use custom script extension in ARM template
    save script file to url that vmss nodes have access to during provisioning
    
.NOTES
    v 1.0

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/install-mirantis.ps1" -outFile "$pwd\install-mirantis.ps1";
#>

param(
    [string]$mirantisInstallUrl = 'https://get.mirantis.com/install.ps1',
    [version]$version = '0.0.0.0', # latest
    [switch]$norestart,
    [switch]$allowUpgrade,
    [switch]$installContainerD,
    [bool]$registerEvent = $true,
    [string]$registerEventSource = 'CustomScriptExtensionPS'
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

function main() {
    $error.Clear()

    $transcriptLog = "$psscriptroot\transcript.log"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (!$isAdmin) {
        Write-Error "restart script as administrator"
        return
    }
    
    register-event
    Start-Transcript -Path $transcriptLog

    $installFile = "$psscriptroot\$([io.path]::GetFileName($mirantisInstallUrl))"
    write-host "installation file:$installFile"

    if (!(test-path $installFile)) {
        "Downloading [$url]`nSaving at [$installFile]" 
        write-host "$result = [net.webclient]::new().DownloadFile($mirantisInstallUrl, $installFile)"
        $result = [net.webclient]::new().DownloadFile($mirantisInstallUrl, $installFile)
        write-host "downloadFile result:$($result | Format-List *)"

        # temp fix for usebasicparsing error in install.ps1
        add-UseBasicParsing -scriptFile $installFile
    }

    # install.ps1 using write-host to output string data. have to capture with 6>&1
    $currentVersions = execute-script -script $installFile -arguments '-showVersions 6>&1'
    write-host "current versions: $currentVersions"
    
    $currentDockerVersions = @($currentVersions[0].ToString().TrimStart('docker:').Replace(" ", "").Split(","))
    write-host "current docker versions: $currentDockerVersions"
    $latestDockerVersion = get-latestVersion -versions $currentDockerVersions
    write-host "latest docker version: $latestDockerVersion"

    if (!$version -or $version -ieq [version]::new(0, 0, 0, 0)) {
        $version = $latestDockerVersion
    }

    $currentContainerDVersions = @($currentVersions[1].ToString().TrimStart('containerd:').Replace(" ", "").Split(","))
    write-host "current containerd versions: $currentContainerDVersions"

    $installedVersion = get-dockerVersion

    if ($installedVersion -eq $version) {
        write-host "docker $installedVersion already installed and is equal to $version. skipping install."
        $norestart = $true
    }
    elseif ($installedVersion -ge $version) {
        write-host "docker $installedVersion already installed and is newer than $version. skipping install."
        $norestart = $true
    }
    elseif ($installedVersion -ne '0.0.0.0' -and ($installedVersion -lt $version -and !$allowUpgrade)) {
        write-host "docker $installedVersion already installed and is older than $version. allowupgrade:$allowUpgrade. skipping install."
        $norestart = $true
    }
    else {
        write-host "installing docker."
        $engineOnly = $null
        if(!$installContainerD) {
            $engineOnly = "-EngineOnly "
        }
        $result = execute-script -script $installFile -arguments "-DockerVersion $($version.tostring()) $engineOnly-verbose 6>&1"

        write-host "install result:$($result | Format-List * | out-string)"
        write-host "restarting OS:$restart"
    }

    Stop-Transcript
    write-event (get-content -raw $transcriptLog)

    if (!$norestart) {
        Restart-Computer -Force
    }

    return $result
}

function add-UseBasicParsing($scriptFile) {
    $newLine
    $scriptLines = [io.file]::ReadAllLines($scriptFile)
    $newScript = [collections.arraylist]::new()
    write-host "updating $scriptFile to use -UseBasicParsing for Invoke-WebRequest"

    foreach ($line in $scriptLines) {
        $newLine = $line
        if ([regex]::IsMatch($line, 'Invoke-WebRequest', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            write-host "found command $line"
            if (![regex]::IsMatch($line, '-UseBasicParsing', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                $newLine = [regex]::Replace($line, 'Invoke-WebRequest', 'Invoke-WebRequest -UseBasicParsing', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                write-host "updating command $line to $newLine"
            }
        }
        [void]$newScript.Add($newLine)
    }

    $newScriptContent = [string]::Join([Environment]::NewLine, $newScript.ToArray())
    rename-item $scriptFile -NewName "$scriptFile.oem" -force
    write-host "saving new script $scriptFile"
    out-file -InputObject $newScriptContent -FilePath $scriptFile -Force
}

function execute-script([string]$script, [string] $arguments) {
    write-host "Invoke-Expression -Command `"$script $arguments`""
    return Invoke-Expression -Command "$script $arguments"
}

function get-dockerVersion() {
    $dockerExe = 'C:\Program Files\Docker\docker.exe'
    if ((test-path $dockerExe)) {
        write-host "found $dockerExe"
        $dockerInfo = (. $dockerExe version)
        $installedVersion = [version][regex]::match($dockerInfo, 'Version:\s+?(\d.+?)\s').groups[1].value
    }
    elseif ((invoke-expression 'docker')) {
        Write-Warning "warning:docker in non default directory"
        $dockerInfo = (docker version)
        $installedVersion = [version][regex]::match($dockerInfo, 'Version:\s+?(\d.+?)\s').groups[1].value
    }
    else {
        write-host "docker not found"
        $installedVersion = [version]::new(0, 0, 0, 0)
    }
    
    $error.clear()
    write-host "installed docker version:$installedVersion"
    return $installedVersion
}

function get-latestVersion([string[]] $versions) {
    $latestVersion = [version]::new()
    
    if (!$versions) {
        return [version]::new(0, 0, 0, 0)
    }
    foreach ($version in $versions) {
        try {
            $currentVersion = [version]::new($version)
            if ($currentVersion -gt $latestVersion) {
                $latestVersion = $currentVersion
            }
        }
        catch {
            $error.Clear()
            continue
        }
    }

    return $latestVersion
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
    $level = 'Information'

    # if ($error) {
    #     $level = 'Error'
    #     $data = "$data`r`nerrors:`r`n$($error | out-string)"
    # }

    try {
        if ($registerEvent) {
            Write-EventLog -LogName 'Application' -Source $registerEventSource -Message $data -EventId 1000 -EntryType $level
        }
    }
    catch {
        $error.Clear()
    }
}

main
