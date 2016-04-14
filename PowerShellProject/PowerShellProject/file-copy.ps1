<#  
.SYNOPSIS  
    powershell script to copy files to remote machine
.DESCRIPTION  
    powershell script to copy files to remote machine using arguments -machineFile -sourcePath -destPath
    
.NOTES  
   File Name  : file-copy.ps1  
   Author     : jagilber
   Version    : 150413
 
.PARAMETER machineFile
    file containing list of machines (one per line) to copy files to. Example c:\temp\machines.txt
 
.PARAMETER sourcePath
    source path of files to copy. Example c:\temp\sourcefiles
 
.PARAMETER destPath
    dest path share of files to copy. Example admin$\temp
 
.EXAMPLE  
    .\file-copy.ps1 -machineFile machines.txt -sourcePath .\sourcefiles -destPath admin$\temp
    deploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp


#>  
 
Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter file containing list of remote machines to copy files to. one machine per line. example: c:\temp\machines.txt")]
    [string] $machineFile,
    [parameter(Position=1,Mandatory=$true,HelpMessage="Enter source folder containing files. example: c:\temp\sourcefiles")]
    [string] $sourcePath,
    [parameter(Position=2,Mandatory=$true,HelpMessage="Enter relative destination share path folder containing files. example: `"admin$\temp`"")]
    [string] $destPath
    )

 
 $logfile = "file-copy.ps1.log"
 
# ---------------------------------------------------------------------------------------------------------------
function main()
{
    if(![IO.File]::Exists($machineFile))
    {
        log-info "unable to find machineFile $($machineFile). exiting"
        return
    }
            
    if(![IO.Directory]::Exists($sourcePath))
    {
        log-info "unable to find source path $($sourcePath). exiting"
        return
    }

    if(![IO.Directory]::Exists("\\127.0.0.1\$($destPath)"))
    {
        log-info "unable to determine destination path \\127.0.0.1\$($destPath). exiting"
        return
    }

    # get source files
    $sourceFiles = [IO.Directory]::GetFiles($sourcePath, "*.*", [System.IO.SearchOption]::TopDirectoryOnly)

    [IO.StreamReader] $reader = new-object IO.StreamReader ($machineFile)
    while ($reader.Peek() -ge 0)
    {
        $machine = $reader.ReadLine()

        foreach($sourceFile in $sourceFiles)
        {
            $destFile = [IO.Path]::GetFileName($sourceFile)
            $destFile = "\\$($machine)\$($destPath)\$($destFile)"

            log-info "copying file $($sourceFile) to $($destFile)"

            try
            {
                [IO.File]::Copy($sourceFile, $destFile, $true)
            }
            catch
            {
                log-info "Exception:Copying File:$($sourceFile) to $($destFile): $($Error)"
                $Error.Clear()
            }
        }
    }

    log-info "finished"
}


# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    $data = "$([System.DateTime]::Now):$($data)`n"
    Write-Host $data
    out-file -Append -InputObject $data -FilePath $logFile
}

# ----------------------------------------------------------------------------------------------------------------
main