<#
  iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/addnode.ps1" -outFile "$pwd\addnode.ps1"
#>
# ------------------------------------------------------------
# Copyright (c) Microsoft Corporation.  All rights reserved.
# Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
# ------------------------------------------------------------

[CmdletBinding(DefaultParametersetName="Unsecure")] 
param (
    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $NodeName,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $NodeType,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $NodeIpAddressOrFQDN,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $ExistingClientConnectionEndpoint,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $UpgradeDomain,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$true)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [string] $FaultDomain,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [switch] $AcceptEULA,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [switch] $Force,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [switch] $NoCleanupOnFailure,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [switch] $BypassUpgradeStateValidation,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [switch] $FabricIsPreInstalled,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [string] $FabricRuntimePackagePath,

    [Parameter(ParameterSetName="Unsecure", Mandatory=$false)]
    [Parameter(ParameterSetName="Certificate", Mandatory=$false)]
    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$false)]
    [int] $TimeoutInSeconds,

    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [switch] $X509Credential,

    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [string] $ServerCertThumbprint,

    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [string] $StoreLocation,

    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [string] $StoreName,

    [Parameter(ParameterSetName="Certificate", Mandatory=$true)]
    [string] $FindValueThumbprint,

    [Parameter(ParameterSetName="WindowsSecurity", Mandatory=$true)]
    [switch] $WindowsCredential

)

$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
$IsAdmin = $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if(!$IsAdmin)
{
    Write-Host "Please run the script with administrative privileges." -ForegroundColor "Red"
    exit 1
}

if(!$AcceptEULA.IsPresent)
{
    $EulaAccepted = Read-Host 'Do you accept the license terms for using Microsoft Azure Service Fabric located in the root of your package download? If you do not accept the license terms you may not use the software.
[Y] Yes  [N] No  [?] Help (default is "N")'
    if($EulaAccepted -ne "y" -and $EulaAccepted -ne "Y")
    {
        Write-host "You need to accept the license terms for using Microsoft Azure Service Fabric located in the root of your package download before you can use the software." -ForegroundColor "Red"
        exit 1
    }
}

$ThisScriptPath = $(Split-Path -parent $MyInvocation.MyCommand.Definition)
$DeployerBinPath = Join-Path $ThisScriptPath -ChildPath "DeploymentComponents"
if(!(Test-Path $DeployerBinPath))
{
    $DCAutoExtractorPath = Join-Path $ThisScriptPath "DeploymentComponentsAutoextractor.exe"
    if(!(Test-Path $DCAutoExtractorPath)) 
    {
        Write-Host "Standalone package DeploymentComponents and DeploymentComponentsAutoextractor.exe are not present local to the script location."
        exit 1
    }

    #Extract DeploymentComponents
    $DCExtractArguments = "/E /Y /L `"$ThisScriptPath`""
    $DCExtractOutput = cmd.exe /c "`"$DCAutoExtractorPath`" $DCExtractArguments && exit 0 || exit 1"
    if($LASTEXITCODE -eq 1)
    {
        Write-Host "Extracting DeploymentComponents Cab ran into an issue."
        Write-Host $DCExtractOutput
        exit 1
    }
    else
    {
        Write-Host "DeploymentComponents extracted."
    }
}

$SystemFabricModulePath = Join-Path $DeployerBinPath -ChildPath "System.Fabric.dll"
if(!(Test-Path $SystemFabricModulePath)) 
{
    Write-Host "Run the script local to the Standalone package directory."
    exit 1
}

$MicrosoftServiceFabricCabFileAbsolutePath = $null
if ((Test-Path variable:FabricRuntimePackagePath) `
        -and ![string]::IsNullOrEmpty($FabricRuntimePackagePath))
{
    $MicrosoftServiceFabricCabFileAbsolutePath = Resolve-Path $FabricRuntimePackagePath
    if(!(Test-Path $MicrosoftServiceFabricCabFileAbsolutePath)) 
    {
        Write-Host "Microsoft Service Fabric Runtime package not found in the specified directory : $FabricRuntimePackagePath"
        exit 1
    }

    Write-Verbose "Using runtime package $MicrosoftServiceFabricCabFileAbsolutePath"
}
else
{
    $RuntimeBinPath = Join-Path $ThisScriptPath -ChildPath "DeploymentRuntimePackages"
    if(!(Test-Path $RuntimeBinPath)) 
    {
        Write-Host "No directory exists for Runtime packages. Creating a new directory."
        md $RuntimeBinPath | Out-Null
        Write-Host "Done creating $RuntimeBinPath"
    }

    Write-Verbose "Will use downloaded runtime package for deployment from $RuntimeBinPath"
}

$ServiceFabricPowershellModulePath = Join-Path $DeployerBinPath -ChildPath "ServiceFabric.psd1"

if (!(Test-Path variable:TimeoutInSeconds) `
    -or ($TimeoutInSeconds -le 0))
{
    $TimeoutInSeconds = 300
    Write-Verbose "TimeoutInSeconds was not set. Defaulting to $TimeoutInSeconds seconds."
}

$parentVerbosePreference = $VerbosePreference

# Invoke in separate AppDomain
if($X509Credential)
{
    Write-Verbose "X509Credential: $X509Credential"
    $argList = @{
        "DeployerBinPath" = $DeployerBinPath;
        "ExistingClientConnectionEndpoint" = $ExistingClientConnectionEndpoint;
        "ServiceFabricPowershellModulePath" = $ServiceFabricPowershellModulePath;
        "NodeName" = $NodeName;
        "NodeType" = $NodeType;
        "NodeIpAddressOrFQDN" = $NodeIpAddressOrFQDN;
        "UpgradeDomain" = $UpgradeDomain;
        "FaultDomain" = $FaultDomain;
        "Force" = $Force.IsPresent;
        "NoCleanupOnFailure" = $NoCleanupOnFailure.IsPresent;
        "BypassUpgradeStateValidation" = $BypassUpgradeStateValidation.IsPresent;
        "FabricIsPreInstalled" = $FabricIsPreInstalled.IsPresent;
        "MicrosoftServiceFabricCabFileAbsolutePath" = $MicrosoftServiceFabricCabFileAbsolutePath;
        "TimeoutInSeconds" = $TimeoutInSeconds;
        "parentVerbosePreference" = $parentVerbosePreference;
        "WindowsCredential" = $false;
        "X509Credential" = $true;
        "ServerCertThumbprint" = $ServerCertThumbprint;
        "StoreLocation" = $StoreLocation;
        "StoreName" = $StoreName;
        "FindValueThumbprint" = $FindValueThumbprint;
    }
}
else
{
    if($WindowsCredential)
    {
        Write-Verbose "WindowsCredential: $WindowsCredential"
        $argList = @{
            "DeployerBinPath" = $DeployerBinPath;
            "ExistingClientConnectionEndpoint" = $ExistingClientConnectionEndpoint;
            "ServiceFabricPowershellModulePath" = $ServiceFabricPowershellModulePath;
            "NodeName" = $NodeName;
            "NodeType" = $NodeType;
            "NodeIpAddressOrFQDN" = $NodeIpAddressOrFQDN;
            "UpgradeDomain" = $UpgradeDomain;
            "FaultDomain" = $FaultDomain;
            "Force" = $Force.IsPresent;
            "NoCleanupOnFailure" = $NoCleanupOnFailure.IsPresent;
            "BypassUpgradeStateValidation" = $BypassUpgradeStateValidation.IsPresent;
            "FabricIsPreInstalled" = $FabricIsPreInstalled.IsPresent;
            "MicrosoftServiceFabricCabFileAbsolutePath" = $MicrosoftServiceFabricCabFileAbsolutePath;
            "TimeoutInSeconds" = $TimeoutInSeconds;
            "parentVerbosePreference" = $parentVerbosePreference;
            "WindowsCredential" = $true;
        }
    }
    else
    {
        Write-Verbose "Not X509Credential nor WindowsCredential."
        $argList = @{
            "DeployerBinPath" = $DeployerBinPath;
            "ExistingClientConnectionEndpoint" = $ExistingClientConnectionEndpoint;
            "ServiceFabricPowershellModulePath" = $ServiceFabricPowershellModulePath;
            "NodeName" = $NodeName;
            "NodeType" = $NodeType;
            "NodeIpAddressOrFQDN" = $NodeIpAddressOrFQDN;
            "UpgradeDomain" = $UpgradeDomain;
            "FaultDomain" = $FaultDomain;
            "Force" = $Force.IsPresent;
            "NoCleanupOnFailure" = $NoCleanupOnFailure.IsPresent;
            "BypassUpgradeStateValidation" = $BypassUpgradeStateValidation.IsPresent;
            "FabricIsPreInstalled" = $FabricIsPreInstalled.IsPresent;
            "MicrosoftServiceFabricCabFileAbsolutePath" = $MicrosoftServiceFabricCabFileAbsolutePath;
            "TimeoutInSeconds" = $TimeoutInSeconds;
            "parentVerbosePreference" = $parentVerbosePreference;
        }
    }
}

if ($parentVerbosePreference -ne "SilentlyContinue")
{
    $argList.Keys | ForEach-Object { Write-Verbose "$($_)=$($argList.$_)" }
}

$standaloneArgsFilepath=Join-Path $([System.IO.Path]::GetTempPath()) "SFStandaloneArgs.txt"
if (Test-Path $standaloneArgsFilepath)
{
    Remove-Item $standaloneArgsFilepath -Force 2> $null
}

$argList.Keys | ForEach-Object { Add-Content $standaloneArgsFilepath "$($_)=$($argList.$_)" }
$standaloneArgsFilepath = Resolve-Path $standaloneArgsFilepath
$shelloutArgs = @( $standaloneArgsFilepath )

Powershell -Command {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ParamFilepath
    )

    Get-Content $ParamFilepath | Where-Object {$_.length -gt 0} | Where-Object {!$_.StartsWith("#")} | ForEach-Object {
        $var = $_.Split('=')
        if ($var.Length -eq 2)
        {
            New-Variable -Name $var[0] -Value $var[1] -Force
        }
    }

    Remove-Item $ParamFilepath -Force 2> $null

    if (![string]::IsNullOrEmpty($Force)) { $Force = [Convert]::ToBoolean($Force); } else { $Force = $false}
    if (![string]::IsNullOrEmpty($NoCleanupOnFailure)) { $NoCleanupOnFailure = [Convert]::ToBoolean($NoCleanupOnFailure); } else { $NoCleanupOnFailure = $false}
    if (![string]::IsNullOrEmpty($BypassUpgradeStateValidation)) { $BypassUpgradeStateValidation = [Convert]::ToBoolean($BypassUpgradeStateValidation); } else { $BypassUpgradeStateValidation = $false}
    if (![string]::IsNullOrEmpty($FabricIsPreInstalled)) { $FabricIsPreInstalled = [Convert]::ToBoolean($FabricIsPreInstalled); } else { $FabricIsPreInstalled = $false}
    if (![string]::IsNullOrEmpty($WindowsCredential)) { $WindowsCredential = [Convert]::ToBoolean($WindowsCredential); } else { $WindowsCredential = $false}
    if (![string]::IsNullOrEmpty($X509Credential)) { $X509Credential = [Convert]::ToBoolean($X509Credential); } else { $X509Credential = $false}
    if (![string]::IsNullOrEmpty($TimeoutInSeconds)) { $TimeoutInSeconds = [Convert]::ToInt32($TimeoutInSeconds); }

    #Add FabricCodePath Environment Path
    $env:path = "$($DeployerBinPath);" + $env:path

    #Import Service Fabric Powershell Module
    Import-Module $ServiceFabricPowershellModulePath

    Try
    {
        # Connect to the existing cluster
        Write-Verbose "Connecting to the cluster at $ExistingClientConnectionEndpoint"
        if($X509Credential)
        {
            Connect-ServiceFabricCluster -ConnectionEndpoint $ExistingClientConnectionEndpoint -X509Credential -ServerCertThumbprint $ServerCertThumbprint -StoreLocation $StoreLocation -StoreName $StoreName -FindValue $FindValueThumbprint -FindType FindByThumbprint
        }
        else
        {
            if($WindowsCredential)
            {
                Connect-ServiceFabricCluster $ExistingClientConnectionEndpoint -WindowsCredential
            }
            else
            {
                Connect-ServiceFabricCluster $ExistingClientConnectionEndpoint
            }
        }
    }
    Catch
    {
        Write-Host "Cannot form client connection to cluster. Check your ClientConnectionEndpoint and security credentials. Exception thrown : $($_.Exception.ToString())" -ForegroundColor Red
        exit 1
    }

    if ($ClusterConnection -eq $null) {
        Write-Host "Could not form client connection to cluster. Check your ClientConnectionEndpoint and security credentials." -ForegroundColor Red
        exit 1
    }

    if ($FabricIsPreInstalled)
    {
        Write-Host "Switch FabricIsPreInstalled is set, so assuming Fabric runtime is already installed on the machine."
    }
    elseif (!(Test-Path variable:MicrosoftServiceFabricCabFileAbsolutePath) `
            -or [string]::IsNullOrEmpty($MicrosoftServiceFabricCabFileAbsolutePath))
    {
        Try
        {
            # Get runtime package details
            $UpgradeStatus = Get-ServiceFabricClusterUpgrade
        }
        Catch
        {
            Write-Host "Could not query current cluster version. Check your ClientConnectionEndpoint and security credentials." -ForegroundColor Red
            exit 1
        }

        if ($UpgradeStatus.UpgradeState -ne "RollingForwardCompleted" -And $UpgradeStatus.UpgradeState -ne "RollingBackCompleted")
        {
            if ($BypassUpgradeStateValidation)
            {
                Write-Host "BypassUpgradeStateValidation is set but cannot be used without FabricRuntimePackagePath when cluster version cannot be automatically inferred from the upgrade state." -ForegroundColor Red
            }

            Write-Host "New node cannot be added to the cluster while upgrade is in progress or before cluster has finished bootstrapping. To monitor upgrade state run Get-ServiceFabricClusterUpgrade and wait until UpgradeState switches to either RollingForwardCompleted or RollingBackCompleted." -ForegroundColor Red
            exit 1
        }

        Try
        {
            $RuntimeCabFilename = "MicrosoftAzureServiceFabric." + $UpgradeStatus.TargetCodeVersion + ".cab"
            $DeploymentPackageRoot = Split-Path -parent $DeployerBinPath
            $RuntimeBinPath = Join-Path $DeploymentPackageRoot -ChildPath "DeploymentRuntimePackages"
            $MicrosoftServiceFabricCabFilePath = Join-Path $RuntimeBinPath -ChildPath $RuntimeCabFilename
                
            if (!(Test-Path $MicrosoftServiceFabricCabFilePath))
            {
                $RuntimePackageDetails = Get-ServiceFabricRuntimeSupportedVersion
                $RequiredPackage = $RuntimePackageDetails.RuntimePackages | where { $_.Version -eq $UpgradeStatus.TargetCodeVersion }
                    
                if ($RequiredPackage -eq $null)
                {
                    Write-Host "The required runtime version is no longer supported. Please upgrade your cluster to the latest version before adding a node." -ForegroundColor Red
                    exit 1
                }
                $Version = $UpgradeStatus.TargetCodeVersion
                Write-Host "Runtime package version $Version was not found in DeploymentRuntimePackages folder and needed to be downloaded."
                (New-Object System.Net.WebClient).DownloadFile($RuntimePackageDetails.GoalRuntimeLocation, $MicrosoftServiceFabricCabFilePath)
                Write-Host "Runtime package has been successfully downloaded to $MicrosoftServiceFabricCabFilePath."
            }
            $MicrosoftServiceFabricCabFileAbsolutePath = Resolve-Path $MicrosoftServiceFabricCabFilePath
        }
        Catch
        {
            Write-Host "Runtime package cannot be downloaded. Check your internet connectivity. If the cluster is not connected to the internet run Get-ServiceFabricClusterUpgrade and note the TargetCodeVersion. Run Get-ServiceFabricRuntimeSupportedVersion from a machine connected to the internet to get the download links for all supported fabric versions. Download the package corresponding to your TargetCodeVersion. Pass -FabricRuntimePackageOutputDirectory <Path to runtime package> to AddNode.ps1 in addition to other parameters. Exception thrown : $($_.Exception.ToString())" -ForegroundColor Red
            exit 1
        }
    }

    #Add Node to an existing cluster
    Try
    {
        $AddNodeTimeoutDuration=[System.TimeSpan]::FromSeconds($TimeoutInSeconds)
        $AddNodeTimeout=[System.DateTime]::UtcNow + $AddNodeTimeoutDuration

        Get-ServiceFabricNode | ft

        $VerbosePreference = $parentVerbosePreference
        $params = @{
                        'NodeName' = $NodeName;
                        'NodeType' = $NodeType;
                        'IpAddressOrFQDN' = $NodeIpAddressOrFQDN;
                        'UpgradeDomain' = $UpgradeDomain;
                        'FaultDomain' = $FaultDomain;
                        'FabricRuntimePackagePath' = $MicrosoftServiceFabricCabFileAbsolutePath;
                        'NoCleanupOnFailure' = $NoCleanupOnFailure;
                        'Force' = $Force;
                        'BypassUpgradeStateValidation' = $BypassUpgradeStateValidation;
                        'FabricIsPreInstalled' = $FabricIsPreInstalled;
                    }

        if ((Test-Path variable:TimeoutInSeconds) `
            -and ($TimeoutInSeconds -gt 0))
        {
            $params += @{'TimeoutSec' = $TimeoutInSeconds;}
        }

        Write-Host "Adding Node $NodeName"
        Add-ServiceFabricNode @params

        Write-Host "Waiting for node to join cluster." -NoNewline

        $nodeJoined=$false
        $firstRun=$true
        do
        {
            if (!$nodeJoined -and !$firstRun)
            {
                Write-Host "." -NoNewline
                Start-Sleep -s 10
            }

            $result=Get-ServiceFabricNode | Where-Object { [System.String]::Compare($_.NodeName, $NodeName, [System.StringComparison]::InvariantCulture) -eq 0 }
            $nodeJoined=$result.Count -gt 0
            $firstRun=$false
        } while(!$nodeJoined -and ([System.DateTime]::UtcNow -lt $AddNodeTimeout))

        Write-Host "" # Newline
        if(-not $nodeJoined)
        {
            Write-Host "Node did not join within timeout of $TimeoutInSeconds seconds." -ForegroundColor Red
            exit 1
        }

        Get-ServiceFabricNode | ft

        Write-Host "Node $NodeName joined the cluster!" -ForegroundColor Green
    }
    Catch
    {
        if($VerbosePreference -eq "SilentlyContinue")
        {
            Write-Host "Add Node failed. Call with -Verbose for more details" -ForegroundColor Red
        }
        Write-Host "Add node to existing cluster failed with exception: $($_.Exception.ToString())" -ForegroundColor Red
        exit 1
    }
    
} -args $shelloutArgs -OutputFormat Text

$env:Path = [System.Environment]::GetEnvironmentVariable("path","Machine")