<#
.SYNOPSIS
    Custom prompt for powershell
.DESCRIPTION
    Custom prompt for powershell
    in ps open $PROFILE and add the following:
    code $PROFILE
    version 231116

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/prompt.ps1" -outFile "$pwd\prompt.ps1";
    code $PROFILE
    code .\prompt.ps1
#>

# autoload modules
$PSModuleAutoLoadingPreference = 2

$global:promptInfo = $null

function new-promptInfo() {
    if (!$global:promptInfo) {
        $global:promptInfo = @{
            path               = $null
            branch             = $null
            defaultBranchCount = 20
            branches           = @()
            remoteBranches     = @()
            remotes            = [collections.arraylist]::new()
            repo               = $null
            status             = $null
            ps                 = if ($IsCoreCLR) { 'pwsh' } else { 'ps' }
            cacheTimer         = [datetime]::MinValue
            enableGit          = $true
            cacheMinutes       = 1
            fetchedRepos       = [collections.arraylist]::new()
        }
    }
}

function prompt() {
    $path = "'$pwd'"#.ToLower()
    new-promptInfo

    try {
        $newPath = (!($promptInfo.path) -or ($path -ine $promptInfo.path))
        $isGitCommand = $^ -and $^.startswith('git') # sometimes this is not current
        $cacheTimeout = ((get-date) - $promptInfo.cacheTimer).TotalMinutes -gt $promptInfo.cacheMinutes

        if ($newPath -or $cacheTimeout -or $isGitCommand) {
            $promptInfo.cacheTimer = get-date
            $promptInfo.path = $path
            $promptInfo.status = get-gitInfo -newPath $newPath -gitCommand $isGitCommand -cacheTimeout $cacheTimeout
        }

        $date = (get-date).ToString('HH:mm:ss')
        #write-host "$($promptInfo.ps) $([char]0x23F2)$date" -ForegroundColor DarkGray -NoNewline
        write-host "$($promptInfo.ps) $date" -ForegroundColor DarkGray -NoNewline
        write-host "$($promptInfo.status)" -ForegroundColor DarkCyan -NoNewline
        write-host " $path" -ForegroundColor White
        return ">"
    }
    catch {
        write-host "Error: $($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return ">"
    }
}

function get-branches() {
    $branches = @(git branch)
    $remoteBranches = @(git branch -r)

    if ($branches -ne $promptInfo.branches -or $remoteBranches -ne $promptInfo.remoteBranches) {
        $promptInfo.branches = @(git branch)
        $promptInfo.remoteBranches = @(git branch -r)
        
        $additionalBranches = $promptInfo.branches.count - $promptInfo.defaultBranchCount
        $additionalBranchInfo = ""
        if ($additionalBranches -gt 0) {
            $additionalBranchInfo = "(+$additionalBranches) additional branches. all branches in `$promptInfo.branches"
        }
        write-host "local branches:`n$($promptInfo.branches | Select-Object -First $promptInfo.defaultBranchCount | Out-String)$additionalBranchInfo" -ForegroundColor DarkYellow

        $additionalBranches = $promptInfo.remoteBranches.count - $promptInfo.defaultBranchCount
        $additionalBranchInfo = ""
        if ($additionalBranches -gt 0) {
            $additionalBranchInfo = "(+$additionalBranches) additional remote branches. all remote branches in `$promptInfo.remoteBranches"
        }
        write-host "remote branches:`n$($promptInfo.remoteBranches | Select-Object -First $promptInfo.defaultBranchCount | Out-String)$additionalBranchInfo" -ForegroundColor DarkCyan
    }    

    return $promptInfo.branches
}

function get-currentBranch() {
    $currentBranch = @(git branch --show-current)
    if ($currentBranch -ne $promptInfo.branch) {
        write-debug "branch changed. continuing"
        $promptInfo.branch = $currentBranch
    }
    else {
        write-debug "branch is the same"
    }

    if (!$promptInfo.branch) {
        $promptInfo.repo = $null
        $promptInfo.status = ""
        write-debug "no branch found. returning"
        return $null
    }

    return $promptInfo.branch
}

function get-diffs() {
    $diff = @(git status --porcelain).count
    
    if ($diff -gt 0) {
        $promptInfo.status = " $([char]0x2325)($($promptInfo.branch)*$diff)"
    }
}

function get-remotes() {
    # only do this once per repo
    $pattern = "(?<remote>\S+?)\s+(?<repo>.+?)\s+?\(\w+?\)"
    $remotes = @(git remote -v)
    $remoteMatches = [regex]::Matches($remotes, $pattern)
    $promptInfo.remotes.clear()
    
    if (!$remoteMatches) {
        write-debug "no remotes found. returning"
        $promptInfo.repo = $null
        return $promptInfo.status = ""
    }

    $repo = $remoteMatches[0].groups['repo'].value
    $sameRepo = $repo -and $repo -eq $promptInfo.repo
    if (!$sameRepo -or $gitCommand) {
        $promptInfo.repo = $repo
        get-branches
    }
    else {
        write-debug "repo is the same"
    }

    foreach ($remoteMatch in $remoteMatches) {
        $remote = $remoteMatch.groups['remote'].value
        $repoRemote = "$repo/$remote/$($promptInfo.branch)"
        
        if (!($promptInfo.remotes.contains($remote))) {
            [void]$promptInfo.remotes.add($remote)
        }

        if (!($promptInfo.fetchedRepos.contains($repoRemote))) {
            [void]$promptInfo.fetchedRepos.add($repoRemote)
            write-host "fetching $repoRemote" -ForegroundColor DarkMagenta
            git fetch $remote
        }
    }

    return $promptInfo.remotes
}

function get-revisions() {
    foreach ($remote in $promptInfo.remotes) {
        try {
            $aheadBehind = git rev-list --left-right --count "$($remote)/$($promptInfo.branch)...$($promptInfo.branch)"
        }
        catch {
            $aheadBehind = "0 0"
        }
        if ($aheadBehind) {
            $aheadBehind = [regex]::replace($aheadBehind, '(\d+)\s+(\d+)', "$([char]0x2193)`$1/$([char]0x2191)`$2")
            $promptInfo.status += "[$($remote):$($aheadBehind)]"
        }
    }
}

function get-gitInfo([bool]$newPath = $false, [bool]$gitCommand = $false, [bool]$cacheTimeout = $false) {
    write-debug "get-gitInfo([bool]newPath = $newPath, [bool]gitCommand = $gitCommand, [bool]cacheTimeout = $cacheTimeout)"

    if (!$promptInfo.enableGit) {
        write-debug "git disabled. returning"
        return $promptInfo.status = ""
    }

    if (!(get-currentBranch)) {
        return $promptInfo.status = ""
    }

    if (!(get-remotes)) {
        return $promptInfo.status = ""
    }

    $promptInfo.status = " $([char]0x2325)($($promptInfo.branch))"

    get-diffs
    get-revisions

    write-debug "returning status: $status"
    return $promptInfo.status
}
