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

.PARAMETER depth
    number of directory levels to display

.PARAMETER directory
    directory to enumerate

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
    [float]$minSizeGB = .01,
    [int]$depth = 99,
    [switch]$notree,
    [switch]$showFiles,
    [string]$logFile,
    [switch]$quiet
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

    [dotNet]::Start($directory, [bool]$showFiles)
    $script:directories = [dotnet]::_directories
    $script:directorySizes = @(([dotnet]::_directories).totalsizeGB)
    $totalFiles = (($script:directories).filesCount | Measure-Object -Sum).Sum
    $totalFilesSize = $script:directories[0].totalsizeGB
    log-info "directory: $($directory) total files: $($totalFiles) total directories: $($script:directories.Count)"

    $sortedBySize = $script:directorySizes -ge $minSizeGB | Sort-Object
    $categorySize = [int]([math]::Floor($sortedBySize.Count / 6))
    
    if ($categorySize -lt 1)
    {
        log-info "no directories found! exiting" -foregroundColor Yellow
        exit
    }

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

    if ([float]$size -lt [float]$minSizeGB)
    {
        log-info -debug -data "skipping below size dir $($sortedDir)"
        continue 
    }

    if (($sortedDir -split '\\').count -gt $depth + 2)
    {
        log-info -debug -data "skipping max depth dir $($sortedDir)"
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

    if (!$notree)
    {
        while (!$sortedDir.Contains("$($previousDir)\"))
        {
            $previousDir = "$([io.path]::GetDirectoryName($previousDir))"
            log-info -debug -data "checking previous dir: $($previousDir)"
        }

        if($directorySizesIndex -eq 0)
        {
            # set root to files in root dir
            $percentSize = $script:directories[$directorySizesIndex].sizeGB / $totalFilesSize
        }
        else 
        {
            $percentSize = $size / $totalFilesSize
        }

        $percent = "[$(('X' * ($percentSize * 10)).tostring().padright(10))]"
        $output = $percent + $sortedDir.Replace("$($previousDir)\", "$(`" `" * $previousDir.Length)\")
    }
    else
    {
        $output = $sortedDir
    }
    
    log-info "$($output)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground

    if ($showFiles)
    {
        foreach ($file in ($script:directories[$directorySizesIndex].files).getenumerator())
        {
            log-info ("$(' '*($output.length))$([int64]::Parse($file.value).tostring("N0").padleft(15))`t$($file.key)") -foregroundColor cyan
        }
    }

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
        public int filesCount;
        public Dictionary<string, long> files = new Dictionary<string, long>();

        int IComparable<directoryInfo>.CompareTo(directoryInfo other)
        {
            // fix string sort 'git' vs 'git lb' when there are subdirs comparing space to \ and set \ to 29
            string compareDir = new String(directory.ToCharArray().Select(ch => ch <= (char)47 ? (char)29 : ch).ToArray());
            string otherCompareDir = new String(other.directory.ToCharArray().Select(ch => ch <= (char)47 ? (char)29 : ch).ToArray());
            return String.Compare(compareDir,otherCompareDir, true);
        }
    }

    public static List<directoryInfo> _directories;
    public static ParallelOptions _po = new ParallelOptions();
    public static DateTime _timer;
    public static bool _showFiles = false;

    public static void Main(string[] args)
    {
        if(args.Length > 1)
        {
            Start(args[0], args[1].Length > 0);
        }
        else if (args.Length > 0)
        {
            Start(args[0]);
        }
        else
        {
            Start(Directory.GetCurrentDirectory());
        }
    }

    public static void Start(string path, bool showFiles = false)
    {
        _directories = new List<directoryInfo>();
        _timer = DateTime.Now;
        _showFiles = showFiles;

        // add 'root' path
        directoryInfo rootPath = new directoryInfo() { directory = path.TrimEnd('\\') };
        _directories.Add(rootPath);

        ParallelJob(path);
        Console.WriteLine("sorting directories");
        _directories.Sort();
        Console.WriteLine("rolling up dir sizes");
        TotalDirectories(_directories);

        // put trailing slash back in case 'root' path is root
        if(path.EndsWith("\\"))
        {
            rootPath.directory = path;
            rootPath.filesCount = _directories.ElementAt(0).filesCount;
            rootPath.files = _directories.ElementAt(0).files;
            rootPath.sizeGB = _directories.ElementAt(0).sizeGB;
            rootPath.totalSizeGB = _directories.ElementAt(0).totalSizeGB;
            _directories.RemoveAt(0);
            _directories.Insert(0, rootPath);
        }

#if DEBUG
        Console.WriteLine(string.Format("directory,size,totalSize,totalFiles"));
        foreach (directoryInfo d in _directories)
        {
            Console.WriteLine(string.Format("{0},{1},{2},{3}", d.directory, d.sizeGB, d.totalSizeGB, d.filesCount));
            foreach (KeyValuePair<string, long> fileInfo in d.files)
            {
                Console.WriteLine(string.Format("\t\t{0}\t\t{1}", fileInfo.Value, fileInfo.Key));
            }
        }
#endif
        Console.WriteLine(string.Format("Processing complete. minutes: {0:F3} directories: {1}", (DateTime.Now - _timer).TotalMinutes, _directories.Count));
        return;
    }

    private static void ParallelJob(string path)
    {
        _po.MaxDegreeOfParallelism = 8;
        
        Console.WriteLine("getting directories");
        AddDirectories(path, _directories);

        Console.WriteLine("adding files");
        Parallel.ForEach(_directories, _po, (currentDirectory) =>
         {
             Debug.Print("Processing {0} on thread {1}", currentDirectory.directory, Thread.CurrentThread.ManagedThreadId);
             AddFiles(currentDirectory.directory, _directories);
         });

    }

    private static void AddFiles(string path, List<directoryInfo> directories)
    {
        Debug.Print("checking " + path);

        try
        {
            List<FileInfo> filesList = new DirectoryInfo(path).GetFileSystemInfos().Where(x => (x is FileInfo)).Cast<FileInfo>().ToList();
            long sum = filesList.Sum(x => x.Length);

            if (sum > 0)
            {
                directoryInfo directory = directories.First(x => x.directory == path);
                directory.sizeGB = (float)sum / (1024 * 1024 * 1024);
                directory.filesCount = filesList.Count;
                if(_showFiles)
                {
                    foreach(FileInfo file in filesList)
                    {
                        directory.files.Add(file.Name, file.Length);
                    }

                    directory.files = new Dictionary<string, long>(directory.files.OrderByDescending(v => v.Value).ToDictionary(x => x.Key, x => x.Value));
                }
            }
        }
        catch (Exception ex)
        {
            Debug.Print("exception: " + path + ex.ToString());
        }
    }

    private static void AddDirectories(string path, List<directoryInfo> directories)
    {
        Debug.Print("checking " + path);

        try
        {
            List<string> subDirectories = Directory.GetDirectories(path).ToList();

            foreach (string dir in subDirectories)
            {
                directoryInfo directory = new directoryInfo() { directory = dir };
                directories.Add(directory);
                AddDirectories(dir, directories);
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

            string pattern = string.Format(@"{0}(\\|$)", Regex.Escape(directory.directory));

            while (match && index < dInfo.Count)
            {
                string dirToMatch = dirEnumerator[index].directory;
                Debug.Print("checking match directory {0}", dirToMatch);

                if(Regex.IsMatch(dirToMatch,pattern, RegexOptions.IgnoreCase))
                {
                    if (!firstmatch)
                    {
                        Debug.Print("first match directory {0}", dirToMatch);
                        firstmatch = true;
                        firstMatchIndex = index;
                    }
                    else
                    {
                        Debug.Print("additional match directory {0}", dirToMatch);
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
    [dotnet]::_directories.clear()
    $script.directories = $Null

    if ($script:logStream)
    {
        $script:logStream.Close() 
        $script:logStream = $null
    }
}
