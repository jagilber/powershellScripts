# deploy service fabric managed cluster with powershell

param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup = '',
    [Parameter(Mandatory = $true, ParameterSetName = "string")]
    [string]$adminPassword = '',
    [Parameter(Mandatory = $true, ParameterSetName = "sstring")]
    [securestring]$secureAdminPassword,
    [Parameter(Mandatory = $true)]
    [string]$thumbprint = '',
    [Parameter(Mandatory = $true)]
    [string]$location = '',
    [string]$adminUserName = 'vmadmin',
    [ValidateSet('standard', 'basic')]
    [string]$sku = 'standard', # standard
    #[Parameter(Mandatory=$true)]
    [string]$clusterName = $resourceGroup,
    [string]$nodeTypeName = "nt0",
    [int]$instanceCount = 5, # 5 - 100 for standard 3 for basic
    [bool]$addTags = $true,
    [switch]$export
)

$error.clear()
$ErrorActionPreference = 'stop'
$PSModuleAutoLoadingPreference = 2
$VerbosePreference = 'continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$startTime = get-date

if (!$secureAdminPassword) {
    $secureAdminPassword = ConvertTo-SecureString -AsPlainText -Force $adminPassword
}

if (((get-module az.servicefabric).Version -le [version](2.1.0))) {
    write-host "Install-Module az.servicefabric -AllowPrerelease -Force -AllowClobber" -ForegroundColor Yellow
    Install-Module az.servicefabric -AllowPrerelease -Force -AllowClobber
    #Install-Module az.accounts -AllowPrerelease -Force -AllowClobber
    #Install-Module az.resources -AllowPrerelease -Force -AllowClobber
}

if (!(get-azcontext)) {
    Connect-AzAccount
}

if (!(get-azresourcegroup -Name $resourceGroup -Location $location -ErrorAction SilentlyContinue)) {
    new-azresourcegroup -Name $resourceGroup -Location $location
}

if (Get-AzServiceFabricManagedCluster -ResourceGroupName $resourceGroup) {
    if ((read-host "managed cluster: $clusterName exists. delete?[y|n]") -imatch 'n') {
        return
    }
    
    write-host "remove-azservicefabricmanagedcluster -ResourceGroupName $resourceGroup -name $clustername" -ForegroundColor Yellow
    remove-azservicefabricmanagedcluster -ResourceGroupName $resourceGroup -name $clustername

    write-host "remove-azservicefabricmanagednodetype -ResourceGroupName $resourceGroup -name $nodeTypeName -ClusterName $clustername" -ForegroundColor Yellow
    remove-azservicefabricmanagednodetype -ResourceGroupName $resourceGroup -name $nodeTypeName -ClusterName $clusterName

    write-host "remove-azservicefabricmanagedclusterclientcertificate -ResourceGroupName $resourceGroup -name $clustername" -ForegroundColor Yellow
    remove-azservicefabricmanagedclusterclientcertificate -ResourceGroupName $resourceGroup -name $clustername
}

write-host "New-AzServiceFabricManagedCluster -ResourceGroupName $resourceGroup `
    -Location $location `
    -ClusterName $clusterName `
    -ClientCertThumbprint $thumbprint `
    -ClientCertIsAdmin `
    -AdminUserName $adminUserName `
    -AdminPassword $secureAdminPassword `
    -Sku $sku `
    -Verbose
    " -ForegroundColor Green

New-AzServiceFabricManagedCluster -ResourceGroupName $resourceGroup `
    -Location $location `
    -ClusterName $clusterName `
    -ClientCertThumbprint $thumbprint `
    -ClientCertIsAdmin `
    -AdminUserName $adminUserName `
    -AdminPassword $secureAdminPassword `
    -Sku $sku `
    -Verbose

write-host "Add-AzServiceFabricManagedClusterClientCertificate -ResourceGroupName $resourceGroup `
    -ClusterName $clusterName `
    -Thumbprint $thumbprint `
    -Admin `
    -Verbose
    " -ForegroundColor Green

Add-AzServiceFabricManagedClusterClientCertificate -ResourceGroupName $resourceGroup `
    -ClusterName $clusterName `
    -Thumbprint $thumbprint `
    -Admin `
    -Verbose

write-host "New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroup `
    -ClusterName $clusterName `
    -Name $NodeTypeName `
    -Primary `
    -InstanceCount $instanceCount `
    -Verbose
    " -ForegroundColor Green

New-AzServiceFabricManagedNodeType -ResourceGroupName $resourceGroup `
    -ClusterName $clusterName `
    -Name $NodeTypeName `
    -Primary `
    -InstanceCount $instanceCount `
    -Verbose

write-host "$cluster = Get-AzServiceFabricManagedCluster -resourcegroupname $resourceGroup -name $clusterName" -ForegroundColor Cyan
$cluster = Get-AzServiceFabricManagedCluster -resourcegroupname $resourceGroup -name $clusterName
$cluster | convertto-json

$sfcRgName = "sfc_$($cluster.ClusterId)"

write-host $sfcRgName -ForegroundColor Cyan
$sfcRg = get-azresourcegroup -ResourceGroupName $sfcRgName
get-azresource -ResourceGroupName $sfcRgName | ConvertTo-Json

write-host $resourceGroup -ForegroundColor Cyan
$clusterRg = get-azresourcegroup -ResourceGroupName $resourceGroup
get-azresource -ResourceGroupName $resourceGroup | convertto-json

if ($addTags) {
    write-host "Update-AzTag -ResourceId $sfcRg.resourceid -Tag @{'sfManagedCluster'= $cluster.name} -Operation merge" -ForegroundColor Yellow
    Update-AzTag -ResourceId $sfcRg.resourceid -Tag @{'sfManagedCluster' = $cluster.name } -Operation merge

    write-host "Update-AzTag -ResourceId $sfcRg.resourceid -Tag @{'sfManagedCluster'= $cluster.name} -Operation merge" -ForegroundColor Yellow
    Update-AzTag -ResourceId $clusterRg.resourceid -Tag @{'sfManagedClusterRG' = $sfcRgName } -Operation merge
}

if ($export) {
    Export-AzResourceGroup -ResourceGroupName $resourceGroupName
    Export-AzResourceGroup -ResourceGroupName $sfcRgName
}

write-host "total time: $((get-date) - $startTime)"
write-host "to connect to node 0:`r`nmstsc /v $clusterName.$location.cloudapp.azure.com:50000" -ForegroundColor Magenta
