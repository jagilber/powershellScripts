<#
    resolves path to directory or file on local system using current and path variables
#>

param(
    $item = (get-location).path
)

function resolve-path($item)
{
    write-host "resolving $item"
    $item = [environment]::ExpandEnvironmentVariables($item)
    $sepChar = [io.path]::DirectorySeparatorChar

    if($result = Get-Item $item -ErrorAction SilentlyContinue)
    {
        return $result
    }

    $paths = [collections.arraylist]@($env:Path.Split(";"))
    [void]$paths.Add([io.path]::GetDirectoryName($MyInvocation.ScriptName))

    foreach ($path in $paths)
    {
        if($result = Get-Item ($path.trimend($sepChar) + $sepChar + $item.trimstart($sepChar)) -ErrorAction SilentlyContinue)
        {
            return $result
        }
    }

    Write-Warning "unable to find $item"
    return $item
}

$result = resolve-path $item
write-host "result: $result"