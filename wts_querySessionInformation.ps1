# From http://serverfault.com/questions/342533/wmi-object-to-get-current-sessions-with-client-name
# QuerySessionInformation.ps1
# Written by Ryan Ries, Jan. 2013, with help from MSDN and Stackoverflow.

$Code = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;
    public class RDPInfo30
    {
        [DllImport("wtsapi32.dll")]
        static extern IntPtr WTSOpenServer([MarshalAs(UnmanagedType.LPStr)] String pServerName);

        [DllImport("wtsapi32.dll")]
        static extern void WTSCloseServer(IntPtr hServer);

        [DllImport("wtsapi32.dll")]
        static extern Int32 WTSEnumerateSessions(
            IntPtr hServer,
            [MarshalAs(UnmanagedType.U4)] Int32 Reserved,
            [MarshalAs(UnmanagedType.U4)] Int32 Version,
            ref IntPtr ppSessionInfo,
            [MarshalAs(UnmanagedType.U4)] ref Int32 pCount);

        [DllImport("wtsapi32.dll")]
        static extern void WTSFreeMemory(IntPtr pMemory);

        [DllImport("Wtsapi32.dll")]
        static extern bool WTSQuerySessionInformation(System.IntPtr hServer, int sessionId, WTS_INFO_CLASS wtsInfoClass, out System.IntPtr ppBuffer, out uint pBytesReturned);

        [StructLayout(LayoutKind.Sequential)]
        private struct WTS_SESSION_INFO
        {
            public Int32 SessionID;
            [MarshalAs(UnmanagedType.LPStr)]
            public String pWinStationName;
            public WTS_CONNECTSTATE_CLASS State;
        }

        // byte type needs to be fixed
        public unsafe struct WTS_SESSION_ADDRESS {
            [MarshalAs(UnmanagedType.U4)] public Int32    AddressFamily;
            public fixed byte Address[20];
        } 



        public enum WTS_INFO_CLASS
        {
            WTSInitialProgram,
            WTSApplicationName,
            WTSWorkingDirectory,
            WTSOEMId,
            WTSSessionId,
            WTSUserName,
            WTSWinStationName,
            WTSDomainName,
            WTSConnectState,
            WTSClientBuildNumber,
            WTSClientName,
            WTSClientDirectory,
            WTSClientProductId,
            WTSClientHardwareId,
            WTSClientAddress,
            WTSClientDisplay,
            WTSClientProtocolType
        }

        public enum WTS_CONNECTSTATE_CLASS
        {
            WTSActive,
            WTSConnected,
            WTSConnectQuery,
            WTSShadow,
            WTSDisconnected,
            WTSIdle,
            WTSListen,
            WTSReset,
            WTSDown,
            WTSInit
        }

        public static IntPtr OpenServer(String Name)
        {
            IntPtr server = WTSOpenServer(Name);
            return server;
        }

        static void Main()
        {
            ListUsers("LOCALHOST");
            //Console.ReadLine();
        }

        public static void CloseServer(IntPtr ServerHandle)
        {
            WTSCloseServer(ServerHandle);
        }

        public static string ByteArrayToString(byte[] ba)
        {
            string hex = BitConverter.ToString(ba);
            return hex.Replace("-", "");
        }
        public static void ListUsers(String ServerName)
        {
            IntPtr serverHandle = IntPtr.Zero;
            List<String> resultList = new List<string>();
            serverHandle = OpenServer(ServerName);

            try
            {
                IntPtr SessionInfoPtr = IntPtr.Zero;
                IntPtr userPtr = IntPtr.Zero;
                IntPtr domainPtr = IntPtr.Zero;
                IntPtr clientNamePtr = IntPtr.Zero;
                IntPtr clientAddressPtr = IntPtr.Zero;
                Int32 sessionCount = 0;
                Int32 retVal = WTSEnumerateSessions(serverHandle, 0, 1, ref SessionInfoPtr, ref sessionCount);
                Int32 dataSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                IntPtr currentSession = SessionInfoPtr;
                uint bytes = 0;
                string addressObjStr = string.Empty;

                if (retVal != 0)
                {
                    for (int i = 0; i < sessionCount; i++)
                    {
                        WTS_SESSION_INFO si = (WTS_SESSION_INFO)Marshal.PtrToStructure((System.IntPtr)currentSession, typeof(WTS_SESSION_INFO));
                        currentSession += dataSize;

                        WTSQuerySessionInformation(serverHandle, si.SessionID, WTS_INFO_CLASS.WTSUserName, out userPtr, out bytes);
                        WTSQuerySessionInformation(serverHandle, si.SessionID, WTS_INFO_CLASS.WTSDomainName, out domainPtr, out bytes);
                        WTSQuerySessionInformation(serverHandle, si.SessionID, WTS_INFO_CLASS.WTSClientName, out clientNamePtr, out bytes);
                        WTSQuerySessionInformation(serverHandle, si.SessionID, WTS_INFO_CLASS.WTSClientAddress, out clientAddressPtr, out bytes);

                        WTS_SESSION_ADDRESS addressObj = (WTS_SESSION_ADDRESS)Marshal.PtrToStructure(clientAddressPtr, typeof(WTS_SESSION_ADDRESS));

                        byte[] bAddress = new byte[24];
                        byte[] bAddressType = new byte[4];
                        byte[] bAddressArray = new byte[20];

                        unsafe
                        {
                            // first 4 bytes are address type 
                            // bytes 4 - 24 are the ip address
                            Marshal.Copy(clientAddressPtr, bAddress, 0, 24);
                            
                        }

                        // ipv4 bytes 2,3,4,5 have the ip
                        Array.Copy(bAddress, 4, bAddressArray, 0, 20);
                        StringBuilder sbClientAddress = new StringBuilder();

                        for (int x = 2; x < 6 ; x++)
                        {
                            sbClientAddress.Append(bAddressArray[x] + ".");
                        }

                        Array.Copy(bAddress, 0, bAddressType, 0, 4);
                        StringBuilder sbClientAddressType = new StringBuilder();

                        for (int x = 0; x < 2; x++)
                        {
                            sbClientAddressType.Append(bAddressType[x]);
                        }


                        if(Marshal.PtrToStringAnsi(domainPtr).Length > 0 && Marshal.PtrToStringAnsi(userPtr).Length > 0)
                        {
                            if (Marshal.PtrToStringAnsi(clientNamePtr).Length < 1)
                            {
                                Console.WriteLine("User: " + Marshal.PtrToStringAnsi(domainPtr) + "\\" + Marshal.PtrToStringAnsi(userPtr)
                                    + "\tSessionID: " + si.SessionID
                                    + "\tClientName: n/a"
                                    + "\tClientAddressType: " + sbClientAddressType.ToString()
                                    + "\tClientAddress: " + sbClientAddress.ToString().TrimEnd('.'));
                            }
                            else
                            {
                                Console.WriteLine("User: " + Marshal.PtrToStringAnsi(domainPtr) + "\\" + Marshal.PtrToStringAnsi(userPtr)
                                    + "\tSessionID: " + si.SessionID
                                    + "\tClientName: " + Marshal.PtrToStringAnsi(clientNamePtr)
                                    + "\tClientAddressType: " + sbClientAddressType.ToString()
                                    + "\tClientAddress: " + sbClientAddress.ToString().TrimEnd('.'));
                            }
                        }
                        WTSFreeMemory(clientNamePtr);
                        WTSFreeMemory(userPtr);
                        WTSFreeMemory(domainPtr);
                        WTSFreeMemory(clientAddressPtr);
                    }
                    WTSFreeMemory(SessionInfoPtr);
                }
            }
            catch(Exception ex)
            {
                Console.WriteLine("Exception: " + ex.Message);
            }
            finally
            {
                CloseServer(serverHandle);
            }
        }
    }
'@

$comParam = new-object CodeDom.Compiler.CompilerParameters
$comParam.CompilerOptions = "/unsafe"

Add-Type $Code -CompilerParameters $comParam



[RDPInfo30]::ListUsers("localhost")
