<#
.SYNOPSIS
    Collects .NET Core traces using dotnet-trace.

.DESCRIPTION
    This script collects diagnostic traces for a specified .NET Core process using the dotnet-trace tool.
    It verifies whether the .NET SDK and dotnet-trace are installed and installs them if needed.
    The trace is then collected based on provided provider settings and other parameters.

.PARAMETER processName
    The name of the process to trace. Default: "ManagedIdentityTokenService".

.PARAMETER traceFile
    The file path to store the collected trace. Default: "$($processName).nettrace".

.PARAMETER logLevel
    The log level for trace providers. Default is 5.

.PARAMETER keywords
    The keywords filter for trace providers. Default is "0xffffffffffffffff".

.PARAMETER listProcesses
    When specified, lists all available processes for tracing and exits.

.PARAMETER providers
    A Hashtable defining provider names and their respective log levels.

.PARAMETER dotnetSdkScriptUrl
    The URL from which to download the dotnet-install script if the .NET SDK is missing.

.PARAMETER version
    The version of the .NET SDK to install if required.

.PARAMETER whatIf
    If specified, only displays the dotnet-trace command without executing it.

.EXAMPLE
    ./dotnet-trace-collect.ps1 -processName "MyApp" -traceFile "MyAppTrace.nettrace"

.EXAMPLE
    ./dotnet-trace-collect.ps1 -listProcesses

.NOTES
    Ensure that your PATH environment variable includes "$env:USERPROFILE\.dotnet\tools" after installing dotnet-trace.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;
    [net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/dotnet-trace-collect.ps1 -outfile $pwd\dotnet-trace-collect.ps1;. $pwd\dotnet-trace-collect.ps1
#>
param(
  [string]$processName = "ManagedIdentityTokenService",
  [string]$traceFile = "$($processName).nettrace",
  [int]$logLevel = 5,
  [string]$keywords = '0xffffffffffffffff',
  [switch]$listProcesses,
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
  if ($install -inotlike "y") {
    return
  }
  invoke-webRequest -uri $dotnetSdkScriptUrl -outFile $downloadFile
  . $downloadFile -version $version
}

if (!(Get-Command dotnet-trace -ErrorAction SilentlyContinue)) {
  write-warning "dotnet-trace is not installed. Please install it using 'dotnet tool install --global dotnet-trace' *and* restart your shell"
  $install = read-host "Do you want to install it now? (y/n)"
  if ($install -inotlike "y") {
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

if($listProcesses) {
  return
}

Write-Host "dotnet-trace collect -n $processName --output $traceFile --providers $providerListString"
if ($whatIf) {
  return
}
else {
  dotnet-trace collect -n $processName --output $traceFile --providers $providerListString
}