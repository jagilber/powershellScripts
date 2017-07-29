<#  
.SYNOPSIS  
    powershell script to monitor hyper-v vm state changes

.DESCRIPTION  
    this script will monitor hyper-v vm state changes.
    press ctrl-c to exit.
    
    requirements: 
        at least windows 8 / 2012
        admin powershell prompt
        admin access to os
    
    remote requirements:
        powershell access

    https://raw.githubusercontent.com/jagilber/powershellScripts/master/hyperv-vm-monitor.ps1
    
.NOTES  
   File Name  : hyperv-vm-monitor.ps1
   Author     : jagilber
   Version    : 170609 original
   History    : 
                
.EXAMPLE  
    .\hyperv-vm-monitor.ps1 -hypervisors machine1,machine2
    monitor two hypervisor machines machine1 and machine2

.EXAMPLE  
    .\hyperv-vm-monitor.ps1 -hypervisors machine1,machine2 -command "powershell.exe .\somescript.ps1"
    monitor two hypervisor machines machine1 and machine2. 
    launches command powershell .\somescript.ps1 <vmname> in new window on modified vm event

.PARAMETER hypervisors
    comma separated list of hypervisor machine names

.PARAMETER command
    command to run on a modified vm event

#>  

param(
    [string]$command,
    [string[]]$hypervisors,
    [switch]$continue
)

$ErrorActionPreference = "Continue"
$currentVmStates = new-object Collections.ArrayList
$newVmStates = new-object Collections.ArrayList

if (!$hypervisors)
{
    if ((Get-WindowsFeature -Name Hyper-v).InstallState -eq "Installed")
    {
        $hypervisors = @($env:COMPUTERNAME)
    }
    else
    {
        write-host "specify -hypervisors to monitor. exiting"
        exit
    }
}

foreach ($hvm in $hypervisors)
{
    write-host "checking machine $($hvm)"
    [void]$currentVmStates.AddRange((get-vm -ComputerName $hvm | select-object Name, State, Uptime, Status, ComputerName))
    #[void]$currentVmStates.AddRange((get-vm -ComputerName $hvm | select-object Name,State,Uptime,Status,ComputerName,HardDrives))
}

$currentVmStates | Format-Table
$count = 0

while ($true)
{
    if (!$currentVmStates)
    {
        if (!$continue)
        {
            Write-Warning "unable to query current vm states. exiting"
            exit
        }
        
        Write-Warning "unable to query current vm states."
    }

    foreach ($hvm in $hypervisors)
    {
        write-verbose "checking machine $($hvm)"
        [void]$newVmStates.AddRange((get-vm -ComputerName $hvm | select-object Name, State, Uptime, Status, ComputerName))
        #[void]$newVmStates.AddRange((get-vm -ComputerName $hvm | select-object Name,State,Uptime,Status,ComputerName,HardDrives))
    }

    foreach ($currentVmState in $currentVmStates)
    {
        if (!$newVmStates.Name.Contains($currentVmState.Name))
        {
            write-host
            write-host "$((get-date).ToString("o")) removed vm $($currentVmState.Name)" -ForegroundColor Red
            $currentVmState | Format-Table *
        }
    }

    foreach ($newVmState in $newVmStates)
    {
        if (!$currentVmStates.Name.Contains($newVmState.Name))
        {
            write-host
            write-host "$((get-date).ToString("o")) new vm $($newVmState.Name)" -ForegroundColor Green
            $newVmState | Format-Table *
        }
        else
        {
            $currentVm = $currentVmStates | where-object Name -eq $newVmState.Name

            if (($currentVm.state -ne $newVmState.state) `
                    -or ($currentVm.Uptime -gt $newVmState.Uptime) `
                    -or ($currentVm.ComputerName -ne $newVmState.ComputerName) `
                    -or ($currentVm.Status -ne $newVmState.Status)) #`
            #-or ($currentVm.HardDrives.Count -ne $newVmState.HardDrives.Count)) 
            {
                write-host
                write-host "$((get-date).ToString("o")) modified vm $($newVmState.Name)" -ForegroundColor Yellow
                write-host "vvvv old state vvvv" -ForegroundColor Gray
                $currentVm | ft *
                #$currentVm.HardDrives.Path | ft *
                
                write-host "vvvv new state vvvv" -ForegroundColor Green
                $newVmState | ft *
                #$newVmState.HardDrives.Path | ft *

                if ($command -and ($newVmState.State -eq "Running") -and ($newVmState.Status -eq "Operating normally"))
                {
                    write-host "running command: cmd.exe /c start $($command) $($newVmState.Name)"
                    #Invoke-expression -Command "cmd.exe /c start $($command) $($newVmState.Name)"
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c start $($command) $($newVmState.Name) $($newVmState.ComputerName)"
                }
            }
        }
    }

    $currentVmStates.Clear()
    $currentVmStates.AddRange($newVmStates)
    $newVmStates.Clear()

    if ($count -eq 80)
    {
        $count = 0
        write-host "."
    }
    else
    {
        write-host "." -NoNewline
        $count++
    }

    Start-Sleep -Seconds 1
}

