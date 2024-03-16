<#
.SYNOPSIS
    Script that maps drive to azure storage account file share.
    Similar to the 'connect' script generated from portal file share blade
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-storage-map-file-share.ps1" -outFile "$pwd\azure-storage-map-file-share.ps1";
    .\azure-storage-map-file-share.ps1 -pass '' -storageAccount '' -fileShare ''
#>

[cmdletbinding()]
param(
    [Parameter(ParameterSetName = 'pass')]
    [string]$user = "localhost",

    [Parameter(ParameterSetName = 'pass', Mandatory = $true)]
    [string]$password = $null,

    [Parameter(ParameterSetName = 'cred', Mandatory = $true)]
    [pscredential]$credentials,

    [Parameter(ParameterSetName = 'pass', Mandatory = $true)]
    [Parameter(ParameterSetName = 'cred', Mandatory = $true)]
    [string]$storageAccount = $null, # = "sflogssomething.file.core.windows.net",

    [Parameter(ParameterSetName = 'pass', Mandatory = $true)]
    [Parameter(ParameterSetName = 'cred', Mandatory = $true)]
    [string]$fileShare = $null, #= "diagnostics",

    [Parameter(ParameterSetName = 'pass')]
    [Parameter(ParameterSetName = 'cred')]
    [string]$drive = "Z",

    [Parameter(ParameterSetName = 'pass')]
    [Parameter(ParameterSetName = 'cred')]
    [bool]$persist = $false
)

#$ErrorActionPreference = "continue"
$error.Clear()

function main () {
    $hostname = $storageAccount.split('.')[0]

    if ($user -ieq 'localhost') {
        $user = "$user\$hostname"
        write-host "user:$user"
    }

    if (!$credentials) {
        $securePassword = ConvertTo-SecureString -String $password -Force -AsPlainText
        $credentials = [pscredential]::new($user, $securePassword)
    }

    write-host "Test-NetConnection -ComputerName $storageAccount -Port 445 -InformationLevel Detailed" -ForegroundColor Cyan
    $connectTestResult = Test-NetConnection -ComputerName $storageAccount -Port 445 -InformationLevel Detailed
    write-host ($connectTestResult | out-string)

    if ($connectTestResult.TcpTestSucceeded) {
        write-host "New-PSDrive -Name $drive -PSProvider FileSystem  -Persist:$persist -Root "\\$storageAccount\$fileShare" -Scope Global -Credential $credentials" -ForegroundColor Cyan
        New-PSDrive -Name $drive -PSProvider FileSystem -Persist:$persist -Root "\\$storageAccount\$fileShare" -Scope Global -Credential $credentials
    }
    else {
        Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
    }
}

main