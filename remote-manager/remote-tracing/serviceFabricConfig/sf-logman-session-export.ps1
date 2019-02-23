logman
logman -ets


<#
PS C:\temp\powershellScripts> logman
logman -ets

Data Collector Set                      Type                          Status
-------------------------------------------------------------------------------
FabricCounters                          Counter                       Running 
GAEvents                                Trace                         Running 
RTEvents                                Trace                         Running 
Server Manager Performance Monitor      Counter                       Stopped 

The command completed successfully.

Data Collector Set                      Type                          Status
-------------------------------------------------------------------------------
AppModel                                Trace                         Running 
Audio                                   Trace                         Running 
WindowsAzure-GuestAgent-Metrics         Trace                         Running 
DiagLog                                 Trace                         Running 
EventLog-Application                    Trace                         Running 
EventLog-System                         Trace                         Running 
Mellanox-Kernel                         Trace                         Running 
NtfsLog                                 Trace                         Running 
UAL_Usermode_Provider                   Trace                         Running 
UBPM                                    Trace                         Running 
WdiContextLog                           Trace                         Running 
MSDTC_TRACE_SESSION                     Trace                         Running 
MpWppTracing-02232019-135415-00000003-ffffffff Trace                         Running 
Diagtrack-Listener                      Trace                         Running 
WindowsAzure-GuestAgent-Status          Trace                         Running 
WindowsAzure-GuestAgent-Diagnostic      Trace                         Running 
MA_ETWSESSION_WAD_af02932e_5f54_44d8_aa81_7b7a098b1824_IaaS__nt0_0 Trace                         Running 
FabricTraces                            Trace                         Running 
FabricLeaseLayerTraces                  Trace                         Running 
FabricSFBDMiniportTraces                Trace                         Running 
FabricAppInfoTraces                     Trace                         Running 
FabricQueryTraces                       Trace                         Running 
FabricOperationalTraces                 Trace                         Running 
UAL_Kernelmode_Provider                 Trace                         Running 
#>

logman export -n FabricTraces -xml FabricTraces.xml -ets
logman export -n FabricLeaseLayerTraces -xml FabricLeaseLayerTraces.xml -ets
logman export -n FabricSFBDMiniportTraces -xml FabricSFBDMiniportTraces.xml -ets
logman export -n FabricAppInfoTraces -xml FabricAppInfoTraces.xml -ets
logman export -n FabricQueryTraces -xml FabricQueryTraces.xml -ets
logman export -n FabricOperationalTraces -xml FabricOperationalTraces.xml -ets
logman export -n FabricCounters -xml FabricCounters.xml -ets







