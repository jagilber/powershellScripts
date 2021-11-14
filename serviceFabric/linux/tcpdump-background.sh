#!/bin/bash
set -o verbose
ifconfig
tcpTraceFile=./tcptrace
rm $tcpTraceFile
#rmdir --ignore-fail-on-non-empty powershellscripts
#scriptFile=https://raw.githubusercontent.com/Azure/service-fabric-scripts-and-templates/master/scripts/SetupServiceFabric/SetupServiceFabric.sh
sudo /usr/sbin/tcpdump -tttt 2>&1 >$tcpTraceFile &
sleep 1s
echo "tcpdump pid: $!"
ping google.com -c 1
ping microsoft.com -c 1
ping github.com -c 1
#curl $scriptFile -o ./SetupServiceFabric.sh #| sudo bash 
#sh ./SetupServiceFabric.sh
echo "killing tcpdump pid: $!"
sudo kill $!
cat $tcpTraceFile
sleep 10s
#tree /
#sleep 10s