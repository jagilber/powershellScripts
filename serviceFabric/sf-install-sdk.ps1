# test script using voting application to perform deploy-fabricapplication from node
# installs webpi and sf sdk if needed
 
param(
    $sfsdk = 'C:\Program Files\Microsoft SDKs\Service Fabric\Tools\PSModule\ServiceFabricSDK',
    $webpiDir = 'C:\Program Files\Microsoft\Web Platform Installer',
    $webpiUrl = 'https://go.microsoft.com/fwlink/?LinkId=287166'
)
 
$startTimer = get-date
 
if (!(test-path $sfsdk)) {
    if (!(test-path $webpiDir)) {
        write-host "download webpi"
        invoke-webrequest $webpiUrl -OutFile $pwd\webpi.msi
 
        write-host "install webpi"
        Start-Process -FilePath "$pwd\webpi.msi" -argumentlist "/quiet /norestart" -wait
    }
 
    Start-Process -FilePath "$webpiDir\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:MicrosoftAzure-ServiceFabric-CoreSDK /AcceptEULA /SuppressReboot" -wait
 
}

 
write-host "finished: $((get-date) - $startTimer)"
 

