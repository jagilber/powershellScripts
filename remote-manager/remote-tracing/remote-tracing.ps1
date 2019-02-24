<#  
.SYNOPSIS  
    powershell script to manage logman ETW tracing and network tracing both locally and remotely

.DESCRIPTION  
    this script will help with the management of ETW and / or network (using netsh) tracing across multiple machines. 
    for stop action, script gather the trace files (.etl) from remote machines and place them in the 'gather' folder in working directory.
    any logman configuration xml files in the -configurationFolder will be deployed.
    see logman.exe export -? for more information on creating xml files.
    
    requirements: 
        at least windows 8 / 2012
        admin powershell prompt
        admin access to os
    
    remote requirements:
        wmi 
        rpc
        smb (unc)
    
    Copyright 2017 Microsoft Corporation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    
.NOTES  
   File Name  : remote-tracing.ps1  
   Author     : jagilber
   Version    : 170626 added exit on bad configurationfolder
   History    : 
                170510 added get-update
                170509 fixed issue with etw session name being blank with configurationfolder switch
                170508.1 fixed issue with config file path and config file delete
                
.EXAMPLE  
    .\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig 
    deploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" to local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig -network
    deploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" and start network tracing on local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action start
    deploy ETW configuration file "single-session.xml" (generated after first start action) to local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action start -network
    start network tracing on local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action start -network -machines 192.168.1.1,192.168.1.2 
    start network tracing on machines machines 192.168.1.1 and 192.168.1.2

.EXAMPLE
    .\remote-tracing.ps1 -action start -machines 192.168.1.1,192.168.1.2 
    deploy ETW configuration file "single-session.xml" (generated after first start action) to machines 192.168.1.1 and 192.168.1.2

.EXAMPLE
    .\remote-tracing.ps1 -action start -network -machines 192.168.1.1,192.168.1.2 
    deploy network tracing to machines 192.168.1.1 and 192.168.1.2

.EXAMPLE
    .\remote-tracing.ps1 -action start -configurationFile single-session.xml -network -machines 192.168.1.1,192.168.1.2 
    deploy ETW configuration file "single-session.xml" (generated after first start action) and network tracing to machines 192.168.1.1 and 192.168.1.2

.EXAMPLE
    .\remote-tracing.ps1 -action start -machines 192.168.1.1,192.168.1.2 -permanent $true -configurationFolder .\remoteDesktopServicesConfig 
    deploy all ETW configuration files in configurationFolder ".\remoteDesktopServicesConfig" to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots)

.EXAMPLE
    .\remote-tracing.ps1 -action stop
    undeploy ETW configuration file "single-session.xml" (generated after first start action) from local machine using default etl output folder ".\gather"

.EXAMPLE  
    .\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig -network
    undeploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" and stop network tracing on local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action stop -network
    stop network tracing on local machine

.EXAMPLE  
    .\remote-tracing.ps1 -action stop -network -machines 192.168.1.1,192.168.1.2 
    stop network tracing on machines machines 192.168.1.1 and 192.168.1.2

.EXAMPLE
    .\remote-tracing.ps1 -action stop -machines 192.168.1.1,192.168.1.2
    undeploy ETW configuration file "single-session.xml" (generated after first start action) from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"

.EXAMPLE
    .\remote-tracing.ps1 -action stop -machines 192.168.1.1,192.168.1.2 -traceFolder c:\temp -configurationFolder .\remoteDesktopServicesConfig
    undeploy all ETW configuration files in configurationFolder ".\remoteDesktopServicesConfig" from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"

.EXAMPLE
    .\remote-tracing.ps1 -action stop -network -machines 192.168.1.1,192.168.1.2 
    undeploy network tracing from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"

.EXAMPLE
    .\remote-tracing.ps1 -action stop -configurationFile single-session.xml -network -machines 192.168.1.1,192.168.1.2 
    undeploy ETW configuration file "single-session.xml" (generated after first start action) and network tracing from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"

.EXAMPLE
    >netsh trace convert input=lmw-single-sesion.etl output=lmw-single-sesion.etl.csv report=yes
    format traces in .etl file and output to .csv 
    NOTE: not all traces will be formatted. some require TMF files that are not available externally.
    Traces that can be converted are 'Manifest' tracing that is same / similar to events outputted to event logs.

.PARAMETER action
    The action to take. Currently this is 'start','stop','generateConfig'. start will enable logman ETW sessions on specified computer(s). stop will disable logman ETW sessions on specified computer(s).
    GenerateConfig, will query logman for currently running traces for baseline, pause for new logman / etw traces to be added, on resume will query logman again
        for differences. the differences will be exported out by session to an xml file for each session. these xml files can then be added to the configurationFolder
        for future use.

.PARAMETER configurationFile
    configuration file or configuration folder need to specified. configuration file should contain xml format of ETW providers to trace. to create xml files, use '-action generateConfig'
    by default the file name is single-session.xml

.PARAMETER configurationFolder
    configuration file or configuration folder need to specified. configuration folder should contain xml format of files of ETW providers to trace. 
    to create xml files, use '-action generateConfig'

.PARAMETER continue
    if specified, will continue on error

.PARAMETER getUpdate
    If specified, will compare the current script against the location in github and will update if different.
    
.PARAMETER machines
    the machine(s) to perform action on. If not specified, the local machine is used. Multiple machines should be separated by comma ',' with no spaces in between. 
    a file name and path with list of machines can be specified.

.PARAMETER network
    if specified, will capture a network trace

.PARAMETER noDynamicPath
    if specified, will override default output structure to make it flat

.PARAMETER outputFolder
    if specified, will override default output folder of .\gather

.PARAMETER permanent
    if specified, will add the ETW session permanently to the target machine(s) (autosession). To remove from machine(s) use action stop.

.PARAMETER rds
    if specified, will configure tracing for a rdsh/rdvh environment.

.PARAMETER showDetail
    if specified, will show additional logging in console output

.PARAMETER traceFolder
    if specified will use custom location for etl output. by default this is %systemroot%\temp

#>  
 
Param(
 
    [parameter(Mandatory = $true, HelpMessage = "Enter the action to take: [start|stop|generateConfig]")]
    [string][ValidateSet('start', 'stop', 'generateConfig')] $action,
    [parameter(HelpMessage = "Specify xml configuration file.")]
    [string] $configurationFile = "",
    [parameter(HelpMessage = "Specify xml configuration folder.")]
    [string] $configurationFolder = "",
    [parameter(HelpMessage = "Enter false to stop after error.")]
    [bool] $continue = $true,
    [parameter(HelpMessage = "Enter etl file to format.")]
    [switch] $formatEtl,
    [parameter(HelpMessage = "Enter to check for script update.")]
    [switch] $getUpdate,
    [parameter(HelpMessage = "Enter single, comma separated, process list of processes to enable for ldap client")]
    [string[]] $ldap = @(),
    [parameter(HelpMessage = "Enter single, comma separated, or file name with list of machines to manage")]
    [string[]] $machines,
    [parameter(HelpMessage = "Select this switch to capture network tracing.")]
    [switch] $network,
    [switch] $noretry,
    [parameter(HelpMessage = "Select this switch force all files to be flat when run on a single machine")]
    [switch] $nodynamicpath,
    [parameter(HelpMessage = "Enter output folder where all collected traces will be copied")]
    [string] $outputFolder = ".\gather", 
    [parameter(HelpMessage = "Specify to enable tracing across reboots.")]
    [switch] $permanent,
    [parameter(HelpMessage = "Specify to enable tracing for Remote Desktop Services.")]
    [switch] $rds,
    [parameter(HelpMessage = "Select this switch to show additional logging")]
    [switch]$showDetail = $false,
    [parameter(HelpMessage = "Enter trace folder where .etl files will be written to while tracing")]
    [string] $traceFolder = [Environment]::GetEnvironmentVariables("Machine").TMP,
    [parameter(HelpMessage = "Enter false to disable singleEtwSession. disabling will use more resources.")]
    [bool] $useSingleEtwSession = $true
)
 
# modify
$logFile = "remote-tracing-log.txt"
$removeEmptyEtls = $true
 
[string] $logAppend = 0 #true -1 only 1 of these 3 can be true
[string] $logOverwrite = 0 #true -1 only 1 of these 3 can be true
[string] $logCircular = -1 #true -1 only 1 of these 3 can be true
[string] $bufferSizeKB = 20
[string] $minBuffersKB = 40
[string] $maxBuffersKB = 80
[string] $etlFileSizeMB = 500
 
# dont modify
$defaultConfigurationFile = ".\single-session.xml"
$ErrorActionPreference = "SilentlyContinue"
$logman = "logman.exe"
$global:configurationFiles = @()
$global:copyFiles = @{}
$global:defaultFolder = $outputFolder
$global:outputFolder = $outputFolder
$global:jobs = @()
$jobThrottle = 10
$minBuild = 9200
$networkEtlFile = "network.etl"
$networkStartCommand = "netsh.exe trace start capture=yes report=disabled persistent=no filemode=circular overwrite=yes maxsize=1024 tracefile="
$networkStopCommand = "netsh.exe trace stop"
$retryCount = 3
$processWaitMs = 10000
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/remote-tracing.ps1"
$workingDir = ""

add-type -TypeDefinition @'
    public enum ActionType 
    {
        start,
        stop,
        generateConfig,
        unknown
    }
'@

[ActionType] $currentAction = [ActionType]::unknown

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    log-info "============================================="
    log-info "Starting"
    $error.Clear()  
    $retval = $null

    # check minimun os ver
    if (!([environment]::OSVersion.Version.Build -ge $minBuild))
    {
        log-info "script requires at least windows 8 / 2012. exiting script"
        exit 2
    }

    # run as administrator
    if (($ret = runas-admin) -eq $false)
    {
        exit 3
    }

    # see if new (different) version of file
    if ($getUpdate)
    {
        if (get-update -updateUrl $updateUrl -destinationFile $MyInvocation.ScriptName)
        {
            exit
        }
    }

    $workingDir = get-workingDirectory

    if ($workingDir.Contains(" "))
    {
        log-info "error:working directory path contains a space. please move script and files to path without space and restart. $($workingDir)"
        exit 4
    }

    # clean up old powershell jobs
    clean-jobs

    # verify and convert action to enum
    [ActionType] $currentAction = determine-action $action

    # if generateConfig then query logman for base line, pause, and query again for differences
    if ($currentAction -eq [ActionType]::generateConfig)
    {
        # set to multisession to split output into named files instead of single-session
        $useSingleEtwSession = $false
        log-info "generating config xml files"
        generate-config
        return
    }
    
    $global:defaultFolder = $global:outputFolder = $global:outputFolder.Replace(".\", "$(get-location)\")

    if (!$network -and [string]::IsNullOrEmpty($configurationFile) -and $useSingleEtwSession)
    {
        # if network not specified its ok to default file name
        # this is to prevent etw from running when intent is only -network
        $configurationFile = $defaultConfigurationFile
    }
 
    # set full paths
    $defaultConfigurationFile = $defaultConfigurationFile.Replace(".\", "$(get-location)\")
    $configurationFile = $configurationFile.Replace(".\", "$(get-location)\")
    $configurationFolder = $configurationFolder.Replace(".\", "$(get-location)\")
    $singleEtwSessionNameFile = $configurationFile
    $singleEtwSessionName = [IO.Path]::GetFileNameWithoutExtension($singleEtwSessionNameFile)

    # should pass configuration file or folder if not network
    if (($configurationFile -and ![IO.File]::Exists($configurationFile)) `
            -and ($configurationFolder -and ![IO.Directory]::Exists($configurationFolder)))
    {
        log-info "neither configuration file '$($configurationFile)' exists nor configuration folder '$($configurationFolder)' exists. exiting."
        log-info "use configurationfile or configurationfolder argument"
        exit 5
    }

    if (![string]::IsNullOrEmpty($configurationFolder) -and [IO.Directory]::Exists($configurationFolder))
    {
        # verify config files are available
        $configurationFolder = verify-configFiles
    
        # delete previous singlesessionfile if it exists

        # enumerate config files
        $global:configurationFiles = [IO.Directory]::GetFiles($configurationFolder, "*.xml", [IO.SearchOption]::AllDirectories)

        if ($useSingleEtwSession)
        {
            $singleEtwSessionNameFile = $defaultConfigurationFile 
            $singleEtwSessionName = [IO.Path]::GetFileNameWithoutExtension($singleEtwSessionNameFile)

            if ([IO.File]::Exists($singleEtwSessionNameFile))
            {
                [IO.File]::Delete($singleEtwSessionNameFile);
            }

            # populate configurationFiles from configuration directory
            populate-configFiles -action $currentAction -configFiles $global:configurationFiles
        }
    }
    elseif ([string]::IsNullOrEmpty($configurationFile) -or ![IO.File]::Exists($configurationFile) -and !$network)
    {
        log-info "error: invalid arguments. need valid configurationFolder or configurationFile if not tracing network. exiting."
        exit 6
    }

    if ($useSingleEtwSession -and [IO.File]::Exists($singleEtwSessionNameFile))
    {
        populate-configFiles -action $currentAction -configFiles @($singleEtwSessionNameFile)
        $global:configurationFiles = $singleEtwSessionNameFile
    }

    $traceFolder = $traceFolder.Replace(":", "$")

    log-info "Setting default etl output folder to: $($traceFolder)"
 
    # add local machine if empty
    if ($machines.Count -lt 1)
    {
        $machines += $env:COMPUTERNAME
    }
    elseif ($machines.Count -eq 1 -and $machines[0].Contains(","))
    {
        # when passing comma separated list of machines from bat, it does not get separated correctly
        $machines = $machines[0].Split(",")
    }
    elseif ($machines.Count -eq 1 -and [IO.File]::Exists($machines))
    {
        # file passed in
        $machines = [IO.File]::ReadAllLines($machines);
    } 

    # run commands
    try
    { 
        run-commands -currentAction $currentAction -configFiles $global:configurationFiles
    }
    catch
    {
        log-info "exception:$($error)"
    }

    # perform any pending file copies
    [string[]] $resultFiles = copy-files $global:copyFiles

    # clean up    
    if (get-job)
    {
        clean-jobs -silent $true
    }

    # display file tree
    if ($currentAction -eq [ActionType]::stop -and [IO.Directory]::Exists($global:outputFolder))
    {
        tree /a /f $($global:outputFolder)
    }

    log-info "finished"    
}
 
# ----------------------------------------------------------------------------------------------------------------
function check-ProcessOutput([string] $output, [ActionType] $action, [bool] $shouldHaveSession = $false, [bool] $shouldNotHaveSession = $false, [string] $sessionName = "")
{
    if ($action -eq [ActionType]::start)
    {
        if ($output -imatch "Data Collector Set already exists" -and !$shouldHaveSession)
        {
            # this is ok
            log-info "warning: $($output)"
            return $false
        }
    }
    elseif ($action -eq [ActionType]::stop)
    {
        if ($output -imatch "Data Collector Set was not found" -and !$shouldNotHaveSession)
        {
            # this is not ok if trace was running. show warning
            log-info "warning: $($output)"
            return $false
        }
    }

    if (![string]::IsNullOrEmpty($sessionName) -and $shouldHaveSession)
    {
        if ($output -inotmatch $sessionName)
        {
            log-info "warning: $($sessionName) does not exist!"
            return $false
        }
    }

    if (![string]::IsNullOrEmpty($sessionName) -and $shouldNotHaveSession)
    {
        if ($output -imatch $sessionName)
        {
            log-info "warning: $($sessionName) is running but should not be!"
            return $false
        }
    }

    if (![string]::IsNullOrEmpty($sessionName))
    {
        if ($output -imatch $sessionName)
        {
            log-info "$($sessionName) etw trace is started"
        }
        else
        {
            log-info "$($sessionName) etw trace is not started"
        }
    }

    if ($output -imatch "error|fail|exception")
    {
        return $false
    }
    else
    {
        return $true
    }
}

# ----------------------------------------------------------------------------------------------------------------
function clean-jobs($silent = $false)
{
    if (get-job)
    {
        if (!$silent)
        {
            [string] $ret = read-host -Prompt "There are existing jobs, do you want to clear?[y:n]" 
            if ($ret -ieq "n")
            {
                return
            }
        }

        get-job 

        while (get-job)
        {
            get-job | remove-job -Force
        }
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function copy-files($files)
{
    $resultFiles = @()
 
    foreach ($kvp in $files.GetEnumerator())
    {
        if ($kvp -eq $null)
        {
            continue
        }
 
        $destinationFile = $kvp.Value
        $sourceFile = $kvp.Key
 
        if (!(Test-Path $sourceFile))
        {
            log-info "Warning:Copying File:No source. skipping:$($sourceFile)"
            continue
        }
 
        $count = 0
 
        while ($count -lt 30)
        {
            try
            {
                if (is-fileLocked $sourceFile)
                {
                    start-sleep -Seconds 1
                    $count++          
                    If ($count -lt 30)          
                    {
                        Continue
                    }
                }
                
                log-info "Copying File:$($sourceFile) to $($destinationFile)"
                [IO.File]::Copy($sourceFile, $destinationFile, $true)
            
                log-info "Deleting File:$($sourceFile)"
                [IO.File]::Delete($sourceFile)
 
                if ($removeEmptyEtls)
                {
                    $fileInfo = new-object System.IO.FileInfo($destinationFile)
 
                    if ($fileInfo.Length -le 8192)
                    {
                        log-info "Deleting Empty Etl:$($destinationFile)"
                        [IO.File]::Delete($destinationFile)
                        break
                    }
                }
                
                if($formatEtl)
                {
                    run-process -processName "cmd.exe" -arguments "/c netsh.exe trace convert input=$($destinationFile) output=$($destinationFile).csv report=no" -wait $false
                }

                if(test-path $destinationFile)
                {
                    # add file if exists local to return array for further processing
                    $resultFiles += $destinationFile
                }

                break
            }
            catch
            {
                log-info "Exception:Copying File:$($sourceFile) to $($destinationFile): $($Error)"
                $Error.Clear()
                $count++
                start-sleep -Seconds 1
            }
        }
    }
 
    return $resultFiles
}

# ----------------------------------------------------------------------------------------------------------------
function determine-action($action)
{
    [ActionType] $at = [ActionType]::unknown
 
    switch ($action.Trim().ToLower())
    {
        "start"
        {
            $at = [ActionType]::start 
        }
        "stop"
        {
            $at = [ActionType]::stop  
        }
        "generateConfig"
        {
            $at = [ActionType]::generateConfig 
        }
        default
        {
            log-info "Unknown action:$($action): should be start or stop. exiting"
            exit
        }
    }
    
    return $at    
}

# ----------------------------------------------------------------------------------------------------------------
function generate-config()
{

    # get base traces before adding new ones to export
    $output = run-logman -arguments "query -ets" -returnResults
    log-info $output

    $regexPattern = "\n(?<set>[a-zA-Z0-9-_ ]*)\s*(?<type>Trace)\s*(?<status>\w*)"
    $regex = New-Object Text.RegularExpressions.Regex ($regexPattern, [Text.RegularExpressions.RegexOptions]::Singleline)
    $result = $regex.Matches($output)
    $originalList = @{}

    for ($i = 0; $i -lt $result.Count; $i++)
    {
        $loggerName = ($result[$i].Groups['set'].Value).Trim()
        $loggerStatus = ($result[$i].Groups['status'].Value).Trim()

        if (![String]::IsNullOrEmpty($loggerName))
        {
            $originalList.Add($loggerName, $loggerStatus)
        }
    }

    log-info "base trace information gathered. Add new logman sessions now."
    read-Host 'Press Enter to continue...' | out-null

    # get new traces after adding new ones to export
    $output = run-logman -arguments "query -ets" -returnResults
    log-info $output
    $result = $regex.Matches($output)
    $newList = @{}

    for ($i = 0; $i -lt $result.Count; $i++)
    {
        $loggerName = ($result[$i].Groups['set'].Value).Trim()
        $loggerStatus = ($result[$i].Groups['status'].Value).Trim()
        
        if (![String]::IsNullOrEmpty($loggerName))
        {
            if (!$originalList.ContainsKey($loggerName))
            {
                $newList.Add($loggerName, $loggerStatus)
            }
        }
    }

    #export out only new logman sessions
    if ($newList.Count -gt 0)
    {
        foreach ($session in $newList.GetEnumerator())
        {
            $output = run-logman -arguments "export `"$($session.Key)`" -ets -xml `"$($workingDir)\$($session.Key).xml`"" -returnResults
            populate-configFiles -configFiles "$($workingDir)\$($session.Key).xml"
        }
    }
    else
    {
        log-info "no new logman sessions to process"   
    }

    log-info "finished"
}
 
# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    $retVal = [string]::Empty
 
    if (Test-Path variable:\hostinvocation)
    {
        $retVal = $hostinvocation.MyCommand.Path
    }
    else
    {
        $retVal = (get-variable myinvocation -scope script).Value.Mycommand.Definition
    }
  
    if (Test-Path $retVal)
    {
        $retVal = (Split-Path $retVal)
    }
    else
    {
        $retVal = (Get-Location).path
        log-info "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
    } 
    
    Set-Location $retVal | out-null
    return $retVal
}

#----------------------------------------------------------------------------
function get-update($updateUrl, $destinationFile)
{
    log-info "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 

        # git  may not have carriage return
        if ([regex]::Matches($git, "`r").Count -eq 0)
        {
            $git = [regex]::Replace($git, "`n", "`r`n")
        }

        if (![IO.File]::Exists($destinationFile))
        {
            $file = ""    
        }
        else
        {
            $file = [IO.File]::ReadAllText($destinationFile)
        }

        if (([string]::Compare($git, $file) -ne 0))
        {
            log-info "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            log-info "script is up to date"
        }
        
        return $false
    }
    catch [System.Exception] 
    {
        log-info "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function is-fileLocked([string] $file)
{
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false)
    {
        log-info "File does not exist:$($file)"
        return $false
    }
  
    try
    {
        $fileStream = $fileInfo.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        if ($fileStream)
        {
            $fileStream.Close()
        }
 
        log-info "File is NOT locked:$($file)"
        return $false
    }
    catch
    {
        # file is locked by a process.
        log-info "File is locked:$($file)"
        return $true
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $foregroundColor = "White"
    if ([string]::IsNullOrEmpty($data))
    {
        return
    }

    if ($data -imatch "error")
    {
        $foregroundColor = "Red"
    }
    elseif ($data -imatch "fail")
    {
        $foregroundColor = "Red"
    }
    elseif ($data -imatch "warning")
    {
        $foregroundColor = "Yellow"
    }
    elseif ($data -imatch "exception")
    {
        $foregroundColor = "Yellow"
    }
    elseif ($data -imatch "running process")
    {
        $foregroundColor = "Cyan"
    }
    elseif ($data -imatch "success")
    {
        $foregroundColor = "Green"
    }
    elseif ($data -imatch "is started")
    {
        $foregroundColor = "Green"
    }
    elseif ($data -imatch "is not started")
    {
        $foregroundColor = "Gray"
    }
    
    $data = "$([DateTime]::Now):$($data)`n"
    Write-Host $data -ForegroundColor $foregroundColor
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
function manage-ldapRegistry([ActionType] $currentAction, [string] $machine, [string[]] $processNames = @("svchost.exe"))
{
    $hklm = 2147483650
    $key = "SYSTEM\CurrentControlSet\Services\ldap\Tracing"
    $wmi = new-object Management.ManagementClass "\\$($machine)\Root\default:StdRegProv" 
    $ret = $null

    foreach ($processName in $processNames)
    {
        switch ($currentAction)
        {
            ([ActionType]::start)
            {
                # to enable
                $ret = $wmi.CreateKey($hklm, "$($key)\$($processName)")
            }
 
            ([ActionType]::stop)
            {
                # to disable
                $ret = $wmi.DeleteKey($hklm, "$($key)\$($processName)")
            }
 
            default
            {
                log-info "Unknown action:$($currentAction): should be start or stop. exiting"
                exit 1
            }
        }
    }
 
    log-info $ret
    return
}

# ----------------------------------------------------------------------------------------------------------------
function manage-rdsRegistry([ActionType] $currentAction, [string] $machine)
{
    # level is typically 0xff
    # flags is typically 0xffffffff
 
    $levelValue = "0xff"
    $flagsValue = "0xffffffff"
    $hklm = 2147483650
    $key = "SYSTEM\CurrentControlSet\Control\Terminal Server"
    $ret = $null 
    $valueNames = @(
        "lsm",
        "termsrv",
        "sdclient",
        "rdpcoremkts",
        "winsta",
        "tsrpc",
        "TSVIPCli",
        "TSVIPSrv",
        "SessionEnv",
        "SessionMsg")
    
    $wmi = new-object Management.ManagementClass "\\$($machine)\Root\default:StdRegProv" 
    
    foreach ($valueName in $valueNames)
    {
        switch ($currentAction)
        {
            ([ActionType]::start)
            {
                # to enable
                $ret = $wmi.SetDWORDValue($hklm, $key, ("Debug$($valueName)"), "1")
                # to enable to debugger
                $ret = $wmi.SetDWORDValue($hklm, $key, ("Debug$($valueName)ToDebugger"), "1")
                # to set flags
                $ret = $wmi.SetDWORDValue($hklm, $key, ("Debug$($valueName)Flags"), $flagsValue)
                # to set level
                $ret = $wmi.SetDWORDValue($hklm, $key, ("Debug$($valueName)Level"), $levelValue)
            }
 
            ([ActionType]::stop)
            {
                # to disable
                $ret = $wmi.DeleteValue($hklm, $key, ("Debug$($valueName)"))
                # to disable to debugger
                $ret = $wmi.DeleteValue($hklm, $key, ("Debug$($valueName)ToDebugger"))
                # to delete flags
                $ret = $wmi.DeleteValue($hklm, $key, ("Debug$($valueName)Flags"))
                # to delete level
                $ret = $wmi.DeleteValue($hklm, $key, ("Debug$($valueName)Level"))
            }
 
            default
            {
                log-info "Unknown action:$($currentAction): should be start or stop. exiting"
                exit 1
            }
        }
    }
 
    log-info $ret
    return
}

# ----------------------------------------------------------------------------------------------------------------
function populate-configFiles([string[]] $configFiles)
{
    # modify settings in config files for environment
    foreach ($file in $configFiles)
    {
        [xml.xmldocument] $xmlDoc = xml-reader $file
 
 
        $xmlDoc.DocumentElement.RootPath = $traceFolder 
        $xmlDoc.DocumentElement.LatestOutputLocation = [string]::Empty
        $xmlDoc.DocumentElement.OutputLocation = [string]::Empty
        $xmlDoc.DocumentElement.TraceDataCollector.FileName = [string]::Empty    
 
        # set session specific information here
        $xmlDoc.DocumentElement.SegmentMaxSize = $etlFileSizeMB
        $xmlDoc.DocumentElement.TraceDataCollector.LogAppend = $logAppend
        $xmlDoc.DocumentElement.TraceDataCollector.LogOverwrite = $logOverwrite
        $xmlDoc.DocumentElement.TraceDataCollector.LogCircular = $logCircular
        $xmlDoc.DocumentElement.TraceDataCollector.BufferSize = $bufferSizeKB
        $xmlDoc.DocumentElement.TraceDataCollector.MinimumBuffers = $minBuffersKB
        $xmlDoc.DocumentElement.TraceDataCollector.MaximumBuffers = $maxBuffersKB
        $xmlDoc.DocumentElement.TraceDataCollector.LatestOutputLocation = [string]::Empty
            
        if ($useSingleEtwSession)
        {
            # create new single session file
            if (!([IO.File]::Exists($singleEtwSessionNameFile)))
            {
                $xmlDoc.DocumentElement.Name = $singleEtwSessionName
                $xmlDoc.DocumentElement.TraceDataCollector.Name = $singleEtwSessionName
                $xmlDoc.DocumentElement.TraceDataCollector.SessionName = $singleEtwSessionName
                xml-writer -file $singleEtwSessionNameFile -xdoc $xmlDoc
            }  
            else
            {
                [xml.xmldocument] $xmlDocSingle = xml-reader $singleEtwSessionNameFile
                $dupe = $false
                $xmlDocSingle.DocumentElement.Name = $singleEtwSessionName
                $xmlDocSingle.DocumentElement.TraceDataCollector.Name = $singleEtwSessionName
                $xmlDocSingle.DocumentElement.TraceDataCollector.SessionName = $singleEtwSessionName
                 
                foreach ($node in $xmlDoc.DocumentElement.TraceDataCollector.GetElementsByTagName("TraceDataProvider"))
                {
                    # check for dupes
                    foreach ($t in $xmlDocSingle.DocumentElement.TraceDataCollector.GetElementsByTagName("Guid")) 
                    {
                        if ((($t.'#text').ToString()) -imatch ($Node.Guid.ToString()))
                        {
                            #dupe
                            log-info "dupe guid:$($node.Guid)"
                            $dupe = $true
                            break
                        }
                    }
                        
                    if (!$dupe)
                    {
                        $newNode = $xmlDocSingle.ImportNode($node, $true)
                        $ret = $xmlDocSingle.DocumentElement.TraceDataCollector.AppendChild($newNode)
                    }
                }
 
                xml-writer -file $singleEtwSessionNameFile -xdoc $xmlDocSingle
            }
        }
        else
        {
            xml-writer -file $file -xdoc $xmlDoc
        }
    }
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    write-verbose "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        if (!$noretry)
        { 
            $commandLine = ($Script:MyInvocation.Line).Replace(".\", "$(get-location)\")
            write-host "restarting script as administrator."
            Write-Host "run-process -processName powershell.exe -arguments -NoExit -ExecutionPolicy Bypass -File $($commandLine) -noretry"
            $ret = run-process -processName "powershell.exe" -arguments "-NoExit -ExecutionPolicy Bypass -File $($commandLine) -noretry" -runas $true
        }
       
        return $false
    }
    else
    {
        write-verbose "running as admin"
    }

    return $true   
}

# ----------------------------------------------------------------------------------------------------------------
function run-commands([ActionType] $currentAction, [string[]] $configFiles)
{
    $machineFolder = [string]::Empty   
    $dirName = ([DateTime]::Now).ToString("yyyy-MM-dd-hh-mm-ss")
 
    foreach ($machine in $machines)
    {
        
        $machine = $machine.Trim()
        if ([String]::IsNullOrEmpty($machine))
        {
            continue
        }

        # add / remove ldap etw registry settings
        if ($ldap)
        {
            manage-ldapRegistry -currentAction $currentAction -machine $machine -processNames $ldap
        }
 
        # add / remove rds debug registry settings
        if ($rds)
        {
            manage-rdsRegistry -currentAction $currentAction -machine $machine
        }
        
        # store files in computer folder or in root
        if ($nodynamicpath)
        {
            $machineFolder = $global:outputFolder
        }
        elseif ($useSingleEtwSession)
        {
            $machineFolder = $global:outputFolder = "$($global:defaultFolder)\$($dirName)"
        }
        else
        {
            $global:outputFolder = "$($global:defaultFolder)\$($dirName)"
            $machineFolder = "$($global:defaultFolder)\$($dirName)\$($machine)"            
        }

        $etlFileFolder = "\\$($machine)\$($traceFolder)"

        if ($currentAction -eq ([ActionType]::stop))
        {
            # verify etl local destination
            if (!(Test-Path $machineFolder))
            {
                log-info "Creating Directory:$($machineFolder)"
                [void][IO.Directory]::CreateDirectory($machineFolder)
            }
        }
 
        if ($configFiles.Length -gt 0)
        {
            if ($showDetail) 
            {
                if ($permanent)
                {
                    run-logman -arguments "query autosession\* -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::stop) -shouldNotHaveSession ($currentAction -eq [ActionType]::start)
                }
                else
                {
                    run-logman -arguments "query -ets -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::stop) -shouldNotHaveSession ($currentAction -eq [ActionType]::start)
                }
            }

            foreach ($file in $configFiles)
            {
                $baseFileName = [IO.Path]::GetFileNameWithoutExtension($file)
                $fullLoggerName = $loggerName = "lmw-$($baseFileName)"
 
                if ($permanent)
                {
                    $fullLoggerName = "autosession\$($loggerName)"
                }
            
                $etlFile = "$($etlFileFolder)\$($baseFileName).etl"
 
                switch ($currentAction)
                {
                    ([ActionType]::start) 
                    {
                        # make sure etl file does not already exist
                    
                        if (Test-Path $etlFile)
                        {
                            log-info "Deleting old etl file:$($etlFile)"
                            [IO.File]::Delete($etlFile)
                        }
 
                        # make sure etl dir exists
                        if (!(Test-Path $etlFileFolder))
                        {
                            [IO.Directory]::CreateDirectory($etlFileFolder)
                        }
 
                        # query to see if session already exists. it shouldnt if we are starting
                        if ($showDetail) 
                        {
                            run-logman -arguments "query -ets -s $($machine)" -shouldNotHaveSession $true -sessionName $loggerName
                        }
 
                        # import configuration from xml file
                        if ($permanent)
                        {
                            # will start next boot
                            run-logman -arguments "import -n $($fullLoggerName) -s $($machine) -xml $($file)"
                            # will start now
                            run-logman -arguments "start $($loggerName) -ets -s $($machine)" -shouldHaveSession $true
                        }
 
                        # will start now only for this boot
                        run-logman -arguments "import -n $($loggerName) -ets -s $($machine) -xml $($file)"
                        run-logman -arguments "query -ets -s $($machine)" -shouldHaveSession $true -sessionName $loggerName
                    }
 
                    ([ActionType]::stop) 
                    {
                        # query to see if session exists. session should exist if we are stoping
                        if ($showDetail) 
                        {
                            run-logman -arguments "query -ets -s $($machine)" -shouldHaveSession $true -sessionName $loggerName
                        }
 
                        run-logman -arguments "stop $($loggerName) -ets -s $($machine)"
                    
                        # delete session
                        if ($permanent)
                        {
                            run-logman -arguments "delete $($fullloggerName) -ets -s $($machine)"
                        }

                        run-logman -arguments "query -ets -s $($machine)" -shouldNotHaveSession $true -sessionName $loggerName

                        # add etl files to list for copy back to local machine
                        if ([IO.File]::Exists($etlFile))
                        {
                            $destFile = "$($machineFolder)\$($machine)-$([IO.Path]::GetFileName($etlFile))"
                            log-info "Adding file to be copied source: $($etlFile) dest: $($destFile)"
                            $global:copyFiles.Add($etlFile, $destFile);
                        }
                        else
                        {
                            log-info "error: $($etlFile) does NOT exist! you may need to troubleshoot and restart tracing."
                        }
                    }
 
                    default
                    {
                        log-info "Unknown action:$($currentAction): should be start or stop. exiting"
                        exit
                    }
                } # end switch
            } # end foreach
 
            #if($permanent)
            #{
            #    run-logman -arguments "query autosession\* -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::start) -shouldNotHaveSession ($currentAction -eq [ActionType]::stop)
            #}
            #else
            #{
            #    run-logman -arguments "query -ets -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::start) -shouldNotHaveSession ($currentAction -eq [ActionType]::stop)
            #}
        } # end if configfiles.length

        if ($network)
        {
            $command = @{ 
                'name'       = "netsh";
                'wait'       = $true;
                'command'    = "";
                'workingDir' = $traceFolder.Replace("$", ":");
            }

            switch ($currentAction)
            {
                ([ActionType]::start) 
                {
                    $destFile = ("$($traceFolder)\$($machine)-$([IO.Path]::GetFileName($networkEtlFile))").Replace("$", ":")
                    $command.command = "$($networkStartCommand)$($destFile)"
                    log-info "starting network trace $($machine)"
                }

                ([ActionType]::stop) 
                {
                    $command.command = $networkStopCommand
                    $etlFile = "$($etlFileFolder)\$($machine)-$([IO.Path]::GetFileName($networkEtlFile))"
                    $destFile = "$($machineFolder)\$([IO.Path]::GetFileName($etlFile))"
                    
                    log-info "stopping network trace $($machine)"
                    log-info "Adding network file to be copied source: $($etlFile) dest: $($destFile)"
                    $global:copyFiles.Add($etlFile, $destFile);
                }

                default
                {
                    log-info "Unknown action:$($currentAction): should be start or stop. exiting"
                    exit
                }
            }

            run-wmiCommandJob -command $command -machine $machine
        }   
    }

    wait-forJobs
    return
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-logman([string] $arguments, [bool] $shouldHaveSession = $false, [bool] $shouldNotHaveSession = $false, [switch] $returnResults, [string] $sessionName = "")
{
    $count = 1
    while($count -le $retryCount)
    {
        $retval = run-process -processName $logman -arguments $arguments -wait $true
        $result = check-processOutput -output $retval `
            -action $currentAction `
            -shouldHaveSession $shouldHaveSession `
            -shouldNotHaveSession $shouldNotHaveSession `
            -sessionName $sessionName
    
        if($result)
        {
            break
        }
        elseif (!$result -and !$continue)
        {
            log-info "error in logman command. exiting. use -continue switch to ignore errors"
            log-info "error: $($retval)"
            exit 1
        }
        elseif (!$resut -and $arguments -imatch "query")
        {
            log-info "retrying..."
            Start-Sleep -Seconds 1
            $count++
        }
        else
        {
            break
        }
    }

    if ($returnResults)
    {
        return $retval
    }
    else
    {
        return
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false, [bool] $runas = $false)
{
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = !$wait
    $process.StartInfo.RedirectStandardOutput = $wait
    $process.StartInfo.RedirectStandardError = $wait
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $wait
    $process.StartInfo.WorkingDirectory = get-location
    
    if ($runas)
    {
        $process.StartInfo.Verb = "runas"
    }

    [void]$process.Start()
    if ($wait -and !$process.HasExited)
    {
        [void]$process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        
        if ($showDetail)
        {
            log-info "Process output:$stdOut"
        }
 
        if (![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            log-info "Error:$stdErr `n $Error"
            $Error.Clear()
            
            if (!$continue)
            {
                exit 1
            }
        }
    }
    elseif ($wait)
    {
        log-info "Process ended before capturing output."
    }

    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
function run-wmiCommandJob($command, $machine)
{

    $functions = {
        function log-info($data)
        {
            $data = "$([System.DateTime]::Now):$($data)`n"
            Write-Host $data
        }
    }

    #throttle
    while ((Get-Job | Where-Object { $_.State -eq 'Running' }).Count -gt $jobThrottle)
    {
        Start-Sleep -Milliseconds 100
    }

    log-info "starting wmi job: $($machine)-$($command.Name)"
    $job = Start-Job -Name "$($machine)-$($command.Name)" -InitializationScript $functions -ScriptBlock {
        param($command, $machine)

        try
        {
            write-host "running wmi command: $($command.command) from dir: $($command.workingDir)"
            $startup = [wmiclass]"Win32_ProcessStartup"
            $startup.Properties['ShowWindow'].value = $False
            # $ret = Invoke-WmiMethod -ComputerName $machine -Class Win32_Process -Name Create -Impersonation Impersonate -ArgumentList @($command.command, $command.workingDir, $startup)
            $wmiP = new-object System.Management.ManagementClass "\\$($machine)\Root\cimv2:Win32_Process" 
            $ret = $wmiP.Create($command.command, $command.workingDir, $startup)
    
            if ($ret.ReturnValue -ne 0 -or $ret.ProcessId -eq 0)
            {
                switch ($result.ReturnValue)
                {
                    0
                    {
                        write-host "$($machine) return:success" 
                    }
                    2
                    {
                        write-host "$($machine) return:access denied" 
                    }
                    3
                    {
                        write-host "$($machine) return:insufficient privilege" 
                    }
                    8
                    {
                        write-host "$($machine) return:unknown failure" 
                    }
                    9
                    {
                        write-host "$($machine) return:path not found" 
                    }
                    21
                    {
                        write-host "$($machine) return:invalid parameter" 
                    }
                    default
                    {
                        write-host "$($machine) return:unknown" 
                    }
                }

                write-host "Error:run-wmiCommand: $($ret.ReturnValue)"
                return
            }

            if ($command.wait)
            {
                while ($true)
                {
                    #write-host "waiting on process: $($ret.ProcessId)"
                    if ((Get-WmiObject -ComputerName $machine -Class Win32_Process -Filter "ProcessID = '$($ret.ProcessId)'"))
                    {
                        Start-Sleep -Seconds 1
                    }
                    else
                    {
                        #write-host "no process"
                        break
                    }
                }
            }
        }
        catch
        {
            write-host "Exception:run-wmiCommand: $($Error)"
            $Error.Clear()
        }
    } -ArgumentList ($command, $machine)
    
    $global:jobs = $global:jobs + $job
}

# ----------------------------------------------------------------------------------------------------------------
function verify-configFiles()
{
    $retval
    log-info "Verifying config files"
 
    # if path starts with a '.' replace with working dir
    if ($configurationFolder.StartsWith(".\"))
    {
        $configurationFolder = "$(get-location)$($configurationFolder.Substring(1))"
        $configurationFolder = $configurationFolder.Trim()
    }
 
    if ([String]::IsNullOrEmpty($configurationFolder) -or !(Test-Path $configurationFolder))
    {
        log-info "logman configuration files not found:$($configurationFolder)"
        log-info "please specify logman configuration file (.xml) files location or add. exiting"
        exit 7
    }
    
    if (!(Test-Path $configurationFolder) -and (Test-Path $defaultTemplateConfigFolder))
    {
        $retval = [IO.Directory]::CreateDirectory($configurationFolder)
 
        if ((Test-Path $configurationFolder) -and (Test-Path $defaultTemplateConfigFolder))
        {
            $retval = Copy-Item $defaultTemplateConfigFolder\* $configurationFolder
        }
        else
        {
            log-info "Config Files do not exist:exiting:" + $configurationFolder
            exit 8
        }
    }
 
    log-info "returning configuration folder:$($configurationFolder)"
    return ($configurationFolder).Trim()
}

# ----------------------------------------------------------------------------------------------------------------
function wait-forJobs()
{
    log-info "jobs count:$($global:jobs.Length)"
    # Wait for all jobs to complete
    $waiting = $true

    if ($global:jobs -ne @())
    {
        while ($waiting)
        {
            $waiting = $false
            foreach ($job in Get-Job)
            {
                if ($showDetail)
                {
                    log-info "waiting on $($job.Name):$($job.State)"
                }

                switch ($job.State)
                {
                    'Stopping'
                    {
                        $waiting = $true 
                    }
                    'NotStarted'
                    {
                        $waiting = $true 
                    }
                    'Blocked'
                    {
                        $waiting = $true 
                    }
                    'Running'
                    {
                        $waiting = $true 
                    }
                }

                if ($stop -and $job.State -ieq 'Completed')
                {
                    # gather files
                    foreach ($machine in $machines)
                    {
                        foreach ($command in $global:stopCommands)
                        {
                            if ($job.Name -ieq "$($machine)-$($command.Name)")
                            {
                                log-info "job completed, copying files from: $($machine) for command: $($command.Name)"
                                gather-files -command $command -machine $machine
                            }
                        }
                    }
                }
                
                # restart failed jobs
                if ($job.State -ieq 'Failed')
                {
                    log-info "** JOB FAILED **"
                    Receive-Job -Job $job
                    Remove-Job -Job $job
                }

                # Getting the information back from the jobs
                if ($job.State -ieq 'Completed')
                {
                    Receive-Job -Job $job
                    Remove-Job -Job $job
                }
            }
            
            if ($job.State -ieq 'Completed')
            {
                foreach ($job in $global:jobs)
                {
                    if ($job.State -ine 'Completed')
                    {
                        if ($showDetail)
                        {
                            log-info ("$($job.Name):$($job.State):$($job.Error)")
                        }

                        Receive-Job -Job $job 
                    }
                }
            }
            else
            {
                Write-Host "." -NoNewline
            }

            Start-Sleep -Seconds 1
        } # end while
    } # end if
}
 
# ----------------------------------------------------------------------------------------------------------------
function xml-reader([string] $file)
{
    if ($showDetail) 
    {
        log-info "Reading xml config file:$($file)"
    }
 
    [Xml.XmlDocument] $xdoc = New-Object System.Xml.XmlDocument
    $xdoc.Load($file)
    return $xdoc
}
 
# ----------------------------------------------------------------------------------------------------------------
function xml-writer([string] $file, [Xml.XmlDocument] $xdoc)
{
    # write xml
    # if xml is not formatted, this will fix it for example when generating config file with logman export
    [IO.StringWriter] $sw = new-object IO.StringWriter
    [Xml.XmlTextWriter] $xmlTextWriter = new-object Xml.XmlTextWriter ($sw)
    $xmlTextWriter.Formatting = [Xml.Formatting]::Indented
    $xdoc.WriteTo($xmlTextWriter)
    $xdoc.PreserveWhitespace = $true
    $xdoc.LoadXml($sw.ToString())

    if ($showDetail)
    {
        log-info "Writing xml config file:$($file)"
    }
    
    $xdoc.Save($file)
}
 
# ----------------------------------------------------------------------------------------------------------------

main
