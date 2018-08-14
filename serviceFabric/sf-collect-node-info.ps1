# Run the following from each sfnode in admin powershell:
# (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1","c:\sf-collect-node-info.ps1")
# c:\sf-collect-node-info.ps1

param(
    $workdir = "c:\temp",
    $startTime = (get-date).AddDays(-5).ToShortDateString(),
    $endTime = (get-date).ToShortDateString(),
    $eventLogNames = "System|Application|Fabric|http|Firewall|Azure",
    [switch]$eventLogs,
    $storageUrl
)

$error.Clear()
$currentWorkDir = get-location
$osVersion = [version]([string]((wmic os get Version) -match "\d"))
$win10 = ($osVersion.major -ge 10)
$parentWorkDir = $workdir
$workdir = "$($workdir)\sfgather-$($env:COMPUTERNAME)"
$ps = "powershell.exe"

function main()
{
    if ((test-path $workdir))
    {
        remove-item $workdir -Recurse 
    }

    new-item $workdir -ItemType Directory
    Set-Location $parentworkdir

    # windows update
    if ($win10)
    {
        Get-WindowsUpdateLog -LogPath "$($workdir)\windowsupdate.txt"
    }
    else
    {
        copy-item "$env:systemroot\windowsupdate.txt" "$($workdir)\windowsupdate.txt"
    }

    # cert scrubbed
    [regex]::Replace((Get-ChildItem -Path cert: -Recurse | format-list * | out-string), "[0-9a-fA-F]{20}`r`n", "xxxxxxxxxxxxxxxxxxxx`r`n") | out-file "$($workdir)\certs.txt"

    # http log files
    copy-item -path "C:\Windows\System32\LogFiles\HTTPERR\*" -Destination $workdir -Force -Filter "*.log"

    # hotfixes
    get-hotfix | out-file "$($workdir)\hotfixes.txt"

    # os
    $osVersion.tostring() | out-file "$($workdir)\os.txt"

    # drives
    Get-psdrive | out-file "$($workdir)\drives.txt"

    # processes
    Get-process | out-file "$($workdir)\pids.txt"

    # services
    Get-Service | out-file "$($workdir)\services.txt"

    # firewall rules
    start-process $ps -ArgumentList "reg.exe export HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules $($workDir)\firewallrules.reg"

    # netstat ports
    start-process $ps -ArgumentList "netstat -bna > $($workdir)\netstat.txt"

    # netsh ssl
    start-process $ps -ArgumentList "netsh http show sslcert > $($workdir)\netshssl.txt"

    # ip info
    start-process $ps -ArgumentList "ipconfig /all > $($workdir)\ipconfig.txt"

    # event logs
    if ($eventLogs)
    {
        (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
        $args = "$($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern $($eventlognames) -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir $($workdir)"
        start-process -filepath $ps -ArgumentList $args -Wait
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
        write-host "upload $($zipFile) to workspace" -ForegroundColor Cyan
    }
    else
    {
        write-host "zip and upload $($workdir) to workspace" -ForegroundColor Cyan
    }

    # upload to storage
    if ($storageUrl)
    {
        #todo
        write-host "$($zipFile) uploaded to storage $($storageUrl)"
    }

    start-process $parentWorkDir
    set-location $currentWorkDir
}

main