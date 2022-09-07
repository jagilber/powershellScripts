<# 
.SYNOPSIS
script to download all sf package versions to extract .man file into separate directory for parsing sf .etl files
.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-download-cab.ps1 -out $pwd/sf-download-cab.ps1;
./sf-download-cab.ps1 
#>

param(
    [string]$sfversion,
    [switch]$all,
    [string]$sfPackageUrl = "https://go.microsoft.com/fwlink/?LinkID=824848&clcid=0x409",
    [string]$programDir = "c:\Program Files\Microsoft Service Fabric",
    [switch]$force,
    [bool]$removeCab = $false,
    [string]$outputFolder = $pwd,
    [bool]$extract = $true,
    [bool]$install = $false
)

$allPackages = @(invoke-restmethod $sfPackageUrl).Packages

if ($sfversion) {
    $packages = @($allPackages -imatch $sfversion)
}
elseif (!$all) {
    $packages = @($allPackages[-1])
}

if(!$packages) {
    write-host ($allPackages | out-string)
    write-warning "no packages found for $sfversion"
    return
}

$packages

foreach ($package in $packages) {
    $package

    if ((test-path "$outputFolder\$($package.Version)") -and !$force) {
        write-warning "package $($package.Version) exists. use force to download"
        continue
    }

    mkdir "$outputFolder\$($package.Version)"
    [net.webclient]::new().DownloadFile($package.TargetPackageLocation,"$outputFolder\$($package.Version).cab")

    if($extract -or $install) {
        expand "$outputFolder\$($package.Version).cab" -F:* "$outputFolder\$($package.Version)"
    }

    if ($removeCab) {
        remove-item "$outputFolder\$($package.Version).cab" -Force -Recurse
    }
}

if($install){
    $sfBinDir = "$programDir\bin\Fabric\Fabric.Code"
    write-host "Copy-Item `"$outputFolder\$($package.Version)`" $programDir -Recurse -Force"
    Copy-Item "$outputFolder\$($package.Version)" $programDir -Recurse -Force
    write-host "start-process -Wait -FilePath `"$sfBinDir\FabricSetup.exe`" -ArgumentList `"/operation:install`" -WorkingDirectory $sfBinDir -NoNewWindow"
    start-process -Wait -FilePath "$sfBinDir\FabricSetup.exe" -ArgumentList "/operation:install" -WorkingDirectory $sfBinDir -NoNewWindow
}