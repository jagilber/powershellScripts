<#

#>
[cmdletBinding()]
param(
  [string]$repoPath = "$pwd",
  [string]$fileTypeExtensions = "*.md",
  [string]$OutputFile = "$pwd\link-checker.log",
  [string[]]$trimUnevenEndCharacters = @('()', '[]', '<>'),
  [string[]]$trimEndCharacters = @('.', '/', ';'), # quote and comma already removed
  [string[]]$excludedFiles = @(),
  [string[]]$excludedUrls = @(
    'cloudapp.azure.com',
    'core.windows.net',
    'contoso',
    ':19080',
    'servicefabric.azure.com',
    'vault.azure.net',
    '127.0.0.1',
    'localhost',
    '0.0.0.0',
    'ipinfo.io'
  )
)

$excludedUrlsPattern = ($excludedUrls -join '|')
$excludedFilesPattern = ($excludedFiles -join '|')

$files = Get-ChildItem -Path $repoPath -Recurse -Filter $fileTypeExtensions
foreach ($file in $files) {
  if ($excludedFiles -and $file.FullName -imatch $excludedFilesPattern) {
    Write-Host "Excluded file: $($file.FullName)" -ForegroundColor Gray
    continue
  }
  Write-Host "Checking file: $($file.FullName)" -ForegroundColor Cyan
  # Write-Host "Get-Content $($file.FullName) | Select-String -Pattern 'https:\/\/[^\s\)\"",\]]+' -AllMatches"
  $links = Get-Content $file.FullName | Select-String -Pattern "https:\/\/[^\s\`"',\]\}\{]+" -AllMatches
  foreach ($linkEntry in $links) {
    foreach ($match in $linkEntry.Matches) {
      $link = $match.Value.trim()
      # remove any non-printable characters
      $link = $link -replace "[^\u0020-\u007E]", ""
      if ($excludedUrlsPattern -and $link -imatch $excludedUrlsPattern) {
        Write-Host "Excluded link: $link" -ForegroundColor Gray
        continue
      }

      $trim = $true
      while ($trim) {
        $trim = $false
        foreach ($char in $trimEndCharacters) {
          if ($link.EndsWith($char)) {
            write-verbose "Trimming $char from $link"
            $link = $link.trimEnd($char)
            $trim = $true
          }
        }
        foreach ($pair in $trimUnevenEndCharacters) {
          # write-verbose "Checking $pair in $link"
          $beginChar = $pair[0]
          $endChar = $pair[1]
          if ($link.EndsWith($endChar)) {
            $leftCharCount = @($link.split($beginChar)).Count
            $rightCharCount = @($link.split($endChar)).Count
            if ($leftCharCount -ne $rightCharCount) {
              write-verbose "Trimming $endChar from $link"
              $link = $link.Substring(0, $link.Length - 1)
              $trim = $true
            }
          }
        }
      }

      Write-Host "Testing link: $link"
      try {
        Invoke-WebRequest -Uri $link -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
        $msg = "Link OK: $link"
        Write-Host $msg -ForegroundColor Green
        Add-Content -Path $OutputFile -Value $msg
      }
      catch {
        $msg = "Bad link: $link"
        Write-Host $msg -ForegroundColor Red
        Add-Content -Path $OutputFile -Value $msg
        # add a todo comment to markdown files in a comment block where the link was found
      }
    }
  }
}
