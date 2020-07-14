<# script to setup git, hub, and vscode with common settings and extensions
to download and execute script:
iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/git-vscode-setup.ps1 -outfile $pwd\git-vscode-setup.ps1;. $pwd\git-vscode-setup.ps1
#>

param(
    [string]$gitHubDir = "c:\github",
    [string[]]$additionalExtensions = @(
        'msazurermtools.azurerm-vscode-tools',
        'eamodio.gitlens',
        'wengerk.highlight-bad-chars',
        'rsbondi.highlight-words',
        'sandcastle.vscode-open',
        'mechatroner.rainbow-csv',
        'grapeCity.gc-excelviewer',
        'ms-dotnettools.csharp',
        'ms-vscode.powershell'),
    [string]$user,
    [string]$email,
    [switch]$ssh,
    [int]$sshPort = 22
)

[io.directory]::CreateDirectory($gitHubDir)
if (!(test-path "$pwd\download-git-client.ps1")) {
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-client.ps1" -outFile  "$pwd/download-git-client.ps1";
}

$error.Clear()

if (!$user) {
 $user = [regex]::Match((whoami /fqdn), "CN=(.+?),").Groups[1].Value
}

if ($error) {
    $error.Clear()
    $user = $env:USERNAME
}

if (!$email) {
    $email = (whoami /upn)
}

if ($error) {
    $error.Clear()
    $email = "$env:USERNAME@$env:userdomain"
}

# git
$error.clear()
(git) | out-null

if ($error) {    
    .\download-git-client.ps1
}

# git config
git config --global user.name $user
git config --global user.email $email
git config --global core.editor "code --wait"

# hub git wrapper
$error.clear()
(hub) | out-null

if ($error) {
    .\download-git-client.ps1 -hub -setpath
}

Set-Location $gitHubDir

$error.clear()
(code /?) | out-null

if ($error) {
    invoke-webRequest "https://raw.githubusercontent.com/PowerShell/vscode-powershell/master/scripts/Install-VSCode.ps1" -outFile  "$pwd/Install-VSCode.ps1";
    .\Install-VSCode.ps1 -additionalExtensions @($additionalExtensions) -launchWhenDone -enableContextMenus
}

if ($ssh) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (!$isAdmin) {
        write-error "run script as admin to configure ssh"
        return
    }
    
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
}
