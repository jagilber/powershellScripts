<#
download windbg appx package
# https://serverfault.com/questions/1018220/how-do-i-install-an-app-from-windows-store-using-powershell
#>

param(
  $packageFamilyName = 'Microsoft.WinDbg_8wekyb3d8bbwe', #'windbg-preview'
  $path = $pwd
)

write-host "
$WebResponse = Invoke-WebRequest `
  -Method 'POST' `
  -Uri 'https://store.rg-adguard.net/api/GetFiles' `
  -Body `"type=PackageFamilyName&url=$PackageFamilyName&ring=Retail`" `
  -ContentType 'application/x-www-form-urlencoded'
" -ForegroundColor Cyan

$WebResponse = Invoke-WebRequest `
  -Method 'POST' `
  -Uri 'https://store.rg-adguard.net/api/GetFiles' `
  -Body "type=PackageFamilyName&url=$PackageFamilyName&ring=Retail" `
  -ContentType 'application/x-www-form-urlencoded'

$global:WebResponse = $WebResponse
write-verbose $global:WebResponse
$linksMatch = @($WebResponse.Links -imatch '\.appx' | select href)
$downloadLinks = @($LinksMatch.href)

for ($i = 0; $i -lt $downloadLinks.Count; $i++) {
  $outDirectory = "$path\$packageFamilyName.$i"
  $outFile = "$outDirectory.appx"
  $zipFile = "$outDirectory.zip"

  if ((test-path $outDirectory)) {
    remove-item $outDirectory -Force
  }

  if ((test-path $outFile)) {
    remove-item $outFile -Force
  }

  if ((test-path $zipFile)) {
    remove-item $zipFile -Force
  }

  write-host "Invoke-WebRequest -Uri $downloadLinks[$i] -OutFile $outFile" -ForegroundColor Cyan
  Invoke-WebRequest -Uri $downloadLinks[$i] -OutFile $outFile
  
  Rename-Item $outFile $zipFile
  expand-archive $zipFile
  get-childItem "$outDirectory\*.exe"
}

