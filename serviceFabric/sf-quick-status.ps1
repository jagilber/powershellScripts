<#
.SYNOPSIS
quick script to enumerate different objects and health in cluster if sfx not available
this may error depending on configuration and version even if cluster is healthy

.LINK
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-quick-status.ps1" -outfile "$pwd\sf-quick-status.ps1";.\sf-quick-status.ps1;
#>

param(
    $timeoutsec = 10
)

connect-servicefabriccluster
if (!(reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServiceFabricNodeBootstrapAgent)) {
    #standalone
    get-servicefabricclusterconfiguration -TimeoutSec $timeoutsec
    get-servicefabricclusterconfigurationupgradestatus -TimeoutSec $timeoutsec
}
else {
    # arm
    $configJson = Get-Content -raw @(dir 'C:\Packages\Plugins\Microsoft.Azure.ServiceFabric.ServiceFabricNode\*\RuntimeSettings\*.settings')[-1].FullName
    $config = $configJson | ConvertFrom-Json
    $publicSettings = $config.runtimeSettings.handlersettings.publicSettings
    $clusterEndpoint = $publicSettings.clusterEndpoint
    $endpointUri = [uri]::new($clusterEndpoint)
    $endpointHost = $endpointUri.Authority

    $error.Clear()
    write-host "Test-NetConnection -ComputerName $endpointHost -port 443"
    $results = Test-NetConnection -ComputerName $endpointHost -port 443
    if (!($results.tcptestsucceeded)) {
        write-error "$($error | out-string)"
        $error.clear()

    }
    else {
        write-host "invoke-webrequest -Uri $clusterEndpoint -Certificate (gci Cert:\LocalMachine\My\$($publicSettings.certificate.thumbprint))"
        $response = invoke-webrequest -Uri $clusterEndpoint -Certificate (gci Cert:\LocalMachine\My\"$($publicSettings.certificate.thumbprint)")
        
        write-host "sfrp response" -ForegroundColor Yellow
        $response.BaseResponse

        $cert = (get-childitem -path Cert:\LocalMachine\my\$thumb)[-1]
        test-Certificate -Cert $cert -Policy SSL -AllowUntrustedRoot
        test-Certificate -Cert $cert -Policy BASE -AllowUntrustedRoot
        certutil -verifystore MY $thumb

    }
}

get-servicefabricclusterhealth -TimeoutSec $timeoutsec
Get-ServiceFabricClusterUpgrade -TimeoutSec $timeoutsec

$nodes = get-servicefabricnode -TimeoutSec $timeoutsec
$nodes
$nodes | get-servicefabricnodehealth -TimeoutSec $timeoutsec

$applications = get-servicefabricapplication -TimeoutSec $timeoutsec
$applications 
$applications | get-servicefabricapplicationhealth -TimeoutSec $timeoutsec
$applications | Get-ServiceFabricApplicationUpgrade -TimeoutSec $timeoutsec

$services = $applications | Get-ServiceFabricService -TimeoutSec $timeoutsec
$services
$services | Get-ServiceFabricServicehealth -TimeoutSec $timeoutsec

foreach ($nodename in $nodes.nodename) {
    foreach ($applicationname in $applications.applicationname) {
        Get-ServiceFabricDeployedApplication -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        Get-ServiceFabricDeployedApplicationHealth -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        $dpackages = get-servicefabricdeployedservicepackage -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
        $dpackages
        $dpackages | get-servicefabricdeployedservicepackagehealth -NodeName $nodename -ApplicationName $applicationname -TimeoutSec $timeoutsec
    }
}

$processes = (get-process) -imatch "fabric" | ft * -AutoSize
#$processes | fl *
$processes
