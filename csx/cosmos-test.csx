// This script creates a Cosmos DB client using a user-assigned managed identity to connect to a specified Azure Cosmos DB account.
// It then reads the properties of a given database to verify connectivity.
//
// Usage Examples:
//   dotnet script -- c:\github\jagilber\powershellScripts\csx\cosmos-test.csx "https://your-cosmos-account.documents.azure.com:443/" "YourDatabaseName" "your-managed-identity-client-id"
//
// Required NuGet packages:
#r "nuget: Azure.Identity, 1.7.0"
#r "nuget: Azure.Cosmos, 4.0.0"

using System;
using System.Threading.Tasks;
using Azure.Identity;
using Azure.Cosmos;

// Function: TestCosmosClientAsync
// Parameters:
//   cosmosEndpoint: your Cosmos DB account endpoint (e.g., https://your-account.documents.azure.com:443/)
//   databaseName: the Cosmos DB database to test connection with
//   managedIdentityClientId: the client id of your user-assigned managed identity
// Description:
//   Creates a CosmosClient using DefaultAzureCredential configured with the provided managed identity.
//   It then attempts to read the specified database's properties to verify that the connection is successful.
async Task TestCosmosClientAsync(string cosmosEndpoint, string databaseName, string managedIdentityClientId)
{
    // Set up the managed identity credential options.
    var credentialOptions = new DefaultAzureCredentialOptions { ManagedIdentityClientId = managedIdentityClientId };
    var credential = new DefaultAzureCredential(credentialOptions);
    
    // Create the CosmosClient with the specified endpoint and credential.
    CosmosClientOptions clientOptions = new CosmosClientOptions()
    {
        ConnectionMode = ConnectionMode.Gateway
    };
    CosmosClient cosmosClient = new CosmosClient(cosmosEndpoint, credential, clientOptions);
    
    try
    {
        // Attempt to read database properties.
        CosmosDatabase database = cosmosClient.GetDatabase(databaseName);
        var response = await database.ReadAsync();
        Console.WriteLine("Connected successfully to Cosmos DB.");
        Console.WriteLine($"Database Id: {response.Resource.Id}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to connect to Cosmos DB: {ex.Message}");
    }
}

// Parse command-line arguments from dotnet script.
if (args.Length < 3)
{
    Console.WriteLine("Usage: dotnet script -- c:\\github\\jagilber\\powershellScripts\\csx\\cosmos-test.csx <cosmosEndpoint> <databaseName> <managedIdentityClientId>");
    return;
}

string cosmosEndpointArg = args[0];
string databaseNameArg = args[1];
string managedIdentityClientIdArg = args[2];
Console.WriteLine($"TestCosmosClientAsync: cosmosEndpoint={cosmosEndpointArg}, databaseName={databaseNameArg}, managedIdentityClientId={managedIdentityClientIdArg}");
Console.WriteLine("Starting TestCosmosClientAsync...");
await TestCosmosClientAsync(cosmosEndpointArg, databaseNameArg, managedIdentityClientIdArg);
