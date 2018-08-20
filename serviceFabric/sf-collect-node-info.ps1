<#
.SYNOPSIS
powershell script to collect service fabric node diagnostic data

To download and execute, run the following commands on each sf node in admin powershell:
iwr('https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1')|iex

To download and execute with arguments:
(new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1","c:\sf-collect-node-info.ps1")
c:\sf-collect-node-info.ps1 -certInfo -days 30

upload to workspace sfgather* dir or zip

.DESCRIPTION
    To enable script execution, you may need to Set-ExecutionPolicy Bypass -Force
    script will collect event logs, hotfixes, services, processes, drive, firewall, and other OS information

    Requirements:
        - administrator powershell prompt
        - administrative access to machine
        - remote network ports:
            - smb 445
            - rpc endpoint mapper 135
            - rpc ephemeral ports
            - to test access from source machine to remote machine: dir \\%remote machine%\admin$
        - winrm
            - depending on configuration / security, it may be necessary to modify trustedhosts on 
            source machine for management of remote machines
            - to query: winrm get winrm/config
            - to enable sending credentials to remote machines: winrm set winrm/config/client '@{TrustedHosts="*"}'
            - to disable sending credentials to remote machines: winrm set winrm/config/client '@{TrustedHosts=""}'
        - firewall
            - if firewall is preventing connectivity the following can be run to disable
            - Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
            
    Copyright 2018 Microsoft Corporation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    
.NOTES
    File Name  : sf-collect-node-info.ps1
    Author     : jagilber
    Version    : 180815 original
    History    : 
    
.EXAMPLE
    .\sf-collect-node-info.ps1 -certInfo
    Example command to query all diagnostic information, event logs, and certificate store information

.PARAMETER workDir
    output directory where all files will be created.
    default is $env:temp

.LINK
    https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1
#>
[CmdletBinding()]
param(
    $workdir = $env:temp,
    $eventLogNames = "System$|Application$|wininet|dns|Fabric|http|Firewall|Azure",
    $startTime = (get-date).AddDays(-7).ToShortDateString(),
    $endTime = (get-date).ToShortDateString(),
    [int[]]$ports = @(1025, 1026, 1027, 19000, 19080, 135, 445, 3389, 5985, 80, 443),
    $remoteMachine = $env:computername,
    $externalUrl = "bing.com",
    [switch]$noAdmin,
    [switch]$noEventLogs,
    [switch]$certInfo
)

$ErrorActionPreference = "Continue"
$currentWorkDir = get-location
$osVersion = [version]([string]((wmic os get Version) -match "\d"))
$win10 = ($osVersion.major -ge 10)
$parentWorkDir = $workdir
$workdir = "$($workdir)\sfgather-$($env:COMPUTERNAME)"
$ps = "powershell.exe"
$jobs = new-object collections.arraylist
$logFile = "$($workdir)\sf-collect-node-info.log"
function main()
{
    $error.Clear()
    write-warning "to troubleshoot this issue, this script may collect sensitive information similar to other microsoft diagnostic tools."
    write-warning "information may contain items such as ip addresses, process information, user names, or similar."
    write-warning "information in directory / zip can be reviewed before uploading to workspace."

    if ((test-path $workdir))
    {
        remove-item $workdir -Recurse 
    }

    new-item $workdir -ItemType Directory
    Set-Location $parentworkdir

    Start-Transcript -Path $logFile -Force
    write-host "starting $(get-date)"

    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
        Write-Warning "please restart script in administrator powershell session"

        if (!$noadmin)
        {
            Write-Warning "if unable to run as admin, restart and use -noadmin switch. This will collect less data that may be needed. exiting..."
            return $false
        }
    }

    write-host "remove old jobs"
    get-job | remove-job -Force

    if ($win10)
    {
        add-job -jobName "windows update" -scriptBlock {
            param($workdir = $args[0]) 
            Get-WindowsUpdateLog -LogPath "$($workdir)\windowsupdate.log.txt"
        } -arguments $workdir
    }
    else
    {
        copy-item "$env:systemroot\windowsupdate.log" "$($workdir)\windowsupdate.log.txt"
    }

    if (!$noEventLogs)
    {
        add-job -jobName "event logs 1 day" -scriptBlock {
            param($workdir = $args[0], $parentWorkdir = $args[1], $eventLogNames = $args[2], $startTime = $args[3], $endTime = $args[4], $ps = $args[5], $remoteMachine = $args[6])
            (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
            Invoke-Expression "$($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern `"$($eventlognames)`" -eventDetails -merge -uploadDir `"$($workdir)\1-day-event-logs`" -nodynamicpath -machines $($remoteMachine)"
        } -arguments @($workdir, $parentWorkdir, $eventLogNames, $startTime, $endTime, $ps, $remoteMachine)

        add-job -jobName "event logs" -scriptBlock {
            param($workdir = $args[0], $parentWorkdir = $args[1], $eventLogNames = $args[2], $startTime = $args[3], $endTime = $args[4], $ps = $args[5], $remoteMachine = $args[6])
            (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
            Invoke-Expression "$($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern `"$($eventlognames)`" -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir `"$($workdir)\$(([datetime]$startTime - [datetime]$endTime).Days)-days-event-logs`" -nodynamicpath -machines $($remoteMachine)"
        } -arguments @($workdir, $parentWorkdir, $eventLogNames, $startTime, $endTime, $ps, $remoteMachine)
    }

    add-job -jobName "check for dump file c" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1])
        # slow
        # Invoke-Command -ComputerName $remoteMachine -ScriptBlock { start-process "cmd.exe" -ArgumentList "/c dir c:\*.*dmp /s > "$env:temp\dumplist-c.txt" -Wait -WindowStyle Hidden }
        Invoke-Expression "cmd.exe /c dir c:\*.*dmp /s > $($workdir)\dumplist-c.txt"
    } -arguments @($workdir, $remoteMachine)

    add-job -jobName "check for dump file d" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1])
        # Invoke-Command -ComputerName $remoteMachine -ScriptBlock { start-process "cmd.exe" -ArgumentList "/c dir d:\*.*dmp /s > "$env:temp\dumplist-d.txt" -Wait -WindowStyle Hidden }
        Invoke-Expression "cmd.exe /c dir d:\*.*dmp /s > $($workdir)\dumplist-d.txt"
    } -arguments @($workdir, $remoteMachine)

    add-job -jobName "network port tests" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1], $ports = $args[2])
        foreach ($port in $ports)
        {
            test-netconnection -port $port -ComputerName $remoteMachine -InformationLevel Detailed | out-file -Append "$($workdir)\network-port-test.txt"
        }
    } -arguments @($workdir, $remoteMachine, $ports)

    add-job -jobName "check external connection" -scriptBlock {
        param($workdir = $args[0], $externalUrl = $args[1])
        [net.httpWebResponse](Invoke-WebRequest $externalUrl -UseBasicParsing).BaseResponse | out-file "$($workdir)\network-external-test.txt" 
    } -arguments @($workdir, $externalUrl)

    add-job -jobName "resolve-dnsname" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1], $externalUrl = $args[2])
        Resolve-DnsName -Name $remoteMachine | out-file -Append "$($workdir)\resolve-dnsname.txt"
        Resolve-DnsName -Name $externalUrl | out-file -Append "$($workdir)\resolve-dnsname.txt"
    } -arguments @($workdir, $remoteMachine, $externalUrl)

    add-job -jobName "nslookup" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1], $externalUrl = $args[2])
        write-host "nslookup"
        out-file -InputObject "querying nslookup for $($externalUrl)" -Append "$($workdir)\nslookup.txt"
        Invoke-Expression "nslookup $($externalUrl) | out-file -Append $($workdir)\nslookup.txt"
        out-file -InputObject "querying nslookup for $($remoteMachine)" -Append "$($workdir)\nslookup.txt"
        Invoke-Expression "nslookup $($remoteMachine) | out-file -Append $($workdir)\nslookup.txt"
    } -arguments @($workdir, $remoteMachine, $externalUrl)


    write-host "winrm settings"
    Invoke-Expression "winrm get winrm/config/client > $($workdir)\winrm-config.txt" 

    if ($certInfo)
    {
        write-host "certs (output scrubbed)"
        [regex]::Replace((Get-ChildItem -Path cert: -Recurse | format-list * | out-string), "[0-9a-fA-F]{20}`r`n", "xxxxxxxxxxxxxxxxxxxx`r`n") | out-file "$($workdir)\certs.txt"
    }
    
    write-host "http log files"
    copy-item -path "\\$($remoteMachine)\C$\Windows\System32\LogFiles\HTTPERR\*" -Destination $workdir -Force -Filter "*.log"

    write-host "hotfixes"
    get-hotfix -ComputerName $remoteMachine | out-file "$($workdir)\hotfixes.txt"

    write-host "os"
    get-wmiobject -Class Win32_OperatingSystem -Namespace root\cimv2 -ComputerName $remoteMachine | format-list * | out-file "$($workdir)\os-info.txt"

    add-job -jobName "drives" -scriptBlock {
        param($workdir = $args[0])
        Get-psdrive | out-file "$($workdir)\drives.txt"
    } -arguments @($workdir)

    write-host "processes"
    Get-process -ComputerName $remoteMachine | out-file "$($workdir)\process-summary.txt"
    Get-process -ComputerName $remoteMachine | format-list * | out-file "$($workdir)\processes.txt"

    write-host "services"
    Get-service -ComputerName $remoteMachine | out-file "$($workdir)\service-summary.txt"
    Get-Service -ComputerName $remoteMachine | format-list * | out-file "$($workdir)\services.txt"

    write-host "installed applications"
    Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall /s /v DisplayName > $($workDir)\installed-apps.reg.txt"

    write-host "features"
    Get-WindowsFeature | Where-Object "InstallState" -eq "Installed" | out-file "$($workdir)\windows-features.txt"

    add-job -jobName ".net reg" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1])
        Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework /s > $($workDir)\dotnet.reg.txt"
    } -arguments @($workdir, $remoteMachine)

    write-host "policies"
    Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SOFTWARE\Policies /s > $($workDir)\policies.reg.txt"

    write-host "schannel"
    Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL /s > $($workDir)\schannel.reg.txt"

    add-job -jobName "firewall" -scriptBlock {
        param($workdir = $args[0], $remoteMachine = $args[1])
        Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules /s > $($workDir)\firewallrules.reg.txt"
        Get-NetFirewallRule | out-file "$($workdir)\firewall-config.txt"
    } -arguments @($workdir, $remoteMachine)

    write-host "get-nettcpconnetion" # doesnt require admin like netstat
    add-job -jobName ".net reg" -scriptBlock {
        param($workdir = $args[0])
        Get-NetTCPConnection | format-list * | out-file "$($workdir)\netTcpConnection.txt"
    } -arguments @($workdir)
    write-host "netstat ports"
    Invoke-Expression "netstat -bna > $($workdir)\netstat.txt"

    write-host "netsh ssl"
    Invoke-Expression "netsh http show sslcert > $($workdir)\netshssl.txt"

    write-host "ip info"
    Invoke-Expression "ipconfig /all > $($workdir)\ipconfig.txt"

    write-host "service fabric reg"
    #HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Service Fabric
    Invoke-Expression "reg.exe query `"\\$($remoteMachine)\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Service Fabric`" /s > $($workDir)\serviceFabric.reg.txt"
    Invoke-Expression "reg.exe query \\$($remoteMachine)\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServiceFabricNodeBootStrapAgent /s > $($workDir)\serviceFabricNodeBootStrapAgent.reg.txt"

    $fabricDataRoot = (get-itemproperty -path "hklm:\software\microsoft\service fabric" -Name "fabricdataroot").fabricdataroot
    write-host "fabric data root:$($fabricDataRoot)"
    Invoke-Expression "dir `"$($fabricDataRoot)`" /s > $($workDir)\dir-fabricdataroot.txt"
    Copy-Item -Path "$($fabricDataRoot)\*" -Filter "*.xml" -Destination $workdir

    $fabricRoot = (get-itemproperty -path "hklm:\software\microsoft\service fabric" -Name "fabricroot").fabricroot
    write-host "fabric root:$($fabricRoot)"
    Invoke-Expression "dir `"$($fabricRoot)`" /s > $($workDir)\dir-fabricroot.txt"
    
    write-host "waiting for $($jobs.Count) jobs to complete"

    while (($incompletedCount = (get-job | Where-Object State -ne "Completed").Count) -gt 0)
    {
        foreach ($job in (get-job | Where-Object State -ne "Completed"))
        {
            if ($job -and $job.Name)
            {
                write-host ("$($job.Name) : $(Receive-Job $job.Name -ErrorAction SilentlyContinue)") -ForegroundColor Cyan
            }
        }

        write-host "waiting on $($incompletedCount) jobs..." -ForegroundColor Yellow
        start-sleep -seconds 10
    }

    write-host "zip"
    $zipFile = "$($workdir).zip"

    if ((test-path $zipFile ))
    {
        remove-item $zipFile 
    }

    Stop-Transcript 

    if ($win10)
    {
        Compress-archive -path $workdir -destinationPath $workdir
    }
    else
    {
        Add-Type -Assembly System.IO.Compression.FileSystem
        $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
        [System.IO.Compression.ZipFile]::CreateFromDirectory($workdir, $zipFile, $compressionLevel, $false)
    }

    Start-Transcript -Path $logFile -Force -Append | Out-Null
    write-host "upload $($zipFile) to workspace" -ForegroundColor Cyan

    if ((test-path "$($env:systemroot)\explorer.exe"))
    {
        start-process "explorer.exe" -ArgumentList $parentWorkDir
    }
}

function add-job($jobName, $scriptBlock, $arguments)
{
    write-host "adding job $($jobName)"
    [void]$jobs.Add((Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $arguments))
}

try
{
    main
}
catch
{
    write-error "main exception: $($error | out-string)"
}
finally
{
    set-location $currentWorkDir
    get-job | remove-job -Force
    write-host "finished $(get-date)"
    write-debug "errors during script: $($error | out-string)"
    Stop-Transcript | Out-Null
}

