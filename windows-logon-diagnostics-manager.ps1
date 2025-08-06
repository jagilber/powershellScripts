<#
.SYNOPSIS
    PowerShell script to enable/disable LSA, RPC, and SChannel diagnostic/debug registry entries

.DESCRIPTION
    This script manages Windows diagnostic and debug registry settings for:
    - LSA (Local Security Authority) debugging
    - RPC (Remote Procedure Call) debugging
    - SChannel (Secure Channel) logging
    
    The script can enable or disable these diagnostic features and provides backup/restore functionality.
    
    *** ALWAYS TEST IN LAB BEFORE USING IN PRODUCTION TO VERIFY FUNCTIONALITY ***
    Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement

    MIT License

    Copyright (c) Microsoft Corporation. All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE

.NOTES
    File Name  : windows-logon-diagnostics-manager.ps1
    Author     : jagilber
    Version    : 250806
    History    : Initial version
    
    Requires Administrator privileges to modify registry settings.
    **use in development / test environment only**

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -enableAll
    Enables all diagnostic logging (LSA, RPC, SChannel)

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -disableAll
    Disables all diagnostic logging

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -enableLsa -enableRpc
    Enables only LSA and RPC debugging

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -status
    Shows current status of all diagnostic settings

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -backup -backupFile "C:\temp\registry-backup.reg"
    Creates a backup of current settings

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -showLogInfo
    Shows detailed information about log destinations and ETW providers

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType "SChannel"
    Starts ETW tracing for SChannel events

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType "LSA2"
    Starts advanced ETW tracing for LSA with specific keywords for detailed authentication debugging

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -enableNetlogon
    Enables Netlogon debugging for authentication troubleshooting

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType AllProviders
    Starts comprehensive ETW tracing for all security providers

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType Authentication
    Starts comprehensive authentication ETW tracing

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -enableLsa -enableNetlogon -startEtwTrace -etwTraceType Authentication
    Enables LSA and Netlogon debugging plus starts authentication ETW tracing

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -disableAll -collectLogs
    Disables all diagnostic logging and automatically collects/zips all log files

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -stopEtwTrace -collectLogs
    Stops all ETW tracing and automatically collects/zips all ETL files

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -enableNetlogon -collectLogs -zipFile "C:\temp\netlogon-logs.zip"
    Enables Netlogon debugging with custom zip file location for log collection

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -stopEtwTrace -collectLogs
    Stops ETW tracing and collects all logs

.EXAMPLE
    .\windows-logon-diagnostics-manager.ps1 -disableAll -collectLogs
    Disables all diagnostics and collects logs

.PARAMETER enableAll
    Enable all diagnostic logging (LSA, RPC, SChannel)

.PARAMETER disableAll
    Disable all diagnostic logging

.PARAMETER enableLsa
    Enable LSA debugging

.PARAMETER disableLsa
    Disable LSA debugging

.PARAMETER enableRpc
    Enable RPC debugging

.PARAMETER disableRpc
    Disable RPC debugging

.PARAMETER enableSchannel
    Enable SChannel logging

.PARAMETER disableSchannel
    Disable SChannel logging

.PARAMETER enableNetlogon
    Enable Netlogon debugging (critical for authentication troubleshooting)

.PARAMETER disableNetlogon
    Disable Netlogon debugging

.PARAMETER status
    Show current status of all diagnostic settings

.PARAMETER backup
    Create a backup of current registry settings

.PARAMETER restore
    Restore registry settings from backup file

.PARAMETER showLogInfo
    Display detailed information about where logs are written and ETW providers

.PARAMETER startEtwTrace
    Start ETW trace sessions for diagnostic logging

.PARAMETER stopEtwTrace
    Stop ETW trace sessions for diagnostic logging

.PARAMETER etwTraceType
    Type of ETW trace to start/stop: LSA, LSA2, RPC, SChannel, Netlogon, Authentication, AllProviders, or All (default: All)

.PARAMETER backupFile
    Path to backup file (default: .\diagnostic-registry-backup.reg)

.PARAMETER logFile
    Path to log file (default: .\windows-diagnostic-registry-manager.log)

.PARAMETER collectLogs
    Automatically collect and zip log files when disabling registry settings or stopping ETW traces

.PARAMETER zipFile
    Path to zip file for collected logs (default: .\diagnostic-logs-YYYYMMDD-HHMMSS.zip)



.LINK
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/windows-logon-diagnostics-manager.ps1" -outFile "$pwd\windows-logon-diagnostics-manager.ps1";
.\windows-logon-diagnostics-manager.ps1 -status
#>

param(
    [switch]$enableAll,
    [switch]$disableAll,
    [switch]$enableLsa,
    [switch]$disableLsa,
    [switch]$enableRpc,
    [switch]$disableRpc,
    [switch]$enableSchannel,
    [switch]$disableSchannel,
    [switch]$enableNetlogon,
    [switch]$disableNetlogon,
    [switch]$status,
    [switch]$backup,
    [switch]$restore,
    [switch]$showLogInfo,
    [switch]$startEtwTrace,
    [switch]$stopEtwTrace,
    [string]$etwTraceType = "All", # LSA, LSA2, RPC, SChannel, Netlogon, Authentication, AllProviders, or All
    [string]$backupFile = ".\diagnostic-registry-backup.reg",
    [string]$logFile = ".\windows-diagnostic-registry-manager.log",
    [switch]$collectLogs,
    [string]$zipFile = ""
)

$error.Clear()
$ErrorActionPreference = "Continue"
$warningTime = 5

# Set default zip file name if not provided
if ([string]::IsNullOrEmpty($zipFile)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zipFile = ".\diagnostic-logs-$timestamp.zip"
}

# Registry paths and values for diagnostic settings
$registrySettings = @{
    LSA = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Values = @{
            "LspDbgInfoLevel" = 0xF000800
            "LspDbgTraceOptions" = 0x1
            # Additional registry values for maximum compatibility
            "DbgInfoLevel" = 0x2080FFFF
        }
        Description = "LSA (Local Security Authority) Debug Logging (ETW Recommended)"
        LogDestinations = @{
            FileLocation = "%SystemRoot%\debug\lsass.log"
            AdditionalFiles = @(
                "%SystemRoot%\debug\lsp.log"
            )
            EventLog = "System"
            ETWProviders = @(
                "Microsoft-Windows-LSA",
                "Microsoft-Windows-Authentication", 
                "Microsoft-Windows-Kerberos-KdcProxy",
                "Microsoft-Windows-Security-Kerberos"
            )
        }
    }
    RPC = @{
        Path = "HKLM:\SOFTWARE\Microsoft\Rpc\ClientProtocols"
        Values = @{
            "DebugFlag" = 7
            "CallFailureLoggingLevel" = 1
        }
        Description = "RPC (Remote Procedure Call) Debug Logging"
        AdditionalPaths = @{
            "HKLM:\SOFTWARE\Microsoft\Rpc\ServerProtocols" = @{
                "DebugFlag" = 7
                "CallFailureLoggingLevel" = 1
            }
        }
        LogDestinations = @{
            FileLocation = "%SystemRoot%\debug\rpc*.log (various RPC logs)"
            EventLog = "System"
            ETWProviders = @(
                "Microsoft-Windows-RPC",
                "Microsoft-Windows-RPC-Events",
                "Microsoft-Windows-RPC-FirewallManager",
                "Microsoft-Windows-RPC-Proxy-LBS",
                "Microsoft-Windows-RPC-Proxy-XDR"
            )
        }
    }
    SChannel = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL"
        Values = @{
            "EventLogging" = 7
        }
        Description = "SChannel (Secure Channel) Event Logging"
        AdditionalPaths = @{
            "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Logging" = @{
                "LogLevel" = 7
            }
        }
        LogDestinations = @{
            FileLocation = "N/A - SChannel primarily logs to Event Log and ETW"
            EventLog = "System (Event IDs: 36870, 36871, 36872, 36873, 36874, 36875, 36878, 36879, 36880, 36881, 36882, 36883, 36884, 36885, 36887, 36888)"
            ETWProviders = @(
                "Microsoft-Windows-Schannel-Events",
                "Schannel",
                "Microsoft-Windows-Security-SSP",
                "Microsoft-Windows-CAPI2"
            )
        }
    }
    Netlogon = @{
        Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        Values = @{
            "DBFlag" = 0x2080FFFF
            "LogFileMaxSize" = 20971520  # 20MB
        }
        Description = "Netlogon Debug Logging (Critical for Authentication Troubleshooting)"
        LogDestinations = @{
            FileLocation = "%SystemRoot%\debug\netlogon.log"
            AdditionalFiles = @(
                "%SystemRoot%\debug\netlogon.bak"
            )
            EventLog = "System"
            ETWProviders = @(
                "Microsoft-Windows-Security-Netlogon",
                "Microsoft-Windows-Directory-Services-SAM",
                "Microsoft-Windows-Directory-Services-SAM-Utility"
            )
        }
    }
}

# ETW trace session configurations for diagnostic logging
$etwTraceConfigs = @{
    LSA = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "Local Security Authority (LSA),LsaSrv,Microsoft-Windows-Kerberos-KdcProxy,Microsoft-Windows-Security-Kerberos"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Description = "ETW trace for LSA debugging"
    }
    LSA2 = @{
        SessionName = "Diagnostic-LSA2-Trace"
        Providers = "{D0B639E0-E650-4D1D-8F39-1580ADE72784}"
        OutputFile = ".\diagnostic-lsa2-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Keywords = 0x40141F
        Description = "ETW trace for advanced LSA debugging (separate session)"
    }
    RPC = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "Microsoft-Windows-RPC,Microsoft-Windows-RPC-Events,Microsoft-Windows-RPC-FirewallManager,Microsoft-Windows-RPC-Proxy-LBS"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Description = "ETW trace for RPC debugging"
    }
    SChannel = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "SChannel,Security: SChannel,Microsoft-Windows-Schannel-Events,Schannel,Microsoft-Windows-CAPI2"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Description = "ETW trace for SChannel debugging"
    }
    Netlogon = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "Microsoft-Windows-Security-Netlogon,Microsoft-Windows-Directory-Services-SAM,Microsoft-Windows-Directory-Services-SAM-Utility,Microsoft-Windows-Security-Kerberos"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Description = "ETW trace for Netlogon and authentication debugging"
    }
    Authentication = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "Microsoft-Windows-Security-Auditing,Microsoft-Windows-Winlogon,Microsoft-Windows-User Profiles Service,Microsoft-Windows-GroupPolicy,Microsoft-Windows-NTLM,Microsoft-Windows-Security-Kerberos,Microsoft-Windows-Security-Netlogon"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 2048
        MaxBuffers = 100
        Description = "Comprehensive ETW trace for authentication troubleshooting"
    }
    AllProviders = @{
        SessionName = "Diagnostic-Debug-Trace"
        Providers = "Local Security Authority (LSA),LsaSrv,Microsoft-Windows-Kerberos-KdcProxy,Microsoft-Windows-Security-Kerberos,Microsoft-Windows-RPC,Microsoft-Windows-RPC-Events,Microsoft-Windows-RPC-FirewallManager,Microsoft-Windows-RPC-Proxy-LBS,SChannel,Security: SChannel,Microsoft-Windows-Schannel-Events,Schannel,Microsoft-Windows-CAPI2,Microsoft-Windows-Security-Netlogon,Microsoft-Windows-Directory-Services-SAM,Microsoft-Windows-Directory-Services-SAM-Utility,Microsoft-Windows-Security-Auditing,Microsoft-Windows-Winlogon,Microsoft-Windows-User Profiles Service,Microsoft-Windows-GroupPolicy,Microsoft-Windows-NTLM"
        OutputFile = ".\diagnostic-debug-trace.etl"
        BufferSize = 4096
        MaxBuffers = 200
        Description = "Comprehensive ETW trace for all security-related providers (WARNING: High volume)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function main() {
    if (-not (Test-IsAdmin)) {
        Write-Error "This script requires Administrator privileges. Please run as Administrator."
        return
    }

    log-info "Starting Windows Diagnostic Registry Manager"
    log-info "Script version: 250805"
    log-info "Logfile: $logFile"

    if ($backup) {
        backup-registrySettings
        return
    }

    if ($restore) {
        restore-registrySettings
        return
    }

    if ($showLogInfo) {
        show-logInfo
        return
    }

    if ($startEtwTrace) {
        start-etwTrace -traceType $etwTraceType
        return
    }

    if ($stopEtwTrace) {
        stop-etwTrace -traceType $etwTraceType
        return
    }

    if ($status) {
        show-status
        return
    }

    if ($enableAll) {
        enable-allDiagnostics
    }
    elseif ($disableAll) {
        disable-allDiagnostics
    }
    else {
        if ($enableLsa) { enable-lsaDebugging }
        if ($disableLsa) { disable-lsaDebugging }
        # if ($enableRpc) { enable-rpcDebugging }  # Commented out due to registry access permission issues
        # if ($disableRpc) { disable-rpcDebugging }  # Commented out due to registry access permission issues
        if ($enableSchannel) { enable-schannelLogging }
        if ($disableSchannel) { disable-schannelLogging }
        if ($enableNetlogon) { enable-netlogonDebugging }
        if ($disableNetlogon) { disable-netlogonDebugging }
    }

    if (-not ($status -or $backup -or $restore)) {
        log-info ""
        log-info "Current status after changes:"
        show-status
    }

    log-info "Finished"
}

# ----------------------------------------------------------------------------------------------------------------
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $message"
    Write-Host $logMessage -ForegroundColor Green
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ----------------------------------------------------------------------------------------------------------------
function log-warning($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] WARNING: $message"
    Write-Host $logMessage -ForegroundColor Yellow
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ----------------------------------------------------------------------------------------------------------------
function log-error($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] ERROR: $message"
    Write-Host $logMessage -ForegroundColor Red
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ----------------------------------------------------------------------------------------------------------------
function ensure-registryPath($path) {
    if (-not (Test-Path $path)) {
        try {
            New-Item -Path $path -Force | Out-Null
            log-info "Created registry path: $path"
        }
        catch {
            log-error "Failed to create registry path: $path - $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# ----------------------------------------------------------------------------------------------------------------
function set-registryValue($path, $name, $value, $type = "DWORD") {
    try {
        if (-not (ensure-registryPath $path)) {
            return $false
        }

        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force
        log-info "Set $path\$name = $value"
        return $true
    }
    catch {
        log-error "Failed to set registry value $path\$name - $($_.Exception.Message)"
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-registryValue($path, $name) {
    try {
        if (Test-Path $path) {
            $property = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
            if ($property) {
                return $property.$name
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

# ----------------------------------------------------------------------------------------------------------------
function remove-registryValue($path, $name) {
    try {
        if ((Test-Path $path) -and (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -Path $path -Name $name -Force
            log-info "Removed $path\$name"
            return $true
        }
        return $true
    }
    catch {
        log-error "Failed to remove registry value $path\$name - $($_.Exception.Message)"
        return $false
    }
}

# ----------------------------------------------------------------------------------------------------------------
function enable-lsaDebugging {
    log-info "Enabling LSA debugging..."
    log-info "This will create log file: %SystemRoot%\debug\lsass.log"
    log-info "Note: The debug directory must exist for logging to work"
    $settings = $registrySettings.LSA
    
    # Ensure the debug directory exists
    $debugDir = "$env:SystemRoot\debug"
    if (-not (Test-Path $debugDir)) {
        try {
            New-Item -Path $debugDir -ItemType Directory -Force | Out-Null
            log-info "Created debug directory: $debugDir"
        }
        catch {
            log-warning "Failed to create debug directory: $debugDir - $($_.Exception.Message)"
            log-warning "LSA logging may not work without this directory"
        }
    }
    
    foreach ($valueName in $settings.Values.Keys) {
        $value = $settings.Values[$valueName]
        set-registryValue $settings.Path $valueName $value
    }
    
    log-info "LSA debugging enabled. Restart required for full effect."
    log-info "Expected log file location: $debugDir\lsass.log"
}

# ----------------------------------------------------------------------------------------------------------------
function disable-lsaDebugging {
    log-info "Disabling LSA debugging..."
    
    # Collect logs before disabling if requested
    if ($collectLogs) {
        log-info "Collecting LSA logs before disabling..."
        $lsaLogPath = [System.Environment]::ExpandEnvironmentVariables($registrySettings.LSA.LogDestinations.FileLocation)
        if (Test-Path $lsaLogPath) {
            Write-Host "LSA log file location: $lsaLogPath" -ForegroundColor Cyan
        }
        
        # Check for lsp.log as well
        $lspLogPath = "$env:SystemRoot\debug\lsp.log"
        if (Test-Path $lspLogPath) {
            $lspLogSize = (Get-Item $lspLogPath).Length / 1MB
            Write-Host "LSP log file location: $lspLogPath (Size: $([math]::Round($lspLogSize, 2)) MB)" -ForegroundColor Cyan
        } else {
            Write-Host "LSP log file not found: $lspLogPath (may not have been created)" -ForegroundColor Yellow
        }
    }
    
    $settings = $registrySettings.LSA
    
    foreach ($valueName in $settings.Values.Keys) {
        remove-registryValue $settings.Path $valueName
    }
    
    log-info "LSA debugging disabled. Restart required for full effect."
    
    if ($collectLogs) {
        collect-diagnosticLogs
    }
}

# ----------------------------------------------------------------------------------------------------------------
# NOTE: RPC debugging functions are temporarily disabled due to registry access permission requirements
# These functions require elevated admin privileges to modify HKLM:\SOFTWARE\Microsoft\Rpc registry keys
function enable-rpcDebugging {
    log-warning "RPC debugging is temporarily disabled due to registry access permission requirements"
    log-info "To enable RPC debugging, run this script as Administrator with elevated privileges"
    return
    
    log-info "Enabling RPC debugging..."
    $settings = $registrySettings.RPC
    
    # Main path
    foreach ($valueName in $settings.Values.Keys) {
        $value = $settings.Values[$valueName]
        set-registryValue $settings.Path $valueName $value
    }
    
    # Additional paths
    foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
        $pathValues = $settings.AdditionalPaths[$additionalPath]
        foreach ($valueName in $pathValues.Keys) {
            $value = $pathValues[$valueName]
            set-registryValue $additionalPath $valueName $value
        }
    }
    
    log-info "RPC debugging enabled. Restart required for full effect."
}

# ----------------------------------------------------------------------------------------------------------------
function disable-rpcDebugging {
    log-warning "RPC debugging is temporarily disabled due to registry access permission requirements"
    log-info "To disable RPC debugging, run this script as Administrator with elevated privileges"
    return
    
    log-info "Disabling RPC debugging..."
    
    # Collect logs before disabling if requested
    if ($collectLogs) {
        log-info "Collecting RPC logs before disabling..."
        $rpcLogPath = [System.Environment]::ExpandEnvironmentVariables($registrySettings.RPC.LogDestinations.FileLocation)
        Write-Host "RPC log file location: $rpcLogPath" -ForegroundColor Cyan
    }
    
    $settings = $registrySettings.RPC
    
    # Main path
    foreach ($valueName in $settings.Values.Keys) {
        remove-registryValue $settings.Path $valueName
    }
    
    # Additional paths
    foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
        $pathValues = $settings.AdditionalPaths[$additionalPath]
        foreach ($valueName in $pathValues.Keys) {
            remove-registryValue $additionalPath $valueName
        }
    }
    
    log-info "RPC debugging disabled. Restart required for full effect."
    
    if ($collectLogs) {
        collect-diagnosticLogs
    }
}

# ----------------------------------------------------------------------------------------------------------------
function enable-schannelLogging {
    log-info "Enabling SChannel logging..."
    $settings = $registrySettings.SChannel
    
    # Main path
    foreach ($valueName in $settings.Values.Keys) {
        $value = $settings.Values[$valueName]
        set-registryValue $settings.Path $valueName $value
    }
    
    # Additional paths
    foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
        $pathValues = $settings.AdditionalPaths[$additionalPath]
        foreach ($valueName in $pathValues.Keys) {
            $value = $pathValues[$valueName]
            set-registryValue $additionalPath $valueName $value
        }
    }
    
    log-info "SChannel logging enabled. Restart required for full effect."
}

# ----------------------------------------------------------------------------------------------------------------
function disable-schannelLogging {
    log-info "Disabling SChannel logging..."
    
    # Collect logs before disabling if requested
    if ($collectLogs) {
        log-info "Collecting SChannel logs before disabling..."
        Write-Host "SChannel logs are primarily in Event Log and ETW traces" -ForegroundColor Cyan
        Write-Host "Event Log: System (Event IDs: 36870-36888)" -ForegroundColor Cyan
    }
    
    $settings = $registrySettings.SChannel
    
    # Main path
    foreach ($valueName in $settings.Values.Keys) {
        remove-registryValue $settings.Path $valueName
    }
    
    # Additional paths
    foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
        $pathValues = $settings.AdditionalPaths[$additionalPath]
        foreach ($valueName in $pathValues.Keys) {
            remove-registryValue $additionalPath $valueName
        }
    }
    
    log-info "SChannel logging disabled. Restart required for full effect."
    
    if ($collectLogs) {
        collect-diagnosticLogs
    }
}

# ----------------------------------------------------------------------------------------------------------------
function enable-netlogonDebugging {
    log-info "Enabling Netlogon debugging..."
    log-info "This is CRITICAL for troubleshooting authentication failures, domain trust issues, and logon problems."
    $settings = $registrySettings.Netlogon
    
    foreach ($valueName in $settings.Values.Keys) {
        $value = $settings.Values[$valueName]
        set-registryValue $settings.Path $valueName $value
    }
    
    log-info "Netlogon debugging enabled."
    log-info "Netlogon logs will be written to: $($settings.LogDestinations.FileLocation)"
    log-warning "High-volume logging enabled. Monitor disk space and disable when done troubleshooting."
    log-warning "IMPORTANT: You may need to restart the Netlogon service for logging to start!"
    log-info "To restart Netlogon service: net stop netlogon && net start netlogon"
    log-info "Or reboot the system for full effect"
}

# ----------------------------------------------------------------------------------------------------------------
function disable-netlogonDebugging {
    log-info "Disabling Netlogon debugging..."
    
    # Collect logs before disabling if requested
    if ($collectLogs) {
        log-info "Collecting Netlogon logs before disabling..."
        $netlogonLogPath = [System.Environment]::ExpandEnvironmentVariables($registrySettings.Netlogon.LogDestinations.FileLocation)
        if (Test-Path $netlogonLogPath) {
            Write-Host "Netlogon log file location: $netlogonLogPath" -ForegroundColor Cyan
            $logSize = (Get-Item $netlogonLogPath).Length / 1MB
            Write-Host "Netlogon log file size: $([math]::Round($logSize, 2)) MB" -ForegroundColor Cyan
        }
        
        # Check for netlogon.bak as well
        $netlogonBakPath = "$env:SystemRoot\debug\netlogon.bak"
        if (Test-Path $netlogonBakPath) {
            $bakLogSize = (Get-Item $netlogonBakPath).Length / 1MB
            Write-Host "Netlogon backup file location: $netlogonBakPath (Size: $([math]::Round($bakLogSize, 2)) MB)" -ForegroundColor Cyan
        } else {
            Write-Host "Netlogon backup file not found: $netlogonBakPath (normal if no rotation has occurred)" -ForegroundColor Yellow
        }
    }
    
    $settings = $registrySettings.Netlogon
    
    foreach ($valueName in $settings.Values.Keys) {
        remove-registryValue $settings.Path $valueName
    }
    
    log-info "Netlogon debugging disabled. Restart Netlogon service or reboot for full effect."
    
    if ($collectLogs) {
        collect-diagnosticLogs
    }
}

# ----------------------------------------------------------------------------------------------------------------
function enable-allDiagnostics {
    log-warning "Enabling ALL diagnostic logging. This will generate significant log data!"
    log-warning "This includes Netlogon debugging which generates HIGH VOLUME logs!"
    log-warning "Waiting $warningTime seconds... Press Ctrl+C to cancel"
    Start-Sleep -Seconds $warningTime
    
    enable-lsaDebugging
    # enable-rpcDebugging  # Commented out due to registry access permission issues
    enable-schannelLogging
    enable-netlogonDebugging
}

# ----------------------------------------------------------------------------------------------------------------
function disable-allDiagnostics {
    log-info "Disabling all diagnostic logging..."
    
    disable-lsaDebugging
    # disable-rpcDebugging  # Commented out due to registry access permission issues
    disable-schannelLogging
    disable-netlogonDebugging
}

# ----------------------------------------------------------------------------------------------------------------
function show-status {
    log-info "Current diagnostic registry settings status:"
    log-info "=" * 50
    
    foreach ($category in $registrySettings.Keys) {
        $settings = $registrySettings[$category]
        log-info ""
        log-info "$($settings.Description):"
        log-info "-" * 30
        
        # Check main path values
        $anyEnabled = $false
        foreach ($valueName in $settings.Values.Keys) {
            $currentValue = get-registryValue $settings.Path $valueName
            $expectedValue = $settings.Values[$valueName]
            
            if ($currentValue -ne $null) {
                $status = if ($currentValue -eq $expectedValue) { "ENABLED" } else { "PARTIAL ($currentValue)" }
                $anyEnabled = $true
            } else {
                $status = "DISABLED"
            }
            
            log-info "  $valueName`: $status"
        }
        
        # Check additional paths if they exist
        if ($settings.AdditionalPaths) {
            foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
                $pathValues = $settings.AdditionalPaths[$additionalPath]
                foreach ($valueName in $pathValues.Keys) {
                    $currentValue = get-registryValue $additionalPath $valueName
                    $expectedValue = $pathValues[$valueName]
                    
                    if ($currentValue -ne $null) {
                        $status = if ($currentValue -eq $expectedValue) { "ENABLED" } else { "PARTIAL ($currentValue)" }
                        $anyEnabled = $true
                    } else {
                        $status = "DISABLED"
                    }
                    
                    $pathShort = $additionalPath -replace "HKLM:\\", ""
                    log-info "  $pathShort\$valueName`: $status"
                }
            }
        }
        
        $overallStatus = if ($anyEnabled) { "PARTIALLY/FULLY ENABLED" } else { "DISABLED" }
        log-info "  Overall: $overallStatus"
    }
    
    log-info ""
    log-info "=" * 50
    log-info "NOTE: Changes require a system restart to take full effect"
}

# ----------------------------------------------------------------------------------------------------------------
function backup-registrySettings {
    log-info "Creating backup of diagnostic registry settings..."
    
    try {
        $regExportContent = @()
        $regExportContent += "Windows Registry Editor Version 5.00"
        $regExportContent += ""
        
        foreach ($category in $registrySettings.Keys) {
            $settings = $registrySettings[$category]
            $regExportContent += "; $($settings.Description)"
            
            # Export main path
            $regPath = $settings.Path -replace "HKLM:", "HKEY_LOCAL_MACHINE"
            $regExportContent += "[$regPath]"
            
            foreach ($valueName in $settings.Values.Keys) {
                $currentValue = get-registryValue $settings.Path $valueName
                if ($currentValue -ne $null) {
                    $regExportContent += "`"$valueName`"=dword:$('{0:x8}' -f $currentValue)"
                }
            }
            $regExportContent += ""
            
            # Export additional paths
            if ($settings.AdditionalPaths) {
                foreach ($additionalPath in $settings.AdditionalPaths.Keys) {
                    $regPath = $additionalPath -replace "HKLM:", "HKEY_LOCAL_MACHINE"
                    $regExportContent += "[$regPath]"
                    
                    $pathValues = $settings.AdditionalPaths[$additionalPath]
                    foreach ($valueName in $pathValues.Keys) {
                        $currentValue = get-registryValue $additionalPath $valueName
                        if ($currentValue -ne $null) {
                            $regExportContent += "`"$valueName`"=dword:$('{0:x8}' -f $currentValue)"
                        }
                    }
                    $regExportContent += ""
                }
            }
        }
        
        $regExportContent | Out-File -FilePath $backupFile -Encoding UTF8
        log-info "Backup created successfully: $backupFile"
    }
    catch {
        log-error "Failed to create backup: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function restore-registrySettings {
    if (-not (Test-Path $backupFile)) {
        log-error "Backup file not found: $backupFile"
        return
    }
    
    log-warning "Restoring registry settings from backup: $backupFile"
    log-warning "This will overwrite current settings. Waiting $warningTime seconds... Press Ctrl+C to cancel"
    Start-Sleep -Seconds $warningTime
    
    try {
        Start-Process -FilePath "regedit.exe" -ArgumentList "/s", "`"$backupFile`"" -Wait -Verb RunAs
        log-info "Registry settings restored successfully from backup"
        log-info "System restart recommended for changes to take effect"
    }
    catch {
        log-error "Failed to restore registry settings: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function collect-diagnosticLogs {
    log-info "Collecting diagnostic log files..."
    log-info "Creating archive: $zipFile"
    
    $logFilesToCollect = @()
    $tempCollectionDir = Join-Path $env:TEMP "diagnostic-logs-collection"
    
    try {
        # Create temporary collection directory
        if (Test-Path $tempCollectionDir) {
            Remove-Item -Path $tempCollectionDir -Recurse -Force
        }
        New-Item -Path $tempCollectionDir -ItemType Directory -Force | Out-Null
        
        # Collect registry diagnostic log files
        foreach ($category in $registrySettings.Keys) {
            $settings = $registrySettings[$category]
            if ($settings.LogDestinations -and $settings.LogDestinations.FileLocation -ne "N/A") {
                $logPath = $settings.LogDestinations.FileLocation
                
                # Expand environment variables
                $logPath = [System.Environment]::ExpandEnvironmentVariables($logPath)
                
                # Handle wildcard paths (like rpc*.log)
                if ($logPath.Contains("*")) {
                    $directory = Split-Path $logPath -Parent
                    $pattern = Split-Path $logPath -Leaf
                    
                    if (Test-Path $directory) {
                        $matchingFiles = Get-ChildItem -Path $directory -Filter $pattern -ErrorAction SilentlyContinue
                        foreach ($file in $matchingFiles) {
                            if ($file.Length -gt 0) {
                                $logFilesToCollect += $file.FullName
                                log-info "Found log file: $($file.FullName) (Size: $([math]::Round($file.Length/1MB, 2)) MB)"
                            }
                        }
                    }
                } else {
                    # Single file path
                    if (Test-Path $logPath) {
                        $file = Get-Item $logPath
                        if ($file.Length -gt 0) {
                            $logFilesToCollect += $logPath
                            log-info "Found log file: $logPath (Size: $([math]::Round($file.Length/1MB, 2)) MB)"
                        }
                    } else {
                        log-warning "Log file not found: $logPath"
                    }
                }
            }
            
            # Collect additional files if specified (like lsp.log)
            if ($settings.LogDestinations.AdditionalFiles) {
                foreach ($additionalFile in $settings.LogDestinations.AdditionalFiles) {
                    $additionalLogPath = [System.Environment]::ExpandEnvironmentVariables($additionalFile)
                    
                    if (Test-Path $additionalLogPath) {
                        $file = Get-Item $additionalLogPath
                        if ($file.Length -gt 0) {
                            $logFilesToCollect += $additionalLogPath
                            log-info "Found additional log file: $additionalLogPath (Size: $([math]::Round($file.Length/1MB, 2)) MB)"
                        }
                    } else {
                        log-info "Additional log file not found (may not have been created): $additionalLogPath"
                    }
                }
            }
        }
        
        # Collect ETL files from current directory (unified trace file and LSA2 trace file)
        $unifiedEtlPath = ".\diagnostic-debug-trace.etl"
        if (Test-Path $unifiedEtlPath) {
            $etlFile = Get-Item $unifiedEtlPath
            if ($etlFile.Length -gt 0) {
                $logFilesToCollect += $etlFile.FullName
                log-info "Found ETL file: $($etlFile.FullName) (Size: $([math]::Round($etlFile.Length/1MB, 2)) MB)"
            }
        }
        
        $lsa2EtlPath = ".\diagnostic-lsa2-trace.etl"
        if (Test-Path $lsa2EtlPath) {
            $lsa2EtlFile = Get-Item $lsa2EtlPath
            if ($lsa2EtlFile.Length -gt 0) {
                $logFilesToCollect += $lsa2EtlFile.FullName
                log-info "Found LSA2 ETL file: $($lsa2EtlFile.FullName) (Size: $([math]::Round($lsa2EtlFile.Length/1MB, 2)) MB)"
            }
        }
        
        # Copy log files to temporary collection directory
        $collectedCount = 0
        foreach ($logFile in $logFilesToCollect) {
            try {
                $fileName = Split-Path $logFile -Leaf
                $destinationPath = Join-Path $tempCollectionDir $fileName
                
                # Handle duplicate filenames by adding a counter
                $counter = 1
                $originalFileName = $fileName
                while (Test-Path $destinationPath) {
                    $extension = [System.IO.Path]::GetExtension($originalFileName)
                    $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($originalFileName)
                    $fileName = "$nameWithoutExtension-$counter$extension"
                    $destinationPath = Join-Path $tempCollectionDir $fileName
                    $counter++
                }
                
                Copy-Item -Path $logFile -Destination $destinationPath -Force
                $collectedCount++
                log-info "Collected: $fileName"
            }
            catch {
                log-error "Failed to collect log file $logFile`: $($_.Exception.Message)"
            }
        }
        
        if ($collectedCount -eq 0) {
            log-warning "No log files found to collect"
            return
        }
        
        # Create zip archive
        if (Test-Path $zipFile) {
            Remove-Item -Path $zipFile -Force
        }
        
        # Use .NET compression to create zip file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempCollectionDir, $zipFile)
        
        $zipSize = (Get-Item $zipFile).Length / 1MB
        log-info "Successfully created diagnostic logs archive: $zipFile"
        log-info "Archive size: $([math]::Round($zipSize, 2)) MB"
        log-info "Files collected: $collectedCount"
        
        Write-Host ""
        Write-Host "DIAGNOSTIC LOGS ARCHIVE CREATED" -ForegroundColor Yellow
        Write-Host "================================" -ForegroundColor Yellow
        Write-Host "Location: $zipFile" -ForegroundColor Cyan
        Write-Host "Size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan
        Write-Host "Files: $collectedCount" -ForegroundColor Cyan
        Write-Host ""
        
    }
    catch {
        log-error "Failed to create diagnostic logs archive: $($_.Exception.Message)"
    }
    finally {
        # Clean up temporary directory
        if (Test-Path $tempCollectionDir) {
            Remove-Item -Path $tempCollectionDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function show-logInfo {
    log-info "Diagnostic Logging Destinations and ETW Information:"
    log-info "=" * 60
    
    foreach ($category in $registrySettings.Keys) {
        $settings = $registrySettings[$category]
        log-info ""
        log-info "$($settings.Description):"
        log-info "-" * 40
        
        if ($settings.LogDestinations) {
            $logDest = $settings.LogDestinations
            
            log-info "  File Location: $($logDest.FileLocation)"
            
            # Show additional files if specified
            if ($logDest.AdditionalFiles) {
                log-info "  Additional Files:"
                foreach ($additionalFile in $logDest.AdditionalFiles) {
                    log-info "    - $additionalFile"
                }
            }
            
            log-info "  Event Log: $($logDest.EventLog)"
            log-info "  ETW Providers:"
            
            foreach ($provider in $logDest.ETWProviders) {
                log-info "    - $provider"
            }
        }
    }
    
    log-info ""
    log-info "=" * 60
    log-info "ETW Trace Commands:"
    log-info ""
    
    foreach ($category in $etwTraceConfigs.Keys) {
        $config = $etwTraceConfigs[$category]
        log-info "$($config.Description):"
        log-info "  Start: logman create trace `"$($config.SessionName)`" -o `"$($config.OutputFile)`" -bs $($config.BufferSize) -nb 16 $($config.MaxBuffers) -ets"
        
        $providerArgs = ""
        foreach ($provider in ($config.Providers -split ',')) {
            $providerArgs += " -p `"$provider`" 0xffffffffffffffff 0xff"
        }
        log-info "         logman update trace `"$($config.SessionName)`"$providerArgs -ets"
        log-info "  Stop:  logman stop `"$($config.SessionName)`" -ets"
        log-info ""
    }
    
    log-info "Event Log Query Examples:"
    log-info "  Get-WinEvent -LogName System -FilterHashTable @{ID=36870,36871,36872,36873,36874,36875} # SChannel events"
    log-info "  Get-WinEvent -LogName Security -FilterHashTable @{ID=4624,4625,4768,4769,4771} # Authentication events"
    log-info "  wevtutil qe System /q:`"*[System[Provider[@Name='Schannel']]]`" /f:text"
}

# ----------------------------------------------------------------------------------------------------------------
function start-etwTrace([string]$traceType = "All") {
    log-info "Starting ETW trace session for: $traceType"
    
    # Handle LSA2 separately since it uses its own session
    if ($traceType -eq "LSA2") {
        start-lsa2EtwTrace
        return
    }
    
    $sessionName = "Diagnostic-Debug-Trace"
    $outputFile = ".\diagnostic-debug-trace.etl"
    $bufferSize = 2048
    $maxBuffers = 100
    
    # Collect all providers based on trace type
    $providersToAdd = @()
    $useKeywords = $false
    $keywordsValue = $null
    
    if ($traceType -eq "All") {
        # Add all providers from all categories except LSA2 (separate session)
        foreach ($category in $etwTraceConfigs.Keys) {
            if ($category -eq "LSA2") { continue }  # Skip LSA2 - it uses separate session
            $config = $etwTraceConfigs[$category]
            $providers = $config.Providers -split ','
            foreach ($provider in $providers) {
                $provider = $provider.Trim()
                if ($provider -notin $providersToAdd) {
                    $providersToAdd += $provider
                }
            }
        }
        # Also start LSA2 in its separate session
        start-lsa2EtwTrace
    } else {
        if ($etwTraceConfigs.ContainsKey($traceType)) {
            $config = $etwTraceConfigs[$traceType]
            $providers = $config.Providers -split ','
            foreach ($provider in $providers) {
                $provider = $provider.Trim()
                $providersToAdd += $provider
            }
            # Use specific buffer settings if available
            $bufferSize = $config.BufferSize
            $maxBuffers = $config.MaxBuffers
            
            # Check if this configuration uses Keywords
            if ($config.Keywords) {
                $useKeywords = $true
                $keywordsValue = $config.Keywords
            }
        } else {
            log-error "Invalid trace type: $traceType. Valid options: LSA, LSA2, RPC, SChannel, Netlogon, Authentication, AllProviders, All"
            return
        }
    }
    
    log-info "Unified ETW trace will include $($providersToAdd.Count) providers"
    
    # Check if session already exists and stop it
    $existingCheck = logman query "$sessionName" -ets 2>$null
    if ($LASTEXITCODE -eq 0) {
        log-warning "Trace session '$sessionName' already exists. Stopping it first..."
        logman stop "$sessionName" -ets | Out-Null
    }
    
    # Create the unified trace session
    log-info "Creating unified trace session: $sessionName"
    log-info "Output file: $outputFile"
    log-info "Buffer size: $bufferSize KB, Max buffers: $maxBuffers"
    
    $createResult = logman create trace "$sessionName" -o "$outputFile" -bs $bufferSize -nb 16 $maxBuffers -ets
    
    if ($LASTEXITCODE -eq 0) {
        log-info "Trace session created successfully"
        
        # Add all providers to the unified session
        $addedCount = 0
        
        foreach ($provider in $providersToAdd) {
            log-info "  Adding provider: $provider"
            
            # Use Keywords if specified (e.g., for LSA2)
            if ($useKeywords -and $keywordsValue) {
                $keywordsHex = "0x{0:X}" -f $keywordsValue
                log-info "    Using Keywords: $keywordsHex"
                $addResult = logman update trace "$sessionName" -p "$provider" $keywordsHex 0xff -ets
            } else {
                $addResult = logman update trace "$sessionName" -p "$provider" 0xffffffffffffffff 0xff -ets
            }
            
            if ($LASTEXITCODE -eq 0) {
                $addedCount++
            } else {
                log-warning "    Failed to add provider: $provider"
            }
        }
        
        log-info "Unified ETW trace session '$sessionName' started successfully"
        log-info "Added $addedCount of $($providersToAdd.Count) providers"
        log-info "Output file: $outputFile"
        
        Write-Host ""
        Write-Host "UNIFIED ETW TRACE STARTED" -ForegroundColor Yellow
        Write-Host "=========================" -ForegroundColor Yellow
        Write-Host "Session: $sessionName" -ForegroundColor Cyan
        Write-Host "Output: $outputFile" -ForegroundColor Cyan
        Write-Host "Providers: $addedCount" -ForegroundColor Cyan
        Write-Host "Type: $traceType" -ForegroundColor Cyan
        Write-Host ""
        
    } else {
        log-error "Failed to create unified ETW trace session '$sessionName'"
    }
    
    log-info ""
    log-info "To stop tracing, run: .\windows-logon-diagnostics-manager.ps1 -stopEtwTrace"
}

# ----------------------------------------------------------------------------------------------------------------
function start-lsa2EtwTrace() {
    log-info "Starting separate LSA2 ETW trace session"
    
    $config = $etwTraceConfigs["LSA2"]
    $sessionName = $config.SessionName
    $outputFile = $config.OutputFile
    $provider = $config.Providers.Trim()
    $keywordsValue = $config.Keywords
    
    # Check if LSA2 session already exists and stop it completely
    logman query "$sessionName" -ets 2>$null
    if ($LASTEXITCODE -eq 0) {
        log-warning "LSA2 trace session '$sessionName' already exists. Stopping it first..."
        logman stop "$sessionName" -ets | Out-Null
        # Wait a moment for the session to fully stop
        Start-Sleep -Milliseconds 500
    }
    
    # Create the LSA2 trace session with provider (Microsoft ADPerfDataCollection.ps1 approach)
    log-info "Creating LSA2 trace session with provider: $sessionName"
    log-info "Output file: $outputFile"
    log-info "Provider: $provider"
    $keywordsHex = "0x{0:X}" -f $keywordsValue
    log-info "Keywords: $keywordsHex"
    
    # Try multiple approaches for LSA2 provider registration
    $success = $false
    
    # Approach 1: Test with standard keywords first to verify provider accessibility
    log-info "Testing LSA2 provider availability with standard keywords..."
    $testSessionName = "LSATest-$(Get-Date -Format 'HHmmss')"
    log-info "Test command: logman start `"$testSessionName`" -p `"$provider`" 0xffffffffffffffff 0xff -o `"test-lsa2.etl`" -ets"
    
    $testResult = logman start "$testSessionName" -p "$provider" 0xffffffffffffffff 0xff -o "test-lsa2.etl" -ets 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        log-info "LSA2 provider test successful with standard keywords!"
        logman stop "$testSessionName" -ets | Out-Null
        Remove-Item "test-lsa2.etl" -Force -ErrorAction SilentlyContinue
        
        # Approach 2: Try Microsoft's exact format - Keywords ONLY (no level parameter)
        log-info "Attempting Microsoft's exact approach: Keywords only, no level parameter"
        log-info "Command: logman start `"$sessionName`" -p `"$provider`" $keywordsHex -o `"$outputFile`" -ets"
        $startResult = logman start "$sessionName" -p "$provider" $keywordsHex -o "$outputFile" -ets 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            log-info "LSA2 ETW trace session '$sessionName' started successfully with Microsoft's Keywords-only approach"
        } else {
            log-warning "Microsoft's Keywords-only approach failed. Exit code: $LASTEXITCODE"
            if ($startResult) {
                log-warning "Keywords-only output: $($startResult -join '; ')"
            }
            
            # Approach 3: Try with Keywords + Level (our previous approach)
            log-info "Trying Keywords + Level approach: $keywordsHex 0xff"
            log-info "Command: logman start `"$sessionName`" -p `"$provider`" $keywordsHex 0xff -o `"$outputFile`" -ets"
            $startResult2 = logman start "$sessionName" -p "$provider" $keywordsHex 0xff -o "$outputFile" -ets 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $success = $true
                log-info "LSA2 ETW trace session '$sessionName' started successfully with Keywords + Level"
            } else {
                log-warning "Keywords + Level approach failed. Exit code: $LASTEXITCODE"
                if ($startResult2) {
                    log-warning "Keywords + Level output: $($startResult2 -join '; ')"
                }
                
                # Approach 4: Try with standard keywords as working alternative
                log-info "Falling back to standard keywords..."
                log-info "Command: logman start `"$sessionName`" -p `"$provider`" 0xffffffffffffffff 0xff -o `"$outputFile`" -ets"
                $startResult3 = logman start "$sessionName" -p "$provider" 0xffffffffffffffff 0xff -o "$outputFile" -ets 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $success = $true
                    log-info "LSA2 ETW trace session '$sessionName' started successfully with standard keywords"
                    Write-Host "Note: Using standard keywords (0xffffffffffffffff 0xff) instead of Microsoft's specific value ($keywordsHex)" -ForegroundColor Yellow
                } else {
                    log-warning "Standard keywords also failed. Exit code: $LASTEXITCODE"
                    if ($startResult3) {
                        log-warning "Standard keywords output: $($startResult3 -join '; ')"
                    }
                }
            }
        }
        
    } else {
        log-error "LSA2 provider test failed - provider not available or accessible"
        log-error "Test exit code: $LASTEXITCODE"
        if ($testResult) {
            log-error "Test output: $($testResult -join '; ')"
        }
        
        # Clean up test session if it was partially created
        logman stop "$testSessionName" -ets 2>$null | Out-Null
        Remove-Item "test-lsa2.etl" -Force -ErrorAction SilentlyContinue
    }
    
    if ($success) {
        log-info "Output file: $outputFile"
        
        Write-Host ""
        Write-Host "LSA2 ETW TRACE STARTED" -ForegroundColor Yellow
        Write-Host "======================" -ForegroundColor Yellow
        Write-Host "Session: $sessionName" -ForegroundColor Cyan
        Write-Host "Output: $outputFile" -ForegroundColor Cyan
        Write-Host "Provider: $provider" -ForegroundColor Cyan
        Write-Host "Keywords: $keywordsHex" -ForegroundColor Cyan
        Write-Host ""
    } else {
        log-error "All LSA2 ETW trace approaches failed"
        log-error "The LSA2 provider $provider cannot be started with Keywords $keywordsHex"
        log-error "This may indicate the provider requires different keywords, level parameters, or has permission restrictions"
    }
}

# ----------------------------------------------------------------------------------------------------------------
function stop-etwTrace([string]$traceType = "All") {
    log-info "Stopping ETW trace session(s)"
    
    # Handle LSA2 separately since it uses its own session
    if ($traceType -eq "LSA2") {
        stop-lsa2EtwTrace
        return
    }
    
    $sessionName = "Diagnostic-Debug-Trace"
    $outputFile = ".\diagnostic-debug-trace.etl"
    
    # For "All", stop both main session and LSA2 session
    if ($traceType -eq "All") {
        stop-lsa2EtwTrace
    }
    
    # Check if main session exists
    logman query "$sessionName" -ets 2>$null
    if ($LASTEXITCODE -eq 0) {
        log-info "Stopping trace session: $sessionName"
        logman stop "$sessionName" -ets | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            log-info "Main ETW trace session '$sessionName' stopped successfully"
            if (Test-Path $outputFile) {
                $fileSize = (Get-Item $outputFile).Length / 1MB
                log-info "Output file: $outputFile (Size: $([math]::Round($fileSize, 2)) MB)"
                
                Write-Host ""
                Write-Host "MAIN ETW TRACE STOPPED" -ForegroundColor Yellow
                Write-Host "=======================" -ForegroundColor Yellow
                Write-Host "Session: $sessionName" -ForegroundColor Cyan
                Write-Host "Output: $outputFile" -ForegroundColor Cyan
                Write-Host "Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "To convert ETL to text: netsh trace convert input=$outputFile" -ForegroundColor Yellow
                Write-Host "To view with WPA: wpa.exe $outputFile" -ForegroundColor Yellow
                Write-Host ""
            }
        } else {
            log-error "Failed to stop main ETW trace session '$sessionName'"
        }
    } else {
        log-warning "Main trace session '$sessionName' is not running"
    }
    
    # Automatically collect logs if collectLogs switch is used
    if ($collectLogs) {
        log-info "Automatically collecting ETL file(s)..."
        collect-diagnosticLogs
    }
}

# ----------------------------------------------------------------------------------------------------------------
function stop-lsa2EtwTrace() {
    log-info "Stopping LSA2 ETW trace session"
    
    $config = $etwTraceConfigs["LSA2"]
    $sessionName = $config.SessionName
    $outputFile = $config.OutputFile
    
    # Check if LSA2 session exists
    logman query "$sessionName" -ets 2>$null
    if ($LASTEXITCODE -eq 0) {
        log-info "Stopping LSA2 trace session: $sessionName"
        logman stop "$sessionName" -ets | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            log-info "LSA2 ETW trace session '$sessionName' stopped successfully"
            if (Test-Path $outputFile) {
                $fileSize = (Get-Item $outputFile).Length / 1MB
                log-info "LSA2 output file: $outputFile (Size: $([math]::Round($fileSize, 2)) MB)"
                
                Write-Host ""
                Write-Host "LSA2 ETW TRACE STOPPED" -ForegroundColor Yellow
                Write-Host "=======================" -ForegroundColor Yellow
                Write-Host "Session: $sessionName" -ForegroundColor Cyan
                Write-Host "Output: $outputFile" -ForegroundColor Cyan
                Write-Host "Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "To convert ETL to text: netsh trace convert input=$outputFile" -ForegroundColor Yellow
                Write-Host "To view with WPA: wpa.exe $outputFile" -ForegroundColor Yellow
                Write-Host ""
            }
        } else {
            log-error "Failed to stop LSA2 ETW trace session '$sessionName'"
        }
    } else {
        log-warning "LSA2 trace session '$sessionName' is not running"
    }
}

# ----------------------------------------------------------------------------------------------------------------
# Entry point
if ($args.Count -eq 0 -and -not ($enableAll -or $disableAll -or $enableLsa -or $disableLsa -or $enableRpc -or $disableRpc -or $enableSchannel -or $disableSchannel -or $enableNetlogon -or $disableNetlogon -or $status -or $backup -or $restore -or $showLogInfo -or $startEtwTrace -or $stopEtwTrace)) {
    Write-Host ""
    Write-Host "Windows Diagnostic Registry Manager" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script manages diagnostic registry settings for LSA, RPC, SChannel, and Netlogon."
    Write-Host "It also provides unified ETW tracing capabilities and log destination information."
    Write-Host "Use -status to see current settings or -help for usage information."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -status" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -showLogInfo" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -enableAll" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -enableNetlogon" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -enableLsa -enableRpc -enableNetlogon" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -disableAll -collectLogs" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType AllProviders" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType Authentication" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType LSA2" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -startEtwTrace -etwTraceType Netlogon" -ForegroundColor Gray
    Write-Host "  .\windows-logon-diagnostics-manager.ps1 -stopEtwTrace -collectLogs" -ForegroundColor Gray
    Write-Host ""
    Write-Host "ETW Trace Types Available:" -ForegroundColor Yellow
    Write-Host "  LSA, LSA2 (with Keywords), RPC, SChannel, Netlogon, Authentication, AllProviders, All" -ForegroundColor Gray
    Write-Host ""
    Write-Host "NOTE: Netlogon debugging is critical for authentication troubleshooting!" -ForegroundColor Cyan
    Write-Host ""
    return
}

main
