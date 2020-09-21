Out-File -InputObject "$(get-date)" -FilePath c:\task-scripts\test.log

New-WinEvent -ProviderName Microsoft-Windows-Powershell `
    -id 4102 `
    -Payload @(
    "context:`r`n$(($MyInvocation | convertto-json -Depth 1))", 
    "user data:`r`n$(([environment]::GetEnvironmentVariables() | convertto-json))", 
    "task.ps1`r`nerror:`r`n$(($error | convertto-json -Depth 1))"
)
