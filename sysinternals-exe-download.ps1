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
  
