logman create trace "httptrace" -ow -o c:\minio_http.etl -p {DD5EF90A-6398-47A4-AD34-4DCECDEF795F} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 4096 -ets
logman update trace "httptrace" -p {20F61733-57F1-4127-9F48-4AB7A9308AE2} 0xffffffffffffffff 0xff -ets
logman update trace "httptrace" -p "Microsoft-Windows-HttpLog" 0xffffffffffffffff 0xff -ets
logman update trace "httptrace" -p "Microsoft-Windows-HttpService" 0xffffffffffffffff 0xff -ets
logman update trace "httptrace" -p "Microsoft-Windows-HttpEvent" 0xffffffffffffffff 0xff -ets
logman update trace "httptrace" -p "Microsoft-Windows-Http-SQM-Provider" 0xffffffffffffffff 0xff -ets
 
pause
logman stop "httptrace"  -ets
