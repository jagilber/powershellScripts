# SF HTTP Client - Quick Reference Guide

## Overview
`sf-http-client.ps1` connects to a Service Fabric cluster from Windows or Linux PowerShell **without** the SF SDK. It uses the `Microsoft.ServiceFabric.Powershell.Http` module and supports certificate-based authentication via local cert store, Azure Key Vault, base64-encoded certificates, or certificate objects.

## Prerequisites
- PowerShell 5.1+ or PowerShell Core
- Certificate with private key for client authentication
- Network access to cluster management endpoint (default port 19080)
- `Microsoft.ServiceFabric.Powershell.Http` module (auto-installed if missing, v1.10.0+ recommended)

## Quick Start

### Connect with Local Certificate
```powershell
./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateName myclustercert
```
The script auto-prepends `https://` and appends `:19080` if not specified.

### Connect with Key Vault Certificate
```powershell
./sf-http-client.ps1 -keyVaultName mykeyvault -certificateName myclustercert -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com
```

### Connect with Base64 Certificate (Cloud Shell)
```powershell
# first, generate base64 string from pfx:
$base64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("C:\path\to\certificate.pfx"))

# then connect:
./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateBase64 $base64
```

### Connect with Certificate Object
```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -ieq "CN=myclustercert"
./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -x509Certificate $cert
```

### Validate Certificate Only (No Connection)
```powershell
./sf-http-client.ps1 -clusterHttpConnectionEndpoint mycluster.eastus.cloudapp.azure.com -certificateName myclustercert -validateOnly
```
Checks EKU, chain, expiration, and private key access without connecting.

## Certificate & EKU Details

### Server vs. Client Certificates
The script automatically retrieves the **server certificate** from the cluster endpoint via TLS handshake. When the server cert differs from the client cert:
- `-ServerCertThumbprint` is set to the server cert thumbprint
- `-ServerCommonName` is set to the server cert CN
- The client cert thumbprint is used for `-FindValue`

### EKU Requirements
| Certificate Role | Required EKU | OID |
|---|---|---|
| Client | Client Authentication | `1.3.6.1.5.5.7.3.2` |
| Server | Server Authentication | `1.3.6.1.5.5.7.3.1` |
| No EKU extension | All purposes allowed | N/A |

The script warns (but does not block) when EKUs are missing. Some SF configurations use a single certificate for both roles.

### Self-Signed Server Certificates
When the server certificate is self-signed (subject == issuer), the script:
1. Checks if it's already in `CurrentUser\Root` trusted store
2. If not, automatically adds it via `certutil -user -addstore Root` for TLS validation
3. This avoids chain trust errors without requiring manual cert trust setup

### Multiple Certificates
When multiple certificates match the CN, the script selects in priority order:
1. Most recent non-expired cert with private key
2. Most recent cert with private key
3. Most recent non-expired cert
4. Most recent cert

## Making REST Requests

### After Connection
```powershell
./sf-http-client.ps1 -absolutePath /$/GetClusterHealth
```

### With Query Parameters
```powershell
./sf-http-client.ps1 -absolutePath "/EventsStore/Nodes/Events" -queryParameters @{
    StartTimeUtc = '2026-01-01T00:00:00Z'
    EndTimeUtc   = '2026-03-01T00:00:00Z'
}
```

## Using SF HTTP Module Commands

After connecting, all `*-SF*` commands from the module are available:

```powershell
# cluster info
Get-SFClusterVersion | ConvertTo-Json

# applications and services
$applications = Get-SFApplication
$services = @($applications).ForEach{ Get-SFService -ApplicationId $_.ApplicationId }
$partitions = @($services).ForEach{ Get-SFPartition -ServiceId $_.ServiceId }
$replicas = @($partitions).ForEach{ Get-SFReplica -PartitionId $_.PartitionId }

# node operations
Restart-SFNode -NodeName _nt0_2 -NodeInstanceId 0
Disable-SFNode -NodeName _nt0_2 -DeactivationIntent Restart -Force

# event queries
Get-SFClusterEventList -StartTimeUtc '2026-02-28T00:00:00Z' -EndTimeUtc '2026-03-01T00:00:00Z'

# application deployment
Copy-SFApplicationPackage -ApplicationPackagePath 'C:\pkg\Release' -ApplicationPackagePathInImageStore 'MyApp'
Register-SFApplicationType -ImageStorePath -ApplicationTypeBuildPath 'MyApp'
New-SFApplication -Name 'fabric:/MyApp' -TypeName 'MyAppType' -TypeVersion '1.0.0'
New-SFService -Singleton -Stateless -ApplicationId 'MyApp' -ServiceName 'fabric:/MyApp/MySvc' -ServiceTypeName 'MySvcType' -InstanceCount -1
```

## Reconnecting

The script outputs a reconnect command after successful connection. Example format:
```powershell
Connect-SFCluster -ConnectionEndpoint https://mycluster.eastus.cloudapp.azure.com:19080 `
    -ServerCertThumbprint <serverCertThumbprint> `
    -X509Credential `
    -FindType FindByThumbprint `
    -FindValue <clientCertThumbprint> `
    -StoreLocation CurrentUser `
    -StoreName My `
    -ServerCommonName mycluster.eastus.cloudapp.azure.com `
    -Verbose
```

## Fallback Behavior
If `Connect-SFCluster` fails, the script falls back to direct REST calls using `Invoke-RestMethod` with the client certificate and `-SkipCertificateCheck`.

## Parameter Sets

| Set | Key Parameters | Use Case |
|---|---|---|
| `default` | `-clusterHttpConnectionEndpoint`, `-certificateName` | Local cert store on Windows |
| `keyvault` | `-keyvaultName`, `-certificateName`, `-keyvaultSecretVersion` | Certificate from Azure Key Vault |
| `local` | `-x509Certificate` or `-certificateBase64` | Certificate object or base64 string |
| `rest` | `-absolutePath`, `-queryParameters` | REST API calls after connection |

## Known Issues (Module v1.10.0)
- `Get-SFApplicationType` may throw a null argument error — use direct REST calls as workaround
- Parameter names changed from v1.6.0 (e.g., `-ApplicationName` → `-Name`, `-TypeName`, `-TypeVersion`)
- v1.6.0 had a hardcoded 90-second `HttpClient.Timeout` that prevented large package uploads — fixed in v1.10.0

## Testing
Run Pester tests:
```powershell
Invoke-Pester -Path .\sf-http-client.tests.ps1 -Output Detailed
```
