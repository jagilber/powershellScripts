# Run the following from each sfnode in admin powershell:
# (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1","c:\sf-collect-node-info.ps1")
# c:\sf-collect-node-info.ps1

param(
    $workdir = $env:temp,
    $startTime = (get-date).AddDays(-5).ToShortDateString(),
    $endTime = (get-date).ToShortDateString(),
    $eventLogNames = "System|Application|Fabric|http|Firewall|Azure",
    [switch]$eventLogs,
    $storageSASKey,
    $remoteMachine = "127.0.0.1",
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
        copy-item "$env:systemroot\windowsupdate.txt" "$($workdir)\windowsupdate.txt"
    }

    # event logs
    if ($eventLogs)
    {
        $jobs.Add((Start-Job -ScriptBlock {
                    param($workdir = $args[0], $parentWorkdir = $args[1], $eventLogNames = $args[2], $startTime = $args[3], $endTime = $args[4], $ps = $args[5])
                    (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
                    $argList = "-NoExit -File $($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern `"$($eventlognames)`" -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir $($workdir)"
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
                param($remoteMachine = $args[0], $workdir = $args[1])
                test-netconnection -port 1025 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 19000 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 19080 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 20001 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 3389 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 445 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
                test-netconnection -port 135 -ComputerName $remoteMachine | out-file -Append "$($workdir)\network-port-test.txt"
            } -ArgumentList $remoteMachine, $workdir))

    # check external connection
    [net.httpWebResponse](Invoke-WebRequest $externalUrl).BaseResponse | out-file "$($workdir)\network-external-test.txt" 

    # nslookup
    start-process $ps -ArgumentList "nslookup $($externalUrl) > $($workdir)\nslookup.txt"

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

    while ((get-job | Where-Object State -ne "Completed"))
    {
        start-sleep -seconds 1
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
#https://jagilbermsstorage.blob.core.windows.net/?sv=2017-11-09&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-08-14T22:26:23Z&st=2018-08-14T14:26:23Z&spr=https&sig=%2Bnb87%2BNEO11rfGAh97VTl7z1O5sbPfgpohmzAaZDsf0%3D
