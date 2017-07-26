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

    [parameter(HelpMessage = "Enter user name:")]
    [string] $user,
    [parameter(HelpMessage = "Enter collection:")]
    [string] $collection,
    [parameter(HelpMessage = "Enter connection Broker:")]
    [string] $server = $env:COMPUTERNAME,
    [parameter(HelpMessage = "Enter `$true to prompt / use alternate credentials. Default is `$false")]
    [bool] $useCreds = $false,
    [parameter(HelpMessage = "Enter `$true to store alternate credentials. Default is `$false")]
    [bool] $storeCreds = $false,
    [parameter(HelpMessage = "Select this switch to check for script update")]
    [switch] $getUpdate

)


$ErrorActionPreference = "SilentlyContinue"
$Creds = $null
# if storing creds, password will have to be saved one time
$passFile = "securestring.txt" 
$logFile = "rds-upd-mgr.log"
$deploymentReg = "SYSTEM\CurrentControlSet\Control\Terminal Server\ClusterSettings"
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/rds-upd-mgr.ps1"
$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG
$global:broker = [string]::Empty
$global:brokers = @()
$global:updShares = @()
$global:updInfo = @{}
$global:updInfoList = new-object System.Collections.ArrayList

# ---------------------------------------------------------------------------
function main ()
{
    $error.Clear()
    $machines = @()
    $userSessions = @{}

    log-info $MyInvocation.ScriptName
    # run as administrator
    if (!(runas-admin))
    {
        return
    }
    
    if ($getUpdate)
    {
        get-update -updateUrl $updateUrl
    }

    log-info "============================================="
    log-info "Starting: $(get-date)"
    
    $retval

    check-creds

    # look for broker and get machine list
    $machines = @(get-machines -server $server)
    
    # get list of users for upd's using sid from upd name
    foreach ($upd in get-upds -shares $global:updShares)
    {
        if ([string]::IsNullOrEmpty($upd) -or !$upd.Contains("UVHD-")) 
        {
            continue
        }

        $sid = [IO.Path]::GetFileNameWithoutExtension($upd).Replace("UVHD-", "")
        $userObj = ([wmi]"Win32_SID.SID='$($sid)'")

        $info = @{}
        $info.File = $upd
        $info.InUse = is-fileLocked -file $upd
        $info.InSession = $false
        $info.DiskAttached = $false
        $info.Server = ""
        $info.Sid = $userObj.Sid
        $info.User = $userObj.AccountName
        $info.Domain = $userObj.ReferencedDomainName

        $global:updInfo.Add($info.Sid, $info)
    }

    $global:updInfo.Values | Out-GridView

    # get list of sessions active, disconnected, connecting 

    foreach ($machine in $machines)
    {
        
        manage-wmiExecute -command $command -machine $machine
        $users = enumerate-users -machine $rdmachine
        $userSids = enumerate-sids -users $users

        #$userSessions.Add(
        enumerate-drives - machine $rdmachine
    }

    
    
    log-info "Finished"

}

#----------------------------------------------------------------------------
function check-creds()
{
    if ($useCreds)
    {
        if ((test-path $passFile) -and $storeCreds)
        {

            $password = cat $passFile | convertto-securestring
            $Creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password

        }
        elseif ($storeCreds)
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

}


#----------------------------------------------------------------------------
function get-machines($server)
{
    $machines = @($server)
    if (!(get-service -DisplayName 'Remote Desktop Connection Broker' -ErrorAction SilentlyContinue))
    {
        log-info "$($server) is not a connection broker. trying to find broker."
        $global:brokers = @((read-reg -machine $server -hive $HKLM -key $deploymentReg -value "SessionDirectoryLocation").Split(';'))

        if ($global:brokers.Count -gt 0 -and ![string]::IsNullOrEmpty($global:brokers[0]))
        {
            $global:broker = $global:brokers[0]
        }
        else
        {
            log-info "unable to find broker. exit"
            exit
        }

        # look for upd share in reg in case it rds. only cb can query for upd via ps
        $global:updShares = @(read-reg -machine $server -hive $HKLM -key $deploymentReg -value "UvhdShareUrl")

        if ($global:updShares.Count -lt 1)
        {
            log-info "server is part of rds deployment, but does not have upd configured. exiting"
            exit
        }
        
    }
    else
    {
        log-info "$($server) is a connection broker."
        $global:brokers = get-rdserver -ConnectionBroker $global:broker -Role RDS-CONNECTION-BROKER
        $global:broker = $server

        foreach ($farmSettings in ((Get-WmiObject -Namespace root\cimv2\terminalservices -Class Win32_RDCentralPublishedFarm).VmFarmSettings))
        {
            if ([string]::IsNullOrEmpty($farmSettings))
            {
                continue
            }

            #$config = (Get-RDSessionCollectionConfiguration -CollectionName $collection)
            $pattern = 'name="UvhdProfRoamingEnabled" value="True"'
            if ([regex]::IsMatch($farmSettings, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase))
            {
                $pattern = 'name="UvhdShareUrl" value="(.+?)"'
                $match = [regex]::Match($farmSettings, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $global:updShares.Add($match.Groups[1].Value)
            }
        }
    }


    #make sure it is active broker
    $ha = Get-RDConnectionBrokerHighAvailability -ConnectionBroker $global:broker
    if ($ha -ne $null)
    {
        log-info $ha
        $global:broker = $ha.ActiveManagementServer
    }

    
    try
    {
        
        # get rdsh machines
        $machines = (Get-RDServer -ConnectionBroker $global:broker -Role RDS-RD-SERVER).Server
        if ($machines -ne $null)
        {
            foreach ($machine in $machines)
            {
                log-info $machine
            }

            #            $result = Read-Host "do you want to collect data from entire deployment? [y:n]"
            #            if([regex]::IsMatch($result, "y",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
            #            {
            #                log-info "adding rds collection machines"
            #                 return $machines
            #           }
            #            else
            #            {
            #                return $server
            #            }
        }
    }
    catch 
    {
        log-info "Exception reading machines from broker: $($error)"
        $error.Clear()
    }

    return $machines
}

#----------------------------------------------------------------------------
function get-upds([string[]] $shares)
{
    $list = new-object System.Collections.ArrayList
    foreach ($share in $shares)
    {
        try
        {
            $list.AddRange([IO.Directory]::GetFiles($share, "*.vhdx", [IO.SearchOption]::TopDirectoryOnly))
        }
        catch
        {
            log-info "Exception querying upd share: $($share): $($error)"
            $error.Clear()
            continue
        }
    }

    return , $list
}

#----------------------------------------------------------------------------
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

#----------------------------------------------------------------------------
function log-info($data)
{
    if ($data.ToString().ToLower().StartsWith("error"))
    {
        $ForegroundColor = "Yellow"
    }
    elseif ($data.ToString().ToLower().StartsWith("fail"))
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
        if (![string]::IsNullOrEmpty($logFile))
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

    if ($wait -and !$process.HasExited)
    {

        if ($process.StandardOutput.Peek() -gt -1)
        {
            $stdOut = $process.StandardOutput.ReadToEnd()
            log-info $stdOut
       }


        if ($process.StandardError.Peek() -gt -1)
        {
            $stdErr = $process.StandardError.ReadToEnd()
            log-info $stdErr
            $Error.Clear()
        }
            
    }
    elseif ($wait)
    {
        log-info "Error:Process ended before capturing output."
    }
    

    
    $exitVal = $process.ExitCode

    log-info "Running process exit $($processName) : $($exitVal)"
    $Error.Clear()

    return $stdOut
}

# ---------------------------------------------------------------------------
function manage-wmiExecute([string] $command, [string] $machine)
{
    log-info "wmiExecute: $($machine) : $($command) : $($workingDir)"
    # $wmi = new-object System.Management.ManagementClass "\\$($machine)\Root\cimv2:Win32_Process" 
    # $result = $wmi.Create($command)
    if ($useCreds)
    {
        $result = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList ($command, $workingDir) -Credential $Creds -ComputerName $computer
    }
    else
    {
        $result = Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList ($command, $workingDir) -ComputerName $computer
    }
    
    switch ($result.ReturnValue)
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
function read-reg($machine, $hive, $key, $value, $subKeySearch = $true)
{
    $retVal = new-object Text.StringBuilder
    
    if ([string]::IsNullOrEmpty($value))
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
        
        for ($i = 0; $i -lt $sNames.count; $i++)
        {
            if (![string]::IsNullOrEmpty($value) -and $sNames[$i] -inotlike $value)
            {
                continue
            }

            switch ($sTypes[$i])
            {
                # REG_SZ 
                1
                { 
                    $keyValue = $reg.GetStringValue($hive, $key, $sNames[$i]).sValue
                    if ($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    }
                }
                
                # REG_EXPAND_SZ 
                2
                {
                    $keyValue = $reg.GetExpandStringValue($hive, $key, $sNames[$i]).sValue
                    if ($enumValue)
                    {
                        return $keyValue
                    }                    
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }            
                
                # REG_BINARY 
                3
                { 
                    $keyValue = (($reg.GetBinaryValue($hive, $key, $sNames[$i]).uValue) -join ',')
                    if ($enumValue -and $displayBinaryBlob)
                    {
                        return $keyValue
                    }
                    elseif ($displayBinaryBlob)
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
                4
                { 
                    $keyValue = $reg.GetDWORDValue($hive, $key, $sNames[$i]).uValue
                    if ($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)")
                    } 
                }
                
                # REG_MULTI_SZ 
                7
                {
                    $keyValue = (($reg.GetMultiStringValue($hive, $key, $sNames[$i]).sValue) -join ',')
                    if ($enumValue)
                    {
                        return $keyValue
                    }
                    else 
                    {
                        [void]$retval.AppendLine("$($sNames[$i]):$($keyValue)") 
                    }
                }

                # REG_QWORD
                11
                { 
                    $keyValue = $reg.GetQWORDValue($hive, $key, $sNames[$i]).uValue
                    if ($enumValue)
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
        
        if ([string]::IsNullOrEmpty($value) -and $subKeySearch)
        {
            
            foreach ($subKey in $reg.EnumKey($hive, $key).sNames)
            {
                if ([string]::IsNullOrEmpty($subKey))
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
function get-update($updateUrl)
{
    try 
    {
        # will always update once when copying from web page, then running -getUpdate due to CRLF diff between UNIX and WINDOWS
        # github can bet set to use WINDOWS style which may prevent this
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl
        $gitClean = [regex]::Replace($git, '\W+', "")
        $fileClean = [regex]::Replace(([IO.File]::ReadAllBytes($MyInvocation.ScriptName)), '\W+', "")

        if (([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            log-info "updating new script"
            [IO.File]::WriteAllText($MyInvocation.ScriptName, $git)
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

# ---------------------------------------------------------------------------
function runas-admin()
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
        log-info "please restart script as administrator. exiting..."
        return $false
    }

    return $true
}

# ---------------------------------------------------------------------------

main