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

    ** Copyright (c) Microsoft Corporation. All rights reserved - 2016.
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

   File Name  : event-log-manager.ps1
   Author     : jagilber
   Version    : 160410 switched to log-merge.ps1
   History    : 160329 original

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
    Example command to query all event logs:

.PARAMETER clearEventLogs
    If specified, will clear all event logs matching 'eventLogNamePattern'

.PARAMETER clearEventLogsOnGather
    If specified, will clear all event logs matching 'eventLogNamePattern' after eventlogs have been gathered.

.PARAMETER days
    If specified, is the number of days to query from the event logs. The number specified is a positive number

.PARAMETER disableDebugLogs
    If specified, will disable the 'analytic and debug' event logs matching 'eventLogNamePattern'

.PARAMETER enableDebugLogs
    If specified, will enable the 'analytic and debug' event logs matching 'eventLogNamePattern'
    NOTE: at end of troubleshooting, remember to 'disableEventLogs' as there is disk and cpu overhead for debug logs
    WARNING: enabling too many debug eventlogs can make system non responsive and may make machine unbootable!
    Only enable specific debug logs needed and only while troubleshooting.

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

.PARAMETER eventStartTime
    If specified, is a time and / or date string that can be used as a starting time to query event logs
    If not specified, the default is for today only

.PARAMETER eventStopTime
    If specified, is a time and / or date string that can be used as a stopping time to query event logs
    If not specified, the default is for current time

.PARAMETER eventTracePattern
    If specified, is a string or regex pattern to specify event log traces to query.
    If not specified, all traces matching other criteria are displayed

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

.PARAMETER rds
    If specified, will set the default 'eventLogNamePattern' to "RemoteApp|RemoteDesktop|Terminal" if value not populated
    If specified, will try to enumerate active connection broker cmdlet get-rdservers. If successful, will prompt to optionally enable gathering event logs from entire deployment
    If specified, and -enableDebugLogs is specified, rds specific debug flags will be enabled
    If specified, and -disableDebugLogs is specified, rds specific debug flags will be disabled

.PARAMETER uploadDir
    The directory where all files will be created.
    The default is c:\upload

#>
Param(
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to clear events")]
    [switch] $clearEventLogs,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to clear events after gather")]
    [switch] $clearEventLogsOnGather,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter days")]
    [int] $days = 0,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enable to debug script")]
    [switch] $debugScript = $false,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter `$true to disable debug event logs")]
    [switch] $disableDebugLogs,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter `$true to enable debug event logs")]
    [switch] $enableDebugLogs,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter comma separated list of event log levels Critical,Error,Warning,Information,Verbose")]
    [string[]] $eventLogLevels = @("critical","error","warning","information","verbose"),
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter comma separated list of event log Id")]
    [int[]] $eventLogIds = @(),
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter regex or string pattern for event log name match")]
    [string] $eventLogNamePattern = "",
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter start time / date (the default is events for today)")]
    [string] $eventStartTime,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter stop time / date (the default is current time)")]
    [string] $eventStopTime,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter regex or string pattern for event log trace to match")]
    [string] $eventTracePattern = "",
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter hours")]
    [int] $hours = 0,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Listen to event logs either all or by -eventLogNamePattern")]
    [switch] $listen,
    [parameter(Position=1,Mandatory=$false,HelpMessage="List event logs either all or by -eventLogNamePattern")]
    [switch] $listEventLogs,
	[parameter(Position=1,Mandatory=$false,HelpMessage="Enter comma separated list of machine names")]
    [string[]] $machines = @(),
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter minutes")]
    [int] $minutes = 0,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter months")]
    [int] $months = 0,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter minutes")]
    [switch] $rds,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter path for upload directory")]
    [string] $uploadDir = "c:\upload",
    [parameter(Position=1,Mandatory=$false,HelpMessage="Display merged event results in viewer. Requires log-merge.ps1")]
    [switch] $displayMergedResults
    )

cls
$appendOutputFiles = $false
$debugLogsMax = 100
$ErrorActionPreference = "Continue"
$eventLogLevelQueryString = $null
$eventLogLevelIdString = $null
$global:jobs = New-Object Collections.ArrayList
$global:baseDir = $uploadDir
$debugLogsEnabled = New-Object Collections.ArrayList
$global:machineRecords = @{}
$global:originalLocation = get-location
$global:eventLogNameSearchPattern = $eventLogNamePattern
$jobThrottle = 10
$listenSleepMs = 1000
$logFile = "event-log-manager.log"
$logMerge = "$($global:originalLocation)\log-merge.ps1"
$maxSortCount = 100
$silent = $true
$startTime = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()

    # clean up old jobs
    remove-jobs $silent

    # some functions require admin
    if($clearEventLogs -or $enableDebugLogs)
    {
        runas-admin
    }

    # make sure directory exists
    if(!(test-path $uploadDir))
    {
        [IO.Directory]::CreateDirectory($uploadDir)
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
    $eventStartTime = configure-startTime -eventStartTime $eventStartTime -eventStopTime $eventStopTime -months $months -days $days -hours $hours -minutes $minutes
    $eventStopTime = configure-stopTime -eventStarTime $origStartTime -eventStopTime $eventStopTime -months $months -days $days -hours $hours -minutes $minutes

    # process all event logs on all machines
    if(process-eventLogs -machines $machines -eventStartTime $eventStartTime -eventStopTime $eventStopTime -eventLogLevelsQuery $eventLogLevelQueryString -eventLogIdsQuery $eventLogIdQueryString)
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
                        write-host ("$([DateTime]::Now) job completed. job name: $($job.Name) job id:$($job.Id) job state:$($job.State) job error:$($job.Error) job status:$($job.StatusMessage)")
                        Remove-Job -Job $job -Force
                        $global:jobs.Remove($job)
                    }
                }
                foreach($job in $global:jobs)
                {
                    if($count -eq 30)
                    {
                        write-host ("$([DateTime]::Now) job name: $($job.Name) job id:$($job.Id) job state:$($job.State) job error:$($job.Error) job status:$($job.StatusMessage)") -
                        $count = 0
                    }
                }

                $count++
                Start-Sleep -Milliseconds 1000
            }
        }

        merge-files
   }

   log-info "finished"
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
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
       log-info "please restart script as administrator. exiting..."
       exit 1
    }
}

# ----------------------------------------------------------------------------------------------------------------
function configure-rds($machines,$eventLogNamePattern)
{
    log-info "setting up for rds environment"
    $global:eventLogNameSearchPattern = "$($global:eventLogNameSearchPattern)|RDMS|RemoteApp|RemoteDesktop|Terminal|VHDMP|^System$|^Application$|^Security$|User-Profile-Service" #CAPI
    
    if(!(get-service -DisplayName 'Remote Desktop Connection Broker' -ErrorAction SilentlyContinue))
    {
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
function configure-startTime( $eventStartTime, $eventStopTime, $months, $hours, $days, $minutes )
{
    [DateTime] $time = new-object DateTime
    [void][DateTime]::TryParse($eventStartTime,[ref] $time)

    if($time -eq [DateTime]::MinValue -and [string]::IsNullOrEmpty($eventStopTime) -and ($months + $hours + $days + $minutes -eq 0))
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
function process-eventLogs( $machines, $eventStartTime, $eventStopTime, $eventLogLevelsQuery, $eventLogIdsQuery )
{
    [bool] $retval = $true
    $ret = $null

    foreach($machine in $machines)
    {
        # check connectivity
        if(!(test-path "\\$($machine)\admin$"))
        {
            log-info "$($machine) not accessible, skipping."
            continue
        }

        log-info "Current upload directory $($uploadDir)"

        # filter log names
        $filteredLogs = filter-eventLogs -eventLogPattern $global:eventLogNameSearchPattern -machine $machine

        # enable / disable eventlog
        $ret = enable-logs -eventLogNames $filteredLogs -machine $machine

        # create machine list
        $global:machineRecords.Add($machine,@{})

        # create eventlog list for machine
        foreach($eventLogName in $filteredLogs)
        {
            ($global:machineRecords[$machine]).Add($eventLogName,0)
        }

        # export all events from eventlogs
        if(!$clearEventLogs -and !$enableDebugLogs -and !$disableDebugLogs -and !$listEventLogs)
        {
           # check upload dir
            $uploadDir = "$($global:baseDir)\$($startTime)\$($machine)"

            if(!(test-path $uploadDir))
            {
                $ret = New-Item -Type Directory -Path $uploadDir
            }

            if($listen)
            {
                log-info "listening for events on $($machine)"
            }
            else
            {
                log-info "dumping events on $($machine)"
            }

            $ret = dump-events -eventLogNames $filteredLogs `
				-machine $machine `
				-eventStartTime $eventStartTime `
				-eventStopTime $eventStopTime `
				-eventLogLevelsQuery $eventLogLevelsQuery `
				-eventLogIdsQuery $eventLogIdsQuery
        }
        else
        {
            $retval = $false
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

    return $retval
}

# ----------------------------------------------------------------------------------------------------------------
function filter-eventLogs($eventLogPattern, $machine)
{
    $filteredEventLogs = New-Object Collections.ArrayList
    $session = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)
    $eventLogNames = $session.GetLogNames()
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
function enable-logs($eventLogNames, $machine)
{
    log-info "enabling logs on $($machine)"
    [Text.StringBuilder] $sb = new-object Text.StringBuilder
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
            else
            {
                $queryString = "<QueryList>
                    <Query Id=`"0`" Path=`"$($eventLogName)`">
                    <Select Path=`"$($eventLogName)`">*[System[$($eventQuery)" `
                        + "TimeCreated[@SystemTime &gt;=`'$($eventStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`' " `
                        + "and @SystemTime &lt;=`'$($eventStopTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`']]]</Select>
                    </Query>
                    </QueryList>"
            }
        }
        else
        {
            $queryString = "<QueryList>
                <Query Id=`"0`" Path=`"$($eventLogName)`">
                <Select Path=`"$($eventLogName)`">*[System[$($eventQuery)" `
					+ "TimeCreated[@SystemTime &gt;=`'$($eventStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`' " `
					+ "and @SystemTime &lt;=`'$($eventStopTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:sszz"))`']]]</Select>
                </Query>
                </QueryList>"
        }

        try
        {
            # peek to see if any records, if so start job
            $pquery = New-Object Diagnostics.Eventing.Reader.EventLogQuery ($eventLogName, [Diagnostics.Eventing.Reader.PathType]::LogName, $queryString)
            $pquery.Session = $psession
            $preader = New-Object Diagnostics.Eventing.Reader.EventLogReader $pquery

            $event = $preader.ReadEvent()
            if($event -eq $null)
            {
                # write-host "skipping eventlog $($eventLogName) as there are 0 events"
                continue
            }

            $recordid = [Math]::Max($recordid,$event.RecordId)
            log-info "dump-events:machine: $($machine) event log name: $eventLogName index: $($recordid)" -debugOnly
            ($global:machineRecords[$machine])[$eventLogName] = $recordid

            # create csv file name
            $outputCsv = (("$($machine)-$($eventLogName).csv").Replace("/","-").Replace(" ", "-"))
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
            while($true)
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
                        $description = [string]::Empty
                    }
                    else
                    {
                        $description = $description.Replace("`r`n",";")
                    }

                    $outputEntry = (("$($event.TimeCreated.ToString("MM/dd/yyyy,hh:mm:ss.ffffff tt"))," `
						+ "$($machine),$($event.Id),$($event.LevelDisplayName),$($event.ProviderName),$($event.ProcessId)," `
						+ "$($event.ThreadId),$($description)"))

					if([string]::IsNullOrEmpty($eventTracePattern) -or
						(![string]::IsNullOrEmpty($eventTracePattern) -and
							[regex]::IsMatch($outputEntry,$eventTracePattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
								[Text.RegularExpressions.RegexOptions]::Singleline)))
                    {
                        #write-host $outputEntry
                        #write-host "------------------------------------------"
                        Out-File -Append -FilePath "$($uploadDir)\$($outputCsv)" -InputObject $outputEntry
                        [void]$newEvents.Add($outputEntry)
                    }
                }
                else
                {
                    log-info "empty event, skipping..."
                }

                ($global:machineRecords[$machine])[$eventLogName] = [Math]::Max(($global:machineRecords[$machine])[$eventLogName],$event.RecordId)
                # write-host "while $($eventLogName):$($recordid[$eventLogName])"
                $event = $preader.ReadEvent()
            }
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
                    $uploadDir,
                    $machine,
                    $eventStartTime,
                    $eventStopTime,
                    $eventLogLevelsQuery,
                    $eventLogIdsQuery,
                    $clearEventLogsOnGather,
                    $queryString,
                    $eventTracePattern)

                try
                {
                    # use .net to see if any events as it doesnt throw exception
                    $session = New-Object Diagnostics.Eventing.Reader.EventLogSession ($machine)
                    $query = New-Object Diagnostics.Eventing.Reader.EventLogQuery ($eventLogName, [Diagnostics.Eventing.Reader.PathType]::LogName, $queryString)
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

                # create csv file name
                $outputCsv = (("$($machine)-$($eventLogName).csv").Replace("/","-").Replace(" ", "-"))
                if(!$appendOutputFiles -and (test-path $outputCsv))
                {
                    write-host "removing existing file: $($outputCsv)"
                    Remove-Item -Path $outputCsv -Force
                }

                while($true)
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
                            $description = [string]::Empty
                        }
                        else
                        {
                            $description = $description.Replace("`r`n",";")
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
                            
                            Out-File -Append -FilePath "$($uploadDir)\$($outputCsv)" -InputObject $outputEntry
                        }
                    }
                    else
                    {
                        write-host "empty event, skipping..."
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
                $logFile,$uploadDir,
                $machine,
                $eventStartTime,
                $eventStopTime,
                $eventLogLevelsQuery,
                $eventLogIdsQuery,
                $clearEventLogsOnGather,
                $queryString,
                $eventTracePattern)

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
function listen-forEvents()
{
	$unsortedEvents = New-Object Collections.ArrayList
    $sortedEvents = New-Object Collections.ArrayList
    $newEvents = New-Object Collections.ArrayList

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
                log-info "listen:checking machine $($machine) $([DateTime]::Now)" -debugOnly

                $newEvents = dump-events -eventLogNames $filteredLogs `
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
                $trace = $trace.Substring(0,$trace.IndexOf(",",11))

                if([DateTime]::TryParse($traceDate,[ref] $result))
                {
                      $straceDate = $result
                }

                for($i = 0; $i -lt $unsortedEvents.Count; $i++)
                {
                    #$pattern = "MM/dd/yyy,hh:mm:ss.ffffff zz"
                    $trace = $unsortedEvents[$i]
                    $trace = $trace.Substring(0,$trace.IndexOf(",",11))

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
			    #Start-Sleep -Milliseconds 10
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
function log-info($data, [switch] $nocolor = $false, [switch] $debugOnly = $false)
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
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
function merge-files()
{
    # run logmerge on all files
    $uploadDir = "$($global:baseDir)\$($startTime)"

	if(![IO.File]::Exists("$($logmerge)"))
	{
		return 
	}
	
	Invoke-Expression -Command "$($logmerge) $($uploadDir) *.csv $($uploadDir)\events-all.csv" 
    if($displayMergedResults -and [IO.File]::Exists("$($uploadDir)\events-all.csv"))
    {
        & "$($uploadDir)\events-all.csv"
    }

    # run logmerge on individual machines
    foreach($machine in $machines)
    {
        log-info "running $($logMerge)"

        $uploadDir = "$($global:baseDir)\$($startTime)\$($machine)"
		Invoke-Expression -Command  "$($logmerge) $($uploadDir) *.csv $($uploadDir)\events-$($machine)-all.csv" 

        if($displayMergedResults -and [IO.File]::Exists("$($uploadDir)\events-$($machine)-all.csv"))
        {
            & "$($uploadDir)\events-$($machine)-all.csv"
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------

main
