$url = "https://go.microsoft.com/fwlink/?linkid=2088631" 
$registryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
$version = (Get-ItemProperty -Path $registryPath -Name Version).Version
Write-Host $version

New-Item -ItemType Directory -Force -Path C:\temp\net_framework_48

$path = "C:\temp\net_framework_48\ndp48-x86-x64-allos-enu.exe" 
      
if(!(Split-Path -parent $path) -or !(Test-Path -pathType Container (Split-Path -parent $path))) { 
    $path = Join-Path $pwd (Split-Path -leaf $path) 
} 
      
"Downloading [$url]`nSaving at [$path]" 
$client = new-object System.Net.WebClient 
$client.DownloadFile($url, $path) 
      
$path

Invoke-Command -ScriptBlock { Start-Process -FilePath $path -ArgumentList "/q /log c:\temp\net_framework_48\net48.log /norestart "  -Wait -PassThru} 