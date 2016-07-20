<#  
.SYNOPSIS
  
  
    powershell script to enable / disable commands remotely across multiple machines

.DESCRIPTION  
    Set-ExecutionPolicy Bypass -Force

    powershell script to enable / disable commands remotely across multiple machines

    
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
   File Name  : remote-manager.ps1  
   Author     : jagilber
   Version    : 150910
                - sub dir search
                - external
                - job fixes. restart
                
   History    : 150826 original

.EXAMPLE  
    .\remote-manager.ps1 -start
    used to start on local machine

.EXAMPLE  
    .\remote-manager.ps1 -stop -machine dc01
    used to stop on machine dc01

.PARAMETER machines
    comma seperated list of machines to deploy utilities to
    if not specified, local machine will be used

.PARAMETER minutes
    number of minutes back from current time to gather events from event logs for
    if not specified 60 minutes will be used

.PARAMETER start
    switch -start to start utilities

.PARAMETER stop
    switch -stop to stop utilities

    
 
#>  
Param(
    [parameter(Position=0,Mandatory=$false,HelpMessage="Use to start")]
    [switch] $start,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Use to stop")]
    [switch] $stop,
    [parameter(Position=2,Mandatory=$false,HelpMessage="Enter comma separated list of machine names")]
    [string[]] $machines = @($env:COMPUTERNAME),
    [parameter(Position=3,Mandatory=$false,HelpMessage="Enter number of minutes from now for event log gathering. Default is 60")]
    [string[]] $minutes = 60,
    [parameter(Position=4,Mandatory=$false,HelpMessage="Enter path for upload directory")]
    [string] $gatherDir = ""
    )
 
cls

$ErrorActionPreference = "SilentlyContinue" #"Stop"
$logFile = "remote-manager.log"
$global:jobs = @()

$jobThrottle = 10

$nameStamp = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
if([string]::IsNullOrEmpty($gatherDir)) 
{ 
    $gatherDir = "$(get-Location)\gather\$($nameStamp)" 
}
ELSE
{
    $gatherdir = "$($gatherdir)\$($nameStamp)"
}


##################
#                #
# START COMMANDS #
#                #
##################

[System.Collections.ArrayList] $global:startCommands = new-object System.Collections.ArrayList

$global:startCommands.Add(@{"rds-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $false;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file logman-wrapper.ps1 -rds -action deploy -configurationfolder c:\windows\temp\2k12-configs-all-rds";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "$(get-Location)\2k12-rds-tracing";
    'destfiles' = "admin`$\temp";
    'searchSubDir' = $true
}})

$global:startCommands.Add(@{"network-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $false;
    'command' = "netsh.exe";
    'arguments' = "trace start capture=yes tracefile=c:\windows\temp\net.etl";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "";
    'destfiles' = "";
    'searchSubDir' = $false
}})

#$global:startCommands.Add(@{"xperf-tracing" = @{ 
#    'useWmi' = $true; 
#    'wait' = $false;
#    'command' = "cmd.exe";
#    'arguments' = "/c C:\windows\temp\xperf.mod.mgr.bat start wait";
#    'workingDir' = "c:\windows\temp";
#    'sourceFiles' = "$(get-Location)\2k8r2-x64-xperf";
#    'destfiles' = "admin`$\temp";
#    'searchSubDir' = $true
#}})

$global:startCommands.Add(@{"perfmon-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $false;
    'command' = "cmd.exe";
    'arguments' = "/c C:\windows\temp\perfmon.mod.mgr.bat start";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "$(get-Location)\perfmon.mod.mgr.bat";
    'destfiles' = "admin`$\temp";
    'searchSubDir' = $false
}})


$global:startCommands.Add(@{"event-filter-export" = @{ 
    'useWmi' = $true; 
    'wait' = $false;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-filter-export.ps1 -clearEventLogs -enableDebugLogs -rds";
#    'command' = "powershell.exe";
#    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-filter-export.ps1 -rds";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "$(get-Location)\events-export";
    'destfiles' = "admin`$\temp";
    'searchSubDir' = $true
}})

$global:startCommands.Add(@{"procmon-tracing" = @{ 
    'useWmi' = $false; 
    'wait' = $false;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-task-procmon.ps1";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "$(get-Location)\procmon-tracing";
    'destfiles' = "admin`$\temp";
    'searchSubDir' = $true
}})


#################
#               #
# STOP COMMANDS #
#               #
#################

[System.Collections.ArrayList]$global:stopCommands = New-Object System.Collections.ArrayList

$global:stopCommands.Add(@{"procmon-tracing" = @{ 
    'useWmi' = $false; 
    'wait' = $true;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-task-procmon.ps1 -terminate";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "admin`$\temp\*.pml";
    'destfiles' = $gatherDir;
    'searchSubDir' = $false
}})

$global:stopCommands.Add(@{"rds-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $true;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file logman-wrapper.ps1 -rds -action undeploy -configurationfolder c:\windows\temp\2k12-configs-all-rds";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "admin`$\temp\gather";
    'destfiles' = $gatherDir;
    'searchSubDir' = $true
}})

$global:stopCommands.Add(@{"network-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $true;
    'command' = "netsh.exe";
    'arguments' = "trace stop";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "admin`$\temp\net.etl";
    'destfiles' = $gatherDir;
    'searchSubDir' = $false
}})

$global:stopCommands.Add(@{"event-filter-export" = @{ 
    'useWmi' = $true; 
    'wait' = $true;
    'command' = "powershell.exe";
 #   'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-filter-export.ps1 -clearEventLogsOnGather -rds -uploadDir c:\windows\temp\events";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-filter-export.ps1 -minutes $($minutes) -rds -uploadDir c:\windows\temp\events";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "admin`$\temp\events\*.csv";
    'destfiles' = $gatherDir;
    'searchSubDir' = $true
}})

$global:stopCommands.Add(@{"event-filter-export-cleanup" = @{ 
    'useWmi' = $true; 
    'wait' = $false;
    'command' = "powershell.exe";
    'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-filter-export.ps1 -disableDebugLogs -rds";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "";
    'destfiles' = "";
    'searchSubDir' = $false
}})


#$global:stopCommands.Add(@{"xperf-tracing" = @{ 
#    'useWmi' = $true; 
#    'wait' = $true;
#    'command' = "cmd.exe";
#    'arguments' = "/c C:\windows\temp\xperf.mod.mgr.bat stop wait";
#    'workingDir' = "c:\windows\temp";
#    'sourceFiles' = "admin`$\temp\*merge.etl";
#    'destfiles' = $gatherDir;
#    'searchSubDir' = $false
#}})

$global:stopCommands.Add(@{"perfmon-tracing" = @{ 
    'useWmi' = $true; 
    'wait' = $true;
    'command' = "cmd.exe";
    'arguments' = "/c C:\windows\temp\perfmon.mod.mgr.bat stop";
    'workingDir' = "c:\windows\temp";
    'sourceFiles' = "admin`$\temp\*.blg";
    'destfiles' = $gatherDir;
    'searchSubDir' = $false
}})

#############
#           #
# FUNCTIONS #
#           #
#############


# ----------------------------------------------------------------------------------------------------------------
function main()
{
    try
    {
    $Error.Clear()
    runas-admin

    if($start -and $stop)
    {
        log-info "argument has to be start or stop, not both, exiting"
        return
    }

    if(!$start -and !$stop)
    {
        log-info "argument has to be start or stop, none specified, exiting"
        return
    }

    clean-jobs

    $workingDir = Get-Location
 
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


    foreach($machine in $machines)
    {
        if(!(test-path "\\$($machine)\admin`$"))
        {
            log-info "machine $($machine) not accessible. skipping"
            continue
        }

        log-info "# ---------------------------------------------------------------"
        if($start)
        {
            log-info "running start commands for $($machine)"
            process-commands -commands $global:startCommands -machine $machine
        }
        elseif($stop)
        {
            log-info "running stop commands for machine $($machine)"
            process-commands -commands $global:stopCommands -machine $machine

        }

    } 

  
    wait-forJobs
    

    log-info "finished"
    tree /a /f $($gatherDir)

    }
    catch
    {
        if(get-job)
        {
            clean-jobs
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function clean-jobs()
{
    if(get-job)
    {
        [string] $ret = read-host -Prompt "There are existing jobs, do you want to clear?[y:n]" 
        if($ret -ieq "y")
        {
            get-job 

            while(get-job)
            {
                get-job | remove-job -Force
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function wait-forJobs()
{
    log-info "jobs count:$($global:jobs.Length)"
    # Wait for all jobs to complete
    $waiting = $true
    $failedJobs = New-Object System.Collections.ArrayList

    if($global:jobs -ne @())
    {
        while($waiting)
        {
            #Wait-Job -Job $global:jobs
            $waiting = $false
            foreach($job in Get-Job)
            {

                log-info "waiting on $($job.Name):$($job.State)"
                switch ($job.State)
                {
                    'Stopping' { $waiting = $true }
                    'NotStarted' { $waiting = $true }
                    'Blocked' { $waiting = $true }
                    'Running' { $waiting = $true }
                    
                }

                if($stop -and $job.State -ieq 'Completed')
                {
                    # gather files
                    foreach($machine in $machines)
                    {
                        foreach($command in $global:stopCommands)
                        {
                            if($job.Name -ieq "$($machine)-$($command.Values.GetHashCode())")
                            {
                                log-info "job completed, copying files $($machine)-$($command.Values.arguments)"
                                gather-files -command $command -machine $machine
                            }
                        }
                    }

                    # todo read start commands to determine list of script / data files to remove from remote machine for cleanup
                    # load start jobs matching same name as stop jobs to find 'source' files
                    # convert 'source' files to 'dest' file cleanup

                }
                
                # restart failed jobs
                if($job.State -ieq 'Failed')
                {
                    Receive-Job -Job $job
                    if(!$failedJobs.Contains($job))
                    {
                        $failedJobs.Add($job)
                        log-info "** restarting failed job $($job.Name) **"
                        log-info "if you continue to see this message for same job, ctrl+c to break"
                        $job | fl *
                        $job = Start-Job -Name $job.Name -ScriptBlock { Invoke-Expression $args[0] } -ArgumentList $job.Command
                        $failedJobs.Add($job)
                    }
                    else
                    {
                        log-info "** JOB FAILED **"
                        Receive-Job -Job $job
                        Remove-Job -Job $job
                    }

                }

                # Getting the information back from the jobs
                if($job.State -ieq 'Completed')
                {
                    Receive-Job -Job $job
                    Remove-Job -Job $job
                }
    
            }
            
    
            foreach($job in $global:jobs)
            {
                if($job.State -ine 'Completed')
                {
                    log-info ("$($job.Name):$($job.State):$($job.Error):$((find-commandFromJob -jobName $job.Name).Keys)")
                    Receive-Job -Job $job 
                    log-info "# ---------------------------------------------------------------"
                }
            }

            
            Start-Sleep -Seconds 1
        }

       
    }
}

# ----------------------------------------------------------------------------------------------------------------
function gather-files($command, $machine)
{

    if(!$stop)
    {
        log-info "gather-files action not stop. returning"
        return
    }
    try
    {
        $subDirSearch = [IO.SearchOption]::TopDirectoryOnly

        if($command.Values.searchSubDir)
        {
            $subDirSearch = [IO.SearchOption]::AllDirectories
        }

        $copyFiles = @{}
        # directory, files, wildcard
        $sourceFiles  = "\\$($machine)\$($command.Values.sourcefiles)"
        log-info "gather-files searching $($sourceFiles)"

        if($sourceFiles.Contains("?") -or $sourceFiles.Contains("*"))
        {
            $sourceFilter = [IO.Path]::GetFileName($sourceFiles)
            $sourceFiles = [IO.Path]::GetDirectoryName($sourceFiles)
                
        }
        else
        {
            if([IO.Directory]::Exists($sourceFiles))
            {
                $sourceFilter = "*"
            }
            else
            {
                    
                #assume file
                $sourceFilter = [IO.Path]::GetFileName($sourceFiles)
                $sourceFiles = [IO.Path]::GetDirectoryName($sourceFiles)
            }

                
        }

        log-info "gather-files searching $($sourceFiles) for $($sourceFilter)"

        $files = [IO.Directory]::GetFiles($sourceFiles,$sourceFilter,$subDirSearch)

        # save in global list to copy at end of all job completion
        foreach($file in $files)
        {
           
            $copyFiles.Add($file, $file.Replace($sourceFiles,"$($command.Values.destfiles)\$($machine)"))
        }

        
        
        copy-files -files $copyFiles -delete $true
    }
    catch
    {
        log-info "gather-files :exception $($error)"
        $error.Clear()
    }
}

# ----------------------------------------------------------------------------------------------------------------
function process-commands($commands, [string] $machine)
{
    foreach($command in $commands)#.GetEnumerator()) 
    {
        
        deploy-files -command $command -machine $machine
        

        if([string]::IsNullOrEmpty($command.Values.command))
        {
            log-info "skipping empty command"
            continue
        }

        if($command.Values.useWmi)
        {
            run-wmiCommandJob -command $command -machine $machine
        }
        else
        {

            manage-scheduledTaskJob -wait $command.values.wait -machine $machine -taskInfo @{
                "taskname" = $command.Keys;
                "taskdescr" = $command.Keys;
                "taskcommand" = $command.Values.command;
                "taskdir" = $command.Values.workingDir;
                "taskarg" = $command.Values.arguments
            }
        }


    }
}

# ----------------------------------------------------------------------------------------------------------------
function deploy-files($command, $machine)
{
    if(!$start)
    {
        log-info "deploy-files action not start. returning"
        return
    }

    $isDir = $false

    try
    {
        $subDirSearch = [IO.SearchOption]::TopDirectoryOnly

        if($command.Values.searchSubDir)
        {
            $subDirSearch = [IO.SearchOption]::AllDirectories
        }

        
        $copyFiles = @{}

        $sourceFiles  = $command.Values.sourcefiles
        if([string]::IsNullOrEmpty($sourceFiles))
        {
            log-info "deploy-files: no source files. returning"
            return
        }

        log-info "deploy-files searching $($sourceFiles)"

        if($sourceFiles.Contains("?") -or $sourceFiles.Contains("*"))
        {
            $sourceFilter = [IO.Path]::GetFileName($sourceFiles)
            $sourceFiles = [IO.Path]::GetDirectoryName($sourceFiles)
                
        }
        else
        {
            if([IO.Directory]::Exists($sourceFiles))
            {
                $sourceFilter = "*"
                $isDir = $true
            }
            else
            {
                    
                #assume file
                $sourceFilter = [IO.Path]::GetFileName($sourceFiles)
                $sourceFiles = [IO.Path]::GetDirectoryName($sourceFiles)
            }

                
        }

        $files = [IO.Directory]::GetFiles($sourceFiles,$sourceFilter,$subDirSearch)

        foreach($file in $files)
        {
            $destFile = $null
            if(!$isDir)
            {
                $destFile = "\$([IO.Path]::GetFileName($file))"
            
            }

            $copyFiles.Add($file, $file.Replace($command.Values.sourcefiles,"\\$($machine)\$($command.Values.destfiles)$($destFile)"))

        }

        copy-files -files $copyFiles

    }
    catch
    {
        log-info "deploy-files error: $($error)"
        $error.Clear()
    }
}


# ----------------------------------------------------------------------------------------------------------------
function run-wmiCommandJob($command, $machine)
{

    $functions = {
        
        function log-info($data)
        {
            $data = "$([System.DateTime]::Now):$($data)`n"

            Write-Host $data
        }
    }

    #throttle
    While((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
    {
        Start-Sleep -Milliseconds 100
    }

    log-info "starting wmi job: $($machine)-$($command.Values.GetHashCode()) $($command.Keys)"

    $job = Start-Job -Name "$($machine)-$($command.Values.GetHashCode())" -InitializationScript $functions -ScriptBlock {
        param($command,$machine)

        try
        {
            $commandline = "$($command.Values.command) $($command.Values.arguments)"
            log-info "running wmi command: $($commandline)"
        
            $startup=[wmiclass]"Win32_ProcessStartup"
            $startup.Properties['ShowWindow'].value=$False
            $ret = Invoke-WmiMethod -ComputerName $machine -Class Win32_Process -Name Create -Impersonation Impersonate -ArgumentList @($commandline, $command.Values.workingDir, $startup)

            if($ret.ReturnValue -ne 0 -or $ret.ProcessId -eq 0)
            {
                log-info "Error:run-wmiCommand: $($ret.ReturnValue)"
                return
            }

            if($command.Values.wait)
            {
                while($true)
                {
                    log-info "waiting on process: $($ret.ProcessId)"
                    if((Get-WmiObject -ComputerName $machine -Class Win32_Process -Filter "ProcessID = '$($ret.ProcessId)'"))
                    {
                        
                        Start-Sleep -Seconds 1
                    }
                    else
                    {
                        log-info "no process"
                        break
                    }
                }
            }
        
        
        }
        catch
        {
            log-info "Exception:run-wmiCommand: $($Error)"
            $Error.Clear()
        }
    } -ArgumentList ($command,$machine)

    
    $global:jobs = $global:jobs + $job
}



# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    if([regex]::IsMatch($data.ToLower(),"error|exception|fail|warning"))
    {
        write-host $data -foregroundcolor Yellow
    }
    else
    {
        Write-Host $data
    }

    $counter = 0
    while(!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            $ret = out-file -Append -InputObject $data -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 50
            $error.Clear()
            $counter++
        }
    }
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
 
# ----------------------------------------------------------------------------------------------------------------
function is-fileLocked([string] $file)
{
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false)
    {
        log-info "File does not exist:$($file)"
        return $false
    }
  
    try
    {
	    $fileStream = $fileInfo.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
	    if ($fileStream)
	    {
            $fileStream.Close()
	    }
 
	    log-info "File is NOT locked:$($file)"
        return $false
    }
    catch
    {
        # file is locked by a process.
        log-info "File is locked:$($file)"
        return $true
    }
}

# ----------------------------------------------------------------------------------------------------------------
function copy-files([hashtable] $files, [bool] $delete = $false)
{
    $resultFiles = @()
 
    foreach($kvp in $files.GetEnumerator())
    {
        if($kvp -eq $null)
        {
            continue
        }
 
        $destinationFile = $kvp.Value
        $sourceFile = $kvp.Key
 
        if(!(Test-Path $sourceFile))
        {
            log-info "Warning:Copying File:No source. skipping:$($sourceFile)"
            continue
        }
 
        $count = 0
 
        while($count -lt 60)
        {
            try
            {

                # copy only if newer
                
                if([IO.File]::Exists($destinationFile))
                {
                    [IO.FileInfo] $dfileInfo = new-object IO.FileInfo ($destinationFile)    
                    [IO.FileInfo] $sfileInfo = new-object IO.FileInfo ($sourceFile)    
                    if($dfileInfo.LastWriteTimeUtc -eq $sfileInfo.LastWriteTimeUtc)
                    {
                        log-info "skipping file copy $($destinationFile)"
                        break
                    }
                }
 
                if(is-fileLocked $sourceFile)
                {
                    start-sleep -Seconds 1
	                $count++          
				    
                    if($count -lt 60)          
				    {
					    Continue
				    }
                }
                
                if(![IO.Directory]::Exists([IO.Path]::GetDirectoryName($destinationFile)))
                {
                    log-info "creating directory:$([IO.Path]::GetDirectoryName($destinationFile))"
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationFile))
                }
                
                log-info "Copying File:$($sourceFile) to $($destinationFile)"
                [IO.File]::Copy($sourceFile, $destinationFile, $true)
            
                if($delete)
                {
                    log-info "Deleting File:$($sourceFile)"
                    [IO.File]::Delete($sourceFile)
                }
 
                # add file if exists local to return array for further processing
                $resultFiles += $destinationFile
 
                break
            }
            catch
            {
                log-info "Exception:Copying File:$($sourceFile) to $($destinationFile): $($Error)"
                $Error.Clear()
                $count++
                start-sleep -Seconds 1
            }
        }
    }
 
    return $resultFiles
}

# ----------------------------------------------------------------------------------------------------------------
function manage-scheduledTaskJob([string] $machine, $taskInfo, [bool] $wait = $false)
{
    #log-info "manage-scheduledTaskJob $($taskInfo.taskname) $($machine)"

    $functions = {
        # ----------------------------------------------------------------------------------------------------------------
        function log-info($data)
        {

            $data = "$([System.DateTime]::Now):$($data)`n"
            Write-Host $data

        }

        # ----------------------------------------------------------------------------------------------------------------
        function manage-scheduledTask([bool] $enable, [string] $machine, $taskInfo, [bool] $wait = $false)
        {
                # win 2k8r2 and below have to use com object
                # 2012 can use cmdlets
        
                log-info "manage-scheduledTask $($taskInfo.taskname) $($machine)"
        
                $TaskName = $taskInfo.taskname
                $TaskDescr = $taskInfo.taskdescr
                $TaskCommand = $taskInfo.taskcommand
                $TaskDir = $taskInfo.taskdir
                $TaskArg = $taskInfo.taskarg

                $error.Clear()
                $service = new-object -ComObject("Schedule.Service")
                # connect to the local machine. 
                # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381833(v=vs.85).aspx
	            # for remote machine connect do $service.Connect(serverName,user,domain,password)
                if([string]::IsNullOrEmpty($machine))
                {
                    $service.Connect()
                }
                else
                {
                    $service.Connect($machine)
                }
 
                $rootFolder = $service.GetFolder("\")
 
                if($enable)
                {
                    $TaskDefinition = $service.NewTask(0) 
                    $TaskDefinition.RegistrationInfo.Description = "$TaskDescr"
                    # 2k8r2 is 65539 (0x10003) 1.3
                    # procmon needs at least 2k8r2 compat
                    #$TaskDefinition.Settings.Compatibility = 3
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
                    $action.WorkingDirectory = $TaskDir
            
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
 
                if($wait)
                {
                    log-info "waiting for task to complete"
                    while($true)
                    {
                        $foundTask = $false
                        # stop task if its running
                        foreach($task in $service.GetRunningTasks(1))
                        {
                            if($task.Name -ieq $TaskName)
                            {
                                log-info "found task"
                                $foundTask = $true
                            }
                        }

                        if(!$foundTask)
                        {
                            break
                        }

                        Start-Sleep -Seconds 5
                    }
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
 
        } # end manage-scheduledTask
 

    } # end functions

    #throttle
    While((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
    {
        Start-Sleep -Milliseconds 100
    }

    log-info "starting task job: $($machine)-$($command.Values.GetHashCode()) $($command.Keys)"

    $job = Start-Job -Name "$($machine)-$($command.Values.GetHashCode())" -InitializationScript $functions -ScriptBlock {
        param($command,$machine, $taskInfo,$wait,$enable,$start)

        try
        {
            if($start)
            {
                log-info "manage-scheduledTaskJob 'start' job"
                # stop old task using current task name
                manage-scheduledTask -enable $true -machine $machine -taskInfo $taskInfo -wait $wait
            }
            else
            {
                log-info "manage-scheduledTaskJob 'stop' job"
                # stop old task using current task name
                manage-scheduledTask -enable $false -machine $machine -taskInfo $taskInfo -wait $false

                # start current task
                manage-scheduledTask -enable $true -machine $machine -taskInfo $taskInfo -wait $wait

                # stop current task
                manage-scheduledTask -enable $false -machine $machine -taskInfo $taskInfo -wait $false


            }
        }
            catch
        {
            log-info "Exception:manage-scheduledTaskJob: $($Error)"
            $Error.Clear()
        }
    } -ArgumentList ($command,$machine, $taskInfo,$wait,$enable,$start)

    
    $global:jobs = $global:jobs + $job

}

# ----------------------------------------------------------------------------------------------------------------
function find-commandFromJob($jobName)
{
    foreach($machine in $machines)
    {
        foreach($command in $global:stopCommands)
        {
            if($job.Name -ieq "$($machine)-$($command.Values.GetHashCode())")
            {
                return $command
            }
        }
        
        foreach($command in $global:startCommands)
        {
            if($job.Name -ieq "$($machine)-$($command.Values.GetHashCode())")
            {
                return $command
            }
        }
    }

    return $null
}



# ----------------------------------------------------------------------------------------------------------------
main