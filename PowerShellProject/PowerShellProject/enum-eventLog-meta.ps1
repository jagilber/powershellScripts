<#  
.SYNOPSIS

    powershell script to enumerate all event logs and enumerate all events for that event logs. Works only with newer logs 
    and not Classic logs.

.DESCRIPTION  

    Set-ExecutionPolicy Bypass -Force

    This script will optionally enable / disable debug and analytic event logs. 
    This can be against both local and remote machines.
    It will also take a regex filter pattern for eventlog names.
    For each match, all event logs will be exported to csv format.
    Each export will be in its own file named with the event log name.
    
    ** Copyright (c) Microsoft Corporation. All rights reserved - 2015.
    **
    ** This script is not supported under any Microsoft standard support program or service.
    ** The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    ** implied warranties including, without limitation, any implied warranties of merchantability
    ** or of fitness for a particular purpose. The entire risk arising out of the use or performance
    ** of the scripts and documentation remains with you. In no event shall Microsoft, its authors,
    ** or anyone else involved in the creation, production, or delivery of the script be liable for
    ** any damages whatsoever (including, without limitation, damages for loss of business profits,
    ** business interruption, loss of business information, or other pecuniary loss) arising out of
    ** the use of or inability to use the script or documentation, even if Microsoft has been advised
    ** of the possibility of such damages.
    **
 
.NOTES  

   File Name  : enum-eventLog-meta.ps1
   Author     : jagilber
   Version    : 150822
                 
   History    : 150722 original

.EXAMPLE  
    .\enum-eventLog-meta.ps1
    
#>  


$logDir = "c:\temp\events"
$logfile = "$($logDir)\enum-eventLog-meta.log"
$eventList = @{}

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $error.Clear()
    $session = New-Object Diagnostics.Eventing.Reader.EventLogSession

    if(![IO.Directory]::Exists($logDir))
    {
        [IO.Directory]::CreateDirectory($logDir)
    }

    foreach($eventLogName in $session.GetLogNames())
    {
       
        
        log-info "checking $($eventLogName)"

        if($eventLogName.Contains("/"))
        {
            $eventLogName = $eventLogName.Remove($eventLogName.IndexOf("/"))
        }

        if(!$eventList.Contains($eventLogName))
        {
            $eventList.Add($eventLogName,"")
        }
        else
        {
            log-info "eventLog already processed. skipping"
            continue
        }


        
        $eventLogFile = "$($logDir)\$($eventLogName).log"
        $meta = $null

        $meta = New-Object Diagnostics.Eventing.Reader.ProviderMetaData ($eventLogName)    
        if($Error)
        {
            $error.Clear()
            continue
        }
        
        eventlog-info "Name:$($meta.Name)"
        eventlog-info "Id:$($meta.Id)"
        eventlog-info "MessageFilePath:$($meta.MessageFilePath)"
        eventlog-info "ResourceFilePath:$($meta.ResourceFilePath)"
        eventlog-info "HelpLink:$($meta.HelpLink)"

        eventlog-info "# ----------------------------------------------------------------------------------------------------------------"
        eventlog-info "# events"
        eventlog-info "# ----------------------------------------------------------------------------------------------------------------"
        
        foreach($event in $meta.Events)
        {

            eventlog-info "id:$($event.Id)"
            eventlog-info "version:$($event.version)"
            eventlog-info "LogLink LogName:$($event.Loglink.LogName)"
            eventlog-info "LogLink DisplayName:$($eent.Loglink.DisplayName)"

            eventlog-info "Level:$($event.Level.Value)"
            eventlog-info "Opcode:$($event.OpCode.Value)"
            eventlog-info "Task name:$($event.Task.Name)"
            eventlog-info "Task event guid:$($event.Task.eventGuid)"

            foreach($keyword in $event.keywords)
            {
                eventlog-info "Keyword name:$($keyword.Name)"
                eventlog-info "Keyword value:$($keyword.Value)"
            }

            eventlog-info "Template:$($event.Template)"
            eventlog-info "Description:$($event.Description)"
            eventlog-info "# ----------------------------------------------------------------------------------------------------------------"
        }
    }

}
# ----------------------------------------------------------------------------------------------------------------

function eventLog-info($data)
{

    $dataWritten = $false
    #Write-Host $data
            
    $counter = 0
    while(!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            out-file -Append -InputObject $data -FilePath $eventLogFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 10
            $counter++
        }
    }
}
# ----------------------------------------------------------------------------------------------------------------

function log-info($data)
{

    $dataWritten = $false
    $data = "$([System.DateTime]::Now):$($data)`n"
    Write-Host $data
            
    $counter = 0
    while(!$dataWritten -and $counter -lt 1000)
    {
        try
        {
            out-file -Append -InputObject $data -FilePath $logFile
            $dataWritten = $true
        }
        catch
        {
            Start-Sleep -Milliseconds 10
            $counter++
        }
    }
}
# ----------------------------------------------------------------------------------------------------------------

main

    