<#
script to convert service fabric .etl trace files to .csv text format
script must be run from node
#>
param(
    $sfLogDir = "d:\svcfab\log", # "d:\svcfab\log\traces",
    $outputDir = "d:\temp",
    $fileFilter = "*.etl",
    $sfDownloadCabScript = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-download-cab.ps1",
    [switch]$force,
    [switch]$clean,
    [int]$etlMaxProcessorInstance = 4
)

# D:\SvcFab\Log\work\WFEtwMan
$ErrorActionPreference = "silentlycontinue"
$netsh = "netsh"

function main() {

    # run as administrator
    if(!runas-admin) { return }

    $pattern = "([0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4})"
    $count = 0

    # sf installed?
    $sfInstalledVersion = (get-itemproperty -ErrorAction SilentlyContinue 'HKLM:\SOFTWARE\Microsoft\Service Fabric' FabricVersion).FabricVersion
    
    if ($sfInstalledVersion) {
        Write-Warning "service fabric is installed. file version: $sfInstalledVersion"    
    }
    
    if ((get-process fabric*)) {
        Write-Warning "fabric is running! will not modify version"
        $force = $false
    }


    # etl files?
    New-Item -ItemType Directory -Path $outputDir
    $etlFiles = @([io.directory]::GetFiles($sfLogDir, $fileFilter, [IO.SearchOption]::AllDirectories))
    $totalFiles = $etlFiles.count
    $etlFileVersion = ([regex]::Match(($etlFiles -join ","), "`_$pattern`_", [text.regularexpressions.regexoptions]::ignorecase)).Groups[1].Value
    Write-Host "etl file version: $etlFileVersion"
    Write-Host "etl files count: $totalFiles"
    
    if ($etlFiles.count -lt 1) {
        write-error "no $fileFilter files found in $sflogdir"
        return
    }

    $sfBinDir = $null

    if (($sfInstalledVersion -ne $etlFileVersion) -and $force) {
        $sfCabScript = "$pwd\$([io.path]::GetFileName($sfDownloadCabScript))"

        if (!(test-path $sfCabScript)) {
            write-host "downloading $sfCabScript"
            (new-object net.webclient).DownloadFile($sfDownloadCabScript, $sfCabScript)
        }

        . $sfCabScript -sfversion $etlFileVersion -outputfolder $outputDir
        $sfBinDir = "$outputDir\$etlFileVersion\bin\Fabric\Fabric.Code"
        write-host "start-process -Wait -FilePath '$sfBinDir\FabricSetup.exe' -ArgumentList '/operation:uninstall' -WorkingDirectory $sfBinDir -NoNewWindow" -ForegroundColor Green
        start-process -Wait -FilePath "$sfBinDir\FabricSetup.exe" -ArgumentList "/operation:uninstall" -WorkingDirectory $sfBinDir -NoNewWindow
        write-host "start-process -Wait -FilePath '$sfBinDir\FabricSetup.exe' -ArgumentList '/operation:install' -WorkingDirectory $sfBinDir -NoNewWindow" -ForegroundColor green
        start-process -Wait -FilePath "$sfBinDir\FabricSetup.exe" -ArgumentList "/operation:install" -WorkingDirectory $sfBinDir -NoNewWindow

    }

    foreach ($etlFile in $etlFiles) {
        monitor-processes -maxCount $etlMaxProcessorInstance
        $count++
        write-host "file $count of $totalFiles"
        $outputFile = "$outputDir\$([io.path]::GetFileNameWithoutExtension($etlFile)).dtr.csv"
        write-host "netsh trace convert input=`"$etlFile`" output=`"$outputFile`" report=no overwrite=yes"
        start-process -FilePath $netsh -ArgumentList "trace convert input=`"$etlFile`" output=`"$outputFile`" report=no overwrite=yes" -NoNewWindow
    }
    
    # wait for all processes to finish
    monitor-processes -maxCount 0

    if ((!$sfInstalledVersion -and $clean) -or ($clean -and $force)) {
        start-process -Wait -FilePath "FabricSetup.exe" -ArgumentList "/operation:uninstall" -WorkingDirectory $sfBinDir -NoNewWindow
    }

    Write-Host "complete"

}

function monitor-processes($maxCount) {
    while ($true) {
        if((get-process) -match $netsh) {
            $instanceCount = (get-process -Name ($netsh)).Length
            write-host "instance count:$($instanceCount)"

            if($instanceCount -ge $maxCount) {
                write-host "waiting for $($netsh) instances to finish."
                write-host " current instance count: $($instanceCount) seconds waiting: $($count++)"
                start-sleep -Seconds 1
                continue
            }
        }
        break
    }
}

function runas-admin() {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {   
       write-host "please restart script as administrator. exiting..."
       return $false
    }
    return $true
}

main
write-host "finished"
