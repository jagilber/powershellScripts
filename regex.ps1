# does grep with findstr

param(
[parameter(Position=0,Mandatory=$true)]
    [string] $searchstring,
[parameter(Position=1,Mandatory=$false)]
    [string] $logDir = ".\"    
)
cd e:\temp
[string] $specialChars = '\ |\@|\"|\\|\/|\:|\*|\?|"|<|>|\||\#|\%|\&|\.|\{|\}|\~'  
$filename = "$([regex]::Replace($searchstring,$specialChars,"_")).csv"
$command = "-Command findstr /S /R /I `"$searchstring`" `"$logDir`"\*.CSV | tee-object -Append -File `"$filename`""
$command
#$regex = new-object System.Text.RegularExpressions.Regex('[System.Text.RegularExpressions.RegexOptions]::MultiLine')

Start-Process powershell.exe $command
