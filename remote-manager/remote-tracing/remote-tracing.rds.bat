@echo off
rem 150712
rem to run in a task hidden add this to powershell command  -WindowStyle Hidden -NonInteractive 
rem arg1 is start or stop
rem arg2 optional machine name to start or stop
set configFolder=
set configFolder2k8=2k8r2-configs-all-rds
set configFolder2k12=remoteDesktopServicesConfig
set machine=

Set operation=unknown
Set allOperations=false

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

IF NOT "%2"=="" (
	set machine=-machines %2
) ELSE (
	set machine=
)

rem check for config folder
IF EXIST %configFolder2k8% (
	set configFolder=%configFolder2k8%
)
IF EXIST %configFolder2k12% (
	set configFolder=%configFolder2k12%
)
IF "%configFolder%"=="" (
	Echo configuration folder missing
	Echo %configFolder2k8% or %configFolder2k12% should exist
	goto error
)

IF %operation%==start (
	rem *********************************
	rem place all utilities to start here	
	rem *********************************

	Echo start /wait powershell.exe -Executionpolicy unrestricted -file remote-tracing.ps1 -network -action start -configurationFolder .\%configFolder% -rds %machine%
	start /wait powershell.exe -Executionpolicy unrestricted -file remote-tracing.ps1 -network -action start -configurationFolder .\%configFolder% -rds %machine%


	IF %allOperations%==true (
		echo -------------------------------------
		Echo All utilities have started. Pausing here to reproduce issue. 
		Echo After issue is reproduced,
		Pause
		Set operation=stop
	) ELSE (
		Goto finish
	)
)

IF %operation%==stop (
	rem *********************************	
	rem place all utilities to stop here	
	rem *********************************

	Echo start /wait powershell.exe -Executionpolicy unrestricted -file remote-tracing.ps1 -network -action stop -configurationFolder .\%configFolder% -rds %machine%
	start /wait powershell.exe -Executionpolicy unrestricted -file remote-tracing.ps1 -network -action stop -configurationFolder .\%configFolder% -rds %machine%

	goto finish
)

:error
Echo script is used to start and stop etw tracing
Echo arguments are:
Echo  no arguments will start utilities
Echo   pause for repro, then will stop utilities.
Echo  argument 1 can be ?, /?, -?, start, stop
Echo  argument 2 can be a single machine name

Echo exiting...

:finish

Echo finished
Echo -------------------------------------


