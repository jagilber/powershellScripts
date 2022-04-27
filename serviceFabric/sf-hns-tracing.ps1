<#
.SYNOPSIS 
service fabric hns etl tracing script

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
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-hns-tracing.ps1" -outFile "$pwd\sf-hns-tracing.ps1";
.\sf-hns-tracing.ps1

#>

[cmdletbinding()]
param(
    # new file https://docs.microsoft.com/windows/win32/etw/logging-mode-constants
    $logFileMode = 8,

    # output file name and path
    $traceFilePath = 'D:\SvcFab\Log\CrashDumps\hns%d.etl',
    
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
        '{0c885e0d-6eb6-476c-a048-2457eed3a5c1}', # Microsoft-Windows-Host-Network-Service	
        '{28F7FB0F-EAB3-4960-9693-9289CA768DEA}',
        '{2F07E2EE-15DB-40F1-90EF-9D7BA282188A}', # Microsoft-Windows-TCPIP
        '{3AD15A04-74F1-4DCA-B226-AFF89085A05A}', # Microsoft-Windows-Wnv
        '{564368D6-577B-4af5-AD84-1C54464848E6}',
        '{6066F867-7CA1-4418-85FD-36E3F9C0600C}', # Microsoft-Windows-Hyper-V-VMMS
        '{66C07ECD-6667-43FC-93F8-05CF07F446EC}', # Microsoft-Windows-WinNat
        '{67DC0D66-3695-47C0-9642-33F76F7BD7AD}', # Microsoft-Windows-Hyper-V-VmSwitch
        '{6C28C7E5-331B-4437-9C69-5352A2F7F296}',
        '{80CE50DE-D264-4581-950D-ABADEEE0D340}',
        '{93f693dc-9163-4dee-af64-d855218af242}', # Microsoft-Windows-Host-Network-Management	
        '{9B322459-4AD9-4F81-8EEA-DC77CDD18CA6}',
        '{9F2660EA-CFE7-428F-9850-AECA612619B0}', # Microsoft-Windows-Hyper-V-VfpExt
        '{A111F1C2-5923-47C0-9A68-D0BAFB577901}',
        '{A6527853-5B2B-46E5-9D77-A4486E012E73}',
        '{A67075C2-3E39-4109-B6CD-6D750058A731}', # Microsoft-Windows-NetworkBridge
        '{AE3F6C6D-BF2A-4291-9D07-59E661274EE3}',
        '{B72C6994-9FE0-45AD-83B3-8F5885F20E0E}', # Microsoft-Windows-MsLbfoEventProvider
        '{D0E4BC17-34C7-43fc-9A72-D89A59D6979A}',
        '{DBC217A8-018F-4D8E-A849-ACEA31BC93F9}'
    )
)

$error.Clear()

if ((Get-AutologgerConfig -Name $traceName)) {
    write-warning "Remove-AutologgerConfig -Name $traceName"
    Remove-AutologgerConfig -Name $traceName
}

if($remove) { return }

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

