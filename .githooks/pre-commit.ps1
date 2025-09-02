Param(
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

function Write-Info($msg){ Write-Host "[pre-commit] $msg" }
function Fail($msg){ Write-Host "`n[pre-commit][FAIL] $msg" -ForegroundColor Red; exit 1 }

if($env:PS_PRECOMMIT_SKIP){
    Write-Info 'PS_PRECOMMIT_SKIP set. Skipping all checks.'
    exit 0
}

# Allowlist file for ScriptAnalyzer rule names that should not cause failure even if severity=Error
$allowListFile = Join-Path $repoRoot '.scriptanalyzer-allowlist'
$ruleAllowList = @()
if(Test-Path $allowListFile){
    $ruleAllowList = Get-Content -LiteralPath $allowListFile | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
    if($ruleAllowList){ Write-Info "Loaded allowlist rules: $($ruleAllowList -join ', ')" }
}

# Gather staged PowerShell scripts
$staged = git -C $repoRoot diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -match '\.ps1$' }
if(-not $staged){
    Write-Info 'No staged PowerShell scripts. Skipping analyzer.'
    exit 0
}

Write-Info "Analyzing $($staged.Count) staged PowerShell script(s)"

# Enforce presence of .SYNOPSIS in each script (within first 150 lines)
$missingSynopsis = @()
foreach($file in $staged){
    $full = Join-Path $repoRoot $file
    if(-not (Test-Path $full)) { continue }
    try {
        $head = Get-Content -LiteralPath $full -TotalCount 150 -ErrorAction Stop
        if(-not ($head -match '(?im)^\s*\.SYNOPSIS')){ $missingSynopsis += $file }
    } catch { Write-Info "Could not read $file : $_" }
}
if($missingSynopsis){
    Fail ("Missing .SYNOPSIS header in: " + ($missingSynopsis -join ', '))
}

# Attempt to import PSScriptAnalyzer if available (unless skipped)
$analyzerAvailable = $false
if(-not $env:PS_PRECOMMIT_SKIP_ANALYZER){
    try {
        if(Get-Module -ListAvailable -Name PSScriptAnalyzer){ Import-Module PSScriptAnalyzer -ErrorAction Stop; $analyzerAvailable = $true }
    } catch { }
} else {
    Write-Info 'PS_PRECOMMIT_SKIP_ANALYZER set. Skipping ScriptAnalyzer.'
}

if($analyzerAvailable){
    $issues = Invoke-ScriptAnalyzer -Path ($staged | ForEach-Object { Join-Path $repoRoot $_ }) -Severity Error,Warning -Recurse -ErrorAction Continue
    if($issues){
        # Filter out allowlisted rule names from errors
        $effectiveErrors = @()
        foreach($iss in $issues){
            if($iss.Severity -eq 'Error'){
                if($ruleAllowList -and ($ruleAllowList -contains $iss.RuleName)) { continue }
                $effectiveErrors += $iss
            }
        }
        if($VerboseOutput){ $issues | Format-Table -AutoSize | Out-String | Write-Host }
        else { $issues | Select-Object Severity,RuleName,ScriptName,Line | Format-Table -AutoSize | Out-String | Write-Host }
        if($effectiveErrors){
            $names = ($effectiveErrors.RuleName | Sort-Object -Unique) -join ', '
            Fail "ScriptAnalyzer reported $($effectiveErrors.Count) non-allowlisted error(s): $names"
        }
        Write-Info "ScriptAnalyzer: 0 blocking errors, $(( $issues | Where-Object Severity -eq 'Warning').Count) warning(s)."
    } else { Write-Info 'ScriptAnalyzer: no findings.' }
} else {
    if(-not $env:PS_PRECOMMIT_SKIP_ANALYZER){ Write-Info 'PSScriptAnalyzer not found. (Install: Install-Module PSScriptAnalyzer -Scope CurrentUser)' }
}

# Secret scan (unless skipped)
if($env:PS_PRECOMMIT_SKIP_SECRETS){
    Write-Info 'PS_PRECOMMIT_SKIP_SECRETS set. Skipping secret scan.'
} else {
    $secretPatterns = @(
        '(?i)client[_-]?secret\s*=', '(?i)password\s*=', '-----BEGIN (RSA|EC|DSA)? ?PRIVATE KEY-----', '(?i)subscription[_-]?key', '(?i)api[_-]?key'
    )
    $secretHits = @()
    foreach($file in $staged){
        $full = Join-Path $repoRoot $file
        if(-not (Test-Path $full)) { continue }
        $content = Get-Content -Raw -LiteralPath $full
        foreach($pat in $secretPatterns){
            if($content -match $pat){
                $secretHits += [pscustomobject]@{ File=$file; Pattern=$pat }
            }
        }
    }
    if($secretHits){
        $secretHits | Format-Table -AutoSize | Out-String | Write-Host
        Fail 'Potential secret-like patterns detected. Review before committing (override by editing hook if intentional).'
    }
}

Write-Info 'All checks passed.'
exit 0
