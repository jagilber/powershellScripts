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
#>

param(
  [string]$xamlDownloadUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6",
  [string]$xamlPath = "$pwd\Microsoft.UI.Xaml.2.8.6.zip",
  [string]$appPackagePath = ".\microsoft.ui.xaml.2.8.6\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx",
  [string]$vcLibsPath = "C:\Program Files (x86)\Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.VCLibs.Desktop\14.0\AppX\Retail\x64\Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$vcLibsUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/refs/heads/master/windbg/Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$wingetUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest",
  [int]$sleepSeconds = 5
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

  write-host "Add-AppxProvisionedPackage -Online -PackagePath $latestWingetMsixBundle -LicensePath $latestWingetMsixLicense -Verbose"
  Add-AppxProvisionedPackage -Online -PackagePath $latestWingetMsixBundle -LicensePath $latestWingetMsixLicense -Verbose

  write-host "sleeping for $sleepSeconds seconds"
  start-sleep -Seconds $sleepSeconds

  if (is-wingetInstalled) {
  
    write-host "winget search microsoft.windbg"
    winget search microsoft.windbg

    write-host "winget install microsoft.windbg --source winget"
    winget install microsoft.windbg --source winget
  }
  else {
    Write-Error "winget not found. Please restart your shell."
  }

  # dotnet tool is not installed by default on Windows Server and is installed with the .NET SDK
  if ((get-command dotnet -ErrorAction SilentlyContinue) -and (dotnet --list-sdks)) {
    write-host "dotnet found. installing dotnet-sos"
    dotnet tool install --global dotnet-sos
    write-host "installing dotnet-debugger-extensions"
    dotnet tool install --global dotnet-debugger-extensions
  }
  else {
    write-host "dotnet sdk not found. skipping dotnet tool installs" -ForegroundColor Yellow
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

main