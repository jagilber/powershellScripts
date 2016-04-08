# calculate time difference between two dates and / or times
# can be just a date 5/28/2015
# can be just a time 8:04:00
# can be partial date 5/28/15
# example complete beginning date: 05/28/2015 10:07:23.000
# example complete end date: 06/03/2015 08:00:04.000

$beginningDate = read-host "enter beginning date: example: 05/28/2015 10:07:23.000"
$enddate = read-host "enter ending date: example: 06/03/2015 08:00:04.000"

$beginningDate = [Convert]::ToDateTime($beginningDate)
write-host "beginning date: $beginningDate"

$endDate = [Convert]::ToDateTime($enddate)
write-host "end date: $endDate"

write-host "time difference: $($endDate - $beginningDate)"
write-host "time difference Total Days: $(($endDate - $beginningDate).TotalDays)"
write-host "time difference Total Hours: $(($endDate - $beginningDate).TotalHours)"
write-host "time difference Total Minutes: $(($endDate - $beginningDate).TotalMinutes)"
write-host "time difference Total Seconds: $(($endDate - $beginningDate).TotalSeconds)"
write-host "time difference Total Milliseconds: $(($endDate - $beginningDate).TotalMilliseconds)"

