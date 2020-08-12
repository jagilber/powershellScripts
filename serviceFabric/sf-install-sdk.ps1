# checks and installs webpi and sf sdk

param(
    [string]$sfsdk = 'C:\Program Files\Microsoft SDKs\Service Fabric\Compatibility\SdkRuntimeCompatibility.json',
    [string]$webpiCmd = 'C:\Program Files\Microsoft\Web Platform Installer\webpiCmd-x64.exe',
    [string]$webpiUrl = 'https://go.microsoft.com/fwlink/?LinkId=287166',
    [switch]$force
)

if ($force -or !(test-path $sfsdk)) {
    if (!(test-path $webpiCmd)) {
        $webpiMsi = "$env:temp\webpi.msi"

        write-host "downloading webpi" -foregroundColor cyan
        write-host "invoke-webRequest $webpiUrl -outFile $webpiMsi"
        invoke-webRequest "$webpiUrl" -outFile "$webpiMsi"

        write-host "installing webpi" -foregroundColor cyan
        write-host "start-process -filePath $webpiMsi -argumentlist /quiet /norestart -wait"
        start-process -filePath "$webpiMsi" -argumentlist "/quiet /norestart" -wait
    }

    write-host "installing sf sdk" -foregroundColor cyan
    write-host "start-process -filePath $webpiCmd -argumentList /install /products:MicrosoftAzure-ServiceFabric-CoreSDK /acceptEULA /suppressReboot -wait"

    start-process -filePath "$webpiCmd" -argumentList "/install /products:MicrosoftAzure-ServiceFabric-CoreSDK /acceptEULA /suppressReboot" -wait
    write-host "finished"
}
else {
    write-host "sf sdk already installed. use -force to install latest" -foregroundColor cyan
    write-host (get-content $sfsdk)
}
