<#
.SYNOPSIS
    Enumerate Service Fabric Applications deployed via ARM
 .DESCRIPTION
    Enumerate Service Fabric Applications deployed via ARM
.PARAMETER resourceGroupName
    resource group name
.PARAMETER clusterName
    cluster name
.EXAMPLE
    .\sf-enum-arm-apps.ps1 -resourceGroupName <resource group name> -clusterName <cluster name>
.EXAMPLE
    .\sf-enum-arm-apps.ps1 -resourceGroupName <resource group name>
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/sf-enum-arm-apps.ps1" -outFile "$pwd/sf-enum-arm-apps.ps1";
    ./sf-enum-arm-apps.ps1
#>
[cmdletbinding()]
param(
    $resourceGroupName = 'sfjagilber1nt3',
    $clusterName = $resourceGroupName
)

function main() {
    if (!(check-module)) {
        return
    }

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

}

function check-module() {
    $error.clear()
    get-command Connect-AzAccount -ErrorAction SilentlyContinue

    if ($error) {
        $error.clear()
        write-warning "azure module for Connect-AzAccount not installed."

        if ((read-host "is it ok to install latest azure az module?[y|n]") -imatch "y") {
            $error.clear()
            install-module az.accounts
            install-module az.resources

            import-module az.accounts
            import-module az.resources
        }
        else {
            return $false
        }

        if ($error) {
            return $false
        }
    }

    if (!(get-azResourceGroup)) {
        Connect-AzAccount
    }

    if (!@(get-azResourceGroup).Count -gt 0) {
        return $false
    }

    return $true
}

main
