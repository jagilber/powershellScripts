// This script creates a Cosmos DB client using a user-assigned managed identity to connect to a specified Azure Cosmos DB account.
// It then reads the properties of a given database to verify connectivity.
//
// Usage Examples:
//   dotnet script cosmos-test.csx "https://your-cosmos-account.documents.azure.com" "YourDatabaseName" "your-managed-identity-client-id"
//
// Required NuGet packages:
#r "nuget: Azure.Identity, 1.13.2"
#r "nuget: Microsoft.Azure.Cosmos, 3.47.2"

using System;
using System.Threading.Tasks;
using Azure.Identity;
using Microsoft.Azure.Cosmos;

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
        Database database = cosmosClient.GetDatabase(databaseName);
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
if (Args.Count < 3)
{
    Console.WriteLine("Usage: dotnet script -- cosmos-test.csx <cosmosEndpoint> <databaseName> <managedIdentityClientId>");
    return;
}

string cosmosEndpointArg = Args[0];
string databaseNameArg = Args[1];
string managedIdentityClientIdArg = Args[2];
Console.WriteLine($"TestCosmosClientAsync: cosmosEndpoint={cosmosEndpointArg}, databaseName={databaseNameArg}, managedIdentityClientId={managedIdentityClientIdArg}");
Console.WriteLine("Starting TestCosmosClientAsync...");
await TestCosmosClientAsync(cosmosEndpointArg, databaseNameArg, managedIdentityClientIdArg);


/*
add custom role assignment to managed identity
https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/security/how-to-grant-data-plane-role-based-access?tabs=built-in-definition%2Ccsharp&pivots=azure-interface-cli
Failed to connect to Cosmos DB: Response status code does not indicate success: Forbidden (403); 
Substatus: 5301; 
ActivityId: 00000000-0000-0000-0000-000000000000; 
Reason: ({"code":"Forbidden","message":"Request blocked by Auth sfmjagilber1nt5d : 
Request is blocked because principal [xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx] does not have required RBAC permissions to perform action 
[Microsoft.DocumentDB/databaseAccounts/readMetadata] on resource [/]. 
Learn more: https://aka.ms/cosmos-native-rbac.\r\nActivityId: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx, Microsoft.Azure.Documents.Common/2.14.0"}
*/

/*
if uami is not added to vmss, the following error will be thrown:
TestCosmosClientAsync: cosmosEndpoint=https://sfmjagilber1nt5d.documents.azure.com, databaseName=cosmicworks, managedIdentityClientId=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Starting TestCosmosClientAsync...
Failed to connect to Cosmos DB: DefaultAzureCredential failed to retrieve a token from the included credentials. See the troubleshooting guide for more information. https://aka.ms/azsdk/net/identity/defaultazurecredential/troubleshoot- EnvironmentCredential authentication unavailable. Environment variables are not fully configured. See the troubleshooting guide for more information. https://aka.ms/azsdk/net/identity/environmentcredential/troubleshoot
- WorkloadIdentityCredential authentication unavailable. The workload options are not fully configured. See the troubleshooting guide for more information. https://aka.ms/azsdk/net/identity/workloadidentitycredential/troubleshoot     
- ManagedIdentityCredential authentication unavailable. The requested identity has not been assigned to this resource.
- VisualStudioCredential authentication failed: Visual Studio Token provider can't be accessed at C:\Users\cloudadmin\AppData\Local\.IdentityService\AzureServiceAuth\tokenprovider.json
- AzureCliCredential authentication failed: Azure CLI not installed
- AzurePowerShellCredential authentication failed: Az.Accounts module >= 2.2.0 is not installed.
- AzureDeveloperCliCredential authentication failed: Azure Developer CLI could not be found.
*/