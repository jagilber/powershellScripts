param(
    [ValidateSet('livekd.exe','psexec.exe','procmon.exe','procdump.exe','procexp.exe','tcpview.exe','rammap.exe','handle.exe','pipelist.exe','winobj.exe')]
    $sysinternalsExe = "procdump.exe",
    $sysinternalsCustomExe,
    [switch]$noExecute
)

[net.ServicePointManager]::Expect100Continue = $true
[net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

if($sysinternalsCustomExe) { $sysinternalsExe = $sysinternalsCustomExe }

if(!(test-path $sysinternalsexe)){
    (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$sysinternalsexe","$pwd\$sysinternalsexe")
}

if(!$noExecute) {
    . .\$sysinternalsexe -accepteula
}
  