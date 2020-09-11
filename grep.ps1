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
    [switch]$includeSubDirs
)

$global:matchedFiles = @{}

function main() {
    $error.clear()
    $startTime = get-date
    $fileCount = 0
 
    $regex = [regex]::new($pattern, [text.regularexpressions.regexoptions]::Compiled -bor [text.regularexpressions.regexoptions]::IgnoreCase)
    $files = @(@(get-childitem -recurse:$includeSubDirs -file -path $path) | where Name -match $filePattern).FullName
    write-verbose "filtered files: $($files | fl * | out-string)"
    $totalFiles = $files.count
    write-host "checking $totalFiles files"

    foreach ($file in $files) {
        $fileCount++
        $fs = $null

        try {
            write-host "checking $fileCount of $totalFiles  $file" -ForegroundColor DarkGray
            $line = 0
            $error.clear()
            $fs = [io.streamreader]::new($file)
            $content = $fs.readtoend()
            if ($content.Length -lt 1) { continue }

            if ($regex.IsMatch($content)) {
                write-host $file -ForegroundColor Green
                [void]$global:matchedFiles.Add($file, [collections.arraylist]::new())
            }
            else {
                continue
            }

            $fs.basestream.position = 0

            while (($content = $fs.ReadLine()) -ne $null) {
                $line++
                if ($content.Length -lt 1) { continue }

                if ($regex.IsMatch($content)) {
                    $matches = $regex.Matches($content)

                    foreach ($match in $matches) {
                        if ($match.Length -lt 1) { continue }

                        $matchCount++
                        $matchObj = @{
                            lineNumber   = $line
                            index  = $match.index
                            length = $match.Length
                            value  = $match.value
                            line = $content
                            groups = $match.Groups
                        }
                        
                        [void]$global:matchedFiles.$file.add($matchObj)
                        write-host "  $($line):$($content)"
                    }
                }
            }
        }
        finally {
            if ($fs -ne $null) {
                $fs.close()
                $fs.dispose()
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
    write-host "to view groups, increase depth: `$global:matchedFiles | convertto-json -depth 4" -ForegroundColor Magenta
    write-host "finished: total files:$($filecount) total matched files:$($global:matchedFiles.count) total matches:$($matchCount) total minutes:$((get-date).Subtract($startTime).TotalMinutes)" -ForegroundColor Magenta
}

main