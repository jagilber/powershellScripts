<#
.SYNOPSIS 
script to enable remote debugging 
#>
[cmdletbinding()]
param(
    $resourceGroup = 'sfjagilber1nt3'
)

$ErrorActionPreference = 'continue'

function main(){
    
    $rg = get-azresourcegroup $resourceGroup
}

main