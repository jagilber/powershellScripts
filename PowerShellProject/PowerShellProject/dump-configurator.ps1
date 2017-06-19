<#  
.SYNOPSIS  
    #DRAFT# powershell script to configure dump configuration settins across multiple machines

.DESCRIPTION  
    using wmi, reg, and file objects, this powershell script will read and configure memoery dump options
 
.NOTES  
   File Name  : dump-configurator.ps1
   Version    : 
   History    : 161117 original


.EXAMPLE  
    .\dump-configurator.ps1 -dumpType complete -machines server1,server2
    query azure rm for all resource groups with ip name containing 'GWPIP' by default.
 
.PARAMETER dumpType
    type of dump, mini, kernel, complete, auto

.PARAMETER machines
    comma separated list of machines to configure

.PARAMETER restart
    switch to optionally restart machine after configuration

.PARAMETER dumpFile
    switch to optionally restart machine after configuration
#>  

param(
    [Parameter(Mandatory=$false)]
    [switch]$dumpType,
    [Parameter(Mandatory=$false)]
    [string[]]$machines = ".",
    [Parameter(Mandatory=$false)]
    [string]$dumpFile= "c:\windows\memory.dmp",
    [Parameter(Mandatory=$false)]
    [switch]$restart=$false
)

$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG

# variables
$logFile = "$($MyInvocation.ScriptName).txt"


# ----------------------------------------------------------------------------------------------------------------
function main ()
{
    runas-admin
    get-workingDirectory
    
    # get machine list

    # query current settings

    # verify new settings 

    # modify settings

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
function log-info($data)
{
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    if([regex]::IsMatch($data.ToLower(),"error|exception|fail|warning"))
    {
        write-host $data -foregroundcolor Yellow
    }
    elseif([regex]::IsMatch($data.ToLower(),"running"))
    {
       write-host $data -foregroundcolor Green
    }
    elseif([regex]::IsMatch($data.ToLower(),"job completed"))
    {
       write-host $data -foregroundcolor Cyan
    }
    elseif([regex]::IsMatch($data.ToLower(),"starting"))
    {
       write-host $data -foregroundcolor Magenta
    }
    else
    {
        Write-Host $data
    }

    try
    {
        $ret = out-file -Append -InputObject $data -FilePath $logFile
    }
    catch
    {
        write-host "log-info:exception: $($error)"
        $error.Clear()
    }
}


# ----------------------------------------------------------------------------------------------------------------
function read-reg($machine, $hive, $key, $value, $subKeySearch = $true)
{

    $retVal = new-object Text.StringBuilder
    
    if([string]::IsNullOrEmpty($value))
    {
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key)")
        $enumValue = $false
    }
    else
    {
        log-info "-----------------------------------------"
        log-info "enumerating $($key) for value $($value)"
        $enumValue = $true
    }
    
    try
    {
        $reg = [wmiclass]"\\$($machine)\root\default:StdRegprov"
        $sNames = $reg.EnumValues($hive, $key).sNames
        $sTypes = $reg.EnumValues($hive, $key).Types
        
        for($i = 0; $i -lt $sNames.count; $i++)
        {
            if(![string]::IsNullOrEmpty($value) -and $sNames[$i] -inotlike $value)
            {
                continue
            }

            switch ($sTypes[$i])
            {
                # REG_SZ 
                1{ 
                    $keyValue = $reg.GetStringValue($hive, $key, $sNames[$i]).sValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    }
                }
                
                # REG_EXPAND_SZ 
                2{
                    $keyValue = $reg.GetExpandStringValue($hive, $key, $sNames[$i]).sValue
                    if($enumValue)
                    {
                        return $keyValue
                    }                    
                    else 
                    {
                         [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }            
                
                # REG_BINARY 
                3{ 
                    $keyValue = (($reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue) -join ',')
                    if($enumValue -and $displayBinaryBlob)
                    {
                        return $keyValue
                    }
                    elseif($displayBinaryBlob)
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    }
                    else
                    {
                        $blob = $reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue
                        [void]$retval.AppendLine("$($sNames[$i]):(Binary Blob (length:$($blob.Length)))")
                    }
                }
                
                # REG_DWORD 
                4{ 
                    $keyValue = $reg.GetDWORDValue($hive, $key, $sNames[$i]).uValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    } 
                }
                
                # REG_MULTI_SZ 
                7{
                    $keyValue = (($reg.GetMultiStringValue($hive, $key, $sNames[$i]).sValue) -join ',')
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }

                # REG_QWORD
                11{ 
                    $keyValue = $reg.GetQWORDValue($hive, $key, $sNames[$i]).uValue
                    if($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    } 
                }
                
                # ERROR
                default { [void]$retval.AppendLine("unknown type") }
            }
        }
        
        if([string]::IsNullOrEmpty($value) -and $subKeySearch)
        {
            
            foreach($subKey in $reg.EnumKey($hive, $key).sNames)
            {
                if([string]::IsNullOrEmpty($subKey))
                {
                    continue
                }
                
                [void]$retval.AppendLine((read-reg -machine $machine -hive $hive -key "$($key)\$($subkey)"))
            }
        }
        

    }
    catch
    {
        #log-info "read-reg:exception $($error)"
        $error.Clear()
        return 
    }

    return $retVal.toString()
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    $Error.Clear()
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = !$wait
    $process.StartInfo.RedirectStandardOutput = $wait
    $process.StartInfo.RedirectStandardError = $wait
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $wait
    $process.StartInfo.WorkingDirectory = get-location
    $process.StartInfo.ErrorDialog = $true
    $process.StartInfo.ErrorDialogParentHandle = ([Diagnostics.Process]::GetCurrentProcess()).Handle
    $process.StartInfo.LoadUserProfile = $false
    $process.StartInfo.WindowStyle = [Diagnostics.ProcessWindowstyle]::Normal


 
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
function manage-wmiExecute([string] $command, [string] $workingDir, [string] $machine)
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

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    write-verbose "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        if(!$noretry)
        { 
            write-host "restarting script as administrator. exiting..."
            Write-Host "run-process -processName "powershell.exe" -arguments $($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
            run-process -processName "powershell.exe" -arguments "$($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
       }
       
       exit 1
   }
    write-verbose "running as admin"
}

# ----------------------------------------------------------------------------------------------------------------

main