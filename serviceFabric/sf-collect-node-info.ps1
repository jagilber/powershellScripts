<#
.SYNOPSIS
    powershell script to collect service fabric node diagnostic data
    Run the following from each sfnode in admin powershell:
    (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1","c:\sf-collect-node-info.ps1")

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
    .\sf-collect-node-info.ps1 -eventlogs
    Example command to query all diagnostic information and event logs

.PARAMETER workDir
    output directory where all files will be created.
    default is $env:temp

.LINK
    https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1
#>

param(
    $workdir = $env:temp,
    $startTime = (get-date).AddDays(-5).ToShortDateString(),
    $endTime = (get-date).ToShortDateString(),
    $eventLogNames = "System|Application|Fabric|http|Firewall|Azure",
    [int[]]$ports = @(1025,1026,1027,19000,19080,135,445,3389),
    [switch]$eventLogs,
    $storageSASKey,
    $remoteMachine = $env:computername,
    $externalUrl = "bing.com"
)

$ErrorActionPreference = "Continue"
$error.Clear()
$currentWorkDir = get-location
$osVersion = [version]([string]((wmic os get Version) -match "\d"))
$win10 = ($osVersion.major -ge 10)
$parentWorkDir = $workdir
$workdir = "$($workdir)\sfgather-$($env:COMPUTERNAME)"
$ps = "powershell.exe"
$jobs = new-object collections.arraylist

function main()
{
    # remove old jobs
    get-job | remove-job -Force

    if ((test-path $workdir))
    {
        remove-item $workdir -Recurse 
    }

    new-item $workdir -ItemType Directory
    Set-Location $parentworkdir

    # windows update
    if ($win10)
    {
        $jobs.Add((Start-Job -ScriptBlock {
                    param($workdir = $args[0]) 
                    Get-WindowsUpdateLog -LogPath "$($workdir)\windowsupdate.txt"
                } -ArgumentList $workdir))
    }
    else
    {
        copy-item "$env:systemroot\windowsupdate.log" "$($workdir)\windowsupdate.txt"
    }

    # event logs
    if ($eventLogs)
    {
        $jobs.Add((Start-Job -ScriptBlock {
                    param($workdir = $args[0], $parentWorkdir = $args[1], $eventLogNames = $args[2], $startTime = $args[3], $endTime = $args[4], $ps = $args[5])
                    (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
                    $argList = "-File $($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern `"$($eventlognames)`" -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir $($workdir)"
                    start-process -filepath $ps -ArgumentList $argList -Wait
                } -ArgumentList $workdir, $parentWorkdir, $eventLogNames, $startTime, $endTime, $ps))
    }

    # check for dump files
    $jobs.Add((Start-Job -ScriptBlock {
                param($workdir = $args[0])
                start-process "cmd.exe" -ArgumentList "/c dir c:\*.*dmp /s > $($workdir)\dumplist-c.txt" -Wait
            } -ArgumentList $workdir))
    $jobs.Add((Start-Job -ScriptBlock {
                param($workdir = $args[0])
                start-process "cmd.exe" -ArgumentList "/c dir d:\*.*dmp /s > $($workdir)\dumplist-d.txt" -Wait  
            } -ArgumentList $workdir))

    # network port tests
    $jobs.Add((Start-Job -ScriptBlock {
                param($workdir = $args[0], $remoteMachine = $args[1], $ports = $args[2])
                foreach($port in $ports)
                {
                    test-netconnection -port $port -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                }
            } -ArgumentList $workdir, $remoteMachine, $ports))

    # check external connection
    [net.httpWebResponse](Invoke-WebRequest $externalUrl).BaseResponse | out-file "$($workdir)\network-external-test.txt" 

    # nslookup
    write-host "querying nslookup for $($externalUrl)" | out-file -Append "$($workdir)\nslookup.txt"
    start-process $ps -ArgumentList "nslookup $($externalUrl) | out-file -Append $($workdir)\nslookup.txt"
    write-host "querying nslookup for $($remoteMachine)" | out-file -Append "$($workdir)\nslookup.txt"
    start-process $ps -ArgumentList "nslookup $($remoteMachine) | out-file -Append $($workdir)\nslookup.txt"

    # winrm settings
    start-process "cmd.exe" -ArgumentList "/c winrm get winrm/config/client > $($workdir)\winrm-config.txt"

    # cert scrubbed
    [regex]::Replace((Get-ChildItem -Path cert: -Recurse | format-list * | out-string), "[0-9a-fA-F]{20}`r`n", "xxxxxxxxxxxxxxxxxxxx`r`n") | out-file "$($workdir)\certs.txt"

    # http log files
    copy-item -path "C:\Windows\System32\LogFiles\HTTPERR\*" -Destination $workdir -Force -Filter "*.log"

    # hotfixes
    get-hotfix | out-file "$($workdir)\hotfixes.txt"

    # os
    (get-wmiobject -Class Win32_OperatingSystem -Namespace root\cimv2 -ComputerName $remoteMachine) | format-list * | out-file "$($workdir)\osinfo.txt"

    # drives
    Get-psdrive | out-file "$($workdir)\drives.txt"

    # processes
    Get-process | out-file "$($workdir)\pids.txt"

    # services
    Get-Service | out-file "$($workdir)\services.txt"

    # firewall rules
    start-process $ps -ArgumentList "reg.exe export HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules $($workDir)\firewallrules.reg"

    # firewall settings
    Get-NetFirewallRule | out-file "$($workdir)\firewall-config.txt"

    # netstat ports
    start-process $ps -ArgumentList "netstat -bna > $($workdir)\netstat.txt"

    # netsh ssl
    start-process $ps -ArgumentList "netsh http show sslcert > $($workdir)\netshssl.txt"

    # ip info
    start-process $ps -ArgumentList "ipconfig /all > $($workdir)\ipconfig.txt"

    write-host "waiting for $($jobs.Count) jobs to complete"

    while (($uncompletedCount = (get-job | Where-Object State -ne "Completed").Count) -gt 0)
    {
        write-host "waiting on $($uncompletedCount) jobs..."
        start-sleep -seconds 10
    }

    # zip
    $zipFile = "$($workdir).zip"

    if ((test-path $zipFile ))
    {
        remove-item $zipFile 
    }

    if ($win10)
    {
        Compress-archive -path $workdir -destinationPath $workdir

        # upload to storage
        if ($storageSASKey)
        {
            # todo install azure
            Start-AzureStorageBlobCopy -SrcFile $zipFile -AbsoluteUri $storageSASKey
            write-host "$($zipFile) uploaded to storage $($storageSASKey)"
        }
        else
        {
            write-host "upload $($zipFile) to workspace" -ForegroundColor Cyan
        }
    }
    else
    {
        # upload to storage
        if ($storageSASKey)
        {
            # todo install azure
            $storageAccount = ([regex]::Matches($storageSASKey, "//(.+?)\.")).Groups[1].Value
            $storageContext = New-AzureStorageContext -StorageAccountName $storageAccount -SasToken $storageSASKey
            #Set-AzureStorageBlobContent -File $file -Container $containerName -Context $StorageContext -Blob $blob -Force
            Start-AzureStorageBlobCopy -SrcDir $workdir -AbsoluteUri $storageSASKey
            write-host "$($workDir) uploaded to storage $($storageSASKey)"
        }
        else
        {
            write-host "zip and upload $($workdir) to workspace" -ForegroundColor Cyan
        }
    }

    # remove jobs
    get-job | remove-job -Force

    start-process $parentWorkDir
    set-location $currentWorkDir
}
 
main

