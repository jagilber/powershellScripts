<#
 script to enumerate ARM deployed service fabric applications

$subscriptionId = ''
$resourceGroupName = 'sfjagilber1nt3v'
$clusterName = $resourceGroupName
$clusterResource = "/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/Microsoft.ServiceFabric/clusters/$clusterName"
$applicationResourceId = "$clusterResource/applications/Voting"
$applicationTypeResourceId = "$clusterResource/applicationTypes/VotingType"
$applicationTypeVersionsResourceId = "$clusterResource/applicationTypes/VotingType/versions"

Remove-AzResource -ResourceId $applicationResourceId -Force -Verbose
Remove-AzResource -ResourceId $applicationTypeVersionsResourceId -Force -Verbose
Remove-AzResource -ResourceId $applicationTypeResourceId -Force -Verbose

#>
[cmdletbinding()]
param(
    $resourceGroupName = 'sfmcapim',
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
            $appType.Add($application.Name, @{$typeVersion.Name = [collections.arraylist]::new()})
            $resourceId = "$($application.ResourceId)"
            $applicationVersions = Get-AzResource -ResourceId $resourceId | where-object { $psitem.Properties.TypeVersion -ieq $typeVersion.Name }

            foreach ($applicationVersion in $applicationVersions) {
                [void]$appType.($application.Name).($typeVersion.Name).Add($applicationVersion)
                [void]$global:applicationView.applications.Add(@{$applicationType.Name = $appType})
            }
        }
    }
}

@($global:applicationView) | convertto-json -depth 99
write-host "object stored in `$global:applicationview" -foregroundColor yellow
