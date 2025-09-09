<#
.SYNOPSIS
    Generate SAS keys for Azure Storage accounts using either storage account keys or user delegation keys.

.DESCRIPTION
    This script generates SAS (Shared Access Signature) tokens for Azure Storage accounts. 
    It supports two authentication methods:
    1. User delegation keys (default) - uses Azure AD authentication for enhanced security, BLOB STORAGE ONLY
    2. Storage account keys - requires storage account access, supports all services
    
    IMPORTANT: User delegation SAS (default) only supports blob storage and creates container-level SAS tokens.
    For account-level SAS tokens across all services, use the -useAccountKey switch.
    
    For user delegation keys, the current user must have appropriate RBAC permissions
    such as "Storage Blob Data Contributor" on the storage account, which includes the
    "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey" action.

.PARAMETER resourceGroupName
    The name of the resource group containing the storage accounts.

.PARAMETER storageAccountName
    Pattern to match storage account names. Supports wildcards.

.PARAMETER service
    The storage services to include in the SAS token. Valid values: blob, file, table, queue.

.PARAMETER resourceType
    The resource types to include in the SAS token. Valid values: service, container, object.

.PARAMETER permission
    The permissions to grant. Default is 'r' (read-only) for user delegation keys, 'racwdlup' for account keys.

.PARAMETER expirationHours
    Number of hours until the SAS token expires. Default is 8 hours.

.PARAMETER useAccountKey
    Use storage account keys instead of user delegation keys. Supports all services and resource types.

.PARAMETER assignRbacRole
    Automatically assign the required RBAC role if using user delegation keys.

.PARAMETER userEmail
    Email address for RBAC role assignment. If not provided, uses current Azure context.

.PARAMETER nonInteractive
    Run in non-interactive mode. When using user delegation, all containers will be selected automatically.

.PARAMETER containerNames
    Array of specific container names to create SAS tokens for. Only used with user delegation.

.EXAMPLE
    .\azure-az-sas-key.ps1 -resourceGroupName "myRG" -storageAccountName "mystorageaccount"
    
    Generate SAS tokens using user delegation keys (default) with interactive container selection.

.EXAMPLE
    .\azure-az-sas-key.ps1 -resourceGroupName "myRG" -storageAccountName "mystorageaccount" -useAccountKey
    
    Generate SAS tokens using storage account keys for all services.

.EXAMPLE
    .\azure-az-sas-key.ps1 -resourceGroupName "myRG" -storageAccountName "mystorageaccount" -assignRbacRole -userEmail "user@domain.com"
    
    Generate SAS tokens using user delegation keys and automatically assign required RBAC role.

.EXAMPLE
    .\azure-az-sas-key.ps1 -resourceGroupName "myRG" -storageAccountName "mystorageaccount" -nonInteractive
    
    Generate SAS tokens for all containers in non-interactive mode using user delegation.

.EXAMPLE
    .\azure-az-sas-key.ps1 -resourceGroupName "myRG" -storageAccountName "mystorageaccount" -containerNames @("logs", "data")
    
    Generate SAS tokens for specific containers only using user delegation.

.NOTES
    For user delegation keys, ensure you have appropriate RBAC permissions:
    - Storage Blob Data Contributor (for blob operations)
    - Storage Queue Data Contributor (for queue operations)
    - Storage Table Data Contributor (for table operations)

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-sas-key.ps1" -outFile "$pwd\azure-az-sas-key.ps1";
    .\azure-az-sas-key.ps1

#>
param(
    [Parameter(Mandatory = $true)]
    $resourceGroupName = '',
    $storageAccountName = '.',
    [ValidateSet('blob', 'file', 'table', 'queue')]
    $service = @('blob', 'file', 'table', 'queue'),
    [ValidateSet('service', 'container', 'object')]
    $resourceType = @('service', 'container', 'object'),
    $permission = $null,
    $expirationHours = 8,
    [switch]$useAccountKey,
    [switch]$assignRbacRole,
    $userEmail = $null,
    [switch]$nonInteractive,
    $containerNames = @()
)

$PSModuleAutoLoadingPreference = 2

# Set default permissions based on authentication method
if ($null -eq $permission) {
    $permission = 'rl'  # Read-only for user delegation (default)
}

function main() {
    try {
        $error.Clear()
        
        write-host "Get-AzStorageAccount -ResourceGroupName $resourceGroupName" -ForegroundColor Cyan

        # Get current Azure context for user email and subscription
        $azContext = Get-AzContext
        if (-not $azContext) {
            write-error "Not logged in to Azure. Please run Connect-AzAccount first."
            exit 1
        }

        $subscriptionId = $azContext.Subscription.Id
        if (-not $userEmail) {
            $userEmail = $azContext.Account.Id
            write-host "Using current Azure context user: $userEmail" -ForegroundColor Yellow
        }

        $accounts = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName) | where-object StorageAccountName -imatch $storageAccountName
        $saskeys = [collections.arraylist]::new()

        # Check permissions and assign RBAC roles if needed for user delegation
        if (-not $useAccountKey) {
            write-host "`nUsing Azure AD User Delegation authentication (default)" -ForegroundColor Cyan
            write-host "Checking user delegation permissions..." -ForegroundColor Cyan
            $accountsNeedingRbac = @()
            
            foreach ($account in $accounts) {
                $hasPermissions = Test-UserDelegationPermissions -storageAccountName $account.StorageAccountName -resourceGroupName $resourceGroupName
                
                if (-not $hasPermissions) {
                    $accountsNeedingRbac += $account
                }
            }
            
            if ($accountsNeedingRbac.Count -gt 0) {
                if ($assignRbacRole) {
                    write-host "`nAssigning required RBAC roles for user delegation..." -ForegroundColor Cyan
                    foreach ($account in $accountsNeedingRbac) {
                        Set-StorageRbacRole -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName -storageAccountName $account.StorageAccountName -userEmail $userEmail -services $service
                    }
                    write-host "Waiting 30 seconds for role assignments to propagate..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                }
                else {
                    write-warning "Some storage accounts require RBAC role assignment:"
                    foreach ($account in $accountsNeedingRbac) {
                        write-host "  - $($account.StorageAccountName)" -ForegroundColor Yellow
                    }
                    write-host "`nTo automatically assign roles, use the -assignRbacRole parameter" -ForegroundColor Cyan
                    write-host "Or manually assign 'Storage Blob Data Contributor' role to your account" -ForegroundColor Cyan
                }
            }
        }
        else {
            write-host "`nUsing Storage Account Key authentication" -ForegroundColor Cyan
        }

        foreach ($account in $accounts) {
            $blobUri = $account.Context.BlobEndPoint
            write-host "Processing Storage Account: $($account.StorageAccountName)" -ForegroundColor Magenta
            
            try {
                if (-not $useAccountKey) {
                    write-host "Using Azure AD user delegation key authentication" -ForegroundColor Cyan
                    
                    # Check if blob service is included
                    if ($service -notcontains 'blob') {
                        write-warning "User delegation SAS only supports blob storage. Blob service not included in requested services. Skipping..."
                        continue
                    }
                    
                    # Warn about other services
                    $otherServices = $service | Where-Object { $_ -ne 'blob' }
                    if ($otherServices.Count -gt 0) {
                        write-warning "User delegation SAS only supports blob storage. The following services will be ignored: $($otherServices -join ', ')"
                    }
                    
                    $storageContext = New-UserDelegationContext -storageAccountName $account.StorageAccountName -resourceGroupName $resourceGroupName -expirationHours $expirationHours
                    
                    if (-not $storageContext) {
                        write-warning "Failed to create user delegation context for $($account.StorageAccountName). Skipping..."
                        continue
                    }
                    
                    # Get container selection from user
                    $selectedContainers = Get-ContainerSelection -storageContext $storageContext -storageAccountName $account.StorageAccountName -nonInteractive $nonInteractive -preSelectedContainers $containerNames
                    
                    if ($selectedContainers.Count -eq 0) {
                        write-warning "No containers available or selected for $($account.StorageAccountName). Skipping..."
                        continue
                    }
                    
                    # Create user delegation SAS for selected containers
                    $blobSasUrls = New-UserDelegationBlobSAS -storageContext $storageContext -storageAccountName $account.StorageAccountName -baseUri $blobUri -permission $permission -expirationHours $expirationHours -selectedContainers $selectedContainers
                    
                    foreach ($url in $blobSasUrls) {
                        write-host "Generated User Delegation SAS URL: $url" -ForegroundColor Green
                        $saskeys.Add($url)
                    }
                    
                }
                else {
                    write-host "Using storage account key authentication" -ForegroundColor Cyan
                    write-host "Getting storage account keys for $($account.StorageAccountName)" -ForegroundColor Yellow
                    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $account.StorageAccountName
                    $storageContext = New-AzStorageContext -StorageAccountName $account.StorageAccountName -StorageAccountKey $keys[0].Value

                    write-host "New-AzStorageAccountSASToken -Service $($service -join ',') ``
                        -ResourceType $($resourceType -join ',') ``
                        -StartTime $((get-date).AddMinutes(-1)) ``
                        -ExpiryTime $((get-date).AddHours($expirationHours)) ``
                        -Context [$($storageContext.GetType().Name)]$($blobUri) ``
                        -Protocol HttpsOnly ``
                        -Permission $permission
                    " -ForegroundColor Cyan

                    $sas = New-AzStorageAccountSASToken -Service $service `
                        -ResourceType $resourceType `
                        -StartTime (get-date).AddMinutes(-1) `
                        -ExpiryTime (get-date).AddHours($expirationHours) `
                        -Context $storageContext `
                        -Protocol HttpsOnly `
                        -Permission $permission
                    
                    # Ensure proper URL formatting with ? separator
                    if ($sas.StartsWith('?')) {
                        $sasUrl = "$($blobUri)$sas"
                    }
                    else {
                        $sasUrl = "$($blobUri)?$sas"
                    }
                    
                    write-host "Generated SAS URL: $sasUrl" -ForegroundColor Green
                    $saskeys.Add($sasUrl)
                }
                
            }
            catch {
                write-error "Failed to generate SAS token for $($account.StorageAccountName): $($_.Exception.Message)"
                if (-not $useAccountKey) {
                    write-host "Hint: Ensure you have the required RBAC permissions. Use -assignRbacRole to automatically assign roles." -ForegroundColor Yellow
                    write-host "Required permission: Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey" -ForegroundColor Yellow
                }
            }
        }

        $global:saskeys = $saskeys
        write-host "`n=== SUMMARY ===" -ForegroundColor Magenta
        write-host "Authentication method: $(if (-not $useAccountKey) { 'Azure AD User Delegation Key (Blob containers only)' } else { 'Storage Account Key (All services)' })" -ForegroundColor Yellow
        write-host "Generated $($saskeys.Count) SAS tokens with $($expirationHours) hour expiration" -ForegroundColor Yellow

        if (-not $useAccountKey) {
            write-host "Services: blob (container-level SAS tokens)" -ForegroundColor Yellow
            write-host "Note: User delegation SAS only supports blob storage with container-level access." -ForegroundColor Green
            write-host "These SAS tokens are tied to your Azure AD identity and can be revoked using:" -ForegroundColor Green
            write-host "Revoke-AzStorageAccountUserDelegationKeys -ResourceGroupName $resourceGroupName -StorageAccountName <storage-account>" -ForegroundColor Cyan
        }
        else {
            write-host "Services: $($service -join ', ')" -ForegroundColor Yellow
            write-host "Resource Types: $($resourceType -join ', ')" -ForegroundColor Yellow
        }

        write-host "Permissions: $permission" -ForegroundColor Yellow

        write-host "`n`$global:saskeys variable contains all generated SAS URLs:" -ForegroundColor Cyan
        $saskeys
    }
    catch {
        write-error "Script execution failed: $($_.Exception.Message)"
        exit 1
    }
}

# Function to assign RBAC role for user delegation key access
function Set-StorageRbacRole {
    param(
        [string]$subscriptionId,
        [string]$resourceGroupName,
        [string]$storageAccountName,
        [string]$userEmail,
        [string[]]$services
    )
    
    $scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
    
    # For user delegation SAS, we need roles that include Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey
    $rolesToAssign = @()
    
    if ($services -contains 'blob') { 
        $rolesToAssign += "Storage Blob Data Contributor" 
        write-host "Note: User delegation SAS only supports blob storage. Other services will be ignored." -ForegroundColor Yellow
    }
    else {
        write-warning "User delegation SAS requires blob service to be included in the services list."
        return
    }
    
    foreach ($role in $rolesToAssign) {
        try {
            write-host "Assigning role '$role' to '$userEmail' for storage account '$storageAccountName'" -ForegroundColor Yellow
            
            # Check if role assignment already exists
            $existingAssignment = Get-AzRoleAssignment -SignInName $userEmail -RoleDefinitionName $role -Scope $scope -ErrorAction SilentlyContinue
            
            if ($existingAssignment) {
                write-host "Role '$role' already assigned to '$userEmail'" -ForegroundColor Green
            }
            else {
                New-AzRoleAssignment -SignInName $userEmail -RoleDefinitionName $role -Scope $scope
                write-host "Successfully assigned role '$role' to '$userEmail'" -ForegroundColor Green
                write-host "This role includes the required permission: Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey" -ForegroundColor Green
            }
        }
        catch {
            write-warning "Failed to assign role '$role': $($_.Exception.Message)"
        }
    }
}

# Function to check if user has required RBAC permissions
function Test-UserDelegationPermissions {
    param(
        [string]$storageAccountName,
        [string]$resourceGroupName
    )
    
    try {
        write-host "Testing user delegation permissions for '$storageAccountName'..." -ForegroundColor Yellow
        
        # Get current user context for detailed diagnostics
        $currentContext = Get-AzContext
        if ($currentContext) {
            write-host "Current Azure user: $($currentContext.Account.Id)" -ForegroundColor Cyan
        }
        
        # Try to create a user delegation context to test permissions
        $testContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount -ErrorAction Stop
        write-host "✓ User delegation context creation successful" -ForegroundColor Green
        
        # Test if we can actually create a simple SAS token (this tests the full flow)
        try {
            write-host "Testing actual SAS token creation..." -ForegroundColor Yellow
            
            # Try creating a simple container SAS token for a test container
            # This will fail if permissions haven't propagated yet
            $testSas = New-AzStorageContainerSASToken -Context $testContext `
                -Name "test-container-name" `
                -Permission "r" `
                -ExpiryTime (Get-Date).AddMinutes(5) `
                -ErrorAction Stop
            
            write-host "✓ SAS token creation test successful" -ForegroundColor Green
            return $true
        }
        catch {
            if ($_.Exception.Message -like "*AuthorizationFailure*" -or 
                $_.Exception.Message -like "*not authorized*" -or
                $_.Exception.Message -like "*Forbidden*") {
                
                write-warning "✗ SAS token creation failed due to authorization"
                write-host "Error: $($_.Exception.Message)" -ForegroundColor Red
                write-host "This typically indicates RBAC permissions are still propagating..." -ForegroundColor Yellow
                write-host "Azure Storage caches role assignments and propagation can take 5-15 minutes" -ForegroundColor Yellow
                write-host "Try running the script again in a few minutes" -ForegroundColor Yellow
                return $false
            }
            elseif ($_.Exception.Message -like "*does not exist*") {
                # Container doesn't exist - that's fine, permissions are working
                write-host "✓ User delegation permissions verified (test container doesn't exist - expected)" -ForegroundColor Green
                return $true
            }
            else {
                write-warning "✗ Unexpected error during SAS test: $($_.Exception.Message)"
                return $false
            }
        }
    }
    catch {
        if ($_.Exception.Message -like "*generateUserDelegationKey*" -or $_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*insufficient privileges*") {
            write-warning "✗ Missing required RBAC permissions for '$storageAccountName'"
            write-host "Required permission: Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey" -ForegroundColor Yellow
            return $false
        }
        else {
            write-warning "✗ Failed to test permissions for '$storageAccountName': $($_.Exception.Message)"
            return $false
        }
    }
}

# Function to enumerate containers using Az PowerShell commands (independent of storage context)
function Get-ContainerList {
    param(
        [string]$resourceGroupName,
        [string]$storageAccountName
    )
    
    try {
        write-host "Enumerating containers using Az PowerShell commands..." -ForegroundColor Cyan
        
        # Method 1: Try using Get-AzStorageContainer (Resource Manager approach)
        try {
            write-host "Attempting to list containers using Get-AzStorageContainer..." -ForegroundColor Yellow
            $containers = Get-AzStorageContainer -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction Stop
            
            if ($containers.Count -gt 0) {
                write-host "✓ Successfully enumerated $($containers.Count) containers using Resource Manager API" -ForegroundColor Green
                return $containers | ForEach-Object { 
                    New-Object PSObject -Property @{
                        Name = $_.Name
                        LastModified = $_.LastModified
                        LeaseStatus = $_.LeaseStatus
                        PublicAccess = $_.PublicAccess
                        HasImmutabilityPolicy = $_.HasImmutabilityPolicy
                        HasLegalHold = $_.HasLegalHold
                    }
                }
            }
            else {
                write-warning "No containers found using Resource Manager API"
                return @()
            }
        }
        catch {
            write-warning "Get-AzStorageContainer failed: $($_.Exception.Message)"
        }
        
        # Method 2: Try using REST API approach if available
        try {
            write-host "Attempting alternative container enumeration method..." -ForegroundColor Yellow
            
            # Get storage account details
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
            
            # Try to create a context with managed identity or current user credentials
            $context = $null
            try {
                # Try with current Azure AD user
                $context = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount -ErrorAction Stop
                write-host "✓ Created storage context using connected account" -ForegroundColor Green
            }
            catch {
                write-warning "Cannot create storage context with connected account: $($_.Exception.Message)"
                
                # Try with storage account keys if available
                try {
                    $keys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
                    $context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keys[0].Value -ErrorAction Stop
                    write-host "✓ Created storage context using account key" -ForegroundColor Green
                }
                catch {
                    write-warning "Cannot create storage context with account key: $($_.Exception.Message)"
                }
            }
            
            if ($context) {
                $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
                write-host "✓ Successfully enumerated $($containers.Count) containers using storage context" -ForegroundColor Green
                return $containers
            }
        }
        catch {
            write-warning "Alternative enumeration method failed: $($_.Exception.Message)"
        }
        
        write-warning "All container enumeration methods failed. Container list unavailable."
        write-host "You can still specify container names manually using -containerNames parameter" -ForegroundColor Cyan
        return @()
    }
    catch {
        write-error "Failed to enumerate containers: $($_.Exception.Message)"
        return @()
    }
}

# Function to get container selection from user
function Get-ContainerSelection {
    param(
        [object]$storageContext,
        [string]$storageAccountName,
        [bool]$nonInteractive = $false,
        [array]$preSelectedContainers = @()
    )
    
    try {
        write-host "`nGetting containers for storage account '$storageAccountName'..." -ForegroundColor Cyan
        
        # If specific container names provided and we can't list containers, use them directly
        if ($preSelectedContainers.Count -gt 0) {
            try {
                $containers = Get-AzStorageContainer -Context $storageContext -ErrorAction Stop
            }
            catch {
                if ($_.Exception.Message -like "*AuthorizationFailure*" -or $_.Exception.Message -like "*not authorized*") {
                    write-warning "Cannot list containers due to insufficient permissions, but using pre-selected container names..."
                    write-host "Required permission: Microsoft.Storage/storageAccounts/blobServices/containers/read" -ForegroundColor Yellow
                    write-host "Using pre-selected container names without validation..." -ForegroundColor Yellow
                    $mockContainers = @()
                    foreach ($containerName in $preSelectedContainers) {
                        $mockContainer = New-Object PSObject -Property @{
                            Name = $containerName
                        }
                        $mockContainers += $mockContainer
                        write-host "Will attempt to create SAS for container: $containerName" -ForegroundColor Yellow
                    }
                    return $mockContainers
                }
                else {
                    throw
                }
            }
        }
        else {
            $containers = Get-AzStorageContainer -Context $storageContext
        }
        
        if ($containers.Count -eq 0) {
            write-warning "No containers found in storage account '$storageAccountName'"
            return @()
        }
        
        # If specific container names provided, filter to those
        if ($preSelectedContainers.Count -gt 0) {
            $selectedContainers = @()
            foreach ($containerName in $preSelectedContainers) {
                $matchedContainer = $containers | Where-Object { $_.Name -eq $containerName }
                if ($matchedContainer) {
                    $selectedContainers += $matchedContainer
                    write-host "Pre-selected container: $containerName" -ForegroundColor Green
                }
                else {
                    write-warning "Container '$containerName' not found in storage account '$storageAccountName'"
                }
            }
            return $selectedContainers
        }
        
        # If non-interactive mode, return all containers
        if ($nonInteractive) {
            write-host "Non-interactive mode: selecting all $($containers.Count) containers" -ForegroundColor Yellow
            return $containers
        }
        
        # Interactive mode - show selection menu
        write-host "`nAvailable containers in '$storageAccountName':" -ForegroundColor Yellow
        write-host "0. [ALL CONTAINERS] (default)" -ForegroundColor Green
        
        for ($i = 0; $i -lt $containers.Count; $i++) {
            write-host "$($i + 1). $($containers[$i].Name)" -ForegroundColor White
        }
        
        write-host "`nEnter your selection (0 for all, or comma-separated numbers like 1,3,5):" -ForegroundColor Cyan
        write-host "Press Enter for default [ALL CONTAINERS]: " -NoNewline -ForegroundColor Yellow
        
        $selection = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq "0") {
            write-host "Selected: All containers" -ForegroundColor Green
            return $containers
        }
        
        $selectedNumbers = $selection.Split(',') | ForEach-Object { $_.Trim() }
        $selectedContainers = @()
        
        foreach ($num in $selectedNumbers) {
            if ($num -match '^\d+$') {
                $index = [int]$num - 1
                if ($index -ge 0 -and $index -lt $containers.Count) {
                    $selectedContainers += $containers[$index]
                    write-host "Selected: $($containers[$index].Name)" -ForegroundColor Green
                }
                else {
                    write-warning "Invalid selection: $num (out of range)"
                }
            }
            else {
                write-warning "Invalid selection: $num (not a number)"
            }
        }
        
        if ($selectedContainers.Count -eq 0) {
            write-warning "No valid containers selected. Using all containers as default."
            return $containers
        }
        
        return $selectedContainers
        
    }
    catch {
        if ($_.Exception.Message -like "*AuthorizationFailure*" -or $_.Exception.Message -like "*not authorized*") {
            write-warning "Cannot list containers due to insufficient permissions."
            write-host "Required permission: Microsoft.Storage/storageAccounts/blobServices/containers/read" -ForegroundColor Yellow
            write-host "This is included in 'Storage Blob Data Reader' or 'Storage Blob Data Contributor' roles" -ForegroundColor Yellow
            
            # If specific containers were provided, try to use them anyway
            if ($preSelectedContainers.Count -gt 0) {
                write-host "Using pre-selected container names without validation..." -ForegroundColor Yellow
                $mockContainers = @()
                foreach ($containerName in $preSelectedContainers) {
                    $mockContainer = New-Object PSObject -Property @{
                        Name = $containerName
                    }
                    $mockContainers += $mockContainer
                    write-host "Will attempt to create SAS for container: $containerName" -ForegroundColor Yellow
                }
                return $mockContainers
            }
            else {
                write-host "Workaround: Use -containerNames parameter to specify container names explicitly." -ForegroundColor Cyan
                write-host "Example: -containerNames @('logs', 'data')" -ForegroundColor Cyan
                return @()
            }
        }
        else {
            write-error "Failed to get containers: $($_.Exception.Message)"
            return @()
        }
    }
}

# Function to create user delegation SAS for selected blob containers
function New-UserDelegationBlobSAS {
    param(
        [object]$storageContext,
        [string]$storageAccountName,
        [string]$baseUri,
        [string]$permission,
        [int]$expirationHours,
        [array]$selectedContainers
    )
    
    try {
        write-host "`nCreating user delegation SAS tokens for selected containers in '$storageAccountName'..." -ForegroundColor Yellow
        $sasUrls = @()
        
        if ($selectedContainers.Count -eq 0) {
            write-warning "No containers provided for SAS generation."
            return @()
        }
        
        foreach ($container in $selectedContainers) {
            try {
                $containerSas = New-AzStorageContainerSASToken -Context $storageContext `
                    -Name $container.Name `
                    -Permission $permission `
                    -ExpiryTime (Get-Date).AddHours($expirationHours)
                
                # Ensure proper URL formatting: baseUri + containerName + ? + sasToken
                # Remove trailing slash from baseUri if present
                $cleanBaseUri = $baseUri.TrimEnd('/')
                
                # Add proper URL formatting with / and ? separators
                if ($containerSas.StartsWith('?')) {
                    $sasUrl = "$cleanBaseUri/$($container.Name)$containerSas"
                }
                else {
                    $sasUrl = "$cleanBaseUri/$($container.Name)?$containerSas"
                }
                
                $sasUrls += $sasUrl
                write-host "✓ Created SAS for container '$($container.Name)'" -ForegroundColor Green
                
            }
            catch {
                if ($_.Exception.Message -like "*AuthorizationFailure*" -or 
                    $_.Exception.Message -like "*not authorized*" -or
                    $_.Exception.Message -like "*Forbidden*") {
                    
                    write-error "✗ Failed to create SAS for container '$($container.Name)' - Authorization failed"
                    write-host "This is likely due to RBAC permission propagation delay." -ForegroundColor Yellow
                    write-host "Azure Storage caches role assignments and it can take 5-15 minutes for changes to propagate." -ForegroundColor Yellow
                    write-host "Please wait a few minutes and try again." -ForegroundColor Yellow
                    write-host "If the issue persists, verify that you have the 'Storage Blob Data Contributor' role assigned." -ForegroundColor Yellow
                }
                else {
                    write-error "✗ Failed to create SAS for container '$($container.Name)': $($_.Exception.Message)"
                }
            }
        }
        
        return $sasUrls
    }
    catch {
        write-error "Failed to create user delegation blob SAS: $($_.Exception.Message)"
        return @()
    }
}

# Function to create user delegation context
function New-UserDelegationContext {
    param(
        [string]$storageAccountName,
        [string]$resourceGroupName,
        [int]$expirationHours
    )
    
    try {
        write-host "Creating user delegation context for '$storageAccountName'" -ForegroundColor Yellow
        
        # Create storage context using Azure AD authentication
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
        
        write-host "✓ User delegation context created successfully" -ForegroundColor Green
        return $ctx
    }
    catch {
        write-error "✗ Failed to create user delegation context: $($_.Exception.Message)"
        return $null
    }
}

main 
