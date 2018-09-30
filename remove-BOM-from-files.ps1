<#
# cleans BOM from start of file in utf encoded files.
# BOM affects use of iwr %script% | iex
# this will convert files with BOM to utf-8 with no BOM
# https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom

example from iwr script download output

PS C:\Users\cloudadmin> $t = iwr "http://aka.ms/directory-treesize.ps1"
PS C:\Users\cloudadmin> $t | iex
iex : At line:58 char:7
+     do not display output

PS C:\Users\cloudadmin> $t | fl *
Content           : {239, 187, 191, 60...}
StatusCode        : 200
StatusDescription : OK
RawContentStream  : Microsoft.PowerShell.Commands.WebResponseContentMemoryStream
RawContentLength  : 18585
RawContent        : HTTP/1.1 200 OK
...
                    X-Powered-By: ASP.NET

issue------>>>>     ???<#
                    .SYNOPSIS
                        powershell script to to enumerate directory summarizing in tree view directories over a given
                    size
#>

param(
    $path = (get-location).path,
    $extensionFilter = "*.ps1",
    [switch]$listOnly,
    [switch]$saveAsAscii,
    [switch]$force
)

$Utf8NoBom = New-Object Text.UTF8Encoding($False)

function main()
{
    foreach($file in get-childitem -Path $path -recurse -filter $extensionFilter)
    {   
        $hasBom = has-bom -file $file
        if($hasBom -or ($saveAsAscii -and $force))
        {
            if($hasBom)
            {
                write-host "file has bom: $($file.fullname)" -ForegroundColor Yellow
            }

            if(!$listOnly)
            {
                write-warning "re-writing file without bom: $($file.fullname)"
                $content = Get-Content $file.fullname -Raw

                if($saveAsAscii)
                {
                    out-file -InputObject $content -Encoding ascii -FilePath ($file.fullname)
                }
                else
                {
                    [System.IO.File]::WriteAllLines($file.fullname, $content, $Utf8NoBom)
                }
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

