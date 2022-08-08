<#
test sf aad scripts
place in clouddrive dir in shell.azure.com

#>
param(
    $tenantId = "$((get-azcontext).tenant.id)",
    $clusterName = "",#'sfcluster',
    $location = 'eastus'
)
$errorActionPreference = 'continue'
$curDir = $pwd
$startTime = get-date
$translog = "$pwd/tran-$($startTime.tostring('yyMMddhhmmss')).log"
$replyUrl = "https://$clusterName.$location.cloudapp.azure.com:19080/Explorer/index.html" # <--- client browser redirect url

try{
    write-host "$(get-date) starting transcript $translog"
    start-transcript -path $translog
    cd ./service-fabric-aad-helpers
    # if using cloud shell
    # cd clouddrive 
    # git clone https://github.com/Azure-Samples/service-fabric-aad-helpers
    # cd service-fabric-aad-helpers
    # code .

    #$webApplicationUri = 'https://mysftestcluster.contoso.com' # <--- must be verified domain due to AAD changes
    $webApplicationUri = "api://$tenantId/$clusterName" # <--- does not have to be verified domain

    $configObj = .\SetupApplications.ps1 -TenantId $tenantId `
        -ClusterName $clusterName `
        -WebApplicationReplyUrl $replyUrl `
        -AddResourceAccess `
        -WebApplicationUri $webApplicationUri `
        -Verbose
    write-host $configObj

    .\SetupUser.ps1 -ConfigObj $configobj `
        -UserName 'TestUser' `
        -Password 'P@ssword!123' `
        -Verbose

    .\SetupUser.ps1 -ConfigObj $configobj `
        -UserName 'TestAdmin' `
        -Password 'P@ssword!123' `
        -IsAdmin `
        -Verbose
}
finally {
    write-host "$(get-date) stopping transcript $translog"
    stop-transcript
    set-location $curDir
}