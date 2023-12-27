<#
.Synopsis
    provide powershell commands to add a new node type to an existing Azure Service Fabric cluster
    provide powershell commands to configure all existing applications to use PLB before adding new nodetype if not already done

    https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-resource-manager-cluster-description#node-properties-and-placement-constraints
.NOTES
    version 
      231219 add function get-certificateFromStore to get allow checking for cert in both localmachine store and currentuser store automatically if not found in specified store
      231210 add find-nodeType function to find vmss for reference node type
      231128 add function get-referenceNodeTypeVMSS($referenceNodeTypeName) to get vmss for reference node type
      231128 check for servicetype before adding to deployedServices and increment instances
        display nodetype names in resource group if nodetype not found
      231122 add check for az modules and version. older versions of az modules have issues with Add-AzServiceFabricNodeType
      231115 add connectivity check and cert validation
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-add-nodetype.ps1" -outFile "$pwd/azure-az-sf-add-nodetype.ps1";
    ./azure-az-sf-add-nodetype.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name>
.PARAMETER connectionEndpoint
    the connection endpoint for the service fabric cluster
.PARAMETER thumbprint
    the thumbprint of the service fabric cluster
.PARAMETER resourceGroupName
    the resource group name of the service fabric cluster
.PARAMETER clusterName
    the name of the service fabric cluster
.PARAMETER newNodeTypeName
    the name of the new node type to add to the service fabric cluster
.PARAMETER referenceNodeTypeName
    the name of the existing node type to use as a reference for the new node type
.PARAMETER isPrimaryNodeType
    whether the new node type is a primary node type
.PARAMETER vmImagePublisher
    the publisher of the vm image to use for the new node type
.PARAMETER vmImageOffer
    the offer of the vm image to use for the new node type
.PARAMETER vmImageSku
    the sku of the vm image to use for the new node type
.PARAMETER vmImageVersion
    the version of the vm image to use for the new node type
.PARAMETER vmInstanceCount
    the number of vm instances to use for the new node type
.PARAMETER vmSku
    the sku of the vm to use for the new node type
.PARAMETER durabilityLevel
    the durability level of the new node type
.PARAMETER adminUserName
    the admin username of the new node type
.PARAMETER adminPassword
    the admin password of the new node type
.PARAMETER logFile
    the log file to write to
.EXAMPLE
    ./azure-az-sf-add-nodetype.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name>
.EXAMPLE
    ./azure-az-sf-add-nodetype.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -referenceNodeTypeName nt0 -newNodeTypeName nt1
.EXAMPLE
    ./azure-az-sf-add-nodetype.ps1 -connectionEndpoint 'sfcluster.eastus.cloudapp.azure.com:19000' -thumbprint <thumbprint> -resourceGroupName <resource group name> -newNodeTypeName nt1 -referenceNodeTypeName nt0 -isPrimaryNodeType $false -vmImagePublisher MicrosoftWindowsServer -vmImageOffer WindowsServer -vmImageSku 2022-Datacenter -vmImageVersion latest -vmInstanceCount 5 -vmSku Standard_D2_v2 -durabilityLevel Silver -adminUserName cloudadmin -adminPassword P@ssw0rd!
#>

[cmdletbinding()]
param(
  [Parameter(ParameterSetName = 'tp', Mandatory = $true)]
  [Parameter(ParameterSetName = 'cn', Mandatory = $true)]
  [string]$connectionEndpoint = '', #'sfcluster.eastus.cloudapp.azure.com:19000',

  [Parameter(ParameterSetName = 'tp', Mandatory = $true)]
  [string]$thumbprint = '',

  [Parameter(ParameterSetName = 'cn', Mandatory = $true)]
  [string]$commonName = '',

  [Parameter(ParameterSetName = 'tp')]
  [Parameter(ParameterSetName = 'cn')]
  [validateSet('CurrentUser', 'LocalMachine')]
  [string]$storeLocation = 'CurrentUser',

  [Parameter(Mandatory = $true)]
  [string]$resourceGroupName = '', #'sfcluster',

  [string]$clusterName = $resourceGroupName,

  #[Parameter(Mandatory = $true)]
  [string]$newNodeTypeName = 'nt1', #'nt1',

  [string]$referenceNodeTypeName = 'nt0', #'nt0',

  [bool]$isPrimaryNodeType, # = $false,

  [string]$vmImagePublisher, # = 'MicrosoftWindowsServer',

  [string]$vmImageOffer, # = 'WindowsServer',

  [string]$vmImageSku, # = '2022-Datacenter',

  [string]$vmImageVersion, # = 'latest',

  [int]$vmInstanceCount, # = 5,

  [string]$vmSku, # = 'Standard_D2_v2',

  [ValidateSet('Bronze', 'Silver', 'Gold')]
  [string]$durabilityLevel, # = 'Silver',

  [string]$adminUserName, # = 'cloudadmin',

  [string]$adminPassword = 'P@ssw0rd!',

  [string]$logFile = "$pwd\azure-az-sf-add-nodetype.log",

  [switch]$force
)

$PSModuleAutoLoadingPreference = 'auto'
$global:deployedServices = @{}

function main() {
  try {
    if ($logFile) {
      Start-Transcript -path $logFile -Force | Out-Null
    }

    write-verbose ("starting")
    $error.Clear()
  
    if (!(Get-Module servicefabric)) {
      Import-Module servicefabric
      if ($error) {
        write-error("error importing servicefabric module")
        write-error("run from developer machine with service fabric sdk installed from from service fabric cluster node locally.")
        return $error
      }
    }
  
    if (!(check-modules)) {
      return
    }
  
    if (!(get-clusterConnection)) {
      return
    }
  
    if (!(get-clusterInformation)) {
      return
    }
  
    if (!(set-referenceNodeTypeInformation)) {
      return
    }
    add-placementConstraints
    write-results
  
    if ($logFile) {
      write-console "log file: $logFile"
    }
    write-console "finished"
  
  }
  catch [Exception] {
    write-console $psitem -ForegroundColor Red
  }
  finally {
    if ($logFile) {
      Stop-Transcript | Out-Null
    }
  }
}

function add-placementConstraints() {
  $plbNodeTypePattern = "($($global:nodeTypePlbNames.name -join '|'))\s?(=|!|<|>){1,2}\s?($($global:nodeTypePlbNames.value -join '|'))"
  $temporaryNodeTypeExclusion = "(NodeType != $newNodeTypeName)"
  $deployedServices = get-deployedServices

  $global:servicesWithPlacementConstraints = $global:deployedServices.Values | where-object {
    $psitem.placementConstraints -and $psitem.placementConstraints -ine 'None'
  }
  if ($global:servicesWithPlacementConstraints) {
    write-console ($global:servicesWithPlacementConstraints | convertto-json -depth 5) -Verbose
    
    foreach ($service in $global:servicesWithPlacementConstraints) {
      if (![regex]::IsMatch($service.placementConstraints, $plbNodeTypePattern)) {
        $placementConstraints = $service.placementConstraints
        $currentPlacementConstraints = $placementConstraints.replace('None', '')
        $placementConstraints = modify-placementConstraints -placementConstraints $placementConstraints -plbNodeTypePattern $plbNodeTypePattern -temporaryNodeTypeExclusion $temporaryNodeTypeExclusion
        $global:deployedServices[$service.serviceTypeName].temporaryPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '$placementConstraints' -force;"
        $global:deployedServices[$service.serviceTypeName].revertPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '$currentPlacementConstraints' -force;"
      }
    }
  }

  $global:servicesWithoutPlacementConstraints = $global:deployedServices.Values | where-object {
    !$psitem.placementConstraints -or $psitem.placementConstraints -ieq 'None'
  }
  if ($global:servicesWithoutPlacementConstraints) {
    write-console ($global:servicesWithoutPlacementConstraints | convertto-json -depth 5) -Verbose

    foreach ($service in $global:servicesWithoutPlacementConstraints) {
      $global:deployedServices[$service.serviceTypeName].temporaryPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '(NodeType != $newNodeTypeName)' -force;"
      $global:deployedServices[$service.serviceTypeName].revertPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '' -force;"
    }
  }

  $global:servicesOnNewNodeType = $global:deployedServices.Values | where-object { $psitem.deployedNodeTypes.Contains($newNodeTypeName) }
  if ($global:servicesOnNewNodeType) {
    write-console ($global:servicesOnNewNodeType | convertto-json -depth 5) -Verbose
    foreach ($service in $global:servicesOnNewNodeType) {
      $placementConstraints = $service.placementConstraints
      $currentPlacementConstraints = $placementConstraints.replace('None', '')
      $placementConstraints = modify-placementConstraints -placementConstraints $placementConstraints -plbNodeTypePattern $plbNodeTypePattern -temporaryNodeTypeExclusion $temporaryNodeTypeExclusion

      $global:deployedServices[$service.serviceTypeName].temporaryPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '$placementConstraints' -force;"
      $global:deployedServices[$service.serviceTypeName].revertPlacementConstraints = "Update-ServiceFabricService -$($service.ServiceKind) -ServiceName $($service.ServiceName) -PlacementConstraints '$($currentPlacementConstraints.replace($temporaryNodeTypeExclusion,''))' -force;"
    }
  }
}

function check-module($name, $version = $null) {
  write-host "checking module: $name version: $version" -ForegroundColor Cyan
  $error.clear()
  $module = get-module $name -ListAvailable
  if ($module) {
    if ($version) {
      if ($module.Version -lt $version) {
        write-warning "module $name version $($module.Version) is less than required version $version"
        $module = $null
      }
    }
  }

  if (!$module -or $error) {
    $error.clear()
    write-warning "azure module $name not installed."

    if ($force -or (read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
      if (!(get-psRepository -name PSGallery)) { register-psRepository -Default }
      $error.clear()
      install-module $name -allowclobber -force
      import-module $name
    }
    else {
      return $false
    }

    if ($error) {
      return $false
    }
  }

  return $true
}

function check-modules() {
  $retval = $true

  $modules = [ordered]@{
    'az.accounts'      = $null 
    'az.compute'       = $null
    'az.servicefabric' = [version]('3.2.0') # older versions have issues with Add-AzServiceFabricNodeType
    'az.resources'     = $null
  }

  foreach ($module in $modules.GetEnumerator()) {
    $retval = $retval -and (check-module $module.Name $module.Value)
  }

  if (!(get-azResourceGroup)) {
    Connect-AzAccount
  }

  if (!@(get-azResourceGroup).Count -gt 0) {
    return $false
  }
  return $retval
}

function compare-sfExtensionSettings([object]$sfExtSettings, [string]$clusterEndpoint, [string]$nodeTypeRef) {
  write-console "compare-sfExtensionSettings:`$settings, $clusterEndpoint, $nodeTypeRef"
  if (!$sfExtSettings) {
    write-console "settings not found" -foregroundColor 'Yellow'
    return $null
  }

  $clusterEndpointRef = $sfExtSettings.ClusterEndpoint
  if (!$clusterEndpointRef) {
    write-console "cluster endpoint not found" -foregroundColor 'Yellow'
    return $null
  }

  $nodeRef = $sfExtSettings.NodeTypeRef
  if (!$nodeRef) {
    write-console "node type ref not found in cluster settings" -foregroundColor 'Yellow'
    return $null
  }

  if ($clusterEndpointRef -ieq $clusterEndpoint -and $nodeTypeRef -ieq $nodeRef) {
    write-console "node type ref: $nodeTypeRef matches reference node type: $nodeRef" -foregroundColor 'Green'
    write-console "cluster endpoint ref: $clusterEndpointRef matches cluster endpoint: $clusterEndpoint" -foregroundColor 'Green'
    return $true
  }
  elseif ($nodeRef -ine $nodeTypeRef) {
    write-console "node type ref: $nodeTypeRef does not match reference node type: $nodeRef" -foregroundColor 'Yellow'
    return $false
  }
  else {
    write-console "cluster endpoint ref: $clusterEndpointRef does not match cluster endpoint: $clusterEndpoint" -foregroundColor 'Yellow'
    return $false
  }
}

function get-certificateFromStore($store, $thumbprint, $commonName) {
  $cert = $null
  if ($thumbprint) {
    write-host "Get-ChildItem cert:\$store\My -recurse | where-object Thumbprint -ieq $thumbprint"
    $cert = Get-ChildItem cert:\$store\My -recurse | where-object Thumbprint -ieq $thumbprint
  }
  else {
    write-host "Get-ChildItem cert:\$store\My -recurse | where-object Subject -ieq 'CN=$commonName'"
    $cert = Get-ChildItem cert:\$store\My -recurse | where-object Subject -ieq "CN=$commonName"
  }

  if (!$cert) {
    write-warning "certificate $thumbprint$commonName not found in $store store."
    return $null
  }
  return $cert
}

function get-clusterConnection() {
  $connected = $false

  try {
    # keep try for 5.1 compatibility
    $error.Clear()
    if ((Get-ServiceFabricClusterConnection).connectionEndpoint -ieq $connectionEndpoint) {
      $connected = $true
    }
  }
  catch [NullReferenceException] {
    write-verbose "Get-AzServiceFabricConnection not found. attempting to connect to cluster using Connect-ServiceFabricCluster"
    $error.Clear()
  }

  if (!$connected) {
    $error.Clear()
    $cert = $null
    
    $cert = get-certificateFromStore -store $storeLocation -thumbprint $thumbprint -commonName $commonName
    if (!$cert) {
      if ($storeLocation -ieq 'localmachine') {
        $storeLocation = 'currentuser'
      }
      else {
        $storeLocation = 'localmachine'
      }

      $cert = get-certificateFromStore -store $storeLocation -thumbprint $thumbprint -commonName $commonName
    }
    
    if (!$cert) {
      write-error "certificate with thumbprint $thumbprint not found"
      return $null
    }

    if (!$cert.HasPrivateKey) {
      write-warning "certificate with thumbprint $thumbprint does not have a private key"
      return $null
    }

    if ($cert.NotAfter -lt (get-date)) {
      write-error "certificate with thumbprint $thumbprint has expired"
      return $null
    }

    if ($cert.NotBefore -gt (get-date)) {
      write-error "certificate with thumbprint $thumbprint is not yet valid"
      return $null
    }

    write-console "using cert: $($cert | out-string)"
    write-console "Connecting to Service Fabric cluster $connectionEndpoint"

    $hostname = $connectionEndpoint.split(':')[0]
    $port = ($connectionEndpoint.split(':')[1], 19000) | select-object -first 1
    
    write-console "test-netConnection -ComputerName $hostname -Port $port"
    $result = test-netConnection -ComputerName $hostname -Port $port

    # set in case port is not specified
    $connectionEndpoint = "$($hostname):$port"

    If (!$result.TcpTestSucceeded) {
      write-error "error connecting to service fabric cluster $connectionEndpoint"                             
      return $null
    }
    else {
      write-console "able to connect to service fabric cluster $connectionEndpoint"
    }

    if ($thumbprint) {
      write-console "Connect-ServiceFabricCluster -ConnectionEndpoint $connectionEndpoint ``
      -KeepAliveIntervalInSec 10 ``
      -X509Credential ``
      -ServerCertThumbprint $thumbprint ``
      -FindType FindByThumbprint ``
      -FindValue $thumbprint ``
      -StoreLocation $storeLocation ``
      -StoreName My ``
      -Verbose
    " -foregroundColor Cyan

      $error.Clear()
      Connect-ServiceFabricCluster -ConnectionEndpoint $connectionEndpoint `
        -KeepAliveIntervalInSec 10 `
        -X509Credential `
        -ServerCertThumbprint $thumbprint `
        -FindType FindByThumbprint `
        -FindValue $thumbprint `
        -StoreLocation $storeLocation `
        -StoreName My `
        -Verbose
    }
    else {
      # common name
      write-console "Connect-ServiceFabricCluster -ConnectionEndpoint $connectionEndpoint ``
        -KeepAliveIntervalInSec 10 ``
        -X509Credential ``
        -ServerCommonName $commonName ``
        -FindType FindBySubjectName ``
        -FindValue $commonName ``
        -StoreLocation $storeLocation ``
        -StoreName My ``
        -Verbose
      " -foregroundColor Cyan
  
      $error.Clear()
      Connect-ServiceFabricCluster -ConnectionEndpoint $connectionEndpoint `
        -KeepAliveIntervalInSec 10 `
        -X509Credential `
        -ServerCommonName $commonName `
        -FindType FindBySubjectName `
        -FindValue $commonName `
        -StoreLocation $storeLocation `
        -StoreName My `
        -Verbose
  
    }
    # for 5.1 compatibility 
    $global:ClusterConnection = $ClusterConnection
  }

  if ($error -or !(Get-ServiceFabricClusterConnection)) {
    write-error "error connecting to service fabric cluster"
    throw
  }
  return $true
}

function find-nodeType([string]$resourceGroupName, [string]$clusterName, [string]$nodeTypeName) {
  write-console "find-nodeType:$resourceGroupName,$clusterName,$nodeTypeName"
  $serviceFabricResource = get-sfClusterResource -resourceGroupName $resourceGroupName -clusterName $clusterName
  if (!$serviceFabricResource) {
    write-console "service fabric cluster $clusterName not found" -err
    return $error
  }

  $nodeType = get-referenceNodeType $nodeTypeName $serviceFabricResource
  if (!$nodeType) {
    write-console "reference node type $nodeTypeName does not exist"  -err
    return $error
  }

  write-console $serviceFabricResource.ResourceId

  # get vmss for reference node type by name from resource group first
  $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
    -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
    -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName -vmssName $nodeTypeName)

  # get vmss for reference node type by name from resource groups
  if (!$currentVmss) {
    $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
      -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
      -vmssResources @(get-vmssResources -resourceGroupName $resourceGroupName)
  }

  # get vmss for reference node type by name from all resource groups
  if (!$currentVmss) {
    $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
      -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
      -vmssResources @(get-vmssResources -vmssName $nodeTypeName)
  }

  # get all vmss for reference node type by name from all resource groups
  if (!$currentVmss) {
    $currentVmss = get-referenceNodeTypeVMSS -nodetypeName $nodeTypeName `
      -clusterEndpoint $serviceFabricResource.properties.ClusterEndpoint `
      -vmssResources @(get-vmssResources)
  }

  if (!$currentVmss) {
    write-console "vmss for reference node type: $nodeTypeName not found" -foregroundColor 'Red'
    $global:referenceNodeType = $null
    return $null
  }

  write-console $currentVmss.ResourceId -foregroundColor 'Cyan'
  return $currentVmss
}

function get-clusterInformation() {
  write-console "Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName"
  $azCluster = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
  if (!$azCluster) {
    write-error "cluster $clusterName not found in resource group $resourceGroupName"
    if (!(get-azResourceGroup -Name $resourceGroupName)) {
      write-error "resource group $resourceGroupName not found in tenant: $((get-azContext).tenantId)"
      write-host "to change tenant, run 'Connect-AzAccount -TenantId <tenantId>'"
    }
    return $false
  }
  $manifest = Get-ServiceFabricClusterManifest
  write-console $manifest -Verbose

  $xmlManifest = [xml]::new()
  $xmlManifest.LoadXml($manifest)
  write-console $xmlManifest -Verbose

  $global:nodeTypePlbNames = ($xmlManifest.ClusterManifest.NodeTypes.NodeType.PlacementProperties.Property | Select-Object Name, Value)
  write-console ($global:nodeTypePlbNames | convertto-json -depth 5) -Verbose
  
  write-console "`$global:applications = Get-ServiceFabricApplication" -foregroundColor magenta
  $global:applications = Get-ServiceFabricApplication
  write-console ($global:applications | convertto-json -depth 5) -Verbose

  write-console "`$global:applicationTypes = `$global:applications | Get-ServiceFabricApplicationType" -foregroundColor magenta
  $global:applicationTypes = $global:applications | Get-ServiceFabricApplicationType
  write-console ($global:applicationTypes | convertto-json -depth 5) -Verbose

  write-console "`$global:services = $global:applications | Get-ServiceFabricService" -foregroundColor magenta
  $global:services = $global:applications | Get-ServiceFabricService
  write-console ($global:services | convertto-json -depth 5) -Verbose

  write-console "`$global:serviceDescriptions = `$global:services | Get-ServiceFabricServiceDescription" -foregroundColor magenta
  $global:serviceDescriptions = $global:services | Get-ServiceFabricServiceDescription
  write-console ($global:serviceDescriptions | convertto-json -depth 5) -Verbose

  write-console "`$global:serviceTypes = `$global:services | Get-ServiceFabricServiceType" -foregroundColor magenta
  $global:serviceTypes = $global:applicationTypes | Get-ServiceFabricServiceType
  write-console ($global:serviceTypes | convertto-json -depth 5) -Verbose

  write-console "`$global:placementConstraints = `$global:serviceDescriptions | Select-Object PlacementConstraints" -foregroundColor magenta
  $global:placementConstraints = $global:serviceDescriptions | Select-Object PlacementConstraints
  write-console ($global:placementConstraints | convertto-json -depth 5) -Verbose

  write-console "`$global:nodes = Get-ServiceFabricNode" -foregroundColor magenta
  $global:nodes = Get-ServiceFabricNode
  write-console ($global:nodes | convertto-json -depth 5) -Verbose

  foreach ($service in $global:serviceDescriptions) {

    if (!($global:deployedServices.ContainsKey($service.ServiceTypeName))) {
      write-console "Creating deployed service for service type $($service.ServiceTypeName)"
      $global:deployedServices.Add($service.ServiceTypeName , @{
          serviceTypeName               = $service.ServiceTypeName
          deployedNodeTypes             = @()
          deployedNodes                 = @()
          placementConstraints          = $service.PlacementConstraints
          serviceKind                   = $service.ServiceKind.ToString()
          serviceName                   = $service.ServiceName
          temporaryPlacementConstraints = ""
          revertPlacementConstraints    = ""
          instances                     = 0
        }
      )
    }
    else {
      write-console "Adding deployed service instance for service type $($service.ServiceTypeName)"
      $global:deployedServices[$service.ServiceTypeName].instances++
    }
  }
  return $true
}

function get-deployedServices() {
  foreach ($application in $global:applications) {
    write-console "Adding deployed service types for $($application.ApplicationName)"

    foreach ($node in $global:nodes) {
      write-console "Getting deployed applications for $($node.NodeName)"
      write-console "$deployedApplications = @(Get-ServiceFabricDeployedApplication -NodeName $node.NodeName)"
      $deployedApplications = @(Get-ServiceFabricDeployedApplication -NodeName $node.NodeName)
      if (!($deployedApplications.ApplicationName -contains $application.ApplicationName)) {
        write-console "Application $($application.ApplicationName) not deployed on node $($node.NodeName)"
        continue
      }
      
      write-console "Getting deployed service types for $($node.NodeName)"
      $deployedServiceTypes = @(Get-ServiceFabricDeployedServiceType -ApplicationName $application.ApplicationName -NodeName $node.NodeName)

      foreach ($deployedServiceType in $deployedServiceTypes) {
        write-console "Adding deployed service type $($deployedServiceType.ServiceTypeName) node $($node.NodeName)"
        $global:deployedServices[$deployedServiceType.ServiceTypeName].deployedNodes += $node.NodeName

        if (!$global:deployedServices[$deployedServiceType.ServiceTypeName].deployedNodeTypes.Contains($node.NodeType)) {
          write-console "Deployed service type $($deployedServiceType.ServiceTypeName) does not contain nodetype $($node.NodeType). Adding it now."
          $global:deployedServices[$deployedServiceType.ServiceTypeName].deployedNodeTypes += $node.NodeType
        }
      }
    }
  }

  return $global:deployedServices
}

function get-referenceNodeType([string]$nodeTypeName, $clusterResource) {
  write-console "get-referenceNodeType:$nodeTypeName,$clusterResource"

  $nodetypes = @($clusterResource.Properties.NodeTypes)
  $nodeType = $nodetypes | where-object name -ieq $nodeTypeName

  write-console "returning: $($nodeType.Name)"
  return $nodeType
}

function get-referenceNodeTypeVMSS([string]$nodetypeName, [string]$clusterEndpoint, $vmssResources) {
  # nodetype name should match vmss name but not always the case
  # get-azvmss returning jobject 23-11-29 mitigation to use get-azresource
  #$referenceVmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $nodeTypeName -ErrorAction SilentlyContinue
  $referenceVmss = $null

  if (!$vmssResources) {
    write-console "vmss for reference node type: $nodetypeName not found" -warn
    return $null
  }

  foreach ($vmss in $vmssResources) {
    $sfExtSettings = get-sfExtensionSettings $vmss
    $isNodeTypeRef = compare-sfExtensionSettings -sfExtSettings $sfExtSettings -clusterEndpoint $clusterEndpoint -nodeTypeRef $nodeTypeName
  
    if ($isNodeTypeRef) {
      write-console "found vmss: $($vmss.Name) for node type: $nodetypeName" -ForegroundColor Green
      $referenceVmss = $vmss
      break
    }
  }

  if (!$referenceVmss) {
    write-console "vmss for reference node type: $nodetypeName not found" -warn
    return $null
  }

  write-console "returning $($referenceVmss.ResourceId)"
  return $referenceVmss
}

function get-sfClusterResource([string]$resourceGroupName, [string]$clusterName) {
  write-console "get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties"
  $serviceFabricResource = get-azresource -ResourceGroupName $resourceGroupName -ResourceType Microsoft.ServiceFabric/clusters -Name $clusterName -ExpandProperties
  if (!$serviceFabricResource) {
    write-console "service fabric cluster $clusterName not found" -warn
  }
  else {
    write-console "cluster endpoint: $($serviceFabricResource.Properties.ClusterEndpoint)"
  }

  return $serviceFabricResource
}

function  get-sfExtensionSettings($vmss) {
  write-console "get-sfExtensionSettings $($vmss.Name)"
  #check extension
  $sfExtension = $vmss.properties.virtualMachineProfile.extensionProfile.extensions.properties | where-object publisher -imatch 'ServiceFabric'
  $settings = $sfExtension.settings
  if (!$settings) {
    write-console "service fabric extension not found for node type: $($vmss.Name)" -warn
  }
  else {
    write-console "service fabric extension found for node type: $($vmss.Name)"
  }
  return $settings
}

function get-vmssResources([string]$resourceGroupName, [string]$vmssName) {
  write-console "get-vmssResources -resourceGroupName $resourceGroupName -vmssName $vmssName"
  $paramValues = @{
    resourceType     = 'Microsoft.Compute/virtualMachineScaleSets'
    expandProperties = $true
  }

  if ($resourceGroupName) { [void]$paramValues.Add('resourceGroupName', $resourceGroupName) }
  if ($vmssName) { [void]$paramValues.Add('name', $vmssName) }

  write-console "get-azresource $($paramValues | convertto-json)" -foregroundColor cyan
  try {
    $vmssResources = @(get-azresource @paramValues -ErrorAction SilentlyContinue)
  }
  catch {
    write-console "exception:vmss $vmssName $($error | out-string)" -err
    return $null
  }

  if (!$vmssResources) {
    write-console "vmss $vmssName not found"
    return $null
  }
  elseif ($vmssResources.Count -gt 1) {
    write-console "returning: $($vmssResources.Count) vmss resource(s)"
  }
  else {
    write-console "returning: $(@($vmssResources)[0].ResourceId)"
  }
  return $vmssResources
}

function modify-placementConstraints($placementConstraints, $plbNodeTypePattern, $temporaryNodeTypeExclusion) {
  if (!$placementConstraints) {
    return $temporaryNodeTypeExclusion
  }
  if ($placementConstraints -ine 'None') {
    
    $placementConstraints = [regex]::replace($placementConstraints, "(\s?&&\s?)?$([regex]::escape($temporaryNodeTypeExclusion))", "").Trim() # $placementConstraints.replace(" && $temporaryNodeTypeExclusion","").trim()
    $pattern = "(?<replacement>NodeType\s?==\s?$newNodeTypeName)(?<termination>\W|$)"
    if ($placementConstraints -imatch $pattern) {
      # ensure that the nodetype name is not part of a larger word when replacing
      $placementConstraints = [regex]::replace($placementConstraints, $pattern, "NodeType != $newNodeTypeName`${termination}", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    else {
      $placementConstraints = "($($service.placementConstraints.trim('()'))) && $temporaryNodeTypeExclusion"
    }
  }
  else {
    $placementConstraints = $temporaryNodeTypeExclusion
  }

  return $placementConstraints
}

function set-referenceNodeTypeInformation() {
  if ($referenceNodeTypeName) {
    $referenceVmss = find-nodeType -resourceGroupName $resourceGroupName -clusterName $clusterName -nodeTypeName $referenceNodeTypeName
    $global:referenceVmss = $referenceVmss
    if (!$referenceVmss) {
      return $false
    }
    write-console "using reference node type $referenceNodeTypeName"
    $global:sfExtension = ($referenceVmss.Properties.virtualMachineProfile.ExtensionProfile.Extensions.properties | where-object publisher -imatch 'ServiceFabric')
    $global:durabilityLevel = set-value $durabilityLevel $sfExtension.Settings.durabilityLevel
    #$global:isPrimaryNodeType = set-value $isPrimaryNodeType $referenceNodeType.IsPrimary
    $global:vmImageSku = set-value $vmImageSku $referenceVmss.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Sku
    $global:vmSku = set-value $vmSku $referenceVmss.Sku.Name
    $global:adminUserName = set-value $adminUserName $referenceVmss.Properties.VirtualMachineProfile.OsProfile.AdminUsername
    $global:vmInstanceCount = set-value $vmInstanceCount $referenceVmss.Sku.Capacity
    $global:vmImagePublisher = set-value $vmImagePublisher $referenceVmss.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Publisher
    $global:vmImageOffer = set-value $vmImageOffer $referenceVmss.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Offer
    $global:vmImageVersion = set-value $vmImageVersion $referenceVmss.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Version
  }
  else {
    write-console "using default values for reference node type"
  }
  return $true
}

function set-value($paramValue, $referenceValue) {
  write-console "comparing values '$paramValue' and '$referenceValue'"
  $returnValue = $paramValue
  if ($paramValue -eq $null) {
    $returnValue = $referenceValue
  }
  elseif ([string]::IsNullOrEmpty($paramValue) -and ![string]::IsNullOrEmpty($referenceValue)) {
    $returnValue = $referenceValue
  }
  elseif ($paramValue -eq 0) {
    $returnValue = $referenceValue
  }

  write-console "returning value: '$returnValue'"
  return $returnValue
}

function write-console($message, $foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
  if (!$message) { return }
  if ($message.gettype().name -ine 'string') {
    $message = $message | convertto-json -Depth 10
  }

  $message = "$(get-date -format 'yyyy-MM-ddTHH:mm:ss.fff')::$message"

  if ($verbose) {
    write-verbose($message)
  }
  else {
    write-host($message) -ForegroundColor $foregroundColor
  }

  if ($warn) {
    write-warning($message)
  }
  elseif ($err) {
    write-error($message)
    throw
  }
}

function write-results() {
  write-console ($global:deployedServices | convertto-json -depth 5) -Verbose
  write-console "current node type placement properties: $($global:nodeTypePlbNames | convertto-json -depth 5)" -ForegroundColor Green
  write-console "current deployed services: $($global:deployedServices | convertto-json -depth 5)" -ForegroundColor Cyan

  if ($global:servicesWithPlacementConstraints) {
    write-console "services with placement constraints: $($global:servicesWithPlacementConstraints | convertto-json -depth 5)" -ForegroundColor Green
  }
  else {
    write-console "no services with placement constraints" -ForegroundColor Green
  }

  if ($global:servicesWithoutPlacementConstraints) {
    write-console "services without placement constraints: $($global:servicesWithoutPlacementConstraints | convertto-json -depth 5)" -ForegroundColor Yellow
  }
  else {
    write-console "no services without placement constraints" -ForegroundColor Green
  }
  
  if ($global:servicesOnNewNodeType) {
    write-console "services on new nodetype: $($global:servicesOnNewNodeType | convertto-json -depth 5)" -ForegroundColor Red
  }
  else {
    write-console "no services on new nodetype" -ForegroundColor Green
  }

  write-console ""
  write-console "--> To add new node type $newNodeTypeName to cluster $clusterName in resource group $resourceGroupName, 
  execute the following 'Add-AzServiceFabricNodeType' command after all services have placement constraints configured to prevent movement of applications to provisioning nodetype:" -ForegroundColor Yellow
  $global:addNodeTypeCommand = "Add-AzServiceFabricNodeType -ResourceGroupName $resourceGroupName ``
    -Name '$clusterName' ``
    -Capacity $global:vmInstanceCount ``
    -VmUserName '$global:adminUserName' ``
    -VmPassword (ConvertTo-SecureString -String '$adminPassword' -Force -AsPlainText) ``
    -VmSku '$global:vmSku' ``
    -DurabilityLevel '$global:durabilityLevel' ``
    -IsPrimaryNodeType `$$isPrimaryNodeType ``
    -VMImagePublisher '$global:vmImagePublisher' ``
    -VMImageOffer '$global:vmImageOffer' ``
    -VMImageSku '$global:vmImageSku' ``
    -VMImageVersion '$global:vmImageVersion' ``
    -NodeType '$newNodeTypeName' ``
    -Verbose
  "
  write-host $global:addNodeTypeCommand -ForegroundColor Magenta


  $global:plbCommands = $global:deployedServices.Values `
  | where-object temporaryPlacementConstraints `
  | select-object serviceName, temporaryPlacementConstraints, revertPlacementConstraints

  if ($global:plbCommands) {
    write-console "--> Potential plb update commands to prevent movement of applications to provisioning nodetype:. verify '-PlacementConstraints' string before executing commands: $($global:plbCommands | format-list * | out-string)"
  }
  else {
    write-console "no potential plb update commands" -ForegroundColor Green
  }

  write-console "values stored in `$global:addNodeTypeCommand `$global:plbCommands, and `$global:deployedServices" -ForegroundColor gray
}

main

