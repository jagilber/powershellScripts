<# 
    script to setup git, hub, and vscode with common settings and extensions
    to download and execute script:
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/git-vscode-setup.ps1 -outfile $pwd\git-vscode-setup.ps1;. $pwd\git-vscode-setup.ps1

    or to just install vscode:
    [net.webclient]::new().DownloadFile('https://vscode-update.azurewebsites.net/latest/win32-x64-user/stable', $pwd\VSCodeUserSetup-x64.exe)

todo set "security.workspace.trust.untrustedFiles": "open",
#>

param(
    [string]$gitHubDir = "c:\github",
    [string[]]$additionalExtensions = @(
        'msazurermtools.azurerm-vscode-tools',
        'wengerk.highlight-bad-chars',
        'rsbondi.highlight-words',
        'sandcastle.vscode-open',
        'mechatroner.rainbow-csv',
        'ms-dotnettools.csharp',
        'ms-vscode.powershell'),
    [string]$user,
    [string]$email,
    [switch]$ssh,
    [int]$sshPort = 22,
    [string]$vscodeScriptUrl = "https://raw.githubusercontent.com/PowerShell/vscode-powershell/main/scripts/Install-VSCode.ps1",
    [string]$pwshReleaseApi = "https://api.github.com/repos/powershell/powershell/releases/latest"
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
# $error.clear()
# (hub) | out-null

# if ($error) {
#     .\download-git-client.ps1 -hub -setpath
# }

Set-Location $gitHubDir

$error.clear()
(pwsh /?) | out-null

if ($error) {
    $outputFile = "$pwd\pwsh.msi"
    $apiResults = convertfrom-json (Invoke-WebRequest $pwshReleaseApi -UseBasicParsing)
    $downloadUrl = @($apiResults.assets -imatch 'PowerShell-.+?-win-x64.msi')[0].browser_download_url
    [net.webclient]::new().DownloadFile($downloadUrl, $outputFile)
    msiexec /i $outputFile /qn /norestart
}

$error.clear()
(code /?) | out-null

if ($error) {
    invoke-webRequest $vscodeScriptUrl -outFile  "$pwd/Install-VSCode.ps1";
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
