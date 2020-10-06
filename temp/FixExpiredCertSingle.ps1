<#
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/FixExpiredCertSingle.ps1" -outFile "$pwd\FixExpiredCertSingle.ps1";
#>

param(
    $clusterDataRootPath = "D:\SvcFab", 
    $oldThumbprint = "replace with expired thumbprint", 
    $newThumbprint = "replace with new thumbprint", 
    $certStoreLocation = 'Cert:\LocalMachine\My\',
    [switch]$startService
)

$ErrorActionPreference = 'continue'
Write-Host "$env:computername : Running on $((Get-WmiObject win32_computersystem).DNSHostName)" -ForegroundColor Green

function StopServiceFabricServices {
    if ($(Get-Process | ? ProcessName -like "*FabricInstaller*" | measure).Count -gt 0) {
        Write-Warning "$env:computername : Found FabricInstaller running, may cause issues if not stopped, consult manual guide..."
        Write-Host "$env:computername : Pausing (15s)..." -ForegroundColor Green
        Start-Sleep -Seconds 15
    }

    $bootstrapAgent = "ServiceFabricNodeBootstrapAgent"
    $fabricHost = "FabricHostSvc"

    $bootstrapService = Get-Service -Name $bootstrapAgent
    if ($bootstrapService) {
        if ($bootstrapService.Status -eq "Running") {
            Set-Service $bootstrapAgent -StartupType Disabled
            Stop-Service $bootstrapAgent -ErrorAction SilentlyContinue 
            Write-Host "$env:computername : Stopping $bootstrapAgent service" -ForegroundColor Green
        }
        Do {
            Start-Sleep -Seconds 1
            $bootstrapService = Get-Service -Name $bootstrapAgent
            if ($bootstrapService.Status -eq "Stopped") {
                Write-Host "$env:computername : $bootstrapAgent now stopped" -ForegroundColor Green
            }
            else {
                Write-Host "$env:computername : $bootstrapAgent current status: $($bootstrapService.Status)" -ForegroundColor Green
            }

        } While ($bootstrapService.Status -ne "Stopped")
    }
    else {
        write-host "bootstrapagent does not exist" -ForegroundColor Yellow
    }
    
    $fabricHostService = Get-Service -Name $fabricHost

    if ($fabricHostService) {
        if ($fabricHostService.Status -eq "Running") {
            Set-Service $fabricHost -StartupType Disabled
            Stop-Service $fabricHost -ErrorAction SilentlyContinue 
            Write-Host "$env:computername : Stopping $fabricHost service" -ForegroundColor Green
        }
        Do {
            Start-Sleep -Seconds 1
            $fabricHostService = Get-Service -Name $fabricHost
            if ($fabricHostService.Status -eq "Stopped") {
                Write-Host "$env:computername : $fabricHost now stopped" -ForegroundColor Green
            }
            else {
                Write-Host "$env:computername : $fabricHost current status: $($fabricHostService.Status)" -ForegroundColor Green
            }

        } While ($fabricHostService.Status -ne "Stopped")
    }
    else {
        write-host "fabrichostservice does not exist" -ForegroundColor Yellow
    }

}

function StartServiceFabricServices {
    $bootstrapAgent = "ServiceFabricNodeBootstrapAgent"
    $fabricHost = "FabricHostSvc"

    $fabricHostService = Get-Service -Name $fabricHost

    if ($fabricHostService) {
        if ($fabricHostService.Status -eq "Stopped") {
            Set-Service $fabricHost -StartupType Manual
            Start-Service $fabricHost -ErrorAction SilentlyContinue 
            Write-Host "$env:computername : Starting $fabricHost service" -ForegroundColor Green
        }
        Do {
            Start-Sleep -Seconds 1
            $fabricHostService = Get-Service -Name $fabricHost
            if ($fabricHostService.Status -eq "Running") {
                Write-Host "$env:computername : $fabricHost now running" -ForegroundColor Green
            }
            else {
                Write-Host "$env:computername : $fabricHost current status: $($fabricHostService.Status)" -ForegroundColor Green
            }

        } While ($fabricHostService.Status -ne "Running")
    }
    else {
        write-host "fabrichostservice does not exist" -ForegroundColor Yellow
    }


    $bootstrapService = Get-Service -Name $bootstrapAgent

    if ($bootstrapService) {
        if ($bootstrapService.Status -eq "Stopped") {
            Set-Service $bootstrapAgent -StartupType Manual
            Start-Service $bootstrapAgent -ErrorAction SilentlyContinue 
            Write-Host "$env:computername : Starting $bootstrapAgent service" -ForegroundColor Green
        }
        Do {
            Start-Sleep -Seconds 1
            $bootstrapService = Get-Service -Name $bootstrapAgent
            if ($bootstrapService.Status -eq "Running") {
                Write-Host "$env:computername : $bootstrapAgent now running" -ForegroundColor Green
            }
            else {
                Write-Host "$env:computername : $bootstrapAgent current status: $($bootstrapService.Status)" -ForegroundColor Green
            }

        } While ($bootstrapService.Status -ne "Running")
    }
    else {
        write-host "bootstrapagent does not exist" -ForegroundColor Yellow
    }
}

if ($startService) {
    StartServiceFabricServices
    return
}

#config files we need
#"D:\SvcFab\clusterManifest.xml"
#"D:\SvcFab\_sys_0\Fabric\Fabric.Data\InfrastructureManifest.xml"
#"D:\SvcFab\_sys_0\Fabric\Fabric.Config.1.131523081591497214\Settings.xml"

$result = Get-ChildItem -Path $clusterDataRootPath -Filter "Fabric.Data" -Directory -Recurse
$hostPath = $result.Parent.Parent.Name
Write-Host "---------------------------------------------------------------------------------------------------------"
Write-Host "---- Working on ip:" $hostPath
Write-Host "---------------------------------------------------------------------------------------------------------"

$manifestPath = $clusterDataRootPath + "\" + $hostPath + "\Fabric\ClusterManifest.current.xml"

$currentPackage = $clusterDataRootPath + "\" + $hostPath + "\Fabric\Fabric.Package.current.xml"
$infrastructureManifest = $clusterDataRootPath + "\" + $hostPath + "\Fabric\Fabric.Data\InfrastructureManifest.xml"

#to get the settings.xml we need to determine the current version
#"D:\SvcFab\_sys_0\Fabric\Fabric.Package.current.xml" --> Read to determine verion# <ConfigPackage Name="Fabric.Config" Version="1.131523081591497214" />
$currentPackageXml = [xml](Get-Content $currentPackage)
$packageName = $currentPackageXml.ServicePackage.DigestedConfigPackage.ConfigPackage | Select-Object -ExpandProperty Name
$packageVersion = $currentPackageXml.ServicePackage.DigestedConfigPackage.ConfigPackage | Select-Object -ExpandProperty Version
$SettingsFile = $clusterDataRootPath + "\" + $hostPath + "\Fabric\" + $packageName + "." + $packageVersion + "\settings.xml"
$SettingsPath = $clusterDataRootPath + "\" + $hostPath + "\Fabric\" + $packageName + "." + $packageVersion
Write-Host "$env:computername : settings file: " $SettingsFile
Write-Host "$env:computername : Settings path: " $SettingsPath

$settings = [xml](Get-Content $SettingsFile)

#TODO: validate newThumbprint is installed
$thumbprintPath = $certStoreLocation + $newThumbprint
If (!(Test-Path $thumbprintPath)) {
    Write-Host "$env:computername : $newThumbprint not installed"
    Exit-PSSession
}

#TODO: validate newThumbprint is ACL'd for NETWORK_SERVICE
#------------------------------------------------------- start ACL
#Change to the location of the local machine certificates
$currentLocation = Get-Location
Set-Location $certStoreLocation

#display list of installed certificates in this store
Get-ChildItem | Format-Table Subject, Thumbprint, SerialNumber -AutoSize
Set-Location $currentLocation

$thumbprint = $certStoreLocation + "\" + $newThumbprint
Write-Host "$env:computername : Setting ACL for $thumbprint" -ForegroundColor Green

#get the container name
$cert = get-item $thumbprint

# Specify the user, the permissions and the permission type
$permission = "$("NETWORK SERVICE")", "FullControl", "Allow"
$accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission

# Location of the machine related keys
$keyPath = Join-Path -Path $env:ProgramData -ChildPath "\Microsoft\Crypto\RSA\MachineKeys"
$keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
$keyFullPath = Join-Path -Path $keyPath -ChildPath $keyName

# Get the current acl of the private key
$acl = (Get-Item $keyFullPath).GetAccessControl('Access')

# Add the new ace to the acl of the private key
$acl.SetAccessRule($accessRule)

# Write back the new acl
Set-Acl -Path $keyFullPath -AclObject $acl -ErrorAction Stop

# Observe the access rights currently assigned to this certificate.
get-acl $keyFullPath | Format-List
#------------------------------------------------------- done ACL

# create a temp folder
New-Item -ItemType Directory -Force -Path 'd:\temp\certwork' | out-null

#copy current config to the temp folder
Copy-Item -Path $manifestPath -Destination 'd:\temp\certwork' -Force -Verbose
$newManifest = "D:\temp\certwork\modified_clustermanifest.xml"
Copy-Item -Path $infrastructureManifest -Destination 'd:\temp\certwork' -Force -Verbose
$newInfraManifest = "D:\temp\certwork\modified_InfrastructureManifest.xml"
Copy-Item -Path $SettingsFile -Destination 'd:\temp\certwork' -Force -Verbose
$newSettingsManifest = "D:\temp\certwork\modified_settings.xml"

# find and replace old thumbprint with the new one
(Get-Content "d:\temp\certwork\clustermanifest.current.xml" |
    Foreach-Object { $_ -replace $oldThumbprint, $newThumbprint } |
    Set-Content $newManifest)

# find and replace old thumbprint with the new one
(Get-Content "d:\temp\certwork\InfrastructureManifest.xml" |
    Foreach-Object { $_ -replace $oldThumbprint, $newThumbprint } |
    Set-Content $newInfraManifest)

# find and replace old thumbprint with the new one
(Get-Content "d:\temp\certwork\settings.xml" |
    Foreach-Object { $_ -replace $oldThumbprint, $newThumbprint } |
    Set-Content $newSettingsManifest)

$backupSettingsFile = $SettingsPath + "\settings_backup.xml"
Copy-Item -Path $SettingsFile -Destination $backupSettingsFile -Force -Verbose
Copy-Item -Path $newSettingsManifest -Destination $SettingsFile -Force -Verbose

#stop these services
Write-Host "$env:computername : Stopping services " -ForegroundColor Green
StopServiceFabricServices

#update the node configuration
$logRoot = $clusterDataRootPath + "\Log"
Write-Host "$env:computername : Updating Node configuration with new cert: $newThumbprint" -ForegroundColor Green
New-ServiceFabricNodeConfiguration -FabricDataRoot $clusterDataRootPath -FabricLogRoot $logRoot -ClusterManifestPath $newManifest -InfrastructureManifestPath $newInfraManifest
Write-Host "$env:computername : Updating Node configuration with new cert: complete" -ForegroundColor Green

#restart these services
Write-Host "$env:computername : Starting services " -ForegroundColor Green

#StartServiceFabricServices
write-host "rerun script second time with -startService switch on each node after executing this script first on all nodes."