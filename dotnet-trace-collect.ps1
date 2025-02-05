<#
# needs dotnet sdk and dotnet-trace
dotnet tool install --global dotnet-trace
#>
param(
  $name = "ManagedIdentityTokenService",
  $providers = @{
    "Microsoft.AspNetCore.Server.Kestrel" = 5
    "Microsoft.AspNetCore.Server.Kestrel.BadRequests" = 5
    "Microsoft.AspNetCore.Server.Kestrel.Connections" = 5
    "Microsoft.AspNetCore.Server.Kestrel.Http2" = 5
    "Microsoft.AspNetCore.Server.Kestrel.Http3" = 5
    "System.Net" = 5
    "System.Net.AspNetCore.Http" = 5
    "System.Net.AspNetCore" = 5
    "System.Net.Http" = 5
    "System.Net.NameResolution" = 5
    "System.Net.Sockets" = 5
    "System.Net.Security" = 5
    "System.Net.TestLogging" = 5
    "Private.InternalDiagnostics.System.Net.Http" = 5
    "Private.InternalDiagnostics.System.Net.NameResolution" = 5
    "Private.InternalDiagnostics.System.Net.Sockets" = 5
    "Private.InternalDiagnostics.System.Net.Security" = 5
    "Private.InternalDiagnostics.System.Net.Quic" = 5
    "Private.InternalDiagnostics.System.Net.Http.WinHttpHandler" = 5
    "Private.InternalDiagnostics.System.Net.HttpListener" = 5
    "Private.InternalDiagnostics.System.Net.Mail" = 5
    "Private.InternalDiagnostics.System.Net.NetworkInformation" = 5
    "Private.InternalDiagnostics.System.Net.Primitives" = 5
    "Private.InternalDiagnostics.System.Net.Requests" = 5
  },
  [string]$traceFile = "$($name).trace",
  [string]$dotnetSdkScriptUrl = "https://dot.net/v1/dotnet-install.ps1",
  [string]$version = "6.0",
  [switch]$whatIf
)

if(!(get-command dotnet -ErrorAction SilentlyContinue)) {
  write-host "dotnet core is not installed. this script is only for .net core projects"
  return
}

if(!(dotnet --list-sdks)) {
  $downloadFile = "$pwd\dotnet-sdk-$version.exe"
  write-host "dotnet sdk is not installed. Please install it from https://dotnet.microsoft.com/download"
  $install = read-host "Do you want to install it now? (y/n)"
  if($install -ne "y") {
    return
  }
  invoke-webRequest -uri $dotnetSdkScriptUrl -outFile $downloadFile
  . $downloadFile --version $version
}

if(!(Get-Command dotnet-trace -ErrorAction SilentlyContinue)) {
  write-warning "dotnet-trace is not installed. Please install it using 'dotnet tool install --global dotnet-trace' *and* restart your shell"
  return
}

$providersList = $providers.GetEnumerator() | ForEach-Object {
  $provider = $_.Key
  $level = $_.Value
  "$($provider):0xffffffffffffffff:$($level)"
}

$providerListString = $providersList -join ","

Write-Host "dotnet-trace collect -n $name --output $traceFile --providers $providerListString"
if($whatIf) {
  return
}
else{
  dotnet-trace collect -n $name --output $traceFile --providers $providerListString
}