# start "powershell.exe" -ArgumentList "-NoExit -file C:\temp\Untitled3.ps1"

param(
    $path = (get-location).path
)

$code = @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Drawing;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;

public class Example
{
    public static class directoryInfo
    {
        public string directory;
        public Int32 size;
        public Int32 totalSize;
    }

    public static List<directoryInfo> directories = new List<directoryInfo>();

    public static void Start(string path)
    {
        ParallelJob(path);
        Console.WriteLine("Processing complete.");
        return;
    }

    private static void ParallelJob(string path)
    {
        // A simple source for demonstration purposes. Modify this path as necessary.
        //String[] directories = System.IO.Directory.GetDirectories(path, "*.*", SearchOption.AllDirectories);

        AddDirectories(path, directories);
        foreach(string directory in directories)
        {
            Console.WriteLine(directory);
        }

        Parallel.ForEach(directories, (currentDirectory) => 
                                {
                                    Console.WriteLine("Processing {0} on thread {1}", currentDirectory, Thread.CurrentThread.ManagedThreadId);
                                    // Make a reference to a directory.
                                    //DirectoryInfo di = new DirectoryInfo(currentDirectory);
                                    // Get a reference to each file in that directory.
                                    //FileInfo[] fiArr = di.GetFiles();
                                    // Display the names and sizes of the files.
                                    //Console.WriteLine("The directory {0} contains the following files:", di.Name);
                                    //foreach (FileInfo f in fiArr)
                                    //{
                                    //    Console.WriteLine("The size of {0} is {1} bytes.", f.Name, f.Length);
                                    //}
                                    
                                    AddFiles
                                });

        // Keep the console window open in debug mode.

    }

    private static void AddFiles(string path, List<string> files)
    {
        Debug.WriteLine("checking " + path);

        try
        {
            Directory.GetFiles(path)
                .ToList()
                .Sum(s => files.Add(s.Length));

            //Directory.GetDirectories(path)
            //    .ToList()
            //    .ForEach(s => {files.Add(s); AddFiles(s, files);});
        }
        catch (Exception ex)
        {
            // ok, so we are not allowed to dig into that directory. Move on.
            Debug.WriteLine("exception: " + ex.ToString());
        }
    }

    private static void AddDirectories(string path, List<string> files)
    {
        Debug.WriteLine("checking " + path);

        try
        {
            //Directory.GetFiles(path)
            //    .ToList()
            //    .ForEach(s => files.Add(s));

            Directory.GetDirectories(path)
                .ToList()
                .ForEach(s => {files.Add(s); AddDirectories(s, files);});
        }
        catch (Exception ex)
        {
            // ok, so we are not allowed to dig into that directory. Move on.
            Debug.WriteLine("exception: " + ex.ToString());
        }
    }
}
'@

Add-Type $code
[Example]::Start($path)