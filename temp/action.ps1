<#
  iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/action.ps1" -outFile "$pwd\action.ps1"
#>
# ------------------------------------------------------------
# Copyright (c) Microsoft Corporation.  All rights reserved.
# Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
# ------------------------------------------------------------

param(
    $applicationName = 'fabric:/NCAS-STG', #'fabric:/Voting', 
    $placementConstraints = 'NodeName==NotUsed',
    $fmPartitionId = '00000000-0000-0000-0000-000000000001',
    [switch]$whatif
)

$erroractionpreference = 'stop' #'continue'

if(!(get-servicefabricclusterconnection)) {
    Connect-ServiceFabricCluster
}

write-host "Get-ServiceFabricService -ApplicationName $applicationName" -foregroundColor green
$services = Get-ServiceFabricService -ApplicationName $applicationName
$services | convertto-json

write-host "Get-ServiceFabricNode" -foregroundColor green
$nodes = Get-ServiceFabricNode
$nodes |  convertto-json

foreach($service in $services){
        $serviceName = $service.ServiceName
        if($service.ServiceKind -ieq 'Stateful'){
            write-warning "skipping stateful service $($service | convertto-json)"
            continue
        }
        else {
            write-host "Update-ServiceFabricService -Stateless -InstanceCount 1 -ServiceName $serviceName -Force" -foregroundColor green
            if(!$whatif) { Update-ServiceFabricService -Stateless -InstanceCount 1 -ServiceName $serviceName  -Force}

            write-host "Update-ServiceFabricService -Stateless -PlacementConstraints $placementConstraints -ServiceName $serviceName -Force" -foregroundColor green
            if(!$whatif) { Update-ServiceFabricService -Stateless -PlacementConstraints $placementConstraints -ServiceName $serviceName  -Force}

        }

    foreach($node in $nodes)
    {   
        $nodeName = $node.NodeName
        write-host "Get-ServiceFabricDeployedReplica -NodeName $nodeName -ApplicationName $applicationName | Where-Object {`$_.ServiceName -match $serviceName}" -foregroundColor green
        $replicas = Get-ServiceFabricDeployedReplica -NodeName $nodeName -ApplicationName $applicationName | Where-Object {$_.ServiceName -match $serviceName} 
        $replicas | convertto-json

        foreach($replica in $replicas){
            $partitionId = $replica.PartitionId
            $instanceId = $replica.InstanceId
            write-host "Remove-ServiceFabricReplica -NodeName $nodeName -ForceRemove -PartitionId $partitionId -ReplicaOrInstanceId $instanceId" -foregroundColor green
            if(!$whatif) { Remove-ServiceFabricReplica -NodeName $nodeName -ForceRemove -PartitionId $partitionId -ReplicaOrInstanceId $instanceId }
        }
    }
}

write-warning "if above is successful, disable and reimage all nodes in same nodetype (worker), one node at a time waiting for successful reimage completion between each node."
write-warning "it is critical for cluster to stabalize (be green) between each node reimage."
pause

# remove fm replicas
write-host "Get-ServiceFabricReplica -PartitionId $fmPartitionId | Remove-ServiceFabricReplica -PartitionId $fmPartitionId" -foregroundColor green
if(!$whatif) { Get-ServiceFabricReplica -PartitionId $fmPartitionId | Remove-ServiceFabricReplica -PartitionId $fmPartitionId }

write-host "Repair-ServiceFabricPartition -PartitionId $fmPartitionId -Force" -foregroundColor green
if(!$whatif) { Repair-ServiceFabricPartition -PartitionId $fmPartitionId -Force }


write-warning "wait here for cluster to become healthy. if above is successful."
pause


foreach($service in $services) {
    $serviceName = $service.ServiceName
    write-host "Remove-ServiceFabricService -ForceRemove -ServiceName $serviceName -Force" -foregroundColor green
    if(!$whatif) { Remove-ServiceFabricService -ForceRemove -ServiceName $serviceName -Force}
}

write-host "finished" -foregroundColor green