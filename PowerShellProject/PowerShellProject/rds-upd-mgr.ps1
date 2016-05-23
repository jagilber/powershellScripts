<#  
.SYNOPSIS  
    powershell script to enumerate customer RDS environment for UPD information
    
.DESCRIPTION  
    powershell script to enumerate customer RDS environment for UPD information
    

.NOTES  
    Version:
        160520 original 
    
    History:
  
.EXAMPLE  
    .\rds-upd-mgr.ps1 -user jagilber
    .\rds-upd-mgr.ps1 -sid S-1-5-21-124525095-708259637-1543119021-1234567
    
.PARAMETER user
    users ad account with issue
 
.PARAMETER sid
    users sid or sid from vhd with issue

.PARAMETER server
    server to query or connection broker to query
#>  
 
 
Param(
 
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter customer subscription id:")]
    [string] $user,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter customer RemoteApp Id:")]
    [string] $sis,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter customer RemoteApp Id:")]
    [string] $server
    )

$logFile = "rds-upd-mgr.log"


# ---------------------------------------------------------------------------
function main ()
{
    $servers = @()
    $userSessions = @{}

    if([string]::IsNullOrEmpty($server))
    {
        log-info "getting all rds servers from broker, if broker does not exist, query current server"
        $servers = Get-RDServer
    }
    else
    {
        $servers = @($server)
    }

    foreach ($rdServer in $servers)
    {
        
        $users = enumerate-users -server $rdServer
        $userSids = enumerate-sids -users $users

        $userSessions.Add(
        enumerate-drives - server $rdServer
    }
}

#----------------------------------------------------------------------------
function log-info($data)
{
    if($data.ToString().ToLower().StartsWith("error"))
    {
        $ForegroundColor = "Yellow"
    }
    elseif($data.ToString().ToLower().StartsWith("fail"))
    {
        $ForegroundColor = "Red"
    }
    else
    {
        $ForegroundColor = "Green"
    }
 
    write-host $data -ForegroundColor $ForegroundColor

    try
    {
        if(![string]::IsNullOrEmpty($logFile))
        {
            out-file -Append -FilePath $logFile -InputObject "$([DateTime]::Now):$($data)" -Encoding ascii
        }
    }
    catch 
    { 
        $error
        $error.Clear()
    }
}

# ---------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    $Error.Clear()
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $wait
    $process.StartInfo.RedirectStandardError = $wait
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $wait
    $process.StartInfo.WorkingDirectory = get-location
 
    [void]$process.Start()
 
    if($wait -and !$process.HasExited)
    {
 
        if($process.StandardOutput.Peek() -gt -1)
        {
            $stdOut = $process.StandardOutput.ReadToEnd()
            log-info $stdOut
        }
 
 
        if($process.StandardError.Peek() -gt -1)
        {
            $stdErr = $process.StandardError.ReadToEnd()
            log-info $stdErr
            $Error.Clear()
        }
            
    }
    elseif($wait)
    {
        log-info "Error:Process ended before capturing output."
    }
    
 
    
    $exitVal = $process.ExitCode
 
    log-info "Running process exit $($processName) : $($exitVal)"
    $Error.Clear()
 
    return $stdOut
}

# ---------------------------------------------------------------------------
main