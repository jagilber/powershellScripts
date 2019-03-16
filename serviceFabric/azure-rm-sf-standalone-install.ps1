<#
 script to install service fabric standalone in azure arm
 # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-for-windows-server

    The CleanCluster.ps1 will clean these certificates or you can clean them up using script 'CertSetup.ps1 -Clean -CertSubjectName CN=ServiceFabricClientCert'.
    Server certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\server.pfx with the password 1230909376
    Client certificate is exported to C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\Certificates\client.pfx with the password 940188492
    Modify thumbprint in C:\temp\Microsoft.Azure.ServiceFabric.WindowsServer.latest\ClusterConfig.X509.OneNode.json
#>
param(
    [switch]$remove,
    [switch]$force,
    [string]$configurationFile = ".\ClusterConfig.X509.MultiMachine.json", # ".\ClusterConfig.X509.MultiMachine.json", #".\ClusterConfig.Unsecure.DevCluster.json",
    [string]$packageUrl = "https://go.microsoft.com/fwlink/?LinkId=730690",
    [string]$packageName = "Microsoft.Azure.ServiceFabric.WindowsServer.latest.zip",
    [int]$timeout = 1200,
    [string]$diagnosticShare,
    [string]$thumbprint,
    [string]$nodes,
    [string]$commonname
)

function main()
{
    $VerbosePreference = $DebugPreference = "continue"
    $Error.Clear()
    $scriptPath = ([io.path]::GetDirectoryName($MyInvocation.ScriptName))
    $packagePath = "$(get-location)\$([io.path]::GetFileNameWithoutExtension($packageName))"
    #$downloadPath = "$packagePath\Download"
    $certPath = "$packagePath\Certificates"
    Start-Transcript -Path "$scriptPath\install.log"
    $currentLocation = (get-location).Path
    $configurationFileMod = "$([io.path]::GetFileNameWithoutExtension($configurationFile)).mod.json"

    if ($force -and (test-path $packagePath))
    {
        [io.directory]::Delete($packagePath, $true)
    }

    if (!(test-path $packagePath))
    {
        (new-object net.webclient).DownloadFile($packageUrl, "$(get-location)\$packageName")
        Expand-Archive $packageName
    }

    Set-Location $packagePath

    if(!(test-path $configurationFile))
    {
        Write-Error "$configurationFile does not exist"
        return
    }

    # verify and acl cert
    $cert = get-item Cert:\LocalMachine\My\$thumbprint
    if($cert)
    {
        write-host "found cert: $cert"
        $machineKeyFileName = [regex]::Match((certutil -store my $thumbprint),"Unique container name: (.+?)\s").groups[1].value

        if(!$machineKeyFileName)
        {
            finish-script
            return 1
        }

        #$certFile = "c:\programdata\microsoft\crypto\rsa\machinekeys\$machineKeyFileName"
        $certFile = "c:\programdata\microsoft\crypto\keys\$machineKeyFileName"
        write-host "cert file: $certFile"
        write-host "cert file: $(cacls $certFile)"

        $acl = get-acl $certFile
        $rule = new-object security.accesscontrol.filesystemaccessrule "NT AUTHORITY\NETWORK SERVICE", "Read", allow
        write-host "setting acl: $rule"
        $acl.AddAccessRule($rule)
        set-acl $certFile $acl
        write-host "acl set"
        write-host "cert file: $(cacls $certFile)"

    }
    else
    {
        write-error "unable to find cert: $thumbprint. exiting"
        finish-script
        return 1
    }

    # enable remoting
    set-netFirewallProfile -Profile Domain,Public,Private -Enabled False
    enable-psremoting
    winrm quickconfig -force -q
    winrm set winrm/config/client '@{TrustedHosts="*"}'

    # read and modify config with thumb and nodes if first node
    $nodes = $nodes.split(',')

    write-host "nodes count: $($nodes.count)"
    write-host "nodes: $($nodes)"

    if($nodes[0] -inotmatch $env:COMPUTERNAME)
    {
        Write-Warning "$env:COMPUTERNAME is not first node. exiting..."
        finish-script
        return
    }

    write-host "start sleeping $($timeout / 2) seconds"
    start-sleep -seconds ($timeout / 2)
    write-host "resuming"


    $json = Get-Content -Raw $configurationFile
    $json = $json.Replace("[Thumbprint]",$thumbprint)
    $json = $json.Replace("[IssuerCommonName]",$commonname)
    $json = $json.Replace("[CertificateCommonName]",$commonname)
    
    Out-File -InputObject $json -FilePath $configurationFileMod -Force
    # add nodes to json
    $json = Get-Content -Raw $configurationFileMod | convertfrom-json
    $nodeList = [collections.arraylist]@()
    $count = 0

    foreach($node in $nodes)
    {
        $nodeList.Add(@{
            nodeName      = $node
            iPAddress     = (@((Resolve-DnsName $node).ipaddress) -imatch "10\..+\..+\.")[0]
            nodeTypeRef   = "NodeType0"
            faultDomain   = "fd:/dc1/r$count"
            upgradeDomain = "UD$count"
        })
        
        $count++
    }

    $json.nodes = $nodeList.toarray()
    
    Out-File -InputObject ($json | convertto-json -Depth 99) -FilePath $configurationFileMod -Force

    if ($remove)
    {
        .\RemoveServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod -Force
        .\CleanFabric.ps1
    }
    else
    {
        $error.Clear()
        $result = .\TestConfiguration.ps1 -ClusterConfigFilePath $configurationFileMod
        $result

        if($result -imatch "false|fail|exception")
        {
            Write-Error "failed test: $($error | out-string)"
            return 1
        }

        .\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $configurationFileMod `
            -AcceptEULA `
            -NoCleanupOnFailure `
            -TimeoutInSeconds $timeout `
            -MaxPercentFailedNodes 0

        Connect-ServiceFabricCluster -ConnectionEndpoint localhost:19000
        Get-ServiceFabricNode |Format-Table
    }

    finish-script
}

function finish-script()
{
    Set-Location $currentLocation
    Stop-Transcript
    $VerbosePreference = $DebugPreference = "silentlycontinue"
}

main