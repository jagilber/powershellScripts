param(
	$username = "cloudadmin",
	$password = "n0tMiP@ssw0rD",
	$database = "testAzureSqlDb",
	$port = 1433,
	$query = "select 1"
)

$VerbosePreference = $DebugPreference = "continue"
$ErrorActionPreference = "continue"
$sqlConnection = New-Object System.Data.SqlClient.SqlConnection
$sqlConnection.ConnectionString = "Server=tcp:$database.database.windows.net,$port;Initial Catalog=$database;Persist Security Info=False;User ID=$username;Password=$password;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$sqlConnection.Open()
$sqlCmd = New-Object System.Data.SqlClient.SqlCommand($query,$sqlConnection)
$sqlReader = $sqlCmd.ExecuteReader()
$Counter = $sqlReader.FieldCount

While ($sqlReader.Read()) 
{
	For ($i = 0; $i -lt $Counter; $i++) 
	{
		Write-Host $sqlReader.GetName($i), $sqlReader.GetValue($i)
	}
}

$sqlConnection.Close()
$VerbosePreference = $DebugPreference = "silentlycontinue"
Write-Host "finished"