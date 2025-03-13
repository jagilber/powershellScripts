<#
.SYNOPSIS
    Parses ETL files into csv format using pktmon or netsh

.DESCRIPTION
    This script reads Windows ETL files.
    The script uses pktmon or netsh to convert the ETL files to CSV format.

.NOTES
    File Name      : parse-etl-files.ps1
    Author         : jagilber

.EXAMPLE
    .\parse-etl-files.ps1 -etlFilesPath "C:\Windows\Logs\WindowsUpdate" -outputDir "C:\Windows\Logs\WindowsUpdate\csv" -useNetsh -etlMaxProcessorInstance 4 -tmfPath "C:\users\Public\TMF" -sort -force -sleepSeconds 1 

.PARAMETER etlFilesPath
    Path to the directory containing the WindowsUpdate ETL files

.PARAMETER etlFileFilter
    Filter for the ETL files. Default is "*.etl"

.PARAMETER useNetsh
    Using pktmon to parse the ETL files is about 33% faster than netsh but not available on all systems

.PARAMETER outputFile
    If specified, the script will save the parsed entries to a CSV file or JSON file

.PARAMETER outputDir
    Directory to save the parsed CSV files

.PARAMETER etlMaxProcessorInstance
    Maximum number of ETL files to process simultaneously

.PARAMETER tmfPath
    Path to the TMF files

.PARAMETER sort
    Sort the entries by level

.PARAMETER force
    Overwrite existing files

.PARAMETER sleepSeconds
    Number of seconds to wait between checking for completed jobs

.PARAMETER loadFunctions
    Load the script functions

#>
[cmdletbinding()]
param(
  # [Parameter(Mandatory = $true)]
  [string]$etlFilesPath, # Path to the directory containing the WindowsUpdate ETL files
  [string]$etlFileFilter = "*.etl",
  [switch]$useNetsh, # Using pktmon to parse the ETL files is about 33% faster than netsh but not available on all systems
  # [string]$outputFile, #= "$pwd\WindowsUpdate.csv" # if specified, the script will save the parsed entries to a CSV file or JSON file
  [string]$outputDir = $etlFilesPath,
  [int]$etlMaxProcessorInstance = 4,
  [string]$tmfPath = 'C:\users\Public\TMF',
  [switch]$sort,
  [switch]$force,
  [int]$sleepSeconds = 1,
  [switch]$loadFunctions,
  [switch]$includeSubdirectories = $false
)

$global:startTime = get-date
$global:etlEventEntries = [System.Collections.ArrayList]::New()
$global:outputFiles = @{}
$global:scriptName = $null #$MyInvocation.ScriptName #"$psscriptroot\$($MyInvocation.MyCommand.Name)"
#$commandLine = $global:myinvocation.myCommand.definition
$scriptParams = $PSBoundParameters

function main() {
  try {
    $global:scriptName = $MyInvocation.ScriptName
    if (!(test-path $etlFilesPath)) {
      get-help  $global:scriptName -Examples
      write-error "The specified path does not exist: $etlFilesPath"
      return $null
    }

    $process = if ($usepktmon) { 'pktmon' } else { 'netsh' }
    write-log "@(get-childItem -Path $etlFilesPath -Filter $etlFileFilter -Recurse:$includeSubdirectories)"
    $etlFiles = @(get-childItem -Path $etlFilesPath -Filter $etlFileFilter -Recurse:$includeSubdirectories)
    $usepktmon = !$useNetsh -and ($null -ne (Get-Command -Name pktmon -ErrorAction SilentlyContinue))
    $totalFiles = $etlFiles.Count
    $count = 0
    remove-jobs

    if ($totalFiles -gt 0) {
      foreach ($etlFile in $etlFiles) {
        monitor-processes -maxCount $etlMaxProcessorInstance -process $process
        $count++
        write-log -data  "file $count of $totalFiles"
        $outputFile = "$outputDir\$([io.path]::GetFileNameWithoutExtension($etlFile)).csv"
        # write-log -data  "netsh trace convert input=`"$etlFile`" output=`"$outputFile`" report=no overwrite=yes"
        # start-process -FilePath $process -ArgumentList "trace convert input=`"$etlFile`" output=`"$outputFile`" report=no overwrite=yes" -NoNewWindow
        
        write-progress -Activity "Processing ETL files" -Status "Processing $etlFile" -PercentComplete (($etlFiles.IndexOf($etlFile) / $totalFiles) * 100)
        [void]$global:outputFiles.Add($outputFile, (format-etlFile -fileName $etlFile.FullName -outputFileName $outputFile -usepktmon $usepktmon))
      }
      wait-jobs
      # wait for all processes to finish
      # monitor-processes -maxCount 0 -process $process
      # foreach ($outputFile in $global:outputFiles.GetEnumerator()) {
      #   if ($usepktmon) {
      #     # $eventEntries = read-pktmonCsvFile -fileName $outputFile.key
      #     $outputFileName = "$($outputFile.key).json"
      #     # $job = (read-pktmonCsvFile -fileName $outputFile.key -outputFile $outputFile) &
      #     # $job = start-job -ScriptBlock { param($fileName, $outputFile) read-pktmonCsvFile -fileName $fileName -outputFile $outputFile } -ArgumentList $outputFile.key, $outputFile
      #     $job = start-job -ScriptBlock { 
      #       param($global:scriptName, $scriptParams, $fileName, $outputFile)
      #       Start-Sleep -Seconds 5
      #       # Wait-Debugger
      #       [void]$scriptParams.Add("loadFunctions", $true)
      #       write-host ". $global:scriptName @scriptParams"
      #       . $global:scriptName @scriptParams

      #       write-host "read-pktmonCsvFile -fileName $fileName -outputFile $outputFile "
      #       read-pktmonCsvFile -fileName $fileName -outputFile $outputFile 
      #     } -ArgumentList ($MyInvocation.ScriptName, $scriptParams, $outputFile.key, $outputFileName) -Debug

      #     if ($DebugPreference -ine "SilentlyContinue") {
      #       write-log -data 'debugging job' -ForegroundColor Cyan
      #       #Wait-Debugger
      #       #Start-Sleep -Seconds 5
      #       debug-job -Job $job.childjobs[0] -BreakAll -Debug
      #       # debug-job -Job $job -BreakAll -Debug
      #       pause
      #     }
      #   }
      #   else {
      #     $eventEntries = read-netshCsvFile -fileName $outputFile.key
      #   }
      
      #   [void]$global:etlEventEntries.AddRange(@($eventEntries))
      # }
      wait-jobs
    }
    else {
      write-error "No ETL files found in the specified directory: $etlFilesPath"
      return $null
    }

    # save-toFile -outputFile $outputFile
    $levelGroups = $global:etlEventEntries.Level | Group-Object | Sort-Object | Select-Object Count, Name

    write-log -data  "Level Counts:$($levelGroups| out-string)" -ForegroundColor Cyan
    write-log -data  "Total entries: $($global:etlEventEntries.Count)"
    write-log -data  "Entries saved to `$global:etlEventEntries"
    
    return $global:etlEventEntries
  }
  catch {
    write-log -data  "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    return $null
  }
}

function format-etlFile([string]$fileName, [string]$outputFileName, [bool]$usepktmon) {
  write-verbose "format-etlFile:$fileName"
  $error.clear()
  $result = $false
  $parentDir = split-path -Path $outputFileName
  
  if (!(test-path $parentDir)) {
    write-log -data  "md (split-path -Path $outputFileName)" -ForegroundColor Cyan
    mkdir $parentDir
  }
  if (!$outputFileName) {
    $outputFileName = "$fileName.csv"
  }
  if ((test-path -PathType Leaf -Path $outputFileName)) {
    write-warning "file exists: $outputFileName"
    if ($force) {
      write-warning "remove-item -Path $outputFileName -Force"
      remove-item -Path $outputFileName -Force
    }
    else {
      return $null
    }
  }

  if ($usepktmon) {
    write-log -data  "pktmon etl2txt $fileName -o $outputFileName -m -v 5 -p $tmfPath" -ForegroundColor Cyan
    $job = pktmon etl2txt $fileName -o $outputFileName -m -v 5 -p $tmfPath &
    #    $eventEntries = read-pktmonCsvFile -fileName $outputFileName
  }
  else {
    write-log -data  "netsh trace convert input=$fileName output=$outputFileName" -ForegroundColor Cyan
    $job = netsh trace convert input=$fileName output=$outputFileName &
    #   $eventEntries = read-netshCsvFile -fileName $outputFileName
  }

  write-log -data $job -ForegroundColor Green

  if ($error -or $LASTEXITCODE -ne 0) {
    write-log -data  "Failed to parse ETL file: $fileName" -ForegroundColor Red
    return $null
  }

  # remove-item -Path $outputFileName -Force

  write-log -data  "format-etlFile: $fileName - $($eventEntries.Count) entries"
  return $eventEntries
}

function monitor-processes([int]$maxCount, [string]$process) {
  while ($true) {
    if ((get-process) -match $process) {
      $instanceCount = (get-process -Name ($process)).Length
      write-log -data  "instance count:$($instanceCount)"

      if ($instanceCount -ge $maxCount) {
        write-log -data  "waiting for $($process) instances to finish."
        write-log -data  " current instance count: $($instanceCount) seconds waiting: $($count++)"
        start-sleep -Seconds 1
        continue
      }
    }
    break
  }
}

function remove-jobs() {
  try {
    foreach ($job in get-job) {
      write-log -data "removing job $($job.Name)"
      write-log -data $job
      $job.StopJob()
      Remove-Job $job -Force
    }
  }
  catch {
    write-log -data "error:$($Error | out-string)"
    $error.Clear()
  }
}

function save-toFile([string]$outputFile) {
  if (!$outputFile) { return }
  write-log -data  "Saving entries to $outputFile" -ForegroundColor Cyan

  if ((test-path -PathType Leaf -Path $outputFile)) {
    write-warning "remove-item -Path $outputFile -Force"
    remove-item -Path $outputFile -Force
  }

  if ($outputFile.ToLower().EndsWith(".json")) {
    $global:etlEventEntries | ConvertTo-Json | Out-File -FilePath $outputFile
  }
  else {
    # export-csv does not format datetime correctly
    $streamWriter = [IO.StreamWriter]::New($outputFile, $false)
    $streamWriter.WriteLine("Time,PID,TID,Level,Keyword,Provider,Event,Info")

    foreach ($entry in $global:etlEventEntries) {
      $line = "$($entry.time.ToString('o')),$($entry.pid),$($entry.tid),$($entry.level),$($entry.keyword),$($entry.provider),$($entry.event),$($entry.info),"
      $streamWriter.WriteLine($line)
    }
    $streamWriter.Close()
  }
}

function wait-jobs() {
  write-log "monitoring jobs"
  while (get-job) {
    foreach ($job in get-job) {
      $jobInfo = (receive-job -Id $job.id)
      if ($jobInfo) {
        write-log -data $jobInfo
      }
      else {
        write-log -data ($job | Format-List *)
      }

      if ($job.state -ine "running") {
        write-log -data ($job | Format-List *)

        if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
          write-log -data $job
        }

        write-log -data $job
        remove-job -Id $job.Id -Force  
      }

      write-progressInfo
      start-sleep -Seconds $sleepSeconds
    }
  }

  write-log "finished jobs"
}

function write-log($data, [consoleColor]$foregroundColor = 'White') {
  if (!$data) { return }
  [text.stringbuilder]$stringData = New-Object text.stringbuilder
  
  if ($data.GetType().Name -eq "PSRemotingJob") {
    foreach ($job in $data.childjobs) {
      if ($job.Information) {
        $stringData.appendline(@($job.Information.ReadAll()) -join "`r`n")
      }
      if ($job.Verbose) {
        $stringData.appendline(@($job.Verbose.ReadAll()) -join "`r`n")
      }
      if ($job.Debug) {
        $stringData.appendline(@($job.Debug.ReadAll()) -join "`r`n")
      }
      if ($job.Output) {
        $stringData.appendline(@($job.Output.ReadAll()) -join "`r`n")
      }
      if ($job.Warning) {
        write-warning (@($job.Warning.ReadAll()) -join "`r`n")
        $stringData.appendline(@($job.Warning.ReadAll()) -join "`r`n")
        $stringData.appendline(($job | format-list * | out-string))
        $global:resourceWarnings++
      }
      if ($job.Error) {
        write-error (@($job.Error.ReadAll()) -join "`r`n")
        $stringData.appendline(@($job.Error.ReadAll()) -join "`r`n")
        $stringData.appendline(($job | format-list * | out-string))
        $global:resourceErrors++
      }
      if ($stringData.tostring().Trim().Length -lt 1) {
        return
      }
    }
  }
  else {
    $stringData = "$(get-date):$($data | format-list * | out-string)"
  }

  write-host $stringData
}

function write-progressInfo() {
  $ErrorActionPreference = $VerbosePreference = 'silentlycontinue'
  $errorCount = $error.Count
  # write-verbose "Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue"
  # $deploymentOperations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName -ErrorAction silentlycontinue
  $jobInfo = (get-job)
  $jobInfo.ChildJobs | ForEach-Object {
    $job = $_
    $status = $job.State
    $currentOperation = $job.Name
    $status = "$status $($job.StatusMessage). $($job.Progress)"
    if (!$currentOperation -or $job.State -ieq "Completed") {
      # $status = "$status $($job.Output)"
    }
    else {
      Write-Progress -Activity $currentOperation -id ($count++) -Status $status
    }
  }
  $status = "time elapsed:  $(((get-date) - $global:startTime).TotalMinutes.ToString("0.0")) minutes. job count: $($jobInfo.ChildJobs.Count)" #`r`n"
  write-verbose $status
  # $pattern = "/subscriptions/(?<subscriptionId>.+?)/resourceGroups/(?<resourceGroup>.+?)/providers/(?<provider>.+?)/(?<providerType>.+?)/(?<resource>.+)"

  $count = 0
  
  if ($errorCount -ne $error.Count) {
    $error.RemoveRange($errorCount - 1, $error.Count - $errorCount)
  }

  # if ($detail) {
  $ErrorActionPreference = $VerbosePreference = 'continue'
  # }
}

if ($loadFunctions) {
  write-log -data  "loaded script functions" -ForegroundColor Cyan
}
else {
  main
}