# to connect to raspberry pi 2 windows 10 IoT# From <https://ms-iot.github.io/content/win10/samples/PowerShell.htm> # from admin machine# ip or name$machineName = "clt-jgs-IoT-1" # use ip for first boot "65.53.9.19" $newPassword = "newPassword"$newComputerName = "clt-jgs-IoT-1"# one time to enable remoting wsman / winrm# Enable-PSRemoting# one time to setup server wsman for each machine / ip# Set-Item WSMan:\localhost\Client\TrustedHosts -Value $machineName# Stack Overflow bug workaround#remove-module psreadline -force# default password  p@ssw0rdEnter-PsSession -ComputerName $machineName -Credential "$($machineName)\Administrator"# only needs to be done onceif($env:COMPUTERNAME -eq "MINWINPC"){    # net user Administrator $newPassword
    schtasks /Delete /TN Microsoft\Windows\IoT\Startup /F 
    setcomputername $newComputerName
}

# to see list of startup apps
startup /d

# to reboot
#shutdown /r /t 0

# to set to headed or headless
#setbootoption headed
#setbootoption headless