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

.PARAMETER machine
    machine to query or connection broker to query
#>  
 
 
Param(
 
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter customer subscription id:")]
    [string] $user,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter customer RemoteApp Id:")]
    [string] $sis,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter customer RemoteApp Id:")]
    [string] $machine,
    [parameter(Position=4,Mandatory=$false,HelpMessage="Enter `$true to prompt / use alternate credentials. Default is `$false")]
    [bool] $useCreds = $false,
    [parameter(Position=5,Mandatory=$false,HelpMessage="Enter `$true to store alternate credentials. Default is `$false")]
    [bool] $storeCreds = $false

    )

 
$ErrorActionPreference = "SilentlyContinue"
$Creds = $null
# if storing creds, password will have to be saved one time
$passFile = "securestring.txt" 
$logFile = "rds-upd-mgr.log"


# ---------------------------------------------------------------------------
function main ()
{
    $error.Clear()
    $machines = @()
    $userSessions = @{}


    log-info "============================================="
    log-info "Starting: $(get-date)"
    
    $retval

    if($useCreds)
    {
        if((test-path $passFile) -and $storeCreds)
        {

            $password = cat $passFile | convertto-securestring
            $Creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password

        }
        elseif($storeCreds)
        {
            read-host -assecurestring | convertfrom-securestring | out-file $passFile

            $password = cat $passFile | convertto-securestring
            $Creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password

        }
        else
        {
            $Creds = Get-Credential
        }
    }

    if([string]::IsNullOrEmpty($machine))
    {
        log-info "getting all rds machines from broker, if broker does not exist, query current machine"
        $machines = get-machines
    }
    else
    {
        $machines = @($machine)
    }

    foreach ($machine in $machines)
    {
        
        manage-wmiExecute -command $command -machine $machine
        $users = enumerate-users -machine $rdmachine
        $userSids = enumerate-sids -users $users

        $userSessions.Add(
        enumerate-drives - machine $rdmachine
    }

    
    
    log-info "Finished"

}

#----------------------------------------------------------------------------
function get-machines()
{
    $machines = @()
    if(!(get-service -DisplayName 'Remote Desktop Connection Broker' -ErrorAction SilentlyContinue))
    {
        return $machines
    }

    try
    {
        
        # see if it is a connection broker
        $machines = (Get-RDmachine).machine
        if($machines -ne $null)
        {
            foreach($machine in $machines)
            {
                log-info $machine
            }

            $result = Read-Host "do you want to collect data from entire deployment? [y:n]"
            if([regex]::IsMatch($result, "y",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
            {
                log-info "adding rds collection machines"
                $machines = $machines
            }
        }
    }
    catch {}

    return $machines
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


# ----------------------------------------------------------------------------------------------------------------
function manage-wmiExecute([string] $command, [string] $machine)
{
    log-info "wmiExecute: $($machine) : $($command) : $($workingDir)"
   # $wmi = new-object System.Management.ManagementClass "\\$($machine)\Root\cimv2:Win32_Process" 
   # $result = $wmi.Create($command)
    if($useCreds)
    {
        $result = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList ($command, $workingDir) -Credential $Creds -ComputerName $computer
    }
    else
    {
        $result = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList ($command, $workingDir) -ComputerName $computer
    }
    
    switch($result.ReturnValue)
    {
        0
            {
                log-info "$($machine) return:success"
            }

        2
            {
                log-info "$($machine) return:access denied"
            }

        3
            {
                log-info "$($machine) return:insufficient privilege"
            }
        
        8
            {
                log-info "$($machine) return:unknown failure"
            }

        9
            {
                log-info "$($machine) return:path not found"
            }

        21
            {
                log-info "$($machine) return:invalid parameter"
            }

        default
            {
                log-info "$($machine) return:unknown $($result.ReturnValue)"
            }
    }

    return $result.ReturnValue

}


# ---------------------------------------------------------------------------
main