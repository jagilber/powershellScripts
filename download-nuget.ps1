<#
downloads nuget.exe if not found from default:
https://dist.nuget.org/win-x86-commandline/latest/nuget.exe

to run with no arguments:
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-nuget.ps1" -UseBasicParsing|iex

or use the following to save and pass arguments:
(new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-nuget.ps1","$pwd/download-nuget.ps1");
.\download-nuget.ps1

nuget has to be pathed .\nuget.exe 
by default it is added to 'path' for session 
-setPath will add to 'path' permanently
-force to force reinstall
-clean to remove
#>
param(
    [string]$destPath = $pwd,
    [string]$fileDownload = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe",
    [switch]$setPath,
    [switch]$force,
    [switch]$clean,
    [string]$file = "nuget.exe"
)

$erroractionpreference = "continue"
$error.clear()
$clientFile = "$destpath\$file"
$env:path += ";$pwd;$psscriptroot"

if(!($result = test-path nuget))
{
    (new-object net.webclient).downloadFile($fileDownload, $clientFile)
    $result = [bool](nuget)
}

if (!$result -and $clean) {
    write-warning "$file already removed"
    exit
}

if ($result -and !$force -and !$clean) {
    . $clientFile
    write-warning "$file already installed. use -force"
    exit
}

Write-Host "downloading $file from $fileDownload" -ForegroundColor Green
$error.clear()
$destPath = $clientFile.Trim([io.path]::GetExtension($clientFile))
remove-item $destPath -force -recurse -erroraction silentlycontinue
$path = [environment]::GetEnvironmentVariable("Path")

if ($clean) {
    if ($path.tolower().contains($destPath)) {
        [environment]::SetEnvironmentVariable("Path", $($path.replace(";$destPath", "")), "Machine")
    }
    
    write-host "cleaned..."
    exit
}

$fileDownload
mkdir $destPath
(new-object net.webclient).DownloadFile($fileDownload, "$destPath\$clientFile")
$env:Path += ";$destPath"

if ($setPath -and !$path.tolower().contains($destPath)) {
    # permanent
    [environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$destPath", "Machine")
}

. $clientFile
write-host "finished"
