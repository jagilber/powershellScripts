param(
	$username = "cloudadmin",
	$password = "n0tMiP@ssw0rD",
	$database = "testAzureSqlDb",
	$port = 1433,
	$query = "select 1"
)

$VerbosePreference = $DebugPreference = "continue"
$ErrorActionPreference = "continue"
$sqlConnection = new-object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = "Server=tcp:$database.database.windows.net,$port;
    Initial Catalog=$database;
    Persist Security Info=False;
    User ID=$username;
    Password=$password;
    MultipleActiveResultSets=False;
    Encrypt=True;
    TrustServerCertificate=False;
    Connection Timeout=30;"

$sqlConnection.Open()
$sqlCmd = new-object System.Data.SqlClient.SqlCommand($query,$sqlConnection)
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
$VerbosePreference = $DebugPreference = "silentlycontinue"
write-host "finished"