<#  
.SYNOPSIS  
    powershell script to connect to quick start rds deployments after deployment

.DESCRIPTION  
    script authenticates to azure rm 
    queries all resource groups for public ip name
    gives list of resource groups
    enumerates public ip of specified resource group
    downloads certificate from RDWeb
    adds cert to local machine trusted root store
    tries to resolve subject name in dns
    if not the same as public loadbalancer ip address it is added to hosts file
 
.NOTES  
   File Name  : art-rds-post-deploy.ps1
   Version    : 161024 fixed -noretry command
   History    : original

.EXAMPLE  
    .\art-rds-post-deploy.ps1
    query azure rm for all resource groups with ip name containing 'GWPIP' by default.
 
.PARAMETER azureResourceManagerGroup
    optional parameter to specify Resource Group Name

.PARAMETER publicIpAddressName
    optional parameter to override ip resource name 'GWPIP'
#>  
 

param(
    [Parameter(Mandatory=$false)]
    [string]$azureResourceManagerGroup,
    [Parameter(Mandatory=$false)]
    [string]$publicIpAddressName = "GWPIP",
    [Parameter(Mandatory=$false)]
    [switch]$noretry#,
    #[Parameter(Mandatory=$false)]
    #[string]$clean
)

# to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *<%subject%>* | Remove-Item
# to remove certs from all stores Get-ChildItem -Recurse -Path cert:\ -DnsName *rdsart* | Remove-Item
# Get-AzureRmResourceGroup | Get-AzureRmResourceGroupDeployment | Get-AzureRmResourceGroupDeploymentOperation

$hostsFile = "$($env:windir)\system32\drivers\etc\hosts"

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    cls
    $error.Clear()
    $resourceList = @{}
    $rg = $null
    $subject = $null
    $certInfo = $null

    runas-admin

    # authenticate
    try
    {
        Get-AzureRmResourceGroup | Out-Null
    }
    catch
    {
        Add-AzureRmAccount
    }

    # find resource group
    if([string]::IsNullOrEmpty($azureResourceManagerGroup))
    {
        write-host "resource groups with public IP address containing name $($publicIpAddressName):"
        $rgs = Get-AzureRmResourceGroup 
        $count = 1
        foreach($rgn in $rgs)
        {
            if(![string]::IsNullOrEmpty((query-publicIp -resourceName $rgn.ResourceGroupName -ipName $publicIpAddressName)))
            {
                write-host "$($count). $($rgn.ResourceGroupName)"
                $resourceList.Add($count,$rgn.ResourceGroupName)
                $count++
            }

        }

        [int]$id = Read-Host ("Enter number for resource group to enumerate:")
        $rg = Get-AzureRmResourceGroup -Name $resourceList[$id]
        write-host $rg.ResourceGroupName
    }
    else
    {
        $rg = Get-AzureRmResourceGroup -Name $azureResourceManagerGroup
    }

    # enumerate resource group
    write-host "provision state: $($rg.ProvisioningState)"
    
    # find public ip from loadbalancer
    $ip = query-publicIp -resourceName $rg.ResourceGroupName -ipName $publicIpAddressName

    if(![string]::IsNullOrEmpty($ip.IpAddress))
    {
        write-host "public loadbalancer ip address: $($ip.IpAddress)"
        $gatewayUrl = "https://$($ip.IpAddress)/RDWeb"

        # get certificate from RDWeb site
        $cert = get-cert -url $gatewayUrl -fileName "$($rg.ResourceGroupName).cer"
        $subject = $cert.Subject.Replace("CN=","")   
        
        if(![string]::IsNullOrEmpty($subject))
        {
            # see if cert needs to be imported
            if((Get-ChildItem -Recurse -Path cert:\ -DnsName "$($subject)").Count -lt 1)
            {
                write-host "importing certificate:$($subject) into localmachine root"
                $certInfo = Import-Certificate -FilePath "$($rg.ResourceGroupName).cer" -CertStoreLocation Cert:\LocalMachine\Root
            }
            else
            {
                write-host "certificate already installed $($subject)"
            }
    
            # see if it needs to be added to hosts file
            $dnsresolve = (Resolve-DnsName -Name $subject).IPAddress
            if($ip.IpAddress -ne $dnsresolve)
            {
                write-host "$($ip.IpAddress) not same as $($dnsresolve), checking hosts file"
                
                # add to hosts file
                [string]$hostFileInfo = [IO.File]::ReadAllText($hostsFile)
                
                if($hostFileInfo -inotmatch $subject)
                {
                    $newEntry = "$($ip.IpAddress)`t$($subject)`n"
                    write-host "adding new entry:$($newEntry)"
                
                    [IO.File]::AppendAllText($hostsFile,$newEntry)
                    type $hostsFile
                }
            }
            else
            {
                write-host "dns resolution for $($subject) same as loadbalancer ip:$($ip.IpAddress)"
            }
    
            # launch RDWeb site
            Start-Process "https://$($subject)/RDWeb"
        }
    }

    write-host "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function query-publicIp([string] $resourceName, [string] $ipName)
{
    $count = 0
    $returnList = New-Object Collections.ArrayList
    $ips = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceName
    
    foreach($ip in $ips)
    {
        if($ip.Name -imatch $ipName)
        {
            return $ip
        }
                
    }

    return $null
}

# ----------------------------------------------------------------------------------------------------------------
function get-cert([string] $url,[string] $fileName)
{
    $webRequest = [Net.WebRequest]::Create($url)
    
    try
    { 
        $webRequest.GetResponse() 
    }
    catch {}

    $cert = $webRequest.ServicePoint.Certificate
    $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)

    if($bytes.Length -gt 0)
    {
        if([IO.File]::Exists($fileName))
        {
            [IO.File]::Delete($fileName)
        }

        set-content -value $bytes -encoding byte -path $fileName
        $crt = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $crt.Import($fileName)
        return $crt
    }

    return $null
}

# ----------------------------------------------------------------------------------------------------------------
function run-process([string] $processName, [string] $arguments, [bool] $wait = $false)
{
    write-host "Running process $processName $arguments"
    $exitVal = 0
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $true
    $process.StartInfo.RedirectStandardOutput = $false
    $process.StartInfo.RedirectStandardError = $false
    $process.StartInfo.FileName = $processName
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.CreateNoWindow = $false
    $process.StartInfo.WorkingDirectory = get-location
    $process.StartInfo.Verb = "runas"
 
    [void]$process.Start()
    if($wait -and !$process.HasExited)
    {
        $process.WaitForExit($processWaitMs)
        $exitVal = $process.ExitCode
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        write-host "Process output:$stdOut"
 
        if(![String]::IsNullOrEmpty($stdErr) -and $stdErr -notlike "0")
        {
            #write-host "Error:$stdErr `n $Error"
            $Error.Clear()
        }
    }
    elseif($wait)
    {
        write-host "Process ended before capturing output."
    }
    
    #return $exitVal
    return $stdOut
}

# ----------------------------------------------------------------------------------------------------------------
function runas-admin()
{
    write-host "checking for admin"
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        if(!$noretry)
        { 
            write-host "restarting script as administrator. exiting..."
            Write-Host "run-process -processName "powershell.exe" -arguments $($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
            run-process -processName "powershell.exe" -arguments "$($SCRIPT:MyInvocation.MyCommand.Path) -noretry"
       }
       
       exit 1
   }
    write-host "running as admin"
}

# ----------------------------------------------------------------------------------------------------------------
main

