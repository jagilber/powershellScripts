#    This script will help with the deployment and undeployment of umdh. 
#    
#   File Name  : umdh-manager-2k8.ps1  
#   Author     : jagilber
#   Version    : 150413
# 

$scriptName = "umdh-manager-2k8.ps1"
$logFile = "%systemroot%\temp\umdh-manager-2k8.log"
$sleepTimeMins = 60
$processWaitMs = 100

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    runas-admin

    $workingDir = get-workingDirectory
    $umdhExe = "$($workingDir)\umdh.exe"

    if(![System.IO.File]::Exists($umdhExe))
    {
        log-info "$($umdhExe) does not exist. copy umdh.exe into same directory as script. exiting"
        return
    }

    #[Environment]::SetEnvironmentVariable( "_NT_SYMBOL_PATH", "c:\mysymbols;srv*c:\mycache*http://msdl.microsoft.com/download/symbols", [System.EnvironmentVariableTarget]::Machine )

    # verify termservice is in its own process
    if((get-service -Name TermService).ServiceType -imatch "Win32ShareProcess")
    {
        #$retVal = Read-Host -Prompt "this will restart remote desktop services. existing connections will be dropped, but sessions will remain. clients can reconnect. is this ok? [yes|no]" 
        #if(![regex]::IsMatch($retVal,"yes",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        #{
        #    log-info "exiting script. no changes made"
        #    return
        #}

        log-info "Error: remote desktop services is not in its own process. exiting." 
        return
        #log-info "restarting remote desktop services. existing connections will be dropped, but sessions will remain. clients can reconnect." 
        #$retVal = run-process -processName "sc" -arguments "config termservice type= own" -wait $true
        #$service = get-service -Name TermService
        #Restart-Service -InputObject $service -Force
    }
    else
    {
        log-info "termservice already set to use its own process"
    }
        

   if((get-service -Name TermService).ServiceType -imatch "Win32ShareProcess")
   {
        log-info "Error:TermService not configured to run its own process."
        log-info "Run script with -action deploy to change. This will require restart of terminal service. exiting..."
        return
   }


    while($true)
    {
        $outputFile = [Environment]::ExpandEnvironmentVariables("%systemroot%\temp\umdh-$([System.DateTime]::Now.ToString(`"yy-mm-dd-HH-mm`")).txt")
        $processId = (gwmi Win32_Service -Filter "Name LIKE 'TermService'").ProcessId

        $arguments = "-p:$($processId) -f:$($outputFile)"
        run-process -processName $umdhExe -arguments $arguments -wait $true
        sleep -Seconds ($sleepTimeMins * 60)
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
    #Write-Host $data
    out-file -Append -InputObject $data -FilePath ([Environment]::ExpandEnvironmentVariables($logFile))
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
