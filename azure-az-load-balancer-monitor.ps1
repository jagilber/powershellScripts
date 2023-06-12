<#
.SYNOPSIS
    This script will monitor health probes for the load balancer.
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-load-balancer-monitor.ps1" -outFile "$pwd\azure-az-load-balancer-monitor.ps1";
    .\azure-az-load-balancer-monitor.ps1 -resourceGroup "rg" -loadBalancerName "lb"
#>
[cmdletbinding()]
param(
    $resourceGroup = '',
    $loadBalancerName
)

$PSModuleAutoLoadingPreference = 'all'
$ipAddresses = @{}
$tcpTestSucceeded = $false
$global:status = ''

function main() {
    $job = $null
    $publicIps = @{}
    $loadBalancerNames = $null

    try {
        if (!$loadBalancerName) {
            $loadBalancerNames = (get-azLoadBalancer -ResourceGroupName $resourceGroup).Name
        }
        else {
            $loadBalancerNames = @($loadBalancerName)
        }
        
        foreach ($loadBalancerName in $loadBalancerNames) {
            $publicIps += get-loadBalancerIps -ResourceGroup $resourceGroup -loadBalancerName $loadBalancerName
           # get-loadBalancerIps -ResourceGroup $resourceGroup -loadBalancerName $loadBalancerName
        }

        $job = start-job -ScriptBlock { while ($true) { Start-Sleep -Seconds 1 } }
        wait-forJob -JobId $job.Id -ipAddresses $publicIps
    }
    catch [Exception] {
        write-error "[main] $($psitem | out-string)"
    }
    finally {
        remove-jobId -JobId $job.Id
        write-host "global:status: $global:status"
        write-host "[main] Completed"
    }
}

function get-loadBalancerIps([string]$resourceGroup, [string]$loadBalancerName) {
    $loadBalancer = Get-AzLoadBalancer -ResourceGroupName $resourceGroup -Name $loadBalancerName

    foreach ($feConfig in $loadBalancer.FrontendIpConfigurations) {
        $ipAddresses = @{}
        $probes = [collections.ArrayList]::new()
        
        $pip = Get-AzPublicIpAddress -ResourceGroupName $feConfig.PublicIpAddress.Id.Split('/')[4] -Name $feConfig.PublicIpAddress.Id.Split('/')[-1]
        if ($feConfig.LoadBalancingRules) {
            foreach ($probe in $loadBalancer.Probes) {
                write-host "checking probe $($pip.IpAddress):$($probe.port)" -ForegroundColor Cyan
                if ($feConfig.LoadBalancingRules.Id -contains $probe.LoadBalancingRules.Id) {
                    write-host "adding probe $($pip.IpAddress):$($probe.port)" -ForegroundColor Green
                    [void]$probes.Add($probe.port)
                }
            }

            $ipAddress = @{
                ip = $pip.IpAddress
                fqdn = $pip.DnsSettings.Fqdn
                probes = $probes.ToArray()
            }
            [void]$ipAddresses.Add($pip.IpAddress, $ipAddress)
        }
    }
    return $ipAddresses
}

function start-ipMonitorJob([hashtable]$publicIps) {
    # cloud shell does not have test-netconnection. using tcpclient
    $tcpJob = $null
    if ($publicIps) {
        $tcpJob = Start-Job -ScriptBlock {
            param([hashtable]$publicIps)
            $WarningPreference = $ProgressPreference = 'SilentlyContinue'

            while ($true) {
                $tcpClient = $null
                try {
                    Start-Sleep -Seconds 5
                    $tcpTestSucceeded = $true
                    # check all ip addresses
                    foreach ($publicIp in $publicIps.GetEnumerator()) {
                        $portTestSucceeded = $false
                        $foregroundColor = Cyan
                        # checak all ports for each ip address
                        if($publicIp.Value.fqdn){
                            $dnsIp = (Resolve-DnsName -Name $publicIp.Value.fqdn -QuickTimeout).IPAddress
                            write-host "$((get-date).tostring('o')):DNS: $($publicIp.Value.fqdn) $($publicIp.Value.ip)==$($dnsIp)" -ForegroundColor magenta
                            $portTestSucceeded = $portTestSucceeded -and $dnsIp -eq $publicIp.Value.ip
                            if($dnsIp -and $dnsIp -ne $publicIp.Value.ip -and $publicIps[$publicIp.Value.ip]){
                                $publicIps[$publicIp.Value.ip].fqdn = $publicIp.Value.fqdn
                                write-host "$((get-date).tostring('o')):$($publicIp.Key)updating DNS ip value:$($publicIp.Value.ip)==$($dns)" -ForegroundColor Yellow
                            }
                        }
                        foreach ($port in $publicIp.Value.probes) {
                            $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
                            $tcpClient.SendTimeout = $tcpClient.ReceiveTimeout = 1000
                            [IAsyncResult]$asyncResult = $tcpClient.BeginConnect($publicIp.Value.ip, $port, $null, $null)

                            if (!$asyncResult.AsyncWaitHandle.WaitOne(1000, $false)) {
                                $portTestSucceeded = $false
                            }
                            else {
                                $portTestSucceeded = $portTestSucceeded -or $tcpClient.Connected
                            }

                            if(!$portTestSucceeded){
                                $foregroundColor = Red
                            }
                            
                            write-host "$((get-date).tostring('o')):$($publicIp.Key) port:$($port) $portTestSucceeded" -ForegroundColor $foregroundColor
                            $tcpClient.Dispose()
                        }

                        $tcpTestSucceeded = $tcpTestSucceeded -and $portTestSucceeded
                    }

                    write-host "$((get-date).tostring('o')):result: $tcpTestSucceeded" -ForegroundColor magenta
                    write-output $tcpTestSucceeded
                }
                catch {
                    write-warning "[CreateIPMonitorJob] exception:$($PSItem)"
                }
                finally {
                    if ($tcpClient) {
                        $tcpClient.Dispose()
                    }
                }
            }
        } -Verbose:$psboundparameters['verbose'] -ArgumentList @($publicIps)
    }
    return $tcpJob
}

function remove-jobId([string]$JobId) {
    write-host "[remove-jobId] Removing Job Id: $($JobId)"
    if (Get-Job -Id $JobId -ErrorAction SilentlyContinue) {
        Remove-Job -Id $JobId -Force
        write-host "[remove-jobId] Job Removed: $($JobId)"
    }
    else {
        write-warning "[remove-jobId] Job Id Not Found: $($JobId)"
    }
}

function wait-forJob ([string]$JobId, [hashtable]$ipAddresses) {

    $job = $null
    $percentAvailable = 0
    $publicIpInfo = ''
    $samples = 1
    $global:status = ''
    $tcpTestLastResult = $null
    $tcpTestSucceeded = $false
    $trueResults = 0

    write-host "[wait-forJob] Checking Job Id: $($JobId)"
    $tcpJob = start-ipMonitorJob -publicIps $ipAddresses

    while ($job = get-job -Id $JobId) {
        $jobInfo = (receive-job -Id $JobId)
        $Message = $job.Name

        if ($jobInfo) {
            write-host "[wait-forJob] Receiving Job: $($jobInfo)"
        }
        elseif ($DebugPreference -ieq 'Continue') {
            write-host "[wait-forJob] Receiving Job No Update: $($job | ConvertTo-Json -Depth 1 -WarningAction SilentlyContinue)"
        }

        if ($ipAddresses -and (Get-Job -id $tcpJob.Id)) {
            $tcpTestSucceeded = @((Receive-Job -Id $tcpJob.Id))[-1]
            if (![string]::IsNullOrEmpty($tcpTestSucceeded)) {
                $tcpTestLastResult = $tcpTestSucceeded
                if ($tcpTestLastResult) {
                    $trueResults++
                }
                $percentAvailable = [decimal][Math]::Round(($trueResults / $samples++) * 100)
            }
            else {
                $tcpTestSucceeded = $tcpTestLastResult
            }

            $publicIpInfo = "IP Avail:$tcpTestSucceeded ($percentAvailable% Total Avail)"
        }

        $executionTime = ((get-date) - $job.PSBeginTime).TotalSeconds
        $uptime = [decimal]($executionTime * ($percentAvailable / 100))
        $global:status = "$publicIpInfo Minutes Executing:$($executionTime / 60) Minutes Available: $($uptime / 60) State:$($job.State)"
        Write-Progress -Activity $Message -id 0 -Status $global:status

        if ($job.State -ine "Running") {
            write-host "[wait-forJob] Job Not Running: $($job)"

            if ($job.State -imatch "fail" -or $job.StatusMessage -imatch "fail") {
                write-error "[wait-forJob] Job Failed: $($job)"
            }

            remove-jobId -JobId $JobId
            Write-Progress -Activity 'Complete' -id 0 -Completed
            break
        }

        Start-Sleep -Seconds 1
    }

    write-host "[wait-forJob] Job Complete: $global:status"

    if ($tcpJob) {
        remove-jobId -JobId $tcpJob.Id
    }
}

main
