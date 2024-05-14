<#
.SYNOPSIS
  This script opens a Visual Studio Developer Command Prompt in the current shell.
.DESCRIPTION
  This script opens a Visual Studio Developer Command Prompt in the current shell.
  The script imports the Visual Studio module and calls the Enter-VsDevShell function.
  The script sets the working directory to the Visual Studio installation directory.
  The script sets the working directory back to the original location after the Visual Studio Developer Command Prompt is closed.
.PARAMETER vsVersion
  The Visual Studio version to use. The default value is "2022".
.PARAMETER vsBasePath
  The Visual Studio base path. The default value is "C:\Program Files\Microsoft Visual Studio".
.EXAMPLE
  .\developer-prompt.ps1 -vsVersion "2022" -vsBasePath "C:\Program Files\Microsoft Visual Studio"
  This example opens a Visual Studio Developer Command Prompt for Visual Studio 2022.

#>
param(
  [ValidateSet("2019","2022","2017")]
  $vsVersion = "2022",
  [ValidateSet("C:\Program Files\Microsoft Visual Studio","C:\Program Files (x86)\Microsoft Visual Studio")]
  $vsBasePath = "C:\Program Files\Microsoft Visual Studio",
  [ValidateSet("Enterprise","IntPreview","Community","Professional")]
  $edition = "Enterprise"
)

function main() {
  $currentLocation = (Get-Location).Path
  $vsModulePath = "$vsBasePath\$vsVersion\$edition\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
  if (-not (Test-Path $vsModulePath)) {
    write-error "Visual Studio module not found at $vsModulePath"
    return
  }
  try {

    $workingDir = "$vsBasePath\$vsVersion\$edition\"
    Set-Location $workingDir

    write-host "Import-Module -name $vsModulePath -PassThru"
    $result = Import-Module -name $vsModulePath -PassThru

    if ($result -eq $null) {
      write-error "Failed to import module $vsModulePath"
      return
    }
    
    $error.clear()
    write-host "Enter-VsDevShell -VsInstallPath $vsBasePath\$vsVersion\$edition -SkipAutomaticLocation"
    Enter-VsDevShell -VsInstallPath $vsBasePath\$vsVersion\$edition -SkipAutomaticLocation
    if ($error) {
      write-error "Failed to enter Visual Studio Developer Command Prompt"
      return
    }

    $global:envVar = [environment]::GetEnvironmentVariables().getEnumerator()| sort-object Name
    $global:envVar
  }
  catch {
  }
  finally {
    Set-Location $currentLocation
  }
}

main