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
    [switch]$latest,
    [string]$sfPackageUrl = "https://go.microsoft.com/fwlink/?LinkID=824848&clcid=0x409",
    [string]$programDir = "c:\Program Files\Microsoft Service Fabric",
    [switch]$force,
    [bool]$removeCab = $false,
    [string]$outputFolder = $pwd,
    [bool]$extract = $false,
    [bool]$install = $false
)

write-host "invoke-restmethod $sfPackageUrl"
$global:allPackages = @(invoke-restmethod $sfPackageUrl).Packages
if (!$allPackages) {
    write-warning "no packages found at $sfPackageUrl"
    return
}
write-host "found $($allPackages.Count) packages at $sfPackageUrl"
write-host "all packages: $($allPackages | Format-Table * -AutoSize -Wrap| out-string)"

if ($sfversion) {
    $packages = @($allPackages -imatch $sfversion)
}
elseif ($all) {
    $packages = @($allPackages)
}
elseif ($latest) {
    $packages = @($allPackages[-1])
}
else {
    write-host ($allPackages | out-string)
    write-host "specify -sfversion or -all or -latest"
    return
}

if (!$packages) {
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

    write-host "downloading package $($package.Version) to $outputFolder\$($package.Version).cab"
    if (!(test-path $outputFolder)) {
        write-host "creating output folder $outputFolder"
        new-item -ItemType Directory -Path $outputFolder | out-null
    }
    mkdir "$outputFolder\$($package.Version)"
    write-host "[net.webclient]::new().DownloadFile($($package.TargetPackageLocation), $outputFolder\$($package.Version).cab)"
    [net.webclient]::new().DownloadFile($package.TargetPackageLocation, "$outputFolder\$($package.Version).cab")

    if ($extract -or $install) {
        write-host "extracting package $($package.Version) to $outputFolder\$($package.Version)"
        expand "$outputFolder\$($package.Version).cab" -F:* "$outputFolder\$($package.Version)"
    }

    if ($removeCab) {
        write-host "removing cab file $outputFolder\$($package.Version).cab"
        remove-item "$outputFolder\$($package.Version).cab" -Force -Recurse
    }
}

if ($install) {
    $sfBinDir = "$programDir\bin\Fabric\Fabric.Code"
    write-host "Copy-Item `"$outputFolder\$($package.Version)`" $programDir -Recurse -Force"
    Copy-Item "$outputFolder\$($package.Version)" $programDir -Recurse -Force
    write-host "start-process -Wait -FilePath `"$sfBinDir\FabricSetup.exe`" -ArgumentList `"/operation:install`" -WorkingDirectory $sfBinDir -NoNewWindow"
    start-process -Wait -FilePath "$sfBinDir\FabricSetup.exe" -ArgumentList "/operation:install" -WorkingDirectory $sfBinDir -NoNewWindow
}