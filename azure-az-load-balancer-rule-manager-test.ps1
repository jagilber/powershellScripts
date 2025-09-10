<#+
.SYNOPSIS
    Test harness for azure-az-load-balancer-rule-manager.ps1
.DESCRIPTION
    Executes a full lifecycle test (List -> AddProbe -> Add Rule -> Update Rule -> List -> Remove Rule -> Remove Probe) against a specified Standard Load Balancer.
.PARAMETER ResourceGroup
    Target resource group.
.PARAMETER LoadBalancerName
    Load balancer name.
.PARAMETER RuleName
    Test rule name (default: test-lb-rule-50000)
.PARAMETER ProbeName
    Test probe name (default: test-probe-50000)
.PARAMETER FrontendPort
    Frontend/Backend port to use (default: 50000)
.PARAMETER DryRunOnly
    If specified, only performs DryRun operations.
.PARAMETER AddOnly
    Perform only AddProbe/Add Rule (no update or removal) and leave resources for manual verification.
.PARAMETER RemoveOnly
    Perform only removal (rule then probe) for provided names and exit.
.EXAMPLE
    .\azure-az-load-balancer-rule-manager-test.ps1 -ResourceGroup rg -LoadBalancerName lb
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$LoadBalancerName,
    [string]$RuleName = 'test-lb-rule-50000',
    [string]$ProbeName = 'test-probe-50000',
    [int]$FrontendPort = 50000,
    [switch]$DryRunOnly,
    [switch]$AddOnly,
    [switch]$RemoveOnly
)

if (($AddOnly -and $RemoveOnly) -or ($DryRunOnly -and ($AddOnly -or $RemoveOnly))) {
    throw 'Specify only one of: -DryRunOnly, -AddOnly, -RemoveOnly.'
}

$scriptPath = Join-Path $PSScriptRoot 'azure-az-load-balancer-rule-manager.ps1'
if (!(Test-Path $scriptPath)) { throw "Cannot locate rule manager script at $scriptPath" }

function Invoke-Step($Label, [scriptblock]$Script) {
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    try { & $Script } catch { Write-Warning "Step '$Label' failed: $($_.Exception.Message)"; throw }
}

$common = @{ ResourceGroup = $ResourceGroup; LoadBalancerName = $LoadBalancerName }

if ($RemoveOnly) {
    Invoke-Step 'Remove Rule (if exists)' { & $scriptPath @common -Action Remove -RuleName $RuleName }
    Invoke-Step 'Remove Probe (if exists)' { & $scriptPath @common -Action RemoveProbe -ProbeName $ProbeName }
    Invoke-Step 'List (post remove)' { & $scriptPath @common -Action List }
    Invoke-Step 'ListProbes (post remove)' { & $scriptPath @common -Action ListProbes }
    Write-Host 'RemoveOnly sequence complete.' -ForegroundColor Green
    return
}

# 1. List existing rules/probes (diagnostics)
Invoke-Step 'List (initial)' { & $scriptPath @common -Action List -Diagnostics }
Invoke-Step 'ListProbes (initial)' { & $scriptPath @common -Action ListProbes }

# 2. DryRun AddProbe
Invoke-Step 'AddProbe DryRun' { & $scriptPath @common -Action AddProbe -ProbeName $ProbeName -ProbeProtocol Tcp -ProbePort $FrontendPort -DryRun -PassThru }
if (-not $DryRunOnly) {
    Invoke-Step 'AddProbe' { & $scriptPath @common -Action AddProbe -ProbeName $ProbeName -ProbeProtocol Tcp -ProbePort $FrontendPort -PassThru }
}

# 3. DryRun Add Rule
Invoke-Step 'Add Rule DryRun' { & $scriptPath @common -Action Add -RuleName $RuleName -FrontendPort $FrontendPort -BackendPort $FrontendPort -Protocol Tcp -ProbeName $ProbeName -DryRun -PassThru }
if (-not $DryRunOnly) {
    Invoke-Step 'Add Rule' { & $scriptPath @common -Action Add -RuleName $RuleName -FrontendPort $FrontendPort -BackendPort $FrontendPort -Protocol Tcp -ProbeName $ProbeName -EnableTcpReset -PassThru }
}

if (-not $AddOnly) {
    # 4. Update Rule (idle timeout) dry run then apply
    Invoke-Step 'Update Rule DryRun' { & $scriptPath @common -Action Update -RuleName $RuleName -IdleTimeoutInMinutes 25 -DryRun -PassThru }
    if (-not $DryRunOnly) {
        Invoke-Step 'Update Rule' { & $scriptPath @common -Action Update -RuleName $RuleName -IdleTimeoutInMinutes 25 -PassThru }
    }
}

# 5. List after changes
Invoke-Step 'List (post changes)' { & $scriptPath @common -Action List }
Invoke-Step 'ListProbes (post changes)' { & $scriptPath @common -Action ListProbes }

if (-not $DryRunOnly -and -not $AddOnly) {
    # 6. Remove Rule (dry then real)
    Invoke-Step 'Remove Rule DryRun' { & $scriptPath @common -Action Remove -RuleName $RuleName -DryRun }
    Invoke-Step 'Remove Rule' { & $scriptPath @common -Action Remove -RuleName $RuleName }

    # 7. Remove Probe (dry then real)
    Invoke-Step 'Remove Probe DryRun' { & $scriptPath @common -Action RemoveProbe -ProbeName $ProbeName -DryRun }
    Invoke-Step 'Remove Probe' { & $scriptPath @common -Action RemoveProbe -ProbeName $ProbeName }

    # Final list
    Invoke-Step 'Final List' { & $scriptPath @common -Action List }
    Invoke-Step 'Final ListProbes' { & $scriptPath @common -Action ListProbes }
}

Write-Host 'Test sequence complete.' -ForegroundColor Green
