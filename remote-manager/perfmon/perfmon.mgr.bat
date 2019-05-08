@echo off

Set operation=unknown
Set allOperations=false
Set outputDir=c:\windows\temp\remoteManager
Set remoteoutputDir=c$\Perflogs

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

IF NOT "%2" == "" (
	Set machine= -s %2
) ELSE (
	Set machine=
)

IF %operation%==start (
	Echo -------------------------------------
	Echo starting Perfmon
	
	rem long perf
	Echo Logman.exe create counter PerfLog-Long%machine% -o "%outputDir%\%2PerfLog-Long.blg" -f bincirc -v mmddhhmm -max 300 -c "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Exceptions(*)\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" -si 00:05:00
	Logman.exe create counter PerfLog-Long%machine% -o "%outputDir%\%2PerfLog-Long.blg" -f bincirc -v mmddhhmm -max 300 -c "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Exceptions(*)\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" -si 00:05:00

	rem short perf
	Echo Logman.exe create counter PerfLog-Short%machine% -o "%outputDir%\%2PerfLog-Short.blg" -f bincirc -v mmddhhmm -max 300 -c "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Exceptions(*)\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" -si 00:00:03
	Logman.exe create counter PerfLog-Short%machine% -o "%outputDir%\%2PerfLog-Short.blg" -f bincirc -v mmddhhmm -max 300 -c "\LogicalDisk(*)\*" "\Memory\*" "\.NET CLR Exceptions(*)\*" "\.NET CLR Memory(*)\*" "\Cache\*" "\Network Interface(*)\*" "\Netlogon(*)\*" "\Paging File(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Processor Information(*)\*" "\Process(*)\*" "\Server\*" "\System\*" "\Server Work Queues(*)\*" -si 00:00:03

	
	Echo Logman.exe start PerfLog-Long%machine%
	Logman.exe start PerfLog-Long%machine%
	
	Echo Logman.exe start PerfLog-Short%machine%
	Logman.exe start PerfLog-Short%machine%

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
	
	Echo Logman.exe stop PerfLog-Long%machine%
	Logman.exe stop PerfLog-Long%machine%
	
	Echo Logman.exe stop PerfLog-Short%machine%
	Logman.exe stop PerfLog-Short%machine%
	
	IF NOT "%2" == "" (
		echo moving logs
		Echo move \\%2\%remoteoutputDir%\%2perflog-Long*.blg %outputdir%
		move \\%2\%remoteoutputDir%\%2perflog-Short*.blg %outputdir%
		Echo move \\%2\%remoteoutputDir%\%2perflog-Long*.blg %outputdir%
		move \\%2\%remoteoutputDir%\%2perflog-Short*.blg %outputdir%
	)

	Echo -------------------------------------
	Echo Gather the following logs from: %outputDir%
	Echo -------------------------------------
		dir %outputDir%\%2perflog-*.blg /b
	Echo -------------------------------------
	Goto finish
)

:error
Echo script is used to start and stop long and short perfmon tracing
Echo  no arguments will start perfmon
Echo   pause for repro, then will stop procmon.
Echo  argument 1 can be ?, /?, -?, start, stop
Echo  argument 2 can be name of machine to monitor remotely
Echo   if using remotely with argument 2, then start or stop must be used for argument 1

Echo exiting...

:finish

Echo finished
Echo -------------------------------------
