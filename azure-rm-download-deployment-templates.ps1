<#
    script to export all deployment templates, parameters, and operations from azure subscription or list of resourcegroups
    https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups/exporttemplate

    {
"options" : "IncludeParameterDefaultValue, IncludeComments",
"resources" : ['*']

}
#>

param(
    [string]$outputDir = (get-location).path,
    [string[]]$resourceGroups
)

$outputDir = $outputDir + "\armDeploymentTemplates"
$ErrorActionPreference = "silentlycontinue"

# authenticate
try
{
    $tenants = @(Get-AzureRmTenant)
                
    if ($tenants)
    {
        write-host "auth passed $($tenants.Count)"
    }
    else
    {
        write-host "auth error $($tenants)" -ForegroundColor Yellow
        return
    }
}
catch
{
    try
    {
        Add-AzureRmAccount
    }
    catch
    {
        write-host "exception authenticating. exiting $($error)" -ForegroundColor Yellow
        return
    }
}

New-Item -ItemType Directory $outputDir -ErrorAction SilentlyContinue
Get-AzureRmDeployment | Save-AzureRmDeploymentTemplate -Path $outputDir -Force

if($resourceGroups.Count -lt 1)
{
    $resourceGroups = @((Get-AzureRmResourceGroup).ResourceGroupName)
}

foreach($rg in $resourceGroups)
{
    $rgDir = "$($outputDir)\$($rg)"
    New-Item -ItemType Directory $rgDir -ErrorAction SilentlyContinue

    foreach($dep in (Get-AzureRmResourceGroupDeployment -ResourceGroupName $rg))
    {
        Save-AzureRmResourceGroupDeploymentTemplate -Path $rgDir -ResourceGroupName $rg -DeploymentName ($dep.DeploymentName) -Force
        out-file -InputObject (convertto-json $dep.Parameters) -FilePath "$($rgDir)\$($dep.deploymentname).parameters.json" -Force
        out-file -InputObject (convertto-json (Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $($dep.DeploymentName) -ResourceGroupName $rg) -Depth 99) -FilePath "$($rgDir)\$($dep.deploymentname).operations.json" -Force
    }    
}

code $outputDir
$outputDir
write-host "finished"