<#
install winget on Windows Server 2022 for windbg

https://ekremsaydam.com.tr/install-winget-cli-and-windows-terminal-apps-for-windows-server-2022-cee6c8078313
https://github.com/microsoft/winget-cli/issues/1861
https://github.com/microsoft/winget-cli/issues/700
.\azure-az-vmss-run-command.ps1 -resourceGroup  -vmssName nodetype1 -script .\drafts\draft-server-winget.ps1

C:\Program Files (x86)\Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.VCLibs.Desktop\14.0\AppX\Microsoft.VCLibs.x64.14.00.Desktop.appx
#>

# Invoke-WebRequest -Uri https://github.com/microsoft/winget-cli/releases/download/v1.4.10173/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle -OutFile .\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
# Invoke-WebRequest -Uri https://github.com/microsoft/winget-cli/releases/download/v1.4.10173/3463fe9ad25e44f28630526aa9ad5648_License1.xml -OutFile .\3463fe9ad25e44f28630526aa9ad5648_License1.xml
# Add-AppxProvisionedPackage -Online -PackagePath .\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle -LicensePath .\3463fe9ad25e44f28630526aa9ad5648_License1.xml -Verbose

param(
  [string]$xamlDownloadUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6",
  [string]$xamlPath = "$pwd\Microsoft.UI.Xaml.2.8.6.zip",
  [string]$appPackagePath = ".\microsoft.ui.xaml.2.8.6\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx",
  [string]$vcLibsPath = "C:\Program Files (x86)\Microsoft SDKs\Windows Kits\10\ExtensionSDKs\Microsoft.VCLibs.Desktop\14.0\AppX\Retail\x64\Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$vcLibsUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/refs/heads/master/windbg/Microsoft.VCLibs.x64.14.00.Desktop.appx",
  [string]$wingetUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
)

if ($PSVersionTable.PSVersion.Major -gt 5) {
  Write-Warning "This script requires PowerShell 5. use powershell.exe"
  return
}

$vcLibsAppx = $vcLibsPath.Split("\")[-1]
if (!(test-path $vcLibsPath)) {
  $vcLibsPath = "$pwd\$vcLibsAppx"
  if(!(test-path $vcLibsPath)) {
    [net.webclient]::new().DownloadFile($vcLibsUrl, $vcLibsPath)
  }
}

if (!(Test-Path $vcLibsPath)) {
  Write-Error "VC Libs not found at $vcLibsPath. Please install the Windows SDK or Visual Studio 2022."
  return
}

if (!(test-path $xamlPath)) {
  [net.webclient]::new().DownloadFile($xamlDownloadUrl, $xamlPath)
  #Invoke-WebRequest -Uri https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6 -OutFile .\microsoft.ui.xaml.2.8.6.zip
  Expand-Archive $xamlPath
}
Add-AppxPackage $appPackagePath

$latestWingetMsixBundleUri = $(Invoke-RestMethod $wingetUrl).assets.browser_download_url | Where-Object { $psitem.EndsWith(".msixbundle") }
$latestWingetMsixBundle = $latestWingetMsixBundleUri.Split("/")[-1]

$latestWingetMsixLicenseUri = $(Invoke-RestMethod $wingetUrl).assets.browser_download_url | Where-Object { $psitem -imatch ".+license.+.xml" }
$latestWingetMsixLicense = $latestWingetMsixLicenseUri.Split("/")[-1]


if (!(test-path "$pwd/$latestWingetMsixBundle")) {

  write-host "Downloading winget to artifacts directory..."
  [net.webclient]::new().DownloadFile($latestWingetMsixBundleUri, "$pwd/$latestWingetMsixBundle")

  write-host "Downloading winget license to artifacts directory..."
  [net.webclient]::new().DownloadFile($latestWingetMsixLicenseUri, "$pwd/$latestWingetMsixLicense")

  #Invoke-WebRequest -Uri $latestWingetMsixBundleUri -OutFile "./$latestWingetMsixBundle"
  #[net.webclient]::new().DownloadFile("https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx", "$pwd/Microsoft.VCLibs.x64.14.00.Desktop.appx")
  #Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
}

write-host "Add-AppxPackage $vcLibsAppx"
Add-AppxPackage $vcLibsAppx

write-host "Add-AppxPackage $latestWingetMsixBundle"
Add-AppxPackage $latestWingetMsixBundle
