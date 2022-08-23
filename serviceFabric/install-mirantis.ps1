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
    [bool]$registerEvent = $true,
    [string]$registerEventSource = 'CustomScriptExtensionPS',
    [bool]$restart = $true
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;

function main() {
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
    }

    # install.ps1 using write-host to output string data. have to capture with 6>&1
    $currentVersions = execute-script -script $installFile -arguments '-showVersions 6>&1'
    write-host "current versions: $currentVersions"
    
    $matches = [regex]::Matches($s,'docker: (?<docker>.+?)containerd: (?<containerd>.+)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline)

    $currentDockerVersions = @($matches.captures[0].Groups['docker'].Value.TrimStart('docker:').Replace(" ", "").Split(","))
    write-host "current docker versions: $currentDockerVersions"

    $latestDockerVersion = get-latestVersion -versions $currentDockerVersions
    write-host "latest docker version: $latestDockerVersion"

    if ($version -ieq [version]::new(0, 0, 0, 0).Version) {
        $version = $latestDockerVersion
    }

    $currentContainerDVersions = @($matches.captures[0].Groups['containerd'].Value.TrimStart('containerd:').Replace(" ", "").Split(","))
    write-host "current containerd versions: $currentContainerDVersions"

    $installedVersion = get-dockerVersion

    if ($installedVersion -ge $version) {
        write-event "docker $installedVersion already installed"
        $restart = $false
    }
    else {
        $result = execute-script -script $installFile -arguments '-verbose 6>&1'

        write-host "install result:$($result | Format-List * | out-string)"
        Write-Host "installed docker version final:$(get-dockerVersion)"
        write-host "restarting OS:$restart"
    }

    Stop-Transcript
    write-event (get-content -raw $transcriptLog)

    if ($restart) {
        Restart-Computer -Force
    }

    return $result
}

function execute-script([string]$script, [string] $arguments) {
    $exe = 'powershell.exe'

    if ($psedition -ieq 'core') {
        $exe = 'pwsh.exe'
    }

    $result = run-process -processName $exe -arguments "$script $arguments" -wait $true
    return $result
}

function get-dockerVersion() {
    $error.clear()
    $dockerExe = 'C:\Program Files\Docker\docker.exe'
    if ((test-path $dockerExe)) {
        $dockerInfo = (. $dockerExe version)
        $installedVersion = [version][regex]::match($dockerInfo, 'Version:\s+?(\d.+?)\s').groups[1].value
    }
    elseif ((docker) -and !$error) {
        Write-Warning "warning:docker in non default directory"
        $dockerInfo = (docker version)
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

function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    write-host "Running process $processName $arguments"
    $exitVal = 0
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WorkingDirectory = get-location

    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        [void]$process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        write-host "Process output:$stdOut"

        if(![System.String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            write-host "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        write-host "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
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

main
