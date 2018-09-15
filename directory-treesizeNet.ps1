<#
.SYNOPSIS
    powershell script to to enumerate directory summarizing in tree view directories over a given size

.DESCRIPTION
    To download and execute, run the following command in powershell:
    iwr('https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1') -UseBasicParsing|iex

    To download and execute with arguments:
    (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1",".\directory-treesize.ps1");
    .\directory-treesize.ps1 c:\windows\system32

    To enable script execution, you may need to Set-ExecutionPolicy Bypass -Force
    
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    
.NOTES
    File Name  : directory-treesize.ps1
    Author     : jagilber
    Version    : 180901 original
    History    : 

.EXAMPLE
    .\directory-treesize.ps1
    enumerate current working directory

.PARAMETER directory
    directory to enumerate

.PARAMETER displayProgress
    display progress banner

.PARAMETER depth
    subdirectory levels to query

.PARAMETER minSizeGB
    minimum size of directory / file to display in GB

.PARAMETER noTree
    output complete directory and file paths

.PARAMETER showFiles
    output file information

.PARAMETER logFile
    log output to log file

.PARAMETER quiet
    do not display output

.LINK
    https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1
#>

[cmdletbinding()]
param(
    $directory = (get-location).path,
    $depth = 99,
    [float]$minSizeGB = .01,
    [switch]$notree,
    [switch]$showFiles,
    [string]$logFile,
    [switch]$quiet,
    [switch]$displayProgress
)

$timer = get-date
$error.Clear()
$ErrorActionPreference = "silentlycontinue"
$drive = Get-PSDrive -Name $directory[0]
$writeDebug = $DebugPreference -ine "silentlycontinue"
$script:logStream = $null
$script:directories = @()
$script:directorySizes = @()
$script:foundtreeIndex = 0
$script:progressTimer = get-date

function main()
{
    log-info "$(get-date) starting"
    log-info "$($directory) drive total: $((($drive.free + $drive.used) / 1GB).ToString(`"F3`")) GB used: $(($drive.used / 1GB).ToString(`"F3`")) GB free: $(($drive.free / 1GB).ToString(`"F3`")) GB"
    log-info "all sizes in GB and are 'uncompressed' and *not* size on disk. enumerating $($directory) sub directories, please wait..." -ForegroundColor Yellow

    [dotNet]::Start($directory)
    $script:directories= [dotnet]::directories
    $script:directorySizes = @(([dotnet]::directories).sizeGB)
    $totalFiles = (($script:directories).files | Measure-Object -Sum).Sum

    log-info "directory: $($directory) total files: $($totalFiles) total directories: $($script:directories.Count)"

    $sortedBySize = $script:directorySizes -ge $minSizeGB | Sort-Object
    $categorySize = [int]([math]::Floor($sortedBySize.Count / 6))
    $redmin = $sortedBySize[($categorySize * 6) - 1]
    $darkredmin = $sortedBySize[($categorySize * 5) - 1]
    $yellowmin = $sortedBySize[($categorySize * 4) - 1]
    $darkyellowmin = $sortedBySize[($categorySize * 3) - 1]
    $greenmin = $sortedBySize[($categorySize * 2) - 1]
    $darkgreenmin = $sortedBySize[($categorySize) - 1]
    $previousDir = $directory.ToLower()
    [int]$i = 0

    for ($directorySizesIndex = 0; $directorySizesIndex -lt $script:directorySizes.Length; $directorySizesIndex++)
    {

         $previousDir = enumerate-directorySizes -directorySizesIndex $directorySizesIndex -previousDir $previousDir
    }

    log-info "$(get-date) finished. total time $((get-date) - $timer)"
}

function enumerate-directorySizes($directorySizesIndex, $previousDir)
{
    $sortedDir = $script:directories[$directorySizesIndex].directory
    log-info -debug -data "checking dir $($script:directories[$directorySizesIndex].directory) previous dir $($previousDir) tree index $($directorySizesIndex)"
    [float]$size = $script:directories[$directorySizesIndex].totalsizeGB
    log-info -debug -data "rollup size: $($sortedDir) $([float]$size)"

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

    if ([float]$size -lt [float]$minSizeGB)
    {
        log-info -debug -data "skipping below size dir $($sortedDir)"
        continue 
    }

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
    return $sortedDir
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
        if ($script:logStream -eq $null)
        {
            $script:logStream = new-object System.IO.StreamWriter ($logFile, $true)
        }

        $script:logStream.WriteLine($data)
    }
}


$code = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public class dotNet
{
    public class directoryInfo : IComparable<directoryInfo>
    {
        public string directory;
        public float sizeGB;
        public float totalSizeGB;
        public int files;

        int IComparable<directoryInfo>.CompareTo(directoryInfo other)
        {
            // fix string sort 'git' vs 'git lb' when there are subdirs comparing space to \
            return String.Compare(directory.Replace((char)32, (char)28), (other.directory.Replace((char)32, (char)28)), true);
        }
    }

    public static List<directoryInfo> directories = new List<directoryInfo>();
    public static ParallelOptions po = new ParallelOptions();
    public static DateTime timer = DateTime.Now;

    public static void Main(string[] args)
    {
        if (args.Length > 0)
        {
            Start(args[0]);
        }
        else
        {
            Start(Directory.GetCurrentDirectory());
        }
    }

    public static void Start(string path)
    {

        ParallelJob(path);
        Console.WriteLine("sorting directories");
        directories.Sort();
        Console.WriteLine("rolling up dir sizes");
        TotalDirectories(directories);

#if DEBUG
        Console.WriteLine(string.Format("directory,size,totalSize,totalFiles"));
        foreach (directoryInfo d in directories)
        {
            Console.WriteLine(string.Format("{0},{1},{2},{3}", d.directory, d.sizeGB, d.totalSizeGB, d.files));
        }
#endif
        Console.WriteLine(string.Format("Processing complete. minutes: {0:F3} directories: {1}", (DateTime.Now - timer).TotalMinutes, directories.Count));
        return;
    }

    private static void ParallelJob(string path)
    {
        po.MaxDegreeOfParallelism = 8;
        directories.Add(new directoryInfo() { directory = path });
        Console.WriteLine("getting directories");
        AddDirectories(path, directories);

        Console.WriteLine("adding files");
        Parallel.ForEach(directories, po, (currentDirectory) =>
         {
             Debug.Print("Processing {0} on thread {1}", currentDirectory.directory, Thread.CurrentThread.ManagedThreadId);
             AddFiles(currentDirectory.directory, directories);
         });

    }

    private static void AddFiles(string path, List<directoryInfo> files)
    {
        Debug.Print("checking " + path);

        try
        {
            List<FileInfo> list = new DirectoryInfo(path).GetFileSystemInfos().Where(x => (x is FileInfo)).Cast<FileInfo>().ToList();
            long sum = list.Sum(x => x.Length);

            if (sum > 0)
            {
                directoryInfo d = files.First(x => x.directory == path);
                d.sizeGB = (float)sum / (1024 * 1024 * 1024);
                d.files = list.Count;
            }
        }
        catch (Exception ex)
        {
            Debug.Print("exception: " + path + ex.ToString());
        }
    }

    private static void AddDirectories(string path, List<directoryInfo> files)
    {
        Debug.Print("checking " + path);

        try
        {
            List<string> directories = Directory.GetDirectories(path).ToList();

            foreach (string dir in directories)
            {
                directoryInfo dInfo = new directoryInfo() { directory = dir };
                files.Add(dInfo);
                AddDirectories(dir, files);
            }
        }
        catch (Exception ex)
        {
            Debug.Print("exception: " + ex.ToString());
        }
    }

    private static void TotalDirectories(List<directoryInfo> dInfo)
    {
        directoryInfo[] dirEnumerator = dInfo.ToArray();
        int index = 0;
        int firstMatchIndex = 0;
        
        foreach (directoryInfo directory in dInfo)
        {
            Debug.Print("checking directory {0}", directory.directory);
            if (directory.totalSizeGB > 0)
            {
                Debug.Print("warning: total size already populated {0}: {1}", directory.directory, directory.totalSizeGB);
                continue;
            }

            bool match = true;
            bool firstmatch = false;

            if (index == dInfo.Count)
            {
                index = 0;
            }

            while (match && index < dInfo.Count)
            {
                string dirToMatch = dirEnumerator[index].directory;
                Debug.Print("checking match directory {0}", dirToMatch);

                if(dirToMatch.Contains(directory.directory))
                {
                    if (!firstmatch)
                    {
                        Debug.Print("first match directory {0}", dirToMatch);
                        firstmatch = true;
                        firstMatchIndex = index;
                    }

                    directory.totalSizeGB += dirEnumerator[index].sizeGB;
                }
                else if (firstmatch)
                {
                    match = false;
                    index = firstMatchIndex;
                    Debug.Print("first no match after match directory {0}", dirToMatch);
                }
                else
                {
                    Debug.Print("no match directory {0}", dirToMatch);
                }

                index++;
            }
        }
    }
}
'@

try
{
    Add-Type $code
    main
}
catch
{
    write-host "main exception: $($error | out-string)"   
    $error.Clear()
}
finally
{
    [dotnet]::directories.clear()

    if ($script:logStream)
    {
        $script:logStream.Close() 
        $script:logStream = $null
    }
}
