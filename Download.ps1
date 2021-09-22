Add-Type -Assembly System.Web # [System.Web.HttpUtility]::UrlEncode() needs this

$SqlVersion = "2017"
$Query = "select * where A='" + $SqlVersion + "'"
$URL   = "https://docs.google.com/spreadsheets/d/16Ymdz80xlCzb6CwRFVokwo0onkofVYFoSkc7mYe6pgw/gviz/tq?tq=" `
       + [System.Web.HttpUtility]::UrlEncode($Query) `
       + "&tqx=out:csv"

Invoke-WebRequest $URL -OutFile "C:\Temp\SqlServerBuilds.csv"