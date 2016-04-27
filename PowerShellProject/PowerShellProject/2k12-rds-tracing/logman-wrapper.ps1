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
   Version    : 160101
   History    : changed gather directory to time\machine. 
                changed rds and permanent to switches.
                added generateConfig to create new logman config xml files
             removed etl processor. Increased run-process waittimeout
			 added working dir to start process
			 added check for etl file being in use.
                added option to use single etw session (default)

.EXAMPLE  
    .\logmanwrapper.ps1 -action deploy
    deploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action deploy -machines 192.168.1.1,192.168.1.2 
    deploy all configuration files in default 'configs' or 'configs_templates' folder to machines 192.168.1.1 and 192.168.1.2 using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action deploy -machines 192.168.1.1,192.168.1.2 -outputFolder c:\temp -permanent $true -configurationFolder c:\temp\configs 
    deploy all configuration files in c:\temp\configs folder to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots). etl output folder is c:\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy
    undeploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy -machines 192.168.1.1,192.168.1.2
    undeploy all configuration files in default 'configs' or 'configs_templates' folder to machines 192.168.1.1 and 192.168.1.2 using defalut etl output folder of %systemroot%\temp
.EXAMPLE
    .\logmanwrapper.ps1 -action undeploy -machines 192.168.1.1,192.168.1.2 -outputFolder c:\temp -permanent -configurationFolder c:\temp\configs
    undeploy all configuration files in c:\temp\configs folder to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots). etl output folder is c:\temp

.PARAMETER action
    The action to take. Currently this is 'deploy','undeploy','generateConfig'. Deploy will enable logman ETW sessions on specified computer(s). Undeploy will disable logman ETW sessions on specified computer(s).
    GenerateConfig, will query logman for currently running traces for baseline, pause for new logman / etw traces to be added, on resume will query logman again
        for differences. the differences will be exported out by session to an xml file for each session. these xml files can then be added to the configurationFolder
        for future use.

.PARAMETER machines
    The machine(s) to perform action on. If not specified, the local machine is used. Multiple machines should be separated by comma ',' with no spaces in between.
.PARAMETER outputFolder
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
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the action to take: [deploy|undeploy|generateConfig]")]
    [string] $action,
    [parameter(Position=1)]
    [string[]] $machines,
    [parameter(Position=2)]
    [string] $outputFolder = "%systemroot%\temp", 
    [parameter(Position=3,HelpMessage="Specify to enable tracing across reboots.")]
    [switch] $permanent,
    [parameter(Position=4)]
    [string] $configurationFolder = "configs",
    [parameter(Position=5,HelpMessage="Specify to enable tracing for Remote Desktop Services.")]
    [switch] $rds
  
    )
 
 
 
# modify
$defaultEtlFolder = "admin$\temp"
$defaultGatherFolder = "gather"
$gatherFolderFlat = $false
$useSingleEtwSession = $true
$singleEtwSessionName = "single-session"
$singleEtwSessionNameFile = "$($singleEtwSessionName).xml"
$logFile = "logman-Wrapper.log"
$logman = "logman.exe"
$removeEmptyEtls = $true
$detail = $false
 
[string] $logAppend = 0 #true -1 only 1 of these 3 can be true
[string] $logOverwrite = 0 #true -1 only 1 of these 3 can be true
[string] $logCircular = -1 #true -1 only 1 of these 3 can be true
[string] $bufferSizeKB = 20
[string] $minBuffersKB = 40
[string] $maxBuffersKB = 80
[string] $etlFileSizeMB = 500
 
# dont modify
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
 
# ----------------------------------------------------------------------------------------------------------------
function main()
{
    log-info "============================================="
    log-info "Starting"
  
    $retval
 
    $workingDir = get-workingDirectory
 
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
 
    # modify defaultEtlFolder if $outputFolder not default
    if($outputFolder.Contains(":"))
    {
        $defaultEtlFolder = [regex]::Replace($outputFolder , ":" , "$")
        log-info "Setting default etl folder to: $($defaultEtlFolder)"
    }
 
    # add local machine if empty
    if($machines.Count -lt 1)
    {
        $machines += $env:COMPUTERNAME
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
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-commands([ActionType] $currentAction, [string[]] $configFiles)
{
    
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
        
        if ($detail) 
        {
            run-logman  "query -ets -s $($machine)"
        }
 
        # store files in computer folder or in root
        if($gatherFolderFlat)
        {
            $gatherFolder = "$(get-location)\$($defaultGatherFolder)\$($dirName)"
        }
        else
        {
            $gatherFolder = "$(get-location)\$($defaultGatherFolder)\$($dirName)\$($machine)"            
        }
 
        if($permanent)
        {
            run-logman  "query autosession\* -s $($machine)"
        }
        else
        {
            run-logman  "query -ets -s $($machine)"
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
                    if ($detail) 
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
                    if ($detail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)"
                    }
                }
 
                ([ActionType]::undeploy) #"undeploy"
                {
                    # query to see if session exists. session should exist if we are undeploying
                    if ($detail) 
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
                    if ($detail) 
                    {
                        run-logman  "query $($fullLoggerName) -ets -s $($machine)"
                    }
 
                    # verify etl local destination
                    if(!(Test-Path $gatherFolder))
                    {
                        log-info "Creating Directory:$($gatherFolder)"
                        [IO.Directory]::CreateDirectory($gatherFolder)
                    }
 
                    # add etl files to list for copy back to local machine
                    if([IO.File]::Exists($etlFile))
                    {
                        $destFile = "$($gatherFolder)\$($machine)-$([IO.Path]::GetFileName($etlFile))"
                        log-info "Adding file to be copied source: $($etlFile) dest: $($destFile)"
                        $copyFiles.Add($etlFile, $destFile);
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
            run-logman  "query autosession\* -s $($machine)"
        }
        else
        {
            run-logman  "query -ets -s $($machine)"
        }
    }
 
    return
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
function populate-configFiles([string[]] $configFiles)
{
    # modify settings in config files for environment
    foreach($file in $configFiles)
    {
        [xml.xmldocument] $xmlDoc = xml-reader $file
 
 
        $xmlDoc.DocumentElement.RootPath = $outputFolder 
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
 
 
# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $data = "$([DateTime]::Now):$($data)`n"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}
 
# ----------------------------------------------------------------------------------------------------------------
function run-logman([string] $arguments)
{
    return run-process -processName $logman -arguments $arguments -wait $true
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
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        log-info "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            log-info "Error:$stdErr `n $Error"
            $Error.Clear()
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
    if($detail) 
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
    

    if($detail)
    {
        log-info "Writing xml config file:$($file)"
    }
    
    $xdoc.Save($file)
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
                log-info 
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
                exit
            }
        }
    }
 
    return $ret
 
}


# ----------------------------------------------------------------------------------------------------------------
function generate-config()
{

    # get base traces before adding new ones to export
     $output = run-logman  "query -ets"
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
     $output = run-logman  "query -ets"
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
            $output = run-logman  "export `"$($session.Key)`" -ets -xml `"$($workingDir)\$($session.Key).xml`""
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

main
 

