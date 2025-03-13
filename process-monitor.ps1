
# powershell script to monitor for a given process name
# once new instance of process name is found, run a process
# in this example, ntsd.exe is being attached to the new process
# v 1.0 06/26/2014
# microsoft support
# [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
#  invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/process-monitor.ps1" -outFile "$(get-location)\process-monitor.ps1"

[cmdletbinding()]
param(
    [string]$processName = "notepad", #"logonui"
    [string]$processArgs = "",
    [int]$sleepMs = 10,
    [string]$debugProcess = "procdump.exe", #c:\temp\mon-logonui.bat"
    [string]$debugArguments = "-accepteula -ma -e -t -n 10 ",
    [switch]$listOnly,
    [switch]$showMonitor
)

$currentProcessList = @{ }
$tempList = @{ }
$newList = @{ }
$listOnly = ($listOnly.IsPresent -or $processName -ieq '*')


function main() {
    #init
    $currentProcessList = enum-processes -processName $processName

    if ($syinternalsProcess -and ![IO.File]::Exists($debugProcess)) {
        if ([string]::IsNullOrEmpty((get-sysInternalsUtility -utilityName ([IO.Path]::GetFileName($debugProcess))))) {
            "unable to download $($debugProcess). exiting"
            return
        }
    }

    $count = 0

    while ($true) {
        $newList = enum-processes -processName $processName

        foreach ($id in $newList.GetEnumerator()) {
            if (!$currentProcessList.ContainsKey($id.Key)) {
                $newLine = $null
                if ([console]::GetCursorPosition().Left -ne 0) { $newLine = "`r" } #clear line
                write-host "$($newLine)Adding process to list: $($id.Value.Name):$($id.key)"
                $currentProcessList.Add($id.Key, $process);

                if (!$listOnly -and $processArgs -ne $null) {
                    $cmdline = Get-WmiObject Win32_Process -Filter "ProcessId like `'$($id.key)`'"
                    if (!$cmdline.CommandLine.Contains($processArgs)) {
                        continue
                    }
                }

                if (!$listOnly -and $debugProcess) {
                    #windbg
                    #Start-Process -process $debugProcess -arguments "$($debugArguments) -p $($id.Key)"
                    #write-host "Start-Process -process $debugProcess -arguments `"$($debugArguments) -p $($id.Key)`"""

                    #procdump
                    Start-Process -process $debugProcess -arguments "$($debugArguments) $($id.Key)"
                    write-host "Start-Process -process $debugProcess -arguments `"$($debugArguments) $($id.Key)`""

                    #tttracer
                    #Start-Process -process $debugProcess -arguments "$($debugArguments) $($id.Key)"
                    #write-host "Start-Process -process $debugProcess -arguments `"$($debugArguments) $($id.Key)`""
                }
            }
        }

        $tempList = $currentProcessList.Clone();

        foreach ($id in $tempList.GetEnumerator()) {
            if (!$newList.ContainsKey($id.Key)) {
                $newLine = $null
                if ([console]::GetCursorPosition().Left -ne 0) { $newLine = "`r" } #clear line
                write-host "$($newLine)Removing process from list: $($id.Value.Name):$($id.key)"
                $currentProcessList.Remove($id.Key);
            }
        }

        Start-Sleep -Milliseconds $sleepMs
        if($showMonitor) { show-monitor }
    }
}

function enum-processes($processName) {
    $tempList = @{ }

    if ($processName -eq "*") {
        foreach ($process in [diagnostics.Process]::GetProcesses()) {
            write-debug "adding $($process):$($process.id)"
            $tempList.Add($process.Id, $process)
        }
    }
    else {
        foreach ($process in [diagnostics.Process]::GetProcessesByName($processName)) {
            write-debug "adding $($process.Name):$($process.id)"
            $tempList.Add($process.Id, $process)
        }
    }

    return $tempList
}

function show-monitor() {
    if ($count -ge 100) {
        write-host ""
        $count = 0
    }
    else {
        write-host "." -NoNewline
        $count++
    }
}


function start-process($process, $arguments) {
    write-host "Starting $($process)"
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo;
    $processStartInfo.FileName = $process;
    $processStartInfo.WorkingDirectory = (Get-Location).Path;
    if ($arguments) { $processStartInfo.Arguments = $arguments }
    #$processStartInfo.UseShellExecute = $false;
    #$processStartInfo.RedirectStandardOutput = $true;

    $processObj = [System.Diagnostics.Process]::Start($processStartInfo);
    #$processObj.WaitForExit();
    #$processObj.StandardOutput.ReadToEnd();

}


function get-sysInternalsUtility ([string] $utilityName) {
    try {
        $destFile = "$(get-location)\$utilityName"
        [System.Net.ServicePointManager]::Expect100Continue = $true;
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
        if (![IO.File]::Exists($destFile)) {
            $sysUrl = "https://live.sysinternals.com/$($utilityName)"

            write-host "Sysinternals process psexec.exe is needed for this option!" -ForegroundColor Yellow
            if ((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y')) {
                $webClient = new-object System.Net.WebClient
                [void]$webClient.DownloadFile($sysUrl, $destFile)
                write-host "sysinternals utility $($utilityName) downloaded to $($destFile)"
            }
            else {
                return [string]::Empty
            }
        }

        return $destFile
    }
    catch {
        "Exception downloading $($utilityName): $($error)"
        $error.Clear()
        return [string]::Empty
    }
}


Main
