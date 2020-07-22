note this script has had limited testing and is provided as is.
if you decide to try, test in non production environment first.
if you need assistance with your certificate swap, it may be best to open a support case with microsoft.
if you need assistance with this script feel free to ping me.

**to use with azure 'az' modules:**

```powershell
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-patch-resource.ps1" -outFile "$pwd\azure-az-patch-resource.ps1"
.\azure-az-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]
```

**to use azure 'azurerm' modules:**

```powershell
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-azurerm-patch-resource.ps1" -outFile "$pwd\azure-azurerm-patch-resource.ps1"
.\azure-azurerm-patch-resource.ps1 -resourceGroupName {{ resource group name }} -resourceName {{ resource name }} [-patch]
```

**example enumeration (GET) steps 2 - 8 for nodetype:**

this will enumerate nodetype/vmss resource named 'nt0' from resource group 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName nt0
```

**make changes in template.json (steps 2 - 8)**

**example (PUT) steps 2 - 8 for nodetype:**

this will update nodetype/vmss resource named 'nt0' in resource group 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName nt0 -patch
```

**example enumeration (GET) steps 9 - 13 for cluster:**

this will enumerate service fabric cluster resource named 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName sfjagilbercluster
```

**make changes in template.json (steps 9 - 13)**

**example (PUT) steps 9 - 13 for cluster:**

this will update service fabric cluster resource named 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName sfjagilbercluster -patch
```

**example enumeration (GET) steps 14 - 18 for nodetype:**

this will enumerate nodetype/vmss resource named 'nt0' from resource group 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName nt0
```

**make changes in template.json (steps 14 -18)**

**example (PUT) steps 14 - 18 for nodetype:**

this will update nodetype/vmss resource named 'nt0' in resource group 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName nt0 -patch
```

**example enumeration (GET) steps 19 - 22 for cluster:**

this will enumerate service fabric cluster resource named 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName sfjagilbercluster
```

**make changes in template.json (steps 19 - 22)**

**example (PUT) steps 19 - 22 for cluster:**

this will update service fabric cluster resource named 'sfjagilbercluster':

```powershell
.\azure-az-patch-resource.ps1 -resourceGroupName sfjagilbercluster -resourceName sfjagilbercluster -patch
```
