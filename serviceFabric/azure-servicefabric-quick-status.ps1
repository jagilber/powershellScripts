<#
quick script to enumerate different objects and health in cluster if sfx not available
this may error depending on configuration and version even if cluster is healthy
#>

param(
    $timeoutsec = 10
)

connect-servicefabriccluster

get-servicefabricclusterconfiguration -TimeoutSec $timeoutsec
get-servicefabricclusterconfigurationupgradestatus -TimeoutSec $timeoutsec
get-servicefabricclusterhealth -TimeoutSec $timeoutsec

$nodes = get-servicefabricnode -TimeoutSec $timeoutsec
$nodes
$nodes | get-servicefabricnodehealth -TimeoutSec $timeoutsec

$applications = get-servicefabricapplication -TimeoutSec $timeoutsec
$applications 
$applications | get-servicefabricapplicationhealth -TimeoutSec $timeoutsec

$services = $applications | Get-ServiceFabricService -TimeoutSec $timeoutsec
$services
$services | Get-ServiceFabricServicehealth -TimeoutSec $timeoutsec

foreach ($node in $nodes)
{
    foreach ($application in $applications)
    {
        $applicationname = $application.applicationname
        $nodeName = $node.NodeName
        Get-ServiceFabricDeployedApplication -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        Get-ServiceFabricDeployedApplicationHealth -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        $dpackages = get-servicefabricdeployedservicepackage -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        $dpackages
        $dpackages | get-servicefabricdeployedservicepackagehealth -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
    }
}


