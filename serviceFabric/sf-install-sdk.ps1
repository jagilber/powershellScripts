<# 
.SYNOPSIS
checks and installs webpi and sf sdk
.LINK
iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-install-sdk.ps1 -out $pwd/sf-install-sdk.ps1;
./sf-install-sdk.ps1 
#>


param(
    [string]$sfsdk = 'C:\Program Files\Microsoft SDKs\Service Fabric\Compatibility\SdkRuntimeCompatibility.json',
    [string]$webpiCmd = 'C:\Program Files\Microsoft\Web Platform Installer\webpiCmd-x64.exe',
    [string]$webpiUrl = 'https://go.microsoft.com/fwlink/?LinkId=287166',
    [switch]$force
)

function main () {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (!$isAdmin -and $force) {
        write-error "restarting script as administrator."
        $command = "powershell.exe"

        if ($PSVersionTable.PSEdition -ieq 'core') {
            $command = "pwsh.exe"
        }

        write-host "start-process -wait -verb RunAs -FilePath $command -ArgumentList `"-file $($MyInvocation.ScriptName) --force:$force -noexit -workingDirectory $pwd`""
        start-process -wait -verb RunAs -FilePath $command -ArgumentList "-file $($MyInvocation.ScriptName) --force:$force -noexit -interactive -workingDirectory $pwd"
        return
    }
    elseif (!$isAdmin) {
        write-error "restart script as administrator."
        return
    }

    if ($force -or !(test-path $sfsdk)) {
        $webpiMsi = "$env:temp\webpi.msi"

        if (!(test-path $webpiMsi)) {
            write-host "downloading webpi" -foregroundColor cyan
            write-host "invoke-webRequest $webpiUrl -outFile $webpiMsi"
            if (!(invoke-webRequest "$webpiUrl" -outFile "$webpiMsi")) {
                write-error "unable to download $webpiMsi"
                if (!$force) {return}
            }
        }

        write-host "installing webpi" -foregroundColor cyan
        write-host "start-process -wait -filePath $webpiMsi -argumentlist /package $webpiMsi /quiet /norestart"

        if (!(start-process -wait -filePath msiexec.exe -argumentlist "/package $webpiMsi /quiet /norestart")) {
            write-error "unable to install $webpiMsi"
            if (!$force) {return}
        }

        write-host "installing sf sdk" -foregroundColor cyan
        write-host "start-process -wait -filePath $webpiCmd -argumentList /install /products:MicrosoftAzure-ServiceFabric-CoreSDK /acceptEULA /suppressReboot"

        if (!(start-process -wait -filePath "$webpiCmd" -argumentList "/install /products:MicrosoftAzure-ServiceFabric-CoreSDK /acceptEULA /suppressReboot")) {
            write-error "unable to install $webpiMsi"
            if (!$force) {return}
        }

        write-host (get-content $sfsdk)
        write-host "finished"
    }
    else {
        write-host "sf sdk already installed. use -force to install latest" -foregroundColor cyan
        write-host (get-content $sfsdk)
    }
}

main
start-sleep -Seconds 10