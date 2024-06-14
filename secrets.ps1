<#
.\secrets.ps1 -createVault -resourceGroup vaults -vaultName vault -vaultSecretName secrets -location eastus
.\secrets.ps1 -secretKeyName external-subscription  -secretValue '00000000-0000-0000-0000-000000000000' -updateSecret -secretNotes 'test secret'
#>

param(
    [string]$secretKeyName, # = "key",
    [string]$secretName, # = "secret",
    [string]$secretValue, # = "value",
    [string]$secretNotes, # = "notes",
    [string]$subscriptionId, # = "00000000-0000-0000-0000-000000000000",
    [string]$resourceGroup = "vaults",
    [string]$jsonConfig = "$pwd\secrets.json",
    [string]$vaultName = "vault",
    [string]$vaultSecretName = "secrets",
    [string]$location, # = "eastus",
    [switch]$saveSecretsToFile,
    [switch]$updateVault,
    [switch]$updateSecret,
    [switch]$setGlobalVariable,
    [switch]$createVault
)

$script:secrets = @{}
$ErrorActionPreference = 'Continue'
$maxSizeBytes = 25 * 1024

function main() {
    try {
        if (!(connect-az)) { return }

        if ($createVault) {
            $vault = create-keyVault -resourceGroup $resourceGroup -vaultName $vaultName -location $location
            if (!$vault) {
                return
            }
        }
        if ($updateVault) {
            $script:secrets = read-secretsFromFile $jsonConfig
            if (!($script:secrets)) {
                write-error "secrets file not found"
                return
            }
            if (!(set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets)) {
                write-error "failed to set secrets to vault"
                return
            }
            return
        }

        if ($updateSecret) {
            $script:secrets = get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
            update-secret -secretName $secretKeyName -name $secretName -value $secretValue -notes $secretNotes
            set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets
            return
        }

        if ($setGlobalVariable) {
            $global:secrets = $script:secrets
        }

        $script:secrets = get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
        write-verbose "secrets: $($script:secrets | ConvertTo-Json -Depth 100)"

        if ($saveSecretsToFile) {
            save-secrets
        }
        return $script:secrets
    }
    catch {
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return 1
    }
    finally {
    }
}

function add-secret([string]$secretName, [object]$secretObj) {
    if (!$secretObj) {
        write-error "secret object is null"
        return $false
    }
    if (!(get-secret $secretName)) {
        [void]$script:secrets.add($secretName, $secretObj)
        write-host "secret $secretName added"
        return $true
    }
    else {
        write-host "secret $secretName already exists"
        return $false
    }
    
}

function connect-az($resourceGroup, $subscriptionId) {
    $moduleList = @('az.accounts', 'az.resources', 'az.keyvault')
    
    foreach ($module in $moduleList) {
        write-verbose "checking module $module"
        if (!(get-module -name $module)) {
            if (!(get-module -name $module -listavailable)) {
                write-host "installing module $module" -ForegroundColor Yellow
                install-module $module -force
                import-module $module
                if (!(get-module -name $module -listavailable)) {
                    return $false
                }
            }
        }
    }

    if ($subscriptionId -and (Get-AzContext).Subscription.Id -ne $subscriptionId) {
        write-host "setting subscription $subscriptionId" -ForegroundColor Yellow
        set-azcontext -SubscriptionId $subscriptionId
    }

    if (!(@(Get-AzResourceGroup).Count)) {
        $error.clear()
        Connect-AzAccount

        if ($error -and ($error | out-string) -match '0x8007007E') {
            $error.Clear()
            Connect-AzAccount -UseDeviceAuthentication
        }
    }

    return $null = get-azcontext
}

function new-secret([string]$secretName, [string]$name = "", [string]$value = "", [string]$notes = "") {
    if (!$name) {
        $name = $secretName
    }
    $secret = @{
        name     = $name
        value    = $value
        notes    = $notes
        created  = (Get-Date).ToString()
        modified = (Get-Date).ToString()
    }
    return $secret
}

function create-keyVault([string]$resourceGroup, [string]$vaultName, [string]$location) {
    $error.clear()
    if (!(get-resourceGroup $resourceGroup)) {
        if ($createVault) {
            return create-resourceGroup $resourceGroup $location
        }
        else {
            write-error "resource group $resourceGroup not found"
            return $null
        }
    }

    write-host "creating vault $vaultName"
    write-host "new-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup -Location $location"
    $vault = new-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup -Location $location
    if ($error) {
        write-error $error
        return $null
    }
    return $vault
}

function get-keyVault([string]$resourceGroup, [string]$vaultName) {
    $error.clear()
    write-host "get-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup"
    $vault = get-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup
    if (!$vault) {
        write-host "vault $vaultName not found"
        return $null
    }
    if ($error) {
        write-warning "$($error.Exception | out-string)"
        return $null
    }
    return $vault
}

function create-resourceGroup([string]$resourceGroup, [string]$location) {
    $error.clear()
    write-host "creating resource group $resourceGroup"
    write-host "new-azresourcegroup -name $resourceGroup -location $location"
    $result = new-azresourcegroup -name $resourceGroup -location $location
    if ($error) {
        write-error $error
        return $null
    }
    return $result
}

function get-resourceGroup([string]$resourceGroup) {
    $error.clear()
    write-host "get-azresourcegroup -name $resourceGroup"
    $result = get-azresourcegroup -name $resourceGroup -erroraction silentlycontinue
    if ($error) {
        write-warning "$($error.Exception | out-string)"
        return $null
    }
    return $result
}

function get-secret([string]$secretName) {
    write-host "getting secret $secretName"
    if (!$script:secrets -or !$script:secrets.ContainsKey($secretName)) {
        write-host "secret $secretName not found"
        return $null
    }
    return $script:secrets[$secretName]
}

function get-secretsFromVault([string]$vaultName, [string]$vaultSecretName, [switch]$includeVersions) {
    $error.clear()
    $secrets = @{}
    write-host "get-azkeyvaultsecret -vaultName $vaultName -name $vaultSecretName"
    $kvSecret = get-azkeyvaultsecret -vaultName $vaultName -name $vaultSecretName #-AsPlainText
    $global:kvSecret = $kvSecret
    write-verbose "kvSecret: $($kvSecret | ConvertTo-Json -Depth 100)"
    $plainString = ConvertFrom-SecureString -SecureString $kvSecret.SecretValue -AsPlainText
    $secretString = [text.encoding]::UNICODE.GetString([convert]::FromBase64String($plainString))
    if ($error) {
        write-warning "$($error.Exception | out-string)"
        return @{}
    }
    if (!$secretString) {
        write-host "secrets not found"
        return @{}
    }
    try {
        write-host $secretString
        $secretObj = $secretString | ConvertFrom-Json -AsHashtable
        $script:secrets = $secretObj
        return $script:secrets
    }
    catch [System.Management.Automation.PSArgumentException] {
        write-host "error converting secret string to object $($error.Exception.Message)"
        $error.Clear()
        return @{}
    }
}

function set-secretsToVault([string]$vaultName, [string]$vaultSecretName, [object]$secrets) {
    if (!$secrets) {
        write-error "secrets object is null"
        return $false
    }

    $error.clear()
    $secretString = $secrets | ConvertTo-Json -Depth 100 -Compress
    $baseString = [convert]::ToBase64String([text.encoding]::Unicode.GetBytes($secretString))
    write-host "set-azkeyvaultsecret -vaultName $vaultName -Name $vaultSecretName -SecretValue $secretString"
    $secureString = ConvertTo-SecureString -String $baseString -Force -AsPlainText
    $secureStringSize = $baseString.Length
    if ($secureStringSize -gt $maxSizeBytes) {
        write-error "secret size $secureStringSize exceeds maximum size $maxSizeBytes"
        return $false
    }
    if($maxSizeBytes - $secureStringSize -lt 10000) {
        write-warning "secret size $secureStringSize is close to maximum size $maxSizeBytes"
    }
    else {
        write-host "secret size $secureStringSize (percentage: $($secureStringSize / $maxSizeBytes * 100))" -ForegroundColor Green
    }

    set-azkeyvaultsecret -vaultName $vaultName -Name $vaultSecretName -SecretValue $secureString
    if ($error) {
        write-error $error
        return $false
    }
    return $true
}

function set-secret([string]$secretName, [string]$value) {
    write-host "setting secret $secretName"
    if (!(get-secret $secretName)) {
        $script:secrets[$secretName] = new-secret $secretName $value
    }
    else {
        $script:secrets[$secretName].value = $value
    }
}

function read-secretsFromFile($jsonConfig) {
    write-host "reading secrets from $jsonConfig"
    if (!(test-path $jsonConfig)) {
        write-error "secrets file not found"
        return $null
    }
    $secrets = Get-Content -Raw -Path $jsonConfig | ConvertFrom-Json
    return $secrets
}

function save-secrets() {
    write-host "saving secrets to $jsonConfig"
    $script:secrets | ConvertTo-Json | Set-Content -Path $jsonConfig
}

function update-secret([string]$secretName, [string]$name = "", [string]$value = "", [string]$notes = "") {
    write-host "updating secret $secretName"
    # if(!$name) {
    #     $name = $secretName
    # }
    $secret = get-secret $secretName
    if (!$secret) {
        write-host "secret $secretName not found"
        return add-secret $secretName (new-secret $secretName $name $value $notes)
    }
    $script:secrets[$secretName] = @{
        name     = if ($name) { $name } else { $secret.name }
        value    = if ($value) { $value } else { $secret.value }
        notes    = if ($notes) { $notes } else { $secret.notes }
        created  = $secret.created
        modified = (Get-Date).ToString()
    }
    return $secret
}


main