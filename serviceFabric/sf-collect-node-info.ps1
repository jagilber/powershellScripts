# (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-collect-node-info.ps1","c:\sf-collect-node-info.ps1")

# Run the following from each sfnode in admin powershell:

param(
    $workdir = "c:\temp",
    $startTime = (get-date).AddDays(-5).ToShortDateString(),
    $endTime = (get-date).ToShortDateString(),
    $eventLogNames = "*",
    [switch]$eventLogs
)

$currentWorkDir = get-location
$osVersion = [version]([string]((wmic os get Version) -match "\d"))
$parentWorkDir = $workdir
$workdir = "$($workdir)\gather"
$win10 = $false

if($osVersion.major -ge 10)
{
    $win10 = $true
}

if ((test-path $workdir))
{
    remove-item $workdir -Recurse 
}

new-item $workdir -ItemType Directory
Set-Location $parentworkdir

if ($eventLogs)
{
    (new-object net.webclient).downloadfile("http://aka.ms/event-log-manager.ps1", "$($parentWorkdir)\event-log-manager.ps1")
    $args = "$($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern $($eventlognames) -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir $($workdir)"
    start-process -filepath "powershell.exe" -ArgumentList $args
}

if($win10)
{
    Get-WindowsUpdateLog -LogPath "$($workdir)\windowsupdate.log"
}
else
{
    copy-item "$env:systemroot\windowsupdate.log" "$($workdir)\windowsupdate.log"
}

get-hotfix | out-file "$($workdir)\hotfixes.log"
$osVersion.tostring() | out-file "$($workdir)\os.log"
Get-psdrive | out-file "$($workdir)\drives.log"
Get-process | out-file "$($workdir)\pids.log"
start-process "powershell.exe" -ArgumentList "reg.exe export HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules $($workDir)\firewallrules.reg"
start-process "powershell.exe" -ArgumentList "netstat -bna > $($workdir)\netstat.log"
start-process "powershell.exe" -ArgumentList "netsh http show sslcert > $($workdir)\netshssl.log"
start-process "powershell.exe" -ArgumentList "ipconfig /all > $($workdir)\ipconfig.log"

if ((test-path "$($workdir).zip"))
{
    remove-item "$($workdir).zip" 
}

if($win10)
{
    Compress-archive -path $workdir -destinationPath $workdir
    write-host "upload $($workdir).zip to workspace" -ForegroundColor Cyan
}
else
{
    write-host "zip and upload $($workdir) to workspace" -ForegroundColor Cyan
}

start-process $parentWorkDir
set-location $currentWorkDir