# start "powershell.exe" -ArgumentList "-NoExit -file C:\temp\Untitled3.ps1"

param(
    $path = (get-location).path
)

$code = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;

public class dotNet
{
    public class directoryInfo
    {
        public string directory;
        public Int32 size;
        public Int32 totalSize;
    }

    //public static ConcurrentBag<directoryInfo> directories = new ConcurrentBag<directoryInfo>();
    public static ConcurrentBag<directoryInfo> directories = new ConcurrentBag<directoryInfo>();

    public static void Main(string[] args)
    {
        if (args.Length > 0)
        {
            Start(args[0]);
        }
        else
        {
            Start(Directory.GetCurrentDirectory());
        }

        Console.ReadLine();
    }

    public static void Start(string path)
    {
        ParallelJob(path);
        foreach (directoryInfo d in directories)
        {
            Debug.WriteLine(string.Format("{0}\t{1}\t{2}", d.directory, d.size, d.totalSize));
        }

        Console.WriteLine(string.Format("Processing complete.{0}", directories.Count));
        return;
    }

    private static void ParallelJob(string path)
    {

        directories.Add(new directoryInfo() { directory = path });
        Console.WriteLine("getting directories");
        AddDirectories(path, directories);

        foreach (directoryInfo directory in directories)
        {
            Debug.WriteLine(directory.directory);
        }
        Console.WriteLine("adding files");
        Parallel.ForEach(directories, (currentDirectory) =>
        {
            Debug.WriteLine("Processing {0} on thread {1}", currentDirectory.directory, Thread.CurrentThread.ManagedThreadId);
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

            AddFiles(currentDirectory.directory, directories);
        });

    }

    private static void AddFiles(string path, ConcurrentBag<directoryInfo> files)
    {
        Debug.WriteLine("checking " + path);

        try
        {
            //List<string> list = Directory.GetFiles(path).ToList();
            List<FileSystemInfo> list = new DirectoryInfo(path).GetFileSystemInfos().Where(x => x.Attributes != FileAttributes.Directory).ToList();
            Int32 sum = list.Sum(x => ((int)((FileInfo)x).Length));
            //Int32 sum = 0;
            files.First(x => x.directory == path).size = sum;
        }
        catch (Exception ex)
        {
            Debug.WriteLine("exception: " + ex.ToString());
        }
    }

    private static void AddDirectories(string path, ConcurrentBag<directoryInfo> files)
    {
        Debug.WriteLine("checking " + path);

        try
        {
            List<string> directories = Directory.GetDirectories(path).ToList();
            foreach (string dir in directories)
            {
                directoryInfo dInfo = new directoryInfo() { directory = dir };
                files.Add(dInfo);
                AddDirectories(dir, files);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine("exception: " + ex.ToString());
        }
    }
}

'@

Add-Type $code
[dotNet]::Start($path)