<#
.SYNOPSIS
    Enumerates all running processes and summarizes private working set memory usage.

.DESCRIPTION
    This script collects detailed information about all running processes and provides
    a summary of private working set memory usage. It displays individual process
    memory usage and provides aggregate statistics including total, average, and
    top memory consumers. Supports export to CSV and filtering options.

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
    File Name  : process-memory-summary.ps1
    Author     : PowerShell Scripts Repository
    Requires   : PowerShell 5.1 or higher
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.1
    Changelog  : 1.0 - Initial release
                 1.1 - Updated to follow repository template standards

.PARAMETER Top
    Number of top memory consuming processes to display in detail. Default is 10.

.PARAMETER SortBy
    Property to sort processes by. Valid values: PrivateMemorySize, WorkingSet, 
    VirtualMemorySize, ProcessName. Default is PrivateMemorySize.

.PARAMETER ExportPath
    Optional path to export results to CSV file.

.PARAMETER ShowDetails
    Switch to display detailed information for all processes.

.PARAMETER WhatIf
    Shows what would be executed without actually running the operations.

.PARAMETER Diagnostics
    Display diagnostic information about the script execution environment.

.EXAMPLE
    .\process-memory-summary.ps1
    
    Displays top 10 processes by private memory usage with summary statistics.

.EXAMPLE
    .\process-memory-summary.ps1 -Top 5 -SortBy WorkingSet
    
    Displays top 5 processes sorted by working set memory.

.EXAMPLE
    .\process-memory-summary.ps1 -ShowDetails -ExportPath "C:\temp\process-report.csv" -WhatIf
    
    Shows what would happen when displaying all process details and exporting to CSV file.

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/process-memory-summary.ps1" -outFile "$pwd\process-memory-summary.ps1";
    .\process-memory-summary.ps1
#>

#requires -version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [int]$Top = 10,
    
    [Parameter()]
    [ValidateSet('PrivateMemorySize', 'WorkingSet', 'VirtualMemorySize', 'ProcessName')]
    [string]$SortBy = 'PrivateMemorySize',
    
    [Parameter()]
    [string]$ExportPath,
    
    [Parameter()]
    [switch]$ShowDetails,
    
    [Parameter()]
    [switch]$Diagnostics
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'Continue'
$scriptName = "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'Continue'
$scriptName = "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"

# always top function
function main() {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($Diagnostics) {
        write-console "PowerShell Version: $($PSVersionTable.PSVersion)"
        write-console "OS: $([System.Environment]::OSVersion.VersionString)"
        write-console "Script: $scriptName"
        write-console "Parameters: Top=$Top, SortBy=$SortBy, ExportPath=$ExportPath, ShowDetails=$ShowDetails"
        write-console ""
    }

    try {
        write-console "Process Memory Summary Tool" -ForegroundColor White
        write-console "============================" -ForegroundColor White
        write-console ""
        
        # Collect process information
        write-console "collect-processMemoryInfo" -ForegroundColor Cyan
        $allProcesses = get-processMemoryInfo
        
        if ($allProcesses.Count -eq 0) {
            write-console "No process information collected. Exiting." -warn
            return 1
        }
        
        # Display summary
        show-memorySummary -Processes $allProcesses
        
        # Display top processes
        show-topProcesses -Processes $allProcesses -TopCount $Top -SortProperty $SortBy
        
        # Display detailed information if requested
        if ($ShowDetails) {
            show-detailedProcesses -Processes $allProcesses
        }
        
        # Export to CSV if path provided
        if ($ExportPath) {
            write-console "export-processData -Path '$ExportPath'" -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($ExportPath, "Export process data to CSV")) {
                export-processData -Processes $allProcesses -Path $ExportPath
            }
        }
        
        write-console "`nProcess enumeration completed successfully." -ForegroundColor Green
    }
    catch {
        write-console "exception::$($_.Exception.Message)`r`n$($_.ScriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((Get-Variable -Scope local).Value | ConvertTo-Json -WarningAction SilentlyContinue -Depth 2)"
        return 1
    }
    finally {
        # Cleanup if needed
    }
    
    return 0
}

# alphabetical list of functions
# ** ENSURE FUNCTIONS ARE REORGANIZED ALPHABETICALLY EXCEPT FOR main() **
# ** ENSURE ALL FUNCTIONS THROW ERRORS, DO NOT CATCH THEM **
# ** ONLY main() CATCHES ERRORS AND HANDLES LOGGING / EXIT CODES **

function export-processData {
    param(
        [array]$Processes,
        [string]$Path
    )
    
    write-console "enter export-processData"
    
    $exportData = $Processes | Select-Object ProcessName, Id, 
        @{Name="PrivateMemoryMB"; Expression={[math]::Round($_.PrivateMemorySize / 1MB, 2)}},
        @{Name="WorkingSetMB"; Expression={[math]::Round($_.WorkingSet / 1MB, 2)}},
        @{Name="VirtualMemoryMB"; Expression={[math]::Round($_.VirtualMemorySize / 1MB, 2)}},
        @{Name="PagedMemoryMB"; Expression={[math]::Round($_.PagedMemorySize / 1MB, 2)}},
        Threads, Handles, 
        @{Name="CPUSeconds"; Expression={[math]::Round($_.CPU, 2)}},
        StartTime, Company, Description, Path
    
    $exportData | Export-Csv -Path $Path -NoTypeInformation
    write-console "Process data exported to: $Path" -ForegroundColor Green
    
    write-console "exit export-processData"
}

function format-bytes {
    param([long]$Bytes)
    
    if ($Bytes -eq 0) { return "0 B" }
    
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $index = [math]::Floor([math]::Log($Bytes, 1024))
    $size = [math]::Round($Bytes / [math]::Pow(1024, $index), 2)
    
    return "$size $($sizes[$index])"
}

function get-processMemoryInfo {
    write-console "enter get-processMemoryInfo"
    
    # Get all processes with memory information
    $processes = Get-Process | Where-Object { $null -ne $_.ProcessName } | ForEach-Object {
        $proc = $_
        $startTime = $null
        $cpuTime = 0
        $company = ""
        $description = ""
        $path = ""
        
        # Safely get optional properties
        try { $startTime = $proc.StartTime } catch { }
        try { $cpuTime = $proc.TotalProcessorTime.TotalSeconds } catch { }
        try { $company = $proc.Company } catch { }
        try { $description = $proc.Description } catch { }
        try { $path = $proc.Path } catch { }
        
        [PSCustomObject]@{
            ProcessName = $proc.ProcessName
            Id = $proc.Id
            PrivateMemorySize = $proc.PrivateMemorySize64
            WorkingSet = $proc.WorkingSet64
            VirtualMemorySize = $proc.VirtualMemorySize64
            PagedMemorySize = $proc.PagedMemorySize64
            NonpagedSystemMemorySize = $proc.NonpagedSystemMemorySize64
            PagedSystemMemorySize = $proc.PagedSystemMemorySize64
            StartTime = $startTime
            CPU = $cpuTime
            Threads = $proc.Threads.Count
            Handles = $proc.HandleCount
            Company = $company
            Description = $description
            Path = $path
        }
    } | Where-Object { $null -ne $_ }
    
    write-console "exit get-processMemoryInfo: collected $($processes.Count) processes"
    return $processes
}

function show-detailedProcesses {
    param([array]$Processes)
    
    write-console "enter show-detailedProcesses"
    
    write-console "`n=== DETAILED PROCESS INFORMATION ===" -ForegroundColor Magenta
    
    $Processes | Sort-Object PrivateMemorySize -Descending | Select-Object @{
        Name = "Process"; Expression = { $_.ProcessName }
    }, @{
        Name = "PID"; Expression = { $_.Id }
    }, @{
        Name = "Private (MB)"; Expression = { [math]::Round($_.PrivateMemorySize / 1MB, 2) }
    }, @{
        Name = "Working (MB)"; Expression = { [math]::Round($_.WorkingSet / 1MB, 2) }
    }, @{
        Name = "Virtual (MB)"; Expression = { [math]::Round($_.VirtualMemorySize / 1MB, 2) }
    }, @{
        Name = "Paged (MB)"; Expression = { [math]::Round($_.PagedMemorySize / 1MB, 2) }
    }, @{
        Name = "Threads"; Expression = { $_.Threads }
    }, @{
        Name = "Handles"; Expression = { $_.Handles }
    }, @{
        Name = "CPU"; Expression = { [math]::Round($_.CPU, 1) }
    }, @{
        Name = "Start Time"; Expression = { if ($_.StartTime) { $_.StartTime.ToString("MM/dd HH:mm") } else { "N/A" } }
    }, @{
        Name = "Company"; Expression = { if ($_.Company) { $_.Company } else { "Unknown" } }
    } | Format-Table -AutoSize
    
    write-console "exit show-detailedProcesses"
}

function show-memorySummary {
    param([array]$Processes)
    
    write-console "enter show-memorySummary"
    
    write-console "`n=== MEMORY USAGE SUMMARY ===" -ForegroundColor Cyan
    
    $totalPrivate = ($Processes | Measure-Object -Property PrivateMemorySize -Sum).Sum
    $totalWorking = ($Processes | Measure-Object -Property WorkingSet -Sum).Sum
    $totalVirtual = ($Processes | Measure-Object -Property VirtualMemorySize -Sum).Sum
    $processCount = $Processes.Count
    
    write-console "Total Processes: $processCount"
    write-console "Total Private Memory: $(format-bytes $totalPrivate)"
    write-console "Total Working Set: $(format-bytes $totalWorking)"
    write-console "Total Virtual Memory: $(format-bytes $totalVirtual)"
    write-console "Average Private Memory: $(format-bytes ($totalPrivate / $processCount))"
    write-console "Average Working Set: $(format-bytes ($totalWorking / $processCount))"
    
    write-console "exit show-memorySummary"
}

function show-topProcesses {
    param(
        [array]$Processes,
        [int]$TopCount,
        [string]$SortProperty
    )
    
    write-console "enter show-topProcesses"
    
    write-console "`n=== TOP $TopCount PROCESSES (by $SortProperty) ===" -ForegroundColor Yellow
    
    $topProcesses = $Processes | Sort-Object $SortProperty -Descending | Select-Object -First $TopCount
    
    $table = $topProcesses | Select-Object @{
        Name = "Process Name"; Expression = { $_.ProcessName }
    }, @{
        Name = "PID"; Expression = { $_.Id }
    }, @{
        Name = "Private Memory"; Expression = { format-bytes $_.PrivateMemorySize }
    }, @{
        Name = "Working Set"; Expression = { format-bytes $_.WorkingSet }
    }, @{
        Name = "Virtual Memory"; Expression = { format-bytes $_.VirtualMemorySize }
    }, @{
        Name = "Threads"; Expression = { $_.Threads }
    }, @{
        Name = "CPU (sec)"; Expression = { [math]::Round($_.CPU, 2) }
    }
    
    $table | Format-Table -AutoSize
    
    write-console "exit show-topProcesses"
}

function write-console($message, [consoleColor]$foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.GetType().Name -ine 'string') {
        $message = $message | ConvertTo-Json -Depth 10
    }

    if ($verbose) {
        Write-Verbose($message)
    }
    else {
        Write-Host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        Write-Warning($message)
    }
    elseif ($err) {
        Write-Error($message)
        throw
    }
}

main