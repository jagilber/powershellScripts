<#
    To download and execute:
    [net.servicePointManager]::Expect100Continue = $true;
    [net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr "https://raw.githubusercontent.com/jagilber/powershellScripts/master/temp/desktop-heap.ps1" -outFile "$pwd\desktop-heap.ps1";.\desktop-heap.ps1
#>
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems"

$Name = "Windows"

# The critical bit is:
#
# SharedSection=1024,20480,768
# The first number (1024) is the system heap size.
# The second number (20480) is the size for interactive sessions. 
# The third number (768) is the size of non-interactive (services) sessions. Note how the third number is 26x smaller than the second. 
#    Changing this to: SharedSection=1024,20480,2048
#    Increased the limit of background service processes running from 113 to 270, almost perfectly scaling with the heap size. 
#    Pick a value that reflects the maximum number of service processes that you expect to be deployed on the system. 
#    Do not make this value larger than necessary, and no larger than 8192, as each service in your system will consume more of a precious resource.
#

$value = "%SystemRoot%\system32\csrss.exe ObjectDirectory=\Windows SharedSection=1024,20480,2048 Windows=On SubSystemType=Windows ServerDll=basesrv,1 ServerDll=winsrv:UserServerDllInitialization,3 ServerDll=sxssrv,4 ProfileControl=Off MaxRequestThreads=16"

if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType ExpandString -Force | Out-Null
}
else {
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType ExpandString -Force | Out-Null
}

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems"