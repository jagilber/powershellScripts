<#  
.SYNOPSIS  
    powershell script to enumerate license server connectivity.
    can be used on rdsh server or license server
    
.DESCRIPTION  
    This script will enumerate license server configuration off of an RDS server. it will check the known registry locations
    as well as run WMI tests against the configuration. a log file named rds-lic-svr-chk.txt will be generated that should
    be uploaded to support.
    Tested on windows 2008 r2 and windows 2012 r2
 
.NOTES  
   File Name  : rds-lic-svr-chk.ps1  
   Author     : jagilber
   Version    : 161206 using transcript file for logging to match console
   History    : 
   
.EXAMPLE  
    .\rds-lic-svr-chk.ps1
    query for license server configuration and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -licServer rds-lic-1
    query for license server rds-lic-1 and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -getUpdate

.PARAMETER licServer
    If specified, all wmi checks will use this server, else it will use enumerated list.

.PARAMETER rdshServer
    If specified, all wmi checks will use this server for testing connectivity from particular rdsh server.

.PARAMETER getUpdate
    If specified, will download latest version of script and replace if different.
#>  

Param(
 
    [parameter(HelpMessage="Enter license server name:")]
    [string] $licServer,    
    [parameter(HelpMessage="Enter rdsh server name:")]
    [string] $rdshServer = $env:COMPUTERNAME,
    [parameter(HelpMessage="Use to check for script update:")]
    [switch] $getUpdate,
    [parameter(HelpMessage="Use to run script as network service:")]
    [switch] $runAsNetworkService,
    [parameter(HelpMessage="Enter user name to check if per user:")]
    [string] $checkUser
 
    
    )
$error.Clear()
cls 
$ErrorActionPreference = "SilentlyContinue"
$logFile = "rds-lic-svr-chk.txt"
$licServers = @()
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rds-lic-svr-chk.ps1"
$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG
$displayBinaryBlob = $false
$lsDiscovered = $false
$appServer = $false
$licenseModeSource = $null
$licenseMode = 0
$hasX509 = $false

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    Start-Transcript -Path $logFile -Force

    $MyInvocation.ScriptName
    # run as administrator
    if(!(runas-admin))
    {
        return
    }
    
    if($getUpdate)
    {
        get-update -updateUrl $updateUrl
    }

    if($runAsNetworkService)
    {
        $psexec = get-sysInternalsUtility -utilityName "psexec.exe"
        if(![string]::IsNullOrEmpty($psexec))
        {
            run-process -processName $($psexec) -arguments "-accepteula -i -u `"nt authority\network service`" cmd.exe /c powershell.exe -noexit -executionpolicy Bypass -file $($MyInvocation.ScriptName) -checkUser $($env:USERNAME) " -wait $false            
            return
        }
        else
        {
            "unable to download utility. exiting"
            return
        }
    }

    if(![string]::IsNullOrEmpty($checkUser))
    {
        check-user -user $checkUser
    }

    if(![string]::IsNullOrEmpty($licServer))
    {
        $licServers = @($licServer)
    }

    "-----------------------------------------"
    "OS $($rdshServer)"
    "-----------------------------------------"
    $osVersion = read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value CurrentVersion
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName

    "-----------------------------------------"
    "INSTALLED FEATURES $($rdshServer)"
    "-----------------------------------------"
    
    Get-WindowsFeature -ComputerName $rdshServer | ? Installed -eq $true

    "-----------------------------------------"
    "EVENTS $($rdshServer)"
    "-----------------------------------------"

    Get-EventLog -LogName System -Source TermService -Newest 10 -ComputerName $rdshServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    "-----------------------------------------"
    "REGISTRY $($rdshServer)"
    "-----------------------------------------"

    if($rdshServer -ilike $env:COMPUTERNAME -and $osVersion -gt 6.1) # does not like 2k8
    {
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Audit | fl *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM" -Audit | fl *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod" -Audit | fl *
    }
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server' -subKeySearch $false
    $hasX509 = (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' -value "X509 Certificate").Length -gt 0
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' 
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\TermServLicensing'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' -subKeySearch $false
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    
    "-----------------------------------------"
    "Win32_TerminalServiceSetting $($rdshServer)"
    "-----------------------------------------"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting -ComputerName $rdshServer
    $rWmi
    
    # lsdiag uses licensingmode from rcm when not overriden in policy
    # todo: need to verify if same is true when in collection and when 'centrallicensing' presumably when configuring in gui in 2012
    
    # lsdiag calls this
    "-----------------------------------------"
    "Win32_TerminalServiceSetting::FindLicenseServers()"
    "-----------------------------------------"

    $lsList = $rWmi.FindLicenseServers().LicenseServersList

    
    foreach($ls in $lsList)
    {
        #lsdiag uses this
        if(![string]::IsNullOrEmpty($ls.LicenseServer))
        {
            $lsDiscovered = $true
        }

        #lsdiag uses this to determine if app server or admin server
        if($rWmi.TerminalServerMode -eq 1)
        {
            $appServer = $true
        }
    
        "LicenseServer:$($ls.LicenseServer)"
        "HowDiscovered:$(if($ls.HowDiscovered) { "Manual" } else { "Auto" })"
        "IsAdminOnLS:$($ls.IsAdminOnLS)"
        "IsLSAvailable:$($ls.IsLSAvailable)"
        "IssuingCals:$($ls.IssuingCals)"
        "-----------------------------------------"
    }

    "-----------------------------------------"
    "Win32_TSDeploymentLicensing $($rdshServer)"
    "-----------------------------------------"
    
    $rWmiL = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TSDeploymentLicensing -ComputerName $rdshServer
    $rWmiL
    
    "-----------------------------------------"
    "checking wmi for lic server"
    $tempServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    $licMode = $rWmi.LicensingType
    "wmi lic servers: $($tempServers) license mode: $($licMode)"
    
    $licenseModeSource = 'wmi'
    $licenseMode = $licMode    
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    "-----------------------------------------"
    "checking gpo for lic server"
    $tempServers = @(([string](read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicenseServers')).Split(",",[StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicensingMode')
    "gpo lic servers: $($tempServers) license mode: $($licMode)"

    if($rWmi.PolicySourceLicensingType)
    {
        $licenseModeSource = 'policy'
        $licenseMode = $licMode    
    }
    
    if([string]::IsNullOrEmpty($licServer) -and ($rWmi.PolicySourceConfiguredLicenseServers -or $rWmi.PolicySourceDirectConnectLicenseServers))
    {
        $licServers = $tempServers;        
    }
    
    if($rdshServer -ilike $env:COMPUTERNAME)
    {
        "-----------------------------------------"
        "checking local ps for lic server"
        $tempServers = @(([string]((Get-RDLicenseConfiguration).LicenseServer)).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
        $licMode = (Get-RDLicenseConfiguration).Mode
        "ps lic servers: $($tempServers) license mode: $($licMode)"
    }
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
    
    if($licenseMode -eq 0)
    {
        $licenseModeSource = 'powershell'
        $licenseMode = $licMode -band $licMode
    }
 
    if($licServers.Length -lt 1)
    {
        "license server has not been configured!"
    
    }
    else
    {
        $licCheck = $true
        foreach($server in $licServers)
        {
            # issue where server name has space in front but not sure why so adding .Trim() for now
            if($server -ne $server.Trim())
            {
               "warning:whitespace characters on server name"    
            }
        
            $licCheck = $licCheck -band (check-licenseServer -licServer $server.Trim())
        }
    }
    
    try
    {
        $ret = $rWmi.GetGracePeriodDays()
        $daysLeft = $ret.DaysLeft
    }
    catch
    {
        $daysLeft = "NOT_SET"
    }
    
    "-----------------------------------------" 
    # from lsdiag if findlicenseservers returns server and tsappallowlist\licensetype -ne 5 an daysleft > 0
    if($lsDiscovered -and $licCheck -and ($daysLeft -notlike "NOT_SET" -and $daysLeft -gt 0) -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        "Success:$($rdshServer) is connected to a license server. Server is in Grace Period, but this is ok. Days Left: $($daysLeft)"
    }
    elseif($lsDiscovered -and $licCheck -and ($daysLeft -eq 0 -or $daysLeft -eq "NOT_SET") -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        "Success:$($rdshServer) is connected to a license server and is not in grace. ($($daysLeft))"        
    }
    elseif($lsDiscovered -and !$licCheck -and ($daysLeft -notlike "NOT_SET" -and $daysLeft -gt 0) -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        "Warning:$($rdshServer) has connected to a license server. Server is in Grace Period, but server cannot currently connect to a license server. Days Left: $($daysLeft)"
    }
    elseif($lsDiscovered -and !$licCheck -and ($daysLeft -eq 0 -or $daysLeft -eq "NOT_SET") -and $appServer -and ($licenseMode -ne 0 -and $licenseMode -ne 5) -and $hasX509)
    {
        "Warning:$($rdshServer) has connected to a license server and is not in grace but server cannot currently connect to a license server. ($($daysLeft))"        
    }
    elseif(!$lsDiscovered -and $daysLeft -eq 0 -and $appServer -and $hasX509)
    {
        "ERROR:$($rdshServer) has connected to a license server at some point but is NOT in grace and is NOT currently connected to license server. ($($daysLeft))"        
    }
    elseif(!$lsDiscovered -and $daysLeft -eq 0 -and $appServer -and !$hasX509)
    {
        "ERROR:$($rdshServer) is NOT connected to a license server and is NOT in grace. ($($daysLeft))"        
    }
    elseif(!$appServer)
    {
        "ERROR:$($rdshServer) is configured for Remote Administration (2 session limit). ($($daysLeft))"
    }
    else
    {
        "ERROR:Unknown state. ($($daysLeft))"        
    }
 
    switch($licenseMode)
    {
        0 { $modeString = "0 (should not be set to this!)"}
        1 { $modeString = "Personal Desktop (admin mode 2 session limit. should not be set to this if rdsh server!)"}
        2 { $modeString = "Per Device"}
        4 { $modeString = "Per User"}
        5 { $modeString = "Not configured (should not be set to this!)"}
        default { $modeString = "error: $($licenseMode)" }
    }
    
    "current license mode: $($modeString)"
    "current license mode source: $($licenseModeSource)"

    Stop-Transcript 

    "-----------------------------------------"
    "finished" 
    
}
# ----------------------------------------------------------------------------------------------------------------

function check-licenseServer([string] $licServer)
{
    [bool] $retVal = $true
    
    "-----------------------------------------"
    "-----------------------------------------"
    "checking license server: '$($licServer)'"
    "-----------------------------------------" 

    "-----------------------------------------"
    "OS $($licServer)"
    "-----------------------------------------"
     
    read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName
    
    "-----------------------------------------"
    "SERVICE $($licServer)"
    "-----------------------------------------"
    
    "License Server Service status: $((Get-Service -Name TermServLicensing -ComputerName $licServer -ErrorAction SilentlyContinue).Status)"

    "-----------------------------------------"
    "EVENTS $($licServer)"
    "-----------------------------------------"

    Get-EventLog -LogName "System" -Source "TermServLicensing" -Newest 10 -ComputerName $licServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    if(($rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseServer -ComputerName $licServer))
    {
        "-----------------------------------------"
        "Win32_TSLicenseServer $($licServer)"
        "-----------------------------------------"
        $rWmiLS

        $wmiClass = ([wmiclass]"\\$($licServer)\root\cimv2:Win32_TSLicenseServer")
        "activation status: $($wmiClass.GetActivationStatus().ActivationStatus)"
        "license server id: $($wmiClass.GetLicenseServerID().sLicenseServerId)"
        "is ls in ts ls group in AD: $($wmiClass.IsLSinTSLSGroup([System.Environment]::UserDomainName).IsMember)"
        "is ls on dc: $($wmiClass.IsLSonDC().OnDC)"
        "is ls published in AD: $($wmiClass.IsLSPublished().Published)"
        "is ls registered to SCP: $($wmiClass.IsLSRegisteredToSCP().Registered)"
        "is ls security group enabled: $($wmiClass.IsLSSecGrpGPEnabled().Enabled)"
        "is ls secure access allowed: $($wmiClass.IsSecureAccessAllowed($rdshServer).Allowed)"
        "is rds in tsc group on ls: $($wmiClass.IsTSinTSCGroup($rdsshServer).IsMember)"
    }
    
    try
    {
        $ret = $rWmi.PingLicenseServer($licServer)
        $ret = $true
    }
    catch
    {
        $ret = $false
    }
    $retVal = $retVal -band $ret
    "Can ping license server? $([bool]$ret)"
 
    $ret = $rWmi.CanAccessLicenseServer($licServer)
    $retVal = $retVal -band $ret
    "Can access license server? $([bool]$ret.AccessAllowed)"
 
    $ret = $rWmi.GetTStoLSConnectivityStatus($licServer)
    switch($ret.TsToLsConnectivityStatus)
    {
        0 { $retName = "LS_CONNECTABLE_UNKNOWN" }
        1 { $retName = "LS_CONNECTABLE_VALID_WS08R2=1" }
        2 { $retName = "LS_CONNECTABLE_VALID_WS08" }
        3 { $retName = "LS_CONNECTABLE_BETA_RTM_MISMATCH" }
        4 { $retName = "LS_CONNECTABLE_LOWER_VERSION" }
        5 { $retName = "LS_CONNECTABLE_NOT_IN_TSCGROUP" }
        6 { $retName = "LS_NOT_CONNECTABLE" }
        7 { $retName = "LS_CONNECTABLE_UNKNOWN_VALIDITY" }
        8 { $retName = "LS_CONNECTABLE_BUT_ACCESS_DENIED" }
        9 { $retName = "LS_CONNECTABLE_VALID_WS08R2_VDI, R2 with VDI support (SP1 release)" }
        10 { $retName = "LS_CONNECTABLE_FEATURE_NOT_SUPPORTED" }
        11 { $retName = "LS_CONNECTABLE_VALID_LS" }
        default { $retName = "Unknown $($ret.TsToLsConnectivityStatus)" }
    }
    
    $retVal = $retVal -band ($ret.TsToLsConnectivityStatus -eq 9 -or $ret.TsToLsConnectivityStatus -eq 11)
    "license connectivity status: $($retName)"
    
    return $retVal
}

# ----------------------------------------------------------------------------------------------------------------
function check-user ([string] $user)
{
    try
    {
        $strFilter = "(&(objectCategory=User)(samAccountName=$($user)))"

        $objDomain = New-Object System.DirectoryServices.DirectoryEntry

        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher
        $objSearcher.SearchRoot = $objDomain
        $objSearcher.PageSize = 1000
        $objSearcher.Filter = $strFilter
        $objSearcher.SearchScope = "Subtree"

        # lic server user attributes for per user
        $colProplist = "msTSManagingLS","msTSExpireDate" #"name"
        foreach ($i in $colPropList)
        {
            $objSearcher.PropertiesToLoad.Add($i)
        }

        $colResults = $objSearcher.FindAll()

        foreach ($objResult in $colResults)
        {
            "-------------------------------------"
            "AD user:$($objresult.Properties["adspath"])"
            "RDS CAL expire date:$($objresult.Properties["mstsexpiredate"])"
            log-ingo "RDS License Server Identity:$($objresult.Properties["mstsmanagingls"])"
        }
        
        return $true
    }
    catch
    {
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function read-reg($machine, $hive, $key, $value, $subKeySearch = $true)
{
    $retVal = new-object Text.StringBuilder
    
    if([string]::IsNullOrEmpty($value))
    {
        write-host "-----------------------------------------"
        write-host "enumerating $($key)"
        $enumValue = $false
    }
    else
    {
        write-host "-----------------------------------------"
        write-host "enumerating $($key) for value $($value)"
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
        #"read-reg:exception $($error)"
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

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            "updating new script"
            [IO.File]::WriteAllText($MyInvocation.ScriptName, $git)
            "restart to use new script. exiting."
            exit
        }
        else
        {
            "script is up to date"
        }
        
        return $true
        
    }
    catch [System.Exception] 
    {
        "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-sysInternalsUtility ([string] $utilityName)
{
    try
    {
        $destFile = "$(get-location)\$utilityName"
        
        if(![IO.File]::Exists($destFile))
        {
            $sysUrl = "http://live.sysinternals.com/$($utilityName)"

            write-host "Sysinternals process psexec.exe is needed for this option!" -ForegroundColor Yellow
            if((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                $webClient.DownloadFile($sysUrl, $destFile)
                "sysinternals utility $($utilityName) downloaded to $($destFile)"
            }
            else
            {
                return [string]::Empty
            }
        }

        return $destFile
    }
    catch
    {
        "Exception downloading $($utilityName): $($error)"
        $error.Clear()
        return [string]::Empty
    }
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).Identities.Name -eq "NT AUTHORITY\NETWORK SERVICE")
    {
        return $true
    }
    elseif (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       "please restart script as administrator. exiting..."
       return $false
    }

    return $true
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    $Error.Clear()
    "Running process $processName $arguments"
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
            $stdOut
        }
 
 
        if($process.StandardError.Peek() -gt -1)
        {
            $stdErr = $process.StandardError.ReadToEnd()
            $stdErr
            $Error.Clear()
        }
            
    }
    elseif($wait)
    {
        "Error:Process ended before capturing output."
    }
    
 
    
    $exitVal = $process.ExitCode
 
    "Running process exit $($processName) : $($exitVal)"
    $Error.Clear()
 
    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
main

