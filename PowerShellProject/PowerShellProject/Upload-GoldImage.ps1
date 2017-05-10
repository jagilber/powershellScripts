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

# SIG # Begin signature block
# MIIaxQYJKoZIhvcNAQcCoIIatjCCGrICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoC8VIPtl/suuZLndxki2FzP3
# CWegghWCMIIEwzCCA6ugAwIBAgITMwAAAJzu/hRVqV01UAAAAAAAnDANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwMzMwMTkyMTMw
# WhcNMTcwNjMwMTkyMTMwWjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjU4NDctRjc2MS00RjcwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzCWGyX6IegSP
# ++SVT16lMsBpvrGtTUZZ0+2uLReVdcIwd3bT3UQH3dR9/wYxrSxJ/vzq0xTU3jz4
# zbfSbJKIPYuHCpM4f5a2tzu/nnkDrh+0eAHdNzsu7K96u4mJZTuIYjXlUTt3rilc
# LCYVmzgr0xu9s8G0Eq67vqDyuXuMbanyjuUSP9/bOHNm3FVbRdOcsKDbLfjOJxyf
# iJ67vyfbEc96bBVulRm/6FNvX57B6PN4wzCJRE0zihAsp0dEOoNxxpZ05T6JBuGB
# SyGFbN2aXCetF9s+9LR7OKPXMATgae+My0bFEsDy3sJ8z8nUVbuS2805OEV2+plV
# EVhsxCyJiQIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFD1fOIkoA1OIvleYxmn+9gVc
# lksuMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAFb2avJYCtNDBNG3nxss1ZqZEsphEErtXj+MVS/RHeO3TbsT
# CBRhr8sRayldNpxO7Dp95B/86/rwFG6S0ODh4svuwwEWX6hK4rvitPj6tUYO3dkv
# iWKRofIuh+JsWeXEIdr3z3cG/AhCurw47JP6PaXl/u16xqLa+uFLuSs7ct7sf4Og
# kz5u9lz3/0r5bJUWkepj3Beo0tMFfSuqXX2RZ3PDdY0fOS6LzqDybDVPh7PTtOwk
# QeorOkQC//yPm8gmyv6H4enX1R1RwM+0TGJdckqghwsUtjFMtnZrEvDG4VLA6rDO
# lI08byxadhQa6k9MFsTfubxQ4cLbGbuIWH5d6O4wggTsMIID1KADAgECAhMzAAAB
# Cix5rtd5e6asAAEAAAEKMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE1MDYwNDE3NDI0NVoXDTE2MDkwNDE3NDI0NVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJL8bza74QO5KNZG0aJhuqVG+2MWPi75R9LH7O3HmbEm
# UXW92swPBhQRpGwZnsBfTVSJ5E1Q2I3NoWGldxOaHKftDXT3p1Z56Cj3U9KxemPg
# 9ZSXt+zZR/hsPfMliLO8CsUEp458hUh2HGFGqhnEemKLwcI1qvtYb8VjC5NJMIEb
# e99/fE+0R21feByvtveWE1LvudFNOeVz3khOPBSqlw05zItR4VzRO/COZ+owYKlN
# Wp1DvdsjusAP10sQnZxN8FGihKrknKc91qPvChhIqPqxTqWYDku/8BTzAMiwSNZb
# /jjXiREtBbpDAk8iAJYlrX01boRoqyAYOCj+HKIQsaUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSJ/gox6ibN5m3HkZG5lIyiGGE3
# NDBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# MDQwNzkzNTAtMTZmYS00YzYwLWI2YmYtOWQyYjFjZDA1OTg0MB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQCmqFOR3zsB/mFdBlrrZvAM2PfZ
# hNMAUQ4Q0aTRFyjnjDM4K9hDxgOLdeszkvSp4mf9AtulHU5DRV0bSePgTxbwfo/w
# iBHKgq2k+6apX/WXYMh7xL98m2ntH4LB8c2OeEti9dcNHNdTEtaWUu81vRmOoECT
# oQqlLRacwkZ0COvb9NilSTZUEhFVA7N7FvtH/vto/MBFXOI/Enkzou+Cxd5AGQfu
# FcUKm1kFQanQl56BngNb/ErjGi4FrFBHL4z6edgeIPgF+ylrGBT6cgS3C6eaZOwR
# XU9FSY0pGi370LYJU180lOAWxLnqczXoV+/h6xbDGMcGszvPYYTitkSJlKOGMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBK0wggSp
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAABCix5rtd5e6as
# AAEAAAEKMAkGBSsOAwIaBQCggcYwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPmd
# k8RMdALWHAdQEtJ4qmm8w1u/MGYGCisGAQQBgjcCAQwxWDBWoCqAKABVAHAAbABv
# AGEAZAAtAEcAbwBsAGQASQBtAGEAZwBlAC4AcABzADGhKIAmaHR0cHM6Ly93d3cu
# cmVtb3RlYXBwLndpbmRvd3NhenVyZS5jb20wDQYJKoZIhvcNAQEBBQAEggEAXUXx
# /HQ/EESHbS6kZBf66JvQ9tAw0lfk81dMgRHZT1jv8BWByqGBhndSFXzZgbfcbjLq
# s4UT6iGBS+VK+i33W6/vPgvottCcE++VyN9tlw3JZ7+lNLuv1JoXyO7yO1TGKh0e
# leWEraP3+bNCH+Ly6eGce5k9AwGiSwFXooYBcuW6JIupNR90OB9SlJC9zA383VCa
# G18SG0q+lQSMuigyMBW1h7igi3EsTHftLRFspHuGer/sKkRDD3uZbKedHpVos0Rx
# zv+sMIRGBnpwstER04xoLmNSNw7fPeFjxV/TBm7yMLXTZFZxf9gu57lBLCCm98hs
# yNlVFhham9477DODYaGCAigwggIkBgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhN
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0ECEzMAAACc7v4UValdNVAAAAAAAJwwCQYF
# Kw4DAhoFAKBdMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkF
# MQ8XDTE2MDUwOTEyMjM0NVowIwYJKoZIhvcNAQkEMRYEFD97tOM11UeHOTXirNo2
# LhkpIpgqMA0GCSqGSIb3DQEBBQUABIIBALADs4g9XCD+EatsCGYEUfYAoqfq0PuE
# oT+Gxo4lyYkr1aYwxU526kITHzuWditW6BQIWn3QAWjka+kVdqTv/vfK4LdaOWf4
# 8EWIs9OUk39x2/KvCFJPF+i7FvF0U71nB433Nd/HHan5ztHy7NKc0p4tJXrKfv6+
# lttg6j6k6srkAOXeZMfDXT3ZfRP2uMAG/aDPAS5Q5X1Qx7I8HiTA0XHKYEQr+z6C
# W72rvhcutrzQ5w0a7jBtsuLgWkhUL+OKq5FqVSupaKkS9pfWobs0gIGrcd/Rm4+q
# kuSZsCpnHP2QeQmqdd3Qp5ilSbnrtQlrPDKy19qiw1nu8fUKVwFyrU8=
# SIG # End signature block
