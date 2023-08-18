<#
in ps open $PROFILE and add the following:
#>
$global:path = $null
$global:branch = $null
$global:diff = $null
$global:ps = if ($IsCoreCLR) { 'pwsh' } else { 'ps' }
#[console]::ForegroundColor = 'Magenta'

function prompt() {
    $path = "'$pwd'".ToLower()
    if ($path -ne $global:path) {
        $global:path = $path
        $global:branch = git branch --show-current
        if ($global:branch) {  
            $global:branch = " $global:branch"
            $global:diff = @(git status --porcelain).count
            if ($global:diff -gt 0) { 
                $global:branch = "$global:branch*($global:diff)" 
            }
        }
    }

    $date = (get-date).ToString('HH:mm:ss')
    write-host "$global:ps@$date$global:branch $path" -ForegroundColor Cyan
    return ">"
}