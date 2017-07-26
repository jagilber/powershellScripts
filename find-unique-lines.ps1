<#  
.SYNOPSIS  
    powershell find unique lines in file
.DESCRIPTION  
    powershell script to find unique lines in file
.NOTES  
   File Name  : find-unique-lines.ps1 
   Author     : jagilber
   Version    : 150414
.EXAMPLE  
    .\find-unique-lines.ps1 -file c:\temp\test1.txt
    
.PARAMETER file
    the text file for compare

#>  

Param(

    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter path to first file")]
    [string] $file,
    [parameter(Position=1,Mandatory=$false,HelpMessage="Enter regex")]
    [string] $regex
    )

cls
$count = 0
$lineList = @{}
$logfile = "find-unique-lines.ps1.txt"
# ----------------------------------------------------------------------------------------------------------------
function main()
{
    if([IO.File]::Exists($file))
    {
        [IO.StreamReader] $reader = new-object IO.StreamReader ($file)
        while ($reader.Peek() -ge 0)
        {
            $line = $reader.ReadLine()

            if(![string]::IsNullOrEmpty($regex))
            {
                If([regex]::IsMatch($line, $regex, [Text.RegularExpressions.RegexOptions]::IgnoreCase))
                {
                    $line = [regex]::Match($line, $regex,[Text.RegularExpressions.RegexOptions]::IgnoreCase) 
                }
                else
                {
                    continue
                }

            }

           $count++
            if(!$lineList.ContainsKey($line))
            {
                $lineList.Add($line,1)
            }
            else
            {
                $oldvalue = $lineList[$line]
                $linelist.Remove($line)
                $lineList.Add($line,++$oldvalue)
            }

        }
    }
    else
    {
        log-info "file $($file) does not exist. exiting..."
        return
    }

    
    foreach($kvp in ($lineList.GetEnumerator() | sort Value))
    #foreach($kvp in $lineList)
    {
        log-info "$($kvp.Value):$($kvp.key)"
    }
    
    log-info "------------------------------------------------"
    log-info "Total Unique lines:$($lineList.Count)"
    log-info "Total lines:$($count)"

    log-info "finished"
}


# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    # $data = "$([DateTime]::Now):$($data)`n"
    Write-Host $data
  #  out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------

main

