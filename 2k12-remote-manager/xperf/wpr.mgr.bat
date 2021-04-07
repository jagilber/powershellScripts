@echo off
cls
set errorlevel=0
Set operation=unknown
Set allOperations=false
set xperfCmd=xperf.exe
set xbootCmd=xbootmgr.exe
set result=
Set xperfType=highcpu
Set outputfile=%cd%\xperf.etl
Set useroutputfile=%cd%\user.etl
set mergedFile=%cd%\merged.etl
set configFolder=%cd%
set logFile=%cd%\xperf.mgr.bat.log

echo ----------------------------- >> %logFile%
echo starting >> %logFile%
time /t >> %logFile%
echo outputfile=%outputfile% >> %logFile%
echo configFolder=%configFolder% >> %logFile%
echo firstArg=%1 >> %logFile%
echo secondArg=%2 >> %logFile%
echo thirdArg=%3 >> %logFile%

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
	IF "%1" == "slowlogon" (
		Echo setting xperf for slow logon
		Set xperfType=slowlogon
		Set operation=start
		Set allOperations=true
	)
	IF "%1" == "highcpu" (
		Echo setting xperf for high cpu
		Set xperfType=highcpu
		Set operation=start
		Set allOperations=true
	)
	IF "%1" == "wait" (
		Echo setting xperf for wait
		Set xperfType=wait
		Set operation=start
		Set allOperations=true
	)
	IF "%1" == "clean" (
		Echo setting operation to clean
		Set operation=clean
	)
	IF "%1" == "set" (
		Echo setting operation to set
		Set operation=set
	)
	IF "%1" == "rebootcycle" (
		Echo setting operation to rebootcycle
		Set xperfType=rebootcycle
		Set operation=start
	)
) ELSE (
	Set operation=start
	Set allOperations=true
)

IF NOT "%2" == "" (
	IF "%2" == "slowlogon" (
		Echo setting xperf for slow logon
		Set xperfType=slowlogon
	)
	IF "%2" == "highcpu" (
		Echo setting xperf for high cpu
		Set xperfType=highcpu
	)
	IF "%2" == "wait" (
		Echo setting xperf for wait
		Set xperfType=wait
	)
)

IF %operation%==start (
	Echo -------------------------------------

	IF "%xperfType%" == "slowlogon" (	
		rem high cpu
		echo not implemented
		
		echo errorlevel:%errorlevel% >> %logFile%
	)

	IF "%xperfType%" == "highcpu" (	
		rem high cpu
		rem starting wpr.exe -start CPU -start DiskIO -start FileIO -start Network -start Handle -start HTMLActivity -start HTMLResponsiveness -start DotNET -filemode -recordtempto c:\windows\temp\remoteManager\xperf
		wpr.exe -start CPU -start DiskIO -start FileIO -start Network -start Handle -start HTMLActivity -start HTMLResponsiveness -start DotNET -filemode -recordtempto %cd%
		
		echo errorlevel:%errorlevel% >> %logFile%
	)

	IF "%xperfType%" == "wait" (		
		rem wait analysis
		echo not implemented

		echo errorlevel:%errorlevel% >> %logFile%
	)

	IF "%xperfType%" == "rebootcycle" (		
		rem reboot cycle
		echo not implemented

		echo errorlevel:%errorlevel% >> %logFile%
		Echo Server will now reboot
	)

	IF %allOperations%==true (
		echo -------------------------------------
		Echo xperf has started. Pausing here to reproduce issue. 
		Echo Only run for as long as necessary as tracing can be intensive.
		Echo After issue is reproduced,
		Pause
		
		Set operation=stop
	) ELSE (
		echo -------------------------------------
		Echo xperf has started. 
		Echo Only run for as long as necessary as tracing can be intensive.

		Goto finish
	)
)

IF %operation%==stop (
	Echo -------------------------------------
	Echo stopping xperf
	
	IF "%xperfType%" == "slowlogon" (	
		echo not implemented
		echo errorlevel:%errorlevel% >> %logFile%
	) ELSE (
		Echo wpr.exe -stop %outputfile% remotewpr >> %logFile%
		wpr.exe -stop %outputfile% remotewpr >> %logFile%
		
		echo errorlevel:%errorlevel% >> %logFile%
	)

	Echo Gather the following logs:
	Echo %outputfile%
	
	Goto finish
)

IF %operation%==set (
	Echo -------------------------------------
	Echo adding registry entry
	Echo reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 1 /f
	reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 1 /f
	Goto finish
)

IF %operation%==clean (
	Echo -------------------------------------
	Echo removing registry entry
	Echo reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 0 /f
	reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 0 /f
	Goto finish
)

:error
Echo Script is used to start and stop xperf tracing
Echo Only run for as long as necessary as tracing can be intensive.
Echo  - no arguments will start xperf
Echo     pause for repro, then will stop xperf.
Echo  - argument 1 can be ?, /?, -?, start, stop, clean, set, slowlogon, or rebootcycle
Echo 		- clean will set DisablePagingExecutive back to 0 'normal'
Echo  - argument 2 can be highcpu, slowlogon, wait. If not specified highcpu will be used
Echo ******************************************************

rem check for disablepagingexecutive
reg.exe query "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v DisablePagingExecutive /t REG_DWORD | find  "0x1" > nul

IF "%errorlevel%" == "0" (
	Echo DisablePagingExecutive is set to 1
	goto finish
)

Echo DisablePagingExecutive is set to 0
Echo This has to be set before using xperf and does require a reboot before using xperf.

set /P result=Do you want to set DisablePagingExecutive to 1 ^(a reboot will be required before tracing^)^? [yes^|no] 
IF "%result%" == "yes" (
	Echo reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 1 /f
	reg add "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management"  /v DisablePagingExecutive /t REG_DWORD /d 1 /f
)
	

:finish
set result=
Echo finished
Echo -------------------------------------

echo finished >> %logFile%
echo error: %errorlevel% >> %logFile%
time /t >> %logFile%
