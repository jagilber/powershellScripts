# SCRIPT TO CREATE AZURE SQL DB
# 170512
# https://docs.microsoft.com/en-us/azure/sql-database/sql-database-get-started-powershell

# Server=tcp:server-3027.database.windows.net,1433;Initial Catalog=RdsCbDb;Persist Security Info=False;User ID={your_username};Password={your_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;

param(
[Parameter(Mandatory=$true)]
[string]$resourceGroupName,
[Parameter(Mandatory=$true)]
[string]$location,
[Parameter(Mandatory=$false)]
[string]$serverName,
[Parameter(Mandatory=$false)]
[string]$adminUserName = "sql-administrator",
[Parameter(Mandatory=$true)]
[string]$adminPassword,
[Parameter(Mandatory=$false)]
[pscredential]$credentials,
[Parameter(Mandatory=$false)]
[string]$nsgStartIpAllow = "0.0.0.0",
[Parameter(Mandatory=$false)]
[string]$nsgEndIpAllow = "255.255.255.255",
[Parameter(Mandatory=$true)]
[string]$databaseName

)

$erroractionpreference = "Continue"
$warningPreference = "SilentlyContinue"
$logFile = "azure-rm-create-sql.log"
#$subscriptionId = ""
#Select-AzureRmSubscription -SubscriptionId $subscriptionId 
$global:credential

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    # see if we need to auth
    try
    {
        $ret = Get-AzureRmTenant
    }
    catch 
    {
        Login-AzureRmAccount
    }

    if([string]::IsNullOrEmpty($servername))
    {
        $servername = "server-$(Get-Random)"
    }

    log-info "using server name $($servername)"

    log-info "checking adminUserName account name $($adminUsername)"
    if($adminUsername.ToLower() -eq "admin" -or $adminUsername.ToLower() -eq "administrator")
    {
        log-info "adminUserName cannot be 'admin' or 'administrator'. exiting"
        return
    }


    log-info "checking location"

    if(!(Get-AzureRmLocation | Where-Object Location -Like $location) -or [string]::IsNullOrEmpty($location))
    {
        (Get-AzureRmLocation).Location
        write-warning "location: $($location) not found. supply -location using one of the above locations and restart script."
        exit 1
    }

    log-info "checking password"

    if(!$credentials)
    {
        if([string]::IsNullOrEmpty($adminPassword))
        {
            $global:credential = Get-Credential
        }
        else
        {
            $SecurePassword = $adminPassword | ConvertTo-SecureString -AsPlainText -Force  
            $global:credential = new-object Management.Automation.PSCredential -ArgumentList $adminUsername, $SecurePassword
        }
    }
    else
    {
        $global:credential = $credentials
    }

    $adminUsername = $global:credential.UserName
    $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($global:credential.Password)) 

    $count = 0
    # uppercase check
    if($adminPassword -match "[A-Z]") { $count++ }
    # lowercase check
    if($adminPassword -match "[a-z]") { $count++ }
    # numeric check
    if($adminPassword -match "\d") { $count++ }
    # specialKey check
    if($adminPassword -match "\W") { $count++ } 

    if($adminPassword.Length -lt 8 -or $adminPassword.Length -gt 123 -or $count -lt 3)
    {
        Write-warning @"
            azure password requirements at time of writing (3/2017):
            The supplied password must be between 8-123 characters long and must satisfy at least 3 of password complexity requirements from the following: 
                1) Contains an uppercase character
                2) Contains a lowercase character
                3) Contains a numeric digit
                4) Contains a special character.
        
            correct password and restart script. 
"@
        exit 1
    }

    log-info "checking for existing resource group"

    if((Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue))
    {
        if((read-host "resource group exists! Do you want to delete?[y|n]") -ilike 'y')
        {
            Remove-AzureRmResourceGroup -Name $resourceGroupName
        }
    }

    # create resource group if it does not exist
    if(!(Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue))
    {
        log-info "creating resource group $($resourceGroupName) in location $($location)"   
        New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    }

    log-info "create a logical server"
    New-AzureRmSqlServer -ResourceGroupName $resourceGroupName `
        -ServerName $servername `
        -Location $location `
        -SqlAdministratorCredentials $global:credential

    log-info "configure a server firewall rule"
    New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourcegroupname `
        -ServerName $servername `
        -FirewallRuleName "AllowSome" -StartIpAddress $nsgStartIpAllow -EndIpAddress $nsgEndIpAllow

    log-info "create a blank database"
    New-AzureRmSqlDatabase  -ResourceGroupName $resourceGroupName `
        -ServerName $servername `
        -DatabaseName $databasename `
        -RequestedServiceObjectiveName "S0"

    log-info "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"

    log-info $data

    $counter = 0
    while(!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            out-file -Append -InputObject $data -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 10
            $counter++
        }
    }
}
# ----------------------------------------------------------------------------------------------------------------

main