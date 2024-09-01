<#

.SYNOPSIS
    Manage Azure Key Vault secrets

.DESCRIPTION
    Manage Azure Key Vault secrets

.NOTES
    File Name      : azure-az-keyvault-manager.ps1
    Author         : jagilber
    Prerequisite   : PowerShell core 6.1.0 or higher

.PARAMETER secretName
    The name of the secret

.PARAMETER secretValue
    The value of the secret

.PARAMETER secretNotes
    The notes for the secret

.PARAMETER subscriptionId
    The subscription id to use

.PARAMETER resourceGroup
    The resource group to use

.PARAMETER secretFile
    The file to save secrets to

.PARAMETER vaultName
    The name of the vault

.PARAMETER vaultSecretName
    The name of the vault secret

.PARAMETER location
    The location to use

.PARAMETER setGlobalVariable
    Set the global variable

.PARAMETER saveSecretsToFile
    Save secrets to file

.PARAMETER createSecret
    Create a secret

.PARAMETER updateSecret
    Update a secret

.PARAMETER removeSecret
    Remove a secret

.PARAMETER createVault
    Create a vault

# .PARAMETER updateVault
#     Update a vault

.PARAMETER removeVault
    Remove a vault

.PARAMETER whatif
    What if

.EXAMPLE
    azure-az-keyvault-manager.ps1 -createVault -vaultName "vault"
    Create Azure Key Vault

.EXAMPLE
    azure-az-keyvault-manager.ps1 -removeVault -vaultName "vault"
    Remove Azure Key Vault

.EXAMPLE
    azure-az-keyvault-manager.ps1 -secretName "secret" -secretValue "value" -secretNotes "notes" -createSecret
    Create Azure Key Vault secrets

.EXAMPLE
    azure-az-keyvault-manager.ps1 -secretName "secret" -secretValue "value" -secretNotes "notes" -updateSecret
    Update Azure Key Vault secrets

.EXAMPLE
    azure-az-keyvault-manager.ps1 -secretName "secret" -removeSecret
    Remove Azure Key Vault secrets

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/azure-az-keyvault-manager.ps1" -outFile "$pwd\azure-az-keyvault-manager.ps1";
    .\azure-az-keyvault-manager.ps1

#>
[CmdletBinding()]
param(
    [string]$secretName, # = "secret",
    [string]$secretValue, # = "value",
    [string]$secretNotes, # = "notes",
    [string]$subscriptionId, # = "00000000-0000-0000-0000-000000000000",
    [string]$resourceGroup = "vaults",
    [string]$secretFile = "$pwd\secrets.json",
    [string]$vaultName = "*", #"vault", # has to be globally unique
    [string]$vaultSecretName = "secrets",
    [string]$location, # = "eastus",
    [bool]$setGlobalVariable = $true,
    [string]$certificateName,
    [string]$certificateIssuer = "Self",
    [string]$certificateSubject,
    [int]$certificateValidityInMonths = 12,
    [switch]$saveSecretsToFile,
    [switch]$createCertificate,
    [switch]$createSecret,
    [switch]$updateSecret,
    [switch]$removeSecret,
    [switch]$createVault,
    # [switch]$updateVault,
    [switch]$removeVault,
    [switch]$whatif
)

$script:secrets = [collections.arrayList]::new()
$ErrorActionPreference = 'Continue'
$maxSizeBytes = 25 * 1024
$maxOperationCounter = 20
$sleepSeconds = 5

function main() {
    try {
        if (!(connect-az)) { return }

        if (!$location) {
            $location = (get-resourceGroup $resourceGroup).Location
            if (!$location) {
                write-error "location is required"
                return
            }
        }
        # check if vaultName is unique
        $vaultName = create-vaultName -resourceGroup $resourceGroup -vaultName $vaultName
        if (!($vaultName)) { return }

        if (manage-vault $vaultName $location $resourceGroup) { return }

        if ((get-keyVault -resourceGroup $resourceGroup -vaultName $vaultName) -eq $null) {
            write-error "vault $vaultName not found"
            return
        }

        if ($certificateName) {
            if (!(manage-certifcate -name $certificateName `
                        -subject $certificateSubject `
                        -vaultName $vaultName `
                        -issuer $certificateIssuer `
                        -validity $certificateValidityInMonths)) { return }

            $certificate = get-certificate $certificateName $vaultName
            write-host "returning certificate $certificateName" -ForegroundColor Green
            write-verbose "returning certificate: $($certificate | ConvertTo-Json -Depth 100)"
            return $certificate
        }
        else {
            get-secretsFromVault -vaultName $vaultName -vaultSecretName $vaultSecretName
            write-verbose "secrets: $($script:secrets | ConvertTo-Json -Depth 100)"

            if (!(manage-secrets)) { return }
            if ($secretName) {
                $secret = get-secret $secretName
                write-verbose "returning secret: $($secret | ConvertTo-Json -Depth 100)"
                return $secret
            }    
        }        
                
        # convert list to keyed dictionary so we can return by name
        $secretDict = [ordered]@{}
        foreach ($secret in $script:secrets) {
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

function add-secret([string]$secretName, [collections.specialized.orderedDictionary]$secretObj) {
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

function connect-az($subscriptionId) {
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

function create-certificate([string]$certificateName, [string]$certificateSubject, [string]$vaultName, [string]$issuerName = "Self", [int]$validityInMonths = 12) {
    $error.clear()
    if (!$certificateName) {
        write-error "certificate name is required"
        return $null
    }
    if (!$certificateSubject) {
        write-error "certificate subject is required"
        return $null
    }

    if (get-certificate $certificateName $vaultName) {
        write-warning "certificate $certificateName already exists"
        return $null
    }

    write-host "creating certificate $certificateName"
    write-host "new-azKeyVaultCertificatePolicy -SubjectName $certificateSubject -IssuerName $issuerName -ValidityInMonths $validityInMonths"
    $certpolicy = new-azKeyVaultCertificatePolicy -SubjectName $certificateSubject -IssuerName $issuerName -ValidityInMonths $validityInMonths

    write-host "add-azKeyVaultCertificate -VaultName $vaultName -Name $certificateName -CertificatePolicy $certpolicy"
    $operation = add-azKeyVaultCertificate -VaultName $vaultName -Name $certificateName -CertificatePolicy $certpolicy
    $status = $operation.Status
    $counter = 0

    while ($status -ine 'completed' -and $counter -lt $maxOperationCounter) {
        write-host "status: $status counter: $counter"
        start-sleep -Seconds $sleepSeconds
        write-host "get-azKeyVaultCertificateOperation -VaultName $vaultName -Name $certificateName"
        $operation = get-azKeyVaultCertificateOperation -VaultName $vaultName -Name $certificateName
        write-verbose ($operation | ConvertTo-Json -Depth 1 -WarningAction SilentlyContinue)
        $status = $operation.Status
        $counter++
    }

    if ($status -ine 'completed') {
        write-error "certificate $certificateName not created"
        return $null
    }

    return $true
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

function create-vaultName([string]$resourceGroup, [string]$vaultName) {
    write-host "creating vault name:$vaultName"
    $retval = $null
    $count = 0
    $newName = $vaultName
    
    if (!$vaultName) {
        write-host "vault name is required" -ForegroundColor Red
        return $null
    }
    if ($vaultName -imatch "\*") {
        if ($vaultName -eq "*") {
            $vaultName = 'vault'
        }
        else {
            $vaultName = $vaultName.Replace("*", "")
        }
        write-host "generating vault name for '*' vaultname"
        while ($count -lt 100) {
            #$newName = "vault-$($count)$([regex]::Match(((get-azcontext).Account.Id) ,'[A-Za-z0-9]+').Captures[0].Value)"
            $newName = "$($vaultName)$($count)-$([regex]::Match(((get-azcontext).Subscription.Id) ,'[A-Za-z0-9]+').Captures[0].Value)"
            $count++
            write-host "newName: $newName"
            $newName = $newName.Substring(0, [math]::min($newName.length, 21)).ToLower()
            
            if (!(is-vaultNameRegistered $newName)) {
                break
            }

            if (!(is-vaultNameOwned $resourceGroup $newName)) {
                write-verbose "vault exists in different subscription"
                continue    
            }
            else {
                break
            }
        }
    }
    else {
        $newName = $vaultName
        if ((is-vaultNameRegistered $newName) -and !(is-vaultNameOwned $resourceGroup $newName)) {
            write-error "vault exists in different subscription"
            return $null
        }
    }
    if (!($count -lt 100)) { 
        $newName = $null 
        write-host "unable to generate vault name" -ForegroundColor Red
    }
    else {
        write-host "create-vaultName:returning vault name:'$newName' for vaultname" -ForegroundColor Yellow
    }
    return $newName
}

function is-vaultNameOwned([string]$resourceGroup, [string]$vaultName) {
    $vault = get-keyVault $resourceGroup $vaultName
    if ($vault) {
        write-host "vault name:'$vaultName' exists:$($vault)" -ForegroundColor Yellow
        return $true
    }
    write-host "vault name:'$vaultName' not found" -ForegroundColor Yellow
    return $false
}

function is-vaultNameRegistered([string]$vaultName) {
    if (!$vaultName) {
        write-host "vault name is required" -ForegroundColor Red
        return $null
    }

    $newName = $vaultName

    # resolve dns name to see if it is unique before checking if vault exists in subscription
    $newDnsName = "$newName.vault.azure.net"
    write-host "Resolve-DnsName -Name $newDnsName -Type A -ErrorAction SilentlyContinue"
    $dnsNameExists = Resolve-DnsName -Name $newDnsName -Type A -ErrorAction SilentlyContinue
    if ($dnsNameExists) {
        write-host "dns name $newDnsName exists" -ForegroundColor Yellow
        return $true
    }
    else {
        write-host "dns name $newDnsName does not exist" -ForegroundColor Yellow
    }
    
    return $false
}

function get-certificate([string]$certificateName, [string]$vaultName) {
    write-host "get-azkeyvaultcertificate -vaultName $vaultName -name $certificateName"
    $certificate = get-azkeyvaultcertificate -vaultName $vaultName -name $certificateName -ErrorAction SilentlyContinue
    if (!$certificate) {
        write-host "certificate $certificateName not found"
        return $null
    }
    return $certificate
}

function get-keyVault([string]$resourceGroup, [string]$vaultName) {
    $error.clear()
    write-host "get-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup"
    if (!$vaultName -or $vaultname -eq "*") {
        write-host "vault name is required" -ForegroundColor Red
        return $null
    }
    # if($vaultname -eq "*") {
    #     $vaults = @(get-azkeyvault -ResourceGroupName $resourceGroup)
    #     if($vaults.Count -eq 1) {
    #         write-host "returning vault:'$($vaults[0].VaultName)' for '*' vaultname" -ForegroundColor Yellow
    #         return $vaults[0]
    #     }
    #     write-host "'*' specified but $($vaults.Count) vaults found. to use '*', only 1 vaultname can be enumerated. list of vaults in subscription:$($vaults | out-string)" -ForegroundColor Yellow
    #     return $null
    # }
    $vault = get-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup
    if (!$vault) {
        $rgVaults = get-azkeyvault -ResourceGroupName $resourceGroup
        if ($rgVaults) {
            write-host "list of vaults in resource group:$($resourceGroup)$($rgVaults | out-string)" -ForegroundColor Yellow
        }
        else {
            $vaults = get-azkeyvault
            write-host "no vaults found in resource group:$($resourceGroup)" -ForegroundColor Yellow
            write-host "list of vaults in subscription:$($vaults | out-string)" -ForegroundColor Yellow
        }

        write-host "vault name:'$vaultName' not found" -ForegroundColor Red
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

function manage-certifcate([string]$name, [string]$subject, [string]$vaultName, [string]$issuer, [int]$validity) {
    if ($createCertificate) {
        $certificate = create-certificate -certificateName $name `
            -certificateSubject $subject `
            -vaultName $vaultName `
            -issuerName $issuer `
            -validityInMonths $validity

        if (!$certificate) {
            write-error "certificate $name not created"
            return $false
        }

        write-host "certificate $name created"
        return $true
    }

    return $true
}

function manage-secrets() {
    if ($createSecret) {
        add-secret $secretName (new-secret $secretName $secretValue $secretNotes)
        if (!(set-secretsToVault -vaultName $vaultName -vaultSecretName $vaultSecretName -secrets $script:secrets)) {
            return $false
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

    return $true
}

function manage-vault([string]$vaultName, [string]$location, [string]$resourceGroup) {
    if ($createVault) {
        $vault = create-keyVault -resourceGroup $resourceGroup -vaultName $vaultName -location $location
        if (!$vault) {
            write-error "vault $vaultName not created"
            return $false
        }
        write-host "vault $vaultName created"
        return $true
    }
    # elseif ($updateVault) {
    #     write-host "updating vault $vaultName"
    #     if(get-keyVault -resourceGroup $resourceGroup -vaultName $vaultName) {
    #         write-host "vault $vaultName already exists"
    #     }
    #     else {
    #         write-warning "vault $vaultName not found"
    #     }
    #     # update vault
    #     return $true
    # }
    elseif ($removeVault) {
        write-host "removing vault $vaultName"
        if (get-keyVault -resourceGroup $resourceGroup -vaultName $vaultName) {
            remove-azkeyvault -vaultName $vaultName -ResourceGroupName $resourceGroup
        }
        else {
            write-warning "vault $vaultName not found"
        }
        # remove vault
        return $true
    }
    return $false
}

function new-secret([string]$name = "", [string]$value = "", [string]$notes = "") {
    $secret = [ordered]@{
        name     = $name
        value    = $value
        created  = (Get-Date).ToString()
        notes    = $notes
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
        $secret.created = $secret.created
        $secret.notes = if ($notes) { $notes } else { $secret.notes }
        $secret.modified = (Get-Date).ToString()
    }

    return $secret
}

main