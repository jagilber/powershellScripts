@echo off
cls
Set operation=unknown
Set allOperations=false
set xperfCmd=xperf.exe
set xbootCmd=xbootmgr.exe
set result=
Set xperfType=highcpu
Set outputfile=%systemroot%\temp\xperf.etl
set configFolder=
set configFolderx64=%systemroot%\temp\WPR-8.1-x64
set configFolderx86=%systemroot%\temp\WPR-8.1-x86


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
		Set outputfile=%systemroot%\temp\xperf.etl
		Set operation=start
		Set allOperations=true
	)
	IF "%1" == "highcpu" (
		Echo setting xperf for high cpu
		Set xperfType=highcpu
		Set outputfile=%systemroot%\temp\xphighcpu.etl
		Set operation=start
		Set allOperations=true
	)
	IF "%1" == "wait" (
		Echo setting xperf for wait
		Set xperfType=wait
		Set outputfile=%systemroot%\temp\xpwait.etl
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
		Set outputfile=%systemroot%\temp\xpreboot.etl
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
		Set outputfile=%systemroot%\temp\xperf.etl

	)
	IF "%2" == "highcpu" (
		Echo setting xperf for high cpu
		Set xperfType=highcpu
		Set outputfile=%systemroot%\temp\xphighcpu.etl
	)
	IF "%2" == "wait" (
		Echo setting xperf for wait
		Set xperfType=wait
		Set outputfile=%systemroot%\temp\xpwait.etl
	)
)

rem check for config folder
IF EXIST %configFolderx86% (
	set configFolder=%configFolderx86%
)
IF EXIST %configFolderx64% (
	set configFolder=%configFolderx64%
)
IF "%configFolder%"=="" (
	Echo configuration folder missing
	Echo %configFolderx64% or %configFolderx86% should exist
	goto error
)

IF %operation%==start (
	Echo -------------------------------------
	Echo checking to see if DisablePagingExecutive is set to 1
	reg.exe query "HKLM\System\CurrentControlSet\Control\Session Manager\Memory Management" /v DisablePagingExecutive /t REG_DWORD | find  "0x1" > nul

	IF "%errorlevel%" == "0" (
		Echo DisablePagingExecutive is set to 1
	) ELSE (
		Echo DisablePagingExecutive is set to 0
	
		goto error
	)

	IF "%xperfType%" == "slowlogon" (	
		rem high cpu
		Echo starting %configfolder%\%xperfCmd% -on base+latency+dispatcher+NetworkTrace+Registry+FileIO -stackWalk CSwitch+ReadyThread+ProcessCreate+ThreadCreate+Profile -BufferSize 128 -start CustomTrace -on "Microsoft-Windows-Shell-Core+Microsoft-Windows-Wininit+Microsoft-Windows-Folder Redirection+Microsoft-Windows-User Profiles Service+Microsoft-Windows-GroupPolicy+Microsoft-Windows-Winlogon+Microsoft-Windows-Security-Kerberos+Microsoft-Windows-User Profiles General+e5ba83f6-07d0-46b1-8bc7-7e669a1d31dc+63b530f8-29c9-4880-a5b4-b8179096e7b8+2f07e2ee-15db-40f1-90ef-9d7ba282188a+030f2f57-abd0-4427-bcf1-3a3587d7dc7d" -BufferSize 1024 -MinBuffers 64 -MaxBuffers 128 -MaxFile 1024

		%configfolder%\%xperfCmd% -on base+latency+dispatcher+NetworkTrace+Registry+FileIO -stackWalk CSwitch+ReadyThread+ProcessCreate+ThreadCreate+Profile -BufferSize 128 -start CustomTrace -on "Microsoft-Windows-Shell-Core+Microsoft-Windows-Wininit+Microsoft-Windows-Folder Redirection+Microsoft-Windows-User Profiles Service+Microsoft-Windows-GroupPolicy+Microsoft-Windows-Winlogon+Microsoft-Windows-Security-Kerberos+Microsoft-Windows-User Profiles General+e5ba83f6-07d0-46b1-8bc7-7e669a1d31dc+63b530f8-29c9-4880-a5b4-b8179096e7b8+2f07e2ee-15db-40f1-90ef-9d7ba282188a+030f2f57-abd0-4427-bcf1-3a3587d7dc7d" -BufferSize 1024 -MinBuffers 64 -MaxBuffers 128 -MaxFile 1024
	)

	IF "%xperfType%" == "highcpu" (	
		rem high cpu
		Echo starting %configfolder%\%xperfCmd% -on Latency -stackWalk Profile -BufferSize 64 -MaxBuffers 1024 -MaxFile 1024 -FileMode Circular
		%configfolder%\%xperfCmd% -on Latency -stackWalk Profile -BufferSize 64 -MaxBuffers 1024 -MaxFile 1024 -FileMode Circular
	)

	IF "%xperfType%" == "wait" (		
		rem wait analysis
		Echo starting %configfolder%\%xperfCmd% -on Latency+DISPATCHER -stackWalk CSwitch+ReadyThread+ThreadCreate+Profile -BufferSize 64 -MaxBuffers 1024 -MaxFile 1024 -FileMode Circular
		%configfolder%\%xperfCmd% -on Latency+DISPATCHER -stackWalk CSwitch+ReadyThread+ThreadCreate+Profile -BufferSize 64 -MaxBuffers 1024 -MaxFile 1024 -FileMode Circular
	)

	IF "%xperfType%" == "rebootcycle" (		
		rem reboot cycle
		Echo starting %configfolder%\%xbootCmd% -trace rebootCycle -numRuns 1 -noPrepReboot -traceFlags BASE+LATENCY+DISK_IO_INIT+DISPATCHER+DRIVERS+FILE_IO+FILE_IO_INIT+NETWORKTRACE+PERF_COUNTER+POWER+PRIORITY+REGISTRY -resultPath 
		%configfolder%\%xbootCmd% -trace rebootCycle -numRuns 1 -noPrepReboot -traceFlags BASE+LATENCY+DISK_IO_INIT+DISPATCHER+DRIVERS+FILE_IO+FILE_IO_INIT+NETWORKTRACE+PERF_COUNTER+POWER+PRIORITY+REGISTRY -resultPath %systemroot%\temp
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
	
	Echo %configfolder%\%xperfCmd% -stop -stop CustomTrace -d %outputfile%
	%configfolder%\%xperfCmd% -stop -stop CustomTrace -d %outputfile%
	

	Echo Gather the following logs:
	Echo %outputfile%
	Echo Remember to run 'xperf.mgr.bat clean' when finished troubleshooting to set disablepagingexecutive back to 0
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

