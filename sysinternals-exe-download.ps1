param(
    [ValidateSet('livekd.exe','psexec.exe','procmon.exe','procdump.exe','procexp.exe','tcpview.exe','rammap.exe','handle.exe','pipelist.exe','winobj.exe')]
    $sysinternalsExe = "procdump.exe",
    $sysinternalsCustomExe,
    [switch]$noExecute
)

[net.ServicePointManager]::Expect100Continue = $true
[net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

if(!$sysinternalsCustomExe) { $sysinternalsCustomExe = $sysinternalsExe}

if(!(test-path $sysinternalsexe)){
    (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$sysinternalsCustomExe","$pwd\$sysinternalsCustomExe")
}

if(!$noExecute) {
    . .\$sysinternalsCustomExe -accepteula
}
  