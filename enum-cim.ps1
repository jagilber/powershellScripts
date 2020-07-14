<#  
.SYNOPSIS  
    script to enumerate cim at a given node matching a given class

.DESCRIPTION  
    
.NOTES  
   File Name  : enum-cim.ps1  
   Author     : jagilber
   Version    : 160612

.EXAMPLE  
    .\enum-cim.ps1 -namespace root\cimv2 -class Win32_TS
    
.PARAMETER namespace
    provide cim namespace where to start enumeration. example root\cimv2

.PARAMETER class
    provide cim class or partial class to enumerate. ex Win32_TS

#>  
Param(
    [parameter(Mandatory = $false, HelpMessage = "Enter the namespace. ex: root\cimv2")]
    [string] $nameSpace = "root\cimv2\TerminalServices",
    [parameter(Mandatory = $false, HelpMessage = "Enter string class filter. ex: Win32_Drive")]
    [string] $classFilter = ""
)

$ErrorActionPreference = "silentlycontinue"
$logFile = "cim-enumLog.txt"

cls

#-----------------------------------------------------------------------------------------------
function main() {
    Stop-Transcript

    $error.Clear()
        
    Start-Transcript -Path $logfile
    log-info "*******************************************"
    log-info "*******************************************"
    log-info "starting"
    log-info "*******************************************"
    log-info "*******************************************"

    "*******************************************"
    "Class:$($cimNamespace)\$($cimClass.CimClassName)"
    "*******************************************"
    $cimObj = Get-CimInstance -Namespace $namespace -Class $classFilter
    if ($cimObj -ne $null) {
        $cimObj
        "*******************************************"
        return
    }

    $cimNamespaces = enumerate-namespaces -cimnamespace $nameSpace
    foreach ($cimNamespace in $cimNamespaces) {
        if ($cimNamespace.Contains("ms_409")) {
            continue
        }
        "*******************************************"
        "Namespace:$($cimNamespace)"
        "*******************************************"

        $cimClasses = Get-CimClass -ClassName * -Namespace $cimNamespace
        foreach ($cimClass in $cimClasses) {
            if ($cimClass.CimClassName.Contains("ms_409")) {
                continue
            }

            if (![string]::IsNullOrEmpty($classFilter) -and !$cimClass.CimClassName.ToLower().Contains($classFilter)) {
                continue
            }
           
            if ($cimClass.CimClassMethods.Count -gt 0) {
                "*******************************************"
                "Class:$($cimNamespace)\$($cimClass.CimClassName) Methods"
                "*******************************************"
                foreach ($method in $cimClass.CimClassMethods) {
                    $method | fl *
                    #log-info $method
                }

                "*******************************************"
            }

            if ($cimClass.CimClassName.StartsWith("__") -or $cimClass.CimClassName.StartsWith("CIM")) {
                continue
            }
            else {
                "*******************************************"
                "Class:$($cimNamespace)\$($cimClass.CimClassName)"
                "*******************************************"
                $cimObj = Get-CimInstance -Namespace $cimNamespace -Class $cimClass.CimClassName #-Recurse #-ErrorAction SilentlyContinue
                if ($cimObj -ne $null) {
                    #log-info "Value:`t`t$($cimObj)"
                    #"`t`t$($cimObj)"
                    $cimObj#.Properties | fl *
                    "*******************************************"
                }
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

function enumerate-namespaces($cimNamespace) {
    $cimRootNamespaces = new-object Collections.ArrayList
    [void]$cimRootNamespaces.Add($cimNamespace)

    foreach ($name in (Get-CimInstance -Namespace $cimNamespace -Class __NAMESPACE).Name) {
        $tempName = "$($cimNamespace)\$($name)"
        [void]$cimRootNamespaces.AddRange(@(enumerate-namespaces -cimnamespace $tempName ))
    }

    return $cimRootNamespaces
}
#-----------------------------------------------------------------------------------------------

function log-info($data) {
    $data = "$([System.DateTime]::Now):$($data)`n"
    $data 
    #out-file -Append -InputObject $data -FilePath $logFile
}
#-----------------------------------------------------------------------------------------------

main 

