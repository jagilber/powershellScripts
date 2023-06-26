<#
.Synopsis
    script to restore service fabric cluster stateful applications from backup

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/drafts/azure-az-sf-restore-backup.ps1" -outFile "$pwd/azure-az-sf-restore-backup.ps1";
    ./azure-az-sf-restore-backup.ps1

    https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/service-fabric/service-fabric-backup-restore-service-trigger-restore.md
#>

[cmdletbinding()]
param(
  $connectionEndpoint = 'https://sfjagilber1nt5.eastus.cloudapp.azure.com:19080',
  $applicationName = 'fabric:/Voting',
  $applicationId = 'Voting~VotingData',
  $backupLocation = "https://$backupStorageAccountName.blob.core.windows.net/$containerName",
  $backupId = '',
  $backupStorageAccountName = '',
  $thumbprint = '',
  $containerName = 'backup',
  $backupStorageAccountKey = '',
  $resourceGroupName = 'sfjagilber1nt5',
  $apiVersion = '9.1',
  $timeoutSeconds = '3',
  [bool]$enableBackups = $true
)

$PSModuleAutoLoadingPreference = 'auto'
$global:httpStatusCode = 0
$sfHttpModule = 'Microsoft.ServiceFabric.Powershell.Http'
$baseUrl = "$connectionEndpoint{0}?api-version=$apiVersion&timeout=$timeoutSeconds{1}"

function main() {
  write-host "starting $((get-date).tostring())" -foregroundColor yellow

  if (!(get-azresourcegroup)) {
    connect-azaccount
  }

  if (!(get-azresourcegroup)) {
    write-host "failed to connect to azure" -foregroundColor red
    return
  }

  #get key if not provided
  if (!$backupStorageAccountKey) {
    $backupStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $backupStorageAccountName).Value[0]
    
  }
  if (!$backupStorageAccountKey) {
    write-host "failed to get storage account key" -foregroundColor red
    return
  }

  write-host "get-childitem -Path Cert:\CurrentUser -Recurse | Where-Object Thumbprint -eq $thumbprint"
  $cert = Get-ChildItem -Path Cert:\CurrentUser -Recurse | Where-Object Thumbprint -eq $thumbprint
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

function invoke-rest($method = 'GET', $absolutePath, $body = $null, $attributes = @{}) {
  $response = $null
  $attributesString = $attributes.GetEnumerator() | ForEach-Object { "&$($_.Name)=$($_.Value)" } | Join-String

  try {
    $error.Clear()
    $url = $baseUrl -f $absolutePath, $attributesString

    if ($method -ieq 'POST') {
      write-host "Invoke-WebRequest -Uri $url ``
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
      write-host "Invoke-WebRequest -Uri $url ``
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

    #format response
    $responseJson = $response.Content | convertfrom-json | convertto-json
    write-host "response: $responseJson" -foregroundColor Green

    if ($response.Content.ContinuationToken -ne $null) {
      #write-host "continuation token: $($response.ContinuationToken)" -foregroundColor Green
      $attributes.continuationToken = $response.Content.ContinuationToken
      return invoke-rest -method $method -absolutePath $absolutePath -body $body -attributes $attributes -continuationToken $response.ContinuationToken
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

    return $responseJson
  }
  catch [Exception] {
    write-host "exception calling rest method:$url" -foregroundColor red
    write-host $error.Exception.Message -foregroundColor red
    write-host $error.Exception.InnerException.Message -ForegroundColor Red
    write-host $error.Exception.InnerException.StackTrace -ForegroundColor Red
    return $null
  }
  
}

function get-sfHttpModule() {
  if (!(get-module -ListAvailable $sfHttpModule -ErrorAction SilentlyContinue)) {
    write-host "installing service fabric powershell module" -foregroundColor yellow
    Install-Module -Name $sfHttpModule -Scope CurrentUser -Force -AllowPrerelease
  }
  write-host "importing service fabric powershell module" -foregroundColor yellow
  Import-Module -Name $sfHttpModule -Force
  write-host "connecting to service fabric cluster" -foregroundColor yellow
  write-host "connect-sfcluster -connectionEndpoint $connectionEndpoint -ServerCertThumbprint $thumbprint -X509Credential -FindType FindByThumbprint -FindValue $thumbprint -StoreLocation CurrentUser -StoreName My" -foregroundColor yellow
  Connect-SFCluster -ConnectionEndpoint $connectionEndpoint -ServerCertThumbprint $thumbprint -X509Credential -FindType FindByThumbprint -FindValue $thumbprint -StoreLocation CurrentUser -StoreName My
  
  $backups = Get-SFBackupsFromBackupLocation -Application `
    -ApplicationName $applicationName `
    -AzureBlobStore `
    -ConnectionString "DefaultEndpointsProtocol=https;AccountName=$backupStorageAccountName;AccountKey=$backupStorageAccountKey;EndpointSuffix=blob.core.windows.net" `
    -ContainerName $containerName

  $backups | ConvertTo-Json -Depth 99

  if ($?) {
    write-host "connected to service fabric cluster" -foregroundColor yellow
    write-host "restoring $applicationName from $backupLocation/$backupId" -foregroundColor yellow
    Restore-ServiceFabricBackup -BackupId $backupId -BackupLocation $backupLocation -BackupStorage $backupStorageAccountName -ApplicationName $applicationName
    if ($?) {
      write-host "restored $applicationName from $backupLocation/$backupId" -foregroundColor yellow
    }
    else {
      write-host "failed to restore $applicationName from $backupLocation/$backupId" -foregroundColor red
    }
  }
  else {
    write-host "failed to connect to service fabric cluster" -foregroundColor red
  }

}

main
