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
$processName = "notepad" #"logonui" 
$processArgs = ""
$sleepMs = 10
$debugProcess = "procdump.exe" #c:\temp\mon-logonui.bat"
$debugArguments = "-accepteula -ma -e -t -n 10 "

#-------------------------------------------------------------------------------------------------
function main()
{
    #init
    $currentProcessList = enum-processes -processName $processName

    if($syinternalsProcess -and ![IO.File]::Exists($debugProcess))
    {
        if([string]::IsNullOrEmpty((get-sysInternalsUtility -utilityName ([IO.Path]::GetFileName($debugProcess)))))
        {
            "unable to download $($debugProcess). exiting"
            return
        }
    } 

    $count = 0

    while($true)
    {
        $newList = enum-processes -processName $processName
 
        foreach($id in $newList.GetEnumerator())
        {
            if(!$currentProcessList.ContainsKey($id.Key))
            {
                write-host "Adding process to list: $($id.key):$($id.Value)"
                $currentProcessList.Add($id.Key, $process);
                
                if($processArgs -ne $null)
                {
                    $cmdline = Get-WmiObject Win32_Process -Filter "ProcessId like `'$($id.key)`'" 
                    if(!$cmdline.CommandLine.Contains($processArgs))
                    {
                        continue
                   }
                }
 
                #windbg
                #Start-Process -process $debugProcess -arguments "$($debugArguments) -p $($id.Key)"
                
                #procdump
                Start-Process -process $debugProcess -arguments "$($debugArguments) $($id.Key)"
                
                #tttracer
                #Start-Process -process $debugProcess -arguments "$($debugArguments) $($id.Key)"
            }
        }
 
        $tempList = $currentProcessList.Clone();
 
        foreach($id in $tempList.GetEnumerator())
        {
            if(!$newList.ContainsKey($id.Key))
            {
                write-host "Removing process from list: $($id.key):$($id.Value)"
                $currentProcessList.Remove($id.Key);
            }
        }
 
        Start-Sleep -Milliseconds $sleepMs
        if($count -ge 100)
        {
            write-host ""
            $count = 0
        }
        else
        {
            write-host "." -NoNewline
            $count++
        }
    }
 
}
 
#-------------------------------------------------------------------------------------------------
function enum-processes($processName)
{
    $tempL = @{}
    
    foreach($process in [System.Diagnostics.Process]::GetProcessesByName($processName))
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
    if($arguments) { $processStartInfo.Arguments = $arguments }
    #$processStartInfo.UseShellExecute = $false;
    #$processStartInfo.RedirectStandardOutput = $true;
 
    $processObj = [System.Diagnostics.Process]::Start($processStartInfo);
    #$processObj.WaitForExit();
    #$processObj.StandardOutput.ReadToEnd();
 
}
 
#-------------------------------------------------------------------------------------------------
function get-sysInternalsUtility ([string] $utilityName)
{
    try
    {
        $destFile = "$(get-location)\$utilityName"
        
        if(![IO.File]::Exists($destFile))
        {
            $sysUrl = "http://live.sysinternals.com/$($utilityName)"

            write-host "Sysinternals process psexec.exe is needed for this option!" -ForegroundColor Yellow
            if((read-host "Is it ok to download $($sysUrl) ?[y:n]").ToLower().Contains('y'))
            {
                $webClient = new-object System.Net.WebClient
                [void]$webClient.DownloadFile($sysUrl, $destFile)
                write-host "sysinternals utility $($utilityName) downloaded to $($destFile)"
            }
            else
            {
                return [string]::Empty
            }
        }

        return $destFile
    }
    catch
    {
        "Exception downloading $($utilityName): $($error)"
        $error.Clear()
        return [string]::Empty
    }
}

#------------------------------------------------------------------------------------------------- 
Main
