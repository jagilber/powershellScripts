#$wmiObj = Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_Termin -Recurse
#root
$logFile = "wmi-enumLog.txt"
 
$rootNamespace = "root"
$rootNamespace = "root\cimv2\terminalservices"
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
 
    $wmiNamespaces = enumerate-namespaces -namespace $rootNamespace
    foreach($namespace in $wmiNamespaces)
    {
        log-info ""
        log-info "*******************************************"
        log-info "Namespace:$($namespace)"
        log-info "*******************************************"
        log-info ""
 
        $wmiClasses = Get-CimClass -ClassName * -Namespace $namespace
        
        foreach ($class in $wmiClasses)
        {
 
            if($class.CimClassName.StartsWith("__") -or $class.CimClassName.StartsWith("CIM"))
            {
                continue
            }
            else
            {
                log-info ""
                log-info "*******************************************"
                log-info "Class:$($class.CimClassName)"
                log-info "*******************************************"
                log-info ""
 
                $wmiObj = Get-WmiObject -Namespace $namespace -Class $class.CimClassName -Recurse #-ErrorAction SilentlyContinue
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
 
function enumerate-namespaces($namespace)
{
    $wmiRootNamespaces = new-object Collections.ArrayList
    [void]$wmiRootNamespaces.Add($namespace)
 
    foreach($name in (Get-WmiObject -Namespace $namespace -Class __NAMESPACE).Name)
    {
        $tempName = "$($namespace)\$($name)"
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
