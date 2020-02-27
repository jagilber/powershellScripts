param (
    [string]$localHostName = "",
    [int]$localHostPort = 8080,
    [string]$remoteHostName = "",
    [int]$remoteHostPort = 8081,
    [string]$absolutePath = "/",
    [int]$iterations = 1
)

$code = @'
//https://stackoverflow.com/questions/19523088/create-http-request-using-tcpclient
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public class csSocketHttp
{
    public static string Connect(string localHostName, int localHostPort, string remoteHostName, int remoteHostPort, string absolutePath)
    {
        IPAddress host = IPAddress.Parse(localHostName);
        IPEndPoint hostep = new IPEndPoint(host, localHostPort);
        TcpClient client = new TcpClient(hostep);
        string request = string.Format("GET {0} HTTP/1.1", absolutePath);
        client.Connect(remoteHostName, remoteHostPort);
        var result = Task.Run(() => HttpRequestAsync(client, string.Format("{0}:{1}",remoteHostName,remoteHostPort), request)).Result;
        Console.WriteLine(result);
        return result;
    }

    private static int BinaryMatch(byte[] input, byte[] pattern)
    {
        int sLen = input.Length - pattern.Length + 1;
        for (int i = 0; i < sLen; ++i)
        {
            bool match = true;
            for (int j = 0; j < pattern.Length; ++j)
            {
                if (input[i + j] != pattern[j])
                {
                    match = false;
                    break;
                }
            }
            if (match)
            {
                return i;
            }
        }
        return -1;
    }

    private static async Task<string> HttpRequestAsync(TcpClient tcp, string host, string getRequest)
    {
        string result = string.Empty;

        using (tcp)
        using (var stream = tcp.GetStream())
        {
            tcp.SendTimeout = 500;
            tcp.ReceiveTimeout = 1000;
            // Send request headers
            var builder = new StringBuilder();
            builder.AppendLine(getRequest);
            builder.AppendLine(string.Format("Host: {0}",host));
            builder.AppendLine("Connection: close");
            builder.AppendLine();
            var header = Encoding.ASCII.GetBytes(builder.ToString());
            await stream.WriteAsync(header, 0, header.Length);

            // receive data
            using (var memory = new MemoryStream())
            {
                await stream.CopyToAsync(memory);
                memory.Position = 0;
                var data = memory.ToArray();

                var index = BinaryMatch(data, Encoding.ASCII.GetBytes("\r\n\r\n")) + 4;
                var headers = Encoding.ASCII.GetString(data, 0, index);
                memory.Position = index;
                result = Encoding.UTF8.GetString(data, index, data.Length - index);
            }

            Console.WriteLine(result);
            return result;
        }
    }
}
'@

add-type $code
$count = 0
while ($count -le $iterations) {
    [csSocketHttp]::Connect($localHostName, $localHostPort, $remoteHostName, $remoteHostPort, $absolutePath)
    start-sleep -Seconds 1
    $count++
}
write-host "finished"