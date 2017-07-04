<#  
.SYNOPSIS  

    powershell script to merge multiple csv files with timestamps by timestamp into new file

.DESCRIPTION  
        
.NOTES  
   File Name  : log-merge.ps1  
   Author     : jagilber
   Version    : 170111 added date ranges

   History    : 
                160619 added "o" date format

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *evt*.csv -outputFile c:\temp\all-events.csv
    Search c:\logfiles folder for all files matching pattern *evt*.csv and output to c:\temp\all-events.csv   

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *FMT*.csv -outputFile c:\temp\all-etw.csv
    Search c:\logfiles folder for all files matching pattern *FMT*.txt and output to c:\temp\all-etw.csv   

.PARAMETER sourceFolder
    Path to source folder to be searched. ex: c:\logfiles

.PARAMETER filePattern
    Dos style file matching pattern for csv files to parse. ex: *evt*.csv

.PARAMETER outputFile
    Name and location of the new merged file. ex: c:\temp\test.csv

.PARAMETER startDate
    optional parameter to exclude lines with dates older than given date

.PARAMETER endDate
    optional parameter to exclude lines with dates newer than given date
#>  

Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the source folder for searching:")]
    [string] $sourceFolder,
    [parameter(Position=1,Mandatory=$true,HelpMessage="Enter the file filter pattern (dos style *.*):")]
    [string] $filePattern,
    [parameter(Position=2,Mandatory=$true,HelpMessage="Enter the new file name:")]
    [string] $outputFile = "log-merge.csv",
    [parameter(Position=3,Mandatory=$false,HelpMessage="Use to enable subdir search")]
    [switch] $subDir,
    [string] $startDate,
    [string] $endDate
    )

$ErrorActionPreference = "SilentlyContinue"
$global:outputList = @{}
$error.Clear()

function main($sourceFolder, $filePattern, $outputFile, $defaultDir, $subDir, $startDate, $endDate)
{
    [int]$precision = 0;

    #07/22/2014-14:48:10.909 for etl and 07/22/2014,14:48:10 PM for eventlog
    [string]$datePattern = "(?<DateEtlPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\.[0-9]{7}) |" +
        "(?<DateEtl>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\.[0-9]{3}) |" +
        "(?<DateEvt>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
        "(?<DateEvtSpace>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
        "(?<DateEvtPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\.[0-9]{6} [AP]M)|" +
        "(?<DateISO>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}T[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\.[0-9]{3,7})";  
    [string]$dateFormatEtl = "MM/dd/yyyy-HH:mm:ss.fff";
    [string]$dateFormatEtlPrecise = "MM/dd/yy-HH:mm:ss.fffffff";
    [string]$dateFormatEvt = "MM/dd/yyyy,hh:mm:ss tt";
    [string]$dateFormatEvtSpace = "MM/dd/yyyy hh:mm:ss tt";
    [string]$dateFormatEvtPrecise = "MM/dd/yyyy,hh:mm:ss.ffffff tt";
    [string]$dateFormatISO = "yyyy-MM-ddTHH:mm:ss.ffffff"; # may have additional digits and Z
        
    [bool]$detail = $false;
    [Globalization.CultureInfo]$culture = new-object Globalization.CultureInfo ("en-US");
    [Int64]$missedMatchCounter = 0;
    [Int64]$missedDateCounter = 0;

    try
    {
        [IO.Directory]::SetCurrentDirectory($defaultDir);

        if (($sourceFolder) -and ($filePattern) -and ($outputFile))
        {
            $option = $null; 

            if($subDir)
            {
                $option = [IO.SearchOption]::AllDirectories;
            }
            else
            {
                $option = [IO.SearchOption]::TopDirectoryOnly;
            }

            [string[]]$files = [IO.Directory]::GetFiles($sourceFolder, $filePattern, $option);
            if ($files.Length -lt 1)
            {
                write-host "unable to find files. returning";
                return;
            }

            ReadFiles -files $files -outputFile $outputFile -startDate $startDate -endDate $endDate;
        }
        else
        {
            write-host "utility combines *fmt.txt files into one file based on timestamp. provide folder and filter args and output file.";
            write-host "LogMerge takes three arguments; source dir, file filter, and output file.";
            write-host "example: LogMerge f:\\cases *fmt.txt c:\\temp\\all.csv";
        }
    }
    catch
    {
        write-host ([string]::Format("exception:main:precision:{0}:missed:{1}:excetion:{2}",$precision, $missedMatchCounter, $error));
        $error.Clear()
    }
}

function ReadFiles([string[]]$files, [string]$outputfile, [DateTime]$startDate, [DateTime]$endDate)
{
    $match = $null;
    [long]$lastTicks = 0;
    [string]$line = "";

    try
    {

        foreach ($file in $files)
        {
            write-host $file;
            [IO.StreamReader]$reader = new-object IO.StreamReader ($file);
            [DateTime]$date = new-object DateTime;
            [string]$fileName = [IO.Path]::GetFileName($file);
            [string]$pidPattern = "^(.*)::";
            [string]$lastPidstring = "";
            [string]$traceDate = "";
            [string]$dateFormat = "";

            while ($reader.Peek() -ge 0)
            {
                $line = $reader.ReadLine();

                if ([regex]::IsMatch($line, $pidPattern))
                {
                    $lastPidstring = [regex]::Match($line, $pidPattern).Value;
                }

                $matchTraceDate = [regex]::Match($line, $datePattern);

                if (($matchTraceDate.Groups["DateEtlPrecise"].Value))
                {
                    $dateFormat = $dateFormatEtlPrecise;
                    $traceDate = $matchTraceDate.Groups["DateEtlPrecise"].Value;
                }
                elseif (($matchTraceDate.Groups["DateEtl"].Value))
                {
                    $dateFormat = $dateFormatEtl;
                    $traceDate = $matchTraceDate.Groups["DateEtl"].Value;
                }
                elseif (($matchTraceDate.Groups["DateEvt"].Value))
                {
                    $dateFormat = $dateFormatEvt;
                    $traceDate = $matchTraceDate.Groups["DateEvt"].Value;
                }
                elseif (($matchTraceDate.Groups["DateEvtSpace"].Value))
                {
                    $dateFormat = $dateFormatEvtSpace;
                    $traceDate = $matchTraceDate.Groups["DateEvtSpace"].Value;
                }
                elseif (($matchTraceDate.Groups["DateEvtPrecise"].Value))
                {
                    $dateFormat = $dateFormatEvtPrecise;
                    $traceDate = $matchTraceDate.Groups["DateEvtPrecise"].Value;
                }
                elseif (($matchTraceDate.Groups["DateISO"].Value))
                {
                    $dateFormat = $dateFormatISO;
                    $traceDate = $matchTraceDate.Groups["DateISO"].Value;
                }
                else
                {
                    if ($detail) 
                    {
                        write-host "unable to parse date:$($missedDateCounter):$($line)";
                    }
                    $missedDateCounter++;
                }

                if ([DateTime]::TryParseExact($traceDate,
                    $dateFormat,
                    $culture,
                    [Globalization.DateTimeStyles]::AssumeLocal,
                    [ref] $date))
                {
                    if ($lastTicks -ne $date.Ticks)
                    {
                        $lastTicks = $date.Ticks;
                        $precision = 0;
                    }
                }
                elseif ([DateTime]::TryParse($traceDate, [ref] $date))
                {
                    if ($lastTicks -ne $date.Ticks)
                    {
                        $lastTicks = $date.Ticks;
                        $precision = 0;
                    }

                    $dateFormat = $dateFormatEvt;
                }
                else
                {
                    # use last date and let it increment to keep in place
                    $date = new-object DateTime ($lastTicks);

                    # put cpu pid and tid back in

                    if ([regex]::IsMatch($line, $pidPattern))
                    {
                        $line = [string]::Format("{0}::{1}", $lastPidString, $line);
                    }
                    else
                    {
                        $line = [string]::Format("{0}{1} -> {2}", $lastPidString, $date.ToString($dateFormat), $line);
                    }

                    $missedMatchCounter++;
                    write-host "unable to parse time:$($missedMatchCounter):$($line)";
                }

                if(!($startDate -lt $date -and $date -lt $endDate))
                {
                    continue;
                }

                while ($precision -lt 99999999)
                {
                    if (AddToList -date $date -line ([string]::Format("{0}, {1}", $fileName, $line)))
                    {
                        break;
                    }

                    $precision++;
                }
            }
        }

        if ([IO.File]::Exists($outputfile))
        {
            [IO.File]::Delete($outputfile);
        }

        [IO.StreamWriter]$writer = new-object IO.StreamWriter ($outputfile, $true)
        
        write-host "sorting lines.";
        foreach ($item in ($global:outputList | Sort-Object -Property Key))
        {
            $writer.WriteLine($item.Value);
        }

        $writer.Close()

        write-host ([string]::Format("finished:missed {0} lines", $missedMatchCounter));
        return $true;
    }
    catch
    {
        write-host ([string]::Format("ReadFiles:exception:lines count:{0}: dictionary count:{1}: exception:{2}", $line.Length, $global:outputList.Count, $error));
        $error.Clear();
        return $false;
    }
}

function AddToList([DateTime]$date, [string]$line)
{
    [string]$key = [string]::Format("{0}{1}",(get-date).Ticks.ToString(), $precision.ToString("D8"));
    if(!$global:outputList.ContainsKey($key))
    {
        $global:outputList.Add($key,$line);
    }
    else
    {
        return $false;
    }

    return $true;
}

[DateTime] $time = new-object DateTime

if(![DateTime]::TryParse($startDate,[ref] $time))
{
   $startDate = [DateTime]::MinValue
}

if(![DateTime]::TryParse($endDate,[ref] $time))
{
   $endDate = [DateTime]::Now
}

main -sourceFolder $sourceFolder -filePattern $filePattern -outputFile $outputFile -defaultDir (get-location) -subDir $subDir -startDate $startDate -endDate $endDate


