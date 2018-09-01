<# script to query drive size for large files
powershell script to enumerate folder tree and size
To download and execute, run the following commands on each sf node in admin powershell:
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-node-drive-treesize.ps1","c:\sf-node-drive-treesize.ps1")
c:\sf-node-drive-treesize.ps1
#>

[cmdletbinding()]
param(
    $directory = "$($env:SystemRoot)\system32",
    $depth = 99,
    [float]$minSizeGB = .001,
    [switch]$rollupSize,
    [switch]$notree,
    [switch]$showFiles,
    [string]$logFile,
    [switch]$quiet
)

$timer = get-date
$error.Clear()
$ErrorActionPreference = "silentlycontinue"
$sizeObjs = @{}
$drive = Get-PSDrive -Name $directory[0]
$writeDebug = $DebugPreference -ine "silentlycontinue"
$global:logStream = $null

function main()
{
    log-info "$($directory) drive total: $((($drive.free + $drive.used) / 1GB).ToString(`"F3`")) GB used: $(($drive.used / 1GB).ToString(`"F3`")) GB free: $(($drive.free / 1GB).ToString(`"F3`")) GB"
    log-info "NOTE: by default, this script performs a quick scan which is not as accurate as running script with '-rollupSize' switch, but is much faster." -ForegroundColor Cyan
    log-info "all sizes in GB are 'uncompressed' and *not* size on disk. enumerating $($directory) sub directories, please wait..." -ForegroundColor Yellow

    $directories = new-object collections.arraylist
    $directories.AddRange(@((Get-ChildItem -Directory -Path $directory -Depth $depth -Force -ErrorAction SilentlyContinue).FullName | Sort-Object))
    $directories.Insert(0, $directory.ToLower().trimend("\"))
    $previousDir = $null
    $totalFiles = 0

    foreach ($subdir in $directories)
    {
        log-info -debug -data "enumerating $($subDir)"
        $files = Get-ChildItem $subdir -Force -File -ErrorAction SilentlyContinue | Sort-Object -Descending -Property Length
        $sum = ($files | Measure-Object -Property Length -Sum)
        $size = [float]($sum.Sum / 1GB).ToString("F7")
    
        if ($showFiles -or $writeDebug)
        {
            log-info "$($subdir) file count: $($files.Count) folder file size bytes: $($sum.Sum)" -foregroundColor Cyan
            foreach ($file in $files)
            {
                $filePath = $file.name
                
                if ($notree)
                {
                    $filePath = $file.fullname    
                }

                if ($notree)
                {
                    log-info "$($filePath),$($file.length)"
                }
                else
                {
                    log-info "`t$($file.length.tostring().padleft(16)) $($filePath)"    
                }
                
            }
        }

        #if ($size -gt 0)
        #{
        try
        {
            [void]$sizeObjs.Add($subdir.ToLower(), [float]$size)
            $totalFiles = $totalFiles + $sum.Count
            log-info -debug -data "adding $($subDir) $($size)"
        }
        catch
        {
            Write-Warning "error adding $($subdir)"                
        }
        #}
    }

    log-info "directory: $($directory) total files: $($totalFiles) total directories: $($sizeObjs.Count)"

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
  
        log-info -debug -data "checking dir $($sortedDir)"
        $sortedDir = $sortedDir.ToLower()
        [float]$size = 0

        if ($rollupSize -or !$previousDir)
        {
            $pattern = "$([regex]::Escape($sortedDir))(\\|$)"
            #$size = (($SizeObjs.GetEnumerator() | Where-Object {$_.Key -imatch "$([regex]::Escape($sortedDir))(\\|$)").value | Measure-Object -Sum).Sum
            foreach ($sizeObj in $sizeObjs.GetEnumerator())
            {
                if ([regex]::IsMatch($sizeObj.Key, $pattern, [text.regularexpressions.regexoptions]::IgnoreCase))
                {
                    $size += [float]$sizeObj.value
                    log-info -debug -data "match: pattern:$($pattern) $($sizeObj.Key),$([float]$sizeObj.Value)"
                }
                else
                {
                    log-info -debug -data "no match: $($sizeObj.Key) and $($pattern)"
                }
            }

            log-info -debug -data "rollup size: $($sortedDir) $([float]$size)"
        }
        else
        {
            $size = [float]$sizeobjs.item($sortedDir)
        }

  
        #if ([float]$size -eq 0) 
        #{
        #    log-info -debug -data "skipping empty dir $($sortedDir)"
        #    continue
        #}

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

        if ($previousDir -and ([float]$size -lt [float]$minSizeGB))
        {
            log-info -debug -data "skipping below size dir $($sortedDir)"
            continue 
        }

        if ($previousDir)
        {
            if (!$notree)
            {
                while (!$sortedDir.Contains("$($previousDir)\"))
                {
                    $previousDir = "$([io.path]::GetDirectoryName($previousDir))"
                    log-info -debug -data "checking previous dir: $($previousDir)"
                }

                $output = $sortedDir.Replace("$($previousDir)\", "$(`" `" * $previousDir.Length)\")
            }
            else
            {
                $output = $sortedDir
            }

            log-info "$($output)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
        }
        else
        {
            # root
            log-info "$($sortedDir)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
        }

        $previousDir = "$($sortedDir)"
    }

    log-info "total time $((get-date) - $timer)"
}

function log-info($data, [switch]$debug, $foregroundColor = "White")
{
    if ($debug -and !$writeDebug)
    {
        return
    }

    if ($debug)
    {
        $foregroundColor = "Yellow"
    }

    if (!$quiet)
    {
        write-host $data -ForegroundColor $foregroundColor
    }

    if ($logFile)
    {
        if ($global:logStream -eq $null)
        {
            $global:logStream = new-object System.IO.StreamWriter ($logFile, $true)
        }

        $global:logStream.WriteLine($data)
    }
}

try
{
    main
}
catch
{
    write-host "main exception: $($error | out-string)"   
    $error.Clear()
}
finally
{
    if ($global:logStream)
    {
        $global:logStream.Close() 
        $global:logStream = $null
    }

}
