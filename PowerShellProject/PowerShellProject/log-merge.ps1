<#  
.SYNOPSIS  

    powershell script to merge multiple csv files with timestamps by timestamp into new file

.DESCRIPTION  
        
    ** Copyright (c) Microsoft Corporation. All rights reserved - 2016.
    **
    ** This script is not supported under any Microsoft standard support program or service.
    ** The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    ** implied warranties including, without limitation, any implied warranties of merchantability
    ** or of fitness for a particular purpose. The entire risk arising out of the use or performance
    ** of the scripts and documentation remains with you. In no event shall Microsoft, its authors,
    ** or anyone else involved in the creation, production, or delivery of the script be liable for
    ** any damages whatsoever (including, without limitation, damages for loss of business profits,
    ** business interruption, loss of business information, or other pecuniary loss) arising out of
    ** the use of or inability to use the script or documentation, even if Microsoft has been advised
    ** of the possibility of such damages.
    **
 
.NOTES  
   File Name  : log-merge.ps1  
   Author     : jagilber
   Version    : 160311
                
   History    : 

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *evt*.csv -outputFile c:\temp\all-events.csv
    Search c:\logfiles folder for all files matching pattern *evt*.csv and output to c:\temp\all-events.csv   

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *FMT*.csv -outputFile c:\temp\all-etw.csv
    Search c:\logfiles folder for all files matching pattern *FMT*.txt and output to c:\temp\all-etw.csv   

.PARAMETER sourceFolder
    Path to source folder to be searched. ex: c:\logfiles

.PARAMETER filePattern
    Dos style file matching pattern for csv files to parse. ex: *evt*.csv

.PARAMETER outputFile
    Name and location of the new merged file. ex: c:\temp\test.csv
#>  

Param(
 
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the source folder for searching:")]
    [string] $sourceFolder,
    [parameter(Position=1,Mandatory=$true,HelpMessage="Enter the file filter pattern (dos style *.*):")]
    [string] $filePattern,
    [parameter(Position=2,Mandatory=$true,HelpMessage="Enter the new file name:")]
    [string] $outputFile = "log-merge.csv"
    )



$Code = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using System.Text.RegularExpressions;
using System.Globalization;


    public class LogMerge
    {

        int precision = 0;
        Dictionary<string, string> outputList = new Dictionary<string, string>();
        //07/22/2014-14:48:10.909 for etl and 07/22/2014,14:48:10 PM for eventlog
        string datePattern = "(?<DateEtlPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{7}) |" +
            "(?<DateEtl>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{3}) |" +
            "(?<DateEvt>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
            "(?<DateEvtSpace>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
            "(?<DateEvtPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{6} [AP]M)";  
        string dateFormatEtl = "MM/dd/yyyy-HH:mm:ss.fff";
        string dateFormatEtlPrecise = "MM/dd/yy-HH:mm:ss.fffffff";
        string dateFormatEvt = "MM/dd/yyyy,hh:mm:ss tt";
        string dateFormatEvtSpace = "MM/dd/yyyy hh:mm:ss tt";
        string dateFormatEvtPrecise = "MM/dd/yyyy,hh:mm:ss.ffffff tt";
        
        bool detail = false;

        CultureInfo culture = new CultureInfo("en-US");
        Int64 missedMatchCounter = 0;
        Int64 missedDateCounter = 0;
        
        public static void Start(string[] args,string defaultDir)
        {
            LogMerge program = new LogMerge();
            try
            {
                Directory.SetCurrentDirectory(defaultDir);

                if (args.Length > 2)
                {
                    string[] files = Directory.GetFiles(args[0], args[1], SearchOption.AllDirectories);
                    if (files.Length < 1)
                    {
                        Console.WriteLine("unable to find files. returning");
                        return;
                    }

                    program.ReadFiles(files, args[2]);

                }
                else
                {
                    Console.WriteLine("utility combines *fmt.txt files into one file based on timestamp. provide folder and filter args and output file.");

                    Console.WriteLine("LogMerge takes three arguments; source dir, file filter, and output file.");
                    Console.WriteLine("example: LogMerge f:\\cases *fmt.txt c:\\temp\\all.csv");
                }
            }
            catch (Exception e)
            {
                Console.WriteLine(string.Format("exception:main:precision:{0}:missed:{1}:excetion:{2}",program.precision, program.missedMatchCounter, e));
            }
        }

        bool ReadFiles(string[] files, string outputfile)
        {
            Match match = Match.Empty;
            long lastTicks = 0;
            string line = string.Empty;

            try
            {

                foreach (string file in files)
                {
                    Console.WriteLine(file);
                    StreamReader reader = new StreamReader(file);
                    DateTime date = new DateTime();
                    string fileName = Path.GetFileName(file);
                    string pidPattern = "^(.*)::";
                    string lastPidString = string.Empty;
                    string traceDate = string.Empty;
                    string dateFormat = string.Empty;

                    while (reader.Peek() >= 0)
                    {
                        line = reader.ReadLine();
                        //     if(Regex.IsMatch(line,datePattern))
                        //     {
                        if (Regex.IsMatch(line, pidPattern))
                        {
                            lastPidString = Regex.Match(line, pidPattern).Value;
                        }

                        Match matchTraceDate = Regex.Match(line, datePattern);

                        if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEtlPrecise"].Value))
                        {
                            dateFormat = dateFormatEtlPrecise;
                            traceDate = matchTraceDate.Groups["DateEtlPrecise"].Value;
                        }
                        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEtl"].Value))
                        {
                            dateFormat = dateFormatEtl;
                            traceDate = matchTraceDate.Groups["DateEtl"].Value;
                        }
                        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvt"].Value))
                        {
                            dateFormat = dateFormatEvt;
                            traceDate = matchTraceDate.Groups["DateEvt"].Value;
                        }
                        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvtSpace"].Value))
                        {
                            dateFormat = dateFormatEvtSpace;
                            traceDate = matchTraceDate.Groups["DateEvtSpace"].Value;
                        }
                        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvtPrecise"].Value))
                        {
                            dateFormat = dateFormatEvtPrecise;
                            traceDate = matchTraceDate.Groups["DateEvtPrecise"].Value;
                        }
                        else
                        {
                            if (detail) Console.WriteLine("unable to parse date:{0}:{1}", missedDateCounter, line);
                            missedDateCounter++;
                        }


                        if (DateTime.TryParseExact(traceDate,
                            dateFormat,
                            culture,
                            DateTimeStyles.AssumeLocal,
                            out date))
                        {
                            if (lastTicks != date.Ticks)
                            {
                                lastTicks = date.Ticks;
                                precision = 0;

                            }

                        }
                        else if (DateTime.TryParse(traceDate, out date))
                        {
                            if (lastTicks != date.Ticks)
                            {
                                lastTicks = date.Ticks;
                                precision = 0;

                            }


                            dateFormat = dateFormatEvt;

                        }
                        else
                        {
                            //      Console.WriteLine("unable to parse date2:{0}:{1}", missedDateCounter, line);
                            // use last date and let it increment to keep in place
                            date = new DateTime(lastTicks);

                            // put cpu pid and tid back in

                            if (Regex.IsMatch(line, pidPattern))
                            {
                                line = string.Format("{0}::{1}", lastPidString, line);
                            }
                            else
                            {
                                line = string.Format("{0}{1} -> {2}", lastPidString, date.ToString(dateFormat), line);
                            }

                            missedMatchCounter++;
                            Console.WriteLine("unable to parse time:{0}:{1}", missedMatchCounter, line);
                        }


                        while (precision < 99999999)
                        {
                            if (AddToList(date, string.Format("{0}, {1}", fileName, line)))
                            {
                                break;
                            }

                            precision++;

                        }

                    }
                }

                if (File.Exists(outputfile))
                {
                    File.Delete(outputfile);
                }

                using (StreamWriter writer = new StreamWriter(outputfile, true))
                {
                    Console.WriteLine("sorting lines.");
                    foreach (var item in outputList.OrderBy(i => i.Key))
                    {
                        writer.WriteLine(item.Value);
                    }
                }

                Console.WriteLine(string.Format("finished:missed {0} lines", missedMatchCounter));
                return true;
            }
            catch (Exception e)
            {
                Console.WriteLine(string.Format("ReadFiles:exception:lines count:{0}: dictionary count:{1}: exception:{2}", line.Length, outputList.Count, e));
                return false;
            }
        }

        bool AddToList(DateTime date, string line)
        {
            string key = string.Format("{0}{1}",date.Ticks.ToString(), precision.ToString("D8"));
            if(!outputList.ContainsKey(key))
            {
             //   Console.WriteLine("debug:list:key:{0} value:{1}", key, line);
                outputList.Add(key,line);
            }
            else
            {
                return false;
               //precision++;
               //AddToList(date,line);
            }

            return true;
        }
    }
'@

Add-Type $Code


[LogMerge]::Start(@($sourceFolder,$filePattern,$outputFile),(get-location))


