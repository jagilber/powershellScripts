<#
.SYNOPSIS 
service fabric restart stateful / remove stateless replicas in warning state.
run from working node or connect-servicefabriccluster prior to running script if not on node.

.DESCRIPTION

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-restart-warning-replicas.ps1" -outFile "$pwd/sf-restart-warning-replicas.ps1";
    ./sf-restart-warning-replicas.ps1 -whatIf

#>
[cmdletbinding()]
param(
    [switch]$whatIf,
    [switch]$all,
    [int]$delaySeconds = 1
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
$error.Clear()
$badReplicas = @{} #[collections.arraylist]::new()

if (!(get-command connect-servicefabriccluster)) {
    import-module servicefabric
}

if (!(Get-ServiceFabricClusterConnection)) {
    connect-servicefabriccluster
}

write-host "get-servicefabricapplication" -ForegroundColor Cyan
$global:applications = get-servicefabricapplication
$applications

write-host "get-servicefabricnode" -ForegroundColor Cyan
$global:nodes = get-servicefabricnode

foreach ($application in $applications) {
    $appName = $application.ApplicationName
    write-host "checking $appName" -ForegroundColor Cyan
    
    foreach ($node in $nodes) {
        $nodeName = $node.NodeName
        write-host "checking $nodeName" -ForegroundColor Cyan
        write-host "`$replicas = get-servicefabricdeployedreplica -nodename $nodeName" -ForegroundColor Cyan
        $global:replicas = get-servicefabricdeployedreplica -nodename $nodeName -ApplicationName $appName
        $replicas

        foreach ($replica in $replicas) {
            $serviceName = $replica.ServiceName
            write-host "checking service: $serviceName" -ForegroundColor Cyan
            $partitionId = $replica.PartitionId
            $replicaOrInstanceId = $replica.ReplicaOrInstanceId
            if ($all) {
                write-host "adding replica $($replica |convertto-json)"
                [void]$badReplicas.add($replica, $nodeName)
                continue
            }
            
            write-host "`$health = get-servicefabricreplicahealth -partitionId $partitionId -replicaorinstanceid $replicaOrInstanceId" -ForegroundColor green
            $health = get-servicefabricreplicahealth -partitionId $partitionId -replicaorinstanceid $replicaOrInstanceId
            $health
            if ($health.AggregatedHealthState -ine "ok") {
                write-warning "replica health not 'ok' $($replica | convertto-json -depth 99)"
                [void]$badReplicas.add($replica, $nodeName)
                #continue
            }
            else {
                write-host "replica health ok: $($health.AggregatedHealthState)" -ForegroundColor Green
            }
            <#
            if ($replica.ReplicaStatus -ine "Ready") {
                write-warning "replica is not ready $($replica | convertto-json -depth 99)"
                [void]$badReplicas.add($replica,$nodeName)
                continue
            }
            else {
                write-host "replica is ready $($replica | convertto-json -depth 99)" -ForegroundColor green
            }
            if ($replica.ReconfigurationInformation -and $replica.ReconfiguraitonInformation.ReconfigurationPhase -and $replica.ReconfiguraitonInformation.ReconfigurationPhase -ine "None") {
                write-warning "reconfiguration phase not equal None $($replica.ReconfiguraitonInformation.ReconfigurationPhase)"
                [void]$badReplicas.add($replica, $nodeName)
                continue
            }
            else {
                write-host "replica not being reconfigured $($replica | convertto-json -depth 99)" -ForegroundColor green
            }
            #>
        }
    }
}

#$badReplicas
if ($badReplicas) {
    write-host "bad replicas $($badReplicas )"
    foreach ($badReplica in $badReplicas.getenumerator()) {
        $partitionId = $badReplica.key.PartitionId
        $replicaOrInstanceId = $badReplica.key.ReplicaOrInstanceId
        $nodeName = $badReplica.value
        $serviceKind = $badReplica.key.ServiceKind
        if ($serviceKind -ieq 'stateless') {
            Write-Warning "remove-servicefabricreplica -partitionId $partitionId -nodename $nodeName -replicaOrInstanceId $replicaOrInstanceId"
            if (!($whatIf)) {
                remove-servicefabricreplica -partitionId $partitionId -nodename $nodeName -replicaOrInstanceId $replicaOrInstanceId
            }    
        }
        else {
            Write-Warning "restart-servicefabricreplica -partitionId $partitionId -nodename $nodeName -replicaOrInstanceId $replicaOrInstanceId"
            if (!($whatIf)) {
                restart-servicefabricreplica -partitionId $partitionId -nodename $nodeName -replicaOrInstanceId $replicaOrInstanceId
            }    
        }
        start-sleep -Seconds $delaySeconds
    }
}
else {
    write-host "no bad replicas found"
}


