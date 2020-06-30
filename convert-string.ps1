param(
    [string]$inputString,
    [switch]$stringToBase64,
    [switch]$base64ToString
)


if($stringToBase64){
    write-host "stringToBase64: $([convert]::ToBase64String([text.encoding]::UTF8.GetBytes($inputString)))"
}

if($base64ToString){
    write-host "base64ToString: $([text.encoding]::UTF8.GetString([convert]::FromBase64String($inputString)))"
}

#write-host "finished"


