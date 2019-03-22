param(
    [PSCredential]$UserAccount,
    [string]$installScript = "$PSScriptRoot\azure-rm-dsc-sf-standalone-install.ps1",
    [string]$thumbprint,
    [string[]]$nodes,
    [string]$commonName,
    [string]$transcript
)

$configurationData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
}

configuration SFStandaloneInstall
{
    param(
        #[Parameter(Mandatory=$true)]
        #[ValidateNotNullorEmpty()]
        [PSCredential]$UserAccount,
        [string]$installScript = "$PSScriptRoot\azure-rm-dsc-sf-standalone-install.ps1",
        [string]$thumbprint,
        [string[]]$nodes,
        [string]$commonname,
        [string]$transcript = ".\transcript.log"
    )
    
    $ErrorActionPreference = "silentlycontinue"
    set-location $PSScriptRoot
    Start-Transcript -Path $transcript
        
    foreach ($key in $MyInvocation.BoundParameters.keys)
    {
        $value = (get-variable $key).Value 
        write-host "$key -> $value"
    }
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    write-host "current location: $((get-location).path)"
    write-host "useraccount: $($useraccount.username)"
    Write-host "install script:$installScript"

    Node localhost {

        User LocalUserAccount
        {
            Username = $UserAccount.UserName
            Password = $UserAccount
            Disabled = $false
            Ensure = "Present"
            FullName = "Local User Account"
            Description = "Local User Account"
            PasswordNeverExpires = $true
        }

        $credential = new-object Management.Automation.PSCredential -ArgumentList ".\$($userAccount.Username)", $userAccount.Password
        $firstNode = $false

        if($nodes[0] -imatch $env:COMPUTERNAME)
        {
            write-host "$env:COMPUTERNAME is first node."
            $firstNode = $true
        }
        else 
        {
            write-host "$env:COMPUTERNAME is not first node."
        }

        Script Install-Standalone
        {
            GetScript = { 
                    $result = $false

                    if($firstNode)
                    {
                        $result = winrm g winrm/config/client
                    }
                    else 
                    {
                        $result = ((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric").FabricVersion)
                    }
                    
                    @{ Result = $result}
            }
            SetScript = { 
                    write-host "setscript: $using:installScript -thumbprint $using:thumbprint -nodes $using:nodes -commonname $using:commonname"
                    $result = Invoke-Expression -Command ("powershell.exe -file $using:installScript -thumbprint $using:thumbprint -nodes $using:nodes -commonname $using:commonname") -Verbose -Debug
                    write-host "invoke result: $result"
                }
            TestScript = { 
                
                    if($firstNode)
                    {
                        if((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric" -ErrorAction SilentlyContinue).FabricVersion)
                        {
                            return $true
                        }
                    }
                    else 
                    {
                        return [bool](winrm g winrm/config/client) -imatch "trustedhosts = ."
                    }
                    return $false
                }
            PsDscRunAsCredential = $credential
            #[ DependsOn = [string[]] ]
        }
    }

    stop-transcript
}

if($thumbprint -and $nodes -and $commonName)
{
    write-host "sfstandaloneinstall"
    SFStandaloneInstall -useraccount $UserAccount `
        -installScript $installScript `
        -thumbprint $thumbprint `
        -nodes $nodes `
        -commonname $commonName `
        -ConfigurationData $configurationData

    # Start-DscConfiguration .\SFStandaloneInstall -wait -force -debug -verbose
}
else
{
    write-host "configuration.ps1: no args! exiting"
}
