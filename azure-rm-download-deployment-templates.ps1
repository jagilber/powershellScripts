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
    [string[]]$resourceGroups,
    [string]$clientId,
    [string]$clientSecret,
    [string]$thumbprint,
    [switch]$useGit
)

$outputDir = $outputDir + "\armDeploymentTemplates"
$ErrorActionPreference = "silentlycontinue"
$getCurrentConfig = $clientId + $clientSecret + $thumbprint -gt 0
$currentdir = (get-location).path
$error.Clear()
function main()
{
    check-authentication
    New-Item -ItemType Directory $outputDir -ErrorAction SilentlyContinue
    Get-AzureRmDeployment | Save-AzureRmDeploymentTemplate -Path $outputDir -Force
    set-location $outputDir

    if($useGit -and !(git))
    {
        write-host "git not installed"
        $useGit = $false
        $error.Clear()
    }
    
    if($useGit -and !(git status))
    {
        git init
    }

    if($resourceGroups.Count -lt 1)
    {
        $resourceGroups = @((Get-AzureRmResourceGroup).ResourceGroupName)
    }

    foreach($rg in $resourceGroups)
    {
        $rgDir = "$($outputDir)\$($rg)"
        New-Item -ItemType Directory $rgDir -ErrorAction SilentlyContinue
        if($getCurrentConfig)
        {
            out-file -InputObject (convertto-json get-CurrentConfig) -FilePath "$($rgDir)\current.json" -Force
        }

        foreach($dep in (Get-AzureRmResourceGroupDeployment -ResourceGroupName $rg))
        {
            if($useGit)
            {
                $templateFile = "$($rgDir)\template.json"

                if((test-path $templateFile))
                {
                    $previousTemplate = ConvertFrom-Json $templateFile
                }

                Save-AzureRmResourceGroupDeploymentTemplate -Path $templateFile -ResourceGroupName $rg -DeploymentName ($dep.DeploymentName) -Force
                out-file -Encoding ascii -InputObject (convertto-json $dep.Parameters) -FilePath "$($rgDir)\parameters.json" -Force
                out-file -Encoding ascii -InputObject (convertto-json (Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $($dep.DeploymentName) -ResourceGroupName $rg) -Depth 99) -FilePath "$($rgDir)\operations.json" -Force
                
                git add -A
                git commit -a -m "$($rg) $($dep.deploymentname)) $($dep.TimeStamp) $($dep.ProvisioningState)`n$($outputs | out-string)" --date (($dep.TimeStamp).ToString("o"))
            }
            else
            {
                Save-AzureRmResourceGroupDeploymentTemplate -Path $rgDir -ResourceGroupName $rg -DeploymentName ($dep.DeploymentName) -Force
                out-file -Encoding ascii -InputObject (convertto-json $dep.Parameters) -FilePath "$($rgDir)\$($dep.deploymentname).parameters.json" -Force
                out-file -Encoding ascii -InputObject (convertto-json (Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $($dep.DeploymentName) -ResourceGroupName $rg) -Depth 99) -FilePath "$($rgDir)\$($dep.deploymentname).operations.json" -Force
            }
        }    
    }

    if(!$getCurrentConfig)
    {
        write-warning "this information does *not* include the currently running confiruration, only the last deployments. example no changes made in portal after deployment"
        write-host "to get the current running configuration ('automation script' in portal), use portal, or"
        write-host "rerun script with clientid and clientsecret or thumbprint arguments"
        write-host "these are values used when connecting to azure using a script either with powershel azure modules or rest methods"
        write-host "use this script to generate azure ad spn app with a self signed cert for use with scripts (not just this one)"
        write-host "(new-object net.webclient).downloadfile(`"https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-rm-create-aad-application-spn.ps1`",`"$(get-location)\azure-rm-create-aad-application-spn.ps1`");" -ForegroundColor Yellow
        write-host "c:\azure-rm-create-aad-application-spn.ps1 -aadDisplayName powerShellRestSpn -logontype certthumb" -ForegroundColor Yellow
        write-host "output will contain clientid and clientsecret (thumbprint)"
        write-host "see for additional information https://blogs.msdn.microsoft.com/igorpag/2017/06/28/using-powershell-as-an-azure-arm-rest-api-client/"

    }
}
function get-CurrentConfig()
{
    if($thumbprint)
    {
        return convertto-json (Invoke-RestMethod -Method Get -Uri "https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups/exporttemplate" -CertificateThumbprint $thumbprint) 
    }
    else
    {
#        return convertto-json (Invoke-RestMethod -Method Get -Uri "https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups/exporttemplate" ) 
    }
}

function check-authentication()
{
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
                write-host "auth error $($error)" -ForegroundColor Yellow
                exit 1
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
                exit 1
            }
        }
}

try
{
    main
}
catch
{
    write-host "main exception $($error | out-string)"
}
finally
{
    code $outputDir
    $outputDir
    set-location $currentdir
    write-host "finished"
}