<#
.SYNOPSIS
    powershell script to search for and optionally replace guids in files doing a matched search and replace by guid

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/regenerate-guids.ps1" -outFile "$pwd\regenerate-guids.ps1";
    .\regenerate-guids.ps1 [-path] [-pattern]

.EXAMPLE
    example to search template.json files in the templates directory and subdirectories for guids and replace them with new guids
    .\regenerate-guids.ps1 -pattern '%old thumbprint%' `
        -path '\templates' `
        -filePattern 'template\.json' `
        -includeSubDirs `
        -replace `
        -createBackup `
        -whatIf
#>

[cmdletbinding()]
param(
  [string]$path = $pwd,
  [string]$filePattern = '.*',
  [switch]$includeSubDirs,
  [switch]$replace, # = $null,
  [ValidateSet($null, '00000000-0000-0000-0000-000000000000', 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX', '12345678-1234-1234-1234-123456789012')]
  [string]$replaceMask = $null, # normally null, but can be set to a non unique global mask pattern to replace with ex: '00000000-0000-0000-0000-000000000000'
  [string]$guidExcludePattern = $null, # = '00000000-0000-0000-0000-000000000000',
  [switch]$createBackup,
  [switch]$whatIf,
  [string]$backupExtension = '.bak',
  [string]$pattern = '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}',
  [switch]$quiet
)
  
$global:matchedFiles = @{}
$global:guidMap = @{}

function main() {
  $startTime = get-date
  $error.clear()
  if ($filePattern.startsWith('*')) {
    $filePattern = '.' + $filePattern
    # $filePattern = [regex]::escape($filePattern)
    write-console "escaped filePattern: $filePattern"
  }
    
  $fileCount = 0
  $regex = [regex]::new($pattern, [text.regularexpressions.regexoptions]::Compiled -bor [text.regularexpressions.regexoptions]::IgnoreCase)
  $files = @(@(get-childitem -recurse:$includeSubDirs -file -path $path) | Where-Object Name -match $filePattern).FullName
    
  write-console "filtered files: $($files | Format-List * | out-string)" -verbose
  $totalFiles = $files.count
  write-console "checking $totalFiles files"

  foreach ($file in $files) {
    $fileCount++
    $sr = $null
    write-console "checking $fileCount of $totalFiles  $file" -ForegroundColor DarkGray
    if ([io.path]::GetExtension($file) -ieq $backupExtension) {
      write-console "skipping backup file $file" -ForegroundColor Yellow
      continue
    }

    try {
      $line = 0
      $error.clear()
      $sr = [io.streamreader]::new($file)
      $content = $sr.readtoend()

      if ($content.Length -lt 1) { continue }
      # read first 100 bytes or max length if less than 100 bytes to check if file is binary or text, then reset position
      $testContent = $content.substring(0, [math]::min(100, $content.Length))
      $bytes = [system.text.encoding]::UTF8.GetBytes($testContent)
      $isBinary = $false
      foreach ($byte in $bytes) {
        if ($byte -lt 32 -and $byte -ne 9 -and $byte -ne 10 -and $byte -ne 13) {
          write-console "skipping binary file $file" -ForegroundColor Yellow
          $isBinary = $true
          break
        }
      }

      if ($isBinary) { continue }
      $sr.basestream.position = 0

      if ($regex.IsMatch($content)) {
        write-console $file -ForegroundColor Magenta
        [void]$global:matchedFiles.Add($file, [collections.arraylist]::new())
      }
      else {
        write-console "no matches in file $file" -verbose
        continue
      }

      $sr.basestream.position = 0
      [text.stringbuilder]$replaceContent = [text.stringbuilder]::new()
      while ($null -ne ($content = $sr.ReadLine())) {
        $line++

        if ($content.Length -lt 1) { continue }

        if ($regex.IsMatch($content)) {
          $regexMatches = $regex.Matches($content)

          foreach ($match in $regexMatches) {
            if ($match.Length -lt 1) { continue }
            $excluded = $false
            $groupsTable = @{}
            $g = $match.groups[0]
            # foreach ($g in $match.groups) {
            $replaceValue = $replaceMask
            if (!$replaceMask) {
              $replaceValue = [guid]::newguid().tostring()
            }

            if ($guidExcludePattern -and $g.value -match $guidExcludePattern) {
              write-console "skipping guid:$($g.value)" -ForegroundColor Yellow
              $excluded = $true
            }

            [void]$groupsTable.add($g.name, $g.value)
            # add to guidMap with key as name and value as new guid
            if (!($global:guidMap[$g.value])) {
              $global:guidMap[$g.value] = @{
                newGuid  = if (!$excluded) { $replaceValue } else { $null }
                oldGuid  = $g.value
                count    = 1
                files    = @($file)
                excluded = $excluded
              }
            }
            else {
              $global:guidMap[$g.value].count++
              $replaceValue = $global:guidMap[$g.value].newGuid

              if (!($global:guidMap[$g.value].files -contains $file)) {
                $global:guidMap[$g.value].files += $file
              }
            }
            # }

            $matchCount++
            $matchObj = [ordered]@{
              file   = $file
              line   = $line
              index  = $match.index
              length = $match.Length
              value  = $match.value
              #captures = $match.captures
              groups = $groupsTable
            }
                        
            [void]$global:matchedFiles.$file.add($matchObj)
            write-console "  $($line):$($match | Select-Object index, length, value)"

            if ($replace -and !$excluded) {
              $newLine = $regex.Replace($content, $replaceValue)
              write-console "replacing line:$($line) match:'$($match.value)' with '$replaceValue'`n`toldLine:'$content'`n`tnewLine:'$newLine'" -ForegroundColor Cyan
              [void]$replaceContent.AppendLine($newLine)
            }
          }
        }
        else {
          #if ($null -ne $replace) {
          [void]$replaceContent.AppendLine($content)
        }
      }

      if ($replace) {
        if ($sr -ne $null) {
          $sr.close()
          $sr.dispose()
        }

        if ($createBackup) {
          write-console "saving backup file $file$backupExtension" -ForegroundColor Green
          if (!$whatIf) {
            [io.file]::copy($file, "$file$backupExtension", $true)
          }
        }
                
        # remove readonly if set
        $att = [io.file]::GetAttributes($file)

        if ($att -band [io.fileAttributes]::ReadOnly) {
          write-console "attempting to remove readonly attribute from file $file" -ForegroundColor Yellow
          $att = $att -band (-bnot [io.fileAttributes]::ReadOnly)
          if (!$whatIf) {
            [io.file]::SetAttributes($file, $att)
          }
        }
    
        write-console "saving replacements in file $file" -ForegroundColor Green
        if (!$whatIf) {
          [io.file]::WriteAllText($file, $replaceContent.ToString())
        }
      }    
    }
    catch {
      write-console "error processing file $file" -ForegroundColor Red
      write-console $_.exception.message -ForegroundColor Red
    }
    finally {
      if ($null -ne $sr) {
        $sr.close()
        $sr.dispose()
      }
    }
  }
  if ($global:matchedFiles.Count) {
    write-console "matched files summary:" -ForegroundColor Green

    foreach ($m in $global:matchedFiles.getenumerator()) {
      write-console "`t$($m.key) matches:$($m.value.count)" -ForegroundColor Cyan
    }

    write-console (convertto-json $global:guidMap) -foregroundColor Cyan
    write-console "$($global:matchedFiles.Count) matched files in global variable: `$global:matchedFiles guid map:`$global:guidMap" -ForegroundColor Magenta
    write-console "to view: `$global:matchedFiles | convertto-json" -ForegroundColor Magenta
  }
  else {
    write-console "0 matched files" -ForegroundColor Yellow
  }
  write-console "finished: total files:$($filecount) total matched files:$($global:matchedFiles.count) total matches:$($matchCount) total minutes:$((get-date).Subtract($startTime).TotalMinutes)" -ForegroundColor Magenta
}

function write-console([object]$msg, [consolecolor]$foregroundColor = [consolecolor]::White, [switch]$verbose) {
  if ($quiet -or $verbose) { 
    Write-Verbose ($msg | Out-String)
  }
  else { 
    write-host $msg -ForegroundColor $foregroundColor 
  }
}

main
