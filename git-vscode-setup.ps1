<# script to setup git, hub, and vscode with common settings and extensions
to download and execute script:
(new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/git-vscode-setup.ps1", "$pwd/git-vscode-setup.ps1");
.\git-vscode-setup.ps1
#>

param(
    [string]$gitHubDir = "c:\github",
    [string[]]$additionalExtensions = @('shan.code-settings-sync',
        'msazurermtools.azurerm-vscode-tools',
        'eamodio.gitlens',
        'wengerk.highlight-bad-chars',
        'rsbondi.highlight-words',
        'sandcastle.vscode-open',
        'mechatroner.rainbow-csv',
        'grapeCity.gc-excelviewer',
        'ms-vscode.csharp',
        'ms-vscode.powershell'),
    [string]$user,
    [string]$email
)

[io.directory]::CreateDirectory($gitHubDir)
if(!(test-path "$pwd\download-git-client.ps1")) {
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/download-git-client.ps1", "$pwd/download-git-client.ps1");
}

$error.Clear()

if(!$user){
 $user = [regex]::Match((whoami /fqdn),"CN=(.+?),").Groups[1].Value
}

if($error){
    $error.Clear()
    $user = $env:USERNAME
}

if(!$email){
    $email = (whoami /upn)
}

if($error){
    $error.Clear()
    $email = "$env:USERNAME@$env:userdomain"
}

# git
$error.clear()
(git)|out-null

if($error) {    
    .\download-git-client.ps1
}

# git config
git config --global user.name $user
git config --global user.email $email
git config --global core.editor "code --wait"

# hub git wrapper
$error.clear()
(hub)|out-null

if($error) {
    .\download-git-client.ps1 -hub -setpath
}

Set-Location $gitHubDir

$error.clear()
(code /?)|out-null

if($error) {
    (new-object net.webclient).downloadFile("https://raw.githubusercontent.com/PowerShell/vscode-powershell/master/scripts/Install-VSCode.ps1", "$pwd/Install-VSCode.ps1");
    .\Install-VSCode.ps1 -additionalExtensions @($additionalExtensions) -launchWhenDone -enableContextMenus
}
