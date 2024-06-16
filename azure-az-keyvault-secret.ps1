<#
.\secrets.ps1 -createVault -resourceGroup vaults -vaultName vault -vaultSecretName secrets -location eastus
.\secrets.ps1 -secretKeyName external-subscription  -secretValue '00000000-0000-0000-0000-000000000000' -updateSecret -secretNotes 'test secret'
#>
[CmdletBinding()]
param(
    [string]$secretName, # = "secret",
    [string]$secretValue, # = "value",
    [string]$secretNotes, # = "notes",
    [string]$subscriptionId, # = "00000000-0000-0000-0000-000000000000",
    [string]$resourceGroup = "vaults",
    [string]$secretFile = "$pwd\secrets.json",
    [string]$vaultName = "vault", # has to be globally unique
    [string]$vaultSecretName = "secrets",
    [string]$location, # = "eastus",
    [switch]$saveSecretsToFile,
    [switch]$createSecret,
    [switch]$updateSecret,
    [switch]$removeSecret,
    [switch]$createVault,
    [switch]$updateVault,
    [switch]$removeVault,
    [switch]$setGlobalVariable,
    [switch]$whatif
)

$script:secrets = [collections.arrayList]::new()
$ErrorActionPreference = 'Continue'
$maxSizeBytes = 25 * 1024

function main() {
    try {
        if (!(connect-az)) { return }

        if ($createVault) {
            $vault = create-keyVault -resourceGroup $resourceGroup -vaultName $vaultName -location $location
            write-host "vault: $($vault | ConvertTo-Json -Depth 1)"
            return
        }
        elseif ($updateVault) {
            [void]$script:secrets.AddRange((read-secretsFromFile $secretFile))
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
        elseif ($removeVault) {
            if ((get-keyVault -resourceGroup $resourceGroup -vaultName $vaultName)) {
                write-host "removing vault $vaultName"
                remove-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup
            }
            else {
                write-warning "vault $vaultName not found"
            }
            return
        }

        get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
        write-verbose "secrets: $($script:secrets | ConvertTo-Json -Depth 100)"

        if ($createSecret) {
            add-secret $secretName (new-secret $secretName $secretValue $secretNotes)
            if(!(set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets)) {
                return
            }
            get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
        }
        elseif ($updateSecret) {
            update-secret -name $secretName -value $secretValue -notes $secretNotes
            set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets
            get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
        }
        elseif ($removeSecret) {
            $secret = get-secret $secretName
            if ($secret) {
                write-host "removing secret $secretName"
                $script:secrets.Remove($secret)
                set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets
                get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
            }
            else {
                write-warning "secret $secretName not found"
            }
        }

        if ($saveSecretsToFile) {
            save-secretsToFile $secretFile
        }
        

        if ($secretName) {
            $secret = get-secret $secretName
            write-verbose "returning secret: $($secret | ConvertTo-Json -Depth 100)"
            return $secret
        }
        
        # convert list to keyed dictionary so we can return by name
        $secretDict = [ordered]@{}
        foreach($secret in $script:secrets) {
            write-host "secret: $($secret)"
            [void]$secretDict.add($secret.name, $secret)
        }

        if ($setGlobalVariable) {
            $global:secrets = $secretDict
        }

        return $secretDict # $script:secrets
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
        [void]$script:secrets.add($secretObj)
        write-host "secret $secretName added"
        return $true
    }
    else {
        write-host "secret $secretName already exists"
        return $false
    }

}

function check-secretSize([string]$secretValue) {
    $secretSize = $secretValue.Length
    if ($secretSize -gt $maxSizeBytes) {
        write-error "secret ($($script:secrets.Count)) size $secretSize exceeds maximum size $maxSizeBytes"
        return $false
    }
    if ($maxSizeBytes - $secretSize -lt 10000) {
        write-warning "secret ($($script:secrets.Count)) size $secretSize is close to maximum size $maxSizeBytes"
    }
    else {
        write-host "secret ($($script:secrets.Count)) size $secretSize (percentage: $($secretSize / $maxSizeBytes * 100))" -ForegroundColor Green
    }
    return $true
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

function convert-csvToJson([string]$csv) {
    write-host "converting csv to json:`n$csv" -ForegroundColor Cyan
    $jsonString = "[$(($csv | ConvertFrom-Csv | ConvertTo-Json).trim("[]"))]"
    write-host "returning json string:`n$jsonString" -ForegroundColor DarkCyan
    return $jsonString
}

function convert-jsonToCsv([string]$jsonString) {
    write-host "converting json to csv:`n$jsonString" -ForegroundColor Cyan
    $jsonObj = $jsonString | ConvertFrom-Json
    $csvString = [text.stringbuilder]::new()

    $header = $null
    foreach ($obj in $jsonObj) {
        if (!$header) {
            $withHeader = ($obj | ConvertTo-Csv)
            $withoutHeader = ($obj | ConvertTo-Csv -NoHeader)
            $header = $withHeader.replace($withoutHeader, "")
            write-host "header: $header"
            [void]$csvString.appendLine($header)
        }
        [void]$csvString.appendLine(($obj | ConvertTo-Csv -NoHeader))
    }

    write-host "returning csv string:`n$csvString" -ForegroundColor DarkCyan
    return ($csvString.toString())
}

function create-keyVault([string]$resourceGroup, [string]$vaultName, [string]$location) {
    $error.clear()
    if (!(get-resourceGroup $resourceGroup)) {
        if ($createVault) {
            if (!(create-resourceGroup $resourceGroup $location)) {
                return $null
            }
        }
        else {
            write-error "resource group $resourceGroup not found"
            return $null
        }
    }

    write-host "creating vault $vaultName"
    write-host "new-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup -Location $location" -ForegroundColor Green
    if ($whatif) { return $true }
    $vault = new-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup -Location $location
    if ($error) {
        write-error $error
        return $null
    }
    return $vault
}

function create-resourceGroup([string]$resourceGroup, [string]$location) {
    $error.clear()
    if (!$location) {
        write-error "location is required"
        return $null
    }
    write-host "creating resource group $resourceGroup"
    write-host "new-azresourcegroup -name $resourceGroup -location $location" -ForegroundColor Green
    if ($whatif) { return $true }
    $result = new-azresourcegroup -name $resourceGroup -location $location
    if ($error) {
        write-error $error
        return $null
    }
    return $result
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
    if (!$script:secrets -or !($script:secrets | Where-Object name -ieq $secretName)) {
        write-host "secret $secretName not found"
        return $null
    }
    return ($script:secrets | Where-Object name -ieq $secretName)
}

function get-secretsFromVault([string]$vaultName, [string]$vaultSecretName, [switch]$includeVersions) {
    $error.clear()
    $noSecrets = [collections.arrayList]::new()
    write-host "get-azkeyvaultsecret -vaultName $vaultName -name $vaultSecretName"
    try {
        $kvSecret = get-azkeyvaultsecret -vaultName $vaultName -name $vaultSecretName #-AsPlainText
        #temp
        $global:kvSecret = $kvSecret
        if (!$kvSecret) {
            write-host "secrets not found"
            return $noSecrets
        }
        write-verbose "kvSecret: $($kvSecret | ConvertTo-Json -Depth 100)"
        $plainString = ConvertFrom-SecureString -SecureString $kvSecret.SecretValue -AsPlainText
        $secretString = [text.encoding]::UNICODE.GetString([convert]::FromBase64String($plainString))
        if ($error) {
            write-warning "$($error.Exception | out-string)"
            return $noSecrets
        }
        if (!$secretString) {
            write-host "secrets not found"
            return $noSecrets
        }
        write-host $secretString
        $null = check-secretSize $secretString
        # convert csv to json
        $jsonString = convert-csvToJson $secretString
        #temp
        $global:jsonString = $jsonString
        $secretObj = @(ConvertFrom-Json $jsonString) #-AsHashtable
        if (!$secretObj) {
            write-error "unable to convert secret string to object"
            return $noSecrets
        }
        [void]$script:secrets.clear()
        [void]$script:secrets.addrange($secretObj)
        return $script:secrets
    }
    catch [System.Management.Automation.PSArgumentException] {
        write-host "error converting secret string to object $($error.Exception.Message)"
        $error.Clear()
        return $noSecrets
    }
}

function new-secret([string]$name = "", [string]$value = "", [string]$notes = "") {
    $secret = [ordered]@{
        name     = $name
        value    = $value
        notes    = $notes
        created  = (Get-Date).ToString()
        modified = (Get-Date).ToString()
    }
    return $secret
}

function read-secretsFromFile($secretFile) {
    write-host "reading secrets from $secretFile"
    if (!(test-path $secretFile)) {
        write-error "secrets file not found"
        return $null
    }
    $secrets = ConvertFrom-Json (Get-Content -Raw -Path $secretFile)
    return $secrets
}

function save-secretsToFile([string]$secretFile) {
    write-host "saving secrets to $secretFile"
    $jsonString = "[$((convertto-json $script:secrets).trim("[]"))]"
    write-verbose "jsonString: $jsonString"
    out-file -InputObject $jsonString -FilePath $secretFile
}

function save-toFile([string]$file, [string]$content) {
    write-host "saving $file"
    $content = "$(Get-Date) ----------------`r`n$content"
    write-verbose "content: $content"
    out-file -InputObject $content -FilePath $file
}

function set-secretsToVault([string]$vaultName, [string]$vaultSecretName, [collections.arraylist]$secrets) {
    if (!$secrets) {
        write-error "secrets object is null"
        return $false
    }

    $error.clear()
    $secretString = $secrets | ConvertTo-Json -Depth 100 -Compress
    # convert json to csv
    $csvString = convert-jsonToCsv $secretString
    $baseString = [convert]::ToBase64String([text.encoding]::Unicode.GetBytes($csvString))

    $secureString = ConvertTo-SecureString -String $baseString -Force -AsPlainText
    if (!(check-secretSize $baseString)) {
        return $false
    }

    write-host "set-azkeyvaultsecret -vaultName $vaultName -Name $vaultSecretName -SecretValue $secretString"
    if ($whatif) { return $true }
    set-azkeyvaultsecret -vaultName $vaultName -Name $vaultSecretName -SecretValue $secureString
    if ($error) {
        write-error $error
        return $false
    }
    return $true
}

function update-secret([string]$name = "", [string]$value = "", [string]$notes = "") {
    write-host "updating secret $Name"
    $secret = get-secret $name
    if (!$secret) {
        write-host "secret $name not found"
        return add-secret $name (new-secret $name $value $notes)
    }
    else {
        # update secret
        $secret.name = if ($name) { $name } else { $secret.name }
        $secret.value = if ($value) { $value } else { $secret.value }
        $secret.notes = if ($notes) { $notes } else { $secret.notes }
        $secret.created = $secret.created
        $secret.modified = (Get-Date).ToString()
    }

    return $secret
}

main