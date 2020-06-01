<#
.SYNOPSIS
enable ssh server port 22 for vscode remote

.LINK
to run with no arguments:
iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/enable-ssh-server.ps1" -UseBasicParsing|iex

#>

write-host "checking ssh config"
$hasSSHClient = (Get-WindowsCapability -Online | where-object Name -match 'OpenSSH.client').state -ieq "installed"
write-host "has ssh client installed: $hasSSHClient"
$hasSSHServer = (Get-WindowsCapability -Online | where-object Name -match 'OpenSSH.server').state -ieq "installed"
write-host "has ssh server installed: $hasSSHServer"

if (!$hasSSHClient) {
    write-host "installing the OpenSSH Client"
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
}

if (!$hasSSHServer) {
    write-host "installing the OpenSSH Server"
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

}

Start-Service sshd
# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'
# Confirm the Firewall rule is configured. It should be created automatically by setup. 
Get-NetFirewallRule -Name *ssh*
# There should be a firewall rule named "OpenSSH-Server-In-TCP", which should be enabled
# If the firewall does not exist, create one
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $sshPort