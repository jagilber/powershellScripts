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
    [string]$destPath = (get-location).Path,
    [string]$gitReleaseApi = "https://api.github.com/repos/git-for-windows/git/releases/latest",
    [string]$gitClientType = "mingit.+64",
    [switch]$setPath,
    [switch]$force,
    [switch]$clean,
    [switch]$full
)

[Net.ServicePointManager]::Expect100Continue = $true;
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
$erroractionpreference = "silentlycontinue"
$error.clear()

if($full)
{
    $gitClientType = "Git-.+?-64-bit.exe"
}

(git)|out-null

if($error -and $clean)
{
    write-warning "git already removed"
    return
}

if(!$error -and !$force -and !$clean)
{
    write-warning "git already installed. use -force"
    return
}

$error.clear()
remove-item $clientFile -force -erroraction silentlycontinue
$destPath = $clientFile.Trim([io.path]::GetExtension($clientFile))
remove-item $destPath -force -recurse -erroraction silentlycontinue
$newPath = "$($destPath)\cmd"
$path = [environment]::GetEnvironmentVariable("Path")

if($clean)
{
    if($path.tolower().contains($destPath))
    {
        [environment]::SetEnvironmentVariable("Path", $($path.replace(";$($newPath)","")), "Machine")
    }
    
    write-host "cleaned..."
    return
}

# -usebasicparsing deprecated but needed for nano / legacy
$apiResults = convertfrom-json (Invoke-WebRequest $gitReleaseApi -UseBasicParsing)
$downloadUrl = @($apiResults.assets -imatch $gitClientType)[0].browser_download_url

if(!$downloadUrl)
{
    $apiResults
    write-warning "unable to find download url"
    return
}

$downloadUrl
#$clientFile = "$($destPath)\gitfullclient.zip"
$clientFile = "$($destPath)\$([io.path]::GetFileName($downloadUrl))"
mkdir $destPath
(new-object net.webclient).DownloadFile($downloadUrl,$clientFile)

if($clientFile -imatch ".zip")
{
    Expand-Archive $clientFile $destPath
    $env:Path = $env:Path + ";$($newPath)"

    if($setPath -and !$path.tolower().contains($newPath))
    {
        # permanent
        [environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$($newPath)", "Machine")
    }
}
else
{
    # install
    write-host "$clientFile /SP- /SILENT /SUPPRESSMSGBOXES /LOG=git-install.log /NORESTART /CLOSEAPPLICATIONS"
    . $clientFile /SP- /SILENT /SUPPRESSMSGBOXES /LOG=git-install.log /NORESTART /CLOSEAPPLICATIONS
}

write-host "finished"