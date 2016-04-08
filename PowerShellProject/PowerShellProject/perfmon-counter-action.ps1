<#  
.SYNOPSIS  
    powershell script to monitor a performance counter and take an action
.DESCRIPTION  
    - All variables are configued at top of script and not via command line
    - make sure script execution is enabled if not already by: set-executionpolicy  RemoteSigned
    - run script from administrator prompt

    - details
        - will wait for a threshold
        - will monitor for sustained threshold
        - will launch a start executable
        - will wait for certain amount of time
        - will launch s stop executable

    ** Copyright (c) Microsoft Corporation. All rights reserved - 2015.
    **
    ** This script is not supported under any Microsoft standard support program or service.
    ** The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    ** implied warranties including, without limitation, any implied warranties of merchantability
    ** or of fitness for a particular purpose. The entire risk arising out of the use or performance
    ** of the scripts and documentation remains with you. In no event shall Microsoft, its authors,
    ** or anyone else involved in the creation, production, or delivery of the script be liable for
    ** any damages whatsoever (including, without limitation, damages for loss of business profits,
    ** business interruption, loss of business information, or other pecuniary loss) arising out of
    ** the use of or inability to use the script or documentation, even if Microsoft has been advised
    ** of the possibility of such damages.
    **
 
.NOTES  
   File Name  : perfmon-counter-actions.ps1
   Author     : jagilber
   Version    : 150618 
   History    : 
#>  


$threshold = 99
$sampleInterval = 1 #seconds
$sustainedIterations = 30 
$runTime = 60 #seconds
$logFile = "perfmon-counter-action.log"
$logDetail = $false
$processWaitMs = 10000

$workingDir = "c:\temp"

$startCommand = "cmd.exe"
$startArguments = "/c xperf.mgr.bat start highcpu"

$stopCommand = "cmd.exe"
$stopArguments = "/c xperf.mgr.bat stop highcpu"

$sustainedCount = 0


#-------------------------------------------------------------------------------------------------
function main()
{
    # run as administrator
    runas-admin

    while($true)
    {
        $counterObj = Get-counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval $sampleInterval
        $cookedValue = 0
        foreach($val in $counterObj.CounterSamples.GetEnumerator())
        { 
            $cookedValue = $val.CookedValue 
        }
    
        if($sustainedCount -ge $sustainedIterations)
        {
            log-info "starting app"
            run-process -processName $startCommand -arguments $startArguments -workingDir $workingDir -wait $true
        
            if($runTime -gt 0 -and $stopCommand -ne $null)
            {
                Start-Sleep $runTime
                log-info "stopping app"
                run-process -processName $stopCommand -arguments $stopArguments -workingDir $workingDir -wait $true
                log-info "exiting"
                return

            }
            else
            {
                log-info "exiting"
                return
            }

        }
        elseif($cookedValue -ge $threshold)
        {
            log-info "in state. sustainedCount: $($sustainedCount) value: $($cookedValue)"
            $sustainedCount++        
        }
        else
        {
            if($logDetail)
            {
                log-info "not in state. sustainedCount: $($sustainedCount) value: $($cookedValue)"
            }

            $sustainedCount = 0
        }


    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $data = "$([DateTime]::Now):$($data)"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [string] $workingDir, [bool] $wait = $false)
{
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WorkingDirectory = $workingDir
 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        log-info "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            log-info "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        log-info "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
}

 
# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       exit
    }
}

#------------------------------------------------------------------------------------------------- 
main
