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
        'humao.rest-client',
        'ms-vscode.remote-server',
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
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-client.ps1" -user 'powershell' -outFile  "$pwd/download-git-client.ps1";
}

$error.Clear()

if (!$user) {
    $whoami = (whoami /fqdn)
    if ($whoami -match "CN=(.+?),") {
        $user = [regex]::Match($whoami, "CN=(.+?),").Groups[1].Value
    }
    else {
        $user = $env:USERNAME
    }
}


if (!$email) {
    $whoami = (whoami /upn)
    if ($whoami -match "CN=(.+?),") {
        $email = [regex]::Match($whoami, "CN=(.+?),").Groups[1].Value
    }
    else {
        $email = "$env:USERNAME@$env:userdomain"
    }
}

write-host "checking git"
if (!(get-command git -errorAction SilentlyContinue)) {
    write-host "git not found" -ForegroundColor Yellow
    .\download-git-client.ps1
}
else {
    write-host "git found" -ForegroundColor Green
}

if ((get-command git -errorAction SilentlyContinue)) {
    # git config
    git config --global user.name $user
    git config --global user.email $email
    git config --global core.editor "code --wait"
}
else {
    write-host "git not found. skipping config" -ForegroundColor Red
}

Set-Location $gitHubDir

write-host "checking pwsh"
if (!(get-command pwsh -errorAction SilentlyContinue)) {
    write-host "pwsh not found" -ForegroundColor Yellow
    $outputFile = "$pwd\pwsh.msi"
    $apiResults = convertfrom-json (Invoke-WebRequest $pwshReleaseApi -UseBasicParsing)
    $downloadUrl = @($apiResults.assets -imatch 'PowerShell-.+?-win-x64.msi')[0].browser_download_url
    [net.webclient]::new().DownloadFile($downloadUrl, $outputFile)
    msiexec /i $outputFile /qn /norestart
}
else {
    write-host "pwsh found" -ForegroundColor Green
}

write-host "checking vscode"
if (!(get-command code -errorAction SilentlyContinue)) {
    write-host "vscode not found" -ForegroundColor Yellow
    invoke-webRequest $vscodeScriptUrl -user 'powershell' -outFile  "$pwd/Install-VSCode.ps1";
    .\Install-VSCode.ps1 -additionalExtensions @($additionalExtensions) -launchWhenDone -enableContextMenus
}
else {
    write-host "vscode found" -ForegroundColor Green
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
