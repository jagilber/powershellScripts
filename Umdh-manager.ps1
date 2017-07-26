 

<#  
.SYNOPSIS  
    powershell script to manage umdh on local or remote machine

.DESCRIPTION  
    This script will help with the deployment and undeployment of umdh across multiple machines. 
    note: when undeploying, the powershell process will continue to run on remote machine until server is rebooted
    - umdh files will be in the remote server share that was specified. in examples below would be %systemroot%\temp
    
.NOTES  
   File Name  : umdh-manager.ps1  
   Author     : jagilber
   Version    : 150611
 
 .EXAMPLE  
    .\Umdh-manager.ps1 -action deploy -machine clt-jgs-2k8r2-2 -sourcePath c:\temp\umdh-manager\sourcefiles -destPath admin$\temp
 
 .EXAMPLE  
    .\Umdh-manager.ps1 -action undeploy -machine clt-jgs-2k8r2-2 -sourcePath c:\temp\umdh-manager\sourcefiles -destPath admin$\temp
 
 .EXAMPLE  
    .\Umdh-manager.ps1 -action undeploy -machine 127.0.0.1 -sourcePath c:\temp\umdh-manager\sourcefiles -destPath admin$\temp

.PARAMETER action
    The action to take. Currently this is either 'deploy' or 'undeploy'. 

.PARAMETER machine
    The remote machine to deploy to. if deploying to local machine do not use this argument.
#>  

Param(

    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter the action to take: [deploy|undeploy]")]
    [string] $action,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter machine name to deploy to:")]
    [string] $machine,
    [parameter(Position=2,Mandatory=$false,HelpMessage="Enter source folder containing files. example: c:\temp\sourcefiles")]
    [string] $sourcePath,
    [parameter(Position=3,Mandatory=$false,HelpMessage='Enter relative destination share path folder containing files. example: admin$\temp')]
    [string] $destPath
    )

$scriptName = "umdh-script-start.bat"
$logFile = "umdh-manager.log"
$processWaitMs = 1000
$TaskName = "Umdh-manager"
$TaskDescr = "Manages umdh"
$TaskDir = "%systemroot%\temp"

#use svcHostService OR processName but not both
$svcHostService = "WinRM"
$processName = $null #"testlimit64"

$TaskArg = ""
$TaskCommand = "$($TaskDir)\$($scriptName)"
$sleepTimeHours = 1
$requiresRestart = $false
$procDumpExe = "procdump.exe"
$procArguments = "-accepteula -ma"

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    runas-admin

    
    if(![string]::IsNullOrEmpty($machine))
    {
        $isRemote = $true
    }
    else
    {
        $machine = [Environment]::MachineName
        $isRemote = $false
    }

    if($action -ieq "deploy")
    {
        #[Environment]::SetEnvironmentVariable( "_NT_SYMBOL_PATH", "c:\mysymbols;srv*c:\mycache*http://msdl.microsoft.com/download/symbols", [System.EnvironmentVariableTarget]::Machine )
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

        # verify $svcHostService is in its own process
        if($svcHostService -ne $null)
        {
            if((get-service -ComputerName $machine -Name $svcHostService).ServiceType -imatch "Win32ShareProcess")
            {
                $retVal = run-process -processName "sc" -arguments "\\$($machine) config $svcHostService type= own" -wait $true
                $svc = Get-Service -Name $svcHostService -ComputerName $machine
                $svc.Stop()
                $count = 0
                while($svc.Status -ine "Stopped" -and $count -lt 30)
                {
                    Start-Sleep 1
                    $svc = Get-Service -Name $svcHostService -ComputerName $machine
                    $count++
                }

                $svc.Start()

                log-info "$svcHostService has been configured to run in its own process." 

            }
            else
            {
                log-info "$svcHostService already set to use its own process"
            }
        }

        # get source files
        $sourceFiles = [IO.Directory]::GetFiles($sourcePath, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)

        # copy files
        foreach($sourceFile in $sourceFiles)
        {
            $destFile = [IO.Path]::GetFileName($sourceFile)
            $destFile = "\\$($machine)\$($destPath)\$($destFile)"

            log-info "copying file $($sourceFile) to $($destFile)"

            try
            {
                [IO.File]::Copy($sourceFile, $destFile, $true)
            }
            catch
            {
                log-info "Exception:Copying File:$($sourceFile) to $($destFile): $($Error)"
                $Error.Clear()
            }
        }
        

        #create scheduled task
        manage-scheduledTask -enable $true -machine $machine

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
    elseif($action -ieq "undeploy")
    {
        if($svcHostService -ne $null)
        {
            if((get-service -ComputerName $machine -Name $svcHostService).ServiceType -imatch "Win32OwnProcess")
            {
                $retVal = run-process -processName "sc" -arguments "\\$($machine) config $svcHostService type= share" -wait $true 
                $svc = Get-Service -Name $svcHostService -ComputerName $machine
                $svc.Stop()
                $count = 0
                while($svc.Status -ine "Stopped" -and $count -lt 30)
                {
                    Start-Sleep 1
                    $svc = Get-Service -Name $svcHostService -ComputerName $machine
                    $count++
                }

                $svc.Start()

                log-info "$svcHostService set back to sharing process (default)."
            }   
            else
            {
                log-info "$svcHostService already set to use share process"
            }
       }

        manage-scheduledTask -enable $false -machine $machine

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

   # no arguments so do task

    $workingDir = get-workingDirectory
    $umdhExe = "$($workingDir)\umdh.exe"

    if(![System.IO.File]::Exists($umdhExe))
    {
        log-info "$($umdhExe) does not exist. copy umdh.exe into same directory as script. exiting"
        return
    }

    $procDumpExe = "$($workingDir)\$($procDumpExe)"

    if(![System.IO.File]::Exists($procDumpExe))
    {
        log-info "$($procDumpExe) does not exist. copy umdh.exe into same directory as script. exiting"
        return
    }
   

   if($svcHostService -ne $null)
   {
       if((get-service -ComputerName $machine -Name $svcHostService).ServiceType -imatch "Win32ShareProcess")
       {
            log-info "Error:$svcHostService not configured to run its own process."
            log-info "Run script with -action deploy to change. exiting..."
            return
       }
   }


    $dumpSchedule = @{100 = $false; 200 = $false; 300 = $false; 400 = $false  }
    
   # do work
   while($true)
   {
       $processId = $null
       $outputFile = "$($workingdir)\umdh-$([System.DateTime]::Now.ToString(`"yy-MM-dd-HH-mm`")).txt"
       if($svcHostService -ne $null)
       {
            $processId = (gwmi Win32_Service -Filter "Name LIKE '$svcHostService'").ProcessId
       }
       elseif($processName -ne $null)
       {
            $processId = (get-process -Name $processName).Id
            if([string]::IsNullOrEmpty($processId) -or $processId -lt 1)            
            {
                log-info "Error:$processName does not exist. sleeping..."
                  if($sleepTimeHours -eq 0)
                   {
                        #test mode sleep 1 second
                        sleep -Seconds 10
                   }
                   else
                   {
                        sleep -Seconds ($sleepTimeHours * 60 * 60)
                   }
                continue
            }
       }
       

       $arguments = "-p:$($processId) -f:$($outputFile)"
       run-process -processName $umdhExe -arguments $arguments -wait $true

       # check size of private bytes
       # dump at 100,200,300,400,quit
       $process = Get-Process -id $processId
       $privateMBytes = $process.PrivateMemorySize / 1024 / 1024

       if(($privateMBytes -gt 100) -and ($dumpSchedule[100] -eq $false))
       {
            $dumpSchedule[100] = $true
            run-process -processName $procDumpExe -arguments "$procArguments $processId" -wait $true
       }
       elseif(($privateMBytes -gt 200) -and ($dumpSchedule[200] -eq $false))
       {
            $dumpSchedule[200] = $true
            run-process -processName $procDumpExe -arguments "$procArguments $processId" -wait $true
       }
       elseif(($privateMBytes -gt 300) -and ($dumpSchedule[300] -eq $false))
       {
            $dumpSchedule[300] = $true
            run-process -processName $procDumpExe -arguments "$procArguments $processId" -wait $true
       }
       elseif(($privateMBytes -gt 400) -and ($dumpSchedule[400] -eq $false))
       {
            $dumpSchedule[400] = $true
            run-process -processName $procDumpExe -arguments "$procArguments $processId" -wait $true
            return;
       }


       if($sleepTimeHours -eq 0)
       {
            #test mode sleep 1 second
            sleep -Seconds 10
       }
       else
       {
            sleep -Seconds ($sleepTimeHours * 60 * 60)
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
function manage-scheduledTask([bool] $enable, [string] $machine)
{
    # win 2k8r2 and below have to use com object
    # 2012 can use cmdlets
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
main

log-info "finished"
