# Run the following from each sfnode in admin powershell:
param(
$workdir = "c:\temp",
$startTime = "7/10/2018",
$endTime = "7/25/2018",
$eventLogNames = "*"
)

$eventLogScript = "http://aka.ms/event-log-manager.ps1"
$parentWorkDir = $workdir
$workdir = "$($workdir)\gather"

if((test-path $workdir)) { remove-item $workdir -Recurse }

new-item $workdir -ItemType Directory
Set-Location $parentworkdir

(new-object net.webclient).downloadfile($eventLogScript,"$($parentWorkdir)\event-log-manager.ps1")
"$($parentWorkdir)\event-log-manager.ps1 -eventLogNamePattern $($eventlognames) -eventStartTime $($startTime) -eventStopTime $($endTime) -eventDetails -merge -uploadDir $($workdir)"
Get-WindowsUpdateLog -LogPath "$($workdir)\windowsupdate.log"
get-hotfix | out-file "$($workdir)\hotfixes.log"
wmic os get version | out-file "$($workdir)\os.log"
Get-psdrive | out-file "$($workdir)\drives.log"
Get-process | out-file "$($workdir)\pids.log"

if((test-path "$($workdir).zip")) { remove-item "$($workdir).zip" }

Compress-archive -path $workdir -destinationPath $workdir
set-location $parentworkdir
write-host "upload $($workdir).zip to workspace" -ForegroundColor Cyan
start-process $parentWorkDir
