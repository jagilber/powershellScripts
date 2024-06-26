# How to use AzurePowershell builtin task to manage Service Fabric Managed Cluster server thumbprint in Azure Devops service connection

Service Fabric Managed Clusters manage the 'server' certificate rollover before certificate expires.
There is currently no notification when this occurs.
Azure Devops (ADO) connections using X509 Certificate authentication requires the configuration of the server certificate thumbprint.
When the certificate is rolled over, the Service Fabric service connection will fail to connect to cluster causing pipelines  to fail.

The steps below describe how to use a builtin task with provided powershell script to update the server thumbprint when thumbprint has changed.

## Requirements

- Location to store powershell script used in task that is available from ADO pipeline: https://aka.ms/sf-managed-ado-connection.ps1
- Service fabric managed cluster Admin 'client' certificate has to be stored in azure key vault and be accessible from ADO pipeline / release.
- Pfx certificate to be used for ADO connection which does not have a certificate password.
- ADO Azure service connection to subscription with managed cluster.
- ADO Service Fabric service connection using 'Certificate Based' Authentication Method.
- Service connection in ADO permissions allowing access to update connection from ADO pipeline / release.
- AzurePowershell task executing script must be executed before any Service Fabric task and must be in the same job.

## Process

The provided ADO configurations and powershell script performs the following:

- Builtin task AzurePowershell:
    - provides the connection to Azure for querying managed cluster and key vault resources.
    - downloads and executes powershell script sf-managed-ado-connection.ps1.
- Powershell script does the following:
    1. connects to ADO service endpoint REST url to enumerate service fabric connection.
    2. connects to Azure to query service fabric managed cluster by service connection url.
    3. compares server thumbprint from azure resource and from service connection.
    4. if thumbprint is different:
        1. connects to Azure to query key vault for 'client' certificate to create base64 string for ADO connection.
        2. updates ADO service endpoint via REST with new server thumbprint.
        3. writes ##vso[task.setvariable variable=ENDPOINT_AUTH_$serviceConnectionName;] to update connection thumbprint for subsequent tasks.

## Azure Key vault

To provide ADO with certificate information, the Admin client certificate for the managed service fabric cluster has to be stored in a key vault.
During the creation of cluster, either a thumbprint or key vault is required.
If key vault was provided, the same Admin client certificate can be used for ADO connection.
If the cluster has not been configured to use a key vault, a key vault can be added with a new Admin client certificate.

### Add key vault to existing cluster

To add a key vault to an existing managed cluster, navigate to the managed cluster resource in azure portal.
On the 'Security' blade, select 'Add with keyvault'.

Create a new or select existing key vault.
Create a new or select existing certificate.
Add as an 'Admin' client certificate.

![](media/2022-07-06-14-29-31.png)

Example creating a new certificate:

![](media/2022-07-06-14-35-31.png)

![](media/2022-07-06-14-35-57.png)

![](media/2022-07-06-14-38-09.png)

### PFX certificate base64 string

When creating the Service Fabric ADO service connection using 'Thumbprint' method, the PFX certficate base64 string is required. Use the following powershell command providing path the certificate .pfx file. Pfx file can be exported from Azure key vault from certificate view.

```powershell
PS C:>[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\certificate.pfx"))
MIIKRAIBAzCCCgAGCSqGSIb3DQEHAaCCCfEEggntMIIJ6TCCBhoGCSqGSIb3DQEHAaCCBgsEggYHMIIGAzCCBf8GCyqGSIb3DQEMCgECoIIE/jCCBPowHAYK...
```

## Azure Service Connection

Create the Azure Service Connection to provide connectivity to Azure from ADO pipelines.
When service connection is created, an Azure App Registration is also created.
This App registration is needed to set the RBAC permissions on the Azure Keyvault.

**NOTE: You may need to allow popups for authentication prompt.

```https://dev.azure.com/{{organization}}/{{project}}/_settings/adminservices```

![](media/2022-07-06-14-00-33.png)

![](media/2022-07-06-14-01-27.png)

![](media/2022-07-06-14-01-53.png)

![](media/2022-07-06-14-14-50.png)

## Azure Key vault Permissions

After the Azure Service Connection has been created, the key vault access policy containing the client certificate needs to modified.
The app registration for the Azure connection is added the the Access Policies.

Navigate to Azure key vault in portal and select Access Policies.
The Azure service connection needs read access to both the certificate and certificate secret.
If using a template, select 'Secret & Certificate Management' as shown below.
For 'Select Principal', select 'None selected' to find the azure service connection app registration service principal.
Search by typing in ADO organization name.
The service principal name is in the format of: %organization%-%project%-%subscriptionId%.
When finished with configuration, save changes.

![](media/2022-07-17-17-15-07.png)

## Service Fabric Service Connection

Create / Modify the Service Fabric Service Connection to provide connectivity to Service Fabric managed cluster from ADO pipelines.
For this configuration, only 'Certificate Based' authentication is supported.

### Enumerate certificate thumbprint

To enumerate the 'server' certificate thumbprint from a managed cluster, provide resource group name, cluster name, and subscription id for powershell command.
See [Connect to a Service Fabric managed cluster](https://docs.microsoft.com/en-us/azure/service-fabric/how-to-managed-cluster-connect) for additional information.

```powershell
$resourceGroupName = ''
$clusterName = ''
$subscriptionId = ''
$resourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ServiceFabric/managedclusters/$clusterName"
$serverThumbprint = (Get-AzResource -ResourceId $resourceId).Properties.clusterCertificateThumbprints
write-host $serverThumbprint
```

This connection requires the following information:

- Authentication - Certificate Based
- Cluster Endpoint - cluster connection endpoint url using tcp:// uri. example: tcp://mycluster.eastus.cloudapp.azure.com:19000
- Server Certificate Lookup - Thumbprint.
- Server Certificate Thumbprint - as described above.
- Client Certificate - admin client pfx certificate in base64 string format as described above.
- Password - do not use.
- Service connection name.

Example:

![](media/2022-07-17-14-29-08.png)

## Using AzurePowershell builtin task in a pipeline

To use powershell script in a build pipeline, an AzurePowershell task has to be used.
This task must run before any service fabric tasks and in the same job.

Required pipeline variables:

- azureSubscriptionName - name of ADO Azure service connection.
- sfmcCertificateName - name of admin client cerficate in Azure key vault.
- sfmcKeyVaultName - name of Azure key vault containing admin client certificate.
- sfmcServiceConnectionName - name of ADO Azure Service Fabric connection.
- system_accessToken - $(System.AccessToken) - system variable containing ADO token used by script to modify service connection.

### AzurePowerShell InlineScript powershell commands

```powershell
write-host "starting inline"
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://aka.ms/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
./sf-managed-ado-connection.ps1 -accessToken $env:system_accessToken `
  -sfmcServiceConnectionName $env:sfmcServiceConnectionName `
  -keyVaultName $env:sfmcKeyVaultName `
  -certificateName $env:sfmcCertificateName
write-host "finished inline"
```

## AzurePowershell builtin task in a build pipeline

To use the script to manage service fabric service connection in a build pipeline, perform the following:

```yaml
variables:
  System.Debug: true
  azureSubscriptionName: armServiceConnection
  sfmcCertificateName: sfmc-cluster-devops
  sfmcKeyVaultName: sfmcCluster
  sfmcServiceConnectionName: serviceFabricConnection

steps:
  - task: AzurePowerShell@5
    inputs:
      azureSubscription: $(azureSubscriptionName)
      ScriptType: "InlineScript"
      Inline: |
        write-host "starting inline"
        [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
        invoke-webRequest "https://aka.ms/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
        ./sf-managed-ado-connection.ps1 -accessToken $env:system_accessToken `
          -sfmcServiceConnectionName $env:sfmcServiceConnectionName `
          -keyVaultName $env:sfmcKeyVaultName `
          -certificateName $env:sfmcCertificateName
        write-host "finished inline"
      errorActionPreference: continue
      azurePowerShellVersion: LatestVersion
    env:
      system_accessToken: $(System.AccessToken)
```

## AzurePowershell builtin task in a release pipeline

To use script to manage service fabric service connection in a release pipeline, perform the following:

Create / Modify Service Fabric Release pipeline.
In 'Tasks' view, select 'Agent job'.
Under 'Additional options', check 'Allow script to access the OAuth token'

![](media/2022-07-18-10-01-20.png)

In 'Tasks' view, select the '+' button to add a new task.

![](media/2022-07-17-18-08-35.png)

Search for 'Azure Powershell' and 'Add' task.

![](media/2022-07-17-18-10-11.png)

Move task above the Service Fabric task(s) and populate settings as shown below.
When completed, save pipeline.

![](media/2022-07-17-18-17-48.png)


### Release pipeline variables

Navigate to the Release pipeline 'Variables' tab to set the Release pipeline variables as shown below.
When completed, save pipeline.

![](media/2022-07-17-18-23-47.png)

### release pipeline yaml pseudo example

```yaml

steps:
- task: AzurePowerShell@5
  displayName: 'Azure PowerShell script: InlineScript'
  inputs:
    azureSubscription: $(azureSubscriptionName)
    ScriptType: InlineScript
    Inline: |
     write-host "starting inline"
     [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
     invoke-webRequest "https://aka.ms/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
     ./sf-managed-ado-connection.ps1 -accessToken $env:system_accessToken `
        -sfmcServiceConnectionName $env:sfmcServiceConnectionName `
        -keyVaultName $env:sfmcKeyVaultName `
        -certificateName $env:sfmcCertificateName
      write-host "finished inline"
    errorActionPreference: continue
    azurePowerShellVersion: LatestVersion
    pwsh: true
```

## Testing

To test configuration, modify thumbprint in the service fabric service connection to a different thumbprint. Below is a working yaml file that can be used for testing. Set correct branch and populate variables to use.

### Build pipeline test yaml

```yaml
trigger:
  - master

pool:
  vmImage: "windows-latest"

variables:
  System.Debug: true
  sfmcServiceConnectionName: serviceFabricConnection
  azureSubscriptionName: armServiceConnection
  sfmcKeyVaultName: 
  sfmcCertificateName: 

steps:
  - task: AzurePowerShell@5
    inputs:
      azureSubscription: $(azureSubscriptionName)
      ScriptType: "InlineScript"
      Inline: |
        write-host "starting inline"
        [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
        invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-managed-ado-connection.ps1" -outFile "$pwd/sf-managed-ado-connection.ps1";
        ./sf-managed-ado-connection.ps1 -accessToken $env:system_accessToken `
          -sfmcServiceConnectionName $env:sfmcServiceConnectionName `
          -keyVaultName $env:sfmckeyVaultName `
          -certificateName $env:sfmccertificateName
        write-host "finished inline"
      errorActionPreference: continue
      verbosePreference: continue
      debugPreference: continue
      azurePowerShellVersion: LatestVersion
    env:
      system_accessToken: $(System.AccessToken)

  - task: ServiceFabricPowerShell@1
    inputs:
      clusterConnection: $(sfmcServiceConnectionName)
      ScriptType: "InlineScript"
      Inline: |
        $verbosePreference = $debugpreference = 'continue'
        $psversiontable
        $env:connection
        [environment]::getenvironmentvariables().getenumerator()|sort Name

```


## Troubleshooting

Use logging from task to assist with issues.
Enabling System.Debug in build yaml or in release variables will provide additional write-verbose output from script but will include sensitive security information.

### AzurePowerShell Example log

```powershell
```