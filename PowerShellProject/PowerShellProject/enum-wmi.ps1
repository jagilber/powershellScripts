<#  
.SYNOPSIS  
    script to enumerate WMI at a given node matching a given class

.DESCRIPTION  
    
.NOTES  
   File Name  : enum-wmi.ps1  
   Author     : jagilber
   Version    : 160414
                
   History    :  160414 original

.EXAMPLE  
    .\enum-wmi.ps1 -namespace root\cimv2 -class Win32_TS
    
.PARAMETER namespace
    provide wmi namespace where to start enumeration. example root\cimv2

.PARAMETER class
    provide wmi class or partial class to enumerate. ex Win32_TS

#>  
Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the namespace. ex: root\cimv2")]
    [string] $nameSpace = "root\cimv2",
    [string] $class = ""
    )
$logFile = "wmi-enumLog.txt"
$ErrorActionPreference = "silentlycontinue"
cls
 
#-----------------------------------------------------------------------------------------------
function main()
{
    Stop-Transcript
 
    
    Start-Transcript -Path $logfile
    log-info "*******************************************"
    log-info "*******************************************"
    log-info "starting"
    log-info "*******************************************"
    log-info "*******************************************"
 
    $wmiNamespaces = enumerate-namespaces -namespace $nameSpace
    foreach($wmiNamespace in $wmiNamespaces)
    {
        log-info ""
        log-info "*******************************************"
        log-info "Namespace:$($wmiNamespace)"
        log-info "*******************************************"
        log-info ""
 
        $wmiClasses = Get-CimClass -ClassName * -Namespace $wmiNamespace
        
        foreach ($wmiClass in $wmiClasses)
        {
            
            if(![string]::IsNullOrEmpty($class) -and $wmiClass.CimClassName -inotmatch $class)
            {
                continue
            }
 
            if($wmiClass.CimClassName.StartsWith("__") -or $wmiClass.CimClassName.StartsWith("CIM"))
            {
                continue
            }
            else
            {
                log-info ""
                log-info "*******************************************"
                log-info "Class:$($wmiClass.CimClassName)"
                log-info "*******************************************"
                log-info ""
 
                $wmiObj = Get-WmiObject -Namespace $wmiNamespace -Class $wmiClass.CimClassName -Recurse #-ErrorAction SilentlyContinue
                if($wmiObj -ne $null)
                {
                    #log-info "Value:`t`t$($wmiObj)"
                    #"`t`t$($wmiObj)"
                    $wmiObj
                }
                #log-info
                #write-host $wmiObj
            }
            
        }
    }
 
    log-info "*******************************************"
    log-info "*******************************************"
    log-info "finished"
    log-info "*******************************************"
    log-info "*******************************************"
    stop-Transcript
    
}
#-----------------------------------------------------------------------------------------------
 
function enumerate-namespaces($wmiNamespace)
{
    $wmiRootNamespaces = new-object Collections.ArrayList
    [void]$wmiRootNamespaces.Add($wmiNamespace)
 
    foreach($name in (Get-WmiObject -Namespace $wmiNamespace -Class __NAMESPACE).Name)
    {
        $tempName = "$($wmiNamespace)\$($name)"
        [void]$wmiRootNamespaces.AddRange(@(enumerate-namespaces($tempName)))
    }
 
    return $wmiRootNamespaces
}
#-----------------------------------------------------------------------------------------------
 
function log-info($data)
{
    $data = "$([System.DateTime]::Now):$($data)`n"
    $data 
    #out-file -Append -InputObject $data -FilePath $logFile
}
#-----------------------------------------------------------------------------------------------
 
main 
