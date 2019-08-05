[cmdletbinding()]
param(
    $clusterendpoint = "cluster.location.cloudapp.azure.com:19000",#"10.0.0.4:19000",
    $thumbprint,
    $resourceGroup,
    $clustername = $resourceGroup,
    [ValidateSet('LocalMachine', 'CurrentUser')]
    $storeLocation = "LocalMachine"
)

# proxy test
#$proxyString = "http://127.0.0.1:5555"
#$proxyUri = new-object System.Uri($proxyString)
#[Net.WebRequest]::DefaultWebProxy = new-object System.Net.WebProxy ($proxyUri, $true)
#$proxy = [System.Net.CredentialCache]::DefaultCredentials
#[System.Net.WebRequest]::DefaultWebProxy.Credentials = $proxy
#Add-azAccount
$error.Clear()
import-module servicefabric
$DebugPreference = "continue"
$global:ClusterConnection = $null

if($resourceGroup -and $clustername)
{
    $cluster = Get-azServiceFabricCluster -ResourceGroupName $resourceGroup -Name $clustername
    $clusterendpoint = ($cluster.ManagementEndpoint.Replace("19080","19000").Replace("https://",""))
    $thumbprint = $cluster.Certificate.Thumbprint
    $global:cluster | ConvertTo-Json -Depth 99
}

# this sets wellknown local variable $ClusterConnection
Connect-ServiceFabricCluster `
    -ConnectionEndpoint $clusterendpoint `
    -ServerCertThumbprint $thumbprint `
    -StoreLocation $storeLocation `
    -X509Credential `
    -FindType FindByThumbprint `
    -FindValue $thumbprint `
    -Verbose

write-host "Connect-ServiceFabricCluster -ConnectionEndpoint $clusterendpoint -ServerCertThumbprint $thumbprint -StoreLocation $storeLocation -X509Credential -FindType FindByThumbprint -FindValue $thumbprint -verbose" -ForegroundColor Green
write-host "Get-ServiceFabricClusterConnection" -ForegroundColor Green

write-host "============================" -ForegroundColor Green
Get-ServiceFabricClusterConnection
$DebugPreference = "silentlycontinue"

# set global so commands can be run outside of script
$global:ClusterConnection = $ClusterConnection