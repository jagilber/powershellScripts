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

#[cmdletbinding()]
param(
    [string]$resourceGroup = '',
    [string]$loadBalancerName,
    [int]$sleepSeconds = 5,
    [int]$refreshSeconds = 60,
    [switch]$verbose
)

$PSModuleAutoLoadingPreference = 'all'
$ipAddresses = @{}
$tcpTestSucceeded = $false
$regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Multiline

$global:status = ''
$global:counter = 1
$global:startTime = [datetime]::Now

function main() {
    $job = $null
    $publicIps = @{}
    $loadBalancerNames = $null

    try {
        new-monitorJob
    }
    catch [Exception] {
        write-error "[main] $($psitem | out-string)"
    }
    finally {
        write-host "global:status: $global:status"
        write-host "[main] Completed"
    }
}

function get-dnsMatches($jobResults, $ipAddresses) {
    $dnsMatches = [regex]::matches($jobResults, '(?<time>.+?): dns:(?<name>.+?) ip:(?<ip>.+?) resolvedip:(?<resolvedip>.*?)$', $regexOptions)
    $executionTime = ((get-date) - $global:startTime).TotalSeconds

    foreach ($dnsMatch in $dnsMatches) {
        $percentAvailable = 0
        $successSamples = 0
        $ipAddress = $ipAddresses[$dnsMatch.Groups['ip'].Value]
        $dnsName = $dnsMatch.Groups['name'].Value
        $resolvedIp = $dnsMatch.Groups['resolvedip'].Value
        $currentlyAvailable = $false

        if ($ipAddress) {
            $ipAddress.dnsTotalSamples++
            $totalSamples = $ipAddress.dnsTotalSamples

            if ($ipAddress.ip -eq $resolvedIp) {
                $ipAddress.dnsSuccessSamples++
                $successSamples = $ipAddress.dnsSuccessSamples
                $ipAddress.lastResult = $true
                $currentlyAvailable = $true
            }
            else {
                Write-Warning "[watch-job] DNS Mismatch: $($dnsMatch.Groups['name'].Value) $($dnsMatch.Groups['ip'].Value) $($resolvedIp)"
                $resolvedIpAddress = $ipAddresses[$resolvedIp]
                if ($resolvedIpAddress) {
                    $resolvedIpAddress.fqdn = $dnsMatch.Groups['name'].Value
                    $resolvedIpAddress.dnsTotalSamples++
                    $resolvedIpAddress.dnsSuccessSamples++
                }
                $ipAddress.lastResult = $false
            }

            if ($totalSamples -gt 0) {
                $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
            }

            $downtime = [decimal]($executionTime - ($executionTime * ($successSamples / $totalSamples)))
            $probeStatus = "$percentAvailable% Available. Minutes Unavailable:$([Math]::Round($downtime / 60, 2)) Currently: $currentlyAvailable"
            write-progress -Activity "$($dnsName):$($ipAddress.ip)" -id "$($ipAddress.id)" -Status $probeStatus -PercentComplete $percentAvailable
        }
        else {
            write-warning "[watch-job] DNS no IP match: $($dnsMatch.Groups['name'].Value) $($dnsMatch.Groups['ip'].Value) $($resolvedIp)"
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

function get-loadBalancers() {
    if (!$loadBalancerName) {
        $loadBalancerNames = (get-azLoadBalancer -ResourceGroupName $resourceGroup).Name
    }
    else {
        $loadBalancerNames = @($loadBalancerName)
    }

    if (!$loadBalancerNames) {
        write-error "[main] No load balancers found in resource group: $($resourceGroup)"
        return $null
    }

    return $loadBalancerNames
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
            param([hashtable]$publicIps, [int]$sleepSeconds = 5, [bool]$verbose)
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
                            if ($verbose) {
                                write-host $dnsResult -ForegroundColor magenta
                            }

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
                            if ($verbose) {
                                write-host $portResult -ForegroundColor $foregroundColor
                            }

                            write-output $portResult
                            $tcpClient.Dispose()
                        }

                        $tcpTestSucceeded = $tcpTestSucceeded -and $portTestSucceeded
                    }

                    $ipResult = "$((get-date).tostring('o')): ip:$($publicIp.Key) result:$tcpTestSucceeded"

                    if ($verbose) {
                        write-host $ipResult -ForegroundColor magenta
                    }
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
        } -ArgumentList @($publicIps, $sleepSeconds, $verbose)
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

function new-monitorJob() {
    $publicIps = @{}

    while ($refreshSeconds) {
        update-loadBalancerIps -loadBalancerNames (get-loadBalancers) -publicIps $publicIps
        watch-job -ipAddresses $publicIps -refreshSeconds $refreshSeconds
    }
}

function update-loadBalancerIps([string[]]$loadBalancerNames, [hashtable]$publicIps) {
    foreach ($loadBalancerName in $loadBalancerNames) {
        $ips = get-loadBalancerIps -ResourceGroup $resourceGroup -loadBalancerName $loadBalancerName
        foreach ($ip in $ips.Values) {
            if (!$publicIps[$ip.ip]) {
                [void]$publicIps.Add($ip.ip, $ip)
            }
            else {
                $publicIps[$ip.ip].fqdn = $ip.fqdn
                foreach ($probe in $ip.probes.Values) {
                    if (!$publicIps[$ip.ip].probes[$probe.port]) {
                        [void]$publicIps[$ip.ip].probes.Add($probe.port, $probe)
                    }
                    else {
                        $publicIps[$ip.ip].probes[$probe.port].port = $probe.port
                    }
                }
            }
        }
    }
}
function watch-job ([hashtable]$ipAddresses, [int]$refreshSeconds = 0) {
    $tcpJob = $null
    $global:status = ''
    $watchTime = [datetime]::Now

    write-host "[watch-job] starting and monitoring job"
    try {
        $tcpJob = start-ipMonitorJob -publicIps $ipAddresses

        while ($refreshSeconds -eq 0 -or ((get-date) - $watchTime).TotalSeconds -lt $refreshSeconds) {
            if ($ipAddresses -and (Get-Job -id $tcpJob.Id)) {
                $jobResults = [string]::Join("`n", @(Receive-Job -Id $tcpJob.Id))

                get-ipMatches -jobResults $jobResults -ipAddresses $ipAddresses
                get-dnsMatches -jobResults $jobResults -ipAddresses $ipAddresses
            }

            write-ipAddresses -ipAddresses $ipAddresses

            if ($tcpJob.State -ine "Running") {
                write-host "[watch-job] Job Not Running: $($tcpJob)"

                if ($tcpJob.State -imatch "fail" -or $tcpJob.StatusMessage -imatch "fail") {
                    write-error "[watch-job] Job Failed: $($tcpJob)"
                }

                remove-jobId -JobId $tcpJob.Id
                Write-Progress -Activity 'Complete' -id 0 -Completed
                break
            }
        
            Start-Sleep -Seconds $sleepSeconds
        }

        write-host "[watch-job] Job Complete: $global:status"
    }
    catch [Exception] {
        write-error "[watch-job] $($psitem | out-string)"
        return
    }
    finally {
        if ($tcpJob) {
            remove-jobId -JobId $tcpJob.Id
        }
    }
}

function write-ipAddresses($ipAddresses) {
    $successSamples = ($ipAddresses.Values.successSamples | Measure-Object -sum).Sum
    $totalSamples = ($ipAddresses.Values.totalSamples | measure-object -sum).Sum 
    $percentAvailable = 0

    if ($totalSamples -gt 0) {
        $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
    }

    $message = "$resourceGroup : "
    $publicIpInfo = "IP Avail:$tcpTestSucceeded ($percentAvailable% Total Avail)"
    $executionTime = ((get-date) - $global:startTime).TotalSeconds
    $uptime = [decimal]($executionTime * ($percentAvailable / 100))
    $global:status = "$publicIpInfo Minutes Executing:$([Math]::Round($executionTime / 60, 2)) Minutes Available:$([Math]::Round($uptime / 60,2))"
    Write-Progress -Activity $message -id 0 -Status $global:status -PercentComplete $percentAvailable

    foreach ($ipAddress in $ipAddresses.Values) {
        foreach ($probe in $ipAddress.probes.Values) {
            $successSamples = $probe.successSamples
            $totalSamples = $probe.totalSamples
            $percentAvailable = 0
            if ($totalSamples -gt 0) {
                $percentAvailable = [decimal][Math]::Min(100, [Math]::Round(($successSamples / $totalSamples) * 100))
            }

            $downtime = [decimal]($executionTime - ($executionTime * ($percentAvailable / 100)))
            $probeStatus = "$percentAvailable% Available. Minutes Unavailable:$([Math]::Round($downtime / 60,2)) Currently: $($ipAddress.lastResult)"
            write-progress -Activity "$($ipAddress.ip):$($probe.port)" -id "$($ipAddress.id)$($probe.port)" -Status $probeStatus -PercentComplete $percentAvailable 
        }
    }
}

main
