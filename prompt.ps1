<#
in ps open $PROFILE and add the following:
code $PROFILE
#>
$global:path = $null
$global:branch = $null
$global:remotes = @()
$global:status = $null
$global:ps = if ($IsCoreCLR) { 'pwsh' } else { 'ps' }
$global:cacheTimer = [datetime]::MinValue
#[console]::ForegroundColor = 'Magenta'

function prompt() {
    $path = "'$pwd'".ToLower()
    try{
    if ($path -ne $global:path `
        -or (((get-date) - $global:cacheTimer).TotalMinutes) -gt 1 `
        -or ($global:branch -and ($^ -and $^.startswith('git')))) {
        $global:cacheTimer = get-date
        $global:path = $path
        $global:branch = git branch --show-current
        if ($global:branch) {  
            $global:status = get-gitInfo
        }
    }

    $date = (get-date).ToString('HH:mm:ss')
    write-host "$global:ps@$date$global:status $path" -ForegroundColor Cyan
    return ">"
    } catch {
        write-host "Error: $($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return ">"
    }
}

function get-gitInfo(){
    $global:remotes = @(git remote)
    $status = " ($global:branch)"
    $diff = @(git status --porcelain).count
    if ($diff -gt 0) { 
        $status = " ($global:branch*$diff)" 
    }

    foreach($remote in $global:remotes){
        #write-host "git rev-list --left-right --count $($remote)/$($global:branch)...$($global:branch)" 
        try{
            $aheadBehind = git rev-list --left-right --count "$($remote)/$($global:branch)...$($global:branch)"
        } catch {
            $aheadBehind = "0 0"
        }
        if($aheadBehind){
            $aheadBehind = [regex]::replace($aheadBehind, '(\d+)\s+(\d+)', 'v$1/^$2')
            $status += "[$($remote):$($aheadBehind)]"
        }
        #write-host "status:$($status)"
    }
    return $status
}