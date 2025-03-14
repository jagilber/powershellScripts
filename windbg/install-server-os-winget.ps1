<#
install winget on Windows Server 2022 for windbg

winget search microsoft.windbg
winget install microsoft.windbg
https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-sos
https://www.nuget.org/api/v2/package/dotnet-sos/9.0.553101
dotnet tool install --global dotnet-sos
https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-debugger-extensions
dotnet tool install --global dotnet-debugger-extensions
https://www.nuget.org/api/v2/package/dotnet-debugger-extensions/9.0.557512


https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options?view=windows-11
DISM.exe /Online [/Get-ProvisionedAppxPackages | /Add-ProvisionedAppxPackage | /Remove-ProvisionedAppxPackage | /Set-ProvisionedAppxDataFile | /StubPackageOption]
Dism /online /Get-ProvisionedAppxPackages /?

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/windbg/install-server-os-winget.ps1" -outFile "$pwd\install-server-os-winget.ps1";
    .\install-server-os-winget.ps1

#>

param(
  [string]$xamlDownloadUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6",
  [string]$xamlPath = "$pwd\Microsoft.UI.Xaml.2.8.6.zip",
  [string]$appPackagePath = ".\microsoft.ui.xaml.2.8.6\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx",
  [string]$vcLibsPath = "C:\Program Files (x86)\Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.VCLibs.Desktop\14.0\AppX\Retail\x64\Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$vcLibsUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/refs/heads/master/windbg/Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$wingetUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest",
  [switch]$installCoreSdk,
  [string]$defaultWingetPath = "$env:LocalAppData\Microsoft\WindowsApps\winget.exe",
  [string]$logPath = "$pwd\install-server-os-winget.log" # %WINDIR%\Logs\Dism\dism.log
)

$ErrorActionPreference = 'continue'
$script = $MyInvocation.MyCommand.Definition
$scriptParams = $MyInvocation.BoundParameters


function main() {
  write-host "executing $script with parameters $($scriptParams | out-string)" -ForegroundColor Green
  
  if (is-wingetInstalled) {
    write-host "winget is already installed" -ForegroundColor Green
    return
  }

  if ($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Warning "This script requires PowerShell 5. switching to powershell.exe"
    powershell $script @scriptParams
    return
  }

  $vcLibsAppx = $vcLibsPath.Split("\")[-1]
  if (!(test-path $vcLibsPath)) {
    $vcLibsPath = "$pwd\$vcLibsAppx"
    if (!(test-path $vcLibsPath)) {
      write-host "downloading file $vcLibsUrl to $vcLibsPath"
      [net.webclient]::new().DownloadFile($vcLibsUrl, $vcLibsPath)
    }
  }

  if (!(Test-Path $vcLibsPath)) {
    Write-Error "VC Libs not found at $vcLibsPath. Please install the Windows SDK or Visual Studio 2022."
    return
  }

  if (!(test-path $xamlPath)) {
    [net.webclient]::new().DownloadFile($xamlDownloadUrl, $xamlPath)
    Expand-Archive $xamlPath
  }

  write-host "Add-AppxPackage $appPackagePath"
  Add-AppxPackage $appPackagePath -verbose

  $latestWingetMsixBundleUri = $(Invoke-RestMethod $wingetUrl).assets.browser_download_url | Where-Object { $psitem.EndsWith(".msixbundle") }
  $latestWingetMsixBundle = "$pwd\$($latestWingetMsixBundleUri.Split("/")[-1])"

  write-host "latestWingetMsixBundleUri: $latestWingetMsixBundleUri"
  write-host "latestWingetMsixBundle: $latestWingetMsixBundle"

  $latestWingetMsixLicenseUri = $(Invoke-RestMethod $wingetUrl).assets.browser_download_url | Where-Object { $psitem -imatch ".+license.+.xml" }
  $latestWingetMsixLicense = "$pwd\$($latestWingetMsixLicenseUri.Split("/")[-1])"

  write-host "latestWingetMsixLicenseUri: $latestWingetMsixLicenseUri"
  write-host "latestWingetMsixLicense: $latestWingetMsixLicense"

  if (!(test-path $latestWingetMsixBundle) -or !(test-path $latestWingetMsixLicense)) {
    download-file $latestWingetMsixBundleUri $latestWingetMsixBundle
    download-file $latestWingetMsixLicenseUri $latestWingetMsixLicense
  }

  write-host "Add-AppxPackage $vcLibsAppx"
  Add-AppxPackage $vcLibsAppx -verbose

  # installing with Add-AppxPackage makes winget available immediately
  write-host "Add-AppxPackage $latestWingetMsixBundle -verbose"
  Add-AppxPackage $latestWingetMsixBundle -verbose

  # installing with Add-AppxProvisionedPackage is required to set the license
  # using only Add-AppxProvisionedPackage will not make winget available immediately
  write-host "Add-AppxProvisionedPackage -Online -PackagePath $latestWingetMsixBundle -LicensePath $latestWingetMsixLicense -Verbose -LogLevel Debug -LogPath $logPath"
  Add-AppxProvisionedPackage -Online -PackagePath $latestWingetMsixBundle -LicensePath $latestWingetMsixLicense -Verbose -LogLevel Debug -LogPath $logPath

  if (is-wingetInstalled) {
  
    write-host "winget search microsoft.windbg"
    winget search microsoft.windbg

    write-host "winget install microsoft.windbg --source winget"
    winget install microsoft.windbg --source winget

    write-host "winget search microsoft.timeTravelDebugging"
    winget search microsoft.timeTravelDebugging

    write-host "winget install microsoft.timeTravelDebugging --source winget"
    winget install microsoft.timeTravelDebugging --source winget
    
  }
  else {
    Write-Error "winget not found. Please restart your shell."
  }

  $hasNetCoreRuntime = (dotnet --list-runtimes) -imatch "NETCore"
  $hasNetCoreSdk = (dotnet --list-sdks) -imatch "NETCore"

  if($installCoreSdk -and !$hasNetCoreSdk -and $hasNetCoreRuntime) {
    write-host "installing latest .NET Core SDK"
    $latestNetCoreRuntime = @((dotnet --list-runtimes) -imatch 'netcore')[-1] #-match '\d+\.\d+\.\d+'
    $latestNetCoreVersion = $latestNetCoreRuntime -replace '.*(\d+\.\d+\.\d+).*', '$1'
    $lastestNetCoreMajorVersion = $latestNetCoreVersion -replace '(\d+)\.\d+\.\d+', '$1'
    
    write-host "winget search 'Microsoft.DotNet.SDK.$lastestNetCoreMajorVersion'"
    winget search "Microsoft.DotNet.SDK.$lastestNetCoreMajorVersion"

    write-host "winget install 'Microsoft.DotNet.SDK.$lastestNetCoreMajorVersion'"
    winget install "Microsoft.DotNet.SDK.$lastestNetCoreMajorVersion"
  }
  # dotnet tool is not installed by default on Windows Server and is installed with the .NET SDK
  if ((get-command dotnet -ErrorAction SilentlyContinue) -and (dotnet --list-sdks)) {
    write-host "dotnet found. installing dotnet-sos"
    dotnet tool install --global dotnet-sos
    write-host "installing dotnet-debugger-extensions"
    dotnet tool install --global dotnet-debugger-extensions
  }
  else {
    write-host "dotnet sdk not found. skipping dotnet tool installs. winget install 'Microsoft.DotNet.SDK.9'" -ForegroundColor Yellow
  }
  
  write-host "finished"
}

function download-file($source, $destination) {
  $error.Clear()
  write-host "downloading file $source to $destination"
  [net.webclient]::new().DownloadFile($source, $destination)
  if ($error.Count -gt 0) {
    write-host "error downloading file $source to $destination" -ForegroundColor Red
    $error
    return $false
  }
  else {
    write-host "downloaded file $source to $destination" -ForegroundColor Green
    return $true
  }
}

function is-wingetInstalled() {
  $isInstalled = get-command winget -ErrorAction SilentlyContinue
  write-host "is-wingetInstalled: $isInstalled" -ForegroundColor Magenta
  return $isInstalled
}

function resolve-envPath($item) {
  write-host "resolving $item"
  $item = [environment]::ExpandEnvironmentVariables($item)
  $sepChar = [io.path]::DirectorySeparatorChar

  if ($result = Get-Item $item -ErrorAction SilentlyContinue) {
    return $result.FullName
  }

  $paths = [collections.arraylist]@($env:Path.Split(";"))
  [void]$paths.Add((@($psscriptroot, $pwd) | select-object -first 1))

  foreach ($path in $paths) {
    if ($result = Get-Item ($path.trimend($sepChar) + $sepChar + $item.trimstart($sepChar)) -ErrorAction SilentlyContinue) {
      return $result.FullName
    }
  }

  Write-Warning "unable to find $item"
  return $null
}

main