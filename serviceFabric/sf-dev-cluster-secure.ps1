<#
.SYNOPSIS
    create a secure service fabric standalone development cluster
.DESCRIPTION
    script to create a secure service fabric standalone development cluster
    devclustersetup.ps1 currently requires admin privileges and .net framework 4.7.2 so powershell.exe is used
    devclustersetup.ps1 calls certsetup.ps1 to create a self signed certificate named 'ServiceFabricDevClusterCert'
    this cert is created in the current user's personal certificate store with an exportable private key and expiration of 1 year
.PARAMETER asSecureCluster
    create a secure cluster
.PARAMETER createOneNodeCluster
    create a one node cluster
.PARAMETER devClusterScriptDir
    directory containing dev cluster setup and clean scripts
.EXAMPLE
    .\sf-dev-cluster-secure.ps1 -asSecureCluster -createOneNodeCluster
.EXAMPLE
    .\sf-dev-cluster-secure.ps1 -asSecureCluster
.EXAMPLE
    .\sf-dev-cluster-secure.ps1
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-dev-cluster-secure.ps1" -outFile "$pwd/sf-dev-cluster-secure.ps1";
    ./sf-dev-cluster-secure.ps1 -resourceGroupName <resource group name>

#>
param(
    [switch]$asSecureCluster,
    [switch]$createOneNodeCluster,
    [string]$devClusterScriptDir = 'c:\program files\microsoft sdks\service fabric\clustersetup'
)

$clusterSetupScript = 'devClusterSetup.ps1'
$clusterCleanScript = 'cleanCluster.ps1'
$devCertSubjectName = 'CN=ServiceFabricDevClusterCert'

function main() {
    try {

        if (!(test-path $devClusterScriptDir)) {
            Write-Warning "dev cluster script directory not found"
            if(!(install-sdk)){
                Write-Warning "sdk not installed."
                return
            }
        }

        if (!(test-path "$devClusterScriptDir\$clusterSetupScript")) {
            Write-Warning "dev cluster setup script not found"
            return
        }

        if (!(test-path "$devClusterScriptDir\$clusterCleanScript")) {
            Write-Warning "dev cluster clean script not found"
            return
        }

        $arguments = @(
            "-noexit",
            "-file"
            "`"$devClusterScriptDir\$clusterSetupScript`""
        )

        if($asSecureCluster){
            $arguments += "-asSecureCluster"
        }
        
        if($createOneNodeCluster){
            $arguments += "-createOneNodeCluster"
        }
    
        # have to run as admin and in powershell.exe 5.1 for .net framework 4.7.2
        write-host "start-process ``
            -verb RunAs ``
            -PassThru ``
            -WorkingDirectory `"$devClusterScriptDir`" ``
            -FilePath 'powershell.exe' ``
            -ArgumentList @($($arguments -join ' '))
        "
        $proc = start-process `
            -verb RunAs `
            -PassThru `
            -WorkingDirectory "$devClusterScriptDir" `
            -FilePath 'powershell.exe' `
            -ArgumentList $arguments

        $proc.WaitForExit()
        write-host "enumerating dev certificate"
        $cert = Get-ChildItem cert:\CurrentUser\my | where-object Subject -imatch $devCertSubjectName
        write-host "service fabric dev cluster cert: $($cert | Format-List *| out-string)" -ForegroundColor Green

        write-host "to export the dev cluster cert to pem format run the following commands:
            # pscore only
            `$cert = Get-ChildItem cert:\CurrentUser\my | where-object Subject -imatch $devCertSubjectName
            `$cert.PrivateKey.ExportRSAPrivateKeyPem()
            `$cert.ExportCertificatePem()
        "
    }
    catch {
        Write-Error $_.Exception.Message
    }
    finally {
    }
}

function install-sdk(){
    try {
        if(winget){
            if((read-host "install sdk using command 'winget install Microsoft.ServiceFabricSDK'? (y/n)") -ieq 'y') {
                winget install Microsoft.ServiceFabricSDK
                return $true
            }
            return $false
        }
        else {
            throw
        }    
    }
    catch {
        Write-Warning "winget not found. install from https://learn.microsoft.com/azure/service-fabric/service-fabric-get-started#install-the-sdk-and-tools and restart script."
        return $false
    }
}

main