# SCRIPT TO CREATE AZURE SQL DB
# 170513
# https://docs.microsoft.com/en-us/azure/sql-database/sql-database-get-started-powershell

# Server=tcp:server-1877773027.database.windows.net,1433;Initial Catalog=RdsCbDb;Persist Security Info=False;User ID={your_username};Password={your_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;

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
$global:credential = $null

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $createSqlServer = $false
    $CreateSqlDatabase = $false

    # see if we need to auth
    try
    {
        $ret = Get-AzureRmTenant
    }
    catch 
    {
        Login-AzureRmAccount
    }

    log-info "checking location $($location)"

    if(!(Get-AzureRmLocation | Where-Object Location -Like $location) -or [string]::IsNullOrEmpty($location))
    {
        (Get-AzureRmLocation).Location
        write-warning "location: $($location) not found. supply -location using one of the above locations and restart script."
        exit 1
    }

    log-info "checking for existing resource group $($resourceGroupName)"

    # create resource group if it does not exist
    if(!(Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue))
    {
        log-info "creating resource group $($resourceGroupName) in location $($location)"   
        New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    }
    else
    {
        log-info "resource group $($resourceGroupName) already exists."
    }

    # make sure sql available in region
    $sqlAvailable = Get-AzureRmSqlCapability -LocationName $location
    log-info "sql server capability in $($location) : $($sqlAvailable.Status)"
    if(!$sqlAvailable)
    {
        log-info "sql not available in this region. exiting"
        return
    }

    log-info "checking for sql servers in resource group $($resourceGroupName)"
    

    if([string]::IsNullOrEmpty($servername))
    {
        $sqlServersAvailable = @(Get-AzureRmSqlServer -ResourceGroupName $resourceGroupName)
    }
    else
    {
        $sqlServersAvailable = @(Get-AzureRmSqlServer -ServerName $servername -ResourceGroupName $resourceGroupName)
    }

    if([string]::IsNullOrEmpty($servername))
    {
        if($sqlServersAvailable.Count -gt 0)
        {
            log-info "existing sql servers in resource group:"
            $sqlServersAvailable.ServerName | fl *
        }

        $servername = read-host "enter servername to use for new database or leave empty to generate random name"
    }

    if([string]::IsNullOrEmpty($servername))
    {
        $servername = "sql-server-$(Get-Random)"
    }

    if($sqlServersAvailable.Count -gt 0 -and $sqlServersAvailable.ServerName.Contains($servername))
    {
        $sqlDbAvailable = Get-AzureRmSqlDatabase -DatabaseName $databaseName `
            -ResourceGroupName $resourceGroupName `
            -ServerName $servername `
            -ErrorAction SilentlyContinue
    }
    else
    {
        $createSqlServer = $true
    }

    log-info "checking sql db $($databaseName) on server $($servername)"
    $sqlDbAvailable = Get-AzureRmSqlDatabase -DatabaseName $databaseName `
        -ResourceGroupName $resourceGroupName `
        -ServerName $servername `
        -ErrorAction SilentlyContinue

    if(!$sqlDbAvailable)
    {
        $CreateSqlDatabase = $true
    }
    else
    {
        log-info "database $($databasename) already exists on server $($servername). exiting"
        return
    }

    log-info "using server name $($servername)"
    log-info "creating sql server : $($createSqlServer) creating sql db : $($CreateSqlDatabase)"

    log-info "checking adminUserName account name $($adminUsername)"
    if($adminUsername.ToLower() -eq "admin" -or $adminUsername.ToLower() -eq "administrator")
    {
        log-info "adminUserName cannot be 'admin' or 'administrator'. exiting"
        return
    }


    log-info "using admin name: $($adminUserName)"

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


    if($createSqlServer)
    {

        log-info "create a logical server"
        New-AzureRmSqlServer -ResourceGroupName $resourceGroupName `
            -ServerName $servername `
            -Location $location `
            -SqlAdministratorCredentials $global:credential

        log-info "configure a server firewall rule"
        New-AzureRmSqlServerFirewallRule -ResourceGroupName $resourcegroupname `
            -ServerName $servername `
            -FirewallRuleName "AllowSome" -StartIpAddress $nsgStartIpAllow -EndIpAddress $nsgEndIpAllow
    }

    if($CreateSqlDatabase)
    {
        log-info "create a blank database"

        New-AzureRmSqlDatabase  -ResourceGroupName $resourceGroupName `
            -ServerName $servername `
            -DatabaseName $databasename `
            -RequestedServiceObjectiveName "S0"
    }


    log-info "connection string:`r`nServer=tcp:$($servername).database.windows.net,1433;Initial Catalog=$($databaseName);Persist Security Info=False;User ID=$($adminUserName);Password=$($adminPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    log-info "finished"
}

# ----------------------------------------------------------------------------------------------------------------
function log-info($data)
{
    
    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"

    write-host $data

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