<#
.SYNOPSIS
example script to use sfctl to start chaos using 'voting' solution test project

.NOTES
uses and assumes example voting solution has been deployed to cluster
https://github.com/Azure-Samples/service-fabric-dotnet-quickstart


https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-controlled-chaos
https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-sfctl-chaos

.LINK

#>

param(
    $timeToRunMinutes = 10,
    $maxConcurrentFaults = 3,
    $maxClusterStabilizationTimeSecs = 30,
    $waitTimeBetweenIterationsSec = 10,
    $maxPercentUnhealthyApplications = 0,
    $waitTimeBetweenFaultsSec = 0,
    $clusterEndpoint,
    $pemFile,
    $applicationTypeFilter = "fabric:/Voting",
    $nodeTypeFilter = "nt0",
    $appTypeHealthPolicy = "[{\`"key\`": \`"$applicationTypeFilter\`", \`"value\`": \`"$maxPercentUnhealthyApplications\`"}]",
    $chaosTargetFilter = @{
        NodeTypeInclusionList    = @($nodeTypeFilter)
        ApplicationInclusionList = @($applicationTypeFilter)
    }
)

$PSModuleAutoLoadingPreference = 2
$erroractionpreference = "continue"
$error.Clear()

if(!(sfctl)) {
    write-error "sfctl not installed. see https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cli"

}

$timer = get-date
$chaosTargetFilterJSON = [regex]::replace(($chaosTargetFilter | ConvertTo-Json), "\s", "").Replace("`"", "\`"")

write-host "app Health Policy json: `r`n$appTypeHealthPolicy" -ForegroundColor Cyan
write-host "chaos Target Filter JSON: `r`n$chaosTargetFilterJSON" -ForegroundColor Cyan
$timeToRunSeconds = $timeToRunMinutes * 60

$error.Clear()
write-host "sfctl cluster show-connection"
$connection = sfctl cluster show-connection
if($error -or !$connection){
    if($clusterEndpoint -and $pemFile) {
        write-host "sfctl cluster select --endpoint $clusterEndpoint --pem $pemFile --no-verify"
        sfctl cluster select --endpoint $clusterEndpoint --pem $pemFile --no-verify
    }
    else {
        write-error "provide `$clusterEndpoint and `$pemfile to select cluster. not connecting to cluster."
        return
    }
}

write-host "sfctl chaos stop --debug"
sfctl chaos stop --debug

write-host "
sfctl chaos start `
    --time-to-run $timeToRunSeconds `
    --max-concurrent-faults $maxConcurrentFaults `
    --max-cluster-stabilization $maxClusterStabilizationTimeSecs `
    --wait-time-between-iterations $waitTimeBetweenIterationsSec `
    --wait-time-between-faults $waitTimeBetweenFaultsSec `
    --app-type-health-policy-map $appTypeHealthPolicy `
    --chaos-target-filter $chaosTargetFilterJSON `
    --debug
"

sfctl chaos start `
    --time-to-run $timeToRunSeconds `
    --max-concurrent-faults $maxConcurrentFaults `
    --max-cluster-stabilization $maxClusterStabilizationTimeSecs `
    --wait-time-between-iterations $waitTimeBetweenIterationsSec `
    --wait-time-between-faults $waitTimeBetweenFaultsSec `
    --app-type-health-policy-map $appTypeHealthPolicy `
    --chaos-target-filter $chaosTargetFilterJSON `
    --debug

$chaosStatus = $null

while (!$chaosStatus -or $chaosStatus.scheduleStatus -ieq 'Active') {
    $chaosStatus = sfctl chaos get --debug | convertfrom-json
    write-host ($chaosStatus | fl * | out-string)
    start-sleep -Seconds 1
}

sfctl chaos get --debug

$totalTime = (get-date) - $timer

if($totalTime -lt ($timeToRunSeconds))  {
    Write-Warning "test finished before timeout"
}

write-host "finished: total time: $totalTime"