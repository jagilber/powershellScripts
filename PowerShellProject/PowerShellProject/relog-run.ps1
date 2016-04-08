cd F:\cases\115041612643997_Edgar_Toro_House_of_Commons_Canada_-_Premier_Standard_-_2015-18\Perfmon_Logs20150603@084421\Perfmon_Logs20150603@084421

#$name = "EISSSENCOM02PTV"
$name = Read-Host "enter machine name:"

del "$name.blg"

relog "$name*.blg" -c "\Process(svchost#*)\ID Process" -f "CSV" -o "$name.ids.csv"
type "$name.ids.csv" 

$instance = Read-Host 'What is the service host instance number?'

relog "$name*.blg" -c "\Process(svchost#$instance)\*" -o "$name.blg"

Invoke-Item "$name.blg"


