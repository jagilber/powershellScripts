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
	Echo starting RDGateway NPS / NAP / LOGON tracing
	
	Nltest /DBFlag:2080FFFF
	
	netsh nps set tracing *=verbose
	netsh nap client set tracing state=enable
	netsh ras set tracing * enabled
 
	Echo tracing started:
 
	IF %allOperations%==true (
		echo -------------------------------------
		Echo rdgateway tracing has started. Pausing here to reproduce issue. 
		Echo After issue is reproduced,
		Pause
		
		Set operation=stop
	) ELSE (
		Goto finish
	)
	
)

IF %operation%==stop (
	Echo -------------------------------------
	Echo stopping RDGateway NPS / NAP / LOGON tracing
	
	netsh nps set tracing *=none
	netsh nap client set tracing state=disable
	netsh ras set tracing * disabled

	Nltest /DBFlag:0x0

	Echo tracing has stopped.	
	Echo gather files from c:\windows\debug and c:\windows\tracing	
	Goto finish
)

:error
Echo script is used to start and stop RDGateway tracing
Echo  no arguments will start tracing
Echo   pause for repro, then will stop tracing.
Echo  argument 1 can be ?, /?, -?, start, stop

Echo exiting...

:finish

Echo finished
Echo -------------------------------------

