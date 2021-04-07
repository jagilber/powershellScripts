$thumbprint = "0123456789012345678901234567890123456789"
$fabricApplicationName = "fabric:/Watchdog"
$fabricApplicationNameType = "fabric:/WatchdogType"
$fabricServiceName = "fabric:/WatchdogType/WatchdogService"
$applicationVersion = "1.0.0"
$applicationTypeName = "WatchdogType"

Connect-ServiceFabricCluster -ConnectionEndpoint "10.0.0.4:19000" -X509Credential -ServerCertThumbprint $thumbprint -FindType FindByThumbprint -FindValue $thumbprint -verbose -StoreLocation CurrentUser

Remove-ServiceFabricApplication -ApplicationName $fabricApplicationName

Remove-ServiceFabricApplication -ApplicationName $fabricApplicationNameType
Unregister-ServiceFabricApplicationType -ApplicationTypeName $applicationTypeName -ApplicationTypeVersion $applicationVersion -Verbose
Remove-ServiceFabricApplicationPackage -ApplicationPackagePathInImageStore $fabricApplicationNameType -Verbose
Remove-ServiceFabricService -ServiceName $fabricServiceName -Verbose