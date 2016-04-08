

<#  
.SYNOPSIS  
    powershell script to eventlog entries
.DESCRIPTION  
    powershell script to eventlog entries. arguments are inside script
.NOTES  
   
.EXAMPLE  
    .\printer-map.ps1 -install $true
    .\printer-map.ps1 -uninstall $true
    
.PARAMETER install
    will install event log source PSPrinterMapper for this script for the Application event log. this needs to be done once per server.
.PARAMETER uninstall
    will uninstall event log source PSPrinterMapper for this script for the Application event log. this needs to be done once per server.
#>  


Param(
 
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to install event log monitor")]
    [bool] $install = $false,
    [parameter(Position=0,Mandatory=$false,HelpMessage="Enter `$true to uninstall event log monitor")]
    [bool] $uninstall = $false
    )


$ErrorActionPreference = "SilentlyContinue"
$Error.Clear()
$eventData = new-object System.Text.StringBuilder
$eventID = 1116
$eventSource = "Microsoft Antimalware"
$entryType = "Warning"
$eventLog = "System"

# -----------------------------------------------------------------------
function main()
{
    if($install)
    {
        new-eventLog -LogName "Application" -source $eventSource
        write-event "Installed $($eventSource) event log source"
        return
    }

    if($uninstall)
    {
        write-event "Removed $($eventSource) event log source"
        remove-eventLog -source $eventSource
        return
    }

    #build-event "---------------------------------------------------------------------------"
    
    #build-event "---------------------------------------------------------------------------"

    $testData = '<?xml version="1.0" encoding="utf-8"?>
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event" xml:lang="en-US">
  <System>
    <Provider Name="Microsoft Antimalware" />
    <EventID Qualifiers="0">1116</EventID>
    <Level>3</Level>
    <Task>0</Task>
    <Keywords>0x80000000000000</Keywords>
    <TimeCreated SystemTime="2015-07-02T19:42:44.000000000Z" />
    <EventRecordID>662111</EventRecordID>
    <Channel>System</Channel>
    <Computer>CO1-JUMP-MGR1.JUMP.local</Computer>
    <Security />
  </System>
  <EventData>
    <Data>%%860</Data>
    <Data>4.7.0209.0</Data>
    <Data>{EDDB363B-F881-4D14-B31B-CCAB566AD9C9}</Data>
    <Data>2015-07-02T19:42:40.881Z</Data>
    <Data />
    <Data />
    <Data>2147519003</Data>
    <Data>Virus:DOS/EICAR_Test_File</Data>
    <Data>5</Data>
    <Data>Severe</Data>
    <Data>42</Data>
    <Data>Virus</Data>
    <Data>http://go.microsoft.com/fwlink/?linkid=37020&amp;name=Virus:DOS/EICAR_Test_File&amp;threatid=2147519003</Data>
    <Data>1</Data>
    <Data />
    <Data>1</Data>
    <Data>3</Data>
    <Data>%%818</Data>
    <Data>C:\Windows\System32\notepad.exe</Data>
    <Data>JUMP\Jayowens</Data>
    <Data />
    <Data>file:_C:\Users\jayowens\Documents\eicar.txt</Data>
    <Data>1</Data>
    <Data>%%845</Data>
    <Data>1</Data>
    <Data>%%813</Data>
    <Data>0</Data>
    <Data>%%822</Data>
    <Data>0</Data>
    <Data>9</Data>
    <Data>%%887</Data>
    <Data />
    <Data>0x00000000</Data>
    <Data>The operation completed successfully. </Data>
    <Data />
    <Data>0</Data>
    <Data>0</Data>
    <Data>No additional actions required</Data>
    <Data />
    <Data />
    <Data>AV: 1.201.552.0, AS: 1.201.552.0, NIS: 115.2.0.0</Data>
    <Data>AM: 1.1.11804.0, NIS: 2.1.11804.0</Data>
  </EventData>
  <RenderingInfo Culture="en-US">
    <Message>Microsoft Antimalware has detected malware or other potentially unwanted software.
 For more information please see the following:
http://go.microsoft.com/fwlink/?linkid=37020&amp;name=Virus:DOS/EICAR_Test_File&amp;threatid=2147519003
Name: Virus:DOS/EICAR_Test_File
ID: 2147519003
Severity: Severe
Category: Virus
Path: file:_C:\Users\jayowens\Documents\eicar.txt
Detection Origin: Local machine
Detection Type: Concrete
Detection Source: Real-Time Protection
User: JUMP\Jayowens
Process Name: C:\Windows\System32\notepad.exe
Signature Version: AV: 1.201.552.0, AS: 1.201.552.0, NIS: 115.2.0.0
Engine Version: AM: 1.1.11804.0, NIS: 2.1.11804.0</Message>
    <Level>Warning</Level>
    <Task />
    <Opcode>Info</Opcode>
    <Channel />
    <Provider />
    <Keywords>
      <Keyword>Classic</Keyword>
    </Keywords>
  </RenderingInfo>
</Event>
'
    
    #write-event $eventData
    write-event $testData
}

# -----------------------------------------------------------------------
function build-event($data)
{
    $data = "$((get-date).ToString('hh:mm:ss.ffffff')):$($data)"
    #Write-Host $data
    $eventData.AppendLine($data)
}

# -----------------------------------------------------------------------
function write-event($data)
{
    #out-file -InputObject $data -FilePath c:\temp\ps.log -Append -Encoding Ascii 
    Write-EventLog -LogName $eventLog -Source $eventSource -Message $data -EventId $eventID -EntryType $entryType 
}
# -----------------------------------------------------------------------

main 

