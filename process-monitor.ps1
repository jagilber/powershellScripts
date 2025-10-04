
<#
.SYNOPSIS
    Monitors for new instances of a specified process and optionally attaches a debugger or diagnostic tool.

.DESCRIPTION
    Continuously monitors the system for new instances of a specified process name. When a new process instance
    is detected, the script can automatically attach a diagnostic tool (e.g., ProcDump, WinDbg) to capture dumps
    or debug information. The script tracks process creation and termination in real-time with color-coded output.
    Supports filtering by command-line arguments and list-only mode for passive monitoring.

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
    File Name  : process-monitor.ps1
    Author     : jagilber
    Requires   : PowerShell 5.1 or higher
    Disclaimer : Provided AS-IS without warranty.
    Version    : 2.0
    Changelog  : 1.0 - Initial release (06/26/2014)
                 2.0 - Updated to template standards: added proper help, error handling, ShouldProcess support,
                       alphabetized functions, added write-console helper, improved parameter validation

.PARAMETER processName
    Name of the process to monitor (without .exe extension). Use "*" to monitor all processes (list-only mode).
    Default: "notepad"

.PARAMETER processArgs
    Optional command-line arguments filter. Only trigger actions on processes whose command line contains this string.

.PARAMETER sleepMs
    Sleep interval in milliseconds between process enumeration checks. Lower values = faster detection, higher CPU usage.
    Default: 10ms

.PARAMETER debugProcess
    Path to the diagnostic tool to launch when a new process instance is detected (e.g., "procdump.exe", "windbg.exe").
    If the file doesn't exist locally and is a Sysinternals utility, the script will offer to download it.
    Default: "procdump.exe"

.PARAMETER debugArguments
    Arguments to pass to the debugProcess. Use $id.Key placeholder for process ID (handled internally).
    For ProcDump: "-accepteula -ma -e -t -n 10" (creates dump on exception, up to 10 dumps)
    Default: "-accepteula -ma -e -t -n 10 "

.PARAMETER listOnly
    If specified, only monitors and reports process creation/termination without launching any diagnostic tools.
    Automatically enabled when processName is "*".

.PARAMETER showMonitor
    If specified, displays progress dots to indicate the script is actively monitoring.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually attaching debuggers or making changes.

.PARAMETER Confirm
    Prompts for confirmation before attaching debuggers to new process instances.

.EXAMPLE
    .\process-monitor.ps1 -processName "notepad" -listOnly
    
    Monitors for new notepad.exe instances and logs creation/termination without attaching any tools.

.EXAMPLE
    .\process-monitor.ps1 -processName "w3wp" -debugProcess "procdump.exe" -debugArguments "-accepteula -ma -e -t -n 3" -WhatIf
    
    Shows what would happen when monitoring w3wp.exe processes with ProcDump configured to capture 3 dumps on exceptions.

.EXAMPLE
    .\process-monitor.ps1 -processName "myapp" -processArgs "production" -sleepMs 100 -Confirm
    
    Monitors for myapp.exe processes with "production" in command line, prompts before attaching debugger.

.EXAMPLE
    .\process-monitor.ps1 -processName "*" -showMonitor
    
    Monitors all system processes in list-only mode with progress indicator.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/process-monitor.ps1" -outFile "$pwd\process-monitor.ps1";
    .\process-monitor.ps1 -processName "notepad" -listOnly
#>

#requires -version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Position = 0)]
    [string]$processName = 'notepad',
    
    [Parameter()]
    [string]$processArgs = '',
    
    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$sleepMs = 10,
    
    [Parameter()]
    [string]$debugProcess = 'procdump.exe',
    
    [Parameter()]
    [string]$debugArguments = '-accepteula -ma -e -t -n 10 ',
    
    [Parameter()]
    [switch]$listOnly,
    
    [Parameter()]
    [switch]$showMonitor
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'Continue'

# Script-level variables
$script:currentProcessList = @{ }
$script:currentDiffCount = 0
$script:monitorCount = 0

function main() {
    try {
        # Set list-only mode if wildcard or switch specified
        $listOnlyMode = ($listOnly.IsPresent -or $processName -ieq '*')
        
        write-console "Starting process monitor for '$processName'" -ForegroundColor Cyan
        
        if ($listOnlyMode) {
            write-console "List-only mode enabled - no debuggers will be attached" -ForegroundColor Yellow
        }

        # Initialize process list
        $script:currentProcessList = Get-ProcessList -processName $processName

        # Check if debug process exists or can be downloaded
        if (!$listOnlyMode -and $debugProcess) {
            if (![IO.File]::Exists($debugProcess)) {
                $isSysinternalsUtility = $debugProcess -match '^(procdump|procmon|procexp|psexec|pskill|pslist|psloggedon|pspasswd|psservice|pssuspend|handle|listdlls|livekd|logonsessions|notmyfault|portmon|procexp|strings|sync|tcpview|vmmap|winobj|zoomit)\.exe$'
                
                if ($isSysinternalsUtility) {
                    $downloadedPath = Get-SysInternalsUtility -utilityName ([IO.Path]::GetFileName($debugProcess))
                    if ([string]::IsNullOrEmpty($downloadedPath)) {
                        throw "Unable to download or locate $debugProcess"
                    }
                    $debugProcess = $downloadedPath
                }
                else {
                    throw "Debug process not found: $debugProcess"
                }
            }
            
            write-console "Debug process configured: $debugProcess" -ForegroundColor Cyan
            write-console "Debug arguments: $debugArguments" -ForegroundColor Cyan
        }

        write-console "Monitoring started. Press Ctrl+C to stop." -ForegroundColor Green
        
        # Main monitoring loop
        while ($true) {
            $newList = Get-ProcessList -processName $processName

            # Check for new processes
            foreach ($id in $newList.GetEnumerator()) {
                if (!$script:currentProcessList.ContainsKey($id.Key)) {
                    $script:currentDiffCount++
                    $newLine = if ([console]::GetCursorPosition().Left -ne 0) { "`r" } else { $null }
                    write-console "$($newLine)$((Get-Date).ToString('HH:mm:ss.fff')):>>>add:$($script:currentDiffCount) $($id.Value.Name):$($id.Key)" -ForegroundColor Green
                    $script:currentProcessList.Add($id.Key, $id.Value)

                    # Filter by process arguments if specified
                    if (!$listOnlyMode -and ![string]::IsNullOrWhiteSpace($processArgs)) {
                        $cmdline = Get-CimInstance Win32_Process -Filter "ProcessId = $($id.Key)" -ErrorAction SilentlyContinue
                        if ($cmdline -and !$cmdline.CommandLine.Contains($processArgs)) {
                            Write-Verbose "Process $($id.Key) does not match argument filter '$processArgs', skipping"
                            continue
                        }
                    }

                    # Attach debugger if not in list-only mode
                    if (!$listOnlyMode -and $debugProcess) {
                        Invoke-DebuggerAttach -processId $id.Key -debugProcess $debugProcess -debugArguments $debugArguments
                    }
                }
            }

            # Check for removed processes
            $tempList = $script:currentProcessList.Clone()
            foreach ($id in $tempList.GetEnumerator()) {
                if (!$newList.ContainsKey($id.Key)) {
                    $script:currentDiffCount--
                    $newLine = if ([console]::GetCursorPosition().Left -ne 0) { "`r" } else { $null }
                    write-console "$($newLine)$((Get-Date).ToString('HH:mm:ss.fff')):<<<remove:$($script:currentDiffCount) $($id.Value.Name):$($id.Key)" -ForegroundColor Red
                    $script:currentProcessList.Remove($id.Key)
                }
            }

            Start-Sleep -Milliseconds $sleepMs
            if ($showMonitor) { 
                Show-MonitorProgress 
            }
        }
    }
    catch {
        write-console "exception::$($PSItem.Exception.Message)`r`n$($PSItem.ScriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((Get-Variable -Scope local).Value | ConvertTo-Json -WarningAction SilentlyContinue -Depth 2)"
        return 1
    }
    finally {
        write-console "`nProcess monitoring stopped." -ForegroundColor Cyan
    }
}

# ============================================================
# FUNCTIONS (alphabetically ordered except main which is always first)
# ============================================================

function Get-ProcessList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$processName
    )
    
    $tempList = @{ }

    try {
        if ($processName -eq '*') {
            foreach ($process in [Diagnostics.Process]::GetProcesses()) {
                Write-Verbose "Adding process: $($process.Name):$($process.Id)"
                if (!$tempList.ContainsKey($process.Id)) {
                    $tempList.Add($process.Id, $process)
                }
            }
        }
        else {
            foreach ($process in [Diagnostics.Process]::GetProcessesByName($processName)) {
                Write-Verbose "Adding process: $($process.Name):$($process.Id)"
                if (!$tempList.ContainsKey($process.Id)) {
                    $tempList.Add($process.Id, $process)
                }
            }
        }
    }
    catch {
        throw "Failed to enumerate processes: $($_.Exception.Message)"
    }

    return $tempList
}

function Get-SysInternalsUtility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$utilityName
    )

    try {
        $destFile = Join-Path (Get-Location) $utilityName
        
        # TLS NOTE: Explicit TLS1.2 enable kept for legacy Windows PowerShell hosts that default to older protocols.
        # Modern PowerShell Core already negotiates TLS1.2+ automatically.
        if ($PSVersionTable.PSVersion.Major -le 5) {
            [System.Net.ServicePointManager]::Expect100Continue = $true
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        }
        
        if (![IO.File]::Exists($destFile)) {
            $sysUrl = "https://live.sysinternals.com/$utilityName"

            write-console "Sysinternals utility '$utilityName' is needed for this operation." -ForegroundColor Yellow
            $response = Read-Host "Download from $sysUrl ? [y/n]"
            
            if ($response.ToLower() -eq 'y') {
                write-console "Downloading $utilityName..." -ForegroundColor Cyan
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($sysUrl, $destFile)
                write-console "Downloaded $utilityName to $destFile" -ForegroundColor Green
            }
            else {
                throw "User declined download of $utilityName"
            }
        }

        return $destFile
    }
    catch {
        throw "Failed to download $utilityName : $($_.Exception.Message)"
    }
}

function Invoke-DebuggerAttach {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$processId,
        
        [Parameter(Mandatory = $true)]
        [string]$debugProcess,
        
        [Parameter(Mandatory = $true)]
        [string]$debugArguments
    )

    try {
        $commandLine = "$debugProcess $debugArguments $processId"
        
        if ($PSCmdlet.ShouldProcess("Process ID $processId", "Attach debugger: $commandLine")) {
            write-console "Attaching debugger to process $processId : $commandLine" -ForegroundColor Cyan
            
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processStartInfo.FileName = $debugProcess
            $processStartInfo.Arguments = "$debugArguments $processId"
            $processStartInfo.WorkingDirectory = (Get-Location).Path
            $processStartInfo.UseShellExecute = $false
            
            $processObj = [System.Diagnostics.Process]::Start($processStartInfo)
            write-console "Debugger attached (PID: $($processObj.Id))" -ForegroundColor Green
        }
        else {
            write-console "Debugger attach skipped (WhatIf or user declined)" -ForegroundColor Yellow
        }
    }
    catch {
        throw "Failed to attach debugger to process $processId : $($_.Exception.Message)"
    }
}

function Show-MonitorProgress {
    [CmdletBinding()]
    param()
    
    if ($script:monitorCount -ge 100) {
        Write-Host ''
        $script:monitorCount = 0
    }
    else {
        Write-Host '.' -NoNewline
        $script:monitorCount++
    }
}

function write-console {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Real-time monitoring requires immediate console feedback')]
    param(
        [Parameter(Position = 0)]
        [object]$message,
        
        [Parameter()]
        [ConsoleColor]$foregroundColor = 'White',
        
        [Parameter()]
        [switch]$toVerbose,
        
        [Parameter()]
        [switch]$err,
        
        [Parameter()]
        [switch]$warn
    )
    
    if (!$message) { return }
    
    if ($message.GetType().Name -ine 'string') {
        $message = $message | ConvertTo-Json -Depth 10
    }

    if ($toVerbose) {
        Write-Verbose $message
    }
    else {
        # Write-Host is intentional for real-time monitoring feedback with color-coded output
        Write-Host $message -ForegroundColor $foregroundColor
    }

    if ($warn) {
        Write-Warning $message
    }
    elseif ($err) {
        Write-Error $message
        throw
    }
}

# Execute main function
main
