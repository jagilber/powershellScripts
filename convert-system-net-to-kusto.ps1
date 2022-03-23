
<#
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/convert-system-net-to-kusto.ps1" -outFile "$pwd\convert-system-net-to-kusto.ps1";
    .\convert-system-net-to-kusto.ps1 -inputfile $pwd\network.log -outputfile $pwd\network.combine.log

    https://docs.microsoft.com/en-us/dotnet/framework/network-programming/how-to-configure-network-tracing

System.Net.Http Verbose: 0 : [8732] Entering HttpClientHandler#55878869::.ctor()
    ProcessId=6744
    DateTime=2022-03-21T13:51:40.0956620Z

    # time,type,level,pid,tid,data,ref

    .\kusto-rest.ps1 -cluster -database
    $kusto.ImportCsv("$pwd\network.combine.log",'system_net',"['time']:datetime,['type']:string,['level']:string,['pid']:int,['tid']:int,['data']:string,['ref']:dynamic")
    $kusto.Exec('system_net | evaluate bag_unpack(ref)')
#>
[CmdletBinding()]
param (
    $inputFile = '', #'.\network.log',
    $outputFile = '', #'.\network.combine.log',
    $inputFolder = '',
    $outputFolder = '',
    $excludeLevel = 'Verbose'
)
    
$typePattern = "(?<type>^.+?) (?<level>\w+?): \d+ : \[(?<tid>\d+)\] (?<data>.+)"
$processPattern = "ProcessId=(\d+)"
$datePattern = "DateTime=(.+)"
$referencePattern = "(?<refName>[\w``\.0-9]+)#(?<refId>\d+)"
$regexoptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase
$refNames = [collections.arraylist]::new()
$i = 1

$lineObjTemplate = @{
    dateTime = ''
    pid      = ''
    tid      = ''
    type     = ''
    level    = ''
    ref      = ''
    data     = ''
}

$refObj = @{
    refName = ''
    refId   = ''
}

$lineObj = $lineObjTemplate.Clone()

$code = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

public static class dotNet
{
    public static StreamWriter _streamWriter;
    public static StreamReader _streamReader;

    public static void CloseInputFile()
    {
        _streamWriter?.Close();
    }

    public static void CloseOutputFile()
    {
        _streamWriter?.Close();
    }

    public static void OpenOutputFile(string fileName)
    {
        _streamWriter = new StreamWriter(fileName, true);
    }

    public static void OpenInputFile(string fileName)
    {
        _streamReader = new StreamReader(fileName, true);
    }

    public static void WriteLine(string line)
    {
        _streamWriter.WriteLine(line);
    }

    public static void WriteLines(string[] lines)
    {
        foreach(string line in lines)
        {
            _streamWriter.WriteLine(line);
        }
    }

    public static string ReadLine()
    {
        if(_streamReader.Peek() >=0)
        {
            return _streamReader.ReadLine();
        }

        return null;
    }
    
    public static List<string> ReadLines()
    {
        List<string> lines = new List<string>();
        while(_streamReader.Peek() >= 0)
        {
            lines.Add(_streamReader.ReadLine());
        }
        return lines;
    }

    public static bool IsMatch(string inputString, string pattern)
    {
        return Regex.IsMatch(inputString,pattern,RegexOptions.IgnoreCase);
    }

    public static Match GetMatch(string inputString, string pattern)
    {
        return Regex.Match(inputString,pattern,RegexOptions.IgnoreCase);
    }

    public static MatchCollection GetMatches(string inputString, string pattern)
    {
        return Regex.Matches(inputString,pattern,RegexOptions.IgnoreCase);
    }

}
'@

add-type $code

function main() {
    try {

        if ($outputFile) {
            $outputDir = [io.path]::GetDirectoryName($outputFile)
            if (!(test-path $outputDir)) {
                mkdir $outputDir
            }
        }

        if ($inputFile) {
            if ((test-path $outputFile)) {
                remove-item $outputFile -fo
            }
        }
    
        if ($inputFolder -and !(test-path $inputFolder)) {
            write-error "folder $inputfolder does not exist"
            return
        }

        if ($outputFolder -and !(test-path $outputFolder)) {
            mkdir $outputFolder
        }

        if ($inputFile -and $outputFile) {
            parse-file $inputFile $outputFile
        }
        elseif ($inputFolder -and $outputFolder) {
            $inputfiles = [io.directory]::getfiles($inputFolder)
            foreach ($inputfile in $inputfiles) {
                $outputfile = $outputfolder + "\" + [io.path]::getFileName($inputFile)
                parse-file $inputfile $outputFile
            }
        }
        else {
            write-error "unknown configuration"
            return
        }

        Write-Host "ref names: $($refNames | Sort-Object | convertto-json)"
    }
    catch {
        write-error ($error | out-string)
    }
    finally {
        [dotnet]::CloseInputFile()
        [dotnet]::CloseOutputFile()
    }
}

function parse-file($inputFile, $outputFile) {
    write-host "process file: $inputfile $outputfile"
    [dotnet]::OpenInputFile($inputFile)
    [dotnet]::OpenOutputFile($outputFile)
    $i = 0
    
    foreach ($line in [dotnet]::ReadLines()) {
        #write-host "checking line:$(($i++).ToString())"
        Write-verbose "checking line:$(($i).ToString()) $line"
        if ($line -eq $null) {
            return
        }

        if ($line.length -lt 1) { continue }

        if ((is-match $line $typePattern)) {
            if ($lineobj.data -and $lineobj.dateTime -and $lineObj.pid) { 
                if ($excludeLevel -and [dotnet]::IsMatch($lineObj.level, $excludeLevel)) {
                    write-verbose "level excluded, skipping"
                }
                else {
                    Write-verbose "add: $($lineObj| Format-List *)"
                    $formattedString = "$($lineobj.dateTime),$($lineobj.type),$($lineobj.level),$($lineobj.pid),$($lineobj.tid),`"`"`"$($lineobj.data.replace('"',"'"))`"`"`",$($lineobj.ref)"
                    [dotnet]::WriteLine($formattedString)
                }
                $lineObj = $lineObjTemplate.Clone()
            }
                    
            $results = get-matches $line $typePattern
            $lineobj.type = $results.Groups['type'].value
            $lineobj.tid = $results.Groups['tid'].value
            $lineobj.level = $results.Groups['level'].value
            $lineobj.data = $results.Groups['data'].value

            if ($excludeLevel -and [dotnet]::IsMatch($lineObj.level, $excludeLevel)) {
                write-verbose "level excluded, skipping2"
                continue
            }

            $results = @(get-matches $line $referencePattern)
            $refs = @{}
            #$refs = [collections.arraylist]::new()
            foreach ($result in $results) {
                $ref = $refObj.Clone()
                $ref.refName = $result.Groups['refName'].value
                $ref.refId = $result.Groups['refId'].value
                if ($ref.refName) {
                    if (!$refNames.Contains($ref.refName)) {
                        [void]$refNames.Add($ref.refName)
                    }
                    [void]$refs.Add($ref.refName, $ref.refId)
                    #[void]$refs.Add($ref)
                }
            }
            if ($refs) {
                $lineobj.ref = '"' + ($refs | convertto-json -Compress).replace('"', "`"`"") + '"'
            }
        }
        elseif ((is-match $line $processPattern)) {
            $lineobj.pid = get-match $line $processPattern
        }
        elseif ((is-match $line $datePattern)) {
            $lineobj.dateTime = get-match $line $datePattern
        }
        else {
            Write-verbose "no match $($line.Substring(0,$line.Length))"
            $lineobj.data = $lineobj.data + ', ' + $line
        }
    }
}

function get-match($inputstring, $pattern) {
    return [dotnet]::GetMatch($inputstring, $pattern).groups[1].value
    write-verbose "match search pattern:$pattern input:$inputstring "
    $match = [regex]::Match($inputstring, $pattern , $regexoptions)
    write-verbose "match result:$match"
    return $match.groups[1].value
}

function get-matches($inputstring, $pattern) {
    return [dotnet]::GetMatches($inputstring, $pattern)
    write-verbose "matches search pattern:$pattern input:$inputstring "
    $matches = [regex]::Matches($inputstring, $pattern , $regexoptions)
    write-verbose "matches result:$matches"
    return $matches
}

function is-match($inputstring, $pattern) {
    return [dotnet]::IsMatch($inputstring, $pattern)
    write-verbose "is match pattern:$pattern input:$inputstring "
    $result = [regex]::IsMatch($inputstring, $pattern , $regexoptions)
    write-verbose "is match result:$result "
    return $result 
}

main
