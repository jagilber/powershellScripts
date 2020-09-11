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
    [switch]$matchLine
)

function main() {
    $error.clear()
    if ($matchLine) {
        $pattern = ".*$pattern.*"
    }
    
    $startTime = get-date
    $fileCount = 0
    $regex = [regex]::new($pattern, [text.regularexpressions.regexoptions]::Compiled -bor [text.regularexpressions.regexoptions]::IgnoreCase)
    $files = @(get-childitem -recurse:$includeSubDirs -file -path $path) | where Name -match $filePattern
    write-verbose "filtered files: $($files.FileName | fl * | out-string)"

    foreach ($file in $files) {
        $fileCount++
        $fs = $null

        try {
            write-verbose "checking $file"
            $line = 0
            $error.clear()
            $fs = [io.streamreader]::new($file)
            $content = $fs.readtoend()
            if ($content.Length -lt 1) { continue }

            if ($regex.IsMatch($content)) {
                write-host $file -ForegroundColor Yellow
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
                        write-host "  $($line):$($match | select index, length, value)"
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

    write-host "finished total files:$($filecount) total matches: $($matchCount) total minutes: $((get-date).Subtract($startTime).TotalMinutes)"
}

main