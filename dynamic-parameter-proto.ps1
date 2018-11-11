#dynamic parameter example
#https://stackoverflow.com/questions/49819811/dynamic-parameters-with-dynamic-validateset
# https://martin77s.wordpress.com/2014/06/09/dynamic-validateset-in-a-dynamic-parameter/


[CmdletBinding()]
Param(
    # Any other parameters can go here
    #[parameter(DontShow)]
    #$resourceGroupNames,
    #[parameter(DontShow)]
    #$vms

    #[string[]]$resourceGroups 
)

$cacheLifeMin = 10
if(!$global:dynamicParameters -or
((get-date) - $Global:dynamicParameters.Item("lastenum")).totalminutes -gt $cacheLifeMin)
{
    $global:dynamicParameters = @{} 
    $global:dynamicParameters.Add("lastenum",(get-date))
    $global:dynamicParameters.Add("resources",(Get-AzureRmResource))
}

$resources = $global:dynamicParameters.Item("resources")
$RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

out-file -Append -encoding ascii -FilePath c:\temp\ps.log -InputObject "has rgs pscmdlet: $($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('resourceGroupNames'))"
foreach($ParameterName in @('resourceGroupNames','excluderesourceGroupNames'))
{
    if(!$global:dynamicParameters.ContainsKey($ParameterName))
    {
        out-file -Append -encoding ascii -FilePath c:\temp\ps.log -InputObject "has rgs"
        $AttributeCollection = New-Object Collections.ObjectModel.Collection[Attribute]
        $ParameterAttribute = New-Object Management.Automation.ParameterAttribute
        # $ParameterAttribute.Mandatory = $true
        $ParameterAttribute.Position = 0    
        $AttributeCollection.Add($ParameterAttribute)
    
        $arrSet = ($resources | Select-Object -unique ResourceGroupName).resourcegroupname
        $ValidateSetAttribute = New-Object Management.Automation.ValidateSetAttribute($arrSet)
        $AttributeCollection.Add($ValidateSetAttribute)
    
        $RuntimeParameter = New-Object Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
        $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
        $global:dynamicParameters.Add($ParameterName, $RuntimeParameter)
    }
    else 
    {
        $RuntimeParameterDictionary.Add($ParameterName,$Global:dynamicParameters.Item($ParameterName))
    }
}

out-file -Append -encoding ascii -FilePath c:\temp\ps.log -InputObject "has vms pscmdlet: $($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('vms'))"
foreach($ParameterName in @('vms','excludevms'))
{
    if(!$global:dynamicParameters.ContainsKey($ParameterName))
    {
        out-file -Append -encoding ascii -FilePath c:\temp\ps.log -InputObject "has vms"
        $AttributeCollection = New-Object Collections.ObjectModel.Collection[Attribute]
        $ParameterAttribute = New-Object Management.Automation.ParameterAttribute
        #$ParameterAttribute.Mandatory = $true
        $ParameterAttribute.Position = 0
        $AttributeCollection.Add($ParameterAttribute)
    
        $arrSet = ($resources | where-object ResourceType -eq Microsoft.Compute/virtualMachines).Name
        $ValidateSetAttribute = New-Object Management.Automation.ValidateSetAttribute($arrSet)
        $AttributeCollection.Add($ValidateSetAttribute)

        $RuntimeParameter = New-Object Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
        $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
        $global:dynamicParameters.Add($ParameterName, $RuntimeParameter)
    }
    else 
    {
        $RuntimeParameterDictionary.Add($ParameterName,$Global:dynamicParameters.Item($ParameterName))
    }
}

return $RuntimeParameterDictionary
}

begin
{
    $ErrorActionPreference = "continue"
    if($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('resourceGroupNames'))
    {
        [string[]]$resourceGroupNames = $PSCmdlet.MyInvocation.BoundParameters['resourceGroupNames']
    }

    if($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('vms'))
    {
        [string[]]$vms = $PSCmdlet.MyInvocation.BoundParameters['vms']
    }

    if($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('excludeResourceGroupNames'))
    {
        [string[]]$excludeResourceGroupNames = $PSCmdlet.MyInvocation.BoundParameters['excludeResourceGroupNames']
    }

    if($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('excludeVms'))
    {
        [string[]]$excludeVms = $PSCmdlet.MyInvocation.BoundParameters['excludeVms']
    }
}


process
{
    # Your code goes here
    #dir -Path $Path
    #Get-AzureRmResourceGroup
    Write-Host "hello world"
}


