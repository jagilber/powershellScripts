<#
.SYNOPSIS
    resolves path to directory or file on local system using current and path variables
.LINK
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/resolve-envPath.ps1" -outFile "$pwd\resolve-envPath.ps1";
    .\resolve-envPath.ps1 -item nuget

#>

param(
    $item = (get-location).path
)

function resolve-envPath($item)
{
    write-host "resolving $item"
    $item = [environment]::ExpandEnvironmentVariables($item)
    $sepChar = [io.path]::DirectorySeparatorChar

    if($result = Get-Item $item -ErrorAction SilentlyContinue)
    {
        return $result.FullName
    }

    $paths = [collections.arraylist]@($env:Path.Split(";"))
    [void]$paths.Add([io.path]::GetDirectoryName($MyInvocation.ScriptName))

    foreach ($path in $paths)
    {
        if($result = Get-Item ($path.trimend($sepChar) + $sepChar + $item.trimstart($sepChar)) -ErrorAction SilentlyContinue)
        {
            return $result.FullName
        }
    }

    Write-Warning "unable to find $item"
    return $null
}

$result = resolve-envPath $item
write-host "result: $result"