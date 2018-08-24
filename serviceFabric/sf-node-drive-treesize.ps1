<# script to query drive size for large files
powershell script to enumerate folder tree and size
To download and execute, run the following commands on each sf node in admin powershell:
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-node-drive-treesize.ps1","c:\sf-node-drive-treesize.ps1")
c:\sf-node-drive-treesize.ps1
#>

param(
    $directory = "$($env:SystemRoot)\system32",
    $depth = 99,
    [switch]$detail,
    [float]$minSizeGB = .01,
    [switch]$rollupSize,
    [switch]$notree,
    [switch]$showFiles
)

$timer = get-date
$error.Clear()
$ErrorActionPreference = "silentlycontinue"
$sizeObjs = @{}
$drive = Get-PSDrive -Name $directory[0]

write-host "$($directory) drive total: $((($drive.free + $drive.used) / 1GB).ToString(`"F3`")) GB used: $(($drive.used / 1GB).ToString(`"F3`")) GB free: $(($drive.free / 1GB).ToString(`"F3`")) GB"
write-host "NOTE: by default, this script performs a quick scan which is not as accurate as running script with '-rollupSize' switch, but is much faster." -ForegroundColor Cyan
write-host "all sizes in GB are 'uncompressed' and *not* size on disk. enumerating $($directory) sub directories, please wait..." -ForegroundColor Yellow

$directories = new-object collections.arraylist
$directories.AddRange(@((Get-ChildItem -Directory -Path $directory -Depth $depth).FullName | Sort-Object))
$directories.Insert(0, $directory.ToLower())
$previousDir = $null
$totalFiles = 0


foreach ($subdir in $directories)
{
    Write-Debug "enumerating $($subDir)"
    $files = Get-ChildItem $subdir
    $sum = ($files | Measure-Object -Property Length -Sum)
    $size = [float]($sum.Sum / 1GB).ToString("F5")
    
    if($showFiles)
    {
        write-host "$($subdir) file count: $($files.Count) folder file size bytes: $($sum.Sum)"
        foreach($file in $files)
        {
            write-host "`t$($file)"
        }
    }

    if($size -gt 0)
    {
        [void]$sizeObjs.Add($subdir.ToLower(), $size)
        $totalFiles = $totalFiles + $sum.Count
    }
}

write-host "directory: $($directory) total files: $($totalFiles) total directories: $($sizeObjs.Count)"

$sortedBySize = ($sizeObjs.GetEnumerator() | Where-Object Value -ge $minSizeGB | Sort-Object -Property Value).Value
$categorySize = [int]([math]::Floor($sortedBySize.Count / 6))
$redmin = $sortedBySize[($categorySize * 6) - 1]
$darkredmin = $sortedBySize[($categorySize * 5) - 1]
$yellowmin = $sortedBySize[($categorySize * 4) - 1]
$darkyellowmin = $sortedBySize[($categorySize * 3) - 1]
$greenmin = $sortedBySize[($categorySize * 2) - 1]
$darkgreenmin = $sortedBySize[($categorySize) - 1]

foreach ($sortedDir in $directories)
{
  
    Write-Debug "checking $($sortedDir)"
    $sortedDir = $sortedDir.ToLower()
    $size = 0

    if ($rollupSize -or !$previousDir)
    {
        $size = (($SizeObjs.GetEnumerator() | Where-Object {$_.Key -imatch [regex]::Escape($sortedDir)}).value | Measure-Object -Sum).Sum
    }
    else
    {
        $size = [float]$sizeobjs.item($sortedDir)
    }

  
    if ([float]$size -eq 0) 
    {
        continue
    }

    switch ([float]$size)
    {
        {$_ -ge $redmin}
        {
            $foreground = "Red"; 
            break;
        }
        {$_ -gt $darkredmin}
        {
            $foreground = "DarkRed"; 
            break;
        }
        {$_ -gt $yellowmin}
        {
            $foreground = "Yellow"; 
            break;
        }
        {$_ -gt $darkyellowmin}
        {
            $foreground = "DarkYellow"; 
            break;
        }
        {$_ -gt $greenmin}
        {
            $foreground = "Green"; 
            break;
        }
        {$_ -gt $darkgreenmin}
        {
            $foreground = "DarkGreen"; 
        }

        default
        {
            $foreground = "Gray"; 
        }
    }

    if ((!$detail -and $previousDir -and ($size -lt $minSizeGB)))
    {
        continue 
    }

    if ($previousDir)
    {
        if (!$notree)
        {
            while (!$sortedDir.Contains("$($previousDir)\"))
            {
                $previousDir = "$([io.path]::GetDirectoryName($previousDir))"
            }

            $output = $sortedDir.Replace("$($previousDir)\", "$(`" `" * $previousDir.Length)\")
        }
        else
        {
            $output = $sortedDir
        }

        write-host "$($output)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
    }
    else
    {
        # root
        write-host "$($sortedDir)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
    }

    $previousDir = "$($sortedDir)"
}

write-host "total time $((get-date) - $timer)"
