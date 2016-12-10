<#
.SYNOPSIS  
    powershell script to query rds/rdv deployment for virtualization hosts and vdi machines
    
.DESCRIPTION  
    powershell script to query rds/rdv deployment for virtualization hosts and vdi machines
    machines that are running will be queried for rdp port, process list, qwinsta, network and share connectivity

.NOTES  
   Author     : jagilber
   Version    : 161209 
   History    : 
                161208.5 added background jobs to speed up vm querying
.EXAMPLE  
    .\rdv-vdi-query.ps1
    query for connection broker, hosts, and desktops, and run script. slow

.EXAMPLE  
    .\rdv-vdi-query.ps1 -activeBroker broker01
    query specific connection broker, query for hosts, and desktops, and run script. slow

.EXAMPLE  
    .\rdv-vdi-query.ps1 -activeBroker broker01 -desktopsFile c:\temp\desktops.txt -virtualizationHostsFile c:\temp\hosts.txt
    query specific connection broker, specific hosts, specific desktops, and run script. fast.

.EXAMPLE  
    .\rdv-vdi-query.ps1 -activeBroker broker01 -desktopsFile c:\temp\desktops.txt -virtualizationHostsFile c:\temp\hosts.txt -generatefiles
    query specific connection broker, for specific hosts, for specific desktops, write to specified files, and run script. slow.

.EXAMPLE  
    .\rdv-vdi-query.ps1 -update
    check github for updated script file.
 
.PARAMETER activeBroker
    optional parameter to specify active connection broker

.PARAMETER desktopsFile
    optional parameter to specify file containing names of vdi desktops to be queried.
    if blank and used with -update, it will be used as file for complete vdi list from deployment.

.PARAMETER virtualizationhostsFile
    optional parameter to specify file containing names of virtualization hosts to be queried.
    if blank and used with -update, it will be used as file for complete virtualizationhosts list from deployment.

.PARAMETER generateFiles
    optional parameter to be used with desktopsfile and virtualizationhostsFile to generate new files from deployment. slow

.PARAMETER update
    optional parameter to check for new version of this script.
#>

param(
[Parameter(Mandatory=$false)]
[string]$activeBroker,
[string]$virtualizationHostsFile,
[string]$desktopsFile,
[switch]$generateFiles,
[switch]$update
)

Set-StrictMode -Version "Latest"
$ErrorActionPreference = "SilentlyContinue"
$global:desktops = @{}
$global:virtualizationHosts = @{}
$outFile = "rdv-vdi-query.txt"
$error.clear()
$updateUrl = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/PowerShellProject/PowerShellProject/rdv-vdi-query.ps1"
$jobName = "vdiquery"
$jobThrottle = 20


#----------------------------------------------------------------------------
function main()
{
    Start-Transcript -Path $outFile -Append
    write-host "----------------------------------------"
    write-host "$(get-date) starting"
    
    get-workingDirectory
    
    if(!(Import-Module RemoteDesktop))
    {
        write-host "error: remotedesktop ps module not available. returning" -ForegroundColor Red
        return
    }

    # clean old jobs
    get-job -name $jobName | remove-job -force

    if($update)
    {
        if((git-update -updateUrl $updateUrl -destinationFile $MyInvocation.ScriptName))
        {
            write-host "script updated. restart"
            return
        }
        else
        {
            write-host "no update. continuing"
        }
    }

    # check broker
    if([string]::IsNullOrEmpty($activeBroker))
    {
        if(($availability = Get-RDConnectionBrokerHighAvailability))
        {
            $activeBroker = $availability.ActiveManagementServer
        }

        if([string]::IsNullOrEmpty($activeBroker))
        {
            if((Get-RDServer).roles -eq "RDS-CONNECTION-BROKER") 
            {
                $activeBroker = @((Get-RDServer | ? Roles -eq "RDS-CONNECTION-BROKER").Server)[0]
            }
            else
            {
                write-host "pass active connection broker name as argument for script. returning"
                return
            }
        }
    }

    write-host "$(get-date) using active broker: $($activeBroker)"

    if(!$generateFiles -and
        ![string]::IsNullOrEmpty($desktopsFile) -and 
        (test-path $desktopsFile) -and 
        ![string]::IsNullOrEmpty($virtualiazationHostsFile) -and 
        (test-path $virtualizationHostsFile))
    {
        write-host "will use files"
    }
    else
    {
        write-host "querying deployment. this make take a while ... use -virtualizationhostsFile and -desktopsFile arguments with file names to process faster"
        $desktopCollections = Get-RDVirtualDesktopCollection -ConnectionBroker $activeBroker
    }


    write-host "$(get-date) checking virtualization"
    if(![string]::IsNullOrEmpty($virtualizationHostsFile) -and (test-path $virtualizationHostsFile))
    {
        # read from file
        foreach($virtualizationhost in (Get-Content $virtualizationHostsFile))
        {
            if(!$global:virtualizationHosts.ContainsKey($virtualizationHost))
            {
                write-host "adding virtualization host from file $($virtualizationHost)"
                $global:virtualizationHosts.Add($virtualizationHost,@{})
            }
        }
    }
    else
    {
        # query deployment
        foreach($desktopCollection in $desktopCollections)
        {
            foreach($virtualizationHostDesktop in (Get-RDVirtualDesktop -CollectionName $desktopCollection.CollectionName -ConnectionBroker $activeBroker))
            {
                if(!$global:desktops.ContainsKey($virtualizationHostDesktop.VirtualDesktopName))
                {
                    write-host "adding Desktop $($virtualizationHostDesktop.VirtualDesktopName)"
                    $global:desktops.Add($virtualizationHostDesktop.VirtualDesktopName,@{})
                    if($generateFiles)
                    {
                        out-file -Append -InputObject $virtualizationHostDesktop.VirtualDesktopName -FilePath $desktopsFile
                    }
                }

                $virtualizationhost = $virtualizationHostDesktop.HostName
                if(!$global:virtualizationHosts.ContainsKey($virtualizationHost))
                {
                    write-host "adding virtualization host $($virtualizationHost)"
                    $global:virtualizationHosts.Add($virtualizationHost,@{})
                    
                    if($generateFiles)
                    {
                        out-file -Append -InputObject $virtualizationHost -FilePath $virtualizationHostsFile
                    }

                }
            }
        }
    }

    write-host "$(get-date) checking desktop"
    if(![string]::IsNullOrEmpty($desktopsFile) -and (test-path $desktopsFile))
    {
        $global:desktops = @{}
        foreach($desktop  in (Get-Content $desktopsFile))
        {
            if(!$global:desktops.ContainsKey($desktop))
            {
                write-host "adding desktop from file $($desktop)"
                $global:desktops.Add($desktop,@{})
            }
        }
    }

    write-host "$(get-date) querying virtualization hosts"
    foreach($vhost in $global:virtualizationHosts.GetEnumerator())
    {
        $vhost.Value.Available = (Test-NetConnection -ComputerName $vhost.Name -Port 135).TcpTestSucceeded
        if($vhost.Value.Available)
        {
            $vhost.Value.Vms = get-vm -ComputerName $vhost.Name
        }
        else
        {
            write-host "error: vhost not available $($vhost.Name)" -ForegroundColor Red
            continue
        }
        
        write-host "querying desktops on host $($vhost.Name)"
        foreach($vm in $vhost.Value.VMs)
        {
            write-host "checking vm $($vm.Name)"
            
            if($vm.State -eq "Running" -and $global:desktops.ContainsKey($vm.Name))
            {
                start-bgJob -vmname $vm.Name
            }
            elseif(!$global:desktops.ContainsKey($vm.Name))
            {
                write-host "information:skipping vm $($vm.Name) because it is not not part of desktops list." -ForegroundColor DarkGray
            }            
            else
            {
                write-host "warning:skipping vm $($vm.Name) because it is not in running state. state: $($vm.State)" -ForegroundColor Yellow
                continue
            }
        }
    }

    while(get-job -name $jobName)
    {
        $jobs = get-job -name $jobName 
        foreach($job in $jobs)
        {
            if($job.State -eq "Completed")
            {
                $results = $job | receive-job
                $job | remove-job -force

                if($global:desktops.ContainsKey($results.Name))
                {
                    $Global:desktops.Remove($results.Name)
                }
                
                $Global:desktops.Add($results.Name,$results)
            }

            $job
        }

        start-sleep -Seconds 1
    }

    write-host "$(get-date) exporting data"
    $global:virtualizationHosts | ConvertTo-Json -Depth 3 | out-file ("$($outFile).virtualizationhosts.txt")
    $global:desktops | ConvertTo-Json -Depth 3 | out-file ("$($outFile).desktops.txt")
    
    write-host "$(get-date) finished"
    write-host "----------------------------------------"
    write-host "log is here:$($outFile)"
    Stop-Transcript
}

#----------------------------------------------------------------------------
function start-bgJob([string]$vmname)
{
    #throttle
    if(@(get-job -Name $jobName).Count -gt 0)
    {
        while(@((get-job -Name $jobName).State -eq "Running").Count -gt $jobThrottle)
        {
            write-host "waiting for job resources..."
            start-sleep -Seconds 1    
        }
    }

    $job = start-job -Name $jobName -ScriptBlock `
    {
        param($vm)
        $desktop = @{}
        write-host "$(get-date) querying desktops"

        $desktop.Name = $vm
        $desktop.ProcessResults = $null
        $desktop.ProcessResultsError = $null
        $desktop.QwinstaResults = $null
        $desktop.QwinstaResultsError = $null
        $desktop.RDPAvailable = $false
        $desktop.RDPAvailableError = $null
        $desktop.RPCAvailable = $false
        $desktop.RPCAvailableError = $null
        $desktop.ShareResults = $false
        $desktop.ShareResultsError = $null
        
        $desktop.RPCAvailable = (Test-NetConnection -ComputerName $vm -Port 135).TcpTestSucceeded
        if($desktop.RPCAvailable)
        {
            # do additional check?                
        }
        else
        {
            write-host "error: desktop RPC not available $($vm)" -ForegroundColor Red
            $desktop.RPCAvailableError = $error
            $error.Clear()
        }

        $desktop.RDPAvailable = (Test-NetConnection -ComputerName $vm -Port 3389).TcpTestSucceeded
        if($desktop.RDPAvailable)
        {
            # do additional check?    
        }
        else
        {
            write-host "error: desktop RDP not available $($vm)" -ForegroundColor Red
            $desktop.RDPAvailableError = $error
            $error.Clear()
        }

        $desktop.QWinstaResults = Invoke-expression "qwinsta.exe /server:$($vm) /VM"
        if($desktop.QWinstaResults)
        {
            # do additional check?                
        }
        else
        {
            $desktop.QwinstaResultsError = $error
            $error.Clear()
            write-host "error: desktop qwinsta not available $($vm)" -ForegroundColor Red
        }

        $desktop.ShareResults = test-path "\\$($vm)\admin$"
        if($desktop.ShareResults)
        {
            # do additional check?
        }
        else
        {
            $desktop.ShareResultsError = $error
            $error.Clear()
            write-host "error: desktop share not available $($vm)" -ForegroundColor Red
        }

        $desktop.ProcessResults = Invoke-expression "tasklist /s $($vm) /v"
        if($desktop.ProcessResults)
        {
            # do additional check?
        }
        else
        {
            $desktop.ProcessResultsError = $error
            $error.Clear()
            write-host "error: desktop processes not available $($vm)" -ForegroundColor Red
        }
    
        $desktop
       
    } -ArgumentList $vmname

    return $job
}

#----------------------------------------------------------------------------
function git-update($updateUrl, $destinationFile)
{
    write-host "get-update:checking for updated script: $($updateUrl)"

    try 
    {
        $git = Invoke-RestMethod -Method Get -Uri $updateUrl 
        $gitClean = [regex]::Replace($git, '\W+', "")

        if(![IO.File]::Exists($destinationFile))
        {
            $fileClean = ""    
        }
        else
        {
            $fileClean = [regex]::Replace(([IO.File]::ReadAllBytes($destinationFile)), '\W+', "")
        }

        if(([string]::Compare($gitClean, $fileClean) -ne 0))
        {
            write-host "copying script $($destinationFile)"
            [IO.File]::WriteAllText($destinationFile, $git)
            return $true
        }
        else
        {
            write-host "script is up to date"
        }
        
        return $false
    }
    catch [System.Exception] 
    {
        write-host "get-update:exception: $($error)"
        $error.Clear()
        return $false    
    }
}

# ----------------------------------------------------------------------------------------------------------------
function get-workingDirectory()
{
    $retVal = [string]::Empty
 
    if (Test-Path variable:\hostinvocation)
    {
        $retVal = $hostinvocation.MyCommand.Path
    }
    else
    {
        $retVal = (get-variable myinvocation -scope script).Value.Mycommand.Definition
    }
  
    if (Test-Path $retVal)
    {
        $retVal = (Split-Path $retVal)
    }
    else
    {
        $retVal = (Get-Location).path
        write-host "get-workingDirectory: Powershell Host $($Host.name) may not be compatible with this function, the current directory $retVal will be used."
    } 
 
    Set-Location $retVal | out-null
    return $retVal
}

#----------------------------------------------------------------------------
main