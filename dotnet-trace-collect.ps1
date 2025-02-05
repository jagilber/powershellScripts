<#
# needs dotnet sdk and dotnet-trace
dotnet tool install --global dotnet-trace
https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script
#>
param(
  [string]$name = "ManagedIdentityTokenService",
  [string]$traceFile = "$($name).nettrace",
  [int]$logLevel = 5,
  [string]$keywords = '0xffffffffffffffff',
  [hashtable]$providers = @{
    "Microsoft-Windows-Crypto-RSAEnh"                            = $logLevel
    "Microsoft-Windows-Crypto-BCrypt"                            = $logLevel
    "Microsoft-Windows-Crypto-CAPI2"                             = $logLevel
    "Microsoft.AspNetCore.Server.Kestrel"                        = $logLevel
    "Microsoft.AspNetCore.Server.Kestrel.BadRequests"            = $logLevel
    "Microsoft.AspNetCore.Server.Kestrel.Connections"            = $logLevel
    "Microsoft.AspNetCore.Server.Kestrel.Http2"                  = $logLevel
    "Microsoft.AspNetCore.Server.Kestrel.Http3"                  = $logLevel
    "System.Net"                                                 = $logLevel
    "System.Net.AspNetCore.Http"                                 = $logLevel
    "System.Net.AspNetCore"                                      = $logLevel
    "System.Net.Http"                                            = $logLevel
    "System.Net.NameResolution"                                  = $logLevel
    "System.Net.Sockets"                                         = $logLevel
    "System.Net.Security"                                        = $logLevel
    "System.Net.TestLogging"                                     = $logLevel
    "Private.InternalDiagnostics.System.Net.Http"                = $logLevel
    "Private.InternalDiagnostics.System.Net.NameResolution"      = $logLevel
    "Private.InternalDiagnostics.System.Net.Sockets"             = $logLevel
    "Private.InternalDiagnostics.System.Net.Security"            = $logLevel
    "Private.InternalDiagnostics.System.Net.Quic"                = $logLevel
    "Private.InternalDiagnostics.System.Net.Http.WinHttpHandler" = $logLevel
    "Private.InternalDiagnostics.System.Net.HttpListener"        = $logLevel
    "Private.InternalDiagnostics.System.Net.Mail"                = $logLevel
    "Private.InternalDiagnostics.System.Net.NetworkInformation"  = $logLevel
    "Private.InternalDiagnostics.System.Net.Primitives"          = $logLevel
    "Private.InternalDiagnostics.System.Net.Requests"            = $logLevel
  },
  [string]$dotnetSdkScriptUrl = "https://dot.net/v1/dotnet-install.ps1",
  [string]$version = "6.0.428",
  [switch]$whatIf
)

if (!(get-command dotnet -ErrorAction SilentlyContinue)) {
  write-host "dotnet core is not installed. this script is only for .net core projects"
  return
}

if (!(dotnet --list-sdks)) {
  $downloadFile = "$pwd\dotnet-install.ps1"
  write-host "dotnet sdk is not installed. Please install it from https://dotnet.microsoft.com/download"
  $install = read-host "Do you want to install it now? (y/n)"
  if ($install -ne "y") {
    return
  }
  invoke-webRequest -uri $dotnetSdkScriptUrl -outFile $downloadFile
  . $downloadFile -version $version
}

if (!(Get-Command dotnet-trace -ErrorAction SilentlyContinue)) {
  write-warning "dotnet-trace is not installed. Please install it using 'dotnet tool install --global dotnet-trace' *and* restart your shell"
  $install = read-host "Do you want to install it now? (y/n)"
  if ($install -ne "y") {
    return
  }
  dotnet tool install --global dotnet-trace
  $env:path += ";$env:USERPROFILE\.dotnet\tools"
}

$providersList = $providers.GetEnumerator() | ForEach-Object {
  $provider = $_.Key
  $level = $_.Value
  "$($provider):$($keywords):$($level)"
}

$providerListString = $providersList -join ","
write-host "dotnet-trace ps"
dotnet-trace ps

Write-Host "dotnet-trace collect -n $name --output $traceFile --providers $providerListString"
if ($whatIf) {
  return
}
else {
  dotnet-trace collect -n $name --output $traceFile --providers $providerListString
}