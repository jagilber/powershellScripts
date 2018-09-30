# cleans BOM from start of file in utf encoded files.
# BOM affects use of iwr %script% | iex
# this will convert files with BOM to utf-8 with no BOM
# https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom

param(
    $path = (get-location).path,
    $extensionFilter = "*.ps1",
    [switch]$listOnly
)

$Utf8NoBom = New-Object Text.UTF8Encoding($False)
$enc = [system.Text.Encoding]::UTF8

function main()
{
    foreach($file in get-childitem -Path $path -recurse -filter $extensionFilter)
    {
        if(has-bom -file $file)
        {
            write-host "file has bom: $($file.fullname)" -ForegroundColor Yellow

            if(!$listOnly)
            {
                write-warning "re-writing file without bom: $($file.fullname)"
                $content = Get-Content $file.fullname -Raw
                [System.IO.File]::WriteAllLines($file.fullname, $content, $Utf8NoBom)
            }
        }
        else
        {
            write-host "file does *not* have bom: $($file.fullname)" -ForegroundColor Green
        }
    }
}

function has-bom($file)        
{
    [Byte[]]$bom = Get-Content -Encoding Byte -ReadCount 4 -TotalCount 4 -Path $file.fullname

    foreach ($encoding in [text.encoding]::GetEncodings().GetEncoding()) 
    {
        $preamble = $encoding.GetPreamble()
    
        if ($preamble) 
        {
            foreach ($i in 0..$preamble.Length) 
            {
                if ($preamble[$i] -ne $bom[$i]) 
                {
                    continue
                }
                elseif ($i -eq $preable.Length) 
                {
                    return $true
                }
            }
        }
    }

    return $false
}

main

