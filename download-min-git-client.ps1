<#
https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-min-git-client.ps1
downloads git client for use but no install
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
    [switch]$clean
)

$erroractionpreference = "silentlycontinue"
$clientFile = "$($destPath)\gitminclient.zip"
$error.clear()
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
$path = [System.Environment]::GetEnvironmentVariable("Path")

if($clean)
{
    if($path.tolower().contains($destPath))
    {
        [System.Environment]::SetEnvironmentVariable("Path", $($path.replace(";$($newPath)","")), "Machine")
    }
    
    write-host "cleaned..."
    return
}

$apiResults = convertfrom-json (Invoke-WebRequest $gitReleaseApi)
$downloadUrl = @($apiResults.assets -imatch $gitClientType)[0].browser_download_url

if(!$downloadUrl)
{
    $apiResults
    write-warning "unable to find download url"
    return
}

$downloadUrl
(new-object net.webclient).DownloadFile($downloadUrl,$clientFile)
Expand-Archive $clientFile $destPath
$env:Path = $env:Path + ";$($newPath)"

if($setPath -and !$path.tolower().contains($newPath))
{
    # permanent
    [System.Environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$($newPath)", "Machine")
}

write-host "finished"