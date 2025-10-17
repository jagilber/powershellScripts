<#
.SYNOPSIS
    download sysinternals utilities

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/sysinternals-exe-download.ps1" -outFile "$pwd\sysinternals-exe-download.ps1";
    .\sysinternals-exe-download.ps1
#>

param(
    [ValidateSet('livekd.exe',
        'psexec.exe',
        'procmon.exe',
        'procdump.exe',
        'procexp.exe',
        'tcpview.exe',
        'rammap.exe',
        'handle.exe',
        'pipelist.exe',
        'winobj.exe',
        'accesschk.exe',
        'disk2vhd.exe'
    )]
    $sysinternalsExe = "procdump.exe",
    $sysinternalsCustomExe,
    [switch]$noExecute
)

[net.ServicePointManager]::Expect100Continue = $true
[net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

if(!$sysinternalsCustomExe) { $sysinternalsCustomExe = $sysinternalsExe}

if(!(test-path $sysinternalsCustomExe)){
    write-host "[net.webclient]::new().DownloadFile(`"http://live.sysinternals.com/$sysinternalsCustomExe`", `"$pwd\$sysinternalsCustomExe`")"
    [net.webclient]::new().DownloadFile("http://live.sysinternals.com/$sysinternalsCustomExe", "$pwd\$sysinternalsCustomExe")
}

if(!$noExecute) {
    . .\$sysinternalsCustomExe -accepteula
}

# Display usage examples for psexec
if($sysinternalsCustomExe -ieq 'psexec.exe') {
    write-host "`nPsExec Usage Examples:" -ForegroundColor Cyan
    write-host "  Run as SYSTEM account:" -ForegroundColor Yellow
    write-host "    .\psexec.exe -s -i cmd.exe" -ForegroundColor Green
    write-host "    .\psexec.exe -s powershell.exe" -ForegroundColor Green
    write-host "`n  Run as NETWORK SERVICE account:" -ForegroundColor Yellow
    write-host "    .\psexec.exe -i -u `"NT AUTHORITY\NETWORK SERVICE`" cmd.exe" -ForegroundColor Green
    write-host "    .\psexec.exe -i -u `"NT AUTHORITY\NETWORK SERVICE`" powershell.exe" -ForegroundColor Green
    write-host "`n  Run on remote computer:" -ForegroundColor Yellow
    write-host "    .\psexec.exe \\\\computername -u domain\username cmd.exe" -ForegroundColor Green
    write-host "`n  Note: -i runs interactively with session 1 (console), -s runs as SYSTEM" -ForegroundColor Gray
}
  
