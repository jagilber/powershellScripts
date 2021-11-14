<#
.SYNOPSIS 
script to test linux node with service fabric rest using certificate

.LINK
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/linux-sf-rest" -outFile "$pwd/linux-sf-rest.ps1";

# https://stackoverflow.com/questions/50694429/curl-with-client-certificate-authentication
# sudo snap install powershell --classic
# cert dir /var/lib/sfcerts
# thumbprint.pem, crt,key,pfx,prv
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-api-reportapplicationhealth
# POST  /Applications/{applicationId}/$/ReportHealth?api-version=6.0&Immediate={Immediate}&timeout={timeout}
#
# https://docs.microsoft.com/en-us/rest/api/servicefabric/sfclient-api-getnodehealth
# GET   /Nodes/{nodeName}/$/GetHealth?api-version=6.0&EventsHealthStateFilter={EventsHealthStateFilter}&timeout={timeout}
#>
param(
    $thumbprint = '',
    $crtFile = "/var/lib/sfcerts/$thumbprint.crt",
    $keyFile = "/var/lib/sfcerts/$thumbprint.pem",
    $password = "",
    $baseuri = 'https://localhost:19080',
    $api = 'api-version=6.4&timeout=1200'
)
#write-host "curl -v --cert $crtFile --key $keyFile --pass $password $uri"
#curl -v --cert $crtFile --key $keyFile --pass $password $uri
if (!(test-path $crtFile)) {
    Write-Error "crt file does not exist:$crtFile"
}
if (!(test-path $keyFile)) {
    Write-Error "key file does not exist:$keyFile"
}
function curl-command($uri) {
    if ($baseuri.startswith('http:')) {
        write-host "sudo curl -v $($baseuri)/$($uri)?$($api)" -ForegroundColor Cyan
        $result = sudo curl -v "$($baseuri)/$($uri)?$($api)"
    }
    else {
        $pass = $null
        if($password){
            $pass = " --pass $password"
        }
        write-host "sudo curl --insecure -v --cert $crtFile --key $keyFile$pass $($baseuri)/$($uri)?$($api)"  -ForegroundColor Green
        $result = sudo curl --insecure -v --cert $crtFile --key $keyFile$pass "$($baseuri)/$($uri)?$($api)"
    }
    write-host "result:`r`n$result"
}
curl-command ''
curl-command '$/GetClusterManifest'
curl-command 'Nodes'
