<#
.SYNOPSIS
    Load environment variables from .env file into current PowerShell session.

.DESCRIPTION
    Reads a .env file (default: .env in script root) and sets environment variables 
    for the current PowerShell session. Supports comments (#) and blank lines.
    Does not override existing environment variables unless -Force is specified.

.PARAMETER Path
    Path to the .env file. Defaults to .env in the script's directory.

.PARAMETER Force
    Override existing environment variables with values from .env file.

.PARAMETER Scope
    Scope for environment variables: Process (default), User, or Machine.
    Process scope only affects current session.

.EXAMPLE
    .\Load-EnvFile.ps1
    
    Loads variables from .env file in current directory.

.EXAMPLE
    .\Load-EnvFile.ps1 -Path "C:\config\.env.production" -Force
    
    Loads variables from specific file, overwriting existing variables.

.EXAMPLE
    . .\Load-EnvFile.ps1
    
    Dot-source to load variables into calling scope.

.NOTES
    Author: PowerShell Scripts Repository
    Version: 1.0
    Date: 2025-10-07
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Join-Path $PSScriptRoot ".env"),
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [ValidateSet('Process', 'User', 'Machine')]
    [string]$Scope = 'Process'
)

function Load-EnvFile {
    param(
        [string]$EnvFilePath,
        [bool]$OverrideExisting,
        [string]$VariableScope
    )
    
    if (-not (Test-Path $EnvFilePath)) {
        Write-Warning "Environment file not found: $EnvFilePath"
        Write-Host "Create one by copying .env.example to .env and filling in your values." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Loading environment variables from: $EnvFilePath" -ForegroundColor Cyan
    
    $loadedCount = 0
    $skippedCount = 0
    $loadedVars = @()
    
    Get-Content $EnvFilePath | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            return
        }
        
        # Parse KEY=VALUE format
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove quotes if present
            if ($value -match '^["''](.*)["`'']$') {
                $value = $matches[1]
            }
            
            $existingValue = [System.Environment]::GetEnvironmentVariable($key, $VariableScope)
            
            if ($existingValue -and -not $OverrideExisting) {
                Write-Verbose "Skipping $key (already set)"
                $skippedCount++
            }
            else {
                try {
                    # Only set if value is not empty
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        [System.Environment]::SetEnvironmentVariable($key, $value, $VariableScope)
                        Write-Verbose "Set $key = $value"
                        
                        # Mask sensitive values for display
                        $displayValue = $value
                        if ($key -match '(PASSWORD|SECRET|KEY|TOKEN)') {
                            $displayValue = "***MASKED***"
                        }
                        elseif ($value.Length -gt 50) {
                            $displayValue = $value.Substring(0, 47) + "..."
                        }
                        
                        $loadedVars += [PSCustomObject]@{
                            Variable = $key
                            Value = $displayValue
                        }
                        $loadedCount++
                    }
                }
                catch {
                    Write-Warning "Failed to set $($key): $($_.Exception.Message)"
                }
            }
        }
    }
    
    Write-Host "`n✓ Loaded $loadedCount environment variable(s)" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  Skipped $skippedCount existing variable(s) (use -Force to override)" -ForegroundColor Yellow
    }
    
    # Display loaded variables with values
    if ($loadedVars.Count -gt 0) {
        Write-Host "`nPopulated Variables:" -ForegroundColor Cyan
        $loadedVars | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    }
}

# Execute
try {
    Load-EnvFile -EnvFilePath $Path -OverrideExisting $Force.IsPresent -VariableScope $Scope
}
catch {
    Write-Error "Failed to load environment file: $($_.Exception.Message)"
    exit 1
}
