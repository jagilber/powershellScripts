<#
.SYNOPSIS 
service fabric permanent etl tracing script

.DESCRIPTION
script will create a permanent ETL tracing session across reboots using powershell Autologger cmdlets.
default destination ($traceFilePath) is configured location used by FabricDCA for log staging.
files saved in D:\SvcFab\Log\CrashDumps\ will by uploaded by FabricDCA to 'sflogs' storage account fabriccrashdumps-{{cluster id}} container.
after upload, local files will be deleted by FabricDCA automatically.
default argument values should work for most scenarios.
add / remove etw tracing guids as needed. see get-etwtraceprovider / logman query providers
to remove tracing use -remove switch.

https://docs.microsoft.com/powershell/module/eventtracingmanagement/new-autologgerconfig

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-auto-etl-tracing.ps1" -outFile "$pwd\sf-auto-etl-tracing.ps1";
.\sf-auto-etl-tracing.ps1

#>

[cmdletbinding()]
param(
    # new file https://docs.microsoft.com/windows/win32/etw/logging-mode-constants
    $logFileMode = 8,

    # output file name and path
    $traceFilePath = 'D:\SvcFab\Log\CrashDumps\sfauto%d.etl',
    
    # output file size in MB
    $maxFileSizeMb = 64,
    
    # max ETW trace buffers
    $maxBuffers = 16,
    
    # buffer size in MB
    $bufferSize = 1024,
    
    # ETW trace session name
    $traceName = 'hns',
    
    # 6 == everything
    $level = 6,
    
    # 0xFFFFFFFFFFFFFFFF == everything
    $keyword = 18446744073709551615,
    
    # remove tracing session
    [switch]$remove,

    # etw trace provider guids array
    [string[]]$traceGuids = @(
        '{2F07E2EE-15DB-40F1-90EF-9D7BA282188A}', # Microsoft-Windows-TCPIP
        '{1C95126E-7EEA-49A9-A3FE-A378B03DDB4D}', # Microsoft-Windows-DNS-Client
        '{B1945E15-4933-460F-8103-AA611DDB663A}', # HttpSysProvider
        '{DD5EF90A-6398-47A4-AD34-4DCECDEF795F}', # HTTP Service Trace
        '{7B6BC78C-898B-4170-BBF8-1A469EA43FC5}' # HttpEvent
    )
)

$error.Clear()

if ((Get-AutologgerConfig -Name $traceName)) {
    write-warning "Remove-AutologgerConfig -Name $traceName"
    Remove-AutologgerConfig -Name $traceName
}

if ($remove) { return }

write-host "
New-AutologgerConfig -Name $traceName ``
    -LogFileMode $logFileMode ``
    -LocalFilePath $traceFilePath ``
    -MaximumFileSize $maxFileSizeMb ``
    -MaximumBuffers $maxBuffers ``
    -BufferSize $bufferSize
" -ForegroundColor Cyan

New-AutologgerConfig -Name $traceName `
    -LogFileMode $logFileMode `
    -LocalFilePath $traceFilePath `
    -MaximumFileSize $maxFileSizeMb `
    -MaximumBuffers $maxBuffers `
    -BufferSize $bufferSize

foreach ($guid in $traceGuids) {
    write-host "adding $guid
    Add-EtwTraceProvider -AutologgerName $traceName ``
        -Guid $guid ``
        -Level $level ``
        -MatchAnyKeyword $keyword
    " -ForegroundColor Cyan

    Add-EtwTraceProvider -AutologgerName $traceName `
        -Guid $guid `
        -Level $level `
        -MatchAnyKeyword $keyword

}

write-host "
Start-EtwTraceSession -Name $traceName ``
    -LogFileMode $logFileMode ``
    -LocalFilePath $traceFilePath ``
    -MaximumFileSize $maxFileSizeMb ``
    -MaximumBuffers $maxBuffers ``
    -BufferSize $bufferSize
" -ForegroundColor Cyan

Start-EtwTraceSession -Name $traceName `
    -LogFileMode $logFileMode `
    -LocalFilePath $traceFilePath `
    -MaximumFileSize $maxFileSizeMb `
    -MaximumBuffers $maxBuffers `
    -BufferSize $bufferSize

Get-AutologgerConfig -Name $traceName | format-list *
logman query -ets #$traceName
write-host "finished. to disable tracing, rerun script with -remove switch." -ForegroundColor Cyan

