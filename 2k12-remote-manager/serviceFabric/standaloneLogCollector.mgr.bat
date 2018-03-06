rem StandaloneLogCollector.exe -output g:\temp\sac1 -scope cluster -mode collect -startutctime "01/27/2017 22:00:00" -endutctime "01/27/2017 23:00:00"


@echo off
Set operation=unknown
Set allOperations=false
Set outputDir=c:\windows\temp\sac
set startutctime="02/26/2018 22:00:00"
set endutctime="02/27/2018 22:00:00"

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
    set startutctime=%2
)

IF NOT "%3" == "" (
    set endutctime=%3
)


IF %operation%==start (
	Echo -------------------------------------
	Echo starting StandaloneLogCollector.exe
	
	rd /s /q %outputDir%
	start /wait StandaloneLogCollector.exe -output %outputDir% -scope node -mode collect -startutctime %startutctime% -endutctime %endutctime% -accepteula
 
	IF %allOperations%==true (
		echo gathering logs...		
		Set operation=stop
	) ELSE (
		Goto finish
	)
	
)

IF %operation%==stop (
	taskkill /IM StandaloneLogCollector.exe /F
	Goto finish
)

:error
Echo script is used to start and stop StandaloneLogCollector.exe
Echo  no arguments will start StandaloneLogCollector.exe
Echo  argument 1 can be ?, /?, -?, start, stop

Echo exiting...

:finish

Echo finished
Echo -------------------------------------
