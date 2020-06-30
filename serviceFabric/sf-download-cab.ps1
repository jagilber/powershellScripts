# script to download all sf package versions to extract .man file into separate directory for parsing sf .etl files

param(
    [string]$sfversion,
    [switch]$all,
    [string]$sfPackageUrl = "https://go.microsoft.com/fwlink/?LinkID=824848&clcid=0x409",
    [switch]$force,
    [bool]$removeCab = $true,
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
    invoke-webrequest -uri ($package.TargetPackageLocation) -outfile "$outputFolder\$($package.Version).cab"

    if($extract -or $install) {
        expand "$outputFolder\$($package.Version).cab" -F:* "$outputFolder\$($package.Version)"
    }

    if ($removeCab) {
        remove-item "$outputFolder\$($package.Version).cab" -Force -Recurse
    }
}

if($install){
    $sfBinDir = "$outputFolder\$($package.Version)\bin\Fabric\Fabric.Code"
    start-process -Wait -FilePath "$sfBinDir\FabricSetup.exe" -ArgumentList "/operation:install" -WorkingDirectory $sfBinDir -NoNewWindow
}