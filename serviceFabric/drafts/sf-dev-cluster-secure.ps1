<#
script to create a secure service fabric standalone development cluster
devclustersetup.ps1 currently requires admin privileges and .net framework 4.7.2 so powershell.exe is used
devclustersetup.ps1 calls certsetup.ps1 to create a self signed certificate named 'ServiceFabricDevClusterCert'
this cert is created in the current user's personal certificate store with an exportable private key and expiration of 1 year
https://slproweb.com/download/Win64OpenSSL_Light-3_1_1.exe

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
            return
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
            $cert = get-item Cert:\CurrentUser\My | ? Subject -imatch '$devCertSubjectName'
            $bytes = $cert.GetRawCertData()
            $base64 = [System.Convert]::ToBase64String($bytes)
            out-file -append 'c:\temp\cert.pem' -inputobject '-----BEGIN CERTIFICATE-----'
            out-file -append 'c:\temp\cert.pem' -inputobject $base64
            out-file -append 'c:\temp\cert.pem' -inputobject '-----END CERTIFICATE-----'
        "
    }
    catch {
        Write-Error $_.Exception.Message
    }
    finally {
    }
}

main