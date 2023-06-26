<#
.Synopsis
    ##DRAFT## script will be to restore service fabric cluster stateful applications from backup
.NOTES
    File Name: azure-az-sf-restore-backup.ps1
    Author   : jagilber
    Requires : azure az modules
  todo: add restore functions
.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-restore-backup.ps1" -outFile "$pwd/azure-az-sf-restore-backup.ps1";
    ./azure-az-sf-restore-backup.ps1

    https://learn.microsoft.com/en-us/rest/api/servicefabric/
    https://learn.microsoft.com/en-us/rest/api/servicefabric/sfclient-index-backuprestore
    https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/service-fabric/service-fabric-backup-restore-service-trigger-restore.md

.DESCRIPTION
    script to restore service fabric cluster stateful applications from backup
.PARAMETER connectionEndpoint
    service fabric cluster connection endpoint
.PARAMETER applicationName
    service fabric application name
.PARAMETER applicationId
    service fabric application id
.PARAMETER backupId
    service fabric backup id
.PARAMETER backupStorageAccountName
    service fabric backup storage account name
.PARAMETER thumbprint
    service fabric cluster certificate thumbprint
.PARAMETER containerName
    service fabric backup container name
.PARAMETER backupStorageAccountKey
    service fabric backup storage account key
.PARAMETER resourceGroupName
    azure resource group name
.PARAMETER apiVersion
    service fabric api version
.PARAMETER timeoutSeconds
    service fabric api timeout in seconds
.PARAMETER backupTimeoutMinutes
    service fabric backup timeout in minutes
.PARAMETER enableBackups
    enable service fabric backups
.PARAMETER startBackup
    start service fabric backup
.PARAMETER loadFunctionsOnly
    load functions only
.EXAMPLE
    ./azure-az-sf-restore-backup.ps1 -connectionEndpoint 'https://sfcluster.eastus.cloudapp.azure.com:19080' -applicationName 'fabric:/Voting' -applicationId '' -backupId '' -backupStorageAccountName '' -thumbprint '' -containerName 'backup' -backupStorageAccountKey '' -resourceGroupName 'sfcluster' -apiVersion '9.1' -timeoutSeconds '3' -backupTimeoutMinutes '10' -enableBackups -startBackup -loadFunctionsOnly
.EXAMPLE
    ./azure-az-sf-restore-backup.ps1 -connectionEndpoint 'https://sfcluster.eastus.cloudapp.azure.com:19080' -applicationName 'fabric:/Voting' -applicationId '' -backupId '' -backupStorageAccountName '' -thumbprint '' -containerName 'backup' -backupStorageAccountKey '' -resourceGroupName 'sfcluster' -apiVersion '9.1' -timeoutSeconds '3' -backupTimeoutMinutes '10' -enableBackups -startBackup
#>

[cmdletbinding()]
param(
  $connectionEndpoint = 'https://sfcluster.eastus.cloudapp.azure.com:19080',
  $applicationName = 'fabric:/Voting',
  $applicationId = '', #'Voting~VotingData',
  $backupId = '',
  $backupStorageAccountName = '',
  $thumbprint = '',
  $containerName = 'backup',
  $backupStorageAccountKey = '',
  $resourceGroupName = 'sfcluster',
  $apiVersion = '9.1',
  $timeoutSeconds = '3',
  $backupTimeoutMinutes = '10', # default is 10 minutes
  [switch]$enableBackups,
  [switch]$startBackup,
  [switch]$loadFunctionsOnly
)

$PSModuleAutoLoadingPreference = 'auto'
$global:httpStatusCode = 0
$maxResults = 100
$baseUrl = "$connectionEndpoint{0}?api-version=$apiVersion&timeout=$timeoutSeconds{1}"

function main() {
  write-host "starting $((get-date).tostring())" -foregroundColor yellow

  #get key if not provided
  if (!$backupStorageAccountKey) {
    if (!(get-azresourcegroup)) {
      connect-azaccount
    }

    if (!(get-azresourcegroup)) {
      write-host "failed to connect to azure" -foregroundColor red
      return
    }

    $backupStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $backupStorageAccountName).Value[0]

  }

  if (!$backupStorageAccountKey) {
    write-host "failed to get storage account key" -foregroundColor red
    return
  }

  write-host "get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Thumbprint -eq $thumbprint"
  $cert = Get-ChildItem -Path Cert:\ -Recurse | Where-Object Thumbprint -eq $thumbprint
  if (!$cert) {
    write-host "failed to get certificate for thumbprint: $thumbprint" -foregroundColor red
    return
  }
  else {
    write-host "found certificate for thumbprint: $thumbprint" -foregroundColor yellow
    write-host "subject: $($cert.Subject)" -foregroundColor yellow
    write-host "issuer: $($cert.Issuer)" -foregroundColor yellow
    write-host "issue date: $($cert.NotBefore)" -foregroundColor yellow
    write-host "expiration date: $($cert.NotAfter)" -foregroundColor yellow
  }

  if (!(get-clusterHealth)) {
    write-host "failed to get cluster health" -foregroundColor red
    return
  }

  if (!(get-clusterBackups)) {
    write-host "failed to get cluster backups" -foregroundColor red
    #return
  }

  if(!$enableBackups -or !$startBackup) {
    return
  }

  if (!$applicationName) {
    $applicationList = get-clusterApplicationList
    if (!$applicationList) {
      write-host "failed to get application list" -foregroundColor red
      return
    }
    write-host "select application to backup: $($applicationList | convertto-json)"
    write-host "application name is required" -foregroundColor red
    return
  }
  if(!$applicationId){
    $applicationId = (get-clusterApplicationList $applicationName).Id
  }

  if ($enableBackups) {
    if (!(create-clusterDailyAzureBackupPolicy)) {
      write-host "failed to create cluster backup policy" -foregroundColor red
      return
    }


    if (!(enable-clusterApplicationBackup $applicationId)) {
      write-host "failed to enable cluster backups" -foregroundColor red
      return
    }
  }

  if($startBackup) {
    if (!(start-partitionBackup $partitionId)) {
      write-host "failed to start partition backup" -foregroundColor red
      return
    }
  }
}

function create-clusterDailyAzureBackupPolicy() {
  $response = invoke-rest -method 'POST' `
    -absolutePath "/BackupRestore/BackupPolicies/$/Create" `
    -attributes @{ValidateConnection = $true } `
    -body (convertto-json @{
      Name                  = 'DailyAzureBackupPolicy'
      AutoRestoreOnDataLoss = $false
      MaxIncrementalBackups = 3
      Schedule              = @{
        ScheduleKind          = 'TimeBased'
        ScheduleFrequencyType = 'Daily'
        RunTimes              = @(
          "0001-01-01T09:00:00Z"
          "0001-01-01T17:00:00Z"
        )
      }
      Storage               = @{
        StorageKind      = 'AzureBlobStore'
        FriendlyName     = 'Azure_storagesample'
        ConnectionString = "DefaultEndpointsProtocol=https;AccountName=$backupStorageAccountName;AccountKey=$backupStorageAccountKey;EndpointSuffix=core.windows.net"
        ContainerName    = $containerName
      }
      RetentionPolicy       = @{
        RetentionPolicyType    = 'Basic'
        MinimumNumberOfBackups = 20
        RetentionDuration      = 'P3M'
      }
    })

  if ($global:httpStatusCode -eq 201) {
    write-host "created backup policy" -foregroundColor Green
    return $true
  }
  else {
    write-host "failed to create backup policy" -foregroundColor red
    return $false
  }
}

function enable-clusterApplicationBackup($applicationId) {
  $response = invoke-rest -method 'POST' -absolutePath "/Applications/$applicationId/$/EnableBackup" -body (convertto-json @{
      BackupPolicyName = "DailyAzureBackupPolicy"
    })
  return $response
}

function get-clusterApplicationBackupConfiguration($applicationId) {
  $response = invoke-rest -method 'GET' -absolutePath "/Applications/$applicationId/$/GetBackupConfigurationInfo" -attributes @{
    MaxResults = $maxResults
  }
  return $response
}

function get-clusterBackups() {
  write-host "get-clusterBackups"
  $response = invoke-rest -method 'POST' -absolutePath '/BackupRestore/$/GetBackups' -body (convertto-json @{
      Storage      = @{
        ConnectionString = "DefaultEndpointsProtocol=https;AccountName=$backupStorageAccountName;AccountKey=$backupStorageAccountKey;EndpointSuffix=core.windows.net"
        ContainerName    = $containerName
        StorageKind      = 'AzureBlobStore'
      }
      BackupEntity = @{
        EntityKind      = 'Application'
        ApplicationName = $applicationName
      }
    })

  if ($response.Items) {
    write-host "backups found" -foregroundColor Green
    write-host ($response.Items | convertto-json) -foregroundColor Green
    $BackupPoints = (ConvertFrom-Json $response.Items.BackupMetadata.BackupChainInfo.BackupPoints)
    $BackupPoints.Items

  }
  else {
    write-host "no backups found" -foregroundColor red
  }

  return $null
}

function get-clusterHealth() {
  write-host "get-clusterHealth"
  $response = invoke-rest -absolutePath '/$/GetClusterHealth'
  write-host "cluster health:$($response.AggregatedHealthState)" -foregroundColor Green
  return $response
}

function get-clusterApplicationList($applicationName = "`"`"") {

  $response = invoke-rest -method 'GET' -absolutePath "/Applications" -attributes @{
    MaxResults                   = $maxResults
    ApplictionTypeName           = $applicationName
    ExcludeApplicationParameters = $true
  }
  return $response
}

function get-clusterPartitionList($serviceId) {
  $response = invoke-rest -method 'GET' -absolutePath "/Services/$serviceId/$/GetPartitions"
  return $response
}

function get-clusterServiceList($applicationId) {
  $response = invoke-rest -method 'GET' -absolutePath "/Applications/$applicationId/$/GetServices"
  return $response
}

function invoke-rest($method = 'GET', $absolutePath, $body = $null, $attributes = @{}) {
  $response = $null
  $attributesString = $attributes.GetEnumerator() | ForEach-Object { "&$($_.Name)=$($_.Value)" } | Join-String
  $resultContent = $null

  try {
    $error.Clear()
    $url = $baseUrl -f $absolutePath, $attributesString

    if ($method -ieq 'POST') {
      write-host "Invoke-WebRequest -Uri '$url' ``
        -Method $method ``
        -ContentType 'application/json' ``
        -CertificateThumbprint $thumbprint ``
        -UseBasicParsing ``
        -SkipCertificateCheck ``
        -SkipHttpErrorCheck ``
        -Body $body
      " -ForegroundColor Magenta

      $response = Invoke-WebRequest -Uri $url `
        -Method $method `
        -ContentType 'application/json' `
        -CertificateThumbprint $thumbprint `
        -UseBasicParsing `
        -SkipCertificateCheck `
        -SkipHttpErrorCheck `
        -Body $body
    }
    else {
      write-host "Invoke-WebRequest -Uri '$url' ``
        -Method $method ``
        -CertificateThumbprint $thumbprint ``
        -UseBasicParsing ``
        -SkipCertificateCheck ``
        -SkipHttpErrorCheck
      " -ForegroundColor Magenta

      $response = Invoke-WebRequest -Uri $url `
        -Method $method `
        -CertificateThumbprint $thumbprint `
        -UseBasicParsing `
        -SkipCertificateCheck `
        -SkipHttpErrorCheck
    }
    if ($error -or !$response) {
      write-host "failed to invoke rest method:$url" -foregroundColor red
      return $null
    }

    $resultContent = $response.Content | convertfrom-json

    if (![string]::IsNullOrEmpty($resultContent.ContinuationToken)) {
      write-verbose "continuation token: $($resultContent.ContinuationToken)"
      if (!$attributes.ContainsKey('continuationToken')) {
        $attributes.ContinuationToken = $response.ContinuationToken
      }
      else {
        $attributes.ContinuationToken = $response.Content.ContinuationToken
      }

      $recurseResult = invoke-rest -method $method -absolutePath $absolutePath -body $body -attributes $attributes -continuationToken $response.ContinuationToken
      $resultContent.Items += $recurseResult.Content.Items
      #return $response.Content
    }

    $global:httpStatusCode = $response.StatusCode
    switch ($response.StatusCode) {
      200 {
        write-host "success" -foregroundColor Green
      }
      201 {
        write-host "created" -foregroundColor Green
      }
      202 {
        write-host "accepted" -foregroundColor Green
      }
      204 {
        write-host "no content" -foregroundColor Green
      }
      400 {
        write-host "bad request" -foregroundColor red
      }
      401 {
        write-host "unauthorized" -foregroundColor red
      }
      403 {
        write-host "forbidden" -foregroundColor red
      }
      404 {
        write-host "not found" -foregroundColor red
      }
      409 {
        write-host "conflict" -foregroundColor red
      }
      500 {
        write-host "internal server error" -foregroundColor red
      }
      default {
        write-host "unknown status code: $($response.StatusCode)" -foregroundColor red
      }
    }

    #format response
    $responseJson = $response.Content | convertfrom-json | convertto-json
    write-verbose "response: $responseJson"

    if ($resultContent.Items -ne $null) {
      return $resultContent.Items
    }
    return $response.Content
  }
  catch [Exception] {
    write-host "exception calling rest method:$url" -foregroundColor red
    write-host $error.Exception.Message -foregroundColor red
    write-host $error.Exception.InnerException.Message -ForegroundColor Red
    write-host $error.Exception.InnerException.StackTrace -ForegroundColor Red
    return $null
  }

}

function start-partitionBackup($partitionId) {
  $response = invoke-rest -method 'POST' -absolutePath "/Partitions/$partitionId/$/Backup" -body (convertto-json @{
      BackupStorage = @{
        StorageKind      = 'AzureBlobStore'
        ConnectionString = "DefaultEndpointsProtocol=https;AccountName=$backupStorageAccountName;AccountKey=$backupStorageAccountKey;EndpointSuffix=core.windows.net"
        ContainerName    = $containerName
      }
    }) `
    -attributes @{
    BackupTimeout = $backupTimeoutMinutes
  }
  return $response
}

if (!$loadFunctionsOnly) {
  main
}

