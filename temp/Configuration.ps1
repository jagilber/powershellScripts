param(
    $adminUserName,
    $adminPassword,
    $installScript = ".\azure-rm-dsc-sf-standalone-install.ps1",
    $thumbPrint,
    [string[]]$nodes,
    $commonName,
    $transcript = ".\transcript.log"
)

configuration SFStandaloneInstall
{
    param(
        #[Parameter(Mandatory=$true)]
        #[ValidateNotNullorEmpty()]
        #[PSCredential]
        $adminUserName,
        $adminPassword,
        $installScript,
        $thumbPrint,
        $nodes,
        $commonname

    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    $SecurePassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force  
    $credential = new-object Management.Automation.PSCredential -ArgumentList $adminUsername, $SecurePassword
    Write-Debug $installScript
    Write-host "install script:$installScript"

    Node localhost {

        User LocalUserAccount
        {
            Username = $credential.UserName
            Password = $credential
            Disabled = $false
            Ensure = "Present"
            FullName = "Local User Account"
            Description = "Local User Account"
            PasswordNeverExpires = $true
        }

    $credential = new-object Management.Automation.PSCredential -ArgumentList ".\$adminUsername", $SecurePassword

        Script Install-Standalone
        {
            GetScript = { @{ Result = ((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric").FabricVersion)}}
            SetScript = { 
                    write-host "setscript: $using:installScript -thumbprint $using:thumbprint -nodes $using:nodes -commonname $using:commonname"
                    Invoke-Expression -Command ("$using:installScript -thumbprint $using:thumbprint -nodes $using:nodes -commonname $using:commonname")
                }
            TestScript = { 
                    if((get-itemproperty "HKLM:\SOFTWARE\Microsoft\Service Fabric" -ErrorAction SilentlyContinue).FabricVersion)
                    {
                        return $true
                    }

                    return $false
                }
            PsDscRunAsCredential = $credential
            #[ DependsOn = [string[]] ]
        }
    }
}

$configurationData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
}

$ErrorActionPreference = "silentlycontinue"
Start-Transcript -Path $transcript

foreach ($key in $MyInvocation.BoundParameters.keys)
{
    $value = (get-variable $key).Value 
    write-host "$key -> $value"
}

SFStandaloneInstall -adminUserName $adminUserName `
    -adminPassword $adminPassword `
    -installScript $installScript `
    -thumbprint $thumbPrint `
    -nodes $nodes `
    -commonname $commonName `
    -ConfigurationData $configurationData

Stop-Transcript

