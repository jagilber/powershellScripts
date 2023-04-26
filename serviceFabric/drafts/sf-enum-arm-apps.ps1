<#
 script to enumerate ARM deployed service fabric applications
#>
[cmdletbinding()]
param(
    $resourceGroupName = '',
    $clusterName = $resourceGroupName
)

$resourceType = "Microsoft.ServiceFabric/managedclusters"
$sfResource = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType | Where-Object Name -ieq $clusterName

if(!$sfResource) {
    $resourceType = "Microsoft.ServiceFabric/clusters"
    $sfResource = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType | Where-Object Name -ieq $clusterName
}

if(!$sfResource) {
    write-error "$clusterName not found in $resourceGroupName"
}

$global:applicationView = @{'applications' = [collections.arraylist]::new()}

$resourceId = "$($sfResource.ResourceId)/applicationTypes"
$applicationTypes = Get-AzResource -ResourceId $resourceId

foreach ($applicationType in $applicationTypes) {
    $appType = @{$applicationType.Name = $applicationType}
    $resourceId = "$($sfResource.ResourceId)/applicationTypes/$($applicationType.Name)/versions"
    $typeVersions = Get-AzResource -ResourceId $resourceId

    foreach ($typeVersion in $typeVersions) {
        $resourceId = "$($sfResource.ResourceId)/applications"
        $applications = Get-AzResource -ResourceId $resourceId 

        foreach ($application in $applications) {
            $versionsArray = @{'versions' = @{$typeVersion.Name = [collections.arraylist]::new()}}
            #[void]$versionsArray.versions.($typeVersion.Name).Add([collections.arraylist]::new())
            [void]$appType.Add($application.Name, $versionsArray)

            $resourceId = $application.ResourceId
            $applicationVersions = Get-AzResource -ResourceId $resourceId | where-object { $psitem.properties.version -ieq $typeVersion.Id }

            foreach ($applicationVersion in $applicationVersions) {
                [void]$appType.($application.Name).versions.($typeVersion.Name).Add($applicationVersion)
                [void]$global:applicationView.applications.Add(@{$applicationType.Name = $appType})
            }
        }
    }
}

@($global:applicationView) | convertto-json -depth 99
write-host "object stored in `$global:applicationview" -foregroundColor yellow
