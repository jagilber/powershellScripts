rem logman start "NT Kernel Logger" -p "Windows Kernel Trace" (process,thread,disk,isr,dpc,net,img,registry,file) -bs 1024 -nb 20 20 -mode Circular -o kernel.etl -ct perf -max 20 -ets
logman start "NT Kernel Logger" -p "Windows Kernel Trace" process,thread,disk,file -bs 1024 -nb 20 20 -mode Circular -o kernel.etl -ct perf -max 20 -ets
pause
Logman stop "NT Kernel Logger" -ets