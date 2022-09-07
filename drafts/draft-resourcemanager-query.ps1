<#
testing resource enumeration get-azresource vs export-azresourcegroup
export-azresourcegroup enumerates microsoft.servicefabric/managedclusters/nodetypes
get-azresource does not
#>

# find dll which is part of az.resources
import-module az.resources
$dllPath = [io.path]::GetDirectoryName((get-module az.resources).Path)

import-module $dllPath\Microsoft.Azure.Management.ResourceManager.dll

[Microsoft.Azure.Management.ResourceManager.ResourceGroupsOperationsExtensions]::ExportTemplate


[Microsoft.Azure.Management.ResourceManager.ResourceGroupsOperationsExtensions]::List