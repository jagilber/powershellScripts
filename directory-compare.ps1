# script to compare fileinfo for two directories
# saves file info to json file

param(
    $directory1 = "F:\c\All_DLLs\DLLs\Bad",
    $directory2 = "F:\c\All_DLLs\DLLs\Good",
    $directory1outputFile = "directory1.json",
    $directory2outputFile = "directory2.json",
    [switch]$detail
)

#-----------------------------------------------------------------------------------------------
function main()
{
    log-info "starting"
    if(!(test-path $directory1) -or !(test-path $directory2))
    {
        Write-Warning "one or more directories do not exist!. exiting"
        return
    }

    $directory1Files = [io.directory]::GetFiles($directory1, "*.*", [io.searchoption]::AllDirectories)
    $directory2Files = [io.directory]::GetFiles($directory2, "*.*", [io.searchoption]::AllDirectories)

    $directory1FileInfo = get-fileInfo -files $directory1Files -baseDir $directory1
    $directory2FileInfo = get-fileInfo -files $directory2Files -baseDir $directory2
    
    log-info "directory1 info:"
    $directory1FileInfo
    $directory1FileInfo | ConvertTo-Json -Depth 3 | out-file $directory1outputFile

    log-info "directory2 info:"
    $directory2FileInfo
    $directory2FileInfo | ConvertTo-Json -Depth 3 | out-file $directory2outputFile

    compare-fileInfo -filesInfo1 $directory1FileInfo -filesInfo2 $directory2FileInfo

    log-info "finished"
}

#-----------------------------------------------------------------------------------------------
function compare-fileInfo($filesInfo1, $filesInfo2)
{

    foreach($file1 in $filesInfo1.getenumerator())
    {
        if(!($filesInfo2.ContainsKey($file1.Key)))
        {
            Write-Warning  "$($file1.Key) in directory1 is *not* in directory2!"
        }
        else
        {
            $hash1 = Get-FileHash -Path $file1.Value.VersionInfo.FileName
            $hash2 = Get-FileHash -Path ($filesInfo2.($file1.Key)).VersionInfo.FileName
            
            if($hash1.hash -ine $hash2.hash)
            {
                Write-Warning  "$($file1.Key) hash in directory1 does *not* match $($file1.Key) hash directory2!"
            }
            else
            {
                if($detail)
                {
                    write-host "$($file1.Key) in directory1 *is* same as file in directory2" -ForegroundColor Green
                }
            }
        }
    }

    foreach($file2 in $filesInfo2.getenumerator())
    {
        if(!($filesInfo1.ContainsKey($file2.Key)))
        {
            Write-Warning  "$($file2.Key) in directory2 is *not* in directory1!"
        }
        else
        {
            $hash2 = Get-FileHash -Path $file2.Value.VersionInfo.FileName
            $hash1 = Get-FileHash -Path ($filesInfo1.($file2.Key)).VersionInfo.FileName
            
            if($hash1.hash -ine $hash2.hash)
            {
                Write-Warning  "$($file2.Key) hash in directory2 does *not* match $($file2.Key) hash directory1!"
            }
            else
            {
                if($detail)
                {
                    write-host "$($file2.Key) in directory2 *is* same as file in directory1" -ForegroundColor Green
                }
            }

        }

    }

}

#-----------------------------------------------------------------------------------------------
function get-fileInfo($files, $baseDir)
{
    $fileInfos = @{}

    foreach($file in $files)
    {
        $fileInfo = new-object io.fileInfo ($file)
        $fileInfos.Add($file.ToLower().Replace($baseDir.ToLower(), ''), $fileInfo)
    }

    return $fileInfos
}

#-----------------------------------------------------------------------------------------------
function md5hash($path)
{
    $fullPath = Resolve-Path $path
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $file = [System.IO.File]::Open($fullPath,[System.IO.Filemode]::Open, [System.IO.FileAccess]::Read)
    
    try 
    {
        return [System.BitConverter]::ToString($md5.ComputeHash($file))
    }
    catch
    {
        return $false
    }
    finally 
    {
        $file.Dispose()
    }
}

#-----------------------------------------------------------------------------------------------
function log-info($data)
{
    write-host "$(get-date) $($data)"
}
#-----------------------------------------------------------------------------------------------

main