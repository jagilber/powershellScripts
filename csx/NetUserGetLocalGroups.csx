#!/usr/bin/env dotnet-script
/*
 * NetUserGetLocalGroups C# Script (CSX)
 * Calls the Windows API NetUserGetLocalGroups function
 * 
 * Usage: dotnet script NetUserGetLocalGroups.csx [serverName] [userName] [level] [flags]
 * 
 * Parameters:
 *   serverName - The DNS or NetBIOS name of the remote server (use "." for local)
 *   userName   - The name of the user
 *   level      - Information level (0 or 1)
 *   flags      - Flags (0 = all groups, 1 = recursive groups)
 * 
 * Example:
 *   dotnet script NetUserGetLocalGroups.csx . MyUser 0 0
 */

using System;
using System.Runtime.InteropServices;
using System.Text;

// NetUserGetLocalGroups API structures and imports
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct LOCALGROUP_USERS_INFO_0
{
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lgrui0_name;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct LOCALGROUP_USERS_INFO_1
{
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lgrui1_name;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string lgrui1_comment;
}

public class NetApi32
{
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int NetUserGetLocalGroups(
        [MarshalAs(UnmanagedType.LPWStr)] string servername,
        [MarshalAs(UnmanagedType.LPWStr)] string username,
        int level,
        int flags,
        out IntPtr bufptr,
        int prefmaxlen,
        out int entriesread,
        out int totalentries);

    [DllImport("netapi32.dll", SetLastError = true)]
    public static extern int NetApiBufferFree(IntPtr Buffer);

    public const int MAX_PREFERRED_LENGTH = -1;
    public const int NERR_Success = 0;
    public const int ERROR_MORE_DATA = 234;
    public const int ERROR_ACCESS_DENIED = 5;
    public const int ERROR_INVALID_LEVEL = 124;
}

// Parse command line arguments
if (Args.Count < 2)
{
    Console.WriteLine("ERROR: Insufficient arguments");
    Console.WriteLine();
    Console.WriteLine("Usage: dotnet script NetUserGetLocalGroups.csx [serverName] [userName] [level] [flags]");
    Console.WriteLine();
    Console.WriteLine("Parameters:");
    Console.WriteLine("  serverName - The DNS or NetBIOS name of the remote server (use \".\" for local)");
    Console.WriteLine("  userName   - The name of the user");
    Console.WriteLine("  level      - Information level (0 or 1), default: 0");
    Console.WriteLine("  flags      - Flags (0 = all groups, 1 = recursive groups), default: 0");
    Console.WriteLine();
    Console.WriteLine("Example:");
    Console.WriteLine("  dotnet script NetUserGetLocalGroups.csx . MyUser 0 0");
    Environment.Exit(1);
}

string serverName = Args[0];
string userName = Args[1];
int level = Args.Count > 2 ? int.Parse(Args[2]) : 0;
int flags = Args.Count > 3 ? int.Parse(Args[3]) : 0;

// Validate level
if (level != 0 && level != 1)
{
    Console.WriteLine($"ERROR: Invalid level '{level}'. Must be 0 or 1.");
    Environment.Exit(1);
}

Console.WriteLine("=== NetUserGetLocalGroups API Call ===");
Console.WriteLine($"Server Name: {(string.IsNullOrEmpty(serverName) || serverName == "." ? "Local Computer" : serverName)}");
Console.WriteLine($"User Name:   {userName}");
Console.WriteLine($"Level:       {level}");
Console.WriteLine($"Flags:       {flags} ({(flags == 0 ? "All groups" : "Recursive groups")})");
Console.WriteLine();

// Call the API
IntPtr bufPtr = IntPtr.Zero;
int entriesRead = 0;
int totalEntries = 0;

try
{
    int result = NetApi32.NetUserGetLocalGroups(
        serverName,
        userName,
        level,
        flags,
        out bufPtr,
        NetApi32.MAX_PREFERRED_LENGTH,
        out entriesRead,
        out totalEntries);

    Console.WriteLine($"API Return Code: {result} (0x{result:X8})");
    
    if (result == NetApi32.NERR_Success)
    {
        Console.WriteLine($"Entries Read:    {entriesRead}");
        Console.WriteLine($"Total Entries:   {totalEntries}");
        Console.WriteLine();

        if (entriesRead > 0)
        {
            Console.WriteLine("Local Groups:");
            Console.WriteLine("-------------");

            if (level == 0)
            {
                int structSize = Marshal.SizeOf(typeof(LOCALGROUP_USERS_INFO_0));
                for (int i = 0; i < entriesRead; i++)
                {
                    IntPtr currentPtr = new IntPtr(bufPtr.ToInt64() + (i * structSize));
                    LOCALGROUP_USERS_INFO_0 info = Marshal.PtrToStructure<LOCALGROUP_USERS_INFO_0>(currentPtr);
                    Console.WriteLine($"  [{i + 1}] {info.lgrui0_name}");
                }
            }
            else if (level == 1)
            {
                int structSize = Marshal.SizeOf(typeof(LOCALGROUP_USERS_INFO_1));
                for (int i = 0; i < entriesRead; i++)
                {
                    IntPtr currentPtr = new IntPtr(bufPtr.ToInt64() + (i * structSize));
                    LOCALGROUP_USERS_INFO_1 info = Marshal.PtrToStructure<LOCALGROUP_USERS_INFO_1>(currentPtr);
                    Console.WriteLine($"  [{i + 1}] {info.lgrui1_name}");
                    if (!string.IsNullOrEmpty(info.lgrui1_comment))
                    {
                        Console.WriteLine($"      Comment: {info.lgrui1_comment}");
                    }
                }
            }
        }
        else
        {
            Console.WriteLine("User is not a member of any local groups.");
        }
    }
    else
    {
        // Handle error codes
        string errorMessage = result switch
        {
            NetApi32.ERROR_ACCESS_DENIED => "Access Denied (5) - Insufficient permissions",
            NetApi32.ERROR_INVALID_LEVEL => "Invalid Level (124) - Level must be 0 or 1",
            NetApi32.ERROR_MORE_DATA => "More Data (234) - Buffer too small",
            2221 => "NERR_UserNotFound - The user name could not be found",
            2236 => "NERR_InvalidComputer - The computer name is invalid",
            _ => $"Error {result} - See Win32 error codes"
        };
        
        Console.WriteLine($"ERROR: {errorMessage}");
        Environment.Exit(result);
    }
}
catch (Exception ex)
{
    Console.WriteLine($"EXCEPTION: {ex.GetType().Name}");
    Console.WriteLine($"Message: {ex.Message}");
    Console.WriteLine($"Stack Trace:\n{ex.StackTrace}");
    Environment.Exit(-1);
}
finally
{
    // Free the buffer
    if (bufPtr != IntPtr.Zero)
    {
        NetApi32.NetApiBufferFree(bufPtr);
    }
}

Console.WriteLine();
Console.WriteLine("=== Completed Successfully ===");
