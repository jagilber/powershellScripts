<#
	script to test sql connectivity to azure sql paas.
	with default query of 'select 1', output will be '1'
#>
param(
    $username = "cloudadmin",
    $password = "n0tMiP@ssw0rD",
    $database = "testAzureSqlDb",
    $port = 1433,
	$query = "select 1",
	[switch]$checkPorts
)

$VerbosePreference = $DebugPreference = "continue"
$ErrorActionPreference = "continue"
$error.Clear()
$sqlConnection = new-object System.Data.SqlClient.SqlConnection
$databaseFqdn = "$database.database.windows.net"
$sqlConnection.ConnectionString = "Server=tcp:$databaseFqdn,$port;
    Initial Catalog=$database;
    Persist Security Info=False;
    User ID=$username;
    Password=$password;
    MultipleActiveResultSets=False;
    Encrypt=True;
    TrustServerCertificate=False;
    Connection Timeout=30;"

$sqlConnection.Open()
$sqlCmd = new-object System.Data.SqlClient.SqlCommand($query, $sqlConnection)
$sqlReader = $sqlCmd.ExecuteReader()
$Counter = $sqlReader.FieldCount

while ($sqlReader.Read()) 
{
    for ($i = 0; $i -lt $Counter; $i++) 
    {
        write-host $sqlReader.GetName($i), $sqlReader.GetValue($i)
    }
}

$sqlConnection.Close()

if($checkPorts)
{
	Test-NetConnection -ComputerName $databaseFqdn -Port $port
	write-host "checking sql redirect"
	Test-NetConnection -ComputerName $databaseFqdn -Port 11000 # first
	Test-NetConnection -ComputerName $databaseFqdn -Port 11999 # last
}

$VerbosePreference = $DebugPreference = "silentlycontinue"
write-host "finished"