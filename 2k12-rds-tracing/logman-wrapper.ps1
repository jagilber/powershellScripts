<#  
.SYNOPSIS  
    powershell script to manage logman ETW tracing

.DESCRIPTION  
    This script will help with the deployment and undeployment of ETW tracing across multiple machines. It will additionally gather the trace files (.etl)
    from remote machine and place them in the 'gather' folder in working directory. Any logman configuration xml files in the configurationFolder (default is 'configs' in working directory) 
    will be deployed. See logman.exe export -? for more information on creating xml files.
    
.NOTES  
   File Name  : logmanWrapper.ps1  
   Author     : jagilber
   Version    : 170220 added -configurationFile and modified -machines to use file and -continue to continue on errors and -showDetial. cleaned output
                

   History    : 
                160902 added -nodynamicpath for when being called from another script to centralize all files in common folder
                160519 added switch verifier

.EXAMPLE  
    .\logmanwrapper.ps1 -action deploy
    deploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action deploy -machines 192.168.1.1,192.168.1.2 
    deploy all configuration files in default 'configs' or 'configs_templates' folder to machines 192.168.1.1 and 192.168.1.2 using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action deploy -machines 192.168.1.1,192.168.1.2 -traceFolder c:\temp -permanent $true -configurationFolder c:\temp\configs 
    deploy all configuration files in c:\temp\configs folder to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots). etl output folder is c:\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy
    undeploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy -machines 192.168.1.1,192.168.1.2
    undeploy all configuration files in default 'configs' or 'configs_templates' folder to machines 192.168.1.1 and 192.168.1.2 using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy -machines 192.168.1.1,192.168.1.2 -traceFolder c:\temp -permanent -configurationFolder c:\temp\configs
    undeploy all configuration files in c:\temp\configs folder to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots). etl output folder is c:\temp

.PARAMETER action
    The action to take. Currently this is 'deploy','undeploy','generateConfig'. Deploy will enable logman ETW sessions on specified computer(s). Undeploy will disable logman ETW sessions on specified computer(s).
    GenerateConfig, will query logman for currently running traces for baseline, pause for new logman / etw traces to be added, on resume will query logman again
        for differences. the differences will be exported out by session to an xml file for each session. these xml files can then be added to the configurationFolder
        for future use.

.PARAMETER machines
    The machine(s) to perform action on. If not specified, the local machine is used. Multiple machines should be separated by comma ',' with no spaces in between. A file name and path with list of machines can be specified.
.PARAMETER traceFolder
    This location where the trace (.etl) files will be created on the target machine while actively tracing. By default these will be created in %systemroot%\temp.
.PARAMETER permanent
    If specified, will add the ETW session permanently to the target machine(s) (autosession). To remove from machine(s) use action undeploy.
.PARAMETER configurationFolder
    If specified, will use this folder as the source of the logman xml configuration files instead of the default location of 'configs' in the working directory of script.
.PARAMETER configurationFolder
    If specified, will enable tracing for Remote Desktop Services tracing.
.PARAMETER rds
    If specified, will configure tracing for a rdsh/rdvh environment.
#>  
 
Param(
 
    [parameter(Mandatory=$true,HelpMessage="Enter the action to take: [deploy|undeploy|generateConfig]")]
    [string][ValidateSet('Deploy', 'Undeploy', 'GenerateConfig')] $action,
    [parameter(HelpMessage="Enter single, comma separated, or file name with list of machines to manage")]
    [string[]] $machines,
    [parameter(HelpMessage="Enter output folder where all collected traces will be copied")]
    [string] $outputFolder = ".\gather", 
    [parameter(HelpMessage="Enter trace folder where .etl files will be written to while tracing")]
    [string] $traceFolder = "%systemroot%\temp", 
    [parameter(HelpMessage="Specify to enable tracing across reboots.")]
    [switch] $permanent,
    [parameter(HelpMessage="Specify xml configuration folder.")]
    [string] $configurationFolder = "",
    [parameter(HelpMessage="Specify xml configuration file.")]
    [string] $configurationFile = "single-session.xml",
    [parameter(HelpMessage="Specify to enable tracing for Remote Desktop Services.")]
    [switch] $rds,
    [parameter(HelpMessage="Select this switch force all files to be flat when run on a single machine")]
    [switch] $nodynamicpath,
    [parameter(HelpMessage="Select this switch force all files to be flat when run on a single machine")]
    [switch] $continue,
    [parameter(HelpMessage="Select this switch to show additional logging")]
    [switch]$showDetail = $false
    )
 
# modify
$defaultEtlFolder = "admin$\temp"
$global:defaultFolder = $outputFolder
$global:outputFolder = $outputFolder
$useSingleEtwSession = $true
$singleEtwSessionName = [IO.Path]::GetFileNameWithoutExtension($configurationFile)
$singleEtwSessionNameFile = $configurationFile
$logFile = "logman-Wrapper.log"
$removeEmptyEtls = $true
 
[string] $logAppend = 0 #true -1 only 1 of these 3 can be true
[string] $logOverwrite = 0 #true -1 only 1 of these 3 can be true
[string] $logCircular = -1 #true -1 only 1 of these 3 can be true
[string] $bufferSizeKB = 20
[string] $minBuffersKB = 40
[string] $maxBuffersKB = 80
[string] $etlFileSizeMB = 500
 
# dont modify
$logman = "logman.exe"
$configurationFiles = @()
$copyFiles = @{}
$scriptName
$processWaitMs = 10000
$workingDir
 
add-type -TypeDefinition @'
    public enum ActionType 
    {
        deploy,
        undeploy,
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
  
    $retval
 
    set-location $psscriptroot
    $workingDir = (get-location).path

    if($workingDir.Contains(" "))
    {
        log-info "error:working directory path contains a space. please move script and files to path without space and restart. $($workingDir)"
        return
    }

    $global:defaultFolder = $global:outputFolder = $global:outputFolder.Replace(".\","$(get-location)\")
 
    # set full paths
    $configurationFile = $configurationFile.Replace(".\","$(get-location)\")
    $configurationFolder = $configurationFolder.Replace(".\","$(get-location)\")

    # run as administrator
    runas-admin $scriptName

    # verify and convert action to enum
    [ActionType] $currentAction = determine-action $action

    # if generateConfig then query logman for base line, pause, and query again for differences
    if($currentAction -eq [ActionType]::generateConfig)
    {
        # set to multisession to split output into named files instead of single-session
        $useSingleEtwSession = $false
        log-info "generating config xml files"
        generate-config
        return
    }
    
    if(![string]::IsNullOrEmpty($configurationFolder) -and [IO.Directory]::Exists($configurationFolder))
    {
        # verify config files are available
        $configurationFolder = verify-configFiles
    
        # delete previous singlesessionfile if it exists
        if($useSingleEtwSession)
        {
            $singleEtwSessionNameFile = "$($workingDir)\$($singleEtwSessionNameFile)"
 
            if([IO.File]::Exists($singleEtwSessionNameFile))
            {
                [IO.File]::Delete($singleEtwSessionNameFile);
            }
        }

        # enumerate config files
        $configurationFiles = [IO.Directory]::GetFiles($configurationFolder,"*.xml",[IO.SearchOption]::AllDirectories)
 
        # populate configurationFiles from configuration directory
        populate-configFiles -action $currentAction -configFiles $configurationFiles

    }
    elseif([string]::IsNullOrEmpty($configurationFile) -and ![IO.File]::Exists($configurationFile))
    {
        log-info "error: invalid arguments. need valid configurationFolder or configurationFile"
        return
    }

    # modify defaultEtlFolder if $traceFolder not default
    if($traceFolder.Contains(":"))
    {
        $defaultEtlFolder = [regex]::Replace($traceFolder , ":" , "$")
        log-info "Setting default etl folder to: $($defaultEtlFolder)"
    }
 
    # add local machine if empty
    if($machines.Count -lt 1)
    {
        $machines += $env:COMPUTERNAME
    }
    elseif($machines.Count -eq 1 -and $machines[0].Contains(","))
    {
        # when passing comma separated list of machines from bat, it does not get separated correctly
        $machines = $machines[0].Split(",")
    }
    elseif($machines.Count -eq 1 -and [IO.File]::Exists($machines))
    {
        # file passed in
        $machines = [IO.File]::ReadAllLines($machines);
    } 

    # determine and run commands
    if($useSingleEtwSession)
    {
        $configurationFiles = $singleEtwSessionNameFile
    }
 
    run-commands -currentAction $currentAction -configFiles $configurationFiles
 
    # perform any pending file copies
    [string[]] $resultFiles = copy-files $copyFiles
    
    log-info "finished"    
    
    if($currentAction -eq [ActionType]::undeploy -and [IO.Directory]::Exists($global:outputFolder))
    {
        tree /a /f $($global:outputFolder)
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function check-ProcessOutput([string] $output, [ActionType] $action, [bool] $shouldHaveSession = $false, [bool] $shouldNotHaveSession = $false)
{
    if($action -eq [ActionType]::deploy)
    {
        if($output -imatch "Data Collector Set already exists")
        {
            # this is ok
            #Write-Warning $output
            return $true
        }

        if($shouldHaveSession)
        {
            if($output -inotmatch $singleEtwSessionName)
            {
                log-info "error: $($singleEtwSessionName) does not exist!"
                return $false
            }
        }
    }
    elseif($action -eq [ActionType]::undeploy)
    {
        if($output -imatch "Data Collector Set was not found")
        {
            # this is not ok if trace was running. show warning
            Write-Warning $output
            return $true
        }

        if($shouldNotHaveSession)
        {
            if($output -imatch $singleEtwSessionName)
            {
                log-info "error: $($singleEtwSessionName) still exists!"
                return $false
            }
        }

    }

    if($output -imatch $singleEtwSessionName)
    {
        log-info "$($singleEtwSessionName) etw trace is started"
    }
    else
    {
        log-info "$($singleEtwSessionName) etw trace is not started"
    }


    if($output -imatch "error|fail|exception")
    {
        return $false
    }
    else
    {
        return $true
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function copy-files($files)
{
    $resultFiles = @()
 
    foreach($kvp in $files.GetEnumerator())
    {
        if($kvp -eq $null)
        {
            continue
        }
 
        $destinationFile = $kvp.Value
        $sourceFile = $kvp.Key
 
        if(!(Test-Path $sourceFile))
        {
            log-info "Warning:Copying File:No source. skipping:$($sourceFile)"
            continue
        }
 
        $count = 0
 
        while($count -lt 30)
        {
            try
            {
 
                if(is-fileLocked $sourceFile)
                {
                    start-sleep -Seconds 1
	               $count++          
				If($count -lt 30)          
				{
					Continue
				}
                }
                
                
                log-info "Copying File:$($sourceFile) to $($destinationFile)"
                [IO.File]::Copy($sourceFile, $destinationFile, $true)
            
                log-info "Deleting File:$($sourceFile)"
                [IO.File]::Delete($sourceFile)
 
                if($removeEmptyEtls)
                {
                    $fileInfo = new-object System.IO.FileInfo($destinationFile)
 
                    if($fileInfo.Length -le 8192)
                    {
                        log-info "Deleting Empty Etl:$($destinationFile)"
                        [IO.File]::Delete($destinationFile)
                        break
                    }
 
                }
 
                # add file if exists local to return array for further processing
                $resultFiles += $destinationFile
 
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
 
    switch($action.Trim().ToLower())
    {
        "deploy"
        {
            $at = [ActionType]::deploy
        }
 
        "undeploy"
        {
            $at = [ActionType]::undeploy
        }
    
        "generateConfig"
        {
            $at = [ActionType]::generateConfig
        }
        default
        {
            log-info "Unknown action:$($action): should be deploy or undeploy. exiting"
            exit
        }
 
    }
    
    return $at    
}

# ----------------------------------------------------------------------------------------------------------------
function generate-config()
{

    # get base traces before adding new ones to export
     $output = run-logman  "query -ets" -returnResults
     log-info $output

     $regexPattern = "\n(?<set>[a-zA-Z0-9-_ ]*)\s*(?<type>Trace)\s*(?<status>\w*)"
     $regex = New-Object Text.RegularExpressions.Regex ($regexPattern,[Text.RegularExpressions.RegexOptions]::Singleline)
     $result = $regex.Matches($output)

     $originalList = @{}
     for($i = 0; $i -lt $result.Count;$i++)
     {
        $loggerName = ($result[$i].Groups['set'].Value).Trim()
        $loggerStatus = ($result[$i].Groups['status'].Value).Trim()
        if(![String]::IsNullOrEmpty($loggerName))
        {
            $originalList.Add($loggerName,$loggerStatus)
        }
     }

     log-info "base trace information gathered. Add new logman sessions now."
     Read-Host 'Press Enter to continue...' | Out-Null

     # get new traces after adding new ones to export
     $output = run-logman  "query -ets" -returnResults
     log-info $output

     $result = $regex.Matches($output)

     $newList = @{}
     for($i = 0; $i -lt $result.Count;$i++)
     {
        $loggerName = ($result[$i].Groups['set'].Value).Trim()
        $loggerStatus = ($result[$i].Groups['status'].Value).Trim()
        
        if(![String]::IsNullOrEmpty($loggerName))
        {
            if(!$originalList.ContainsKey($loggerName))
            {
                $newList.Add($loggerName,$loggerStatus)
            }
        }
     }

     #export out only new logman sessions
     if($newList.Count -gt 0)
     {
         foreach($session in $newList.GetEnumerator())
         {
            $output = run-logman  "export `"$($session.Key)`" -ets -xml `"$($workingDir)\$($session.Key).xml`"" -returnResults
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
    if([string]::IsNullOrEmpty($data))
    {
        return
    }

    if($data.ToLower().Contains("error"))
    {
        $foregroundColor = "Red"
    }
    elseif($data.ToLower().Contains("fail"))
    {
        $foregroundColor = "Red"
    }
    elseif($data.ToLower().Contains("warning"))
    {
        $foregroundColor = "Yellow"
    }
    elseif($data.ToLower().Contains("exception"))
    {
        $foregroundColor = "Yellow"
    }
    elseif($data.ToLower().Contains("running process"))
    {
        $foregroundColor = "Cyan"
    }
    elseif($data.ToLower().Contains("success"))
    {
        $foregroundColor = "Green"
    }
    elseif($data.ToLower().Contains("is started"))
    {
        $foregroundColor = "Green"
    }
    elseif($data.ToLower().Contains("is not started"))
    {
        $foregroundColor = "Gray"
    }
    
    $data = "$([DateTime]::Now):$($data)`n"
    Write-Host $data -ForegroundColor $foregroundColor
    out-file -Append -InputObject $data -FilePath $logFile
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
    #CaptureStackTrace
 
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
 
    
    $wmi = new-object System.Management.ManagementClass "\\$($machine)\Root\default:StdRegProv" 
    
    foreach($valueName in $valueNames)
    {
        switch($currentAction)
        {
            ([ActionType]::deploy)
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
 
            ([ActionType]::undeploy)
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
                log-info "Unknown action:$($currentAction): should be deploy or undeploy. exiting"
                exit 1
            }
        }
    }
 
    return
 
}

# ----------------------------------------------------------------------------------------------------------------
function populate-configFiles([string[]] $configFiles)
{
    # modify settings in config files for environment
    foreach($file in $configFiles)
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
            
        if($useSingleEtwSession)
        {
            # create new single session file
            if(!([IO.File]::Exists($singleEtwSessionNameFile)))
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
 
                foreach($node in $xmlDoc.DocumentElement.TraceDataCollector.GetElementsByTagName("TraceDataProvider"))
                {
                    # check for dupes
                    foreach($t in $xmlDocSingle.DocumentElement.TraceDataCollector.GetElementsByTagName("Guid")) 
                    {
                        if((($t.'#text').ToString()) -imatch ($Node.Guid.ToString()))
                        {
                            #dupe
                            log-info "dupe guid:$($node.Guid)"
                            $dupe = $true
                            break
                        }
                    }
                        
                    if(!$dupe)
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
function runas-admin([string] $arguments)
{
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( `
        [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {   
       log-info "please restart script as administrator. exiting..."
       exit
    }
}

# ----------------------------------------------------------------------------------------------------------------
function run-commands([ActionType] $currentAction, [string[]] $configFiles)
{
    $machineFolder = [string]::Empty   
    $dirName = ([DateTime]::Now).ToString("yyyy-MM-dd-hh-mm-ss")
 
    foreach($machine in $machines)
    {
        
        $machine = $machine.Trim()
        if([String]::IsNullOrEmpty($machine))
        {
            continue
        }
 
        # add / remove rds debug registry settings
        if ($rds)
        {
            manage-rdsRegistry -currentAction $currentAction -machine $machine
        }
        
        if ($showDetail) 
        {
            run-logman  "query -ets -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::deploy) -shouldNotHaveSession ($currentAction -eq [ActionType]::undeploy)
        }
 
        # store files in computer folder or in root
        if($nodynamicpath)
        {
            $machineFolder = $global:outputFolder
        }
        elseif($useSingleEtwSession)
        {
            $machineFolder = $global:outputFolder = "$($global:defaultFolder)\$($dirName)"
        }
        else
        {
            $global:outputFolder = "$($global:defaultFolder)\$($dirName)"
            $machineFolder = "$($global:defaultFolder)\$($dirName)\$($machine)"            
        }
 
        if($permanent)
        {
            run-logman  "query autosession\* -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::undeploy) -shouldNotHaveSession ($currentAction -eq [ActionType]::deploy)
        }
        else
        {
            run-logman  "query -ets -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::undeploy) -shouldNotHaveSession ($currentAction -eq [ActionType]::deploy)
        }
            
 
        foreach($file in $configFiles)
        {
 
            $baseFileName = [IO.Path]::GetFileNameWithoutExtension($file)
 
            $fullLoggerName = $loggerName = "lmw-$($baseFileName)"
 
            if($permanent)
            {
                $fullLoggerName = "autosession\$($loggerName)"
            }
            
            $etlFileFolder = "\\$($machine)\$($defaultEtlFolder)"
            $etlFile = "$($etlFileFolder)\$($baseFileName).etl"
 
            switch($currentAction)
            {
                ([ActionType]::deploy) #"deploy"
                {
                    # make sure etl file does not already exist
                    
                    if(Test-Path $etlFile)
                    {
                        log-info "Deleting old etl file:$($etlFile)"
                        [IO.File]::Delete($etlFile)
                    }
 
                    # make sure etl dir exists
                    if(!(Test-Path $etlFileFolder))
                    {
                        [IO.Directory]::CreateDirectory($etlFileFolder)
                    }
 
                    # query to see if session already exists. it shouldnt if we are deploying
                    if ($showDetail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)"
                    }
 
                    # import configuration from xml file
                    if($permanent)
                    {
                        # will start next boot
                        run-logman  "import -n $($fullLoggerName) -s $($machine) -xml $($file)"
                    }
 
                    # will start now only for this boot
                    run-logman  "import -n $($loggerName) -ets -s $($machine) -xml $($file)"
 
                    run-logman  "start $($loggerName) -ets -s $($machine)"
                   
                    # query to see session status. session should be there and running
                    if ($showDetail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)" -shouldHaveSession $true
                    }
                }
 
                ([ActionType]::undeploy) #"undeploy"
                {
                    # query to see if session exists. session should exist if we are undeploying
                    if ($showDetail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)"
                    }
 
                    run-logman  "stop $($loggerName) -ets -s $($machine)"
                    
                    # delete session
                    if($permanent)
                    {
                        run-logman  "delete $($fullloggerName) -ets -s $($machine)"  
                    }
 
                    # query to verify session does not exist. session should be removed.
                    if ($showDetail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)" -shouldNotHaveSession $true
                    }
 
                    # verify etl local destination
                    if(!(Test-Path $machineFolder))
                    {
                        log-info "Creating Directory:$($machineFolder)"
                        [void][IO.Directory]::CreateDirectory($machineFolder)
                    }
 
                    # add etl files to list for copy back to local machine
                    if([IO.File]::Exists($etlFile))
                    {
                        $destFile = "$($machineFolder)\$($machine)-$([IO.Path]::GetFileName($etlFile))"
                        log-info "Adding file to be copied source: $($etlFile) dest: $($destFile)"
                        $copyFiles.Add($etlFile, $destFile);
                    }
                    else
                    {
                        log-info "error: $($etlFile) does NOT exist! you will need to troubleshoot and restart tracing!"
                    }
                }
 
                default
                {
                    log-info "Unknown action:$($currentAction): should be deploy or undeploy. exiting"
                    exit
                }
 
            }
        }
 
 
        if($permanent)
        {
            run-logman  "query autosession\* -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::deploy) -shouldNotHaveSession ($currentAction -eq [ActionType]::undeploy)
        }
        else
        {
            run-logman  "query -ets -s $($machine)" -shouldHaveSession ($currentAction -eq [ActionType]::deploy) -shouldNotHaveSession ($currentAction -eq [ActionType]::undeploy)
        }
    }
 
    return
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-logman([string] $arguments, [bool] $shouldHaveSession = $false, [bool] $shouldNotHaveSession = $false, [switch] $returnResults)
{
    $retval = run-process -processName $logman -arguments $arguments -wait $true
    
    if(!(check-processOutput -output $retval -action $currentAction -shouldHaveSession $shouldHaveSession -shouldNotHaveSession $shouldNotHaveSession) -and !$continue)
    {
        log-info "error in logman command. exiting. use -continue switch to ignore errors"
        log-info "error: $($retval)"
        exit 1
    }

    if($returnResults)
    {
        return $retval
    }
    else
    {
        return
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    log-info "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.WorkingDirectory = get-location
 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        [void]$process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        
        if($showDetail)
        {
            log-info "Process output:$stdOut"
        }
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            log-info "Error:$stdErr `n $Error"
            $Error.Clear()
            
            if(!$continue)
            {
                exit 1
            }
        }
    }
    elseif($wait)
    {
        log-info "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
function verify-configFiles()
{
    $retval
    log-info "Verifying config files"
 
    # if path starts with a '.' replace with working dir
    if($configurationFolder.StartsWith(".\"))
    {
        $configurationFolder = "$(get-location)$($configurationFolder.Substring(1))"
        $configurationFolder = $configurationFolder.Trim()
    }
 
    if([String]::IsNullOrEmpty($configurationFolder) -or !(Test-Path $configurationFolder))
    {
        log-info "logman configuration files not found:$($configurationFolder)"
        log-info "please specify logman configuration file (.xml) files location or add. exiting"
        exit
    }
    
    if(!(Test-Path $configurationFolder) -and (Test-Path $defaultTemplateConfigFolder))
    {
        $retval = [IO.Directory]::CreateDirectory($configurationFolder)
 
        if((Test-Path $configurationFolder) -and (Test-Path $defaultTemplateConfigFolder))
        {
            $retval = Copy-Item $defaultTemplateConfigFolder\* $configurationFolder
        }
        else
        {
            log-info "Config Files do not exist:exiting:" + $configurationFolder
            #return $false
            exit
        }
    }
 
    log-info "returning configuration folder:$($configurationFolder)"
 
    return ($configurationFolder).Trim()
}
 
# ----------------------------------------------------------------------------------------------------------------
function xml-reader([string] $file)
{
    if($showDetail) 
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
    

    if($showDetail)
    {
        log-info "Writing xml config file:$($file)"
    }
    
    $xdoc.Save($file)
}
 
# ----------------------------------------------------------------------------------------------------------------

main
