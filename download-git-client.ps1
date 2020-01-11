<#
downloads git client for use 

to run with no arguments:
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-client.ps1" -UseBasicParsing|iex

or use the following to save and pass arguments:
(new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-client.ps1","$pwd/download-git-client.ps1");
.\download-git-client.ps1

git has to be pathed .\git.exe 
by default it is added to 'path' for session 
-setPath will add to 'path' permanently
-force to force reinstall
-clean to remove
#>
param(
    [string]$destPath = "c:\program files", #$pwd, # $env:appdata
    [switch]$setPath,
    [switch]$gitMinClient,
    [switch]$hub,
    [switch]$clean,
    [switch]$force,
    [string]$gitReleaseApi = "https://api.github.com/repos/git-for-windows/git/releases/latest",
    [string]$hubReleaseApi = "https://api.github.com/repos/github/hub/releases/latest", 
    [string]$gitClientType = "Git-.+?-64-bit.exe",
    [string]$hubClientType = "hub-windows-amd64-.+?.zip",
    [string]$minGitClientType = "mingit.+64"
)

[net.servicePointManager]::Expect100Continue = $true;
[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
$erroractionpreference = "continue"
$error.clear()

function main() {

    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "restart in admin powershell."
        return
    }

    if ($gitMinClient) {
        $gitClientType = $minGitClientType
    }

    if ($hub) {
        Set-Alias git hub
        $gitClientType = $hubClientType
        $gitReleaseApi = $hubReleaseApi
        $destPath += "\Hub"
    }
    else {
        $destPath += "\Git"
    }

    $binPath = $destPath.ToLower() + "\bin"
    (git) | out-null

    if ($error -and $clean) {
        write-warning "git already removed"
        return
    }

    if (!$error -and !$force -and !$clean) {
        write-warning "git already installed. use -force"
        return
    }

    $error.clear()
    $path = [environment]::GetEnvironmentVariable("Path")

    if ($clean) {
        if ($path.tolower().contains($binPath)) {
            [environment]::SetEnvironmentVariable("Path", $($path.replace(";$($binPath)", "")), "Machine")
        }
      
        remove-install
        write-host "cleaned..."
        return
    }

    # -usebasicparsing deprecated but needed for nano / legacy
    $apiResults = convertfrom-json (Invoke-WebRequest $gitReleaseApi -UseBasicParsing)
    $downloadUrl = @($apiResults.assets -imatch $gitClientType)[0].browser_download_url

    if (!$downloadUrl) {
        $apiResults
        write-warning "unable to find download url"
        return
    }

    $downloadUrl
    #$clientFile = "$($destPath)\gitfullclient.zip"
    $clientFile = "$($destPath)\$([io.path]::GetFileName($downloadUrl))"

    if ($force) {
        remove-install
    }

    mkdir $destPath

    if (!(test-path $clientFile) -or $force) {
        if ($force) {
            remove-item $clientFile
        }

        write-host "downloading $downloadUrl to $clientFile"
        (new-object net.webclient).DownloadFile($downloadUrl, $clientFile)
    }

    if ($clientFile -imatch ".zip") {
        Expand-Archive $clientFile $destPath
    }
    else {
        # install
        $argumentList = "/SP- /SILENT /SUPPRESSMSGBOXES /LOG=git-install.log /NORESTART /CLOSEAPPLICATIONS"
        write-host "$clientFile $argumentList"
        start-process -FilePath $clientFile -ArgumentList $argumentList -Wait
    
        if (!(test-path $binPath)) {
            $binPath = $null
        }
    }

    if ($binPath -and !$path.tolower().contains($binPath)) {
        write-host "setting path"
        $env:Path = $env:Path.TrimEnd(";") + ";$($binPath)"

        if ($setPath) {
            write-host "setting path permanent"
            [environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$($binPath)", "Machine")
        }
    }
    else {
        write-host "path contains $binPath"
    }

    write-host $env:path
    write-host "finished"
}

function remove-install()
{
    if ((test-path $destPath)) {
        $uninstallFile = @([io.directory]::GetFiles("$destpath","unins*.exe"))[-1]
        if ($uninstallFile) {
            Write-Warning "running uninstall"
            Start-Process $uninstallFile -Wait
        }

        remove-item $destPath -Force -Recurse
    }
}

main