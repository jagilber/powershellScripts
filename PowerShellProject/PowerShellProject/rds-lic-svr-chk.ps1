<#  
.SYNOPSIS  
    powershell script to enumerate license server configuration and connectivity for remote desktop services (RDS).
    can be run from rdsh server or license server
    
.DESCRIPTION  
    This script will enumerate license server configuration off of an RDS server. it will check the known registry locations
    as well as run WMI tests against the configuration. a log file named rds-lic-svr-chk.txt will be generated that should
    be uploaded to support.
    Tested on windows 2008 r2 and windows 2012 r2
 
.NOTES  
   File Name  : rds-lic-svr-chk.ps1  
   Author     : jagilber
   Version    : 170605 -notmatch on licserver list check
   History    : 
                170525 fixed logging
                170519 fixed named pipe job not being removed

.EXAMPLE  
    .\rds-lic-svr-chk.ps1
    query for license server configuration and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -licServer rds-lic-1
    query for license server rds-lic-1 and use wmi to test functionality

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -getUpdate

.EXAMPLE  
    .\rds-lic-svr-chk.ps1 -runAsNetworkService -checkUser contoso\jagilber 

.PARAMETER checkUser
    If specified, will attempt to query msts license attributes from user account: domain\user

.PARAMETER getUpdate
    If specified, will download latest version of script and replace if different.

.PARAMETER licServer
    If specified, all wmi checks will use this value for license server, else it will use enumerated list.

.PARAMETER logFile
    If specified, will use path specified for log file

.PARAMETER rdshServer
    If specified, all wmi checks will use this server for rdsh server, else will use current machine.

.PARAMETER runAsNetworkService
    If specified, will ask to download psexec if not exists, will start psexec as network service, and will rerun script in that session.
    this is useful as 'network service' is how the rdsh server and license server communicate (as themselves). 
    this may show issues where running under logged on credentials may not.

.PARAMETER enumCals
    If specified, User / Device cal information will be enumerated as well as license report information

#>  

Param(
    [string] $checkUser = "",
    [switch] $getUpdate,
    [string] $licServer = "",    
    [string] $logFile = "rds-lic-svr-chk.txt",
    [string] $rdshServer = $env:COMPUTERNAME,
    [switch] $runAsNetworkService,
    [switch] $enumCals
)

clear-Host
$error.Clear()
$ErrorActionPreference = "SilentlyContinue"
$licServers = @()
$licServersList = @{}
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rds-lic-svr-chk.ps1"
$HKCR = 2147483648 #HKEY_CLASSES_ROOT
$HKCU = 2147483649 #HKEY_CURRENT_USER
$HKLM = 2147483650 #HKEY_LOCAL_MACHINE
$HKUS = 2147483651 #HKEY_USERS
$HKCC = 2147483653 #HKEY_CURRENT_CONFIG
$displayBinaryBlob = $false
$lsDiscovered = $false
$isLicServer = $false
$isRdshServer = $false
$licenseConfigSource = "not configured"
$licenseMode = 0
$hasX509 = $false

# ----------------------------------------------------------------------------------------------------------------
function main()
{ 
    get-workingDirectory

    if (!$logFile.Contains("\"))
    {
        $logFile = "$(Get-Location)\$($logFile)"
    }                                       

    $MyInvocation.ScriptName
    # run as administrator
    if (!(runas-admin))
    {
        return
    }
    
    if ($getUpdate)
    {
        get-update -updateUrl $updateUrl
    }

    if ($runAsNetworkService)
    {
        $psexec = get-sysInternalsUtility -utilityName "psexec.exe"
        if (![string]::IsNullOrEmpty($psexec))
        {
            run-process -processName $($psexec) -arguments "-accepteula -i -u `"nt authority\network service`" cmd.exe /c powershell.exe -noexit -executionpolicy Bypass -file $($MyInvocation.ScriptName) -checkUser `"$($checkUser)`" -logFile `"$($logFile)`" -licServer `"$($licServer)`" -rdshServer `"$($rdshServer)`"" -wait $false
            return
        }
        else
        {
            log-info "unable to download utility. exiting"
            return
        }
    }

    if (![string]::IsNullOrEmpty($licServer))
    {
        $licServers = @($licServer)
    }

    log-info "-----------------------------------------"
    log-info "OS $($rdshServer)"
    log-info "-----------------------------------------"
    $osVersion = read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value CurrentVersion
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName | Out-String)

    log-info "-----------------------------------------"
    log-info "INSTALLED FEATURES $($rdshServer)"
    log-info "-----------------------------------------"
    
    $features = Get-WindowsFeature -ComputerName $rdshServer | Where-Object Installed -eq $true
    log-info ($features | Out-String)

    if ($features.Name.Contains("RDS-RD-Server"))
    {
        $isRdshServer = $true
    }

    if ($features.Name.Contains("RDS-Licensing"))
    {
        $isLicServer = $true
    }

    log-info "-----------------------------------------"
    log-info "EVENTS $($rdshServer)"
    log-info "-----------------------------------------"

    log-info (Get-EventLog -LogName System -Source TermService -Newest 10 -ComputerName $rdshServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error", "Warning"))

    log-info "-----------------------------------------"
    log-info "REGISTRY $($rdshServer)"
    log-info "-----------------------------------------"

    if ($rdshServer -ilike $env:COMPUTERNAME -and $osVersion -gt 6.1) # does not like 2k8
    {
        log-info (get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Audit | Format-List * | Out-String)
        log-info (get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM" -Audit | Format-List *| Out-String)
        log-info (get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod" -Audit | Format-List *| Out-String)
    }
    
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server' -subKeySearch $false)
    $hasX509 = (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' -value "X509 Certificate").Length -gt 0
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' | Out-String)
    
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\TermServLicensing' | Out-String)
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' -subKeySearch $false | Out-String)
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers' | Out-String)
    log-info (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' | Out-String)
    
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting $($rdshServer)"
    log-info "-----------------------------------------"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting -ComputerName $rdshServer
    log-info ($rWmi | Out-String)

    #lsdiag uses this to determine if app server or admin server
    if ($rWmi.TerminalServerMode -eq 1)
    {
        $isRdshServer = $true
        log-info "TerminalServerMode:1 == Remote Desktop Session Host"
    }
    else
    {
        $isRdshServer = $false
        log-info "TerminalServerMode:$($rWmi.TerminalServerMode) (NOT a Remote desktop Session Host)"
    }
    
    # lsdiag uses licensingmode from rcm when not overriden in policy
    # todo: need to verify if same is true when in collection and when 'centrallicensing' presumably when configuring in gui in 2012
    
    # lsdiag calls this
    log-info "-----------------------------------------"
    log-info "Win32_TerminalServiceSetting::FindLicenseServers()"
    log-info "-----------------------------------------"

    $lsList = $rWmi.FindLicenseServers().LicenseServersList
    
    foreach ($ls in $lsList)
    {
        #lsdiag uses this
        if (![string]::IsNullOrEmpty($ls.LicenseServer))
        {
            $lsDiscovered = $true
        }

        log-info "LicenseServer:$($ls.LicenseServer)"
        log-info "HowDiscovered:$(if($ls.HowDiscovered) { "Manual" } else { "Auto" })"
        log-info "IsAdminOnLS:$($ls.IsAdminOnLS)"
        log-info "IsLSAvailable:$($ls.IsLSAvailable)"
        log-info "IssuingCals:$($ls.IssuingCals)"
        log-info "-----------------------------------------"
    }

    log-info "-----------------------------------------"
    log-info "Win32_TSDeploymentLicensing $($rdshServer)"
    log-info "-----------------------------------------"
    
    $rWmiL = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TSDeploymentLicensing -ComputerName $rdshServer
    log-info ($rWmiL | Out-String)
    
    log-info "-----------------------------------------"
    log-info "checking wmi for lic server"
    $tempServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    $licMode = $rWmi.LicensingType
    log-info "wmi lic servers: $($tempServers) license mode: $($licMode)"
    
    if ($tempServers.Length -gt 0)
    {
        $licenseConfigSource = 'wmi'
    }

    $licenseMode = $licMode    
    
    if ($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    log-info "-----------------------------------------"
    log-info "checking gpo for lic server"
    $tempServers = @(([string](read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicenseServers')).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicensingMode')
    log-info "gpo lic servers: $($tempServers) license mode: $($licMode)"

    if ($rWmi.PolicySourceLicensingType)
    {
        $licenseConfigSource = 'policy'
        $licenseMode = $licMode    
    }
    
    if ([string]::IsNullOrEmpty($licServer) -and ($rWmi.PolicySourceConfiguredLicenseServers -or $rWmi.PolicySourceDirectConnectLicenseServers))
    {
        $licServers = $tempServers;        
    }
    
    if ($rdshServer -ilike $env:COMPUTERNAME)
    {
        log-info "-----------------------------------------"
        log-info "checking local powershell for license server"
        $tempServers = @(([string]((Get-RDLicenseConfiguration).LicenseServer)).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
        $licMode = (Get-RDLicenseConfiguration).Mode
        log-info "powershell license servers: $($tempServers) license mode: $($licMode)"

        if ($tempServers.Length -gt 0)
        {
            $licenseConfigSource = 'powershell/gui'
        }
    }

    if ($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
    
    if ($licenseMode -eq 0)
    {
        $licenseMode = $licMode
    }

    if (![string]::IsNullOrEmpty($checkUser))
    {
        log-info "-----------------------------------------"
        check-user -user $checkUser
        log-info "-----------------------------------------"
    }
 
    if ($licServers.Length -lt 1)
    {
        log-info "license server has not been configured for remote desktop services for this server!"
    }
    else
    {
        $licCheck = $true
        foreach ($server in $licServers)
        {
            # issue where server name has space in front but not sure why so adding .Trim() for now
            if ($server -ne $server.Trim())
            {
                log-info "warning:whitespace characters on server name"    
            }

            $licServersList.Add($server.Trim(), (check-licenseServer -licServer $server.Trim()))
        }
    }

    # show license info if this server is a license server
    if ($isLicServer -and ($licServersList.Keys -notmatch $rdshServer))
    {
        $licServersList.Add($rdshServer, (check-licenseServer -licServer $rdshServer))
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
    
    log-info "-----------------------------------------"
    log-info "*** SUMMARY ***"
    log-info "server $($rdshServer) is rdsh server? $($isRdshServer)"
    log-info "server $($rdshServer) is license server? $($isLicServer)"
    log-info "license server info:"

    foreach ($serverInfo in $licServersList.GetEnumerator())
    {
        log-info "license server name: $($serverInfo.Key)"
        $serverInfo.Value.GetEnumerator() | sort-object Name | Format-Table
    }

    switch ($licenseMode)
    {
        0
        { 
            $modeString = "0 (should not be set to this!)" 
        }
        1
        { 
            $modeString = "Personal Desktop (admin mode 2 session limit)."

            if ($isrdshServer)
            {
                $modeString += " (should not be set to this!)"
            }
        }
        2
        { 
            $modeString = "Per Device"
        }
        4
        { 
            $modeString = "Per User"
        }
        5
        { 
            $modeString = "Not configured"

            if ($isRdshServer)
            {
                $modeString += " (should not be set to this!)"
            }
        }

        default { $modeString = "error: $($licenseMode)" }
    }
    $configuredCorrectly = $false

    if ($isRdshServer)
    {
        $configuredCorrectly = ($licCheck -or $lsDiscovered) -and $hasX509 -and ($licenseMode -eq 2 -or $licenseMode -eq 4) `
            -and $licServersList.Values.TsToLsConnectivityStatus -imatch "LS_CONNECTABLE_VALID"
    }
    else
    {
        $configuredCorrectly = "n/a (not an rdsh server)"    
    }

    log-info "server $($rdshServer) current license mode: $($modeString)"
    log-info "server $($rdshServer) current license config source: $($licenseConfigSource)"
    log-info "server $($rdshServer) currently configured correctly for at least one license server? $($configuredCorrectly)"    
    log-info "server $($rdshServer) ever connected to license server (has x509 cert)? $($hasX509)"
    log-info "server $($rdshServer) Grace period days left? $($daysLeft)"
    log-info "`tNOTE: The Grace period is for a license 'grace' during the first 120 days after RDSH role is installed."
    log-info "`t During this time, the RDSH server will allow connections regardless if licensed or not."
    log-info "`t The internal Grace counter will ALWAYS count down to 0."
    log-info "`t This is regardless of RDSH server connectivity status to license server."

    log-info "-----------------------------------------"
    log-info "log file located here: $([IO.Path]::GetFullPath($logFile))"
    . $([IO.Path]::GetFullPath($logFile))
    log-info "finished"

}
# ----------------------------------------------------------------------------------------------------------------

function check-licenseServer([string] $licServer)
{
    [bool] $retVal = $true
    $licServerResult = @{}
    $licServerResult.OS = $Null
    $licServerResult.ServiceStatus = $Null
    $licServerResult.LicenseServerActivated = $Null
    $licServerResult.LicenseServerId = $null
    $licServerResult.CanPingLicenseServer = $null
    $licServerResult.CanAccessLicenseServer = $null
    $licServerResult.CanAccessNamedPipe = $null
    $licServerResult.CanAccessRpcEpt = $null
    $licServerResult.TsToLsConnectivityStatus = $null
    $licServerResult.Result = $null
    $licServerResult.KeyPacksCount = 0
    $licServerResult.CalsPerUserTotal = 0
    $licServerResult.CalsPerUserAvailable = 0
    $licServerResult.CalsPerUserUsed = 0
    $licServerResult.CalsPerUserTotal = 0
    $licServerResult.CalsPerUserAvailable = 0
    $licServerResult.CalsPerUserUsed = 0


    log-info "-----------------------------------------"
    log-info "-----------------------------------------"
    log-info "checking license server: '$($licServer)'"
    log-info "-----------------------------------------"

    log-info "-----------------------------------------"
    log-info "OS $($licServer)"
    log-info "-----------------------------------------"
     
    $licServerResult.OS = (read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName)
    log-info "$($licServerResult.OS)"
    
    log-info "-----------------------------------------"
    log-info "SERVICE $($licServer)"
    log-info "-----------------------------------------"
    
    $licServerResult.ServiceStatus = (Get-Service -Name TermServLicensing -ComputerName $licServer -ErrorAction SilentlyContinue).Status
    log-info "License Server Service status: $($licServerResult.ServiceStatus)"

    log-info "-----------------------------------------"
    log-info "EVENTS $($licServer)"
    log-info "-----------------------------------------"

    log-info (Get-EventLog -LogName "System" -Source "TermServLicensing" -Newest 10 -ComputerName $licServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error", "Warning") | fl * | out-string)

    if (($rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseServer -ComputerName $licServer))
    {
        log-info "-----------------------------------------"
        log-info "Win32_TSLicenseServer $($licServer)"
        log-info "-----------------------------------------"
        log-info "$($rWmiLS | fl * | out-string)"

        $wmiClass = ([wmiclass]"\\$($licServer)\root\cimv2:Win32_TSLicenseServer")
        
        $licServerResult.LicenseServerActivated = $wmiClass.GetActivationStatus().ActivationStatus
        log-info "activation status: $($licServerResult.LicenseServerActivated) (0 = activated, 1 = not activated)"
        $licServerResult.LicenseServerActivated = ![bool]$wmiClass.GetActivationStatus().ActivationStatus

        $licServerResult.LicenseServerId = $wmiClass.GetLicenseServerID().sLicenseServerId
        log-info "license server id: $($licServerResult.LicenseServerId)"
        log-info "is ls in ts ls group in AD: $($wmiClass.IsLSinTSLSGroup([System.Environment]::UserDomainName).IsMember)"
        log-info "is ls on dc: $($wmiClass.IsLSonDC().OnDC)"
        log-info "is ls published in AD: $($wmiClass.IsLSPublished().Published)"
        log-info "is ls registered to SCP: $($wmiClass.IsLSRegisteredToSCP().Registered)"
        log-info "is ls security group enabled: $($wmiClass.IsLSSecGrpGPEnabled().Enabled)"
        log-info "is ls secure access allowed: $($wmiClass.IsSecureAccessAllowed($rdshServer).Allowed)"
        log-info "is rds in tsc group on ls: $($wmiClass.IsTSinTSCGroup($rdsshServer).IsMember)"
    
        $dbPath = "\\$licServer\admin$\system32\lserver"
        if (test-path $dbPath)
        {
            log-info "-----------------------------------------"
            log-info "License Database $($licServer)"
            log-info "-----------------------------------------"

            log-info "$(Get-ChildItem -Path $dbPath -Recurse | out-string)"
            log-info "$(icacls $dbPath /T /C | out-string)"

        }

        log-info "-----------------------------------------"
        log-info "Win32_TSLicenseKeyPack $($licServer)"
        log-info "-----------------------------------------"
        $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseKeyPack -ComputerName $licServer
        log-info "$($rWmiLS | fl * | out-string)"
        $licServerResult.KeyPacksCount = ($rWmiLS | ? TypeAndModel -Cmatch "RDS Per ").Count
        #$licServerResult.CalsPerUserTotal = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").TotalLicenses | measure-object -Sum).Sum
        $licServerResult.CalsPerUserAvailable = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").AvailableLicenses | measure-object -Sum).Sum
        $licServerResult.CalsPerUserUsed = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").IssuedLicenses | measure-object -Sum).Sum 
        $licServerResult.CalsPerUserTotal = $licServerResult.CalsPerUserAvailable + $licServerResult.CalsPerUserUsed
    
        #$licServerResult.CalsPerDeviceTotal = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").TotalLicenses | measure-object -Sum).Sum
        $licServerResult.CalsPerDeviceAvailable = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").AvailableLicenses | measure-object -Sum).Sum
        $licServerResult.CalsPerDeviceUsed = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").IssuedLicenses | measure-object -Sum).Sum
        $licServerResult.CalsPerDeviceTotal = $licServerResult.CalsPerDeviceAvailable + $licServerResult.CalsPerDeviceUsed

        if ($enumCals)
        {
            log-info "-----------------------------------------"
            log-info "Win32_TSIssuedLicense $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSIssuedLicense -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReport $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReport -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReportEntry $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportEntry -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReportFailedPerUserEntry $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportFailedPerUserEntry -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReportFailedPerUserSummaryEntry $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportFailedPerUserSummaryEntry -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReportPerDeviceEntry $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportPerDeviceEntry -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"

            log-info "-----------------------------------------"
            log-info "Win32_TSLicenseReportSummaryEntry $($licServer)"
            log-info "-----------------------------------------"
            $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportSummaryEntry -ComputerName $licServer
            log-info "$($rWmiLS | fl * | out-string)"
        }
    }

    try
    {
        $ret = $rWmi.PingLicenseServer($licServer)
        $licServerResult.CanPingLicenseServer = $true
    }
    catch
    {
        $licServerResult.CanPingLicenseServer = $false
    }

    $retVal = $retVal -band $licServerResult.CanPingLicenseServer
    log-info "Can ping license server? $([bool]$ret)"
 
    $licServerResult.CanAccessLicenseServer = [bool]$rWmi.CanAccessLicenseServer($licServer).AccessAllowed
    $retVal = $retVal -band $licServerResult.CanAccessLicenseServer
    log-info "Can access license server? $($licServerResult.CanAccessLicenseServer)"
 
    # check named pipe
    log-info "checking named pipe HYDRALSPIPE. if script hangs here, there is a problem connecting to pipe."
    $job = Start-Job -Name "namedpipecheck" -ScriptBlock {
        param($licServer)
        try
        {
            $clientPipe = New-Object IO.Pipes.NamedPipeClientStream($licServer, "HYDRALSPIPE", [IO.Pipes.PipeDirection]::InOut)
            $clientPipe.Connect()
            $pipeReader = New-Object IO.StreamReader($clientPipe)
            log-info "job:Can access named pipe? true"
        }
        catch
        {
            log-info "job:Can access named pipe? false"
        }
        finally
        {
            $pipeReader.Dispose()
            $clientPipe.Dispose()
        }
    } -ArgumentList ($licServer)

    $count = 0
    while ($job -and $job.State -ne "Completed" -and $count -lt 5)
    {
        $jobInfo = get-job -Name $job.Name
        receive-job -Job $jobInfo | Out-Null
        $count++
        start-sleep -Seconds 1
    }

    if ($count -eq 5)
    {
        # pipe failed.
        $licServerResult.CanAccessNamedPipe = $false
    }
    else
    {
        $licServerResult.CanAccessNamedPipe = $true
    }

    if ($jobInfo = get-job -Name $job.Name)
    {
        Stop-Job -Job $jobInfo
        Remove-Job -Job $jobInfo -Force
    }

    log-info "Can access named pipe? $($licServerResult.CanAccessNamedPipe)"

    log-info "checking rpc endpoint mapper"

    if ((Test-NetConnection -Port 135 -ComputerName $licServer).TcpTestSucceeded)
    {
        $licServerResult.CanAccessRpcEpt = $true
    }
    else 
    {
        $licServerResult.CanAccessRpcEpt = $false
    }

    log-info "Can access rpc port mapper? $($licServerResult.CanAccessRpcEpt)"

    $ret = $rWmi.GetTStoLSConnectivityStatus($licServer)
    switch ($ret.TsToLsConnectivityStatus)
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
    
    $licServerResult.TsToLsConnectivityStatus = $retName
    $licServerResult.Result = [bool]($retVal -band ($ret.TsToLsConnectivityStatus -eq 9 -or $ret.TsToLsConnectivityStatus -eq 11))
    log-info "license connectivity status: $($licServerResult.Result)"
    
    return $licServerResult
}

# ----------------------------------------------------------------------------------------------------------------
function check-user ([string] $user)
{
    log-info "checking user in AD: $($user)"

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
        $colProplist = "msTSManagingLS", "msTSExpireDate" #"name"

        foreach ($i in $colPropList)
        {
            [void]$objSearcher.PropertiesToLoad.Add($i)
        }

        $colResults = $objSearcher.FindAll()

        if ($colResults.Count -lt 1)
        {
            log-info "unable to find user:$($user)"
            return $false
        }

        foreach ($objResult in $colResults)
        {
            log-info "-----------------------------------------"
            log-info "AD user:$($objresult.Properties["adspath"])"
            log-info "RDS CAL expire date:$($objresult.Properties["mstsexpiredate"])"
            log-info "RDS License Server Identity:$($objresult.Properties["mstsmanagingls"])"
        }
        
        log-info "found user:$($user)"
        return $true
    }
    catch
    {
        log-info "exception trying to find user:$($user)"
        $error.Clear()
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-update($updateUrl)
{
    try 
    {
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
function get-sysInternalsUtility ([string] $utilityName)
{
    try
    {
        $destFile = "$(get-location)\$utilityName"
        
        if (![IO.File]::Exists($destFile))
        {
            $sysUrl = "http://live.sysinternals.com/$($utilityName)"

            log-info "Sysinternals process psexec.exe is needed for this option!" -ForegroundColor Yellow
            if ((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                [void]$webClient.DownloadFile($sysUrl, $destFile)
                log-info "sysinternals utility $($utilityName) downloaded to $($destFile)"
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
        log-info "Exception downloading $($utilityName): $($error)"
        $error.Clear()
        return [string]::Empty
    }
}

# ----------------------------------------------------------------------------------------------------------------
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
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key) for value $($value)")
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
                    if ($enumValue -or $displayBinaryBlob)
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
                
                read-reg -machine $machine -hive $hive -key "$($key)\$($subkey)"
            }
        }

        if ($enumValue)
        {
            # no value
            return $null
        }
        else
        {
            return $retVal.ToString()
        }
    }
    catch
    {
        $error.Clear()
        return 
    }
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
 
    if ($wait -and !$process.HasExited)
    {
 
        if ($process.StandardOutput.Peek() -gt -1)
        {
            $stdOut = $process.StandardOutput.ReadToEnd()
            $stdOut
        }
 
        if ($process.StandardError.Peek() -gt -1)
        {
            $stdErr = $process.StandardError.ReadToEnd()
            $stdErr
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
# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    #$data = "$([DateTime]::Now):$($data)"
    write-host ($data | out-string)
    out-file -Append -InputObject ($data | out-string) -FilePath $logFile
}


# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).Identities.Name -eq "NT AUTHORITY\NETWORK SERVICE")
    {
        return $true
    }
    elseif (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
        log-info "please restart script as administrator. exiting..."
        return $false
    }

    return $true
}

# ----------------------------------------------------------------------------------------------------------------
main
    