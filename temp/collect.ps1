invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/windows-logon-diagnostics-manager.ps1" -outFile "$pwd\windows-logon-diagnostics-manager.ps1";
$sleepSeconds = 120
# start network trace
netsh trace start capture=yes overwrite=yes maxsize=1024 tracefile=net.etl filemode=circular

# backup registry
.\windows-logon-diagnostics-manager.ps1 -backup

# enable diagnostics
.\windows-logon-diagnostics-manager.ps1 -enableAll

# start tracing
.\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType all

# sleep for 2 minutes
write-host "sleeping for 120 seconds to capture data..." -foregroundcolor yellow
start-sleep -seconds $sleepSeconds

# stop tracing
.\windows-logon-diagnostics-manager.ps1 -stopEtwTrace -etwTraceType all #-collectLogs

# disable diagnostics
.\windows-logon-diagnostics-manager.ps1 -disableAll -collectLogs

# stop network tracing
netsh trace stop

# collect security eventlog
wevtutil qe Security /q:"*[System[TimeCreated[timediff(@SystemTime) <= 600000]]]" /f:text > security.txt

# upload diagnostic-logs*.zip, net.etl, security.txt