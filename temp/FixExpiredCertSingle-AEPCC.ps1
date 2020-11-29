<#
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/FixExpiredCertSingle-AEPCC.ps1" -outFile "$pwd\FixExpiredCertSingle-AEPCC.ps1";
#>

param(
    [ValidateNotNullOrEmpty()]
    [string]$tempPath = "d:\temp\certwork", 
    $clusterDataRootPath = "D:\SvcFab", 
    [switch]$startService
)

$ErrorActionPreference = 'continue'
Write-Host "starting" -ForegroundColor Green

<#
.SYNOPSIS
. Updating Cluster Manifest file with AEPCC Parameter  
#>
function updateManifest {            
    Write-Host "$env:computername : Begin updating ClusterManifest.xml File"
    $manFile = $tempPath + "\clustermanifest.current.xml"
    $newManifest = $tempPath + "\modified_clustermanifest.xml"
    #Checking the AEPCC property value        
    [object]$tempManAEPCC = get-content $manFile | select-string -pattern '<Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="false" />' -AllMatches

    if ($tempManAEPCC) {
        Write-Host "$env:computername : AEPCC is False"
        $intermediateManifest = $tempPath + "\intermediate_clustermanifest.xml"
        get-content $manFile | ? { $_.trim() -ne '<Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="false" />' } | set-content $intermediateManifest 
        $manFile = $intermediateManifest
    }

    $ModContent = Get-Content -Path $manFile |
    ForEach-Object {
        # Output the existing line to pipeline in any case
        $_
    
        if ($_ -match '<Section Name="Security">' ) {
            '      <Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="true" />'
        }
    }
            
    $ModContent | Out-File -FilePath $newManifest -Encoding Default -Force  
        
    Write-Host "$env:computername : Updated the ClusterManifest.xml File : $newManifest"

}
<#
.SYNOPSIS
. Updating Cluster Setting file with AEPCC Parameter  
#>

function updateSettings {       
    Write-Host "$env:computername : Begin updating Settings.xml File"
    $settingFile = $tempPath + "\Settings.xml"
    $newSettings = $tempPath + "\modified_settings.xml"

    #Checking the AEPCC property value 

    [object]$tempSettingAEPCC = get-content $settingFile | select-string -pattern '<Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="false" />' -AllMatches
    if ($tempSettingAEPCC) {
        Write-Host "$env:computername : AEPCC is False"
        $intermediateSettings = $tempPath + "\intermediate_Settings.xml"
        get-content $settingFile | ? { $_.trim() -ne '<Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="false" />' } | set-content $intermediateSettings 
        $settingFile = $intermediateSettings
    }                   

    $ModContent = Get-Content -Path $settingFile |
    ForEach-Object {             
        $_
                
        if ($_ -match '<Section Name="Security">' ) {
            '    <Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="true" />'
        }
    }

    $ModContent | Out-File -FilePath $newSettings -Encoding Default -Force
    Write-Host "$env:computername : Updated Settings.xml $newSettings"
}

<#
.SYNOPSIS
. Stopping both SFNBA and FabricHost
#>
function StopServiceFabricServices {
    if ($(Get-Process | ? ProcessName -like "*FabricInstaller*" | measure).Count -gt 0) {
        Write-Warning "$env:computername : Found FabricInstaller running, may cause issues if not stopped, consult manual guide..."
        Write-Host "$env:computername : Pausing (15s)..."
        Start-Sleep -Seconds 15
    }

    $bootstrapAgent = "ServiceFabricNodeBootstrapAgent"
    $fabricHost = "FabricHostSvc"

    $bootstrapService = Get-Service -Name $bootstrapAgent
    if ($bootstrapService.Status -eq "Running") {
        Stop-Service $bootstrapAgent -ErrorAction SilentlyContinue
        Write-Host "$env:computername : Stopping $bootstrapAgent service" 
    }
    Do {
        Start-Sleep -Seconds 1
        $bootstrapService = Get-Service -Name $bootstrapAgent
        if ($bootstrapService.Status -eq "Stopped") {
            Write-Host "$env:computername : $bootstrapAgent now stopped" 
        }
        else {
            Write-Host "$env:computername : $bootstrapAgent current status: $($bootstrapService.Status)"
        }

    } While ($bootstrapService.Status -ne "Stopped")

    $fabricHostService = Get-Service -Name $fabricHost
    if ($fabricHostService.Status -eq "Running") {
        Stop-Service $fabricHost -ErrorAction SilentlyContinue
        Write-Host "$env:computername : Stopping $fabricHost service" 
    }
    Do {
        Start-Sleep -Seconds 1
        $fabricHostService = Get-Service -Name $fabricHost
        if ($fabricHostService.Status -eq "Stopped") {
            Write-Host "$env:computername : $fabricHost now stopped" 
        }
        else {
            Write-Host "$env:computername : $fabricHost current status: $($fabricHostService.Status)"
        }

    } While ($fabricHostService.Status -ne "Stopped")
}

<#
.SYNOPSIS
. Starting both SFNBA and FabricHost
#>
function StartServiceFabricServices {
    $bootstrapAgent = "ServiceFabricNodeBootstrapAgent"
    $fabricHost = "FabricHostSvc"

    $fabricHostService = Get-Service -Name $fabricHost
    if ($fabricHostService.Status -eq "Stopped") {
        Start-Service $fabricHost -ErrorAction SilentlyContinue
        Write-Host "$env:computername : Starting $fabricHost service" 
    }
    Do {
        Start-Sleep -Seconds 1
        $fabricHostService = Get-Service -Name $fabricHost
        if ($fabricHostService.Status -eq "Running") {
            Write-Host "$env:computername : $fabricHost now running" 
        }
        else {
            Write-Host "$env:computername : $fabricHost current status: $($fabricHostService.Status)"
        }

    } While ($fabricHostService.Status -ne "Running")

    $bootstrapService = Get-Service -Name $bootstrapAgent
    if ($bootstrapService.Status -eq "Stopped") {
        Start-Service $bootstrapAgent -ErrorAction SilentlyContinue
        Write-Host "$env:computername : Starting $bootstrapAgent service" 
    }

    do {
        Start-Sleep -Seconds 1
        $bootstrapService = Get-Service -Name $bootstrapAgent
        if ($bootstrapService.Status -eq "Running") {
            Write-Host "$env:computername : $bootstrapAgent now running" 
        }
        else {
            Write-Host "$env:computername : $bootstrapAgent current status: $($bootstrapService.Status)"
        }

    } While ($bootstrapService.Status -ne "Running")
}

#config files we need
#"D:\SvcFab\ClusterManifest.current.xml"
#"D:\SvcFab\<<node name>>\Fabric\Fabric.Config.<highest version> \Settings.xml"

$result = Get-ChildItem -Path $clusterDataRootPath -Filter "Fabric.Data" -Directory -Recurse
$hostPath = $result.Parent.Parent.Name 

Write-Host "---- Node Name  :  " $hostPath 
Write-Host "---------------------------------------------------------------------------------------------------------"

$manifestPath = $clusterDataRootPath + "\" + $hostPath + "\Fabric\ClusterManifest.current.xml"
$infrastructureManifest = $clusterDataRootPath + "\" + $hostPath + "\Fabric\Fabric.Data\InfrastructureManifest.xml"

# Validating whether Manifest file already contain AEPCC parameter with true                   
[object]$tempAEPCC = get-content $manifestPath | select-string -pattern '<Parameter Name="AcceptExpiredPinnedClusterCertificate" Value="true" />' -AllMatches
        
If (!$tempAEPCC) {
    #to get the settings.xml we need to determine the current version
    #"D:\SvcFab\<node name>\Fabric\Fabric.Package.current.xml" --> Read to determine version# <ConfigPackage Name="Fabric.Config" Version="1.131523081591497214" />
    $currentPackage = $clusterDataRootPath + "\" + $hostPath + "\Fabric\Fabric.Package.current.xml"
    $currentPackageXml = [xml](Get-Content $currentPackage)
    $packageName = $currentPackageXml.ServicePackage.DigestedConfigPackage.ConfigPackage | Select-Object -ExpandProperty Name
    $packageVersion = $currentPackageXml.ServicePackage.DigestedConfigPackage.ConfigPackage | Select-Object -ExpandProperty Version
    $SettingsFile = $clusterDataRootPath + "\" + $hostPath + "\Fabric\" + $packageName + "." + $packageVersion + "\settings.xml"
    $SettingsPath = $clusterDataRootPath + "\" + $hostPath + "\Fabric\" + $packageName + "." + $packageVersion
    Write-Host "$env:computername : Settings file: " $SettingsFile
    Write-Host "$env:computername : Settings path: " $SettingsPath

    # create a temp folder
    $tempFolder = New-Item -ItemType Directory -Force -Path $tempPath 

    Write-Host "$env:computername : Created the temp Work folder :" $tempFolder

    #copy current config to the temp folder
    Copy-Item -Path $manifestPath -Destination $tempPath -Force -Verbose
    $newManifest = $tempPath + "\modified_clustermanifest.xml"
    Copy-Item -Path $SettingsFile -Destination $tempPath -Force -Verbose
    $newSettings = $tempPath + "\modified_settings.xml"            

    # Appending cluster manifest File with AcceptExpiredPinnedClusterCertificate with value true
    updateManifest

    # Appending cluster Settings File with AcceptExpiredPinnedClusterCertificate with value true
    updateSettings

    ### Backup.... 
    $backupSettingsFile = $SettingsPath + "\settings_backup.xml"
    Copy-Item -Path $SettingsFile -Destination $backupSettingsFile -Force -Verbose
    Copy-Item -Path $newSettings -Destination $SettingsFile -Force -Verbose

    #stop these services
    Write-Host "$env:computername : Stopping services"
    StopServiceFabricServices

    #update the node configuration
    $logRoot = $clusterDataRootPath + "\Log"
    Write-Host "$env:computername : Updating Node configuration with new setting AcceptExpiredPinnedClusterCertificate " 

    #For Debugging 
    Write-Host "$env:computername : Cluster Manifest $newManifest"
    Write-Host "$env:computername : Log Root $logRoot"
    Write-Host "$env:computername : Cluster Data Path  : $clusterDataRootPath"
    Write-Host "$env:computername : Infra : $infrastructureManifest"

    New-ServiceFabricNodeConfiguration -FabricDataRoot $clusterDataRootPath -FabricLogRoot $logRoot -ClusterManifestPath $newManifest -InfrastructureManifestPath $infrastructureManifest 
    Write-Host "$env:computername : Updating Node configuration complete"

    #restart these services
    Write-Host "$env:computername : Starting services "
    StartServiceFabricServices
}
else {
    Write-Host "$env:computername : Manifest File already contains the AEPCC parameter $nodeIpAddress"
}

write-host "finished"