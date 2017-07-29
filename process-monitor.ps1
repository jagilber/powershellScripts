

#-------------------------------------------------------------------------------------------------
# powershell script to monitor for a given process name 
# once new instance of process name is found, run a process
# in this example, ntsd.exe is being attached to the new process
# v 1.0 06/26/2014
# microsoft support
#-------------------------------------------------------------------------------------------------

$currentProcessList = @{}
$tempList = @{}
$newList = @{}
$processName = "taskhost" #"svchost"
$processArgs = "" #"NetworkServiceRemoteDesktopPublishing"
$sleepMs = 100
$debugProcess = "c:\debuggers\windbg.exe"
$debugArguments = "-WF c:\temp\tscpub.wew"

#-------------------------------------------------------------------------------------------------
function main()
{
    #init
    $currentProcessList = enum-processes -processName $processName

    while ($true)
    {
        $newList = enum-processes -processName $processName

        foreach ($id in $newList.GetEnumerator())
        {
            if (!$currentProcessList.ContainsKey($id.Key))
            {
                write-host "Adding process to list: $($id.key):$($id.Value)"
                $currentProcessList.Add($id.Key, $process);
                
                if ($processArgs -ne $null)
                {
                    $cmdline = Get-WmiObject Win32_Process -Filter "ProcessId like `'$($id.key)`'" 
                    if (!$cmdline.CommandLine.Contains($processArgs))
                    {
                        continue
                    }
                }
                
                Start-Process -process $debugProcess -arguments "$($debugArguments) -p $($id.Key)"
            }
        }

        $tempList = $currentProcessList.Clone();

        foreach ($id in $tempList.GetEnumerator())
        {
            if (!$newList.ContainsKey($id.Key))
            {
                write-host "Removing process from list: $($id.key):$($id.Value)"
                $currentProcessList.Remove($id.Key);
            }
        }

        Start-Sleep -Milliseconds $sleepMs

    }

}

#-------------------------------------------------------------------------------------------------
function enum-processes($processName)
{
    $tempL = @{}
        
    foreach ($process in [System.Diagnostics.Process]::GetProcessesByName($processName))
    {
        $tempL.Add($process.Id, $process)
    }

    return $tempL
}

#-------------------------------------------------------------------------------------------------
function start-process($process, $arguments)
{
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

#-------------------------------------------------------------------------------------------------

main


