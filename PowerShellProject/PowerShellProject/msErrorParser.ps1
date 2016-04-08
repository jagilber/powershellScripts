<#  
.SYNOPSIS  
    powershell script to parse text files for ms error return codes (winerror.h)
.DESCRIPTION  
    powershell script to parse text files for ms error return codes (winerror.h).
    output will be in same directory as source with same name as source with a .log appended
.NOTES  
   File Name  : msErrorParser.ps1  
   Author     : jagilber
   Version    : 141231
   History    : base
.EXAMPLE  
    .\msErrorParser.ps1 -file c:\temp\trace.csv
    parses trace.csv for errors
.PARAMETER file
    the file to parse
 
#>  
 
Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the file to parse:")]
    [string] $file
    
    )

$logFile = "$($file).err.log"
$errorProcess = "err.exe"
$regexPattern = "\b0x[0-9a-fA-F]{8}\b" #|\b[0-9a-fA-F]{8}\b"
$errorList = @{}

# ---------------------------------------------------------------------------------------------------------------- 
function main()
{
    if([string]::IsNullOrEmpty($file))
    {
        log-info "must supply 'file' argument specifying text file to parse. exiting..."
        return    
    }

    if([IO.File]::Exists($logFile))
    {
        [IO.File]::Delete($logFile)
    }

    log-info "============================================"
    log-info "starting $([DateTime]::Now)" 
    log-info "============================================"
    
    
   
    if([IO.File]::Exists($file))
    {
        [IO.StreamReader] $reader = new-object IO.StreamReader ($file)
        while ($reader.Peek() -ge 0)
        {
            $line = $reader.ReadLine()
            if([regex]::IsMatch($line,$regexPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase))
            {
                log-info "============================================"
                log-info $line
                [Text.RegularExpressions.MatchCollection] $matches = [regex]::Matches($line,$regexPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)

                foreach($match in $matches)
                {
                    log-info $match.ToString().ToUpper()
                    $cleanMatch = $match.ToString().ToUpper().Trim()

                    if($errorList.ContainsKey($cleanMatch.ToString().ToUpper()))
                    {
                        $errorList.($cleanMatch.ToString().ToUpper()) = $errorList.($cleanMatch.ToString().ToUpper()) + 1
                    }
                    else
                    {
                        $errorList.Add($cleanMatch.ToString().ToUpper(),1)
                    }

                }
            }
        }

    }
    else
    {
        log-info "file $($file) does not exist. exiting..."
        return
    }

    log-info "============================================"
    log-info "error descriptions:"
    log-info "============================================"
    foreach($item in $errorList.GetEnumerator() | Sort-Object Value -Descending)
    {
        log-info "============================================"
        log-info "error: $($item.Key)"
        log-info "count: $($item.Value)"
        log-info "description:"
        log-info "$(run-process -processName $errorProcess -arguments $item.Key -wait $true)"
    }

    log-info "============================================"
    log-info "error list: $($errorList.Count)"
    log-info "============================================"
    $totalCount = 0
    foreach($item in $errorList.GetEnumerator() | Sort-Object Value -Descending)
    {
        log-info "error: $($item.Key) count: $($item.Value)"
        $totalCount += $item.Value
    }



    log-info "============================================"
    log-info "stopping $([DateTime]::Now) total count: $($totalCount)" 
    log-info "============================================"
    
}

 
# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    # $data = "$([DateTime]::Now):$($data)`n"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    #log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WorkingDirectory = get-location
 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        # log-info "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            # log-info "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        log-info "Process ended before capturing output."
    }

    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
main