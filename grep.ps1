<#
.SYNOPSIS
    powershell script to search (grep) files in given path

.LINK
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/grep.ps1" -outFile "$pwd\grep.ps1";
    .\grep.ps1 [-path] [-pattern]
#>

[cmdletbinding()]
param(
    [string]$pattern = '.*',
    [string]$path = $pwd,
    [string]$filePattern = '.*',
    [switch]$includeSubDirs,
    [string]$replace,
    [switch]$createBackup,
    [switch]$matchLine,
    [switch]$whatIf,
    [string]$backupExtension = '.bak'
)

$global:matchedFiles = @{}

function main() {
    $error.clear()
    if ($matchLine) {
        $pattern = ".*$pattern.*"
    }
    
    $startTime = get-date
    $fileCount = 0
    $regex = [regex]::new($pattern, [text.regularexpressions.regexoptions]::Compiled -bor [text.regularexpressions.regexoptions]::IgnoreCase)
    $files = @(@(get-childitem -recurse:$includeSubDirs -file -path $path) | Where-Object Name -match $filePattern).FullName
    write-verbose "filtered files: $($files | Format-List * | out-string)"
    $totalFiles = $files.count
    write-host "checking $totalFiles files"

    foreach ($file in $files) {
        if ([io.path]::GetExtension($file) -ieq $backupExtension) {
            write-host "skipping backup file $file" -ForegroundColor Yellow
            continue
        }

        $fileCount++
        $sr = $null

        try {
            write-host "checking $fileCount of $totalFiles  $file" -ForegroundColor DarkGray
            $line = 0
            $error.clear()
            $sr = [io.streamreader]::new($file)
            $content = $sr.readtoend()

            if ($content.Length -lt 1) { continue }

            if ($regex.IsMatch($content)) {
                write-host $file -ForegroundColor Green
                [void]$global:matchedFiles.Add($file, [collections.arraylist]::new())
            }
            else {
                continue
            }

            $sr.basestream.position = 0
            [text.stringbuilder]$replaceContent = [text.stringbuilder]::new()

            while (($content = $sr.ReadLine()) -ne $null) {
                $line++
                if ($content.Length -lt 1) { continue }

                if ($regex.IsMatch($content)) {
                    $matches = $regex.Matches($content)

                    foreach ($match in $matches) {
                        if ($match.Length -lt 1) { continue }
                        $matchCount++
                        $matchObj = @{
                            line   = $line
                            index  = $match.index
                            length = $match.Length
                            value  = $match.value
                        }
                        
                        [void]$global:matchedFiles.$file.add($matchObj)
                        write-host "  $($line):$($match | Select-Object index, length, value)"

                        if ($replace) {
                            write-host "replacing line:$($line) match:'$($match.value)' with '$replace'" -ForegroundColor Yellow
                            [void]$replaceContent.AppendLine($regex.Replace($content, $replace))
                        }
                    }
                }
                else {
                    [void]$replaceContent.AppendLine($content)
                }
            }
        }
        finally {
            if ($sr -ne $null) {
                $sr.close()
                $sr.dispose()
            }
        }

        if ($replace) {
            if ($createBackup) {
                write-host "saving backup file $file$backupExtension" -ForegroundColor Green
                if (!$whatIf) {
                    [io.file]::copy($file, "$file$backupExtension", $true)
                }
            }
            
            # remove readonly if set
            $att = [io.file]::GetAttributes($file)
            if ($att -band [io.fileAttributes]::ReadOnly) {
                write-host "attempting to remove readonly attribute from file $file" -ForegroundColor Yellow
                $att = $att -band (-bnot [io.fileAttributes]::ReadOnly)
                if (!$whatIf) {
                    [io.file]::SetAttributes($file, $att)
                }
            }

            write-host "saving replacements in file $file" -ForegroundColor Green
            if (!$whatIf) {
                [io.file]::WriteAllText($file, $replaceContent.ToString())
            }
        }
    }

    write-host "matched files summary:" -ForegroundColor Green
    foreach ($m in $global:matchedFiles.getenumerator()) {
        write-host "`t$($m.key) matches:$($m.value.count)" -ForegroundColor Cyan
    }

    write-host
    write-host "matched files in global variable: `$global:matchedFiles" -ForegroundColor Magenta
    write-host "to view: `$global:matchedFiles | convertto-json" -ForegroundColor Magenta
    write-host "finished: total files:$($filecount) total matched files:$($global:matchedFiles.count) total matches:$($matchCount) total minutes:$((get-date).Subtract($startTime).TotalMinutes)" -ForegroundColor Magenta
}

main