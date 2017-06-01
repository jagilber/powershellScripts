documention for zip and scripts is located in technet gallery

https://gallery.technet.microsoft.com/site/search?query=jagilber

https://gallery.technet.microsoft.com/ETW-and-Network-Remote-8e620f42
https://aka.ms/remote-tracing.zip

https://gallery.technet.microsoft.com/Remote-Desktop-RDS-ff5d5045?redir=0
https://aka.ms/rds-lic-svr.chk.ps1

https://gallery.technet.microsoft.com/Log-mergeps1-script-to-b1e595d7?redir=0
https://aka.ms/log-merge.ps1

https://gallery.technet.microsoft.com/Windows-Event-Log-ad958986?redir=0
https://aka.ms/event-log-manager.ps1

 
instructions on how to use: 
remote-tracing.zip has been uploaded to your workspace or is available here:
https://gallery.technet.microsoft.com/ETW-and-Network-Remote-8e620f42

Please download and extract to connection broker or server with issue.
NOTE: use in directory path without spaces
 
These scripts can be used to gather rds tracing both locally and remotely.
It is a powershell script and has help.
If you need assistance, please let me know.
 
Remote Desktop Services (RDS):
For RDS, either a bat or ps1 can be used:
	If doing local machine or 1 remote machine, you can use bat file:
	Remote-tracing.rds.bat start
	Remote-tracing.rds.bat stop
	Remote-tracing.rds.bat start 192.168.1.10
	Remote-tracing.rds.bat stop 192.168.1.10
	 
	Bat file uses this command:
		start /wait powershell.exe -Executionpolicy unrestricted -file remote-tracing.ps1 -action start -configurationFolder %configFolder% -rds –machines %machines%
	 
	If wanting to use other switches or do multiple machines, then call script directly from admin powershell prompt
	Help remote-tracing.ps1 –full for arguments
	 
	Example to start tracing: .\remote-tracing.ps1 -network -action start -configurationFolder .\remoteDesktopServicesConfig -rds –machines 192.168.1.10,192.168.1.11
	Example to stop tracing: .\remote-tracing.ps1 -network -action stop -configurationFolder .\remoteDesktopServicesConfig -rds –machines 192.168.1.10,192.168.1.11
 
Remote Desktop Virtualization (RDV):
Only .ps1 can be used
Example to start tracing: .\remote-tracing.ps1 -network -action start -configurationFolder .\remoteDesktopVirtualizationConfig -rds –machines 192.168.1.10,192.168.1.11
Example to stop tracing: .\remote-tracing.ps1 -network -action stop -configurationFolder .\remoteDesktopVirtualizationConfig -rds –machines 192.168.1.10,192.168.1.11
 
Event Logs:
To collect eventlogs from local or remote machines, use the following command:
Example to collect event logs from the last 60 minutes from RDS event logs:
 .\event-log-manager.ps1 -rds -minutes 60 –machines 192.168.1.10,192.168.1.11
 
Command line network traces:
To start network:
netsh trace start capture=yes overwrite=yes maxsize=1024 tracefile=c:\net.etl filemode=circular
 
To stop network:
netsh trace stop
 
When stopping tracing, output files will be copied from remote machines to a folder named ‘gather’ in the same directory as the powershell script remote-tracing.ps1. The gather folder should contain one .etl file for each machine being traced. Network trace will be on root of c:\net.etl and c:\net.cab.
 
Please zip and upload 'gather' folder when complete.


This script is used by Microsoft Support to manage Event Tracing for Windows (ETW) and network tracing. Remote Desktop Services (RDS). remote-tracing.ps1 can be run from any OS greater or equal to Windows 8 / 2012.
It can be used for any ETW module but is configured for RDS and RDV. The script will manage local or remote machines but does require both and Administrative access to the OS and an Administrative PowerShell prompt.
If using remotely, WMI, RPC, SMB (UNC) protocols are used and need to be open.

To create a new / custom configuration with different ETW modules:
- identify the ETW modules needed for tracing (logman.exe query providers lists many of them)
- start script with .\remote-tracing.ps1 -action generateConfig
- script will pause while changes are made using logman or in perfmon gui
- once all changes are made, continue script
- script will export all changes found in logman into new xml configuration files
- these files can be added to a new configurationFolder directory
- specify new configuration folder to use new ETW modules from the xml config files

NOTE: PowerShell scripts require that the execution of scripts be enabled on the machine, current PowerShell session, or by starting PowerShell.exe with '-ExecutionPolicy' switch. To query current execution settings, type 'Get-ExecutionPolicy'. To enable script execution, from admin PowerShell prompt, type 'Set-ExecutionPolicy RemoteSigned -Force' or 'Set-ExecutionPolicy Bypass -Force'. The prior example shows two commonly used policy levels with 'RemoteSigned' being more restrictive than 'Bypass' (additional policy levels available). When finished running script, you can set the policy level back to the prior setting if needed. For additional information type 'help set-executionpolicy -online'.
NOTE: Scripts downloaded from technet may be blocked by default depending on type of download and configuration. If script fails to execute, right click on file and verify that if 'Unblock' exists, it is unchecked.
PS C:\temp\remote-tracing> help .\remote-tracing.ps1 -Full

NAME
    C:\temp\remote-tracing\remote-tracing.ps1
    
SYNOPSIS
    powershell script to manage logman ETW tracing and network tracing both locally and remotely
    
    
SYNTAX
    C:\temp\remote-tracing\remote-tracing.ps1 [-action] <String> [[-configurationFile] <String>] [[-configurationFolder] <String>] [-continue] [[-machines] <String[]>] [-network] [-noretry] [-nodynamicpath] [[-outputFolder] <String>] [-permanent] [-rds] 
    [-showDetail] [[-traceFolder] <String>] [[-useSingleEtwSession] <Boolean>] [<CommonParameters>]
    
    
DESCRIPTION
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
    

PARAMETERS
    -action <String>
        The action to take. Currently this is 'start','stop','generateConfig'. start will enable logman ETW sessions on specified computer(s). stop will disable logman ETW sessions on specified computer(s).
        GenerateConfig, will query logman for currently running traces for baseline, pause for new logman / etw traces to be added, on resume will query logman again
            for differences. the differences will be exported out by session to an xml file for each session. these xml files can then be added to the configurationFolder
            for future use.
        Required?                    true
        
    -configurationFile <String>
        configuration file or configuration folder need to specified. configuration file should contain xml format of ETW providers to trace. to create xml files, use '-action generateConfig'
        by default the file name is single-session.xml

    -configurationFolder <String>
        configuration file or configuration folder need to specified. configuration folder should contain xml format of files of ETW providers to trace. to create xml files, use '-action generateConfig'
        
    -continue [<SwitchParameter>]
        if specified, will continue on error
        Default value                False

    -machines <String[]>
        the machine(s) to perform action on. If not specified, the local machine is used. Multiple machines should be separated by comma ',' with no spaces in between. A file name and path with list of machines can be specified.
        
    -network [<SwitchParameter>]
        if specified, will capture a network trace
        Default value                False

    -nodynamicpath [<SwitchParameter>]
        if specified, will override default output structure to make it flat
        Default value                False

    -outputFolder <String>
        if specified, will override default output folder of .\gather
        Default value                .\gather

    -permanent [<SwitchParameter>]
        if specified, will add the ETW session permanently to the target machine(s) (autosession). To remove from machine(s) use action stop.
        Default value                False

    -rds [<SwitchParameter>]
        if specified, will configure tracing for a rdsh/rdvh environment.
        Default value                False

    -showDetail [<SwitchParameter>]
        if specified, will show additional logging in console output
        Default value                False
        
    -traceFolder <String>
        if specified will use custom location for etl output. by default this is %systemroot%\temp
        Default value                [Environment]::GetEnvironmentVariables("Machine").TMP
        
    -useSingleEtwSession <Boolean>
        Default value                True
        
NOTES
        File Name  : remote-tracing.ps1  
        Author     : jagilber
        Version    : 170506 renamed and added netsh
        
        History    : 
                     170220 added -configurationFile and modified -machines to use file and -continue to continue on errors and -showDetial. cleaned output
                     160902 added -nodynamicpath for when being called from another script to centralize all files in common folder
                     160519 added switch verifier
    
-------------------------- EXAMPLE 1 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig
    deploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" to local machine
    
    -------------------------- EXAMPLE 2 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig -network
    deploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" and start network tracing on local machine
    
    -------------------------- EXAMPLE 3 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start
    deploy ETW configuration file "single-session.xml" (generated after first start action) to local machine
	
    -------------------------- EXAMPLE 4 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -network
    start network tracing on local machine
    
    -------------------------- EXAMPLE 5 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -network -machines 192.168.1.1,192.168.1.2
    start network tracing on machines machines 192.168.1.1 and 192.168.1.2
    
    -------------------------- EXAMPLE 6 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -machines 192.168.1.1,192.168.1.2
    deploy ETW configuration file "single-session.xml" (generated after first start action) to machines 192.168.1.1 and 192.168.1.2
    
    -------------------------- EXAMPLE 7 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -network -machines 192.168.1.1,192.168.1.2
    deploy network tracing to machines 192.168.1.1 and 192.168.1.2
    
    -------------------------- EXAMPLE 8 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -configurationFile single-session.xml -network -machines 192.168.1.1,192.168.1.2
    deploy ETW configuration file "single-session.xml" (generated after first start action) and network tracing to machines 192.168.1.1 and 192.168.1.2
    
    -------------------------- EXAMPLE 9 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -machines 192.168.1.1,192.168.1.2 -permanent $true -configurationFolder .\remoteDesktopServicesConfig
    deploy all ETW configuration files in configurationFolder ".\remoteDesktopServicesConfig" to machines 192.168.1.1 and 192.168.1.2 permanently (across reboots)
    
    -------------------------- EXAMPLE 10 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop
    undeploy ETW configuration file "single-session.xml" (generated after first start action) from local machine using default etl output folder ".\gather"
    
    -------------------------- EXAMPLE 11 --------------------------
    PS C:\>.\remote-tracing.ps1 -action start -configurationFolder .\remoteDesktopServicesConfig -network
    undeploy ETW configuration file "single-session.xml" generated from configurationFolder ".\remoteDesktopServicesConfig" and stop network tracing on local machine
    
    -------------------------- EXAMPLE 12 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -network
    stop network tracing on local machine
    
    -------------------------- EXAMPLE 13 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -network -machines 192.168.1.1,192.168.1.2
    stop network tracing on machines machines 192.168.1.1 and 192.168.1.2
    
    -------------------------- EXAMPLE 14 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -machines 192.168.1.1,192.168.1.2
    undeploy ETW configuration file "single-session.xml" (generated after first start action) from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"
    
    -------------------------- EXAMPLE 15 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -machines 192.168.1.1,192.168.1.2 -traceFolder c:\temp -configurationFolder .\remoteDesktopServicesConfig
    undeploy all ETW configuration files in configurationFolder ".\remoteDesktopServicesConfig" from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"
    
    -------------------------- EXAMPLE 16 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -network -machines 192.168.1.1,192.168.1.2
    undeploy network tracing from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"
    
    -------------------------- EXAMPLE 17 --------------------------
    PS C:\>.\remote-tracing.ps1 -action stop -configurationFile single-session.xml -network -machines 192.168.1.1,192.168.1.2
    undeploy ETW configuration file "single-session.xml" (generated after first start action) and network tracing from machines 192.168.1.1 and 192.168.1.2 using default etl output folder ".\gather"
	
Reference:
Github script repository for this script   
https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/remote-tracing.ps1