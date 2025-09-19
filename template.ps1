<#
# AGENT INSTRUCTIONS (GENERALIZED TEMPLATE v1.1)
# Purpose: Baseline for new reusable PowerShell utility scripts (NOT limited to Azure). Ensures consistency, safety, testability, and clear user experience.
#
# MUST COMPLETE BEFORE COMMIT / RELEASE:
#  - Populate .SYNOPSIS, .DESCRIPTION (1-3 concise sentences each) and >=2 .EXAMPLE blocks (one basic, one advanced / with -WhatIf or -Diagnostics).
#  - All parameters documented with .PARAMETER entries (no orphan params in code or help).
#  - Script uses: [CmdletBinding(SupportsShouldProcess = $true)] if it can change system / external state; rely on built‑in -WhatIf / -Confirm (do NOT invent custom -whatIf).
#  - Idempotent behavior where practical: repeated runs do not duplicate work or corrupt state (document any unavoidable exceptions).
#  - Output: Structured objects via Write-Output / pipeline; minimal Write-Host (user guidance only). No mixing objects and plain strings on same pipeline step.
#  - Logging: Use write-console helper. Verbose = internal steps. Host = high-level start/finish & warnings. Errors bubble up (throw) and are aggregated once in main().
#  - Error Handling: Functions throw; only main() catches. Include inner exception chain text. No empty catch{} blocks. Avoid swallowing non-terminating errors silently.
#  - Parameter Validation: Use Mandatory, ValidateSet/Pattern/Range where applicable. Provide sensible defaults; avoid magic numbers (centralize constants).
#  - Approved Verbs: Function names use Get/Set/New/Remove/Test/Invoke/etc. No custom / unapproved verbs.
#  - Versioning: Maintain Version & Changelog in .NOTES. Increment version for any functional or instruction change. Keep newest entry at bottom of changelog list.
#  - Testing: Provide companion test harness script (scriptName.tests.ps1 or -test harness) covering: happy path, error path, idempotent re-run, -WhatIf / DryRun scenario. Tests must exit non-zero on failure.
#  - Style: Consistent indentation, case ($PSScriptRoot), single quoting where expansion not needed, avoid aliases (use Get-ChildItem not gci).
#  - Security: Never log secrets / tokens / passwords. Prefer SecureString / PSCredential for sensitive input. Sanitize objects before ConvertTo-Json if they may contain secrets.
#  - Performance: Minimize redundant external/service calls (cache list results within run). Batch operations where feasible. Avoid premature optimization; measure first.
#  - Diagnostics: Optional -Diagnostics switch may emit environment summary (PSVersion, runtime context, key parameter values) without leaking secrets.
#  - Exit Codes: main() returns 0 success, non-zero on failure. If script is meant for CI usage, explicitly exit (main). Otherwise just calling main is acceptable for interactive use.
#  - Self-Update (Optional): Pattern: -SelfUpdate compares remote hash or version; prompt unless -Force.
#  - PSScriptAnalyzer: Run Invoke-ScriptAnalyzer -Severity Warning,Error; resolve or explicitly document suppressions with justification.
#  - Verification Checklist (internal, may remove in final):
#     [ ] Help complete  [ ] Examples valid  [ ] Parameters validated  [ ] Idempotent  [ ] Tests added  [ ] Version bumped  [ ] Analyzer clean
#  - Keep main first. Add new functions alphabetically below placeholder section.
#  - Add all declarations to top of script (param, variables, constants).
#
# WHEN EXTENDING:
#  - Keep main first. Add new functions alphabetically below placeholder section.
#  - If adding new external dependencies, note them in .NOTES Requires line.
#  - For breaking changes, add a short MIGRATION NOTE comment near the changelog entry.
#  - Move all declarations to top of script (param, variables, constants).
#
# DO NOT:
#  - Invent custom progress or color wrappers if write-console already covers need.
#  - Force strict mode unless required by repo policy (can re-enable project-wide later).
#  - Store transient credentials in global variables.
#
# End Agent Instructions
.SYNOPSIS

.DESCRIPTION

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

.NOTES
    File Name  : template.ps1
    Author     : GitHubCopilot
    Requires   : <modules>
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.1
    Changelog  : 1.0 - Initial release
                 1.1 - Expanded agent instructions (generalized, structured checklist)
                 1.2 - Define WhatIf

.PARAMETER X

.EXAMPLE

.LINK
    # TLS NOTE / SUPPRESSION: Explicit TLS1.2 enable kept for legacy Windows PowerShell hosts that default to older protocols.
    # Modern PowerShell Core already negotiates TLS1.2+ automatically. Remove if unnecessary in target environment.
    # analyzer-suppress: HardCodedTLS (intentional for backward compatibility)
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/template.ps1" -outFile "$pwd\template.ps1";
    .\template.ps1 -examples
#>

#requires -version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$examples
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = 'continue'
$scriptName = "$psscriptroot\$($MyInvocation.MyCommand.Name)"

# always top function
function main() {
    if ($examples) {
        write-host "get-help $scriptName -examples"
        get-help $scriptName -examples
        return
    }

    try {

        # main logic here
        # create sub functions to handle specific / duplicate work
        # write-console <executable equivalent of command being executed for future copy/paste>
        # if(!$whatIf) {
        #   <command being executed>
        #}

        <#
        WhatIf Code Example:
        write-console "
        Test-azResourceGroupDeployment -ResourceGroupName $resourceGroup ``
            -TemplateFile $templateFile ``
            -Mode $mode ``
            -TemplateParameterObject $templateParameters ``
            @additionalParameters
        " -ForegroundColor Cyan
        
        if(!$whatIf) {
          $ret = Test-azResourceGroupDeployment -ResourceGroupName $resourceGroup `
            -TemplateFile $templateFile `
            -Mode $mode `
            -TemplateParameterObject $templateParameters `
            @additionalParameters
        }
        #>
    }
    catch {
        # always implement at least the following lines as is in all scripts for troubleshooting
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        return 1
    }
    finally {
        # perform any necessary cleanup
    }
}

# alphabetical list of functions
# ** ENSURE FUNCTIONS ARE REORGANIZED ALPHABETICALLY EXCEPT FOR main() **
# ** ENSURE ALL FUNCTIONS THROW ERRORS, DO NOT CATCH THEM **
# ** ONLY main() CATCHES ERRORS AND HANDLES LOGGING / EXIT CODES **

# function new-functionDefinition([type]$argument,...) {
    # write-console 'enter new-functionDefinition'
        
    # function logic

    # write-console 'exit new-functionDefinition $($result|convertto-json -depth 2)'
    # return $result
#}

function write-console($message, [consoleColor]$foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        write-warning($message)
    }
    elseif ($err) {
        write-error($message)
        throw
    }
}

main
