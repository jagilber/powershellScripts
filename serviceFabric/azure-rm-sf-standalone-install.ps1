<#
 script to install service fabric standalone in azure arm
 # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-for-windows-server

 <#
    The CleanCluster.ps1 will clean these certificates or you can clean them up using script 'CertSetup.ps1 -Clean -CertSubjectName CN=ServiceFabricClientCert'.
    Server certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\server.pfx with the password 1230909376
    Client certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\client.pfx with the password 940188492
    Modify thumbprint in C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\ClusterConfig.X509.OneNode.json
#>

#>


param(
    [switch]$remove,
    [switch]$force,
    [string]$configurationFile = ".\ClusterConfig.X509.OneNode.json", # ".\ClusterConfig.X509.MultiMachine.json", #".\ClusterConfig.Unsecure.DevCluster.json",
    $packageUrl = "https://go.microsoft.com/fwlink/?LinkId=730690",
    $packageName = "Microsoft.Azure.ServiceFabric.WindowsServer.latest.zip",
    $downloadPath = "c:\temp",
    $timeout = 1200
)

$Error.Clear()
$scriptPath = ([io.path]::GetDirectoryName($MyInvocation.ScriptName))
Start-Transcript -Path "$scriptPath\install.log"
$currentLocation = (get-location).Path

if(!(test-path $downloadPath))
{
    md $downloadPath
}

set-location $downloadPath
$packagePath = "$(get-location)\$([io.path]::GetFileNameWithoutExtension($packageName))"

if($force -and (test-path $packagePath))
{
    rd $packagePath -Recurse
}

if(!(test-path $packagePath))
{
    (new-object net.webclient).DownloadFile("https://go.microsoft.com/fwlink/?LinkId=730690","$(get-location)\$packageName")
    Expand-Archive $packageName
}

Set-Location $packagePath

if($remove)
{
    .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFile -Force
    .\CleanFabric.ps1
}
else
{
    .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFile
    .\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFile -AcceptEULA -NoCleanupOnFailure -GenerateX509Cert -Force -TimeoutInSeconds $timeout -MaxPercentFailedNodes 100
}

Connect-ServiceFabricCluster -ConnectionEndpoint localhost:19000
Get-ServiceFabricNode |Format-Table

Set-Location $currentLocation
Stop-Transcript