<#  
.SYNOPSIS
    powershell script to manage commands remotely across multiple machines

.DESCRIPTION  
    Set-ExecutionPolicy Bypass -Force
    powershell script to manage commands remotely across multiple machines
    default job definitions at bottom of script
    
.NOTES  
   File Name  : remote-manager.ps1  
   Author     : jagilber
   Version    : 170313 fixed xperf dir
                
                
   History    : 
                170219 added -noclean and machine cleanup

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
    [parameter(HelpMessage = "Use to enable debug output")]
    [switch] $debugScript,
    [parameter(HelpMessage = "json path and file name for command export")]
    [string] $export,
    [parameter(HelpMessage = "Use to force overwrite of file copy")]
    [switch] $force,
    [parameter(HelpMessage = "Enter path for upload directory")]
    [string] $gatherDir = "",
    [parameter(HelpMessage = "json path and file name for command import")]
    [string] $import,
    [parameter(HelpMessage = "Enter comma separated list of machine names")]
    [string[]] $machines = @($env:COMPUTERNAME),
    [parameter(HelpMessage = "Enter number of minutes from now for event log gathering. Default is 60")]
    [string[]] $minutes = 60,
    [parameter(HelpMessage = "Use to not clean remote working directory on stop")]
    [switch] $noclean,
    [parameter(HelpMessage = "Use to start")]
    [switch] $start,
    [parameter(HelpMessage = "Use to stop")]
    [switch] $stop,
    [parameter(HelpMessage = "Enter integer for concurrent jobs limit. default is 10")]
    [int] $throttle = 10

)

cls
Add-Type -assembly "system.io.compression.filesystem"
$ErrorActionPreference = "SilentlyContinue" #"Stop"
$logFile = "remote-manager.log"
$global:jobs = @()
$jobThrottle = $throttle
$managedDirectory = "c:\windows\temp\remoteManager"
$managedRemoteDirectory = "admin`$\temp\remoteManager"
$managedDirectoryTagFile = "readme.txt"
$managedDirectoryFileTag = "created by remote-manager.ps1"
[System.Collections.ArrayList] $global:startCommands = new-object System.Collections.ArrayList
#$global:startCommands = @{}
[System.Collections.ArrayList]$global:stopCommands = New-Object System.Collections.ArrayList
#$global:stopCommands = @{}
$global:cleanupList = @{}

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    try
    {
        $Error.Clear()
        $nameStamp = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
        if ([string]::IsNullOrEmpty($gatherDir)) 
        { 
            $gatherDir = "$(get-Location)\gather\$($nameStamp)" 
        }
        ELSE
        {
            $gatherdir = "$($gatherdir)\$($nameStamp)"
        }

        # loads default jobs
        build-jobsList

        # export default jobs into json file
        if (![string]::IsNullOrEmpty($export))
        {
            export-jobs
            return
        }

        # import jobs from json file
        if (![string]::IsNullOrEmpty($import))
        {
            if (!(import-jobs))
            {
                return
            }
        }
       
        runas-admin

        # make sure action is specified
        if ($start -and $stop)
        {
            log-info "argument has to be start or stop, not both, exiting"
            return
        }

        if (!$start -and !$stop)
        {
            log-info "argument has to be start or stop, none specified, exiting"
            return
        }

        # clean up old powershell jobs
        clean-jobs

        $workingDir = Get-Location
 
        # add local machine if empty
        if ($machines.Count -lt 1)
        {
            $machines += $env:COMPUTERNAME
        }
        elseif ($machines.Count -eq 1 -and $machines[0].Contains(","))
        {
            # when passing comma separated list of machines from bat, it does not get separated correctly
            $machines = $machines[0].Split(",")
        }
        elseif ($machines.Count -eq 1 -and [IO.File]::Exists($machines))
        {
            # file passed in
            $machines = [IO.File]::ReadAllLines($machines);
        }

        foreach ($machine in $machines)
        {
            if (!(test-path "\\$($machine)\admin`$"))
            {
                log-info "machine $($machine) not accessible. skipping"
                continue
            }

            log-info "# ---------------------------------------------------------------"
            if ($start)
            {
                log-info "running start commands for $($machine)"
                process-commands -commands $global:startCommands -machine $machine
            }
            elseif ($stop)
            {
                log-info "running stop commands for machine $($machine)"
                process-commands -commands $global:stopCommands -machine $machine
            }
        } 

        wait-forJobs
        log-info "finished"

        if ($stop)
        {
            # process cleanup list
            clean-machines

            # zip and display            
            if ([IO.Directory]::Exists($gatherDir))
            {
                tree /a /f $($gatherDir)

                if ([IO.File]::Exists("$($gatherDir).zip"))
                {
                    [IO.File]::Delete("$($gatherDir).zip")
                }

                log-info "compressing..."
                [io.compression.zipfile]::CreateFromDirectory($gatherDir, "$($gatherDir).zip") 

                start "$([IO.Path]::GetDirectoryName($gatherDir))"
            }
        }
    }
    catch
    {
        if (get-job)
        {
            clean-jobs
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function clean-jobs()
{
    if (get-job)
    {
        [string] $ret = read-host -Prompt "There are existing jobs, do you want to clear?[y:n]" 
        if ($ret -ieq "y")
        {
            get-job 

            while (get-job)
            {
                get-job | remove-job -Force
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function clean-machines()
{
    if (!$noClean -and $global:cleanupList.Count -gt 0)
    {
        log-info "cleaning files from machines..."
        foreach ($machine in $machines)
        {
            # clean managed dir first
            $remoteDirectory = "\\$($machine)\$($managedRemoteDirectory)"
            $directoryFile = "$($remoteDirectory)\$($managedDirectoryTagFile)"

            if ([IO.Directory]::Exists($remoteDirectory) -and [IO.File]::Exists($directoryFile))
            {
                # check for tag for cleanup when removing directory
                if ([IO.File]::ReadAllText($directoryFile) -ieq $managedDirectoryFileTag)
                {
                    # ok to delete directory
                    [IO.Directory]::Delete($remoteDirectory, $true)
                    log-info "cleaning $($remoteDirectory)"
                }
            }

            foreach ($destinationDirectory in ($global:cleanupList.$machine).GetEnumerator())
            {
                if ($destinationDirectory.Contains($remoteDirectory))
                {
                    continue
                }

                log-info "checking $($machine) : $($destinationDirectory.Key)"
                $directoryFile = "$($destinationDirectory.Key)\$($managedDirectoryTagFile)"

                if (![IO.Directory]::Exists($destinationDirectory.Key) -or ![IO.File]::Exists($directoryFile))
                {
                    continue
                }

                try
                {
                    # check for tag for cleanup when removing directory
                    if ([IO.File]::ReadAllText($directoryFile) -ieq $managedDirectoryFileTag)
                    {
                        # ok to delete directory
                        [IO.Directory]::Delete($destinationDirectory.Key, $true)
                        log-info "cleaning $($destinationDirectory.Key)"
                    }
                }
                catch
                {
                    log-info "exception cleaning $($destinationDirectory). $($error)"
                    $error.Clear()
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function copy-files([hashtable] $files, [bool] $delete = $false)
{
    $resultFiles = @()
 
    foreach ($kvp in $files.GetEnumerator())
    {
        if ($kvp -eq $null)
        {
            continue
        }
 
        $destinationFile = $kvp.Value
        $sourceFile = $kvp.Key
 
        if (!(Test-Path $sourceFile))
        {
            log-info "Warning:Copying File:No source. skipping:$($sourceFile)"
            continue
        }
 
        $count = 0
 
        while ($count -lt 60)
        {
            try
            {
                # copy only if newer if not forced
                if (!$force -and [IO.File]::Exists($destinationFile))
                {
                    [IO.FileInfo] $dfileInfo = new-object IO.FileInfo ($destinationFile)    
                    [IO.FileInfo] $sfileInfo = new-object IO.FileInfo ($sourceFile)    
                    if ($dfileInfo.LastWriteTimeUtc -eq $sfileInfo.LastWriteTimeUtc)
                    {
                        if ($debugScript)
                        {
                            log-info "skipping file copy $($destinationFile)"
                        }

                        break
                    }
                }
 
                if (is-fileLocked $sourceFile)
                {
                    start-sleep -Seconds 1
                    $count++          
				    
                    if ($count -lt 60)          
                    {
                        Continue
                    }
                }
                
                if (![IO.Directory]::Exists([IO.Path]::GetDirectoryName($destinationFile)))
                {
                    $destinationDirectory = [IO.Path]::GetDirectoryName($destinationFile)
                    log-info "creating directory:$($destinationDirectory)"
                    [IO.Directory]::CreateDirectory($destinationDirectory)
                    # add tag for cleanup when command is stopped
                    [IO.File]::WriteAllText("$($destinationDirectory)\$($managedDirectoryTagFile)", $managedDirectoryFileTag)
                }
                
                log-info "Copying File:$($sourceFile) to $($destinationFile)"
                [IO.File]::Copy($sourceFile, $destinationFile, $true)
            
                if ($delete)
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
function deploy-files($command, $machine)
{
    if (!$start)
    {
        if ($debugScript)
        {
            log-info "deploy-files action not start. returning"
        }

        return
    }

    $isDir = $false

    try
    {
        $subDirSearch = [IO.SearchOption]::TopDirectoryOnly

        if ($command.searchSubDir)
        {
            $subDirSearch = [IO.SearchOption]::AllDirectories
        }
        
        foreach ($sourceFiles in $command.sourcefiles.Split(';', [StringSplitOptions]::RemoveEmptyEntries))
        {
            $copyFiles = @{}
            if ([string]::IsNullOrEmpty($sourceFiles))
            {
                log-info "deploy-files: no source files. returning"
                return
            }

            log-info "deploy-files searching $($sourceFiles)"

            if ($sourceFiles.Contains("?") -or $sourceFiles.Contains("*"))
            {
                $sourceFilter = [IO.Path]::GetFileName($sourceFiles)
                $sourceFiles = [IO.Path]::GetDirectoryName($sourceFiles)
                
            }
            else
            {
                if ([IO.Directory]::Exists($sourceFiles))
                {
                    $sourceFilter = "*"
                    $isDir = $true
                }
                else
                {
                    #assume file
                    $copyFiles.Add($sourcefiles, $sourcefiles.Replace([IO.Path]::GetDirectoryName($sourcefiles), "\\$($machine)\$($command.destfiles)"))
                    if ($debugScript)
                    {
                        $copyfiles | fl *
                    }

                    copy-files -files $copyFiles
                    continue
                }
            }

            $files = [IO.Directory]::GetFiles($sourceFiles, $sourceFilter, $subDirSearch)

            foreach ($file in $files)
            {
                $destFile = $null
                if (!$isDir)
                {
                    $destFile = "\$([IO.Path]::GetFileName($file))"
                }

                $copyFiles.Add($file, $file.Replace($sourcefiles, "\\$($machine)\$($command.destfiles)$($destFile)"))
            }

            if ($debugScript)
            {
                $copyfiles | fl *
            }

            if ($debugScript)
            {
                $copyfiles | fl *
            }

            copy-files -files $copyFiles
        }
    }
    catch
    {
        log-info "deploy-files error: $($error)"
        $error.Clear()
    }
}

# ----------------------------------------------------------------------------------------------------------------
function export-jobs()
{
    if (![string]::IsNullOrEmpty($export))
    {
        $commands = @{}
        $commands.StartCommands = $global:startCommands
        $commands.StopCommands = $global:stopCommands

        ConvertTo-Json -InputObject $commands -Depth 3 | out-file $export -Force
    }
}

# ----------------------------------------------------------------------------------------------------------------
function find-commandFromJob($jobName)
{
    foreach ($machine in $machines)
    {
        foreach ($command in $global:stopCommands)
        {
            if ($job.Name -ieq "$($machine)-$($command.Name)")
            {
                return $command
            }
        }
        
        foreach ($command in $global:startCommands)
        {
            if ($job.Name -ieq "$($machine)-$($command.Name)")
            {
                return $command
            }
        }
    }

    return $null
}

# ----------------------------------------------------------------------------------------------------------------
function gather-files($command, $machine)
{

    if (!$stop)
    {
        if ($debugScript)
        {
            log-info "gather-files action not stop. returning"
        }

        return
    }
    try
    {
        $subDirSearch = [IO.SearchOption]::TopDirectoryOnly

        if ($command.searchSubDir)
        {
            $subDirSearch = [IO.SearchOption]::AllDirectories
        }

        if ([string]::IsNullOrEmpty($command.destfiles))
        {
            $command.destfiles = $gatherDir
        }
        elseif ($command.destfiles.StartsWith("."))
        {
            $command.destfiles = $command.destfiles.Replace(".", $gatherDir)
        }

        $copyFiles = @{}
        # directory, files, wildcard
        foreach ($sourceFiles in $command.sourcefiles.Split(';', [StringSplitOptions]::RemoveEmptyEntries))
        {
            $sourceFilesPath = "\\$($machine)\$($sourcefiles)"
            log-info "gather-files searching $($sourceFilesPath)"

            if ($sourceFilesPath.Contains("?") -or $sourceFilesPath.Contains("*"))
            {
                $sourceFilter = [IO.Path]::GetFileName($sourceFilesPath)
                $sourceFilesPath = [IO.Path]::GetDirectoryName($sourceFilesPath)
            }
            else
            {
                if ([IO.Directory]::Exists($sourceFilesPath))
                {
                    $sourceFilter = "*"
                }
                else
                {
                    #assume file
                    $copyFiles.Add($sourcefilesPath, $sourcefilesPath.Replace([IO.Path]::GetDirectoryName($sourcefilesPath), "$($command.destfiles)\$($machine)"))
                    if ($debugScript)
                    {
                        $copyfiles | fl *
                    }

                    copy-files -files $copyFiles
                    continue
                }
            }

            # add to cleanup list
            if (!$global:cleanupList.Contains($machine))
            {
                $global:cleanupList.Add($machine, @{})
            }

            if (!($global:cleanupList.$machine).Contains($sourceFilesPath))
            {
                log-info "adding $($machine) $($sourceFilesPath) to cleanup list"
                ($global:cleanupList.$machine).Add($sourceFilesPath, "")
            }

            log-info "gather-files searching $($sourceFilesPath) for $($sourceFilter)"
            $files = [IO.Directory]::GetFiles($sourceFilesPath, $sourceFilter, $subDirSearch)

            # save in global list to copy at end of all job completion
            foreach ($file in $files)
            {
                $copyFiles.Add($file, $file.Replace($sourceFilesPath, "$($command.destfiles)\$($machine)"))
            }

            if ($debugScript)
            {
                $copyfiles | fl *
            }

            copy-files -files $copyFiles -delete $true
        }
    }
    catch
    {
        log-info "gather-files :exception $($error)"
        $error.Clear()
    }
}

# ----------------------------------------------------------------------------------------------------------------
function import-jobs()
{
    if (![string]::IsNullOrEmpty($import))
    {
        if (test-path $import)
        {
            $global:startCommands.Clear()
            $global:stopCommands.Clear()
            $commands = ConvertFrom-Json -InputObject (get-content $import -Raw)
            $global:startCommands = $commands.StartCommands
            $global:stopCommands = $commands.StopCommands
        }
        else
        {
            log-info "json file does not exist:$($import)"
            return $false
        }

        return $true
    }

    return $false
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
        
        if ($debugScript)
        {
            log-info "File is NOT locked:$($file)"
        }

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
function log-info($data)
{
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    if ([regex]::IsMatch($data.ToLower(), "error|exception|fail|warning"))
    {
        write-host $data -foregroundcolor Yellow
    }
    elseif ([regex]::IsMatch($data.ToLower(), "running"))
    {
        write-host $data -foregroundcolor Green
    }
    else
    {
        Write-Host $data
    }

    $counter = 0
    while (!$dataWritten -and $counter -lt 1000)
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
            if ([string]::IsNullOrEmpty($machine))
            {
                $service.Connect()
            }
            else
            {
                $service.Connect($machine)
            }

            $rootFolder = $service.GetFolder("\")

            if ($enable)
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
                $rootFolder.RegisterTaskDefinition("$TaskName", $TaskDefinition, 6, "System", $null, 5)

                #start task
                $task = $rootFolder.GetTask($TaskName)

                $task.Run($null)

            }
            else
            {
                # stop task if its running
                foreach ($task in $service.GetRunningTasks(1))
                {
                    if ($task.Name -ieq $TaskName)
                    {
                        if ($debugScript)
                        {
                            log-info "found task $($TaskName)"
                        }

                        $task.Stop()
                    }
                }

                # delete task
                $rootFolder.DeleteTask($TaskName, $null)
            }

            if ($wait)
            {
                log-info "waiting for task to complete"
                while ($true)
                {
                    $foundTask = $false
                    # stop task if its running
                    foreach ($task in $service.GetRunningTasks(1))
                    {
                        if ($task.Name -ieq $TaskName)
                        {
                            if ($debugScript)
                            {
                                log-info "found task $($TaskName)"
                            }
                            $foundTask = $true
                        }
                    }

                    if (!$foundTask)
                    {
                        break
                    }

                    Start-Sleep -Seconds 5
                }
            }

            if ($error.Count -ge 1)
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
    While ((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
    {
        Start-Sleep -Milliseconds 100
    }

    log-info "starting task job: $($machine)-$($command.Name)"

    $job = Start-Job -Name "$($machine)-$($command.Name)" -InitializationScript $functions -ScriptBlock {
        param($command, $machine, $taskInfo, $wait, $enable, $start)

        try
        {
            if ($start)
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
    } -ArgumentList ($command, $machine, $taskInfo, $wait, $enable, $start)
    
    $global:jobs = $global:jobs + $job
}

# ----------------------------------------------------------------------------------------------------------------
function process-commands($commands, [string] $machine)
{
    foreach ($command in $commands) 
    {
        if (!$command.enabled)
        {
            continue
        }

        deploy-files -command $command -machine $machine

        if ([string]::IsNullOrEmpty($command.command))
        {
            log-info "skipping empty command"
            continue
        }

        if ($command.useWmi)
        {
            run-wmiCommandJob -command $command -machine $machine
        }
        else
        {

            manage-scheduledTaskJob -wait $command.wait -machine $machine -taskInfo @{
                "taskname"    = $command.Keys;
                "taskdescr"   = $command.Keys;
                "taskcommand" = $command.command;
                "taskdir"     = $command.workingDir;
                "taskarg"     = $command.arguments
            }
        }
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
    While ((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
    {
        Start-Sleep -Milliseconds 100
    }

    log-info "starting wmi job: $($machine)-$($command.Name)"

    $job = Start-Job -Name "$($machine)-$($command.Name)" -InitializationScript $functions -ScriptBlock {
        param($command, $machine)

        try
        {
            $commandline = "$($command.command) $($command.arguments)"
            log-info "running wmi command: $($commandline)"
        
            $startup = [wmiclass]"Win32_ProcessStartup"
            $startup.Properties['ShowWindow'].value = $False
            $ret = Invoke-WmiMethod -ComputerName $machine -Class Win32_Process -Name Create -Impersonation Impersonate -ArgumentList @($commandline, $command.workingDir, $startup)

            if ($ret.ReturnValue -ne 0 -or $ret.ProcessId -eq 0)
            {
                log-info "Error:run-wmiCommand: $($ret.ReturnValue)"
                return
            }

            if ($command.wait)
            {
                while ($true)
                {
                    #log-info "waiting on process: $($ret.ProcessId)"
                    if ((Get-WmiObject -ComputerName $machine -Class Win32_Process -Filter "ProcessID = '$($ret.ProcessId)'"))
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
    } -ArgumentList ($command, $machine)
    
    $global:jobs = $global:jobs + $job
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
        log-info "please restart script as administrator. exiting..."
        exit
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function wait-forJobs()
{
    log-info "jobs count:$($global:jobs.Length)"
    # Wait for all jobs to complete
    $waiting = $true
    $failedJobs = New-Object System.Collections.ArrayList

    if ($global:jobs -ne @())
    {
        while ($waiting)
        {
            #Wait-Job -Job $global:jobs
            $waiting = $false
            foreach ($job in Get-Job)
            {

                #log-info "waiting on $($job.Name):$($job.State)"
                switch ($job.State)
                {
                    'Stopping' { $waiting = $true }
                    'NotStarted' { $waiting = $true }
                    'Blocked' { $waiting = $true }
                    'Running' { $waiting = $true }
                }

                if ($stop -and $job.State -ieq 'Completed')
                {
                    # gather files
                    foreach ($machine in $machines)
                    {
                        foreach ($command in $global:stopCommands)
                        {
                            if ($job.Name -ieq "$($machine)-$($command.Name)")
                            {
                                log-info "job completed, copying files from: $($machine) for command: $($command.Name)"
                                gather-files -command $command -machine $machine
                            }
                        }
                    }

                  
                }
                
                # restart failed jobs
                if ($job.State -ieq 'Failed')
                {
                    Receive-Job -Job $job
                    if (!$failedJobs.Contains($job))
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
                if ($job.State -ieq 'Completed')
                {
                    Receive-Job -Job $job
                    Remove-Job -Job $job
                }
            }
            
            if ($debugScript -or $job.State -ieq 'Completed')
            {
                foreach ($job in $global:jobs)
                {
                    if ($job.State -ine 'Completed')
                    {
                        log-info ("$($job.Name):$($job.State):$($job.Error):$((find-commandFromJob -jobName $job.Name).Keys)")
                        Receive-Job -Job $job 
                    }
                }
            }
            else
            {
                Write-Host "." -NoNewline
            }

            Start-Sleep -Seconds 1
        } # end while
    } # end if
}

# ----------------------------------------------------------------------------------------------------------------
function build-jobsList()
{
    ##################
    #                #
    # START COMMANDS #
    #                #
    ##################

    $global:startCommands.Add(@{ 
            'name'         = "rdgateway-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\rdgateway.mgr.bat start";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\rdgateway\rdgateway.mgr.bat";
            'destfiles'    = $managedRemoteDirectory;
            'searchSubDir' = $false
        })


    $global:startCommands.Add(@{ 
            'name'         = "perfmon-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\perfmon.mgr.bat start";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\perfmon\perfmon.mgr.bat";
            'destfiles'    = $managedRemoteDirectory;
            'searchSubDir' = $false
        })

    $global:startCommands.Add(@{ 
            'name'         = "event-log-manager-debug";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-log-manager.ps1 -enableDebugLogs -rds -eventLogNamePattern `"hyper|host|virtual`"";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\events-export";
            'destfiles'    = $managedRemoteDirectory;
            'searchSubDir' = $true
        })

    $global:startCommands.Add(@{ 
            'name'         = "event-log-manager";
            'enabled'      = $true;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "";
            'arguments'    = "";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\events-export";
            'destfiles'    = $managedRemoteDirectory;   
            'searchSubDir' = $true
        })

    $global:startCommands.Add(@{ 
            'name'         = "rds-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file logman-wrapper.ps1 -rds -action deploy -configurationfile .\single-session.xml";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\2k12-rds-tracing";
            'destfiles'    = $managedRemoteDirectory;
            'searchSubDir' = $false
        })

    $global:startCommands.Add(@{ 
            'name'         = "network-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "netsh.exe";
            'arguments'    = "trace start capture=yes overwrite=yes maxsize=1024 filemode=circular tracefile=$($managedDirectory)\net.etl";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:startCommands.Add(@{ 
            'name'         = "xperf-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\xperf\xperf.mgr.bat set&&$($managedDirectory)\xperf\xperf.mgr.bat start slowlogon";
            'workingDir'   = "$($managedDirectory)\xperf";
            'sourceFiles'  = "$(get-Location)\xperf";
            'destfiles'    = "$($managedRemoteDirectory)\xperf";
            'searchSubDir' = $true
        })

    $global:startCommands.Add(@{ 
            'name'         = "procmon-tracing";
            'enabled'      = $false;
            'useWmi'       = $false; 
            'wait'         = $false;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-task-procmon.ps1";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$(get-Location)\procmon-tracing";
            'destfiles'    = $managedRemoteDirectory;
            'searchSubDir' = $true
        })

    #################
    #               #
    # STOP COMMANDS #
    #               #
    #################

    $global:stopCommands.Add(@{ 
            'name'         = "procmon-tracing";
            'enabled'      = $false;
            'useWmi'       = $false; 
            'wait'         = $true;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-task-procmon.ps1 -terminate";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\*.pml";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "xperf-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\xperf\xperf.mgr.bat stop slowlogon";
            'workingDir'   = "$($managedDirectory)\xperf";
            'sourceFiles'  = "$($managedRemoteDirectory)\xperf\*.etl";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "rds-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file logman-wrapper.ps1 -rds -action undeploy -configurationfile .\single-session.xml -nodynamicpath";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\gather";
            'destfiles'    = "";
            'searchSubDir' = $true
        })

    $global:stopCommands.Add(@{ 
            'name'         = "network-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "netsh.exe";
            'arguments'    = "trace stop";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\net.etl";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "event-log-manager";
            'enabled'      = $true;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "powershell.exe";
            #   'arguments' = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-log-manager.ps1 -clearEventLogsOnGather -rds -uploadDir $($managedDirectory)\events";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-log-manager.ps1 -minutes $($minutes) -rds -uploadDir $($managedDirectory)\events -nodynamicpath -eventLogNamePattern `'hyper|host|virtual`'";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\events\*.csv";
            'destfiles'    = "";
            'searchSubDir' = $true
        })

    $global:stopCommands.Add(@{ 
            'name'         = "event-log-manager-debug";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $false;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file event-log-manager.ps1 -disableDebugLogs -listEventLogs";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "process-list";
            'enabled'      = $true;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "powershell.exe";
            'arguments'    = "-WindowStyle Hidden -NonInteractive -Executionpolicy bypass &`"{get-process | fl * > $($managedDirectory)\processList.txt}`"";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\processList.txt";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "perfmon-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\perfmon.mgr.bat stop";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "$($managedRemoteDirectory)\*.blg";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

    $global:stopCommands.Add(@{ 
            'name'         = "rdgateway-tracing";
            'enabled'      = $false;
            'useWmi'       = $true; 
            'wait'         = $true;
            'command'      = "cmd.exe";
            'arguments'    = "/c $($managedDirectory)\rdgateway.mgr.bat stop";
            'workingDir'   = $managedDirectory;
            'sourceFiles'  = "c`$\windows\tracing\*;c`$\windows\debug\i*.log;c$\windows\debug\n*.log";
            'destfiles'    = "";
            'searchSubDir' = $false
        })

}

# ----------------------------------------------------------------------------------------------------------------
main