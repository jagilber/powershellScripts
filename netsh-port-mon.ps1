param(
    [dateTime]$startTime = (get-date),
    [dateTime]$endTime = (get-date).addHours(2),
    [decimal]$intervalMinutes = 1,
    [string]$logPath = $psscriptroot,
    [switch]$onSchedule
)

$startTimer = get-date
write-host "initializing $startTimer"

$handle = "handle.exe"
if(!(test-path $handle))
{
    write-host "downloading $handle"
    [net.ServicePointManager]::Expect100Continue = $true
    [net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12
    (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$handle","$psscriptroot\$handle")
}

$handle = ".\$handle"
$intervalSeconds = ($intervalMinutes * 60)
mkdir $logPath -ErrorAction SilentlyContinue


$sleepInterval = [math]::max($startTime.Subtract((get-date)).TotalSeconds,0)
write-host "sleeping until $startTime ($sleepInterval seconds)"
start-sleep -Seconds $sleepInterval
write-host "starting $(get-date)"
$iteration = 0

while($endTime -ge $startTime)
{
    $iteration++
    $timer = get-date
    write-host "running $iteration $timer"

    # do work
    $fileTime = $timer.ToString("yy-MM-dd-HH-mm-ss")
    $netshLogFile = "$logPath\$fileTime-$env:computername-netsh-port-mon.log"
    $handleLogFile = "$logPath\$fileTime-$env:computername-handle-mon.log"
    $processLogFile = "$logPath\$fileTime-$env:computername-process-mon.log"

    out-file -InputObject "running $iteration $timer" -FilePath $handleLogFile -Append -Encoding ascii
    out-file -InputObject (. $handle) -FilePath $handleLogFile -Append -Encoding ascii

    out-file -InputObject "running $iteration $timer" -FilePath $processLogFile -Append -Encoding ascii
    out-file -InputObject (get-process | fl *) -FilePath $processLogFile -Append -Encoding ascii

    write-host (get-process| out-string)

    $netshResults = Get-NetTCPConnection 
    out-file -InputObject "running $iteration $timer" -FilePath $netshLogFile -Append -Encoding ascii
    out-file -InputObject ($netshResults | Group-Object State | out-string) -FilePath $netshLogFile -Append -Encoding ascii
    out-file -InputObject ($netshResults | fl *) -FilePath $netshLogFile -Append -Encoding ascii

    write-host ($netshResults | Group-Object State | out-string)
   
    if($onSchedule)
    {
        # $random = (Get-Random -Maximum 10)
        # write-host "working $iteration $random seconds"
        # start-sleep -seconds $random

        # subtract time for work above
        $sleepInterval = [math]::max($intervalSeconds - ((get-date).Subtract($timer).TotalSeconds),0)
    }
    else
    {
        $sleepInterval = $intervalSeconds
    }
    
    write-host "sleeping $iteration $sleepInterval seconds"
    start-sleep -Seconds $sleepInterval
}