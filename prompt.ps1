<#
.SYNOPSIS
Custom prompt for powershell
.DESCRIPTION
Custom prompt for powershell
in ps open $PROFILE and add the following:
code $PROFILE
version 231121 add stashes list

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/prompt.ps1" -outFile "$pwd\prompt.ps1";
code $PROFILE
code .\prompt.ps1
#>

# autoload modules
$PSModuleAutoLoadingPreference = 2
#$DebugPreference = "Continue"
$global:promptInfo = $null
# set terminal tab completion same as editor
#Set-PSReadLineKeyHandler -Chord Tab -Function AcceptSuggestion
#Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete

# symbols
$branchSymbol = [char]0x2325
$deltaSymbol = [char]0x0394
$downArrow = [char]0x2193
$upArrow = [char]0x2191
$stashSymbol = [char]0x21B2

function prompt() {
    $path = "'$pwd'"#.ToLower()
    write-debug "prompt() path: $path command: $LastHistoryEntry"
    new-promptInfo

    try {
        $newPath = (!($promptInfo.path) -or ($path -ine $promptInfo.path))
        $isGitCommand = $LastHistoryEntry -and $LastHistoryEntry.tostring().startswith('git')
        $cacheTimeout = ((get-date) - $promptInfo.cacheTimer).TotalMinutes -gt $promptInfo.cacheMinutes

        if ($newPath -or $cacheTimeout -or $isGitCommand) {
            $promptInfo.cacheTimer = get-date
            $promptInfo.path = $path
            $promptInfo.status = get-gitInfo -newPath $newPath -gitCommand $isGitCommand -cacheTimeout $cacheTimeout
            $promptInfo.ps = get-psEnv
        }

        $date = (get-date).ToString('HH:mm:ss')
        write-host "$($promptInfo.ps)$(get-commandDuration) $date" -ForegroundColor DarkGray -NoNewline

        if ($promptInfo.enablePathOnPromptLine) {
            $path = $path.trim("'")
            write-host "$($promptInfo.status)" -ForegroundColor DarkCyan
            write-host "$path>" -ForegroundColor White -NoNewline
            return
        }
        else {
            write-host "$($promptInfo.status)" -ForegroundColor DarkCyan -NoNewline
            write-host " $path" -ForegroundColor White
            return ">"
        }
    }
    catch {
        write-host "Error: $($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red -NoNewline
        return "$path>"
    }
}

function add-status($status = "", [switch]$reset) {
    write-debug "add-status($status) reset: $reset current status: $($promptInfo.status)"
    if ($reset) {
        write-debug "resetting status"
        $promptInfo.status = $status
    }
    else {
        $promptInfo.status += $status
    }

    write-debug "new status: $($promptInfo.status)"
}


function get-branches() {
    write-debug "get-branches()"
    $branches = @(git branch)
    $branchesChanged = compare-object $branches $promptInfo.branches

    $remoteBranches = @(git branch -r)
    $remoteBranchesChanged = compare-object $remoteBranches $promptInfo.remoteBranches

    if ($branchesChanged) {
        write-debug "branches changed. $($branches) -ne $($promptInfo.branches)"
        $promptInfo.branches = @(git branch)
        $promptInfo.remoteBranches = @(git branch -r)
        
        $additionalBranches = $promptInfo.branches.count - $promptInfo.defaultBranchCount
        $additionalBranchInfo = ""
        if ($additionalBranches -gt 0) {
            $additionalBranchInfo = "(+$additionalBranches) additional branches. all branches in `$promptInfo.branches"
        }
        write-host "local branches:`n$($promptInfo.branches | Select-Object -First $promptInfo.defaultBranchCount | Out-String)$additionalBranchInfo" -ForegroundColor DarkYellow
        write-debug "changed branches:`n$($branchesChanged | out-string)"
    }
    else {
        write-debug "branches are the same"
    }

    if ($remoteBranchesChanged) {
        write-debug "remote branches changed. $($remoteBranches) -ne $($promptInfo.remoteBranches)"
        $additionalBranches = $promptInfo.remoteBranches.count - $promptInfo.defaultBranchCount
        $additionalBranchInfo = ""
        if ($additionalBranches -gt 0) {
            $additionalBranchInfo = "(+$additionalBranches) additional remote branches. all remote branches in `$promptInfo.remoteBranches"
        }
        write-host "remote branches:`n$($promptInfo.remoteBranches | Select-Object -First $promptInfo.defaultBranchCount | Out-String)$additionalBranchInfo" -ForegroundColor DarkCyan
        write-debug "changed branches:`n$($remoteBranchesChanged | out-string)"
    }    
    else {
        write-debug "remote branches are the same"
    }
}

function get-commandDuration() {
    $precision = 'ms'

    write-debug "get-commandDuration()"
    if (!$promptInfo.enableCommandDuration) {
        write-debug "command duration disabled. returning"
        return $null
    }

    $lastCommand = get-history -count 1
    if (!$lastCommand) {
        write-debug "no last command found. returning"
        $durationMs = 0
    }
    else {
        $durationMs = [int]$lastCommand.Duration.TotalMilliseconds.toString('.')
    }
    $result = '{0:N0}' -f $durationMs
    # $timespan = [timespan]::fromMilliseconds($durationMs)
    $promptInfo.commandDurationMs = $durationMs
    # $hours = $null
    # $minutes = $null
    # $seconds = $null
    # $milliseconds = $durationMs

    # if ($timespan.TotalMilliseconds -gt 1000) {
    #     $precision = 's'
    #     # $seconds = [int]($durationMs / 1000)
    #     # $milliseconds = $durationMs % 100
    
    #     if ($timespan.TotalSeconds -gt 60) {
    #         $precision = 'm'
    #         # $minutes = [int]($durationMs / 1000 / 60)
    #         # $seconds = $durationMs /1000 % 60
    #         # $milliseconds = $durationMs /1000 /60 % 60
    
    #         if ($timespan.TotalMinutes -gt 60) {
    #             $precision = 'h'
    #             # $hours = [int]($durationMs / 3600)
    #             # $minutes = $durationMs % 60
    #             # $seconds = $durationMs % 60
    #             # $milliseconds = $durationMs % 60
    #         }
    #     }
    # }

    # $result = $null
    # if ($timespan.hours) {
    #     $result = "$($timespan.hours):$($timespan.minutes):$($timespan.seconds).$($timespan.milliseconds)" #h"
    # }
    # elseif ($timespan.minutes) {
    #     $result = "$($timespan.minutes):$($timespan.seconds).$($timespan.milliseconds)" #m"
    # }
    # elseif ($timespan.seconds) {
    #     $result = "$($timespan.seconds).$($timespan.milliseconds)" #s"
    # }
    # elseif ($timespan.milliseconds -or $timespan.milliseconds -eq 0) {
    #     $result = "$($timespan.milliseconds)" #ms"
    # }

    return " $($deltaSymbol)$($result)$($precision)"
}

function get-currentBranch() {
    write-debug "get-currentBranch()"
    $currentBranch = @(git branch --show-current)
    $currentBranchChanged = compare-object $currentBranch $promptInfo.branch

    if ($currentBranchChanged) {
        write-debug "branch changed. continuing"
        $promptInfo.branch = $currentBranch
    }
    else {
        write-debug "current branch is the same"
    }

    if (!$promptInfo.branch) {
        $promptInfo.repo = $null
        add-status -reset
        write-debug "no branch found. returning"
        return $null
    }

    add-status " $($branchSymbol) ($($promptInfo.branch))"
    return $promptInfo.branch
}

function get-diffs() {
    write-debug "get-diffs()"
    $diff = @(git status --porcelain).Count
    if ($diff -gt 0) {
        add-status " $($branchSymbol) ($($promptInfo.branch)*$($diff))" -reset
    }
}

function get-remotes($gitCommand = $false) {
    write-debug "get-remotes($gitCommand)"
    $pattern = "(?<remote>\S+?)\s+(?<repo>.+?)\s+?\(\w+?\)"
    $remotes = @(git remote -v)
    $remoteMatches = [regex]::Matches($remotes, $pattern)
    [void]$promptInfo.remotes.clear()
    
    if (!$remoteMatches) {
        write-debug "no remotes found. returning"
        $promptInfo.repo = $null
        return $null
    }

    $repo = $remoteMatches[0].groups['repo'].value
    $sameRepo = $repo -and $repo -eq $promptInfo.repo
    if (!$sameRepo -or $gitCommand) {
        $promptInfo.repo = $repo
        $null = get-branches
    }
    else {
        write-debug "repo is the same"
    }

    foreach ($remoteMatch in $remoteMatches) {
        $remote = $remoteMatch.groups['remote'].value
        $repoRemote = "($remote/$($promptInfo.branch)) $repo"
        
        if (!($promptInfo.remotes.contains($remote))) {
            [void]$promptInfo.remotes.add($remote)
        }

        # only do this once per repo
        if (!($promptInfo.fetchedRepos.contains($repoRemote))) {
            [void]$promptInfo.fetchedRepos.add($repoRemote)
            write-host "fetching:$repoRemote" -ForegroundColor DarkMagenta
            git fetch $remote
        }
    }
}

function get-revisions() {
    write-debug "get-revisions()"
    foreach ($remote in $promptInfo.remotes) {
        try {
            $aheadBehind = git rev-list --left-right --count "$($remote)/$($promptInfo.branch)...$($promptInfo.branch)"
        }
        catch {
            $aheadBehind = "0 0"
        }
        if ($aheadBehind) {
            $aheadBehind = [regex]::replace($aheadBehind, '(\d+)\s+(\d+)', "$($downArrow)`$1/$($upArrow)`$2")
            add-status "[$($remote):$($aheadBehind)]"
        }
    }
}

function get-stashes() {
    write-debug "get-stashes()"
    $stashes = @(git stash list)
    $stashesChanged = compare-object $stashes $promptInfo.stashes
    
    if ($stashesChanged) {
        write-debug "stashes changed. $($stashes) -ne $($promptInfo.stashes)"
        $promptInfo.stashes = $stashes
        
        $additionalStashes = $promptInfo.stashes.count - $promptInfo.defaultBranchCount
        $additionalStashInfo = ""
        if ($additionalStashes -gt 0) {
            $additionalStashInfo = "(+$additionalStashes) additional stashes. all stashes in `$promptInfo.stashes"
        }
        write-host "stashes:`n$($promptInfo.stashes | Select-Object -First $promptInfo.defaultBranchCount | Out-String)$additionalStashInfo" -ForegroundColor Yellow
    }
    else {
        write-debug "stashes are the same"
    }

    if ($promptInfo.stashes) {
        write-debug "stashes found. adding to status"
        add-status "{$($stashSymbol)$($promptInfo.stashes.count)}"
    }
}

function get-gitInfo([bool]$newPath = $false, [bool]$gitCommand = $false, [bool]$cacheTimeout = $false) {
    write-debug "get-gitInfo([bool]newPath = $newPath, [bool]gitCommand = $gitCommand, [bool]cacheTimeout = $cacheTimeout)"
    add-status -reset

    if (!$promptInfo.enableGit) {
        write-debug "git disabled. returning"
        return (add-status -reset)
    }

    if (!(get-currentBranch)) {
        return (add-status -reset)
    }

    get-diffs
    get-stashes
    get-remotes -gitCommand $gitCommand
    get-revisions

    write-debug "returning status: $status"
    return $promptInfo.status
}

function get-psEnv() {
    write-debug "get-psEnv()"
    if ($env:VSCMD_VER) {
        $psEnv = "vs$($env:VSCMD_VER) "
    }
    $psEnv += if ($IsCoreCLR) { 'pwsh' } else { 'ps' }
    return $psEnv
}

function init-promptInfoEnv() {
    write-debug "init-promptInfo()"
    $openai = '\github\jagilber\powershellscripts\openai.ps1'
    if ((test-path $openai -WarningAction SilentlyContinue)) {
        . $openai -init -quiet
    }
    else {
        write-debug "openai.ps1 not found"
    }

}

function new-promptInfo() {
    if (!$global:promptInfo) {
        init-promptInfoEnv
        write-debug "new-promptInfo()"
        $global:promptInfo = @{
            path                   = ""
            branch                 = ""
            cacheMinutes           = 1
            branches               = @()
            defaultBranchCount     = 20
            remoteBranches         = @()
            remotes                = [collections.arraylist]::new()
            stashes                = [collections.arraylist]::new()
            repo                   = ""
            status                 = ""
            ps                     = get-psEnv
            cacheTimer             = [datetime]::MinValue
            enableGit              = $true
            enableCommandDuration  = $true
            enablePathOnPromptLine = $false
            fetchedRepos           = [collections.arraylist]::new()
            commandDurationMs      = 0
        }
    }
}
