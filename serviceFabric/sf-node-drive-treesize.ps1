<# script to query drive size for large files
powershell script to collect service fabric node diagnostic data
To download and execute, run the following commands on each sf node in admin powershell:
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-node-drive-treesize.ps1","c:\sf-node-drive-treesize.ps1")
c:\sf-node-drive-treesize.ps1
#>

param(
    $directory = "d:\",
    $depth = 5,
    [switch]$detail,
    $minSizeGB = .1
)

Clear-Host
$error.Clear()
$ErrorActionPreference = "silentlycontinue"
$sizeObjs = @{}
$directories = new-object collections.arraylist
$directories.AddRange(@((Get-ChildItem -Directory -Path $directory -Depth $depth).FullName|Sort-Object))
$directories.Insert(0, $directory.ToLower())
$min = $minSizeGB
$max = 0
$previousDir = $null

foreach ($subdir in $directories)
{
    $sum = (Get-ChildItem $subdir -Recurse | Measure-Object -Property Length -Sum)
    $size = [float]($sum.Sum / 1GB).ToString("F2")
    #[void]$sizeObjs.Add($subdir.ToLower(), "files: $($sum.Count) size: $([float]($size).ToString(`"F2`")))")
    [void]$sizeObjs.Add($subdir.ToLower(), $size)
    $min = [math]::Min($min,$size)
    $max = [math]::Max($max,$size)
}

$categorySize = [int]($max - $min) / 3

foreach ($sortedDir in $directories)
{
    $sortedDir = $sortedDir.ToLower()
    $foreground = "Gray"
    $size = $sizeobjs.item($sortedDir)

    if ($size -gt $minSizeGB)
    {
        switch ($size)
        {
            {$_ -gt $categorySize * 2}
            {
                $foreground = "Red"; 
                break;
            }
            {$_ -gt $categorySize * 1}
            {
                $foreground = "Yellow"; 
                break;
            }
            {$_ -gt $categorySize * 0}
            {
                $foreground = "Green"; 
                break;
            }
            default:
            {
            }
        }
    }
    else
    {
        if (!$detail)
        {
            continue 
        }
    }

    if ($previousDir)
    {
        while (!$sortedDir.Contains($previousDir))
        {
            $previousDir = [io.path]::GetDirectoryName($previousDir)
        }

        $output = $sortedDir.Replace($previousDir, (" " * $previousDir.Length))
        write-host "$($output)`t$($size) GB" -ForegroundColor $foreground
    }
    else
    {
        write-host "$($sortedDir)`t$($size) GB" -ForegroundColor $foreground
    }

    $previousDir = $sortedDir
}

write-host "all sizes in GB are 'uncompressed' and *not* size on disk!!!" -ForegroundColor Yellow
