<#
.SYNOPSIS
    powershell script to search (grep) files in given path for regex pattern and optionally replace with new string.

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/ps-grep.ps1" -outFile "$pwd\ps-grep.ps1";
    .\ps-grep.ps1 [-path] [-pattern]

.EXAMPLE
    example to search clustermanifest.xml files for old thumbprint and replace with new thumbprint
    .\ps-grep.ps1 -pattern '%old thumbprint%' `
        -path 'd:\svcfab' `
        -filePattern 'clustermanifest.*.xml' `
        -includeSubDirs `
        -replace '%new thumbprint%' `
        -createBackup `
        -whatIf
#>

[cmdletbinding()]
param(
    [string]$pattern = '.*',
    [string]$path = $pwd,
    [string]$filePattern = '.*',
    [switch]$includeSubDirs,
    [object]$replace = $null,
    [switch]$createBackup,
    [switch]$matchLine,
    [switch]$whatIf,
    [string]$backupExtension = '.bak',
    [switch]$quiet
)

$global:matchedFiles = @{}

function main() {
    $startTime = get-date
    $error.clear()
    if ($matchLine) {
        $pattern = ".*$pattern.*"
    }
    
    if ($filePattern.startsWith('*')) {
        # $filePattern = [regex]::escape($filePattern)
        $filePattern = '.' + $filePattern
        write-console "escaped filePattern: $filePattern"
    }
    
    $fileCount = 0
    $regex = [regex]::new($pattern, [text.regularexpressions.regexoptions]::Compiled -bor [text.regularexpressions.regexoptions]::IgnoreCase)
    $files = @(@(get-childitem -recurse:$includeSubDirs -file -path $path) | Where-Object Name -match $filePattern).FullName
    
    write-verbose "filtered files: $($files | Format-List * | out-string)"
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
                continue
            }

            $sr.basestream.position = 0
            [text.stringbuilder]$replaceContent = [text.stringbuilder]::new()
            while ($null -ne ($content = $sr.ReadLine())) {
                $line++

                if ($content.Length -lt 1) { continue }

                if ($regex.IsMatch($content)) {
                    $matches = $regex.Matches($content)

                    foreach ($match in $matches) {
                        if ($match.Length -lt 1) { continue }
                        
                        $groupsTable = @{}
                        foreach ($g in $match.groups) {
                            [void]$groupsTable.add($g.name, $g.value)
                        }

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
                        $matchInfo = $match | Select-Object index, length, value
                        $matchInfo.value = highlight-regexMatches $match $content
                        write-console "  $($line):$($matchInfo)"

                        if ($null -ne $replace) {
                            $newLine = $regex.Replace($content, $replace)
                            write-console "replacing line:$($line) match:'$($match.value)' with '$replace'`n`toldLine:'$content'`n`tnewLine:'$newLine'" -ForegroundColor Cyan
                            [void]$replaceContent.AppendLine($newLine)
                        }
                    }
                }
                elseif ($null -ne $replace) {
                    [void]$replaceContent.AppendLine($content)
                }
            }
            if ($null -ne $replace) {
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

        write-console
        write-console "$($global:matchedFiles.Count) matched files in global variable: `$global:matchedFiles" -ForegroundColor Magenta
        write-console "to view: `$global:matchedFiles | convertto-json" -ForegroundColor Magenta
    }
    else {
        write-console "0 matched files" -ForegroundColor Yellow
    }
    write-console "finished: total files:$($filecount) total matched files:$($global:matchedFiles.count) total matches:$($matchCount) total minutes:$((get-date).Subtract($startTime).TotalMinutes)" -ForegroundColor Magenta
}

function highlight-regexMatches([text.RegularExpressions.Match]$match, [string]$InputString) {
    # Using ANSI escape sequences and string concatenation
    # $red = "$([char]27)[31m"
    $green = "$([char]27)[32m"
    $reset = "$([char]27)[0m"
    $output = $InputString

    foreach ($m in $match.Groups) {
        if($m.Name -eq '0' -and $match.Groups.Count -gt 1) { continue }
        $output = $output.Substring(0, $m.Index) + $green + $m.Value + $reset + $output.Substring($m.Index + $m.Length)
    }

    return $output
}

function write-console([object]$msg, [consolecolor]$foregroundColor = [consolecolor]::White) {
    if ($quiet) { 
        Write-Verbose ($msg | Out-String)
    }
    else { 
        write-host $msg -ForegroundColor $foregroundColor 
    }
}

main
