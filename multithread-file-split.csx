// Usage Examples:
//   dotnet script -- c:\github\jagilber\powershellScripts\multithread-file-split.csx "C:\input.csv" "1" "true"
//   dotnet script -- c:\github\jagilber\powershellScripts\multithread-file-split.csx "C:\input.csv" "2"
#r "System.Core.dll"
using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;

public class FileSplitter
{
    // Splits the file into parts by first reading all lines into memory,
    // then partitioning the dataLines array and concurrently writing each part.
    public static async Task SplitFileAsync(string csvPath, long maxSizeBytes, bool writeHeader)
    {
        if (!File.Exists(csvPath))
        {
            Console.WriteLine($"File {csvPath} does not exist.");
            return;
        }
        
        // Read entire file
        var allLines = File.ReadAllLines(csvPath);
        if (allLines.Length < 2)
        {
            Console.WriteLine("File has no data lines.");
            return;
        }
        
        string header = allLines[0];
        List<string> dataLines = allLines.Skip(1).ToList();

        // Estimate file metrics using first 1000 lines (or fewer if file is small)
        long csvFileSize = new FileInfo(csvPath).Length;
        int sampleCount = Math.Min(1000, allLines.Length);
        long totalSampleLength = allLines.Take(sampleCount).Sum(line => (long)line.Length);
        double avgLineSize = sampleCount > 0 ? (double)totalSampleLength / sampleCount : 0;
        double avgLineSizeBytes = avgLineSize; // Assuming size in bytes per character already
        long estimatedTotalLines = (long)(csvFileSize / avgLineSizeBytes);
        Console.WriteLine($"Total file size: {csvFileSize} bytes, Estimated total lines: {estimatedTotalLines}, Avg line size: {avgLineSizeBytes} bytes");

        // Determine number of parts based on file size
        int parts = (int)Math.Ceiling((double)csvFileSize / maxSizeBytes);
        parts = Math.Max(parts, 1);
        int linesPerPart = (int)Math.Ceiling((double)dataLines.Count / parts);
        Console.WriteLine($"Total data lines: {dataLines.Count}, Estimated parts: {parts}, Lines per part: {linesPerPart}");

        // Pre-delete output files to avoid file access conflicts
        for (int i = 0; i < parts; i++)
        {
            string outputPath = $"{csvPath}.part{i}.csv";
            if (File.Exists(outputPath))
            {
                try { File.Delete(outputPath); } 
                catch (Exception ex) { Console.WriteLine($"Error deleting {outputPath}: {ex.Message}"); }
            }
        }

        var tasks = new List<Task>();
        for (int i = 0; i < parts; i++)
        {
            int currentPart = i; // capture the loop variable
            int startIndex = currentPart * linesPerPart;
            int count = Math.Min(linesPerPart, dataLines.Count - startIndex);
            string outputPath = $"{csvPath}.part{currentPart}.csv";
            tasks.Add(Task.Run(() =>
            {
                using (var writer = new StreamWriter(outputPath))
                {
                    if (writeHeader)
                        writer.WriteLine(header);
                    for (int j = 0; j < count; j++)
                    {
                        writer.WriteLine(dataLines[startIndex + j]);
                    }
                }
                Console.WriteLine($"Written part {currentPart} to {outputPath}");
            }));
        }
        await Task.WhenAll(tasks);
        Console.WriteLine("File splitting completed.");
    }
}

// Parse command-line arguments using Args
if (Args.Count == 0)
{
    Console.WriteLine("Usage: dotnet script multithread-file-split.csx <csvPath> <maxSizeGb> [writeHeader]");
    return;
}
string csvPath = Args[0];
double maxSizeGb = double.Parse(Args[1]);
long maxSizeBytes = (long)(maxSizeGb * 1073741824);
bool writeHeader = Args.Count >= 3 ? bool.Parse(Args[2]) : false;

await FileSplitter.SplitFileAsync(csvPath, maxSizeBytes, writeHeader);

// Command line example:
// dotnet script -- c:\github\jagilber\powershellScripts\multithread-file-split.csx "C:\cases\2501230040002730\1\node3_mar7_1\minio_http.csv" "1" "true"