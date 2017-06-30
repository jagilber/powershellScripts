@echo off

Set operation=unknown
Set allOperations=false
Set outputDir=c:\windows\temp

Rem help, start, or stop
IF NOT "%1" == "" (
	IF "%1" == "?" (
		Goto error
	)
	IF "%1" == "/?" (
		Goto error
	)
	IF "%1" == "-?" (
		Goto error
	)
	IF "%1" == "start" (
		Set operation=%1
	)
	IF "%1" == "stop" (
		Set operation=%1
	)
	
) ELSE (
	Set operation=start
	Set allOperations=true
)


IF %operation%==start (
	Echo -------------------------------------
	Echo starting Perfmon
	
	rem long with print server
	Echo Logman.exe create counter PerfLog-Long -o "%outputDir%\PerfLog-Long.blg" -f bincirc -v mmddhhmm -max 300 -c "\Print Queue(*)\*" "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Redirector\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" "\Terminal Services\*" -si 00:05:00
	Logman.exe create counter PerfLog-Long -o "%outputDir%\PerfLog-Long.blg" -f bincirc -v mmddhhmm -max 300 -c "\Print Queue(*)\*" "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Redirector\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" "\Terminal Services\*" -si 00:05:00

	rem short with print server
	Echo Logman.exe create counter PerfLog-Short -o "%outputDir%\PerfLog-Short.blg" -f bincirc -v mmddhhmm -max 300 -c "\Print Queue(*)\*" "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Thread(*)\*" "\Redirector\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" "\Terminal Services\*" -si 00:00:03
	Logman.exe create counter PerfLog-Short -o "%outputDir%\PerfLog-Short.blg" -f bincirc -v mmddhhmm -max 300 -c "\Print Queue(*)\*" "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Thread(*)\*" "\Redirector\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" "\Terminal Services\*" -si 00:00:03

	
	Echo Logman.exe start PerfLog-Long
	Logman.exe start PerfLog-Long
	
	Echo Logman.exe start PerfLog-Short
	Logman.exe start PerfLog-Short

	Echo Note: These data collector sets will need to be started again if the server is rebooted as they do not automatically restart on boot.

	IF %allOperations%==true (
		echo -------------------------------------
		Echo perfmon has started. Pausing here to reproduce issue. 
		Echo After issue is reproduced,
		Pause
		
		Set operation=stop
	) ELSE (
		Goto finish
	)
	
)

IF %operation%==stop (
	Echo -------------------------------------
	Echo stopping Perfmon
	
	Echo Logman.exe stop PerfLog-Long
	Logman.exe stop PerfLog-Long
	
	Echo Logman.exe stop PerfLog-Short
	Logman.exe stop PerfLog-Short
	
	Echo Gather the following logs:
	Echo   %outputDir%\perflog-Long.blg
	Echo   %outputDir%\perflog-Short.blg
	
	Goto finish
)

:error
Echo script is used to start and stop long and short perfmon tracing
Echo  no arguments will start perfmon
Echo   pause for repro, then will stop procmon.
Echo  argument 1 can be ?, /?, -?, start, stop

Echo exiting...

:finish

Echo finished
Echo -------------------------------------

