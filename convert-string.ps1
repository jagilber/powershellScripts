param(
    [Parameter(Mandatory=$true)]
    [object]$inputString,
    [switch]$stringToBase64,
    [switch]$base64ToString,
    [switch]$urlEncodeToString,
    [switch]$stringToUrlEncode,
    [switch]$stringToRegexEscaped,
    [switch]$regexToStringUnescaped,
    [switch]$stringToCharArray,
    [switch]$charArrayToString
)


if($stringToBase64){
    write-host "stringToBase64: [convert]::ToBase64String([text.encoding]::UTF8.GetBytes(`$inputString))" -ForegroundColor Green
    write-host "stringToBase64: $([convert]::ToBase64String([text.encoding]::UTF8.GetBytes($inputString)))"
}

if($base64ToString){
    write-host "base64ToString: [text.encoding]::UTF8.GetString([convert]::FromBase64String(`$inputString))" -ForegroundColor Green
    write-host "base64ToString: $([text.encoding]::UTF8.GetString([convert]::FromBase64String($inputString)))"
}

if($urlEncodeToString) {
    Write-Host "urlEncodeToString: [web.httpUtility]::UrlDecode(`$inputString)" -ForegroundColor Green
    Write-Host "urlEncodeToString: $([web.httpUtility]::UrlDecode($inputString))"
}

if($stringToUrlEncode) {
    Write-Host "stringToUrlEncode: [web.httpUtility]::UrlEncode(`$inputString)" -ForegroundColor Green
    Write-Host "stringToUrlEncode: $([web.httpUtility]::UrlEncode($inputString))"
}

if($stringToRegexEscaped) {
    Write-Host "stringToRegexEscaped: [regex]::Escape(`$inputString)" -ForegroundColor Green
    Write-Host "stringToRegexEscaped: $([regex]::Escape($inputString))"
}

if($regexToStringUnescaped) {
    Write-Host "regexToStringUnescaped: [regex]::Unescape(`$inputString)" -ForegroundColor Green
    Write-Host "regexToStringUnescaped: $([regex]::Unescape($inputString))"
}

if($stringToCharArray) {
    write-host "stringToCharArray: `$inputString.ToCharArray() | foreach-object {[int][char]`$_}" -ForegroundColor Green
    write-host "stringToCharArray: $($inputString.ToCharArray() | foreach-object {[int][char]$_})"
}

if($charArrayToString) {
    write-host "charArrayToString: [string]::new(`$inputString)" -ForegroundColor Green
    write-host "charArrayToString: $([string]::new($inputString))"
}

#write-host "finished"


