<#
.SYNOPSIS
    powershell script to manage event logs on multiple machines

.DESCRIPTION

    Set-ExecutionPolicy Bypass -Force

    This script will optionally enable / disable debug and analytic event logs.
    This can be against both local and remote machines.
    It will also take a regex filter pattern for both event log names and traces.
    For each match, all event logs will be exported to csv format.
    Each export will be in its own file named with the event log name.
    It also has ability to 'listen' to new events by continuously polling configured event logs

.NOTES

   File Name  : event-log-manager.ps1
   Author     : jagilber
   Version    : 161026 added $baseDir to process-eventlogs

   History    : 
                161010 -eventDetails switch wasnt getting passed to job
                160919 added max read count, added logic in listen to temporarily remove machines that arent responding
                160904 removed 'security' from -rds. takes too long to export

.EXAMPLE
    .\event-log-manager.ps1 –rds –minutes 10
    Example command to query rds event logs.
    If active connection broker will query all servers, else it should just query local for any events in last 10 minutes:

.EXAMPLE
    .\event-log-manager.ps1 –rds –minutes 10 –machines rds-gw-1,rds-gw-2
    Example command to query rds event logs. It will query machines rds-gw-1 and rds-gw-2 for events in last 10 minutes:

.EXAMPLE
    .\event-log-manager.ps1 –rds –machines rds-gw-1,rds-gw-2
    Example command to query rds event logs. It will query machines rds-gw-1 and rds-gw-2 for events for today:

.EXAMPLE
    .\event-log-manager.ps1 –enableDebugLogs
    Example command to enable ‘debug and analytic’ event logs:

.EXAMPLE
    .\event-log-manager.ps1 –enableDebugLogs -rds
    Example command to enable ‘debug and analytic’ event logs and rds debug registry flags:

.EXAMPLE
    .\event-log-manager.ps1 –disableDebugLogs
    Example command to disable ‘debug and analytic’ event logs:

.EXAMPLE
    .\event-log-manager.ps1 –cleareventlogs
    Example command to clear event logs:

.EXAMPLE
    .\event-log-manager.ps1 –eventStarTime "12/15/2015 10:00 am"
    Example command to query for all events after specified time:

.EXAMPLE
    .\event-log-manager.ps1 –eventStopTime "12/15/2015 10:00 am"
    Example command to query for all events up to specified time:

.EXAMPLE
    .\event-log-manager.ps1 –listEventLogs
    Example command to query all event log names:

.EXAMPLE
    .\event-log-manager.ps1 -listen -rds -machines rds-rds-1,rds-rds-2,rds-cb-1
    Example command to listen to multiple machines for all eventlogs for Remote Desktop Services:

.EXAMPLE
    .\event-log-manager.ps1 -eventLogPath c:\temp -eventLogNames . 
    Example command to query path c:\temp for all *.evt* files and convert to csv:

.PARAMETER clearEventLogs
    If specified, will clear all event logs matching 'eventLogNamePattern'

.PARAMETER clearEventLogsOnGather
    If specified, will clear all event logs matching 'eventLogNamePattern' after eventlogs have been gathered.

.PARAMETER days
    If specified, is the number of days to query from the event logs. The number specified is a positive number

.PARAMETER disableDebugLogs
    If specified, will disable the 'analytic and debug' event logs matching 'eventLogNamePattern'

.PARAMETER displayMergedResults
    If specified, will display merged results in default viewer for .csv files.

.PARAMETER enableDebugLogs
    If specified, will enable the 'analytic and debug' event logs matching 'eventLogNamePattern'
    NOTE: at end of troubleshooting, remember to 'disableEventLogs' as there is disk and cpu overhead for debug logs
    WARNING: enabling too many debug eventlogs can make system non responsive and may make machine unbootable!
    Only enable specific debug logs needed and only while troubleshooting.

.PARAMETER eventDetails
    If specified, will output event log items including xml data found on 'details' tab.

.PARAMETER eventLogIds
    If specified, a comma separated list of event logs id's to query.
    Default is all id's.

.PARAMETER eventLogLevels
    If specified, a comma separated list of event log levels to query.
    Default is all event levels.
    Options are Critical,Error,Warning,Information,Verbose

.PARAMETER eventLogNamePattern
    If specified, is a string or regex pattern to specify event log names to modify / query.
    If not specified, the default value is for 'Application' and 'System' event logs
    If 'rds $true' and this argument is not specified, the following regex will be used "RemoteApp|RemoteDesktop|Terminal"

.PARAMETER eventLogPath
    If specified as a directory, will be used as a directory path to search for .evt and .evtx files. 
    If specified as a file, will be used as a file path to open .evt or .evtx file. 
    This parameter is not compatible with '-machines'

.PARAMETER eventStartTime
    If specified, is a time and / or date string that can be used as a starting time to query event logs
    If not specified, the default is for today only

.PARAMETER eventStopTime
    If specified, is a time and / or date string that can be used as a stopping time to query event logs
    If not specified, the default is for current time

.PARAMETER eventTracePattern
    If specified, is a string or regex pattern to specify event log traces to query.
    If not specified, all traces matching other criteria are displayed

.PARAMETER getUpdate
    If specified, will compare the current script against the location in github and will update if different.

.PARAMETER hours
    If specified, is the number of hours to query from the event logs. The number specified is a positive number

.PARAMETER listen
    If specified, will listen and display new events from event logs matching specifed pattern with eventlognamepattern

.PARAMETER listeventlogs
    If specified, will list all eventlogs matching specified pattern with eventlognamepattern

.PARAMETER machines
    If specified, will run script against remote machine(s). List is comma separated.
    If not specified, script will run against local machine

.PARAMETER minutes
    If specified, is the number of minutes to query from the event logs. The number specified is a positive number

.PARAMETER months
    If specified, is the number of months to query from the event logs. The number specified is a positive number

.PARAMETER noDynamicPath
    If specifed, will store files in a non-timestamped folder which is useful if calling from another script.

.PARAMETER rds
    If specified, will set the default 'eventLogNamePattern' to "RemoteApp|RemoteDesktop|Terminal" if value not populated
    If specified, will try to enumerate active connection broker cmdlet get-rdservers. If successful, will prompt to optionally enable gathering event logs from entire deployment
    If specified, and -enableDebugLogs is specified, rds specific debug flags will be enabled
    If specified, and -disableDebugLogs is specified, rds specific debug flags will be disabled

.PARAMETER uploadDir
    The directory where all files will be created.
    The default is .\gather

#>

Param(
    [parameter(Position=0,Mandatory=$false,HelpMessage="Select to clear events")]
    [switch] $clearEventLogs,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Select to clear events after gather")]
    [switch] $clearEventLogsOnGather,
    [parameter(HelpMessage="Enter days")]
    [int] $days = 0,
    [parameter(HelpMessage="Enable to debug script")]
    [switch] $debugScript = $false,
    [parameter(HelpMessage="Select to disable debug event logs")]
    [switch] $disableDebugLogs,
    [parameter(HelpMessage="Display merged event results in viewer. Requires log-merge.ps1")]
    [switch] $displayMergedResults,
    [parameter(HelpMessage="Select to enable debug event logs")]
    [switch] $enableDebugLogs,
    [parameter(HelpMessage="Enter comma separated list of event log levels Critical,Error,Warning,Information,Verbose")]
    [string[]] $eventLogLevels = @("critical","error","warning","information","verbose"),
    [parameter(HelpMessage="Enter comma separated list of event log Id")]
    [int[]] $eventLogIds = @(),
    [parameter(HelpMessage="Enter regex or string pattern for event log name match")]
    [string] $eventLogNamePattern = "",
    [parameter(HelpMessage="Enter path and file name of event log file to open")]
    [string] $eventLogPath = "",
    [parameter(HelpMessage="Enter start time / date (the default is events for today)")]
    [string] $eventStartTime,
    [parameter(HelpMessage="Enter stop time / date (the default is current time)")]
    [string] $eventStopTime,
    [parameter(HelpMessage="Enter regex or string pattern for event log trace to match")]
    [string] $eventTracePattern = "",
    [parameter(HelpMessage="Select this switch to export event entry details tab")]
    [switch] $eventDetails,
    [parameter(HelpMessage="Select to check for new version of file")]
    [switch] $getUpdate,
    [parameter(HelpMessage="Enter hours")]
    [int] $hours = 0,
    [parameter(HelpMessage="Listen to event logs either all or by -eventLogNamePattern")]
    [switch] $listen,
    [parameter(HelpMessage="List event logs either all or by -eventLogNamePattern")]
    [switch] $listEventLogs,
                [parameter(HelpMessage="Enter comma separated list of machine names")]
    [string[]] $machines = @(),
    [parameter(HelpMessage="Enter minutes")]
    [int] $minutes = 0,
    [parameter(HelpMessage="Enter months")]
    [int] $months = 0,
    [parameter(HelpMessage="Select to force all files to be flat when run on a single machine")]
    [switch] $nodynamicpath,
    [parameter(HelpMessage="Enter minutes")]
    [switch] $rds,
    [parameter(HelpMessage="Enter path for upload directory")]
    [string] $uploadDir
    )

cls
$appendOutputFiles = $false
$debugLogsMax = 100
$errorActionPreference = "Continue"
$eventLogLevelQueryString = $null
$eventLogLevelIdString = $null
$global:eventLogFiles = ![string]::IsNullOrEmpty($eventLogPath)
$global:eventLogNameSearchPattern = $eventLogNamePattern
$global:jobs = New-Object Collections.ArrayList
$global:machineRecords = @{}
$global:uploadDir = $uploadDir
$jobThrottle = 10
$listenMachineDisabledCount = 10
$listenEventReadCount = 100
$listenSleepMs = 1000
$logFile = "event-log-manager-output.txt"
$logMerge = ".\log-merge.ps1"
$maxSortCount = 100
$silent = $true
$startTime = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/event-log-manager.ps1"

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()

    log-info "starting $([DateTime]::Now.ToString()) $([Diagnostics.Process]::GetCurrentProcess().StartInfo.Arguments)"

    # log arguments
    log-info $PSCmdlet.MyInvocation.Line;
    log-arguments

    # set upload directory
    set-uploadDir

    # clean up old jobs
    remove-jobs $silent

    # some functions require admin
    if($clearEventLogs -or $enableDebugLogs -or $disableDebugLogs)
    {
        runas-admin

        if($clearEventLogs)
        {
            log-info "clearing event logs"
        }

        if($enableDebugLogs)
        {
            log-info "enabling debug event logs"
        }

        if($disableDebugLogs)
        {
            log-info "disabling debug event logs"
        }
    }

    # see if new (different) version of file
    if($getUpdate)
    {
        get-update -updateUrl $updateUrl
    }

    # add local machine if empty
    if($machines.Count -lt 1)
    {
        $machines += $env:COMPUTERNAME
    }

    # when passing comma separated list of machines from bat, it does not get separated correctly
    elseif($machines.length -eq 1 -and $machines[0].Contains(","))
    {
        $machines = $machines[0].Split(",")
    }

    # setup for rds
    if($rds)
    {
        $machines = configure-rds -machines $machines -eventLogNamePattern $global:eventLogNameSearchPattern
    }

    # set default event log names if not specified
    if(!$listEventLogs -and [string]::IsNullOrEmpty($global:eventLogNameSearchPattern))
    {
        $global:eventLogNameSearchPattern = "^Application$|^System$"
    }
    elseif($listEventLogs -and [string]::IsNullOrEmpty($global:eventLogNameSearchPattern))
    {
        # just listing eventlogs and pattern not specified so show all
        $global:eventLogNameSearchPattern = "."
    }

    # set to local host if not specified
    if($machines.Length -lt 1)
    {
        $machines = @($env:COMPUTERNAME)
    }

                # create xml query
    [string]$eventLogLevelQueryString = build-eventLogLevels -eventLogLevels $eventLogLevels
    [string]$eventLogIdQueryString = build-eventLogIds -eventLogIds $eventLogIds

    # make sure start stop and other time range values were not all specified
    if(![string]::IsNullOrEmpty($eventStartTime) -and ![string]::IsNullOrEmpty($eventStopTime) -and ($months + $days + $minutes -gt 0))
    {
        log-info "invalid parameter combination. cannot specify start and stop and other time range attributes in same command. exiting"
        exit
    }

    # determine start time if specified else just search for today
    if($listen)
    {
        $appendOutputFiles = $true
        $eventStartTime = [DateTime]::Now
        $eventStopTime = [DateTime]::MaxValue
    }

    if([string]::IsNullOrEmpty($eventStartTime))
    {
        $origStartTime = ""
    }
    else
    {
        $origStartTime = $eventStartTime
    }

                # determine start and stop times for xml query
    $eventStartTime = configure-startTime -eventStartTime $eventStartTime `
        -eventStopTime $eventStopTime `
        -months $months `
        -days $days `
        -hours $hours `
        -minutes $minutes

    $eventStopTime = configure-stopTime -eventStarTime $origStartTime `
        -eventStopTime $eventStopTime `
        -months $months `
        -days $days `
        -hours $hours `
        -minutes $minutes

    # process all machines
    process-machines -machines $machines `
        -eventStartTime $eventStartTime `
        -eventStopTime $eventStopTime `
        -eventLogLevelsQuery $eventLogLevelQueryString `
        -eventLogIdsQuery $eventLogIdQueryString

   start $global:uploadDir
   
   log-info "files are located here: $($global:uploadDir)"
   log-info "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function build-eventLogIds($eventLogIds)
{
    [Text.StringBuilder] $sb = new-object Text.StringBuilder

    foreach($eventLogId in $eventLogIds)
    {
        [void]$sb.Append("EventID=$($eventLogId) or ")
    }

    return $sb.ToString().TrimEnd(" or ")
}

# ----------------------------------------------------------------------------------------------------------------
function build-eventLogLevels($eventLogLevels)
{
    [Text.StringBuilder] $sb = new-object Text.StringBuilder

    foreach($eventLogLevel in $eventLogLevels)
    {
        switch ($eventLogLevel.ToLower())
        {
            "critical" { [void]$sb.Append("Level=1 or ") }
                                                "error" { [void]$sb.Append("Level=2 or ") }
            "warning" { [void]$sb.Append("Level=3 or ") }
            "information" { [void]$sb.Append("Level=4 or Level=0 or ") }
            "verbose" { [void]$sb.Append("Level=5 or ") }
       }
    }

    return $sb.ToString().TrimEnd(" or ")
}

# ----------------------------------------------------------------------------------------------------------------
function configure-rds($machines,$eventLogNamePattern)
{
    log-info "setting up for rds environment"
    $baseRDSPattern = "RDMS|RemoteApp|RemoteDesktop|Terminal|VHDMP|^System$|^Application$|User-Profile-Service" #CAPI|^Security$"

    if(![string]::IsNullOrEmpty($global:eventLogNameSearchPattern))
    {
        $global:eventLogNameSearchPattern = "$($global:eventLogNameSearchPattern)|$($baseRDSPattern)"
    }
    else
    {
        $global:eventLogNameSearchPattern = $baseRDSPattern
    }
    
    if(!(get-service -DisplayName 'Remote Desktop Connection Broker' -ErrorAction SilentlyContinue))
    {
        $error.Clear()
        return $machines
    }

    try
    {
        $servers = @()
        # see if it is a connection broker
        $servers = (Get-RDServer).Server
        if($servers -ne $null)
        {
            foreach($server in $servers)
            {
                log-info $server
            }

            $result = Read-Host "do you want to collect data from entire deployment? [y:n]"
            if([regex]::IsMatch($result, "y",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
            {
                log-info "adding rds collection servers"
                $machines = $servers
            }
        }
    }
    catch {}

    return $machines
}

# ----------------------------------------------------------------------------------------------------------------
function configure-startTime( $eventStartTime, $eventStopTime, $months, $hours, $days, $minutes )
{
    [DateTime] $time = new-object DateTime
    [void][DateTime]::TryParse($eventStartTime,[ref] $time)

    if($time -eq [DateTime]::MinValue -and ![string]::IsNullOrEmpty($eventLogPath))
    {
        # parsing existing evtx files so do not override $eventStartTime if it was not provided
        [DateTime] $eventStartTime = $time
    }
    elseif($time -eq [DateTime]::MinValue -and [string]::IsNullOrEmpty($eventStopTime) -and ($months + $hours + $days + $minutes -eq 0))
    {
        # default to just today
        $time = [DateTime]::Now.Date
        [DateTime] $eventStartTime = $time
    }
    elseif($time -eq [DateTime]::MinValue -and [string]::IsNullOrEmpty($eventStopTime))
    {
        # subtract from current time
        $time = [DateTime]::Now
        [DateTime] $eventStartTime = $time.AddMonths(-$months).AddDays(-$days).AddHours(-$hours).AddMinutes(-$minutes)
    }
    else
    {
        # offset should not be applied if $eventStartTime specified
        [DateTime] $eventStartTime = $time
    }

    log-info "searching for events newer than: $($eventStartTime.ToString("yyyy-MM-ddTHH:mm:sszz"))"
    return $eventStartTime
}

# ----------------------------------------------------------------------------------------------------------------
function configure-stopTime($eventStartTime,$eventStopTime,$months,$hours,$days,$minutes)
{
    [DateTime] $time = new-object DateTime
    [void][DateTime]::TryParse($eventStopTime,[ref] $time)

    if([string]::IsNullOrEmpty($eventStartTime) -and $time -eq [DateTime]::MinValue -and ($months + $hours + $days + $minutes -gt 0))
    {
        # set to current and return
        [DateTime] $eventStopTime = [DateTime]::Now
    }
    elseif($time -eq [DateTime]::MinValue -and $months -eq 0 -and $hours -eq 0 -and $days -eq 0 -and $minutes -eq 0)
    {
        [DateTime] $eventStopTime = [DateTime]::Now
    }
    elseif($time -eq [DateTime]::MinValue)
    {
        # subtract from current time
        $time = [DateTime]::Now
        [DateTime] $eventStopTime = $time.AddMonths(-$months).AddDays(-$days).AddHours(-$hours).AddMinutes(-$minutes)
    }
    else
    {
        # offset should not be applied if $eventStopTime specified
        [DateTime] $eventStopTime = $time
    }

   log-info "searching for events older than: $($eventStopTime.ToString("yyyy-MM-ddTHH:mm:sszz"))"
    return $eventStopTime
}

# ----------------------------------------------------------------------------------------------------------------
function dump-events( $eventLogNames, [string] $machine, [DateTime] $eventStartTime, [DateTime] $eventStopTime, $eventLogLevelsQuery, $eventLogIdsQuery)
{
    $newEvents = New-Object Collections.ArrayList #(,2)

    # build query string from ids and levels
    if(![string]::IsNullOrEmpty($eventLogLevelsQuery) -and ![string]::IsNullOrEmpty($eventLogIdsQuery))
    {
        $eventQuery = "($($eventLogLevelsQuery)) and ($($eventLogIdsQuery)) and "
    }
    elseif(![string]::IsNullOrEmpty($eventLogLevelsQuery))
    {
        $eventQuery = "($($eventLogLevelsQuery)) and "
    }
    elseif(![string]::IsNullOrEmpty($eventLogIdsQuery))
    {
        $eventQuery = "($($eventLogIdsQuery)) and "
    }

    # used to peek at events
    $psession = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)

    # loop through each log
    foreach($eventLogName in $eventLogNames)
    {
        $queryString = "<QueryList>
        <Query Id=`"0`" Path=`"$($eventLogName)`">
        <Select Path=`"$($eventLogName)`">*[System[$($eventQuery)" `
            + "TimeCreated[@SystemTime &gt;=`'$($eventStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`' " `
            + "and @SystemTime &lt;=`'$($eventStopTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`']]]</Select>
        </Query>
        </QueryList>"

        if($listen)
        {
            $recordid = ($global:machineRecords[$machine])[$eventLogName]
            if($recordid -gt 0)
            {
                $queryString = "<QueryList>
                    <Query Id=`"0`" Path=`"$($eventLogName)`">
                    <Select Path=`"$($eventLogName)`">*[System[$($eventQuery)(EventRecordID &gt;`'$($recordid)`')]]</Select>
                    </Query>
                    </QueryList>"
            }
        }

        try
        {
            # peek to see if any records, if so start job
            if(!$global:eventLogFiles)
            {
                $pathType = [Diagnostics.Eventing.Reader.PathType]::LogName
            }
            else
            {
                $pathType = [Diagnostics.Eventing.Reader.PathType]::FilePath
            }

            $pquery = New-Object Diagnostics.Eventing.Reader.EventLogQuery ($eventLogName, $pathType, $queryString)
            $pquery.Session = $psession
            $preader = New-Object Diagnostics.Eventing.Reader.EventLogReader $pquery

            $event = $preader.ReadEvent()
            if($event -eq $null)
            {
                continue
            }

            if($recordid -eq $event.RecordId)
            {
                #sometimes record id's come back as 0 causing dupes
                $recordid++
            }

            $oldrecordid = ($global:machineRecords[$machine])[$eventLogName]
            $recordid = [Math]::Max($recordid,$event.RecordId)

            log-info "dump-events:machine: $($machine) event log name: $eventLogName old index: $($oldRecordid) new index: $($recordId)" -debugOnly

            ($global:machineRecords[$machine])[$eventLogName] = $recordid

            $cleanName = $eventLogName.Replace("/","-").Replace(" ", "-")

            # create csv file name
            if(!$global:eventLogFiles)
            {
                
                $outputCsv = ("$($global:uploadDir)\$($machine)-$($cleanName).csv")
            }
            else
            {
                $outputCsv = ("$($global:uploadDir)\$([IO.Path]::GetFileNameWithoutExtension($cleanName)).csv")
            }

            if(!$appendOutputFiles -and (test-path $outputCsv))
            {
                log-info "removing existing file: $($outputCsv)"
                Remove-Item -Path $outputCsv -Force
            }
        }
        catch
        {
            log-info "FAIL:$($eventLogName): $($Error)" -debugOnly
            [void]$error.Clear()
            continue
        }

        if($listen)
        {
            $count = 0

            while($count++ -le $listenEventReadCount)
            {
                if($event -eq $null)
                {
                    break
                }
                elseif(![string]::IsNullOrEmpty($event.TimeCreated))
                {
                    $description = $event.FormatDescription()
                    if([string]::IsNullOrEmpty($description))
                    {
                        $description = "$(([xml]$event.ToXml()).Event.UserData.InnerXml)"
                    }
                    else
                    {
                        $description = $description.Replace("`r`n",";")
                    }

                    # event log 'details' tab
                    if($eventdetails)
                    {
                        $description = "$($description)`n$($event.FormatDescription().Replace("`r`n",";"));$(([xml]$event.ToXml()).Event.UserData.InnerXml)"
                    }

                    $outputEntry = (("$($event.TimeCreated.ToString("MM/dd/yyyy,hh:mm:ss.ffffff tt"))," `
                                                                                                + "$($machine),$($event.Id),$($event.LevelDisplayName),$($event.ProviderName),$($event.ProcessId)," `
                                                                                                + "$($event.ThreadId),$($description)"))

                                                                                if([string]::IsNullOrEmpty($eventTracePattern) -or
                                                                                                (![string]::IsNullOrEmpty($eventTracePattern) -and
                                                                                                                [regex]::IsMatch($outputEntry,$eventTracePattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                                                                                                                                [Text.RegularExpressions.RegexOptions]::Singleline)))
                    {
                        Out-File -Append -FilePath $outputCsv -InputObject $outputEntry
                        [void]$newEvents.Add($outputEntry)
                    }
                }
                else
                {
                    log-info "empty event, skipping..."
                }

                ($global:machineRecords[$machine])[$eventLogName] = [Math]::Max(($global:machineRecords[$machine])[$eventLogName],$event.RecordId)
                $event = $preader.ReadEvent()
            } # end while

            while($count -ge $listenEventReadCount)
            {
                # to keep listen from getting behind
                # if there are more records than $listenEventReadCount, read the rest
                # cant seek in debug logs.
                # keep reading events but dont process
                $recordid = $event.RecordId
               
                if(!($event = $preader.ReadEvent()))
                {
                    log-info "warning: max read count reached, skipping newest $($count - $listenEventReadCount) events." #-debugOnly
                    break
                }

                ($global:machineRecords[$machine])[$eventLogName] = $event.RecordId                
                $count++
            }

            log-info "listen end count: $($count)" -debugOnly
        }
        else
        {
            #throttle
            While((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
            {
                Start-Sleep -Milliseconds 100
            }

            $job = Start-Job -Name "$($machine):$($eventLogName)" -ScriptBlock {
                param($eventLogName,
                     $appendOutputFiles,
                     $logFile,
                     $global:uploadDir,
                     $machine,
                     $eventStartTime,
                     $eventStopTime,
                     $eventLogLevelsQuery,
                     $eventLogIdsQuery,
                     $clearEventLogsOnGather,
                     $queryString,
                     $eventTracePattern,
                     $outputCsv,
                     $global:eventLogFiles,
                     $eventDetails)

                try
                {
                    $session = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)

                    if(!$global:eventLogFiles)
                    {
                        $pathType = [Diagnostics.Eventing.Reader.PathType]::LogName
                    }
                    else
                    {
                        $pathType = [Diagnostics.Eventing.Reader.PathType]::FilePath
                    }

                    $query = New-Object Diagnostics.Eventing.Reader.EventLogQuery ($eventLogName, $pathType, $queryString)
                    $query.Session = $session
                    $reader = New-Object Diagnostics.Eventing.Reader.EventLogReader $query
                    write-host "processing machine:$($machine) eventlog:$($eventLogName)"
                }
                catch
                {
                    write-host "FAIL:$($eventLogName): $($Error)"
                    $error.Clear()
                    continue
                }

                if(!$appendOutputFiles -and (test-path $outputCsv))
                {
                    write-host "removing existing file: $($outputCsv)"
                    Remove-Item -Path $outputCsv -Force
                }

                while($true)
                {
                    try
                    {
                        $event = $reader.ReadEvent()

                       if($event -eq $null)
                        {
                            break
                        }
                        elseif(![string]::IsNullOrEmpty($event.TimeCreated))
                        {
                            $description = $event.FormatDescription()
                            if([string]::IsNullOrEmpty($description))
                            {
                                $description = "$(([xml]$event.ToXml()).Event.UserData.InnerXml)"
                            }
                            else
                            {
                                $description = $description.Replace("`r`n",";")
                            }
                            
                            #event log 'details' tab view
                            if($eventdetails)
                            {
                                $description = "$($description)`n$($event.FormatDescription().Replace("`r`n",";"));$(([xml]$event.ToXml()).Event.UserData.InnerXml)"
                            }

                            $outputEntry = (("$($event.TimeCreated.ToString("MM/dd/yyyy,hh:mm:ss.ffffff tt")),$($event.Id)," `
                                                                                                        + "$($event.LevelDisplayName),$($event.ProviderName),$($event.ProcessId),$($event.ThreadId)," `
                                                                                                        + "$($description)"))

                                                                                        if([string]::IsNullOrEmpty($eventTracePattern) -or
                                                                                                        (![string]::IsNullOrEmpty($eventTracePattern) -and
                                                                                                                        [regex]::IsMatch($outputEntry,$eventTracePattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                                                                                                                                        [Text.RegularExpressions.RegexOptions]::Singleline)))
                            {
                                if(![string]::IsNullOrEmpty($eventTracePattern))
                                {
                                    write-host "------------------------------------------"
                                    write-host $outputEntry
                                }
                            
                                Out-File -Append -FilePath $($outputCsv) -InputObject $outputEntry
                            }
                        }
                        else
                        {
                            write-host "empty event, skipping..."
                        }
                    }
                    catch
                    {
                        #
                    }
                }

                if($clearEventLogsOnGather)
                {
                    $eventLog = New-Object Diagnostics.Eventing.Reader.EventLogConfiguration ($eventLogName, $session)
                    write-host "clearing event log: $($eventLogName)"
                    if($eventLog.IsEnabled -and !$eventLog.IsClassicLog)
                    {
                        $eventLog.IsEnabled = $false
                        $eventLog.SaveChanges()
                        $eventLog.Dispose()

                        $session.ClearLog($eventLogName)

                        $eventLog = New-Object Diagnostics.Eventing.Reader.EventLogConfiguration ($eventLogName, $session)
                        $eventLog.IsEnabled = $true
                        $eventLog.SaveChanges()
                    }
                    elseif($eventLog.IsClassicLog)
                    {
                        $session.ClearLog($eventLogName)
                    }
                }
           } -ArgumentList ($eventLogName,
               $appendOutputFiles,
               $logFile,
               $global:uploadDir,
               $machine,
               $eventStartTime,
               $eventStopTime,
               $eventLogLevelsQuery,
               $eventLogIdsQuery,
               $clearEventLogsOnGather,
               $queryString,
               $eventTracePattern,
               $outputCsv,
               $global:eventLogFiles,
               $eventDetails)

            if($job -ne $null)
            {
                log-info "job $($job.id) started for eventlog: $($eventLogName)"
                $global:jobs.Add($job)
            }
        }
    }

                $preader.CancelReading()
                $preader.Dispose()
                $psession.CancelCurrentOperations()
                $psession.Dispose()

    return ,$newEvents
}

# ----------------------------------------------------------------------------------------------------------------
function enable-logs($eventLogNames, $machine)
{
    log-info "enabling logs on $($machine)"
    [Text.StringBuilder] $sb = new-object Text.StringBuilder
    $debugLogsEnabled = New-Object Collections.ArrayList

    [void]$sb.Appendline("event logs:")

    foreach($eventLogName in $eventLogNames)
    {
        $session = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)
        $eventLog = New-Object Diagnostics.Eventing.Reader.EventLogConfiguration ($eventLogName, $session)

        if($clearEventLogs)
        {
            [void]$sb.AppendLine("clearing event log: $($eventLogName)")
            if($eventLog.IsEnabled -and !$eventLog.IsClassicLog)
            {
                $eventLog.IsEnabled = $false
                $eventLog.SaveChanges()
                $eventLog.Dispose()

                $session.ClearLog($eventLogName)

                $eventLog = New-Object Diagnostics.Eventing.Reader.EventLogConfiguration ($eventLogName, $session)
                $eventLog.IsEnabled = $true
                $eventLog.SaveChanges()
            }
            elseif($eventLog.IsClassicLog)
            {
                $session.ClearLog($eventLogName)
            }
        }

        if($enableDebugLogs -and $eventLog.IsEnabled -eq $false)
        {
            [void]$sb.AppendLine("enabling debug log for $($eventLog.LogName) $($eventLog.LogMode)")
            $eventLog.IsEnabled = $true
            $eventLog.SaveChanges()
        }

        if($disableDebugLogs -and $eventLog.IsEnabled -eq $true -and ($eventLog.LogType -ieq "Analytic" -or $eventLog.LogType -ieq "Debug"))
        {
            [void]$sb.AppendLine("disabling debug log for $($eventLog.LogName) $($eventLog.LogMode)")
            $eventLog.IsEnabled = $false
            $eventLog.SaveChanges()
        }

        if($eventLog.LogType -ieq "Analytic" -or $eventLog.LogType -ieq "Debug")
        {
            if($eventLog.IsEnabled -eq $true)
            {
                [void]$sb.AppendLine("$($eventLog.LogName) $($eventLog.LogMode): ENABLED")
                $debugLogsEnabled.Add($eventLog.LogName)

                                                                if($debugLogsMax -le $debugLogsEnabled.Count)
                                                                {
                                                                                log-info "Error: too many debug logs enabled ($($debugLogsMax))."
                                                                                log-info "Error: this can cause system performance / stability issues as well as inability to boot!"
                                                                                log-info "Error: rerun script again with these switches: .\event-log-manager.ps1 -listeventlogs -disableDebugLogs"
                                                                                log-info "Error: this will disable all debug logs."
                                                                                log-info "Warning: exiting script."
                                                                                exit 1
                                                                }
            }
            else
            {
                [void]$sb.AppendLine("$($eventLog.LogName) $($eventLog.LogMode): DISABLED")
            }
        }
        else
        {
            [void]$sb.AppendLine("$($eventLog.LogName)")
        }
    }

    log-info $sb.ToString() -nocolor
    log-info "-----------------------------------------"

    if($debugLogsEnabled.Count -gt 0)
    {
        foreach($eventLogName in $debugLogsEnabled)
        {
            log-info $eventLogName
        }

        log-info "-----------------------------------------"
        log-info "WARNING: $($debugLogsEnabled.Count) Debug eventlogs are enabled. Current limit in script is $($debugLogsMax)."
        log-info "`tEnabling too many debug event logs can cause performance / stability issues as well as inability to boot!" -nocolor
        log-info "`tWhen finished troubleshooting, rerun script again with these switches: .\event-log-manager.ps1 -listeventlogs -disableDebugLogs" -nocolor
        log-info "-----------------------------------------"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function filter-eventLogs($eventLogPattern, $machine, $eventLogPath)
{
    $filteredEventLogs = New-Object Collections.ArrayList

    if(!$global:eventLogFiles)
    {
        # query eventlog session
        $session = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)
        $eventLogNames = $session.GetLogNames()
    }
    else
    {
        if([IO.File]::Exists($eventLogPath))
        {
            $eventLogNames = @($eventLogPath)
        }
        else
        {
            # query eventlog path
            $eventLogNames = [IO.Directory]::GetFiles($eventLogPath, "*.evt*",[IO.SearchOption]::AllDirectories)
        }
    }

    [Text.StringBuilder] $sb = new-object Text.StringBuilder
    [void]$sb.Appendline("")

    foreach($eventLogName in $eventLogNames)
    {
        if (![regex]::IsMatch($eventLogName, $eventLogPattern ,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        {
            continue
        }

        [void]$filteredEventLogs.Add($eventLogName)
    }

    [void]$sb.AppendLine("filtered logs count: $($filteredEventLogs.Count)")
    log-info $sb.ToString()

    return $filteredEventLogs
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl)
{
    try 
    {
        # will always update once when copying from web page, then running -getUpdate due to CRLF diff between UNIX and WINDOWS
        # github can bet set to use WINDOWS style which may prevent this
        $webClient = new-object System.Net.WebClient
        $webClient.DownloadFile($updateUrl, "$($MyInvocation.ScriptName).new")
        if([string]::Compare([IO.File]::ReadAllBytes($MyInvocation.ScriptName), [IO.File]::ReadAllBytes("$($MyInvocation.ScriptName).new")))
        {
            log-info "downloaded new script"
            [IO.File]::Copy("$($MyInvocation.ScriptName).new",$MyInvocation.ScriptName, $true)
            [IO.File]::Delete("$($MyInvocation.ScriptName).new")
            log-info "restart to use new script. exiting."
            exit
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $true
        
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    $retVal = [string]::Empty
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
 
    Set-Location $retVal | out-null
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function listen-forEvents()
{
                $unsortedEvents = New-Object Collections.ArrayList
    $sortedEvents = New-Object Collections.ArrayList
    $newEvents = New-Object Collections.ArrayList
    $machineList = new-object Collections.ArrayList 
    
    foreach($machine in $machines)
    {
        $machineList.Add(@{ $machine = @{'Disabled' = $false; 'DisabledCount' = 0}})
    }

    try
    {
        while($listen)
        {
            # ensure sort by keeping two sets and comparing new to old then displaying old
            [void]$sortedEvents.Clear()
            $sortedEvents = $unsortedEvents.Clone()
            [void]$unsortedEvents.Clear()
            $color = $true

            foreach($machine in $machines)
            {
                if($machineList.$machine.Disabled -and $machineList.$machine.DisabledCount -lt $listenMachineDisabledCount)
                {
                    $machineList.$machine.DisabledCount++
                    log-info "disabled count: $($machine):$($machineList.$machine.DisabledCount)" -debugOnly
                    continue
                }
                elseif($machineList.$machine.Disabled)
                {
                    # check connectivity
                    if(!(test-path "\\$($machine)\admin$"))
                    {
                        log-info "unable to connect to machine: $($machine). leaving disabled"
                        log-info "$($machine) not accessible, skipping."
                        $machineList.$machine.DisabledCount = 0
                        continue
                    }
                    else
                    {
                        log-info "successfully connected to machine: $($machine). enabling..."                        
                        $machineList.$machine.Disabled = $false
                        $machineList.$machine.DisabledCount = 0
                    }
                }

                log-info "listen:checking machine $($machine) $([DateTime]::Now)" -debugOnly

                try
                {
                    $newEvents = dump-events -eventLogNames (New-Object Collections.ArrayList($global:machineRecords[$machine].Keys)) `
                                                                        -machine $machine `
                                                                        -eventStartTime $eventStartTime `
                                                                        -eventStopTime $eventStopTime `
                                                                        -eventLogLevelsQuery $eventLogLevelsQuery `
                                                                        -eventLogIdsQuery $eventLogIdsQuery

                    if($newEvents.Count -gt 0)
                    {
                        [void]$unsortedEvents.AddRange(@($newEvents | sort-object))
                    }
                }
                catch
                {
                    log-info "exception connecting to machine: $($machine). disabling..."
                    log-info "$($error)"
                    $machineList.$machine.Disabled = $true
                    $error.Clear()
                    continue
                }
            }

            if($unsortedEvents.Count -gt $maxSortCount)
            {
                # too many to sort, just display / save
                [void]$sortedEvents.AddRange($unsortedEvents)
                $unsortedEvents.Clear()
                log-info "Warning:listen: unsorted count too high, skipping sort" -debugOnly
                if($sortedEvents.Count -gt 0)
                {
                    foreach($sortedEvent in $sortedEvents)
                    {
                        log-info $sortedEvent -nocolor
                                                                        #write-host "------------------------------------------"
                    }
                }

                $sortedEvents.Clear()

                if($unsortedEvents.Count -gt 0)
                {
                    foreach($sortedEvent in $unsortedEvents)
                    {
                        log-info $sortedEvent -nocolor
                                                                        #write-host "------------------------------------------"
                    }
                }

                $unsortedEvents.Clear()
            }
            elseif($unsortedEvents.Count -gt 0 -and $sortedEvents.Count -gt 0)
            {
                $result = [DateTime]::MinValue
                $trace = $sortedEvents[$sortedEvents.Count -1]

                                                    # date and time are at start of string separated by commas.
                                                    # search for second comma splitting date and time from trace message to extract just date and time
                $traceDate = $trace.Substring(0,$trace.IndexOf(",",11))

                if([DateTime]::TryParse($traceDate,[ref] $result))
                {
                      $straceDate = $result
                }

                for($i = 0; $i -lt $unsortedEvents.Count; $i++)
                {
                    $trace = $unsortedEvents[$i]
                    $traceDate = $trace.Substring(0,$trace.IndexOf(",",11))

                    if([DateTime]::TryParse($traceDate,[ref] $result))
                    {
                          $utraceDate = $result
                    }

                    if($utraceDate -gt $straceDate)
                    {
                        log-info "moving trace to unsorted" -debugOnly
                        # move ones earlier than max of unsorted from sorted to unsorted keep timeline right
                        [void]$sortedEvents.Insert(0,$unsortedEvents[0])
                        [void]$unsortedEvents.RemoveAt(0)
                    }
                }
            }

            if($sortedEvents.Count -gt 0)
            {
                foreach($sortedEvent in $sortedEvents | Sort-Object)
                {
                    log-info $sortedEvent
                                                                    write-host "------------------------------------------"
                }
            }

            log-info "listen: unsorted count:$($unsortedEvents.Count) sorted count: $($sortedEvents.Count)" -debugOnly

                                    if($unsortedEvents.Count -gt 0)
                                    {
                                                    # query again without waiting to not get behind
                log-info "***listen:no sleep***" -debugOnly
                                    }
                                    else
                                    {
                                                    Start-Sleep -Milliseconds $listenSleepMs
                                    }
        }
    }
    catch
    {
        log-info "listen:exception: $($error)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function log-arguments()
{
    log-info "clearEventLogs:$($clearEventLogs)"
    log-info "clearEventLogsOnGather:$($clearEventLogsOnGather)"
    log-info "days:$($days)"
    log-info "debugScript:$($debugScript)"
    log-info "disableDebugLogs:$($disableDebugLogs)"
    log-info "displayMergedResults:$($displayMergedResults)"
    log-info "enableDebugLogs:$($enableDebugLogs)"
    log-info "eventDetails:$($eventDetails)"
    log-info "eventLogLevels:$($eventLogLevels -join ",")"
    log-info "eventLogIds:$($eventLogIds -join ",")"
    log-info "eventLogNamePattern:$($eventLogNamePattern)"
    log-info "eventLogPath:$($eventLogPath)"
    log-info "eventStartTime:$($eventStartTime)"
    log-info "eventStopTime:$($eventStopTime)"
    log-info "eventTracePattern:$($eventTracePattern)"
    log-info "getUpdate:$($getUpdate)"
    log-info "hours:$($hours)"
    log-info "listen:$($listen)"
    log-info "listEventLogs:$($listEventLogs)"
    log-info "machines:$($machines -join ",")"
    log-info "minutes:$($minutes)"
    log-info "months:$($months)"
    log-info "nodynamicpath:$($nodynamicpath)"
    log-info "rds:$($rds)"
    log-info "uploadDir:$($global:uploadDir)"
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data, [switch] $nocolor = $false, [switch] $debugOnly = $false)
{
    try
    {
        if($debugOnly -and !$debugScript)
        {
            return
        }

        $foregroundColor = "White"

        if(!$nocolor)
        {
            if($data.ToString().ToLower().Contains("error"))
            {
                $foregroundColor = "Red"
            }
            elseif($data.ToString().ToLower().Contains("fail"))
            {
                $foregroundColor = "Red"
            }
            elseif($data.ToString().ToLower().Contains("warning"))
            {
                $foregroundColor = "Yellow"
            }
            elseif($data.ToString().ToLower().Contains("exception"))
            {
                $foregroundColor = "Yellow"
            }
            elseif($data.ToString().ToLower().Contains("debug"))
            {
                $foregroundColor = "Gray"
            }
            elseif($data.ToString().ToLower().Contains("analytic"))
            {
                $foregroundColor = "Gray"
            }
            elseif($data.ToString().ToLower().Contains("disconnected"))
            {
                $foregroundColor = "DarkYellow"
            }
            elseif($data.ToString().ToLower().Contains("information"))
            {
                $foregroundColor = "Green"
            }
        }

        Write-Host $data -ForegroundColor $foregroundColor
        out-file -Append -InputObject "$([DateTime]::Now.ToString())::$([Diagnostics.Process]::GetCurrentProcess().ID)::$($data)" -FilePath $logFile
    }
    catch {}
}

# ----------------------------------------------------------------------------------------------------------------
function merge-files()
{
    # run logmerge on all files
    $uDir = $global:uploadDir

    if(![IO.File]::Exists("$($logmerge)"))
    {
                    return 
    }
                
    Invoke-Expression -Command "$($logmerge) `"$($uDir)`" `"*.csv`" `"$($uDir)\events-all.csv`""

    if($displayMergedResults -and [IO.File]::Exists("$($uDir)\events-all.csv"))
    {
        & "$($uDir)\events-all.csv"
    }

    
    # run logmerge on individual machines if more than one
    if($machines.Count -gt 1)
    {
        foreach($machine in $machines)
        {
            log-info "running $($logMerge)"

                                    Invoke-Expression -Command  "$($logmerge) `"$($uDir)`" `"*.csv`" `"$($uDir)\events-$($machine)-all.csv`"" 

            if($displayMergedResults -and [IO.File]::Exists("$($uDir)\events-$($machine)-all.csv"))
            {
                & "$($uDir)\events-$($machine)-all.csv"
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function process-eventLogs( $machines, $eventStartTime, $eventStopTime, $eventLogLevelsQuery, $eventLogIdsQuery )
{
    $retval = $true
    $ret = $null
    $baseDir = $global:uploadDir

    foreach($machine in $machines)
    {
        # check connectivity
        if(!(test-path "\\$($machine)\admin$"))
        {
            log-info "$($machine) not accessible, skipping."
            continue
        }

        # filter log names
        $filteredLogs = filter-eventLogs -eventLogPattern $global:eventLogNameSearchPattern -machine $machine -eventLogPath $eventLogPath

        if(!$global:eventLogFiles)
        {
            # enable / disable eventlog
            $ret = enable-logs -eventLogNames $filteredLogs -machine $machine
        }

        # create machine list
        $global:machineRecords.Add($machine,@{})

        # create eventlog list for machine
        foreach($eventLogName in $filteredLogs)
        {
            ($global:machineRecords[$machine]).Add($eventLogName,0)
        }

        # export all events from eventlogs
        if($clearEventLogs -or $enableDebugLogs -or $disableDebugLogs -or $listEventLogs)
        {
            $retval = $false
        }
        else
        {
            # check upload dir
            if(!$global:eventLogFiles -and !$nodynamicpath)
            {
                $global:uploadDir = "$($baseDir)\$($startTime)\$($machine)"
            }
            
            log-info "upload dir:$($global:uploadDir)"

            if(!(test-path $global:uploadDir))
            {
                $ret = New-Item -Type Directory -Path $global:uploadDir
            }

            if($listen)
            {
                log-info "listening for events on $($machine)"
            }
            else
            {
                log-info "dumping events on $($machine)"
            }

            $ret = dump-events -eventLogNames (New-Object Collections.ArrayList($global:machineRecords[$machine].Keys)) `
                                                                -machine $machine `
                                                                -eventStartTime $eventStartTime `
                                                                -eventStopTime $eventStopTime `
                                                                -eventLogLevelsQuery $eventLogLevelsQuery `
                                                                -eventLogIdsQuery $eventLogIdsQuery
        }
    }

    if($listen)
    {
        log-info "listening for events from machines:"

        foreach($machine in $machines)
        {
            log-info "`t$($machine)" -nocolor
        }

        listen-forEvents
    }

    $global:uploadDir = $baseDir
    return $retval
}

# ----------------------------------------------------------------------------------------------------------------
function process-machines( $machines, $eventStartTime, $eventStopTime, $eventLogLevelsQuery, $eventLogIdsQuery )
{
    # process all event logs on all machines
    if(process-eventLogs -machines $machines `
        -eventStartTime $eventStartTime `
        -eventStopTime $eventStopTime `
        -eventLogLevelsQuery $eventLogLevelQueryString `
        -eventLogIdsQuery $eventLogIdQueryString)
    {
        log-info "jobs count:$($global:jobs.Count)"
        $count = 0
        # Wait for all jobs to complete
        if($global:jobs -ne @())
        {
            while(get-job)
            {
                foreach($job in get-job)
                {
                    Receive-Job -Job $job

                    if($job.State -ieq 'Completed')
                    {
                        write-host ("$([DateTime]::Now) job completed. job name: $($job.Name) job id:$($job.Id) job state:$($job.State)")
                        if(![string]::IsNullOrEmpty($job.Error))
                        {
                            write-host "job error:$($job.Error) job status:$($job.StatusMessage)"
                        }

                        Remove-Job -Job $job -Force
                        $global:jobs.Remove($job)
                    }
                }
                foreach($job in $global:jobs)
                {
                    if($count -eq 30)
                    {
                        write-host ("$([DateTime]::Now) job name: $($job.Name) job id:$($job.Id) job state:$($job.State)") 
                        if(![string]::IsNullOrEmpty($job.Error))
                        {
                            write-host "job error:$($job.Error) job status:$($job.StatusMessage)"
                        }

                        $count = 0
                    }
                }

                $count++
                Start-Sleep -Milliseconds 1000
            }
        }

        merge-files
   }
}

# ----------------------------------------------------------------------------------------------------------------
function remove-jobs($silent)
{
    try
    {
        if((get-job).Count -gt 0)
        {
            if(!$silent -and !(Read-Host -Prompt "delete existing jobs?[y|n]:") -like "y")
            {
                return
            }

            foreach($job in get-job)
            {
                $job.StopJob()
                Remove-Job $job
            }
        }
    }
    catch
    {
        write-host $Error
        $error.Clear()
    }
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    log-info "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
       log-info "please restart script as administrator. exiting..."
       exit 1
   }
    log-info "running as admin"
}

# ----------------------------------------------------------------------------------------------------------------
function set-uploadDir()
{

    # set uploaddir
    get-workingDirectory

    # if parsing a path for evtx files to convert and no upload path is given then use path of evtx
    if([string]::IsNullOrEmpty($global:uploadDir) -and $global:eventLogFiles)
    {
        if([IO.Directory]::Exists($eventLogPath))
        {
            $global:uploadDir = $eventLogPath
        }
        else
        {
            $global:uploadDir = [IO.Path]::GetDirectoryName($eventLogPath)
        }
    }
    elseif([string]::IsNullOrEmpty($global:uploadDir))
    {
        $global:uploadDir = "$(get-location)\gather"
    }

    # make sure directory exists
    if(!(test-path $global:uploadDir))
    {
        [IO.Directory]::CreateDirectory($global:uploadDir)
    }

    log-info "upload dir: $($global:uploadDir)"
}

# ----------------------------------------------------------------------------------------------------------------

main

