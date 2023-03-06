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
    $global:output = [convert]::ToBase64String([text.encoding]::UTF8.GetBytes($inputString))
    write-host "stringToBase64: $($global:output)"
}

if($base64ToString){
    write-host "base64ToString: [text.encoding]::UTF8.GetString([convert]::FromBase64String(`$inputString))" -ForegroundColor Green
    $global:output = [text.encoding]::UTF8.GetString([convert]::FromBase64String($inputString))
    write-host "base64ToString: $($global:output)"
}

if($urlEncodeToString) {
    Write-Host "urlEncodeToString: [web.httpUtility]::UrlDecode(`$inputString)" -ForegroundColor Green
    $global:output = [web.httpUtility]::UrlDecode($inputString)
    Write-Host "urlEncodeToString: $($global:output)"
}

if($stringToUrlEncode) {
    Write-Host "stringToUrlEncode: [web.httpUtility]::UrlEncode(`$inputString)" -ForegroundColor Green
    $global:output = [web.httpUtility]::UrlEncode($inputString)
    Write-Host "stringToUrlEncode: $($global:output)"
}

if($stringToRegexEscaped) {
    Write-Host "stringToRegexEscaped: [regex]::Escape(`$inputString)" -ForegroundColor Green
    $global:output = [regex]::Escape($inputString)
    Write-Host "stringToRegexEscaped: $($global:output)"
}

if($regexToStringUnescaped) {
    Write-Host "regexToStringUnescaped: [regex]::Unescape(`$inputString)" -ForegroundColor Green
    $global:output = [regex]::Unescape($inputString)
    Write-Host "regexToStringUnescaped: $($global:output)"
}

if($stringToCharArray) {
    write-host "stringToCharArray: `$inputString.ToCharArray() | foreach-object {[int][char]`$_}" -ForegroundColor Green
    $global:output = $inputString.ToCharArray() | foreach-object {[int][char]$_}
    write-host "stringToCharArray: $($global:output)"
}

if($charArrayToString) {
    write-host "charArrayToString: [string]::new(`$inputString)" -ForegroundColor Green
    $global:output = [string]::new($inputString)
    write-host "charArrayToString: $($global:output)"
}

write-host "output stored in `$global:output" -ForegroundColor Cyan


