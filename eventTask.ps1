<# 
.SYNOPSIS 
powershell script to monitor debug event logs for event match
.DESCRIPTION 
This script will monitor 'analytic' and 'debug' event logs of format .etl for certain event entries.
    Optionally on match, the script can send an email or run an action.
.NOTES 
File Name : eventTask.ps1 
Author    : jagilber
 Version    : 141206
.EXAMPLE 
.\eventTask.ps1 -install $true
    .\eventTask.ps1 -uninstall $true
    .\eventTask.ps1 -test $true
.PARAMETER install
    will install task scheduler computer startup task to run this script for event log monitor.
.PARAMETER uninstall
    will uninstall task scheduler computer startup task to run this script for event log monitor.
.PARAMETER test
    will test script and sent email if settings are configured.
.PARAMETER workingDir
    working script directory
#> 

Param(

    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to install event log monitor")]
    [bool] $install = $false,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to uninstall event log monitor")]
    [bool] $uninstall = $false,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to test email")]
    [bool] $test = $false,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter working directory")]
    [string] $workingDir
    )

$error.Clear()

$ErrorActionPreference = "SilentlyContinue"
$logFile = "eventTask.log"
$sleepItervalSecs = 60


# event information
$eventLog = "Microsoft-Windows-PrintService/Debug"
$eventId = 119
$eventErrorCode = "0x709"
$eventLabel = "ROUTER_STOP_ROUTING"
$maxEventMatchCount = 10 # 0 disables max count and will run indefinitely

# task information 
# deploy task called during install and as 2nd command during match (to redeploy)
$eventTaskProcessDeploy = "powershell.exe"
$eventTaskArgumentsDeploy = "-WindowStyle Hidden -NonInteractive -Executionpolicy unrestricted -file .\logman-wrapper.ps1 -action deploy -configurationFolder .\configs_rds -rds true"

# undeploy task called during uninstall and as 1st command during match 
$eventTaskProcessUnDeploy = "powershell.exe"
$eventTaskArgumentsUnDeploy = "-WindowStyle Hidden -NonInteractive -Executionpolicy unrestricted -file .\logman-wrapper.ps1 -action undeploy -configurationFolder .\configs_rds -rds true"

# email Information
$To = ""
$From = ""
$Subject = "$($env:computername): monitored event received"
$Body = "event was received that matches filter"

# SMTP Relay Settings
$Server = ""
$Port = 
$passFile = "" 
$username = ""
$useSSL = $false
$useCreds = $false

# scheduled task info
$TaskName = "EventLog Monitor"
$TaskDescr = "Monitors eventlog for event"
$TaskCommand = "powershell.exe"
$TaskScript = (get-variable myinvocation -scope script).Value.Mycommand.Definition #"$($workingDir)\eventTask.ps1"
$TaskArg = "-WindowStyle Hidden -NonInteractive -Executionpolicy unrestricted -file $TaskScript"
$time = (get-date) #- (new-timespan -day 12)


# ----------------------------------------------------------------------------------------------------------------
function main()
{
    try
    {

        if($useCreds)
        {
       set-credentials
        }


        if([string]::IsNullOrEmpty($workingDir))
        {
        $workingDir = get-workingDirectory
        }

      if($install)
        {
            install-task
            exit
        }
        elseif($uninstall)
        {
            uninstall-task
            exit
        }

        # start tracing
        run-process -processName $eventTaskProcessDeploy -arguments $eventTaskArgumentsDeploy -wait $true

        if($test)
        {
            # run as administrator
            runas-admin $scriptName
            install-task

        new-eventLog -LogName $eventLog -source "TEST" 
       Write-EventLog -LogName $eventLog -Source "TEST" -Message "TEST" -EventId $eventId -EntryType Information
        remove-eventlog -source "TEST"
        
            monitor-events
            uninstall-task
         exit
        }
       else
        {
         monitor-events
        }

        log-info "exiting"

    }
    finally
    {
        
        # stop tracing if no longer monitoring    
        run-process -processName $eventTaskProcessUnDeploy -arguments $eventTaskArgumentsUnDeploy -wait $true

    }
}

# ----------------------------------------------------------------------------------------------------------------
function set-credentials()
{
    $Creds
# if storing creds for smtp, password will have to be saved one time
# uncomment following to prompt for credentials
#$Creds = Get-Credential

if(!$Creds)
{
    if(!(test-path $passFile))
    {
    read-host -assecurestring | convertfrom-securestring | out-file $passFile
    }

    $password = cat $passFile | convertto-securestring
    $creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
}
}

# ----------------------------------------------------------------------------------------------------------------
function monitor-events()
{
  $matchCount = 0
$monitoring = $true
    $lastRecordId = 0

  

    # monitor specified eventlog
    while($monitoring)
    {
    $events = get-winEvent -Oldest -FilterHashTable @{LogName=$eventLog; StartTime=$time; Id=$eventId}
    log-info "new event count matching filter:$($events.Length) startTime:$($time)"

    foreach($event in $events)
    {
            
            if([string]::IsNullOrEmpty($event.TimeCreated))
            {
                log-info "empty event, skipping..."
                continue    
            }

    $time = $event.TimeCreated
            log-info "last event TimeCreated:$($time) recordId: $($event.RecordId) matchCount: $($matchCount)"

            # bump time by a second so that we do not get duplicate returns
            if($lastRecordId -eq $event.RecordId)
            {
                $time = $time.AddSeconds(1)
                log-info "query returned duplicate record. incrementing startTime:$($time)"
                $lastRecordId = $event.RecordId
		continue
            }

            if($lastRecordId -lt $event.RecordId)
            {
                $lastRecordId = $event.RecordId
            }

log-info $event.Message

    [xml] $xml = $event.ToXml()

    $label = $xml.Event.UserData.SpoolerGenericEvent.Label 
$errorCode = $xml.Event.UserData.SpoolerGenericEvent.ErrorCode
    

if($test)
    {
                # with a test source, message will not be stored in event object correctly
    $eventLabel = $xml.Event.EventData.Data #$event.Message
    $label = "TEST"
    $errorCode = $eventErrorCode 
                $monitoring = $false
}

    if(($label -match $eventLabel) -and $errorCode -match $eventErrorCode)
    {
    log-info "found match:$($event)"
                $matchCount++
                
     send-mail

                # stop tracing to gather information
                run-process -processName $eventTaskProcessUnDeploy -arguments $eventTaskArgumentsUnDeploy -wait $true
                
                if(($maxEventMatchCount -gt 0) -and ($matchCount -gt $maxEventMatchCount))
                {
                    log-info "max events reached."
                    $monitoring = $false
                }
                else
                {
                    # still monitoring so restart tracing
                    run-process -processName $eventTaskProcessDeploy -arguments $eventTaskArgumentsDeploy -wait $true                
                }
    }
    }

    if($monitoring)
    {
    sleep $sleepItervalSecs
    }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function install-task()
{
    # run as administrator
    runas-admin $scriptName

  # add to task scheduler as a computer startup script
    if(manage-scheduledTask -enable $true)
    {
        $eventLog = Get-WinEvent -ListLog $eventLog
     $eventLog.IsEnabled = $true
        $eventLog.SaveChanges()
        log-info "create scheduled task and enabled debug eventlog"
    }
    else
    {
        log-info "unable to create scheduled task and enable debug eventlog. check log."
    }

    # run-process -processName $eventTaskProcessDeploy -arguments $eventTaskArgumentsDeploy -wait $true

}

# ----------------------------------------------------------------------------------------------------------------
function uninstall-task()
{
    # run as administrator
    runas-admin $scriptName
    
    # remove from task scheduler
if(manage-scheduledTask -enable $false)
    {
       $eventLog = Get-WinEvent -ListLog $eventLog
       $eventLog.IsEnabled = $false
       $eventLog.SaveChanges()
       log-info "deleted scheduled task and disabled debug eventlog"
    }
    else
    {
        log-info "unable to delete scheduled task and disable debug eventlog. check log."
    }

    run-process -processName $eventTaskProcessUnDeploy -arguments $eventTaskArgumentsUnDeploy -wait $true
}

# ----------------------------------------------------------------------------------------------------------------
function send-mail()
{
    log-info "sending email"
    
    if([string]::IsNullOrEmpty($To) -or [string]::IsNullOrEmpty($Server))
    {
        log-info "no mail config. skipping..."
        return
    }    

if($useSSL -and $useCreds)
    {
    Send-MailMessage -To $To -From $From -SmtpServer $Server -Port $Port -UseSsl -Credential $Creds -Subject $Subject -Body $Body
    }
    elseif($useCreds)
    {
    Send-MailMessage -To $To -From $From -SmtpServer $Server -Port $Port -Credential $Creds -Subject $Subject -Body $Body
    }
    else
    {
    Send-MailMessage -To $To -From $From -SmtpServer $Server -Port $Port -Subject $Subject -Body $Body
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $data = "$([System.DateTime]::Now):$($data)`n"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
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
    $process.StartInfo.WorkingDirectory = get-location

[void]$process.Start()
    if($wait -and !$process.HasExited)
    {
    $process.WaitForExit($processWaitMs)
    $exitVal = $process.ExitCode
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()
    log-info "Process output:$stdOut"

    if(![System.String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
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
function manage-scheduledTask([bool] $enable)
{
    # win 2k8r2 and below have to use com object
    # 2012 can use cmdlets
       $error.Clear()
    $service = new-object -ComObject("Schedule.Service")
    # connect to the local machine.
    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381833(v=vs.85).aspx
    $service.Connect()
    $rootFolder = $service.GetFolder("\")

    if($enable)
    {
    $TaskDefinition = $service.NewTask(0)
    $TaskDefinition.RegistrationInfo.Description = "$TaskDescr"
    $TaskDefinition.Settings.Enabled = $true
    $TaskDefinition.Settings.AllowDemandStart = $true

    $triggers = $TaskDefinition.Triggers
    #http://msdn.microsoft.com/en-us/library/windows/desktop/aa383915(v=vs.85).aspx
    $trigger = $triggers.Create(8) # Creates a "boot time" trigger
    #$trigger.StartBoundary = $TaskStartTime.ToString("yyyy-MM-dd'T'HH:mm:ss")
    $trigger.Enabled = $true

    # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381841(v=vs.85).aspx
    $Action = $TaskDefinition.Actions.Create(0)
    $action.Path = "$TaskCommand"
    $action.Arguments = "$TaskArg"
    $action.WorkingDirectory = $workingDir
    
#http://msdn.microsoft.com/en-us/library/windows/desktop/aa381365(v=vs.85).aspx
    $rootFolder.RegisterTaskDefinition("$TaskName",$TaskDefinition,6,"System",$null,5)

    #start task
    $task = $rootFolder.GetTask($TaskName)

    $task.Run($null)

    }
    else
    {
    # stop task if its running
    foreach($task in $service.GetRunningTasks(1))
    {
    if($task.Name -ieq $TaskName)
    {
                    log-info "found task"
    $task.Stop()
    }
    }

    # delete task
    $rootFolder.DeleteTask($TaskName,$null)
    }

    
    if($error.Count -ge 1)
    {
        log-info $error
        $error.Clear()
        return $false
    }
    else
    {
        return $true
    }

}

# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    $retVal

    if (Test-Path variable:\hostinvocation)
    {
    $retVal = $hostinvocation.MyCommand.Path
    }
    else
    {
    $retVal = (get-variable myinvocation -scope script).Value.Mycommand.Definition
    }
 
if (Test-Path $retVal)
    {
    $retVal = (Split-Path $retVal)
    }
    else
    {
    $retVal = (Get-Location).path
    log-info "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
    
} 

    
Set-Location $retVal

    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin([string] $arguments)
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       exit
    }
}

# ----------------------------------------------------------------------------------------------------------------

main 
