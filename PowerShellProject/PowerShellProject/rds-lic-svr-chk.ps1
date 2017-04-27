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
   Version    : 170426.2 added calpack info to summary
   History    : 
                170426 fixed issue with x509 and for currently configured showing false when it was supposed to be true
                170425 added rds role check and made summary more descriptive. fixed issue with x509 check

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
#>  

Param(
    [string] $checkUser = "",
    [switch] $getUpdate,
    [string] $licServer = "",    
    [string] $logFile = "rds-lic-svr-chk.txt",
    [string] $rdshServer = $env:COMPUTERNAME,
    [switch] $runAsNetworkService
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

    if(!$logFile.Contains("\"))
    {
        $logFile = "$(Get-Location)\$($logFile)"
    }                                       

    Start-Transcript -Path $logFile -Force

    $MyInvocation.ScriptName
    # run as administrator
    if(!(runas-admin))
    {
        Stop-Transcript 
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
            Stop-Transcript 
            run-process -processName $($psexec) -arguments "-accepteula -i -u `"nt authority\network service`" cmd.exe /c powershell.exe -noexit -executionpolicy Bypass -file $($MyInvocation.ScriptName) -checkUser `"$($checkUser)`" -logFile `"$($logFile)`" -licServer `"$($licServer)`" -rdshServer `"$($rdshServer)`"" -wait $false
            return
        }
        else
        {
            Stop-Transcript 
            write-host "unable to download utility. exiting`r`n"
            return
        }
    }

    if(![string]::IsNullOrEmpty($licServer))
    {
        $licServers = @($licServer)
    }

    write-host "-----------------------------------------`r`n"
    write-host "OS $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $osVersion = read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value CurrentVersion
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName

    write-host "-----------------------------------------`r`n"
    write-host "INSTALLED FEATURES $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"
    
    $features = Get-WindowsFeature -ComputerName $rdshServer | Where-Object Installed -eq $true
    $features

    if($features.Name.Contains("RDS-RD-Server"))
    {
        $isRdshServer = $true
    }

    if($features.Name.Contains("RDS-Licensing"))
    {
        $isLicServer = $true
    }

    write-host "-----------------------------------------`r`n"
    write-host "EVENTS $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"

    Get-EventLog -LogName System -Source TermService -Newest 10 -ComputerName $rdshServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    write-host "-----------------------------------------`r`n"
    write-host "REGISTRY $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"

    if($rdshServer -ilike $env:COMPUTERNAME -and $osVersion -gt 6.1) # does not like 2k8
    {
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Audit | Format-List *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM" -Audit | Format-List *
        get-acl -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod" -Audit | Format-List *
    }
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server' -subKeySearch $false
    $hasX509 = (read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' -value "X509 Certificate").Length -gt 0
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Control\Terminal Server\RCM' 
    
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\TermServLicensing'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' -subKeySearch $false
    read-reg -machine $rdshServer -hive $HKLM -key 'SYSTEM\CurrentControlSet\Services\TermService\Parameters\LicenseServers\SpecifiedLicenseServers'
    read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    
    write-host "-----------------------------------------`r`n"
    write-host "Win32_TerminalServiceSetting $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"
 
    $rWmi = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TerminalServiceSetting -ComputerName $rdshServer
    $rWmi

    #lsdiag uses this to determine if app server or admin server
    if($rWmi.TerminalServerMode -eq 1)
    {
        $isRdshServer = $true
        write-host "TerminalServerMode:1 == Remote Desktop Session Host`r`n"
    }
    else
    {
        $isRdshServer = $false
        write-host "TerminalServerMode:$($rWmi.TerminalServerMode) (NOT a Remote desktop Session Host)`r`n"
    }
    
    # lsdiag uses licensingmode from rcm when not overriden in policy
    # todo: need to verify if same is true when in collection and when 'centrallicensing' presumably when configuring in gui in 2012
    
    # lsdiag calls this
    write-host "-----------------------------------------`r`n"
    write-host "Win32_TerminalServiceSetting::FindLicenseServers()`r`n"
    write-host "-----------------------------------------`r`n"

    $lsList = $rWmi.FindLicenseServers().LicenseServersList
    
    foreach($ls in $lsList)
    {
        #lsdiag uses this
        if(![string]::IsNullOrEmpty($ls.LicenseServer))
        {
            $lsDiscovered = $true
        }

        write-host "LicenseServer:$($ls.LicenseServer)`r`n"
        write-host "HowDiscovered:$(if($ls.HowDiscovered) { "Manual" } else { "Auto" })`r`n"
        write-host "IsAdminOnLS:$($ls.IsAdminOnLS)`r`n"
        write-host "IsLSAvailable:$($ls.IsLSAvailable)`r`n"
        write-host "IssuingCals:$($ls.IssuingCals)`r`n"
        write-host "-----------------------------------------`r`n"
    }

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSDeploymentLicensing $($rdshServer)`r`n"
    write-host "-----------------------------------------`r`n"
    
    $rWmiL = Get-WmiObject -Namespace root/cimv2/TerminalServices -Class Win32_TSDeploymentLicensing -ComputerName $rdshServer
    $rWmiL
    
    write-host "-----------------------------------------`r`n"
    write-host "checking wmi for lic server`r`n"
    $tempServers = @($rWmi.GetSpecifiedLicenseServerList().SpecifiedLSList)
    $licMode = $rWmi.LicensingType
    write-host "wmi lic servers: $($tempServers) license mode: $($licMode)`r`n"
    
    if($tempServers.Length -gt 0)
    {
        $licenseConfigSource = 'wmi'
    }

    $licenseMode = $licMode    
    
    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
 
    write-host "-----------------------------------------`r`n"
    write-host "checking gpo for lic server`r`n"
    $tempServers = @(([string](read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicenseServers')).Split(",",[StringSplitOptions]::RemoveEmptyEntries))
    $licMode = (read-reg -machine $rdshServer -hive $HKLM -key 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -value 'LicensingMode')
    write-host "gpo lic servers: $($tempServers) license mode: $($licMode)`r`n"

    if($rWmi.PolicySourceLicensingType)
    {
        $licenseConfigSource = 'policy'
        $licenseMode = $licMode    
    }
    
    if([string]::IsNullOrEmpty($licServer) -and ($rWmi.PolicySourceConfiguredLicenseServers -or $rWmi.PolicySourceDirectConnectLicenseServers))
    {
        $licServers = $tempServers;        
    }
    
    if($rdshServer -ilike $env:COMPUTERNAME)
    {
        write-host "-----------------------------------------`r`n"
        write-host "checking local powershell for license server`r`n"
        $tempServers = @(([string]((Get-RDLicenseConfiguration).LicenseServer)).Split(",", [StringSplitOptions]::RemoveEmptyEntries))
        $licMode = (Get-RDLicenseConfiguration).Mode
        write-host "powershell license servers: $($tempServers) license mode: $($licMode)`r`n"

        if($tempServers.Length -gt 0)
        {
            $licenseConfigSource = 'powershell/gui'
        }
    }

    if($licServers.Length -lt 1)
    {
        $licServers = $tempServers;
    }
    
    if($licenseMode -eq 0)
    {
        $licenseMode = $licMode
    }

    if(![string]::IsNullOrEmpty($checkUser))
    {
        write-host "-----------------------------------------`r`n"
        check-user -user $checkUser
        write-host "-----------------------------------------`r`n"
    }
 
    if($licServers.Length -lt 1)
    {
        write-host "license server has not been configured!`r`n"
    }
    else
    {
        $licCheck = $true
        foreach($server in $licServers)
        {
            # issue where server name has space in front but not sure why so adding .Trim() for now
            if($server -ne $server.Trim())
            {
                write-host "warning:whitespace characters on server name"    
            }

            $licServersList.Add($server.Trim(),(check-licenseServer -licServer $server.Trim()))
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
    
    write-host "-----------------------------------------`r`n"
    write-host "*** SUMMARY ***`r`n"
    write-host "server $($rdshServer) is rdsh server? $($isRdshServer)`r`n"
    write-host "server $($rdshServer) is license server? $($isLicServer)`r`n"
    write-host "license server info:`r`n"

    foreach($serverInfo in $licServersList.GetEnumerator())
    {
        write-host "license server name: $($serverInfo.Key)"
        $serverInfo.Value.GetEnumerator() | sort-object Name | Format-Table
    }

    switch($licenseMode)
    {
        0 { 
            $modeString = "0 (should not be set to this!)" 
          }
        1 { 
            $modeString = "Personal Desktop (admin mode 2 session limit)."

            if($isrdshServer)
            {
               $modeString += " (should not be set to this!)"
            }
          }
        2 { 
            $modeString = "Per Device"
          }
        4 { 
            $modeString = "Per User"
          }
        5 { 
            $modeString = "Not configured"

            if($isRdshServer)
            {
               $modeString += " (should not be set to this!)"
            }
          }

        default { $modeString = "error: $($licenseMode)" }
    }
    $configuredCorrectly = $false

    if($isRdshServer)
    {
        $configuredCorrectly = ($licCheck -or $lsDiscovered) -and $hasX509 -and ($licenseMode -eq 2 -or $licenseMode -eq 4) `
            -and $licServersList.Values.TsToLsConnectivityStatus.Contains("LS_CONNECTABLE_VALID")
    }
    else
    {
        $configuredCorrectly = "n/a (not an rdsh server)"    
    }

    write-host "server $($rdshServer) current license mode: $($modeString)`r`n"
    write-host "server $($rdshServer) current license config source: $($licenseConfigSource)`r`n"
    write-host "server $($rdshServer) currently configured correctly for at least one license server? $($configuredCorrectly)`r`n"    
    write-host "server $($rdshServer) ever connected to license server (has x509 cert)? $($hasX509)`r`n"
    write-host "server $($rdshServer) Grace period days left? $($daysLeft)`r`n"
    write-host "`tNOTE: The Grace period is for a license 'grace' during the first 120 days after RDSH role is installed.`r`n"
    write-host "`t During this time, the RDSH server will allow connections regardless if licensed or not.`r`n"
    write-host "`t The internal Grace counter will ALWAYS count down to 0.`r`n"
    write-host "`t This is regardless of RDSH server connectivity status to license server.`r`n"
  
    Stop-Transcript 

    write-host "-----------------------------------------`r`n"
    write-host "log file located here: $([IO.Path]::GetFullPath($logFile))`r`n"
    . $([IO.Path]::GetFullPath($logFile))
    write-host "finished`r`n"
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


    write-host "-----------------------------------------`r`n"
    write-host "-----------------------------------------`r`n"
    write-host "checking license server: '$($licServer)'`r`n"
    write-host "-----------------------------------------`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "OS $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
     
    $licServerResult.OS = (read-reg -machine $licServer -hive $HKLM -key 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -value ProductName)
    write-host "$($licServerResult.OS)`r`n"
    
    write-host "-----------------------------------------`r`n"
    write-host "SERVICE $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    
    $licServerResult.ServiceStatus = (Get-Service -Name TermServLicensing -ComputerName $licServer -ErrorAction SilentlyContinue).Status
    write-host "License Server Service status: $($licServerResult.ServiceStatus)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "EVENTS $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"

    Get-EventLog -LogName "System" -Source "TermServLicensing" -Newest 10 -ComputerName $licServer -After ([DateTime]::Now).AddDays(-7) -EntryType @("Error","Warning")

    if(($rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseServer -ComputerName $licServer))
    {
        write-host "-----------------------------------------`r`n"
        write-host "Win32_TSLicenseServer $($licServer)`r`n"
        write-host "-----------------------------------------`r`n"
        write-host "$($rWmiLS | fl * | out-string)`r`n"

        $wmiClass = ([wmiclass]"\\$($licServer)\root\cimv2:Win32_TSLicenseServer")
        
        $licServerResult.LicenseServerActivated = $wmiClass.GetActivationStatus().ActivationStatus
        write-host "activation status: $($licServerResult.LicenseServerActivated) (0 = activated, 1 = not activated)`r`n"
        $licServerResult.LicenseServerActivated = ![bool]$wmiClass.GetActivationStatus().ActivationStatus

        $licServerResult.LicenseServerId = $wmiClass.GetLicenseServerID().sLicenseServerId
        write-host "license server id: $($licServerResult.LicenseServerId)`r`n"
        write-host "is ls in ts ls group in AD: $($wmiClass.IsLSinTSLSGroup([System.Environment]::UserDomainName).IsMember)`r`n"
        write-host "is ls on dc: $($wmiClass.IsLSonDC().OnDC)`r`n"
        write-host "is ls published in AD: $($wmiClass.IsLSPublished().Published)`r`n"
        write-host "is ls registered to SCP: $($wmiClass.IsLSRegisteredToSCP().Registered)`r`n"
        write-host "is ls security group enabled: $($wmiClass.IsLSSecGrpGPEnabled().Enabled)`r`n"
        write-host "is ls secure access allowed: $($wmiClass.IsSecureAccessAllowed($rdshServer).Allowed)`r`n"
        write-host "is rds in tsc group on ls: $($wmiClass.IsTSinTSCGroup($rdsshServer).IsMember)`r`n"
    }

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSIssuedLicense $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSIssuedLicense -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseKeyPack $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseKeyPack -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"
    $licServerResult.KeyPacksCount = ($rWmiLS | ? TypeAndModel -Cmatch "RDS Per ").Count
    #$licServerResult.CalsPerUserTotal = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").TotalLicenses | measure-object -Sum).Sum
    $licServerResult.CalsPerUserAvailable = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").AvailableLicenses | measure-object -Sum).Sum
    $licServerResult.CalsPerUserUsed = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per User").IssuedLicenses | measure-object -Sum).Sum 
    $licServerResult.CalsPerUserTotal = $licServerResult.CalsPerUserAvailable + $licServerResult.CalsPerUserUsed
    
    #$licServerResult.CalsPerDeviceTotal = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").TotalLicenses | measure-object -Sum).Sum
    $licServerResult.CalsPerDeviceAvailable = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").AvailableLicenses | measure-object -Sum).Sum
    $licServerResult.CalsPerDeviceUsed = (($rWmiLS | ? TypeAndModel -Cmatch "RDS Per Device").IssuedLicenses | measure-object -Sum).Sum
    $licServerResult.CalsPerDeviceTotal = $licServerResult.CalsPerDeviceAvailable + $licServerResult.CalsPerDeviceUsed

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReport $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReport -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReportEntry $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportEntry -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReportFailedPerUserEntry $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportFailedPerUserEntry -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReportFailedPerUserSummaryEntry $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportFailedPerUserSummaryEntry -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReportPerDeviceEntry $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportPerDeviceEntry -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

    write-host "-----------------------------------------`r`n"
    write-host "Win32_TSLicenseReportSummaryEntry $($licServer)`r`n"
    write-host "-----------------------------------------`r`n"
    $rWmiLS = Get-WmiObject -Namespace root/cimv2 -Class Win32_TSLicenseReportSummaryEntry -ComputerName $licServer
    write-host "$($rWmiLS | fl * | out-string)`r`n"

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
    write-host "Can ping license server? $([bool]$ret)`r`n"
 
    $licServerResult.CanAccessLicenseServer = [bool]$rWmi.CanAccessLicenseServer($licServer).AccessAllowed
    $retVal = $retVal -band $licServerResult.CanAccessLicenseServer
    write-host "Can access license server? $($licServerResult.CanAccessLicenseServer)`r`n"
 
    # check named pipe
    write-host "checking named pipe HYDRALSPIPE. if script hangs here, there is a problem connecting to pipe.`r`n"
    $job = Start-Job -Name "namedpipecheck" -ScriptBlock {
        param($licServer)
        try
        {
            $clientPipe = New-Object IO.Pipes.NamedPipeClientStream($licServer, "HYDRALSPIPE", [IO.Pipes.PipeDirection]::InOut)
            $clientPipe.Connect()
            $pipeReader = New-Object IO.StreamReader($clientPipe)
            write-host "job:Can access named pipe? true`r`n"
        }
        catch
        {
            write-host "job:Can access named pipe? false`r`n"
        }
        finally
        {
            $pipeReader.Dispose()
            $clientPipe.Dispose()
        }
    } -ArgumentList ($licServer)

    $count = 0
    while($true -and $job -and $job.State -ne "Completed" -and $count -lt 5)
    {
        $jobInfo = get-job -Name $job.Name
        receive-job -Job $jobInfo | Out-Null
        $count++
        start-sleep -Seconds 1
    }

    if($count -eq 5)
    {
        # pipe failed. cleanup
        $jobInfo = get-job -Name $job.Name
        Remove-Job -Job $jobInfo -Force
        $licServerResult.CanAccessNamedPipe = $false
    }
    else
    {
        $licServerResult.CanAccessNamedPipe = $true
    }

    write-host "Can access named pipe? $($licServerResult.CanAccessNamedPipe)`r`n"

    write-host "checking rpc endpoint mapper`r`n"

    if(Test-NetConnection -Port 135 -ComputerName $licServer)
    {
        $licServerResult.CanAccessRpcEpt = $true
    }
    else 
    {
        $licServerResult.CanAccessRpcEpt = $false
    }

    write-host "Can access rpc port mapper? $($licServerResult.CanAccessRpcEpt)`r`n"

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
    
    $licServerResult.TsToLsConnectivityStatus = $retName
    $licServerResult.Result = [bool]($retVal -band ($ret.TsToLsConnectivityStatus -eq 9 -or $ret.TsToLsConnectivityStatus -eq 11))
    write-host "license connectivity status: $($licServerResult.Result)`r`n"
    
    return $licServerResult
}

# ----------------------------------------------------------------------------------------------------------------
function check-user ([string] $user)
{
    write-host "checking user in AD: $($user)`r`n"

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
            [void]$objSearcher.PropertiesToLoad.Add($i)
        }

        $colResults = $objSearcher.FindAll()

        if($colResults.Count -lt 1)
        {
            write-host "unable to find user:$($user)`r`n"
            return $false
        }

        foreach ($objResult in $colResults)
        {
            write-host "-----------------------------------------`r`n"
            write-host "AD user:$($objresult.Properties["adspath"])`r`n"
            write-host "RDS CAL expire date:$($objresult.Properties["mstsexpiredate"])`r`n"
            write-host "RDS License Server Identity:$($objresult.Properties["mstsmanagingls"])`r`n"
        }
        
        write-host "found user:$($user)`r`n"
        return $true
    }
    catch
    {
        write-host "exception trying to find user:$($user)`r`n"
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

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            write-host "updating new script`r`n"
            [IO.File]::WriteAllText($MyInvocation.ScriptName, $git)
            write-host "restart to use new script. exiting.`r`n"
            exit
        }
        else
        {
            write-host "script is up to date`r`n"
        }
        
        return $true
    }
    catch [System.Exception] 
    {
        write-host "get-update:exception: $($error)`r`n"
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
        write-host "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used.`r`n"
        
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
        
        if(![IO.File]::Exists($destFile))
        {
            $sysUrl = "http://live.sysinternals.com/$($utilityName)"

            write-host "Sysinternals process psexec.exe is needed for this option!`r`n" -ForegroundColor Yellow
            if((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                [void]$webClient.DownloadFile($sysUrl, $destFile)
                write-host "sysinternals utility $($utilityName) downloaded to $($destFile)`r`n"
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
        write-host "Exception downloading $($utilityName): $($error)`r`n"
        $error.Clear()
        return [string]::Empty
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
        [void]$retVal.AppendLine("-----------------------------------------")
        [void]$retVal.AppendLine("enumerating $($key) for value $($value)")
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
                    if($enumValue -or $displayBinaryBlob)
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
                
                read-reg -machine $machine -hive $hive -key "$($key)\$($subkey)"
            }
        }

        if($enumValue)
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
    write-host "Running process $processName $arguments`r`n"
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
        write-host "Error:Process ended before capturing output.`r`n"
    }
    
    $exitVal = $process.ExitCode
    write-host "Running process exit $($processName) : $($exitVal)`r`n"
    $Error.Clear()
    return $stdOut
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
        write-host "please restart script as administrator. exiting...`r`n"
       return $false
    }

    return $true
}

# ----------------------------------------------------------------------------------------------------------------
main
