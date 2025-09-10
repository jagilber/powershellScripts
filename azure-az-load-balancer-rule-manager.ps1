<#
.SYNOPSIS
    Manage (Add/Update/Remove/List) rules and probes on an Azure Standard Load Balancer.

.DESCRIPTION
    This script provides idempotent management of Standard Azure Load Balancer rules and probes.
    Rule Actions:
        Add / Update / Remove / List
    Probe Actions:
        AddProbe / UpdateProbe / RemoveProbe / ListProbes

    Only specified parameters are changed during Update. Unspecified ones retain current values.
    The script validates the Load Balancer SKU (Standard) and provides helpful error messages.

Microsoft Privacy Statement: https://privacy.microsoft.com/en-US/privacystatement
    MIT License
    Copyright (c) Microsoft Corporation. All rights reserved.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE

.PARAMETER ResourceGroup
    The resource group name containing the load balancer.

.PARAMETER LoadBalancerName
    The name of the target load balancer.

.PARAMETER Action
    One of: Add, Update, Remove, List, AddProbe, UpdateProbe, RemoveProbe, ListProbes.

.PARAMETER RuleName
    The load balancing rule name to act upon.

.PARAMETER FrontendIpConfigName
    Name of the frontend IP configuration to bind. Optional for Add/Update when only one exists.

.PARAMETER BackendPoolName
    Name of the backend address pool to use. Optional for Add/Update when only one exists.

.PARAMETER ProbeName
    Optional probe name to associate. If omitted, rule will have no probe (not recommended for production).

.PARAMETER Protocol
    Protocol for the rule. Valid values: Tcp, Udp, All.

.PARAMETER FrontendPort
    Frontend port (public). Required for Add. Optional for Update.

.PARAMETER BackendPort
    Backend port (private). Required for Add. Optional for Update.

.PARAMETER IdleTimeoutInMinutes
    TCP idle timeout in minutes (4-30). Optional.

.PARAMETER EnableFloatingIP
    Enable floating IP (direct server return) for the rule.

.PARAMETER DisableOutboundSnat
    Disable outbound SNAT for the rule.

.PARAMETER EnableTcpReset
    Enable TCP reset on idle timeout or unexpected connection termination (TCP only).

.PARAMETER Force
    For Action Add: if rule exists and -Force supplied, behaves like Update.

.PARAMETER DryRun
    Show the operations that would be performed without applying changes.

.PARAMETER PassThru
    Output the modified resource object (rule or probe) after change.

.PARAMETER ProbeProtocol
    Protocol for probe (Tcp, Http, Https). For probe actions.

.PARAMETER ProbePort
    Probe port. Required for AddProbe.

.PARAMETER ProbeIntervalSeconds
    Interval between probe attempts. Default 5.

.PARAMETER ProbeThreshold
    Number of probes before marking down. Default 2.

.PARAMETER ProbePath
    Path for Http/Https probes (e.g. /health). Required for those protocols.

.PARAMETER NonInteractive
    Fail instead of prompting when multiple selectable resources exist.

.PARAMETER Diagnostics
    When specified, outputs a diagnostic summary of the load balancer (frontends, pools, probes, rules, outbound rules) before performing the requested action.

.PARAMETER AutoFixOutboundSnat
    When true (default), automatically sets DisableOutboundSNAT = true if the frontend selected is referenced by an outbound rule and the rule/probe action would otherwise fail validation.

.EXAMPLE
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup rg -LoadBalancerName myLb -Action Add -RuleName web-443 `
        -FrontendPort 443 -BackendPort 443 -Protocol Tcp -ProbeName httpsProbe -IdleTimeoutInMinutes 15 -EnableTcpReset

    Adds a new TCP rule for HTTPS referencing the httpsProbe if it exists.

.EXAMPLE
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup rg -LoadBalancerName myLb -Action Update -RuleName web-443 -IdleTimeoutInMinutes 25

    Updates only the idle timeout on existing rule web-443.

.EXAMPLE
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup rg -LoadBalancerName myLb -Action Remove -RuleName web-443 -Verbose

    Removes the rule web-443.

.EXAMPLE
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup rg -LoadBalancerName myLb -Action List

    Lists existing rules.

.EXAMPLE
    # Basic lifecycle: add probe, add rule, update rule
    $rg = 'rg1'
    $lb = 'myStandardLb'
    $probe = 'https-probe-443'
    $rule  = 'https-rule-443'
    
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action AddProbe -ProbeName $probe -ProbeProtocol Https -ProbePort 443 -ProbePath '/health' -PassThru
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Add -RuleName $rule -FrontendPort 443 -BackendPort 443 -Protocol Tcp -ProbeName $probe -EnableTcpReset -PassThru
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Update -RuleName $rule -IdleTimeoutInMinutes 25 -PassThru
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action List

.EXAMPLE
    # Full lifecycle with DryRun previews and cleanup (idempotent on re-run)
    $rg = 'rg1'
    $lb = 'myStandardLb'
    $probe = 'test-probe-50000'
    $rule  = 'test-lb-rule-50000'

    # Preview probe & rule creation
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action AddProbe -ProbeName $probe -ProbeProtocol Tcp -ProbePort 50000 -DryRun
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Add -RuleName $rule -FrontendPort 50000 -BackendPort 50000 -Protocol Tcp -ProbeName $probe -DryRun

    # Apply
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action AddProbe -ProbeName $probe -ProbeProtocol Tcp -ProbePort 50000
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Add -RuleName $rule -FrontendPort 50000 -BackendPort 50000 -Protocol Tcp -ProbeName $probe -EnableTcpReset

    # Update with DryRun first
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Update -RuleName $rule -IdleTimeoutInMinutes 25 -EnableFloatingIP -DryRun
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Update -RuleName $rule -IdleTimeoutInMinutes 25 -EnableFloatingIP

    # Diagnostics snapshot
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action List -Diagnostics
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action ListProbes

    # Cleanup (DryRun then apply)
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Remove -RuleName $rule -DryRun
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action Remove -RuleName $rule
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action RemoveProbe -ProbeName $probe -DryRun
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action RemoveProbe -ProbeName $probe

    # Final verification
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action List
    .\azure-az-load-balancer-rule-manager.ps1 -ResourceGroup $rg -LoadBalancerName $lb -Action ListProbes

.NOTES
    File Name  : azure-az-load-balancer-rule-manager.ps1
    Author     : GitHubCopilot
    Requires   : Az.Network module (Az PowerShell)
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.8
    Changelog  : 1.0 - Initial release
                 1.1 - Align with template.ps1 structure (main wrapper, strict mode, write-console helper)
                 1.2 - Sync with updated template (remove Set-StrictMode, add #requires, adjust write-console)
                 1.3 - Conform to template v1.1: add missing parameter help (Diagnostics, AutoFixOutboundSnat), rename Show-* to Write-* using approved verbs, unify dry run output helper
                 1.4 - Idempotent Add (rule/probe): no error when existing config matches; require -Force only when change needed
                 1.5 - Fix Update mapping for resourceId objects; remove unsupported -Force on Remove operations
                 1.6 - Added comprehensive lifecycle .EXAMPLE blocks (basic + full DryRun + cleanup)
                 1.7 - Align catch block with template (no rethrow inside catch, add variable dump), fix Add-Rule probe param bug, ensure diagnostics executed on error
                 1.8 - Added MIT license / privacy statement block from template
#>

#requires -version 6

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter()][string]$LoadBalancerName,
    [Parameter(Mandatory)][ValidateSet('Add', 'Update', 'Remove', 'List', 'AddProbe', 'UpdateProbe', 'RemoveProbe', 'ListProbes')][string]$Action,
    [Parameter()][string]$RuleName,
    [Parameter()][string]$FrontendIpConfigName,
    [Parameter()][string]$BackendPoolName,
    [Parameter()][string]$ProbeName,
    [Parameter()][ValidateSet('Tcp', 'Udp', 'All')][string]$Protocol = 'Tcp',
    [Parameter()][int]$FrontendPort,
    [Parameter()][int]$BackendPort,
    [Parameter()][ValidateRange(4, 30)][int]$IdleTimeoutInMinutes,
    [switch]$EnableFloatingIP,
    [switch]$DisableOutboundSnat,
    [switch]$EnableTcpReset,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$PassThru,
    [switch]$Diagnostics,
    [bool]$AutoFixOutboundSnat = $true,
    [Parameter()][ValidateSet('Tcp', 'Http', 'Https')][string]$ProbeProtocol = 'Tcp',
    [int]$ProbePort,
    [int]$ProbeIntervalSeconds = 5,
    [int]$ProbeThreshold = 2,
    [string]$ProbePath,
    [switch]$NonInteractive
)

# template alignment additions (updated: no strict mode per template)
$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'Continue'
$scriptName = "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"

function main {
    $start = Get-Date
    write-console "starting $scriptName at $start" -foregroundColor Cyan
    $lb = $null
    try {
        $lb = Get-LoadBalancer
        if ($Diagnostics) { Write-Diagnostics -Lb $lb }
        switch ($Action) {
            'List' { Get-LBLoadBalancingRule -Lb $lb }
            'Add' { Add-Rule -Lb $lb }
            'Update' { Update-Rule -Lb $lb }
            'Remove' { Remove-Rule -Lb $lb }
            'ListProbes' { Get-LBProbeList -Lb $lb }
            'AddProbe' { Add-Probe -Lb $lb }
            'UpdateProbe' { Update-Probe -Lb $lb }
            'RemoveProbe' { Remove-Probe -Lb $lb }
            default { throw "Unsupported Action: $Action" }
        }
        $elapsed = (Get-Date) - $start
        write-console "completed $scriptName in $([int]$elapsed.TotalSeconds)s" -foregroundColor Green
        return 0
    }
    catch {
        $all = Get-InnerExceptionMessages -Ex $_.Exception
        # Show diagnostics first (do not abort)
        if ($Diagnostics -and $lb) { Write-Diagnostics -Lb $lb }
        write-console "exception::$all" -foregroundColor Red -warn
        if ($PSItem.InvocationInfo.PositionMessage) { Write-Verbose $PSItem.InvocationInfo.PositionMessage }
        Write-Verbose ("locals::" + ((Get-Variable -Scope Local | ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }) -join ';'))
        return 1
    }
}

function write-console($message, [consoleColor]$foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.GetType().Name -ne 'String') { $message = $message | ConvertTo-Json -Depth 10 -WarningAction SilentlyContinue }
    if ($verbose) { Write-Verbose $message } else { Write-Host $message -ForegroundColor $foregroundColor }
    if ($warn) { Write-Warning $message }
    elseif ($err) { Write-Error $message; throw }
}

# retain existing helper but prefer write-console for new messages (updated)

function Write-VerboseMsg([string]$Message) { if ($PSBoundParameters.ContainsKey('Verbose')) { Write-Verbose $Message } }

function Select-Choice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)]$Items,
        [string]$Property = 'Name'
    )
    if (-not $Items) { return $null }
    if ($Items.Count -le 1) { return $Items[0] }
    if ($NonInteractive) { throw "Multiple options for $Prompt; specify parameter explicitly." }
    Write-Host "Select $($Prompt):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) { $v = $Items[$i].$Property; Write-Host "  [$i] $v" }
    while ($true) {
        $c = Read-Host 'Enter index'
        if ($c -match '^[0-9]+$' -and [int]$c -ge 0 -and [int]$c -lt $Items.Count) { return $Items[[int]$c] }
        Write-Warning 'Invalid selection.'
    }
}

function Get-LoadBalancer {
    if (-not $LoadBalancerName) {
        $lbs = Get-AzLoadBalancer -ResourceGroupName $ResourceGroup -ErrorAction Stop
        if (-not $lbs) { throw "No load balancers in resource group '$ResourceGroup'." }
        $sel = Select-Choice -Prompt 'LoadBalancer' -Items $lbs -Property 'Name'
        $script:LoadBalancerName = $sel.Name
    }
    Write-VerboseMsg "[Get-LoadBalancer] Retrieving load balancer $LoadBalancerName in $ResourceGroup"
    $lb = Get-AzLoadBalancer -Name $LoadBalancerName -ResourceGroupName $ResourceGroup -ErrorAction Stop
    if ($lb.Sku.Name -ne 'Standard') {
        throw "Load Balancer '$LoadBalancerName' SKU is '$($lb.Sku.Name)'. This script only supports Standard."
    }
    return $lb
}

function Resolve-FrontendIpConfig([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    if ($FrontendIpConfigName) {
        $fe = $Lb.FrontendIpConfigurations | Where-Object Name -eq $FrontendIpConfigName
        if (-not $fe) { throw "FrontendIpConfiguration '$FrontendIpConfigName' not found." }
        return $fe
    }
    if ($Lb.FrontendIpConfigurations.Count -eq 1) { return $Lb.FrontendIpConfigurations[0] }
    $sel = Select-Choice -Prompt 'FrontendIpConfiguration' -Items $Lb.FrontendIpConfigurations -Property 'Name'
    $script:FrontendIpConfigName = $sel.Name
    return $sel
}

function Resolve-BackendPool([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    if ($BackendPoolName) {
        $pool = $Lb.BackendAddressPools | Where-Object Name -eq $BackendPoolName
        if (-not $pool) { throw "BackendPool '$BackendPoolName' not found." }
        return $pool
    }
    if ($Lb.BackendAddressPools.Count -eq 1) { return $Lb.BackendAddressPools[0] }
    $sel = Select-Choice -Prompt 'BackendAddressPool' -Items $Lb.BackendAddressPools -Property 'Name'
    $script:BackendPoolName = $sel.Name
    return $sel
}

function Resolve-Probe([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    if (-not $ProbeName) { return $null }
    $probe = $Lb.Probes | Where-Object Name -eq $ProbeName
    if (-not $probe) { throw "Probe '$ProbeName' not found." }
    return $probe
}

function Get-Rule([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb, [string]$Name) {
    if (-not $Name) { return $null }
    return $Lb.LoadBalancingRules | Where-Object Name -eq $Name
}

function Write-PlannedChange([string]$Verb, [hashtable]$Details) {
    Write-Host "[DryRun] $Verb Load Balancer Rule:`n" -ForegroundColor Cyan
    $Details.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host ("  {0} = {1}" -f $_.Key, ($_.Value -join ','))
    }
}

function Get-InnerExceptionMessages([Exception]$Ex) {
    $messages = @()
    while ($Ex) {
        $messages += $Ex.Message
        $Ex = $Ex.InnerException
    }
    return ($messages -join ' | ')
}

function Write-Diagnostics([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    Write-Host '[Diagnostics] FrontendIpConfigurations:' -ForegroundColor Cyan
    $Lb.FrontendIpConfigurations | Select-Object Name, PrivateIpAddress, PublicIpAddress | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host '[Diagnostics] BackendAddressPools:' -ForegroundColor Cyan
    $Lb.BackendAddressPools | Select-Object Name, @{n = 'BackendCount'; e = { $_.BackendIpConfigurations.Count } } | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host '[Diagnostics] Probes:' -ForegroundColor Cyan
    $Lb.Probes | Select-Object Name, Protocol, Port, IntervalInSeconds, NumberOfProbes | Format-Table -AutoSize | Out-String | Write-Host
    if ($Lb.OutboundRules) {
        Write-Host '[Diagnostics] OutboundRules:' -ForegroundColor Cyan
        $Lb.OutboundRules | ForEach-Object { 
            [pscustomobject]@{ 
                Name      = $_.Name; 
                Protocol  = $_.Protocol; 
                Frontends = ($_.FrontendIpConfigurations.Id | ForEach-Object { $_.Split('/')[-1] }) -join ',' 
            } 
        } | Format-Table -AutoSize | Out-String | Write-Host
    }
    Write-Host '[Diagnostics] Existing Rules:' -ForegroundColor Cyan
    ($Lb.LoadBalancingRules | Select-Object Name, Protocol, FrontendPort, BackendPort, IdleTimeoutInMinutes) | Format-Table -AutoSize | Out-String | Write-Host
}

function Test-FrontendRequiresDisableSnat([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb, $Frontend) {
    if (-not $Lb.OutboundRules) { return $false }
    $feId = $Frontend.Id.ToLower()
    foreach ($obr in $Lb.OutboundRules) {
        foreach ($ofe in $obr.FrontendIpConfigurations) {
            if ($ofe.Id.ToLower() -eq $feId) { return $true }
        }
    }
    return $false
}

function Add-Rule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb
    )
    if (-not $RuleName) { throw '-RuleName is required for Add.' }
    if (-not ($FrontendPort -and $BackendPort)) { throw 'FrontendPort and BackendPort are required for Add.' }
    $existing = Get-Rule -Lb $Lb -Name $RuleName
    if ($existing) {
        # Determine if requested parameters differ from existing
        $diffs = @{}
        if ($FrontendPort -and $FrontendPort -ne $existing.FrontendPort) { $diffs.FrontendPort = @($existing.FrontendPort, $FrontendPort) }
        if ($BackendPort -and $BackendPort -ne $existing.BackendPort) { $diffs.BackendPort = @($existing.BackendPort, $BackendPort) }
        if ($Protocol -and $Protocol -ne $existing.Protocol) { $diffs.Protocol = @($existing.Protocol, $Protocol) }
        if ($PSBoundParameters.ContainsKey('IdleTimeoutInMinutes') -and $IdleTimeoutInMinutes -ne $existing.IdleTimeoutInMinutes) { $diffs.IdleTimeoutInMinutes = @($existing.IdleTimeoutInMinutes, $IdleTimeoutInMinutes) }
        if ($EnableFloatingIP.IsPresent -and $EnableFloatingIP.IsPresent -ne $existing.EnableFloatingIP) { $diffs.EnableFloatingIP = @($existing.EnableFloatingIP, $EnableFloatingIP.IsPresent) }
        if ($DisableOutboundSnat.IsPresent -and $DisableOutboundSnat.IsPresent -ne $existing.DisableOutboundSNAT) { $diffs.DisableOutboundSNAT = @($existing.DisableOutboundSNAT, $DisableOutboundSnat.IsPresent) }
        if ($EnableTcpReset.IsPresent -and $EnableTcpReset.IsPresent -ne $existing.EnableTcpReset) { $diffs.EnableTcpReset = @($existing.EnableTcpReset, $EnableTcpReset.IsPresent) }
        if ($ProbeName) {
            $existingProbeName = if ($existing.Probe) { $existing.Probe.Id.Split('/')[-1] } else { $null }
            if ($ProbeName -ne $existingProbeName) { $diffs.Probe = @($existingProbeName, $ProbeName) }
        }
        if ($diffs.Count -eq 0) {
            if ($DryRun) {
                Write-PlannedChange -Verb 'Add (NoOp)' -Details @{ Action = 'Add'; RuleName = $RuleName; Note = 'Rule already exists with identical configuration' }
            }
            else {
                write-console "[Add-Rule] Rule '$RuleName' already exists with identical configuration. No action taken." -foregroundColor Yellow
                if ($PassThru) { $existing | Write-Output }
            }
            return
        }
        if (-not $Force) { throw "Rule '$RuleName' exists with different configuration. Use -Force to apply changes (differences: $((($diffs.Keys | ForEach-Object { $_+':' }) -join ' ')))" }
        Write-VerboseMsg "[Add-Rule] Rule exists with differences. Redirecting to Update (Force)."
        return Update-Rule -Lb $Lb -Existing $existing
    }

    $fe = Resolve-FrontendIpConfig -Lb $Lb
    $pool = Resolve-BackendPool -Lb $Lb
    $probe = Resolve-Probe -Lb $Lb

    $details = @{ Action = 'Add'; RuleName = $RuleName; Frontend = $fe.Name; BackendPool = $pool.Name; Probe = $(if ($probe) { $probe.Name } else { $null }); Protocol = $Protocol; FrontendPort = $FrontendPort; BackendPort = $BackendPort; IdleTimeout = $IdleTimeoutInMinutes; FloatingIP = $EnableFloatingIP.IsPresent; DisableOutboundSnat = $DisableOutboundSnat.IsPresent; EnableTcpReset = $EnableTcpReset.IsPresent }
    if ($DryRun) { Write-PlannedChange -Verb 'Add' -Details $details; return }

    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$RuleName", 'Add Load Balancer Rule')) {
        Write-VerboseMsg '[Add-Rule] Adding rule configuration'
        $params = @{
            LoadBalancer            = $Lb
            Name                    = $RuleName
            Protocol                = $Protocol
            FrontendIpConfiguration = $fe
            BackendAddressPool      = $pool
            FrontendPort            = $FrontendPort
            BackendPort             = $BackendPort
        }
    if ($probe) { $params.Probe = $probe }
        if ($PSBoundParameters.ContainsKey('IdleTimeoutInMinutes')) { $params.IdleTimeoutInMinutes = $IdleTimeoutInMinutes }
        if ($EnableFloatingIP) { $params.EnableFloatingIP = $true }
        $requiresDisableSnat = Test-FrontendRequiresDisableSnat -Lb $Lb -Frontend $fe
        if ($DisableOutboundSnat) { 
            $params.DisableOutboundSNAT = $true 
        }
        elseif ($requiresDisableSnat -and $AutoFixOutboundSnat) {
            Write-VerboseMsg '[Add-Rule] AutoFixOutboundSnat: Setting DisableOutboundSNAT = true due to outbound rule referencing same frontend.'
            $params.DisableOutboundSNAT = $true
        }
        elseif ($requiresDisableSnat -and -not $DisableOutboundSnat) {
            throw "Rule requires -DisableOutboundSnat because outbound rule(s) reference frontend '$($fe.Name)'. Use -DisableOutboundSnat or -AutoFixOutboundSnat."
        }
        if ($EnableTcpReset) { $params.EnableTcpReset = $true }

        Add-AzLoadBalancerRuleConfig @params | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
        Write-VerboseMsg '[Add-Rule] Rule added successfully.'
        if ($PassThru) { Get-Rule -Lb $Lb -Name $RuleName | Write-Output }
    }
}

function Update-Rule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb,
        [Parameter()][object]$Existing
    )
    if (-not $RuleName) { throw '-RuleName is required for Update.' }
    $rule = if ($Existing) { $Existing } else { Get-Rule -Lb $Lb -Name $RuleName }
    if (-not $rule) { throw "Rule '$RuleName' not found for Update." }

    # Resolve existing linked objects; some properties on existing rule may be PSResourceId instead of the full object
    if ($FrontendIpConfigName) { $fe = Resolve-FrontendIpConfig -Lb $Lb } else {
        $fe = if ($rule.FrontendIpConfiguration -and $rule.FrontendIpConfiguration.GetType().Name -eq 'PSFrontendIPConfiguration') { $rule.FrontendIpConfiguration } else { 
            $fid = $rule.FrontendIpConfiguration.Id.Split('/')[-1]
            $Lb.FrontendIpConfigurations | Where-Object Name -eq $fid
        }
    }
    if ($BackendPoolName) { $pool = Resolve-BackendPool -Lb $Lb } else {
        $pool = if ($rule.BackendAddressPool -and $rule.BackendAddressPool.GetType().Name -eq 'PSBackendAddressPool') { $rule.BackendAddressPool } else {
            $poolId = $rule.BackendAddressPool.Id.Split('/')[-1]
            $Lb.BackendAddressPools | Where-Object Name -eq $poolId
        }
    }
    if ($ProbeName) { $probe = Resolve-Probe -Lb $Lb } else {
        $probe = if ($rule.Probe -and $rule.Probe.GetType().Name -eq 'PSProbe') { $rule.Probe } elseif ($rule.Probe) {
            $prid = $rule.Probe.Id.Split('/')[-1]
            $Lb.Probes | Where-Object Name -eq $prid
        } else { $null }
    }

    $frontendPort = if ($PSBoundParameters.ContainsKey('FrontendPort')) { $FrontendPort } else { $rule.FrontendPort }
    $backendPort = if ($PSBoundParameters.ContainsKey('BackendPort')) { $BackendPort }  else { $rule.BackendPort }
    $protocol = if ($PSBoundParameters.ContainsKey('Protocol')) { $Protocol }     else { $rule.Protocol }
    $idleTimeout = if ($PSBoundParameters.ContainsKey('IdleTimeoutInMinutes')) { $IdleTimeoutInMinutes } else { $rule.IdleTimeoutInMinutes }
    $floatingIp = if ($PSBoundParameters.ContainsKey('EnableFloatingIP')) { $EnableFloatingIP.IsPresent } else { $rule.EnableFloatingIP }
    $disableSnat = if ($PSBoundParameters.ContainsKey('DisableOutboundSnat')) { $DisableOutboundSnat.IsPresent } else { $rule.DisableOutboundSNAT }
    $tcpReset = if ($PSBoundParameters.ContainsKey('EnableTcpReset')) { $EnableTcpReset.IsPresent } else { $rule.EnableTcpReset }

    $details = @{ Action = 'Update'; RuleName = $RuleName; Frontend = $fe.Name; BackendPool = $pool.Name; Probe = $(if ($probe) { $probe.Name } else { $null }); Protocol = $protocol; FrontendPort = $frontendPort; BackendPort = $backendPort; IdleTimeout = $idleTimeout; FloatingIP = $floatingIp; DisableOutboundSnat = $disableSnat; EnableTcpReset = $tcpReset }
    if ($DryRun) { Write-PlannedChange -Verb 'Update' -Details $details; return }

    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$RuleName", 'Update Load Balancer Rule')) {
        Write-VerboseMsg '[Update-Rule] Applying updates'
        $params = @{
            LoadBalancer            = $Lb
            Name                    = $RuleName
            Protocol                = $protocol
            FrontendIpConfiguration = $fe
            BackendAddressPool      = $pool
            FrontendPort            = $frontendPort
            BackendPort             = $backendPort
        }
        if ($probe) { $params.Probe = $probe }
        if ($idleTimeout) { $params.IdleTimeoutInMinutes = $idleTimeout }
        if ($floatingIp) { $params.EnableFloatingIP = $true } else { $params.EnableFloatingIP = $false }
        $requiresDisableSnat = Test-FrontendRequiresDisableSnat -Lb $Lb -Frontend $fe
        if ($PSBoundParameters.ContainsKey('DisableOutboundSnat')) {
            $params.DisableOutboundSNAT = $disableSnat
        }
        elseif ($requiresDisableSnat -and $AutoFixOutboundSnat) {
            Write-VerboseMsg '[Update-Rule] AutoFixOutboundSnat: Setting DisableOutboundSNAT = true due to outbound rule referencing same frontend.'
            $params.DisableOutboundSNAT = $true
        }
        elseif ($requiresDisableSnat -and -not $rule.DisableOutboundSNAT) {
            throw "Existing rule must have DisableOutboundSNAT = true because outbound rule(s) reference frontend '$($fe.Name)'. Re-run with -DisableOutboundSnat or -AutoFixOutboundSnat."
        }
        else {
            $params.DisableOutboundSNAT = $rule.DisableOutboundSNAT
        }
        if ($tcpReset) { $params.EnableTcpReset = $true } else { $params.EnableTcpReset = $false }

        Set-AzLoadBalancerRuleConfig @params | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
        Write-VerboseMsg '[Update-Rule] Rule updated successfully.'
        if ($PassThru) { Get-Rule -Lb $Lb -Name $RuleName | Write-Output }
    }
}

function Remove-Rule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb
    )
    if (-not $RuleName) { throw '-RuleName is required for Remove.' }
    $existing = Get-Rule -Lb $Lb -Name $RuleName
    if (-not $existing) { Write-Warning "Rule '$RuleName' not found. Nothing to remove."; return }
    if ($DryRun) { Write-PlannedChange -Verb 'Remove' -Details @{ Action = 'Remove'; RuleName = $RuleName }; return }
    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$RuleName", 'Remove Load Balancer Rule')) {
        Write-VerboseMsg '[Remove-Rule] Removing rule'
    Remove-AzLoadBalancerRuleConfig -LoadBalancer $Lb -Name $RuleName -ErrorAction Stop | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
        Write-VerboseMsg '[Remove-Rule] Rule removed.'
    }
}

function Get-LBLoadBalancingRule([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    $rules = $Lb.LoadBalancingRules | Select-Object Name, Protocol, FrontendPort, BackendPort, @{n = 'Frontend'; e = { $_.FrontendIpConfiguration.Id.Split('/')[-1] } }, @{n = 'BackendPool'; e = { $_.BackendAddressPool.Id.Split('/')[-1] } }, @{n = 'Probe'; e = { if ($_.Probe) { $_.Probe.Id.Split('/')[-1] } } }, IdleTimeoutInMinutes, EnableFloatingIP, DisableOutboundSNAT, EnableTcpReset
    $rules | Sort-Object Name | Write-Output
}

function Get-LBProbeList([Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb) {
    $Lb.Probes | Select-Object Name, Protocol, Port, IntervalInSeconds, NumberOfProbes, RequestPath | Sort-Object Name
}

function Test-ProbeParams {
    if ($Action -in 'AddProbe', 'UpdateProbe') {
        if (-not $ProbeName) { throw '-ProbeName required.' }
        if ($Action -eq 'AddProbe' -and -not $ProbePort) { throw '-ProbePort required for AddProbe.' }
        if ($ProbeProtocol -in 'Http', 'Https' -and -not $ProbePath) { throw '-ProbePath required for Http/Https probe.' }
    }
}

function Add-Probe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb)
    Test-ProbeParams
    $existing = $Lb.Probes | Where-Object Name -eq $ProbeName
    if ($existing) {
        $diffs = @{}
        if ($ProbeProtocol -and $ProbeProtocol -ne $existing.Protocol) { $diffs.Protocol = @($existing.Protocol, $ProbeProtocol) }
        if ($ProbePort -and $ProbePort -ne $existing.Port) { $diffs.Port = @($existing.Port, $ProbePort) }
        if ($ProbeIntervalSeconds -and $ProbeIntervalSeconds -ne $existing.IntervalInSeconds) { $diffs.IntervalInSeconds = @($existing.IntervalInSeconds, $ProbeIntervalSeconds) }
        if ($ProbeThreshold -and $ProbeThreshold -ne $existing.NumberOfProbes) { $diffs.NumberOfProbes = @($existing.NumberOfProbes, $ProbeThreshold) }
        if ($ProbeProtocol -in 'Http','Https') {
            $existingPath = $existing.RequestPath
            if ($ProbePath -and $ProbePath -ne $existingPath) { $diffs.RequestPath = @($existingPath, $ProbePath) }
        }
        if ($diffs.Count -eq 0) {
            if ($DryRun) { Write-PlannedChange -Verb 'AddProbe (NoOp)' -Details @{ Action = 'AddProbe'; Name = $ProbeName; Note = 'Probe already exists with identical configuration' } }
            else { write-console "[Add-Probe] Probe '$ProbeName' already exists with identical configuration. No action taken." -foregroundColor Yellow; if ($PassThru) { $existing | Write-Output } }
            return
        }
        if (-not $Force) { throw "Probe '$ProbeName' exists with different configuration. Use -Force to apply changes." }
        Write-VerboseMsg '[Add-Probe] Probe exists with differences. Redirecting to Update (Force).'
        return Update-Probe -Lb $Lb
    }
    $details = @{Action = 'AddProbe'; Name = $ProbeName; Protocol = $ProbeProtocol; Port = $ProbePort; Interval = $ProbeIntervalSeconds; Threshold = $ProbeThreshold; Path = $ProbePath }
    if ($DryRun) { Write-PlannedChange -Verb 'AddProbe' -Details $details; return }
    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$ProbeName", 'Add Probe')) {
        $params = @{ LoadBalancer = $Lb; Name = $ProbeName; Protocol = $ProbeProtocol; Port = $ProbePort; IntervalInSeconds = $ProbeIntervalSeconds; ProbeCount = $ProbeThreshold }
        if ($ProbeProtocol -in 'Http', 'Https') { $params.RequestPath = $ProbePath }
        Add-AzLoadBalancerProbeConfig @params | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
        if ($PassThru) { Get-LBProbeList -Lb $Lb | Where-Object Name -eq $ProbeName }
    }
}

function Update-Probe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb)
    Test-ProbeParams
    $existing = $Lb.Probes | Where-Object Name -eq $ProbeName
    if (-not $existing) { throw "Probe '$ProbeName' not found." }
    $protocol = if ($PSBoundParameters.ContainsKey('ProbeProtocol')) { $ProbeProtocol } else { $existing.Protocol }
    $port = if ($PSBoundParameters.ContainsKey('ProbePort')) { $ProbePort } else { $existing.Port }
    $interval = if ($PSBoundParameters.ContainsKey('ProbeIntervalSeconds')) { $ProbeIntervalSeconds } else { $existing.IntervalInSeconds }
    $count = if ($PSBoundParameters.ContainsKey('ProbeThreshold')) { $ProbeThreshold } else { $existing.NumberOfProbes }
    $path = if ($protocol -in 'Http', 'Https') { if ($PSBoundParameters.ContainsKey('ProbePath')) { $ProbePath } else { $existing.RequestPath } } else { $null }
    $details = @{Action = 'UpdateProbe'; Name = $ProbeName; Protocol = $protocol; Port = $port; Interval = $interval; Threshold = $count; Path = $path }
    if ($DryRun) { Write-PlannedChange -Verb 'UpdateProbe' -Details $details; return }
    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$ProbeName", 'Update Probe')) {
        $params = @{ LoadBalancer = $Lb; Name = $ProbeName; Protocol = $protocol; Port = $port; IntervalInSeconds = $interval; ProbeCount = $count }
        if ($protocol -in 'Http', 'Https') { $params.RequestPath = $path }
        Set-AzLoadBalancerProbeConfig @params | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
        if ($PassThru) { Get-LBProbeList -Lb $Lb | Where-Object Name -eq $ProbeName }
    }
}

function Remove-Probe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]$Lb)
    if (-not $ProbeName) { throw '-ProbeName required for RemoveProbe.' }
    $existing = $Lb.Probes | Where-Object Name -eq $ProbeName
    if (-not $existing) { Write-Warning "Probe '$ProbeName' not found."; return }
    if ($DryRun) { Write-PlannedChange -Verb 'RemoveProbe' -Details @{Action = 'RemoveProbe'; Name = $ProbeName }; return }
    if ($PSCmdlet.ShouldProcess("$($Lb.Name)/$ProbeName", 'Remove Probe')) {
    Remove-AzLoadBalancerProbeConfig -LoadBalancer $Lb -Name $ProbeName | Out-Null
        Set-AzLoadBalancer -LoadBalancer $Lb | Out-Null
    }
}

main | Out-Null
