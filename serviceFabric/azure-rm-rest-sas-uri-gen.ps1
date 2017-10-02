# https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-rm-rest-sas-uri-gen.ps1
# jagilber
# use to generate / account sas uri with given azure storage account access key and storage resource uri
# references:
#    https://blogs.msdn.microsoft.com/tsmatsuz/2016/07/06/how-to-get-azure-storage-rest-api-authorization-header/
#    https://docs.microsoft.com/en-us/rest/api/storageservices/constructing-a-service-sas
#    https://docs.microsoft.com/en-us/azure/storage/common/storage-dotnet-shared-access-signature-part-1?toc=%2fazure%2fstorage%2fblobs%2ftoc.json
# 20171002

param(
    # Required. access key is located in storage account properties in portal
    # Example "NEExpzAjjo7JpKURq6TbnACEEejy4sp3ZxD6c8g4jMoP3M+p4YkRHy2rjHb6hyIdccyfPnljlyP7iM3Cd7vjQg=="
    [parameter(Mandatory=$true)]
    $accessKey,
    
    # Required uri
    # Example "https://sflogssf118243.table.core.windows.net/",
    [parameter(Mandatory=$true)]
    $storageResourceUri,
    
    # Required. sv Specifies the signed storage service version to use to authenticate requests made with this account SAS. Must be set to version 2015-04-05 or later.
    $signedVersion = '2017-04-17',

    # Required. ss Specifies the signed services accessible with the account SAS. Possible values include:
    # - Blob (b)
    # - Queue (q)
    # - Table (t)
    # - File (f)
    $signedServices = 'bqtf', # all

    # Required. srt Specifies the signed resource types that are accessible with the account SAS.
    # - Service (s): Access to service-level APIs (e.g., Get/Set Service Properties, Get Service Stats, List Containers/Queues/Tables/Shares)
    # - Container (c): Access to container-level APIs (e.g., Create/Delete Container, Create/Delete Queue, Create/Delete Table, Create/Delete Share, List Blobs/Files and Directories)
    # - Object (o): Access to object-level APIs for blobs, queue messages, table entities, and files(e.g. Put Blob, Query Entity, Get Messages, Create File, etc.)
    # You can combine values to provide access to more than one resource type. For example, srt=sc specifies access to service and container resources.
    $signedResourceTypes = 'sco', #all

    # Required. sp Specifies the signed permissions for the account SAS. Permissions are only valid if they match the specified signed resource type; otherwise they are ignored.
    # - Read (r): Valid for all signed resources types (Service, Container, and Object). Permits read permissions to the specified resource type.
    # - Write (w): Valid for all signed resources types (Service, Container, and Object). Permits write permissions to the specified resource type.
    # - List (l): Valid for Service and Container resource types only.
    # - Add (a): Valid for the following Object resource types only: queue messages, table entities, and append blobs.
    # - Create (c): Valid for the following Object resource types only: blobs and files. Users can create new blobs or files, but may not overwrite existing blobs or files.
    # - Update (u): Valid for the following Object resource types only: queue messages and table entities.
    # - Process (p): Valid for the following Object resource type only: queue messages.
    $signedPermission = 'rwdlacup', # all

    # Optional. st The time at which the SAS becomes valid, in an ISO 8601 format. If omitted, start time for this call is assumed to be the time when the storage service receives the request.
    #  ISO 8601 formats include the following: +
    #  YYYY-MM-DD
    #  YYYY-MM-DDThh:mmTZD
    #  YYYY-MM-DDThh:mm:ssTZD
    $signedStart = [DateTime]::UtcNow.ToString("yyyy-MM-ddThh:mm:ssZ"), # default (now)

    # Required. se The time at which the SAS becomes invalid, in an ISO 8601 format. 
    #  ISO 8601 formats include the following: +
    #  YYYY-MM-DD
    #  YYYY-MM-DDThh:mmTZD
    #  YYYY-MM-DDThh:mm:ssTZD
    $signedExpiry = [DateTime]::UtcNow.AddDays(1).ToString("yyyy-MM-ddThh:mm:ssZ"), # add 1 day
    
    # Optional. sip Specifies an IP address or a range of IP addresses from which to accept requests. When specifying a range, note that the range is inclusive.
    # For example, sip=168.1.5.65 or sip=168.1.5.60-168.1.5.70.
    $signedIP = "0.0.0.0-255.255.255.255", # accept any

    # Optional. spr Specifies the protocol permitted for a request made with the account SAS. Possible values are both HTTPS and HTTP (https,http) or HTTPS only (https). The default value is https,http.
    # Note that HTTP only is not a permitted value.
    $signedProtocol = 'https' #,http' # default
)

$error.Clear()

# get account name from uri
$storageResourceUri -imatch "http.://(.+?)\.|/"
$accountName = $Matches[1]
write-host "account name: $($accountName)"

# Required. The signature part of the URI is used to authenticate the request made with the shared access signature.
# The string-to-sign is a unique string constructed from the fields that must be verified in order to authenticate the request. 
# The signature is an HMAC computed over the string-to-sign and key using the SHA256 algorithm, and then encoded using Base64 encoding.
$signatureString = $accountName + "`n" `
    + $signedPermission + "`n" `
    + $signedServices + "`n" `
    + $signedResourceTypes + "`n" `
    + $signedStart + "`n" `
    + $signedExpiry + "`n" `
    + $signedIP + "`n" `
    + $signedProtocol + "`n" `
    + $signedVersion + "`n"

write-host "signature string:`n$($signatureString)" -ForegroundColor Yellow

$encodedSignatureString = [text.encoding]::UTF8.GetBytes($signatureString)
write-host "utf8 encoded signature string bytes[]:`n$encodedSignatureString" -ForegroundColor Green

$hmacsha = New-Object System.Security.Cryptography.HMACSHA256
$hmacsha.key = [Convert]::FromBase64String($accessKey)
$signature = $hmacsha.ComputeHash($encodedSignatureString)

$signature = [Convert]::ToBase64String($signature)
$signature = [uri]::EscapeDataString($signature)

write-host "signature:`n$signature" -ForegroundColor Magenta

$sasUri = $storageResourceUri `
    + '?sv=' + $signedVersion `
    + '&ss=' + $signedServices `
    + '&srt=' + $signedResourceTypes `
    + '&sp=' + $signedPermission `
    + '&st=' + $signedStart `
    + '&se=' + $signedExpiry `
    + '&sip=' + $signedIP `
    + '&spr=' + $signedProtocol `
    + '&sig=' + $signature

write-host "setting new sas uri into clipboard"
Set-Clipboard -Value $sasUri
write-host 'setting new sas uri into global variable $global:sasUri'
$global:sasUri = $sasUri
write-host "new sas uri:`n$($sasUri)" -ForegroundColor Cyan
