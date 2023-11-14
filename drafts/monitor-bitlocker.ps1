<#
monitor bitlocker settings for changes
#>


$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (!$isAdmin) {
    write-error "not administrator"
    return $result
}

$currentSettings = $null

while($true) {
    $newSettings = get-bitlockervolume
    if(!$currentSettings){
        $currentSettings = $newSettings
        $currentSettings
    }
    elseif([string]::compare($currentSettings,$newSettings) -ne 0) {
        [console]::beep(500,1000)
        $currentSettings = $newSettings
        write-warning "warning settings have changed"
        $currentSettings
    }

    start-sleep -seconds 10
}

