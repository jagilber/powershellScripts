<#  
.SYNOPSIS  
    ARA powershell script ValidateRemoteAppImage to validate OS image before sysprep

.DESCRIPTION  
	Azure RemoteApp validation script for customer supplied image to be run before sysprep.
	Only Windows 2012 r2 is supported in Azure RemoteApp for collection VM.
	Before uploading image, install all rollups and applicable hotfixes.
	Refer to http://support.microsoft.com/kb/2933664/EN-US for RDS hotfix list.

.NOTES  
   File Name  : Upload-goldImage.ps1  
   Author     : ajayku
   Version    : 160426
                
   History    : current 

.EXAMPLE
    .\Upload-GoldImage.ps1 -validateCurrentOS
    use validateCurrentOS switch to verify image is ready for sysprep

.PARAMETER uri
	URI to base image blob in Azure Blog Storage
	$vhdContext = Add-AzureVhd -Destination ($uri+$sas) -LocalFilePath $vhdPath

.PARAMETER sas
	Shared Access Signarture (SAS)
	$vhdContext = Add-AzureVhd -Destination ($uri+$sas) -LocalFilePath $vhdPath

.PARAMETER validateCurrentOS
    use validateCurrentOS switch to verify image is ready for sysprep

.PARAMETER force
	bypasses sysprep confirmation prompt

	#>
param(
    [Parameter(Mandatory=$true, ParameterSetName="UploadVhd")]
    [string] $uri,

    [Parameter(Mandatory=$true, ParameterSetName="UploadVhd")] 
    [string] $sas,

    [Parameter(Mandatory=$false, ParameterSetName="UploadVhd")]
    [string] $vhdPath = $null,

    [Parameter(Mandatory=$true, ParameterSetName="ValidateCurrentOS")] 
    [switch] $validateCurrentOS,

    [Parameter(Mandatory=$false, ParameterSetName="ValidateCurrentOS")] 
    [Parameter(Mandatory=$false, ParameterSetName="UploadVhd")] 
    [switch] $Force
)


#############################
# Localization string names #
#############################

$SuccessfullyMountedVhdScriptText            =    "SuccessfullyMountedVhdScriptText"
$FailedToMountVhdScriptError                 =    "FailedToMountVhdScriptError"
$SuccessfullyUnmountedVhdScriptText          =    "SuccessfullyUnmountedVhdScriptText"
$UnsupportedOsScriptError                    =    "UnsupportedOsScriptError"
$UnsupportedOsSkuScriptError                 =    "UnsupportedOsSkuScriptError"
$UnsupportedOsEditionScriptError             =    "UnsupportedOsEditionScriptError"
$ImageIsntGeneralizedScriptError             =    "ImageIsntGeneralizedScriptError"
$FailedToReadAppServerRegistryKeyScriptError =    "FailedToReadAppServerRegistryKeyScriptError"
$RdshRoleNotInstalledScriptError             =    "RdshRoleNotInstalledScriptError"
$NotRemoteAppReadyImageScriptError           =    "NotRemoteAppReadyImageScriptError"
$NotInAzurePowershellEnvironmentScriptError  =    "NotInAzurePowershellEnvironmentScriptError"
$StartingImageUploadScriptText               =    "StartingImageUploadScriptText"
$ImageUploadCompleteScriptText               =    "ImageUploadCompleteScriptText"
$MountingVhdScriptText                       =    "MountingVhdScriptText"
$NotRunningAsAdminScriptError                =    "NotRunningAsAdminScriptError"
$NoOsFoundOnTemplateImage                    =    "NoOsFoundOnTemplateImage"
$MultipleOsFoundOnTemplateImage              =    "MultipleOsFoundOnTemplateImage"
$SysprepVmModeNotSupported                   =    "SysprepVmModeNotSupported"
$UnattendFileError                           =    "UnattendFileError"
$NumberOfWindowsVolumes                      =    "NumberOfWindowsVolumes"
$HiveUnloadSuccess                           =    "HiveUnloadSuccess"
$HiveUnloadFailure                           =    "HiveUnloadFailure"
$CurrentVmModeValue                          =    "CurrentVmModeValue"
$NtfsDisableEncryptionError                  =    "NtfsDisableEncryptionError"
$ImportingAzureModuleScriptText              =    "ImportingAzureModuleScriptText"
$ImportingStorageModuleScriptText            =    "ImportingStorageModuleScriptText"
$FailedToLoadAzureModuleError                =    "FailedToLoadAzureModuleError"
$FailedToLoadStorageModuleError              =    "FailedToLoadStorageModuleError"
$IncompatibleAzurePowerShellModuleError      =    "IncompatibleAzurePowerShellModuleError"
$AzureDotNetSdkNotInstalledError             =    "AzureDotNetSdkNotInstalledError"
$RdpInitVersionInfo                          =    "RdpInitVersionInfo"
$FailedRdpInitVersion                        =    "FailedRdpInitVersion"   
$RdpInitVersionCheckSuccess                  =    "RdpInitVersionCheckSuccess"
$ImageSizeNotMultipleOfMBs		             =    "ImageSizeNotMultipleOfMBs"
$ImageSizeGreaterThanMaxSizeLimit	         =    "ImageSizeGreaterThanMaxSizeLimit"
$ImageSizeLessThanMinSizeLimit   	         =    "ImageSizeLessThanMinSizeLimit"
$StorageModuleImportFailed                   =    "StorageModuleImportFailed"
$ImagePartitionStyleNotSupported	         =    "ImagePartitionStyleNotSupported"
$DiskPartitionStyle			                 =    "DiskPartitionStyle"
$RdcbRoleInstalledScriptError		         =	  "RdcbRoleInstalledScriptError"
$FailedToReadTssdisRegistryKeyScriptError    =	  "FailedToReadTssdisRegistryKeyScriptError"
$FailedToFindMountedDriveVhd                 =    "FailedToFindMountedDriveVhd"
$ClientMachineRunningOnDownlevelOs           =    "ClientMachineRunningOnDownlevelOs"
$FailedToGetVolumeListError                  =    "FailedToGetVolumeListError"
$CurrentOsCheckSuccess                       =    "CurrentOsCheckSuccess"

#######################
# Localization tables #
#######################

$LocalizationTable_en = @{
$SuccessfullyMountedVhdScriptText            =    "Successfully mounted the VHD.";
$FailedToMountVhdScriptError                 =    "Could not mount the specified VHD.";
$SuccessfullyUnmountedVhdScriptText          =    "Successfully detached the VHD.";
$UnsupportedOsScriptError                    =    "The template image must be created using Windows Server 2012 R2 as the operating system.";
$UnsupportedOsSkuScriptError                 =    "The template image must be created using Windows Server as the operating system.";
$UnsupportedOsEditionScriptError             =    "The template image must be created using Windows Server 2012 R2 DataCenter or Standard editions. Your template image edition is {0}";
$ImageIsntGeneralizedScriptError             =    "The template image is not in a generalized state. You can use Sysprep on the image to change the template image to a generalized state.";
$FailedToReadAppServerRegistryKeyScriptError =    "Failed to read the App Server reg key:";
$RdshRoleNotInstalledScriptError             =    "The RD Session Host server role is not installed on the template image.";
$NotRemoteAppReadyImageScriptError           =    "The image does not satisfy Windows Azure RemoteApp requirements.";
$NotInAzurePowershellEnvironmentScriptError  =    "Run this script using Windows Azure PowerShell.";
$StartingImageUploadScriptText               =    "Starting image upload.";
$ImageUploadCompleteScriptText               =    "Successfully uploaded template image.";
$MountingVhdScriptText                       =    "Mounting the VHD.";
$NotRunningAsAdminScriptError                =    "This script requires elevation. Run Windows Azure PowerShell as Administrator and try again.";
$NoOsFoundOnTemplateImage                    =    "Windows Operating System could not be located on the Image Template. Please verifiy that the image has a valid Windows Operating System.";
$MultipleOsFoundOnTemplateImage              =    "The specified Template Image has multiple Windows Operating Systems installed. Please use an image which has only one Windows Operating System.";
$SysprepVmModeNotSupported                   =    "Images prepared with sysprep /mode:VM flag are not supported. Please rerun sysprep.exe without /mode:vm flag and try to upload again."
$UnattendFileError                           =    "Please make sure there are no custom unattend files on the disk. Found: "
$NumberOfWindowsVolumes                      =    "Number of volumes with Windows OS on it: "
$HiveUnloadSuccess                           =    "Successfully unloaded hive: HKLM:\{0} from the VHD."
$HiveUnloadFailure                           =    "Failed to unload registry hive HKLM:\{0} from the VHD. Please unmount the registry hive manually."
$CurrentVmModeValue                          =    "Current sysprep VM Mode value of the image is: "
$NtfsDisableEncryptionError                  =    "Please make sure Encrypting File System (EFS) is disabled on the template image you are trying to upload. In order to disable EFS, boot into a VM running with this template image, run 'Fsutil behavior set disableencryption 1' on an elevated command window and then sysprep and try uploading again"
$ImportingAzureModuleScriptText              =    "Importing Azure module..."
$ImportingStorageModuleScriptText            =    "Importing Storage module..."
$FailedToLoadAzureModuleError                =    "Failed to load Azure module. Make sure you have the latest Azure PowerShell module installed."
$FailedToLoadStorageModuleError              =    "Failed to load Storage powershell module."
$IncompatibleAzurePowerShellModuleError      =    "This version of the Azure PowerShell module is not compatible with Azure RemoteApp services. Please install Azure PowerShell module version 0.8.3 or lower and then try uploading again."
$AzureDotNetSdkNotInstalledError             =    "This script requires Azure .Net SDK installed on the system. Please install Azure SDK and then run the script from a Windows Azure PowerShell"
$RdpInitVersionInfo                          =    "RdpInit.exe version in the VHD:"
$FailedRdpInitVersion                        =    "!!!!!!!!!RdpInit.exe in the '\{0}' is not up to date. Please install KB2977219 from 'http://support.microsoft.com/kb/2977219'."
$RdpInitVersionCheckSuccess                  =    "RdpInit.exe in the '\{0}' is up to date."
$ImageSizeNotMultipleOfMBs		             =    "Size of the specified template image is not a multiple of MBs. Please upload an image whose size is a multiple of 1MB."
$ImageSizeGreaterThanMaxSizeLimit            =    "Size of the specified template image is greater than 128 GB. Please upload an image whose size is 128 GB or less."
$ImageSizeLessThanMinSizeLimit               =    "Size of the specified template image is less than 60 GB. Please upload an image whose size is 60 GB or more."
$StorageModuleImportFailed                   =    "Please close all powershell windows and try executing the script again on a new powershell window. If you are running the script from Azure powershell window, please switch to a Windows powershell window and retry."
$ImagePartitionStyleNotSupported	         =	  "The template image you are trying to upload does not have 'MBR' partition style. Please re-create the image with 'MBR' partition style and upload again."
$DiskPartitionStyle                          =    "Template image disk partitioning style is: "
$RdcbRoleInstalledScriptError				 =	  "Remote Desktop Connection Manager role seems to be installed on the template image. Please uninstall the role, sysprep the image and try uploading again."
$FailedToReadTssdisRegistryKeyScriptError	 =	  "Failed to read the Tssdis reg key on the template image"
$FailedToFindMountedDriveVhd                 =    "Failed to find mounted '\{0}' VHD drive"
$ClientMachineRunningOnDownlevelOs           =    "Client machine is running on OS lower than Windows 8.1 or Windows Server 2012 R2"
$FailedToGetVolumeListError                  =    "Failed to retrieve the list of volumes on current operating system"
$CurrentOsCheckSuccess                       =    "The current image satisfies all the requirements for Azure RemoteApp Template image."
}

###################
# Table of tables #
###################

$LocalizationTables = @{
"en" = $LocalizationTable_en;
}

###########################
# Pick localization table #
###########################

$CurrentCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
$CurrentCultureTable = $null

while($CurrentCultureTable -eq $null)
{
    if([string]::IsNullOrEmpty($CurrentCulture.Name))
    {
        $CurrentCultureTable = $LocalizationTable_en;
    }
    else
    {
        if($LocalizationTables.ContainsKey($CurrentCulture.Name))
        {
            $CurrentCultureTable = $LocalizationTables[$CurrentCulture.Name]
        }
        else
        {
            $CurrentCulture = $CurrentCulture.Parent
        }
    }
}

function Get-FileVersion
{
  param(
    [Parameter(Mandatory=$true)]
     [string]$FileName)
  
  $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FileName)
  if ([string]::IsNullOrEmpty($ver.FileVersion)) {
    return $null
  }
  
  return New-Object Version($ver.FileMajorPart, $ver.FileMinorPart, $ver.FileBuildPart, $ver.FilePrivatePart)
}


function Get-File
{   
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = "C:\"
    $OpenFileDialog.filter = "VHD files (*.vhd;*.vhdx)| *vhd; *.vhdx"
    $dialogResult = $OpenFileDialog.ShowDialog()
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Cancel)
    {
        exit
    }
    $OpenFileDialog.filename 
    Split-Path $OpenFileDialog.filename -Leaf
}

function Is-RunningAsAdmin
{
    $windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $windowsPrincipal = new-object System.Security.Principal.WindowsPrincipal($windowsIdentity)
    $administratorRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $isRunningAsAdmin = $windowsPrincipal.IsInRole($administratorRole)
    return $isRunningAsAdmin
}

function Get-AzureVersion
{
    $path = "HKLM:\SOFTWARE\Microsoft\Microsoft SDKs\ServiceHosting"
    $versions = Get-ChildItem -Path "$path" | Sort-Object -Descending
    $version = Split-Path $versions[0].Name -Leaf  
    return $version
}

function Get-VolumeList()
{
    try
    {
        $volumeInstances = Get-WmiObject -Class Win32_Volume
        foreach($volume in $volumeInstances)
        {
            if(!($global:volumeList.Contains($volume.DeviceID)))
            {
                $global:volumeList.Add($volume.DeviceID)
            }
        }
    }
    catch
    {
    }
    if ($global:volumeList.Count -gt 0) 
    {
        return $true
    }

    Write-Error($CurrentCultureTable[$FailedToGetVolumeListError])
    return $false
}

function Attach-VHD([string] $vhdfile) 
{

    $success = $true
    $diskpartOutput = [string]::Empty
    $errorOutput = [string]::Empty

    Write-Verbose "`r`n"
    Write-Verbose ($CurrentCultureTable[$MountingVhdScriptText])
    Write-Verbose "`r`n"

    # register for new drive event
    $guid = ([guid]::NewGuid()).ToString()
    Register-WmiEvent -SourceIdentifier $guid `
                    -Query "Select * From __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Volume'" `
                    -Action { if(!($global:volumeList.Contains($event.SourceEventArgs.NewEvent.TargetInstance.DeviceId))) {$global:volumeList.Add( $event.SourceEventArgs.NewEvent.TargetInstance.DeviceId )} } | Out-Null

    try 
    {
        $diskpartOutput = 
$(@"
            SELECT VDISK FILE="$vhdfile"
            ATTACH VDISK READONLY
            EXIT
"@ | diskpart)
    }
    catch
    {
        $success = $false
    }

    if ($success -eq $true)
    {
        $retry = 0

        # Sleep for a bit to make sure the event is fired!
        do
        {
            $retry++
            if($global:volumeList.Count -le 0)
            {
                Start-Sleep -Seconds 2
            }
            else
            {
                break
            }
        } while($retry -lt 15)
    }
 
    # Sleep another 5 seconds to make sure that all the drive letters are received
    Start-Sleep -Seconds 5

    Unregister-Event -SourceIdentifier $guid -Force

    # if drive letter detected, return the value
    if ($global:volumeList.Count -gt 0) 
    {
        Write-Verbose ($CurrentCultureTable[$SuccessfullyMountedVhdScriptText]);
        $result = $true
    }
    else
    {
        $result = $false
        $errorOutput = $diskpartOutput -join "`r`n"
        Write-Error([string]::Concat($CurrentCultureTable[$FailedToMountVhdScriptError], "`r`n", $errorOutput))
    }

    return $result
}


function Detach-VHD([string] $vhdfile) 
{
    try 
    {
        $result = 
$(@"
            SELECT VDISK FILE="$vhdfile"
            DETACH VDISK
            EXIT
"@ | diskpart)
    }
    catch
    {
        Write-Verbose $_
        Write-Verbose ($result -join "`r`n")
        return $false
    }
    Write-Verbose ($CurrentCultureTable[$SuccessfullyUnmountedVhdScriptText]);
}

function Test-RdpInitInVhd([string] $winVolume)
{
    $isRdpInitUpToDate = $true
    $rdpInitPathInVHD=$winVolume + "Windows\system32\RdpInit.exe"
    $tempfilename = $env:Temp + "\UploadGoldImageCheckRdpInit.exe"

    try
    {
        # Most of the powershell doesn't work with the volume path. Use the dos command copy the file and check the version.
        (cmd /c copy $rdpInitPathInVHD $tempfilename) | Out-Null
        $rdpInitVerInVHD=Get-FileVersion $tempfilename
        Write-Verbose ([string]::Format($CurrentCultureTable[$RdpInitVersionInfo]) + $rdpInitVerInVHD)
        $supportedVersion = new-Object Version(6, 3, 9600, 17211)
        if ( $rdpInitVerInVHD -lt $supportedVersion)
        {
            Write-Error([string]::Format($CurrentCultureTable[$FailedRdpInitVersion], $vhdPath))
            $isRdpInitUpToDate = $false
        }
        else
        {
            Write-Verbose ([string]::Format($CurrentCultureTable[$RdpInitVersionCheckSuccess], $vhdPath))
        }
    }

    catch
    {
        Write-Error ([string]::Format($CurrentCultureTable[$FailedToFindMountedDriveVhd], $vhdPath))
        $isRdpInitUpToDate = $false
    }

    if (Test-Path -Path $tempfilename -PathType Leaf)
    {
        Remove-Item $tempfilename
    }
    return $isRdpInitUpToDate
}

function Check-VHDSizeAndPartitionStyleRequirements([string] $vhdPath)
{
    $sizeAndPartitionStyleRequirementsSatisfied = $true

    try
    {
        $disk = Get-DiskImage $vhdPath
        # Disk size should be a multiple of 1MB
        if (($disk.Size)%(1MB) -ne 0)
        {
            Write-Error ($CurrentCultureTable[$ImageSizeNotMultipleOfMBs])
            return $false
        }
        
        # disk size should be greater than 60 GB, to avoid low disk space on the OS Disk
        if ($disk.Size -lt 60GB)
        {
            Write-Error ($CurrentCultureTable[$ImageSizeLessThanMinSizeLimit])
            $sizeAndPartitionStyleRequirementsSatisfied = $false
        }

        #disk size should be less than 128 GB, this is Azure limit for an OS disk
        if ($disk.Size -gt 128GB)
        {
            Write-Error ($CurrentCultureTable[$ImageSizeGreaterThanMaxSizeLimit])
            $sizeAndPartitionStyleRequirementsSatisfied = $false
        }

		# Get the mounted disk number
        $diskNumber = $disk.Number

        #Get the PartitionStyle for the mounted disk and ensure it's MBR
        $partitionStyle = (Get-Disk -Number $diskNumber).PartitionStyle
        Write-Verbose ($CurrentCultureTable[$DiskPartitionStyle] + $partitionStyle)

        if ($partitionStyle -ne "MBR")
		{
			Write-Error ($CurrentCultureTable[$ImagePartitionStyleNotSupported])
			$sizeAndPartitionStyleRequirementsSatisfied = $false
		}
    }
    catch
    {
        Write-Verbose $_
        $sizeAndPartitionStyleRequirementsSatisfied = $false
    } 
    return $sizeAndPartitionStyleRequirementsSatisfied
}

function Test-WindowsVolume()
{
    $winVolumeCount = 0
    foreach( $volume in $global:volumeList)
    {
        if(Test-Path -LiteralPath ($volume + "windows\system32\config") -PathType Container)
        {
            $winVolume = $volume
            $winVolumeCount++
        }
    }

    Write-Verbose ($CurrentCultureTable[$NumberOfWindowsVolumes] + $winVolumeCount)

    if($winVolumeCount -eq 0)
    {
        Write-Error ($CurrentCultureTable[$NoOsFoundOnTemplateImage])
        return $null
    }

    if($winVolumeCount -gt 1)
    {
        Write-Error ($CurrentCultureTable[$MultipleOsFoundOnTemplateImage])
        return $null
    }

    return $winVolume
}

function Unload-Reghive([string] $vhd_hive)
{
    $regUnloadRetries = 0
    do
    {
        (reg unload ('hklm\'+$vhd_hive) 2>&1) | Out-Null
        if( (Test-Path('HKLM:\'+ $vhd_hive)) )
        {
            Start-Sleep -Seconds 1
        }
        else
        {
            Write-Verbose ([string]::Format($CurrentCultureTable[$HiveUnloadSuccess], $vhd_hive))
            return
        }
    } while( $regUnloadRetries++ -lt 30 )

    if( (Test-Path('HKLM:\'+ $vhd_hive)) )
    {
        Write-Error ([string]::Format($CurrentCultureTable[$HiveUnloadFailure], $vhd_hive))
    }
}

function Test-MohoroImageRequirements()
{
    $validImage = $true

    $global:volumeList = New-Object System.Collections.Generic.List[string]

    #get list of current volumes if validating current OS
    if ($validateCurrentOS)
    {
        if($false -eq (Get-VolumeList))
        {
            return $false
        }
    }
    #else get the mounted volume list from the VHD
    elseif($false -eq (Attach-VHD($vhdPath)))
    {
        return $false
    }

    $winVolume = Test-WindowsVolume
    
    if( $null -eq ($winVolume) )
    {
        if(!($validateCurrentOS))
        {
            Detach-VHD($vhdPath)
        }
        return $false
    }

    #check VHD size and partitioning style if uploading a VHD
    if (!($validateCurrentOS) -and ($IsStorageModuleAvailable))
    {
       if ($false -eq (Check-VHDSizeAndPartitionStyleRequirements($vhdPath)))
       {
           Detach-VHD($vhdPath)
           return $false
       }
    }

    $validImage = Test-RdpInitInVhd($winVolume)

    # use current OS registry hive if validating current OS
    # else load software reg hive from the mounted VHD's volume
    if($validateCurrentOS)
    {
        $vhd_hive = 'SOFTWARE'
    }
    else
    {
        $vhd_hive = 'vhd_sft'
        (reg load ('hklm\'+$vhd_hive) ($winVolume + "windows\system32\config\SOFTWARE") 2>&1) | Out-Null
    }

    # verify Windows Server 2012 R2 (Blue) image
    $osVer = (Get-ItemProperty ('HKLM:\'+ $vhd_hive + '\Microsoft\Windows NT\CurrentVersion') CurrentVersion).CurrentVersion
    if ($osVer -ne '6.3')
    {
        Write-Error ($CurrentCultureTable[$UnsupportedOsScriptError])
        $validImage = $false;
    }

    Remove-Variable osVer

    # verify it is server
    $osInstallationType = (Get-ItemProperty ('HKLM:\'+ $vhd_hive + '\Microsoft\Windows NT\CurrentVersion') InstallationType).InstallationType
    if ($osInstallationType -ne 'Server')
    {
        Write-Error ($CurrentCultureTable[$UnsupportedOsSkuScriptError])
        $validImage = $false;
    }

    Remove-Variable osInstallationType

    # verify Standard or DataCenter edition
    $edition = (Get-ItemProperty ('HKLM:\'+ $vhd_hive + '\Microsoft\Windows NT\CurrentVersion') EditionID).EditionID
    if (!($edition.Contains( 'Datacenter') -or $edition.Contains( 'Standard')))
    {
        Write-Error ([string]::Format($CurrentCultureTable[$UnsupportedOsEditionScriptError], $edition))
        $validImage = $false;
    }

    Remove-Variable edition

    #skip sysprep checks if validating current OS
    if(!($validateCurrentOS))
    {

        # verify sysprep state
        $sysprepState = (Get-ItemProperty ('HKLM:\'+ $vhd_hive + '\Microsoft\Windows\CurrentVersion\Setup\State') ImageState).ImageState
        if($sysprepState -ne "IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE")
        {
            Write-Error ($CurrentCultureTable[$ImageIsntGeneralizedScriptError])
            $validImage = $false;
        }

        Remove-Variable sysprepState

        # verify sysprep vm mode
        $oobeRegKeyPath = ('HKLM:\'+ $vhd_hive + '\Microsoft\Windows\CurrentVersion\Setup\OOBE')
        $sysprepVmMode = (Get-ItemProperty $oobeRegKeyPath SysprepSetVMMode -ErrorAction SilentlyContinue).SysprepSetVMMode

        if ($sysprepVmMode)
        {
            Write-Verbose ($CurrentCultureTable[$CurrentVmModeValue] + $sysprepVmMode)
        }

        if($sysprepVmMode -eq 1)
        {
            Write-Error ($CurrentCultureTable[$SysprepVmModeNotSupported])
            $validImage = $false
        }

        Remove-Variable sysprepVmMode

        # unload software reg hive
        [GC]::Collect()

        Unload-Reghive($vhd_hive)
    }

    # use current OS registry hive if validating current OS
    # else load software reg hive from the mounted VHD's volume
    if($validateCurrentOS)
    {
        $vhd_hive = 'SYSTEM'
    }
    else
    {
        $vhd_hive = 'vhd_sys'
        (reg load ('hklm\'+$vhd_hive) ($winVolume + "windows\system32\config\SYSTEM") 2>&1) | Out-Null
    }

    # verify if RDSH role and Desktop experince is installed
    $appCompat=$null
    try
    {
        $appCompat = (Get-ItemProperty ('HKLM:\'+ $vhd_hive + '\ControlSet001\Control\Terminal Server') TSAppCompat ).TSAppCompat
    }
    catch
    {
        Write-Verbose($CurrentCultureTable[$FailedToReadAppServerRegistryKeyScriptError] + $_.Exception.Message)
    }
    if(-not($appCompat))
    {
        Write-Error ($CurrentCultureTable[$RdshRoleNotInstalledScriptError])
        $validImage = $false;
    }

    Remove-Variable appCompat
	
    # verify if sysprep unattend registry key is set
    $unattendRegPath = ('HKLM:\'+ $vhd_hive + '\Setup')
    $unattendReg = (Get-ItemProperty $unattendRegPath UnattendFile -ErrorAction SilentlyContinue).UnattendFile 

    if ($unattendReg)
    {
        Write-Error ($CurrentCultureTable[$UnattendFileError])
        $validImage = $false;
    }

    Remove-Variable unattendReg

    # verify if efs is disabled
    $fileSystemRegPath = ('HKLM:\'+ $vhd_hive + '\ControlSet001\Control\FileSystem')
    $ntfsDisableEncryptionReg = (Get-ItemProperty $fileSystemRegPath NtfsDisableEncryption -ErrorAction SilentlyContinue).NtfsDisableEncryption 

    if ($ntfsDisableEncryptionReg -eq 0)
    {
        Write-Error ($CurrentCultureTable[$NtfsDisableEncryptionError])
        $validImage = $false;
    }

    Remove-Variable ntfsDisableEncryptionReg

	#verify that RDCB role is not installed
	$rdcbIsInstalled = $false
	$tssdisRegKeyValue = ""
	try
	{
 		$tssdisRegKeyValue = Get-Item ('HKLM:\' + $vhd_hive + '\ControlSet001\Services\Tssdis') -ErrorAction Stop
		$rdcbIsInstalled = $true
	}
	catch
	{
		if ($_.Exception.GetType().ToString() -ne "System.Management.Automation.ItemNotFoundException")
		{
			Write-Verbose($CurrentCultureTable[$FailedToReadTssdisRegistryKeyScriptError] + $_.Exception.Message)
		}
	}
    if ($rdcbIsInstalled)
    {
	   Write-Error ($CurrentCultureTable[$RdcbRoleInstalledScriptError])
	   $validImage = $false;
    }

    Remove-Variable tssdisRegKeyValue

    # unload system reg hive
    [GC]::Collect()

    if(!($validateCurrentOS))
    {
        Unload-Reghive($vhd_hive)
    }

    # verify unattend file locations
    if(Test-Path -LiteralPath ($winVolume + "windows\Panther\Unattend\Unattend.xml") -PathType Leaf)
    {
        if($validateCurrentOS)
        {
            Remove-Item -Path ($winVolume + "windows\Panther\Unattend\Unattend.xml")
        }
        else
        {
            Write-Error ($CurrentCultureTable[$UnattendFileError] + " $winDrive\windows\Panther\Unattend\Unattend.xml.")
            $validImage = $false
        }
    }

    if(Test-Path -LiteralPath ($winVolume + "windows\Panther\Unattend\Autounattend.xml") -PathType Leaf)
    {
        Write-Error ($CurrentCultureTable[$UnattendFileError] + " $winDrive\windows\Panther\Unattend\Autounattend.xml.")
        $validImage = $false
    }

    if(Test-Path -LiteralPath ($winVolume + "windows\Panther\Unattend.xml") -PathType Leaf)
    {
        if($validateCurrentOS)
        {
            Remove-Item -Path ($winVolume + "windows\Panther\Unattend.xml")
        }
        else
        {
            Write-Error ($CurrentCultureTable[$UnattendFileError] + " $winDrive\windows\Panther\Unattend.xml.")
            $validImage = $false
        }
    }

    if(Test-Path -LiteralPath ($winVolume + "windows\Panther\Autounattend.xml") -PathType Leaf)
    {
        Write-Error ($CurrentCultureTable[$UnattendFileError] + " $winDrive\windows\Panther\Autounattend.xml.")
        $validImage = $false
    }

    if(Test-Path -LiteralPath ($winVolume + "Unattend.xml") -PathType Leaf)
    {
        if($validateCurrentOS)
        {
            Remove-Item -Path ($winVolume + "Unattend.xml")
        }
        else
        {
            Write-Error ($CurrentCultureTable[$UnattendFileError] + " Found: $winDrive\Unattend.xml.")
            $validImage = $false
        }
    }

    if(Test-Path -LiteralPath ($winVolume + "Autounattend.xml") -PathType Leaf)
    {
        Write-Error ($CurrentCultureTable[$UnattendFileError] + " $winDrive\Autounattend.xml.")
        $validImage = $false
    }

    # detach VHD
    if(!($validateCurrentOS))
    {
        Detach-VHD($vhdPath)
    }

    return $validImage
}

###############
# Main script #
###############


$verbosepreference='continue';

$isRunningAsAdmin = Is-RunningAsAdmin
if (!($isRunningAsAdmin))
{
    Write-Error ($CurrentCultureTable[$NotRunningAsAdminScriptError])
    return
}
if(!($validateCurrentOS))
{
    #Get OS Version of the machine where this script is running
    $IsStorageModuleAvailable = $false
    $CurrentVersionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $OsVersion = (Get-ItemProperty -Path $CurrentVersionKey -Name CurrentVersion).CurrentVersion
    if ($OsVersion -ge 6.3)
    {
       $IsStorageModuleAvailable = $true
    }
    else
    {
       Write-Verbose ($CurrentCultureTable[$ClientMachineRunningOnDownlevelOs])
    }

    if ($IsStorageModuleAvailable)
    {
       #Import storage module and make sure it loaded correctly
       Write-Verbose ($CurrentCultureTable[$ImportingStorageModuleScriptText])
       try
       {
          Import-Module "Storage"
       }
       catch
       {
          Write-Error($CurrentCultureTable[$StorageModuleImportFailed])
          return
       }

       $storageModule = get-module "Storage"
       if($null -eq ($storageModule))
       {
           Write-Error ($CurrentCultureTable[$FailedToLoadStorageModuleError])
           return
       }
    }

    # Import Azure module and make sure azure module is loaded
    Write-Verbose ($CurrentCultureTable[$ImportingAzureModuleScriptText])
    Import-Module "azure"
    $azmodule = get-module "azure" 
    if($null -eq ($azmodule))
    {
        Write-Error ($CurrentCultureTable[$FailedToLoadAzureModuleError])
        return
    }

    if ([string]::IsNullOrEmpty($vhdPath))
    {
        $vhdPaths = Get-File
        $vhdPath = $vhdPaths[0]
    }
}

function Confirm-Sysprep()
{
    if($Force)
    {
        return 0
    }

    $title = "Launch Sysprep?"
    $message = 'Please select "Yes" if you have completed all the customizations on this machine. Caution: Selecting "Yes" will start sysprep generalize command and automatically shut down this machine.'

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
        "Yes"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
        "No"

    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)

    $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

    $result
}

$validImage = Test-MohoroImageRequirements

if(!($validImage))
{
    Write-Error ($CurrentCultureTable[$NotRemoteAppReadyImageScriptError])
    return
}

if($validateCurrentOS)
{
    Write-Host($CurrentCultureTable[$CurrentOsCheckSuccess])
    if((Confirm-Sysprep) -eq 0)
    {
        Start-Process -FilePath ($env:windir + "\system32\sysprep\sysprep.exe") -ArgumentList "/generalize /oobe /shutdown"
    }
    return
}

Write-Output $CurrentCultureTable[$StartingImageUploadScriptText]
$vhdContext = Add-AzureVhd -Destination ($uri+$sas) -LocalFilePath $vhdPath
if($null -ne $vhdContext)
{
    # no need to load the storage lib, as it is already loaded by azure PS
    $sasCred = New-Object Microsoft.WindowsAzure.Storage.Auth.StorageCredentials($sas)
    $imageBlob = New-Object Microsoft.WindowsAzure.Storage.Blob.CloudPageBlob($uri, $sasCred)

    $imageBlob.Metadata["Status"] = "UploadComplete"
    $imageBlob.SetMetadata()
    $vhdContext
    Write-Output $CurrentCultureTable[$ImageUploadCompleteScriptText]
}

