<#
.SYNOPSIS
    This script will monitor health probes for the load balancer.
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-load-balancer-monitor.ps1" -outFile "$pwd\azure-az-load-balancer-monitor.ps1";
    .\azure-az-load-balancer-monitor.ps1 -resourceGroup "rg" -loadBalancerName "lb"
.DESCRIPTION
    This script will monitor health probes for the load balancer.
.PARAMETER resourceGroup
    The resource group name.
.PARAMETER loadBalancerName
    The load balancer name.
.PARAMETER sleepSeconds
    The number of seconds to sleep between checks.
.EXAMPLE
    .\azure-az-load-balancer-monitor.ps1 -resourceGroup "rg" -loadBalancerName "lb"
.NOTES
    File Name  : azure-az-load-balancer-monitor.ps1
    Author     : JaGilber
    Prerequisite: Az PowerShell Module
    Disclaimer : This script is provided "AS IS" with no warranties.
    Version    : 1.0
    Changelog  : 1.0 - Initial release
#>

[cmdletbinding()]
param(
    $resourceGroup = '',
    $loadBalancerName,
    $sleepSeconds = 5
)

$PSModuleAutoLoadingPreference = 'all'
$ipAddresses = @{}
$tcpTestSucceeded = $false
$regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Multiline

$global:status = ''
$global:counter = 1

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

function get-dnsMatches($jobResults, $ipAddresses) {
    $dnsMatches = [regex]::matches($jobResults, '(?<time>.+?): dns:(?<name>.+?) ip:(?<ip>.+?) resolvedip:(?<resolvedip>.+?)$', $regexOptions)
    $executionTime = ((get-date) - $job.PSBeginTime).TotalSeconds

    foreach ($dnsMatch in $dnsMatches) {
        $ipAddress = $ipAddresses[$dnsMatch.Groups['ip'].Value]
        $dnsName = $dnsMatch.Groups['name'].Value
        $resolvedIp = $dnsMatch.Groups['resolvedip'].Value

        if ($ipAddress) {
            $ipAddress.dnsTotalSamples++
            if ($ipAddress.ip -eq $resolvedIp) {
                $ipAddress.dnsSuccessSamples++
                $successSamples = $ipAddress.dnsSuccessSamples
                $totalSamples = $ipAddress.totalSamples
                $percentAvailable = 0

                if ($totalSamples -gt 0) {
                    $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
                }

                $downtime = [decimal]($executionTime - ($executionTime * ($percentAvailable / 100)))
                $probeStatus = "$percentAvailable% Available. Minutes Unavailable:$([Math]::Round($downtime / 60,2))"
                write-progress -Activity "$($dnsName):$($ipAddress.ip)" -id "$($ipAddress.id)" -Status $probeStatus -PercentComplete $percentAvailable
            }
            else {
                Write-Warning "[wait-forJob] DNS Mismatch: $($dnsMatch.Groups['name'].Value) $($dnsMatch.Groups['ip'].Value) $($resolvedIp)"
                $resolvedIpAddress = $ipAddresses[$resolvedIp]
                if ($resolvedIpAddress) {
                    $resolvedIpAddress.fqdn = $dnsMatch.Groups['name'].Value
                    $resolvedIpAddress.dnsTotalSamples++
                    $resolvedIpAddress.dnsSuccessSamples++
                }
            }
        }
    }
}

function get-ipMatches($jobResults, $ipAddresses) {
    $ipMatches = [regex]::matches($jobResults, '(?<time>.+?): ip:(?<ip>.+?)(?::(?<port>\d+?))? result:(?<ipResult>\w+)', $regexOptions)
                
    foreach ($ipMatch in $ipMatches) {
        $ipAddress = $ipAddresses[$ipMatch.Groups['ip'].Value]

        if ($ipAddress) {
            $ipAddress.lastResult = [convert]::ToBoolean($ipMatch.Groups['ipResult'].Value)
            $port = [int]$ipMatch.Groups['port'].Value
            $ipAddress.totalSamples++

            if ($ipAddress.lastResult) {
                $ipAddress.successSamples++
            }

            if ($port) {
                if ($ipAddress.lastResult) {
                    $ipAddress.probes[$port].successSamples++
                }

                $ipAddress.probes[$port].totalSamples++
            }
        }
    }
}

function get-loadBalancerIps([string]$resourceGroup, [string]$loadBalancerName) {
    $loadBalancer = Get-AzLoadBalancer -ResourceGroupName $resourceGroup -Name $loadBalancerName

    foreach ($feConfig in $loadBalancer.FrontendIpConfigurations) {
        $ipAddresses = @{}
        $probes = @{}
        
        $pip = Get-AzPublicIpAddress -ResourceGroupName $feConfig.PublicIpAddress.Id.Split('/')[4] -Name $feConfig.PublicIpAddress.Id.Split('/')[-1]
        if ($feConfig.LoadBalancingRules) {
            foreach ($probe in $loadBalancer.Probes) {
                write-host "checking probe $($pip.IpAddress):$($probe.port)" -ForegroundColor Cyan
                if ($feConfig.LoadBalancingRules.Id -contains $probe.LoadBalancingRules.Id) {
                    write-host "adding probe $($pip.IpAddress):$($probe.port)" -ForegroundColor Green
                    [void]$probes.Add($probe.port, @{
                            port           = $probe.port
                            totalSamples   = 0
                            successSamples = 0
                            lastResult     = $false
                        })
                }
            }

            $ipAddress = @{
                ip                = $pip.IpAddress
                fqdn              = $pip.DnsSettings.Fqdn
                probes            = $probes
                successSamples    = 0
                totalSamples      = 0
                lastResult        = $false
                id                = $global:counter++
                dnsSuccessSamples = 0
                dnsTotalSamples   = 0
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
            param([hashtable]$publicIps, [int]$sleepSeconds = 5)
            $WarningPreference = $ProgressPreference = 'SilentlyContinue'

            while ($true) {
                $tcpClient = $null
                try {
                    Start-Sleep -Seconds $sleepSeconds
                    $tcpTestSucceeded = $true
                    # check all ip addresses
                    foreach ($publicIp in $publicIps.GetEnumerator()) {
                        $portTestSucceeded = $false
                        $foregroundColor = 'Cyan'
                        # checak all ports for each ip address
                        if ($publicIp.Value.fqdn) {
                            $dnsIp = (Resolve-DnsName -Name $publicIp.Value.fqdn -QuickTimeout).IPAddress
                            $dnsResult = "$((get-date).tostring('o')): dns:$($publicIp.Value.fqdn) ip:$($publicIp.Value.ip) resolvedip:$($dnsIp)"
                            write-host $dnsResult -ForegroundColor magenta
                            write-output $dnsResult

                            $portTestSucceeded = $portTestSucceeded -and $dnsIp -eq $publicIp.Value.ip
                            if ($dnsIp -and $dnsIp -ne $publicIp.Value.ip -and $publicIps[$publicIp.Value.ip]) {
                                $publicIps[$publicIp.Value.ip].fqdn = $publicIp.Value.fqdn
                                write-host "$((get-date).tostring('o')):$($publicIp.Key)updating DNS ip value:$($publicIp.Value.ip)==$($dns)" -ForegroundColor Yellow
                            }
                        }
                        foreach ($port in $publicIp.Value.probes.Keys.GetEnumerator()) {
                            $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
                            $tcpClient.SendTimeout = $tcpClient.ReceiveTimeout = 1000
                            [IAsyncResult]$asyncResult = $tcpClient.BeginConnect($publicIp.Value.ip, $port, $null, $null)

                            if (!$asyncResult.AsyncWaitHandle.WaitOne(1000, $false)) {
                                $portTestSucceeded = $false
                            }
                            else {
                                $portTestSucceeded = $portTestSucceeded -or $tcpClient.Connected
                            }

                            if (!$portTestSucceeded) {
                                $foregroundColor = 'Red'
                            }
                            
                            $portResult = "$((get-date).tostring('o')): ip:$($publicIp.Key):$($port) result:$portTestSucceeded"
                            write-host $portResult -ForegroundColor $foregroundColor
                            write-output $portResult

                            $tcpClient.Dispose()
                        }

                        $tcpTestSucceeded = $tcpTestSucceeded -and $portTestSucceeded
                    }

                    $ipResult = "$((get-date).tostring('o')): ip:$($publicIp.Key) result:$tcpTestSucceeded"
                    write-host $ipResult -ForegroundColor magenta
                    write-output $ipResult
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
        } -ArgumentList @($publicIps, $sleepSeconds)
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
    $global:status = ''
    $tcpTestSucceeded = $false

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
            $jobResults = [string]::Join("`n", @(Receive-Job -Id $tcpJob.Id))

            get-ipMatches -job $job -jobResults $jobResults -ipAddresses $ipAddresses
            get-dnsMatches -job $job -jobResults $jobResults -ipAddresses $ipAddresses
        }

        $successSamples = ($ipAddresses.Values.successSamples | Measure-Object -sum).Sum
        $totalSamples = ($ipAddresses.Values.totalSamples | measure-object -sum).Sum 
        $percentAvailable = 0

        if ($totalSamples -gt 0) {
            $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
        }
        
        $publicIpInfo = "IP Avail:$tcpTestSucceeded ($percentAvailable% Total Avail)"
        $uptime = [decimal]($executionTime * ($percentAvailable / 100))
        $global:status = "$publicIpInfo Minutes Executing:$([Math]::Round($executionTime / 60, 2)) Minutes Available:$([Math]::Round($uptime / 60,2)) State:$($job.State)"
        Write-Progress -Activity $Message -id 0 -Status $global:status -PercentComplete $percentAvailable

        foreach ($ipAddress in $ipAddresses.Values) {
            foreach ($probe in $ipAddress.probes.Values) {
                $successSamples = $probe.successSamples
                $totalSamples = $probe.totalSamples
                $percentAvailable = 0
                if ($totalSamples -gt 0) {
                    $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
                }

                $downtime = [decimal]($executionTime - ($executionTime * ($percentAvailable / 100)))
                $probeStatus = "$percentAvailable% Available. Minutes Unavailable:$([Math]::Round($downtime / 60,2))"
                write-progress -Activity "$($ipAddress.ip):$($probe.port)" -id "$($ipAddress.id)$($probe.port)" -Status $probeStatus -PercentComplete $percentAvailable 
            }
        }

        if ($job.State -ine "Running") {
            write-host "[wait-forJob] Job Not Running: $($job)"

            if ($job.State -imatch "fail" -or $job.StatusMessage -imatch "fail") {
                write-error "[wait-forJob] Job Failed: $($job)"
            }

            remove-jobId -JobId $JobId
            Write-Progress -Activity 'Complete' -id 0 -Completed
            break
        }
        
        Start-Sleep -Seconds $sleepSeconds
    }

    write-host "[wait-forJob] Job Complete: $global:status"

    if ($tcpJob) {
        remove-jobId -JobId $tcpJob.Id
    }
}

main
