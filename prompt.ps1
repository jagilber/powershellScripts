<#
.SYNOPSIS
    Custom prompt for powershell
.DESCRIPTION
    Custom prompt for powershell
    in ps open $PROFILE and add the following:
    code $PROFILE

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/prompt.ps1" -outFile "$pwd\prompt.ps1";
    code $PROFILE
    code .\prompt.ps1
#>
$global:promptInfo = @{
    path       = $null
    branch     = $null
    branches   = @()
    remotes    = @()
    status     = $null
    ps         = if ($IsCoreCLR) { 'pwsh' } else { 'ps' }
    cacheTimer = [datetime]::MinValue
    enableGit  = $true
    cacheMinutes = 1
}
#[console]::ForegroundColor = 'Magenta'

function prompt() {
    $path = "'$pwd'".ToLower()
    try {
        if ($path -ne $promptInfo.path `
                -or (((get-date) - $promptInfo.cacheTimer).TotalMinutes) -gt $promptInfo.cacheMinutes `
                -or ($promptInfo.branch -and ($^ -and $^.startswith('git')))) {
            $promptInfo.cacheTimer = get-date
            $promptInfo.path = $path
            $promptInfo.status = get-gitInfo
        }

        $date = (get-date).ToString('HH:mm:ss')
        write-host "$($promptInfo.ps)@$date$($promptInfo.status) $path" -ForegroundColor Cyan
        return ">"
    }
    catch {
        write-host "Error: $($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return ">"
    }
}

function get-gitInfo() {
    $status = ""
    if (!$promptInfo.enableGit) {
        return $status
    }

    $promptInfo.branches = @(git branch)
    if (!$promptInfo.branches) {
        return $status
    }

    $promptInfo.branch = (($promptInfo.branches) -imatch '\*').TrimStart('*').Trim()
    $promptInfo.remotes = @(git remote)
    
    $status = " ($($promptInfo.branch))"
    $diff = @(git status --porcelain).count
    
    if ($diff -gt 0) {
        $status = " ($($promptInfo.branch)*$diff)"
    }

    foreach ($remote in $promptInfo.remotes) {
        #write-host "git rev-list --left-right --count $($remote)/$($promptInfo.branch)...$($promptInfo.branch)"
        try {
            $aheadBehind = git rev-list --left-right --count "$($remote)/$($promptInfo.branch)...$($promptInfo.branch)"
        }
        catch {
            $aheadBehind = "0 0"
        }
        if ($aheadBehind) {
            $aheadBehind = [regex]::replace($aheadBehind, '(\d+)\s+(\d+)', "$([char]0x2193)`$1/$([char]0x2191)`$2")
            $status += "[$($remote):$($aheadBehind)]"
        }
        #write-host "status:$($status)"
    }
    return $status
}
