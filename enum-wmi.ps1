<#  
.SYNOPSIS  
    script to enumerate WMI at a given node matching a given class

.DESCRIPTION  
    
.NOTES  
   File Name  : enum-wmi.ps1  
   Author     : jagilber
   Version    : 160612
                
   History    :  160414 original

.EXAMPLE  
    .\enum-wmi.ps1 -namespace root\cimv2 -class Win32_TS
    
.PARAMETER namespace
    provide wmi namespace where to start enumeration. example root\cimv2

.PARAMETER class
    provide wmi class or partial class to enumerate. ex Win32_TS

#>  
Param(
 
    [parameter(Mandatory=$false,HelpMessage="Enter the namespace. ex: root\cimv2")]
    [string] $nameSpace = "root\cimv2\TerminalServices",
    [parameter(Mandatory=$false,HelpMessage="Enter string class filter. ex: Win32_Drive")]
    [string] $classFilter = ""
    )

$ErrorActionPreference = "silentlycontinue"
$logFile = "wmi-enumLog.txt"

cls
 
#-----------------------------------------------------------------------------------------------
function main()
{
    Stop-Transcript
 
    $error.Clear()
        
    Start-Transcript -Path $logfile
    log-info "*******************************************"
    log-info "*******************************************"
    log-info "starting"
    log-info "*******************************************"
    log-info "*******************************************"
 
    $wmiNamespaces = enumerate-namespaces -wminamespace $nameSpace
    foreach($wmiNamespace in $wmiNamespaces)
    {
        if($wmiNamespace.Contains("ms_409"))
        {
            continue
        }
        "*******************************************"
        "Namespace:$($wmiNamespace)"
        "*******************************************"
 
        $wmiClasses = Get-CimClass -ClassName * -Namespace $wmiNamespace
        
        foreach ($wmiClass in $wmiClasses)
        {
            if($wmiClass.CimClassName.Contains("ms_409"))
            {
               continue
            }

            if(![string]::IsNullOrEmpty($classFilter) -and !$wmiClass.CimClassName.ToLower().Contains($classFilter))
            {
               continue
            }
           
            if($wmiClass.CimClassMethods.Count -gt 0)
            {
                "*******************************************"
                "Class:$($wmiNamespace)\$($wmiClass.CimClassName) Methods"
                "*******************************************"
                foreach($method in $wmiClass.CimClassMethods)
                {
                    $method | fl *
                    #log-info $method
                }

                "*******************************************"
            }

            if($wmiClass.CimClassName.StartsWith("__") -or $wmiClass.CimClassName.StartsWith("CIM"))
            {
               continue
            }
            else
            {
                "*******************************************"
                "Class:$($wmiNamespace)\$($wmiClass.CimClassName)"
                "*******************************************"
                $wmiObj = Get-WmiObject -Namespace $wmiNamespace -Class $wmiClass.CimClassName -Recurse #-ErrorAction SilentlyContinue
                if($wmiObj -ne $null)
                {
                    #log-info "Value:`t`t$($wmiObj)"
                    #"`t`t$($wmiObj)"
                    $wmiObj#.Properties | fl *
                    "*******************************************"
                }
                #log-info
                #write-host $wmiObj
            }
            
        }
    }
 
    "*******************************************"
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
        [void]$wmiRootNamespaces.AddRange(@(enumerate-namespaces -wminamespace $tempName ))
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
