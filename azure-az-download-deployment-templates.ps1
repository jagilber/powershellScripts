<#
    script to export all deployment templates, parameters, and operations from azure subscription or list of resourcegroups
    https://docs.microsoft.com/en-us/rest/api/resources/resourcegroups/exporttemplate
#>

param(
    [string]$outputDir = (get-location).path,
    [string[]]$resourceGroups,
    [string]$exportTemplateApiVersion = "2018-02-01",
    [switch]$useGit,
    [switch]$currentOnly,
    [string]$clientId = $global:clientId,
    [string]$clientSecret = $global:clientSecret,
    [switch]$vscode
)

$error.Clear()
$outputDir = $outputDir + "\armDeploymentTemplates"
$ErrorActionPreference = "silentlycontinue"
$getCurrentConfig = $clientId -and $clientSecret
$currentdir = (get-location).path
$error.Clear()
$repo = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/"
$restLogonScript = "$($currentDir)\azure-az-rest-logon.ps1"
$restQueryScript = "$($currentDir)\azure-az-rest-query.ps1"
$global:token = $Null

function main()
{
    if($currentOnly -and (!$clientId -or !$clientSecret))
    {
        write-warning "if specifying -currentOnly, -clientId and -clientSecret must be used as well. exiting..."
        return
    }

    if(!$getCurrentConfig -or !$resourceGroups -or !$currentOnly)
    {
        check-authentication
    }

    New-Item -ItemType Directory $outputDir -ErrorAction SilentlyContinue
    Get-azDeployment | Save-azDeploymentTemplate -Path $outputDir -Force
    set-location $outputDir
    write-host "using output location: $($outputDir)" -ForegroundColor Yellow

    if ($useGit)
    {
        $error.clear()
        (git)
        
        if($error)
        {
            $error.Clear()
            write-host "git not installed"
            $useGit = $false
            $error.Clear()
        }
    }
    
    if ($useGit -and !(git status))
    {
        git init
    }

    if ($resourceGroups.Count -lt 1)
    {
        $resourceGroups = @((Get-azResourceGroup).ResourceGroupName)
    }


    if (!$currentOnly)
    {
        $deployments = (Get-azResourceGroup) | Where-Object ResourceGroupName -imatch ($resourceGroups -join "|") | Get-azResourceGroupDeployment

        foreach ($dep in ($deployments | sort-object -Property Timestamp))
        {
            $rg = $dep.ResourceGroupName
            $rgDir = "$($outputDir)\$($rg)"
            New-Item -ItemType Directory $rgDir -ErrorAction SilentlyContinue

            $baseFile = "$($rgDir)\$($dep.deploymentname)"
            Save-azResourceGroupDeploymentTemplate -Path $baseFile -ResourceGroupName $rg -DeploymentName ($dep.DeploymentName) -Force
            out-file -Encoding ascii -InputObject ((convertto-json ($dep.Parameters) -Depth 99).Replace("    ", " ")) -FilePath "$($baseFile).parameters.json" -Force

            $operations = Get-azResourceGroupDeploymentOperation -DeploymentName $($dep.DeploymentName) -ResourceGroupName $rg
            out-file -Encoding ascii -InputObject ((convertto-json $operations -Depth 99).Replace("    ", " ")) -FilePath "$($baseFile).operations.json" -Force

            if ($useGit)
            {
                git add -A
                git commit -a -m "$($rg) $($dep.deploymentname) $($dep.TimeStamp) $($dep.ProvisioningState)`n$($dep.outputs | fl * | out-string)" --date (($dep.TimeStamp).ToString("o"))
            }
        }
    }

    if ($getCurrentConfig)
    {
        if (!(test-path $restLogonScript))
        {
            get-update -destinationFile $restLogonScript -updateUrl "$($repo)$([io.path]::GetFileName($restLogonScript))"
        }
      
        if (!(test-path $restQueryScript))
        {
            get-update -destinationFile $restQueryScript -updateUrl "$($repo)$([io.path]::GetFileName($restQueryScript))"
        }

        $global:token = Invoke-Expression "$($restLogonScript) -clientSecret $($clientSecret) -clientId $($clientId)" 
        $global:token
    }
    
    if ($useGit -and !(git status))
    {
        git init
    }

    if ($resourceGroups.Count -lt 1)
    {
        $resourceGroups = @((Get-azResourceGroup).ResourceGroupName)
    }

    if ($getCurrentConfig)
    {   

        foreach ($rg in $resourceGroups)
        {
            $rgDir = "$($outputDir)\$($rg)"
            New-Item -ItemType Directory $rgDir -ErrorAction SilentlyContinue
            $currentConfig = get-currentConfig -rg $rg
            #out-file -InputObject (convertto-json (get-currentConfig -rg $rg)) -FilePath "$($rgDir)\current.json" -Force
            out-file -Encoding ascii -InputObject ([Text.RegularExpressions.Regex]::Unescape((convertto-json ($currentConfig.template) -Depth 99))) -FilePath "$($rgDir)\current.json" -Force

            if ($currentConfig.error)
            {
                out-file -Encoding ascii -InputObject ([Text.RegularExpressions.Regex]::Unescape((convertto-json ($currentConfig.error) -Depth 99))) -FilePath "$($rgDir)\current.errors.json" -Force
            }

            if ($useGit)
            {
                git add -A
                git commit -a -m "$($rg) $((get-date).ToString("o"))"
            }
        }
    }
    else
    {
        write-host
        write-warning ("`nthis information does *not* include the currently running configuration, only previous uniquely named deployments.`n" `
            + "some examples are any changes made in portal after deployment or any deployment using same name (only last will be available)")
        write-host
        write-host "to get the current running configuration ('automation script' in portal), use portal, or rerun script with clientid and clientsecret"
        write-host "these are values used when connecting to azure using a script either with powershel azure modules or rest methods"
        write-host "output will contain clientid and clientsecret (thumbprint)."
        write-host "see link for additional information https://blogs.msdn.microsoft.com/igorpag/2017/06/28/using-powershell-as-an-azure-arm-rest-api-client/" -ForegroundColor Cyan
        write-host
        write-host "use this script to generate azure ad spn app with a self signed cert for use with scripts (not just this one)."
        write-host "(new-object net.webclient).downloadfile(`"https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-create-aad-application-spn.ps1`",`"$($currentDir)\azure-az-create-aad-application-spn.ps1`");" -ForegroundColor Cyan
        write-host "$($currentDir)\azure-az-create-aad-application-spn.ps1 -aadDisplayName powerShellRestSpn -logontype certthumb" -ForegroundColor Cyan
    }
}

function get-update($updateUrl, $destinationFile)
{
    write-host "downloading helper script: $($updateUrl)" -ForegroundColor Green
    $file = ""
    $git = $null

    try 
    {
        $git = Invoke-RestMethod -UseBasicParsing -Method Get -Uri $updateUrl 

        # git may not have carriage return
        # reset by setting all to just lf
        $git = [regex]::Replace($git, "`r`n", "`n")
        # add cr back
        $git = [regex]::Replace($git, "`n", "`r`n")

        if ([IO.File]::Exists($destinationFile))
        {
            $file = [IO.File]::ReadAllText($destinationFile)
        }

        if (([string]::Compare($git, $file) -ne 0))
        {
            write-host "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            write-host "script is up to date"
        }
        
        return $false
    }
    catch [System.Exception] 
    {
        write-host "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

function get-currentConfig($rg)
{
    $url = "https://management.azure.com/subscriptions/$((get-azcontext).subscription.id)/resourcegroups/$($rg)/exportTemplate?api-version=$($exportTemplateApiVersion)"
    write-host $url
    $body = "@{'options'='IncludeParameterDefaultValue, IncludeComments';'resources' = @('*')}"
    $command = "$($restQueryScript) -clientId $($clientid) -contentType `"application/json`" -query `"resourcegroups/$($rg)/exportTemplate`" -apiVersion `"$($exportTemplateApiVersion)`" -method post -body " + $body
    write-host $command 
    $results = invoke-expression $command

    if ($results.error)
    {
        write-warning (convertto-json ($results.error) -depth 99)
    }
    
    return $results
}

function check-authentication()
{
    # authenticate
    try
    {
        $tenants = @(Get-azTenant)
                        
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
            connect-azaccount
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
    if($vscode)
    {
        code $outputDir
    }

    set-location $currentdir | Out-Null
    write-host
    write-host "output location: $($outputDir)" -ForegroundColor Yellow
    write-host "finished"
}

