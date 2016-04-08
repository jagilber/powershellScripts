 
 
<#  
.SYNOPSIS  
    powershell script to manage umdh on local or remote machine

.DESCRIPTION  
    This script will help with the deployment and undeployment of umdh across multiple machines. 
    note: when undeploying, the powershell process will continue to run on remote machine until server is rebooted
    - umdh files will be in the remote server share that was specified. in examples below would be %systemroot%\temp
    
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
   File Name  : deploy-files-task.ps1  
   Author     : jagilber
   Version    : 150824
 
 .EXAMPLE  
    .\deploy-files-task.ps1 -action deploy -machine clt-jgs-2k8r2-2 -sourcePath c:\temp\deploy-files-task\sourcefiles -destPath admin$\temp
 
 .EXAMPLE  
    .\deploy-files-task.ps1 -action undeploy -machine clt-jgs-2k8r2-2 -sourcePath c:\temp\deploy-files-task\sourcefiles -destPath admin$\temp
 
 .EXAMPLE  
    .\deploy-files-task.ps1 -action undeploy -machine 127.0.0.1 -sourcePath c:\temp\deploy-files-task\sourcefiles -destPath admin$\temp

.PARAMETER action
    The action to take. Currently this is either 'deploy' or 'undeploy'. 
 
.PARAMETER machine
    The remote machine to deploy to. if deploying to local machine do not use this argument.
#>  
 
Param(
 
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter the action to take: [deploy|undeploy]")]
    [string] $action,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter machine names to deploy to:")]
    [string[]] $machines,
    [parameter(Position=2,Mandatory=$false,HelpMessage="Enter source folder containing files. example: c:\temp\sourcefiles")]
    [string] $sourcePath,
    [parameter(Position=3,Mandatory=$false,HelpMessage='Enter relative destination share path folder containing files. example: admin$\temp')]
    [string] $destPath="admin`$\temp",
    [parameter(Position=4,Mandatory=$false,HelpMessage='Enter DOS style *.* file pattern for files to gather from remote destination path. example: *.pml')]
    [string] $gatherFilePattern = "*.pml",
    [parameter(Position=5,Mandatory=$false,HelpMessage='Enter full path to folder where to store gathered files')]
    [string] $gatherPath = "$(get-location)\gather"
    ) 

$logFile = "deploy-files-task.log"
$processWaitMs = 1000

# scheduled task info
$taskInfoDeploy = @{}
$taskInfoDeploy.Add("taskname","EventLog Monitor deploy")
$taskInfoDeploy.Add("taskdescr","Monitors eventlog for event")
$taskInfoDeploy.Add("taskcommand","powershell.exe")
$taskInfoDeploy.Add("taskdir","%systemroot%\temp")
$taskInfoDeploy.Add("taskarg","-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file %systemroot%\temp\event-task-procmon.ps1")

$taskInfoUnDeploy = @{}
$taskInfoUnDeploy.Add("taskname","EventLog Monitor undeploy")
$taskInfoUnDeploy.Add("taskdescr","removes Monitors eventlog for event")
$taskInfoUnDeploy.Add("taskcommand","powershell.exe")
$taskInfoUnDeploy.Add("taskdir","%systemroot%\temp")
$taskInfoUnDeploy.Add("taskarg","-WindowStyle Hidden -NonInteractive -Executionpolicy bypass -file %systemroot%\temp\event-task-procmon.ps1 -terminate")


$time = (get-date) #- (new-timespan -day 12)

$requiresRestart = $false
 
# ----------------------------------------------------------------------------------------------------------------
function main()
{
    runas-admin
 
    
    if(![string]::IsNullOrEmpty($machines))
    {
        $isRemote = $true
    }
    else
    {
        $machines = [Environment]::MachineName
        $isRemote = $false
    }

    if($machines.Length -eq 1 -and $machines[0].Contains(","))
    {
        $machines = $machines.Split(",")
    }
    
 
    foreach($machine in $machines)
    {

        if(!(test-path "\\$($machine)\$($destPath)"))
        {
            log-info "unable to connect to $($machine). skipping."
            continue
        }

        if($action -ieq "deploy")
        {
            deploy-files -machine $machine
        }
        elseif($action -ieq "undeploy")
        {
            undeploy-files -machine $machine
        }
    }

 
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
    #only needed if useshellexecute is true
    $process.StartInfo.WorkingDirectory = get-location #$workingDirectory
 
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
function log-info($data)
{
    $data = "$([System.DateTime]::Now):$($data)`n"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}
 
# ----------------------------------------------------------------------------------------------------------------
function manage-scheduledTask([bool] $enable, [string] $machine, $taskInfo, [bool] $wait = $false)
{
        # win 2k8r2 and below have to use com object
        # 2012 can use cmdlets

        
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
 
}
 
# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    [string] $retVal = ""
 
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
function deploy-files($machine)
{

    if(![IO.Directory]::Exists($sourcePath))
    {
        log-info "unable to find source path $($sourcePath). exiting"
        return
    }
 
    if(![IO.Directory]::Exists("\\127.0.0.1\$($destPath)"))
    {
        log-info "unable to determine destination path \\127.0.0.1\$($destPath). exiting"
        return
    }
 
    

    # get source files
    $sourceFiles = [IO.Directory]::GetFiles($sourcePath, "*.*", [System.IO.SearchOption]::AllDirectories)
 
    # copy files
    foreach($sourceFile in $sourceFiles)
    {
        #$destFile = [IO.Path]::GetFileName($sourceFile)
        $destFile = $sourceFile.Replace("$($sourcePath)\","")
        $destFile = "\\$($machine)\$($destPath)\$($destFile)"
 
        log-info "copying file $($sourceFile) to $($destFile)"
 
        try
        {
            if(![IO.Directory]::Exists([IO.Path]::GetDirectoryName($destFile)))
            {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destFile))
            }

            [IO.File]::Copy($sourceFile, $destFile, $true)
        }
        catch
        {
            log-info "Exception:Copying File:$($sourceFile) to $($destFile): $($Error)"
            $Error.Clear()
        }
    }
        
 
    #create scheduled task
    manage-scheduledTask -enable $true -machine $machine -taskInfo $taskInfoDeploy
 
    if($requiresRestart)
    {
        $retVal = Read-Host -Prompt "server needs to be restarted. Do you want to do this now? [yes|no]" 
        if(![regex]::IsMatch($retVal,"yes",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        {
            log-info "exiting script. server not restarted"
        }
        else
        {
            log-info "restarting server."
            Restart-Computer -ComputerName $machine -Force -Impersonation Impersonate 
        }
    }
 
    return
} 

# ----------------------------------------------------------------------------------------------------------------
function undeploy-files($machine)
{
    manage-scheduledTask -enable $false -machine $machine -taskInfo $taskInfoDeploy
    manage-scheduledTask -enable $true -machine $machine -taskInfo $taskInfoUnDeploy -wait $true
    manage-scheduledTask -enable $false -machine $machine -taskInfo $taskInfoUnDeploy


    if(![string]::IsNullOrEmpty($gatherFilePattern))
    {
        $remotePath = "\\$($machine)\$($destPath)"
        # get remote files
        $directoryInfo = new-object IO.DirectoryInfo ($remotePath)

        [IO.FileInfo[]] $sourceFiles = ($directoryInfo.EnumerateFiles($gatherFilePattern,[IO.SearchOption]::TopDirectoryOnly))
 
        # copy files
        foreach($sourceFile in $sourceFiles)
        {
            $count = 0
            while ($count -lt 1000)
            {
                
                if(is-fileLocked($sourceFile.FullName))
                {
                    log-info "source file in use: $($sourceFile.FullName)"
                    Start-Sleep -Seconds 1
                    $count++
                }
                else
                {
                    $count = 0
                    break
                }
            }
        
            if($count -ne 0)
            {
                continue
            }
            
            $destFile = $sourceFile.FullName.Replace("$($remotePath)\","")
            $destFileBase = [IO.Path]::GetFileNameWithoutExtension($destFile)
            $destFileExtension = [IO.Path]::GetExtension($destFile)
            $destFile = "$($destFileBase)-$($sourceFile.CreationTime.ToString("yy-MM-dd-hh-mm-ss"))$($destFileExtension)"

            $destFile = "$($gatherPath)\$($machine)\$($destFile)"
 
            log-info "copying file $($sourceFile.FullName) to $($destFile)"
 
            try
            {
                if(![IO.Directory]::Exists([IO.Path]::GetDirectoryName($destFile)))
                {
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destFile))
                }

                [IO.File]::Copy($sourceFile.FullName, $destFile, $true)
                [IO.File]::Delete($sourceFile.FullName)
            }
            catch
            {
                log-info "Exception:Copying File:$($sourceFile.FullName) to $($destFile): $($Error)"
                $Error.Clear()
            }
        }
    }
 
    if($requiresRestart)
    {
        $retVal = Read-Host -Prompt "server needs to be restarted. Do you want to do this now? [yes|no]" 
        if(![regex]::IsMatch($retVal,"yes",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        {
            log-info "exiting script. server not restarted"
        }
        else
        {
            log-info "restarting server."
            Restart-Computer -ComputerName $machine -Force -Impersonation Impersonate 
        }
    }
        

    return


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
main
 
log-info "finished"
