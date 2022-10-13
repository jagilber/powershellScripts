<#
update clipboard contents to add sourceuri similar to onenote
example autohotkey:
f8::
	RunWait, pwsh -WindowStyle Hidden -NonInteractive -NoProfile -File i:\githubshared\jagilber\powershellscripts\paste-with-sourceUri.ps1
	SendInput ^V
	return
#>

[cmdletbinding()]
param(

)

add-type -assemblyname system.windows.forms

$html = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Html)
$text = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Text)

write-verbose $html

if([regex]::isMatch($html,'SourceURL:')){
    $sourceUrl = [regex]::match($html,'(SourceURL:.+)').Groups[1].value
    write-verbose $sourceUrl
}

if($sourceUrl -and !([regex]::isMatch($text,'SourceURL:'))){
    $text = $text + [environment]::newLine + [environment]::newLine + $sourceUrl + [environment]::newLine
    #$text = $html # + [environment]::newLine + [environment]::newLine + $sourceUrl + [environment]::newLine
    write-verbose $text
    [System.Windows.Forms.Clipboard]::SetText($text)
}
