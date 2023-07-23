<#
 script to enumerate ARM deployed service fabric applications

$subscriptionId = (Get-AzContext).Subscription.Id
$resourceGroupName = 'sfjagilber1nt3'
$clusterName = $resourceGroupName
$clusterResource = "/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/Microsoft.ServiceFabric/clusters/$clusterName"
$applicationResourceId = "$clusterResource/applications/Voting"
$applicationTypeResourceId = "$clusterResource/applicationTypes/VotingType"
$applicationTypeVersionsResourceId = "$clusterResource/applicationTypes/VotingType/versions"

Remove-AzResource -ResourceId $applicationResourceId -Force -Verbose #-api-version 2021-06-01
foreach($ver in $versions) {
    Remove-AzResource -ResourceId $applicationTypeVersionsResourceId/$version -Force -Verbose
}

Remove-AzResource -ResourceId $applicationTypeResourceId -Force -Verbose

#>
[cmdletbinding()]
param(
    $resourceGroupName = 'sfjagilber1nt3',
    $clusterName = $resourceGroupName
)

$resourceType = "Microsoft.ServiceFabric/managedclusters"
$sfResource = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType | Where-Object Name -ieq $clusterName

if (!$sfResource) {
    $resourceType = "Microsoft.ServiceFabric/clusters"
    $sfResource = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType | Where-Object Name -ieq $clusterName
}

if (!$sfResource) {
    write-error "$clusterName not found in $resourceGroupName"
}

$global:applicationView = @{'applications' = [collections.arraylist]::new() }

$resourceId = "$($sfResource.ResourceId)/applicationTypes"
write-host "`$applicaitonTypes = Get-AzResource -ResourceId $resourceId" -ForegroundColor Cyan
$applicationTypes = Get-AzResource -ResourceId $resourceId

foreach ($applicationType in $applicationTypes) {
    write-host "adding application type: $($applicationType.Name) to applicationView" -ForegroundColor Green
    $appType = @{$applicationType.Name = $applicationType }
    $resourceId = "$($sfResource.ResourceId)/applicationTypes/$($applicationType.Name)/versions"
    write-host "`$typeVersions = Get-AzResource -ResourceId $resourceId" -ForegroundColor Cyan
    $typeVersions = Get-AzResource -ResourceId $resourceId

    foreach ($typeVersion in $typeVersions) {
        write-host "adding application type version: $($typeVersion.Name) to $($applicationType.Name)" -ForegroundColor Green
        $resourceId = "$($sfResource.ResourceId)/applications"
        write-host "`$applications = Get-AzResource -ResourceId $resourceId" -ForegroundColor Cyan
        $applications = Get-AzResource -ResourceId $resourceId 

        foreach ($application in $applications) {
            write-host "adding application: $($application.Name) to $($typeVersion.Name)" -ForegroundColor Green
            if (!$appType.($application.Name)) {
                [void]$appType.Add($application.Name, @{})
            }

            if (!$appType.($application.Name).($typeVersion.Name)) {
                [void]$appType.($application.Name).Add($typeVersion.Name, [collections.arraylist]::new())
            }

            [void]$appType.($application.Name).($typeVersion.Name).Add($application)
        }
    }

    write-host "adding $($application.Name) to global applicationView hashtable" -ForegroundColor Green
    [void]$global:applicationView.applications.Add($appType)
}

@($global:applicationView) | convertto-json -depth 99
write-host "object stored in `$global:applicationview" -foregroundColor yellow
