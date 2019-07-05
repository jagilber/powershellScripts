<#
downloads nuget.exe if not found from default:
https://dist.nuget.org/win-x86-commandline/latest/nuget.exe

to run with no arguments:
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-nuget.ps1" -UseBasicParsing|iex

or use the following to save and pass arguments:
(new-object net.webclient).downloadFile("https://raw.nugethubusercontent.com/jagilber/powershellScripts/master/download-nuget.ps1","$pwd/download-nuget.ps1");
.\download-nuget.ps1

nuget has to be pathed .\nuget.exe 
by default it is added to 'path' for session 
-setPath will add to 'path' permanently
-force to force reinstall
-clean to remove
#>
param(
    [string]$destPath = $pwd,
    [string]$nugetDownload = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe",
    [switch]$setPath,
    [switch]$force,
    [switch]$clean
)

[System.Net.ServicePointManager]::Expect100Continue = $true;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
$erroractionpreference = "silentlycontinue"
$exeFile = "nuget.exe"

function main() 
{
    $error.clear()
    $clientFile = "$destPath\$exeFile"
    $result = resolve-envPath -item $exeFile

    if (!$result -and $clean) {
        write-warning "nuget already removed"
        return
    }

    if ($result -and !$force -and !$clean) {
        . $clientFile
        write-warning "nuget already installed. use -force"
        return
    }

    Write-Host "downloading nuget from $nugetDownload" -ForegroundColor Green
    $error.clear()
    remove-item $clientFile -force -erroraction silentlycontinue
    $destPath = $clientFile.Trim([io.path]::GetExtension($clientFile))
    remove-item $destPath -force -recurse -erroraction silentlycontinue
    $newPath = "$($destPath)\cmd"
    $path = [environment]::GetEnvironmentVariable("Path")

    if ($clean) 
    {
        if ($path.tolower().contains($destPath)) {
            [environment]::SetEnvironmentVariable("Path", $($path.replace(";$($newPath)", "")), "Machine")
        }
    
        write-host "cleaned..."
        return
    }

    $nugetDownload
    (new-object net.webclient).DownloadFile($nugetDownload, $clientFile)
    Expand-Archive $clientFile $destPath
    $env:Path = $env:Path + ";$($newPath)"

    if ($setPath -and !$path.tolower().contains($newPath)) 
    {
        # permanent
        [environment]::SetEnvironmentVariable("Path", $path.trimend(";") + ";$($newPath)", "Machine")
    }

    . $clientFile
    write-host "finished"
}

function resolve-envPath($item) 
{
    write-host "resolving $item"
    $item = [environment]::ExpandEnvironmentVariables($item)
    $sepChar = [io.path]::DirectorySeparatorChar

    if ($result = Get-Item $item -ErrorAction SilentlyContinue) 
    {
        return $result.FullName
    }

    $paths = [collections.arraylist]@($env:Path.Split(";"))
    [void]$paths.Add([io.path]::GetDirectoryName($MyInvocation.ScriptName))

    foreach ($path in $paths) 
    {
        if ($result = Get-Item ($path.trimend($sepChar) + $sepChar + $item.trimstart($sepChar)) -ErrorAction SilentlyContinue) 
        {
            return $result.FullName
        }
    }

    Write-host "unable to find $item"
    return $null
}

main