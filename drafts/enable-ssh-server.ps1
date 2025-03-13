<#
#>
param(
  [string]$key = 'value',
  [string]$publicKeyPath = "$env:USERPROFILE\.ssh\id_rsa",
  [bool]$autoStart = $true,
  [switch]$createKey
)

function main() {
  
  # make sure admin prompt
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You need to run this script as an Administrator"
    return 1
  }

  # verify public key exists
  if (!(Test-Path -Path $publicKeyPath)) {
    # create public key if requested
    if ($createKey) {
      write-host "creating public key path $publicKeyPath"
      mkdir $publicKeyPath
      Write-Host "Creating public key at $publicKeyPath"
      write-host "ssh-keygen -t rsa -b 2048 -f $publicKeyPath -q -N `"`""
      ssh-keygen -t rsa -b 2048 -f $publicKeyPath -q -N ""
    }
    else {
      Write-Warning "Public key file not found at $publicKeyPath"
      return 1
    }
  }
  else {
    Write-Host "Public key file found at $publicKeyPath"
  }

  # make sure feature is installed
  $sshCapabilities = Get-WindowsCapability -Online | Where-Object Name -like '*OpenSSH*'
  if ($sshCapabilities -eq $null) {
    Write-Host "OpenSSH Client and Server capabilities are not installed. Installing..."
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~
  }
  else {
    Write-Host "OpenSSH Client and Server capabilities are already installed."
  }
  # make sure service is running
  $sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue
  if ($sshService -eq $null) {
    Write-Host "OpenSSH Server service is not running. Starting..."
    Start-Service sshd

    if ($autoStart) {
      write-host "Set-Service -Name sshd -StartupType 'Automatic'"
      Set-Service -Name sshd -StartupType 'Automatic'
    }
  }
  else {
    Write-Host "OpenSSH Server service is already running."
  }
  # make sure firewall rule is enabled
  $sshFirewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
  if ($sshFirewallRule -eq $null) {
    Write-Host "OpenSSH Server firewall rule is not enabled. Enabling..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
  }
  else {
    Write-Host "OpenSSH Server firewall rule is already enabled."
  }
  Write-Host "OpenSSH Server is now installed, running, and accessible."


  # Create the .ssh directory if it doesn't exist
  $sshDir = "$env:ProgramData\ssh"
  if (-Not (Test-Path -Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir
  }

  # Copy your public key to the authorized_keys file
  $authorizedKeysPath = "$sshDir\administrators_authorized_keys"
  Copy-Item -Path $publicKeyPath -Destination $authorizedKeysPath

  # Set the correct permissions for the authorized_keys file
  icacls $authorizedKeysPath /inheritance:r
  icacls $authorizedKeysPath /grant "SYSTEM:F"
  icacls $authorizedKeysPath /grant "Administrators:F"

  # Restart the sshd service to apply changes
  write-host "Restart-Service sshd"
  Restart-Service sshd
  return 0
}

main