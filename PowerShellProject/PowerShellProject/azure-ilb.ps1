# script to setup azure internal loadbalancing 
# this example is setting up load balancing for sql failover 
# jagilber 150908

Try
{
    $reg = Get-AzureService
}
catch
{
    Add-AzureAccount
}

# needs to exist
#$StorageAccountName = 'rdsblog'
#$StorageLocation = "https://$($StorageAccountName).blob.core.windows.net/vhds/"

#Set-AzureSubscription -SubscriptionName "Visual Studio Ultimate with MSDN" -CurrentStorageAccountName $StorageAccountName

$servers = @("rds-sql-1","rds-sql-2")

$svc="sql-ms"
$ilb="rds-ms-ilb"
$subnet="Subnet-2"
$IP="10.0.2.252"

$epname="rds-ms-ilb-ep"
$prot="tcp"
$locport=1433
$pubport=1433
$probePort = 59999

if(!(Get-AzureInternalLoadBalancer -ServiceName $svc))
{
    Add-AzureInternalLoadBalancer -ServiceName $svc -InternalLoadBalancerName $ilb –SubnetName $subnet –StaticVNetIPAddress $IP
}



foreach($server in $servers)
{
    write-host "checking $($server)"
    Get-AzureVM –ServiceName $svc –Name $server | `
        Add-AzureEndpoint -Name $epname -Protocol $prot -LocalPort $locport -PublicPort $pubport `
            -ProbePort $probePort -ProbeIntervalInSeconds 10 -ProbeProtocol $prot `
            -InternalLoadBalancerName $ilb -lbsetname "$($epname)-LB" -DirectServerReturn $true | `
            #-DefaultProbe -InternalLoadBalancerName $ilb -lbsetname "$($epname)-LB" -DirectServerReturn $true | `
        Update-AzureVM
}

write-host "finished"

