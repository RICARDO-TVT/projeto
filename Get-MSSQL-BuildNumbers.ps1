param(
    $sendEmail = 0
)

Import-Module SQLPS

Get-Content "C:\temp\Settings.ini" | foreach-object -begin {$h=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $h.Add($k[0], $k[1]) } }
$server        = $h.Get_Item("centralServer")
$inventoryDB   = $h.Get_Item("inventoryDB")

if($server.length -eq 0){
    Write-Host "You must provide a value for the 'centralServer' in your Settings.ini file!!!" -BackgroundColor Red
    exit
}
if($inventoryDB.length -eq 0){
    Write-Host "You must provide a value for the 'inventoryDB' in your Settings.ini file!!!" -BackgroundColor Red
    exit
}

$mslExistenceQuery = "
SELECT Count(*) FROM dbo.sysobjects where id = object_id(N'[inventory].[MasterServerList]') and OBJECTPROPERTY(id, N'IsTable') = 1
"
$result = Invoke-Sqlcmd -Query $mslExistenceQuery -Database $inventoryDB -ServerInstance $server -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "The table [inventory].[MasterServerList] wasn't found!!!" -BackgroundColor Red 
    exit
}

$enoughInstancesInMSLQuery = "
SELECT COUNT(*) FROM inventory.MasterServerList WHERE is_active = 1
"
$result = Invoke-Sqlcmd -Query $enoughInstancesInMSLQuery -Database $inventoryDB -ServerInstance $server -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "There are no active instances registered to work with!!!" -BackgroundColor Red 
    exit
}

$mslValuesExistenceQuery = "
SELECT Count(*) FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLInstanceValues]') and OBJECTPROPERTY(id, N'IsTable') = 1
"
$result = Invoke-Sqlcmd -Query $mslValuesExistenceQuery -Database $inventoryDB -ServerInstance $server -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "Please run script Get-MSSQL-Instance-Values before proceeding!!!" -BackgroundColor Red 
    exit
}

if ($h.Get_Item("username").length -gt 0 -and $h.Get_Item("password").length -gt 0) {
    $username   = $h.Get_Item("username")
    $password   = $h.Get_Item("password")
}

#Function to execute queries (depending on if the user will be using specific credentials or not)
function Execute-Query([string]$query,[string]$database,[string]$instance,[int]$trusted){
    if($trusted -eq 1){ 
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-BuildNumbers','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -ErrorAction Stop
        }
    }
    else{
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Username $username -Password $password -ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-BuildNumbers','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -ErrorAction Stop
        }
    }
}

#Function for the logic of SQL Server Versions < 2017 (due to the removal of the Service Packs)
function SQL-BuildNumbers([string[]]$Array,[string]$sqlVersion){ 
    $insertQuery = "INSERT INTO tmpBuildNumbers VALUES"

    for($l = 0; $l -lt $fileArray.Count; $l++){
        for($i = 0; $i -lt $Array.Count; $i++){
            $sp = $cu = $extra = $buildNumber = $releaseDate = ""

            if($Array[$i].toString() -eq $fileArray[$l]){
                if($fileArray[$l].Contains("GDR") -or $fileArray[$l].Contains("Security update")  -or $fileArray[$l].Contains("security update") -or $fileArray[$l].Contains("TLS 1.2") -or $fileArray[$l].Contains("QFE")){
                    $extra = "GDR"
                }
                if($fileArray[$l].Contains("On-demand") -or $fileArray[$l].Contains("on-demand")){
                    $extra = "ON"
                }
                if($fileArray[$l].Contains("Customer Technology Preview") -or $fileArray[$l].Contains("Community Technology Preview") -or $fileArray[$l].Contains("CTP")){
                    $extra = "CTP"
                }
                if($fileArray[$l].Contains("Service Pack 1") -or $fileArray[$l].Contains("SP1")){
                    $sp = "SP1"
                }
                if($fileArray[$l].Contains("Service Pack 2") -or $fileArray[$l].Contains("SP2")){
                    $sp = "SP2"
                }
                if($fileArray[$l].Contains("Service Pack 3") -or $fileArray[$l].Contains("SP3")){
                    $sp = "SP3"
                }
                if($fileArray[$l].Contains("Service Pack 4") -or $fileArray[$l].Contains("SP4")){
                    $sp = "SP4"
                }
                if($sp -eq ""){
                    $sp = "RTM"
                }
                if($fileArray[$l].Contains("Cumulative update")){
                $cu = [regex]::Match($fileArray[$l],"\(C.*\)").Value
                $cu = $cu.Substring(1,$cu.IndexOf(")")-1)
                }

                $buildNumber = $fileArray[$l-5]
                $releaseDate = $fileArray[$l+1] -replace " \*new",""
               
                #Complement for SQL 2017 Build Numbers
                if($buildNumber -eq "14.0.3192.2"){$cu = "CU15"}
                if($buildNumber -eq "14.0.3035.2"){$cu = "CU9"}

                #Complement for SQL 2016 Build Numbers
                if($buildNumber -eq "13.0.5366.0"){$cu = "CU7"}
                if($buildNumber -eq "13.0.5270.0"){$cu = "CU5"}
                if($buildNumber -eq "13.0.5239.0"){$cu = "CU4"}
                if($buildNumber -eq "13.0.5201.2"){$cu = "CU2"}
                if($buildNumber -eq "13.0.4604.0"){$cu = "CU15"}
                if($buildNumber -eq "13.0.4522.0"){$cu = "CU10"}
                if($buildNumber -eq "13.0.2218.0"){$cu = "CU9"}
                if($buildNumber -eq "13.0.2190.2"){$cu = "CU3"}
                if($buildNumber -eq "13.0.2186.6"){$cu = "CU3"}
                if($buildNumber -eq "13.0.2170.0"){$cu = "CU2"}
                if($buildNumber -eq "13.0.2169.0"){$cu = "CU2"}

                #Complement for SQL 2014 Build Numbers
                if($buildNumber -eq "12.0.6293.0"){$cu = "CU3"}
                if($buildNumber -eq "12.0.5659.1"){$cu = "CU17"}
                if($buildNumber -eq "12.0.5532.0"){$cu = "CU2"}
                if($buildNumber -eq "12.0.4437.0"){$cu = "CU4"}
                if($buildNumber -eq "12.0.4237.0"){$cu = "CU3"}
                if($buildNumber -eq "12.0.4232.0"){$cu = "CU3"}
                if($buildNumber -eq "12.0.4419.0"){$cu = "CU1"}
                if($buildNumber -eq "12.0.4487.0"){$cu = "CU9"}
                if($buildNumber -eq "12.0.2381.0"){$cu = "CU2"}
                if($buildNumber -eq "12.0.2485.0"){$cu = "CU6"}
                if($buildNumber -eq "12.0.2548.0"){$cu = "CU8"}

                #Complement for SQL 2012 Build Numbers
                if($buildNumber -eq "11.0.6615.2"){$cu = "CU10"}
                if($buildNumber -eq "11.0.6607.3"){$cu = "CU9"}
                if($buildNumber -eq "11.0.6567.0"){$cu = "CU6"}
                if($buildNumber -eq "11.0.5676.0"){$cu = "CU15"}
                if($buildNumber -eq "11.0.5613.0"){$cu = "CU6"}
                if($buildNumber -eq "11.0.3513.0"){$cu = "CU16"}
                if($buildNumber -eq "11.0.3460.0"){$cu = "CU13"}
                if($buildNumber -eq "11.0.3350.0"){$cu = "CU3"}

                #Complement for SQL 2008 R2 Build Numbers
                if($buildNumber -eq "10.50.4339.0"){$cu = "CU13"}
                if($buildNumber -eq "10.50.4321.0"){$cu = "CU13"}
                if($buildNumber -eq "10.50.2881.0"){$cu = "CU13"}
                if($buildNumber -eq "10.50.2861.0"){$cu = "CU8"}
                if($buildNumber -eq "10.50.1790.0"){$cu = "CU7"}

                #Complement for SQL 2008 Build Numbers
                if($buildNumber -eq "10.0.5890.0"){$cu = "CU17"}
                if($buildNumber -eq "10.0.5869.0"){$cu = "CU17"}
                if($buildNumber -eq "10.0.2841.0"){$cu = "CU14"}
                
                if(-not($fileArray[$l].Contains("Withdrawn") -or $fileArray[$l].Contains("Deprecated"))){ 
                    #Extra validation to remove the build numbers from 2008 R2 that might slip in the 2008 validation
                    if($sqlVersion -eq "2008"){
                        if(-not $buildNumber.Contains("10.50")){
                        $insertQuery += "('"+$sp+"','"+$cu+"','"+$extra+"','"+$buildNumber+"','"+$releaseDate+"')," 
                        #$insertQuery -replace "''","NULL"
                        }
                    }
                    else{   
                        $insertQuery += "('"+$sp+"','"+$cu+"','"+$extra+"','"+$buildNumber+"','"+$releaseDate+"')," 
                        #$insertQuery -replace "''","NULL"  
                    }  
                }
            }
        }  
    }
   
    $insertQuery = $insertQuery.Substring(0,$insertQuery.LastIndexOf(','))
    $insertQuery = $insertQuery -replace "''","NULL"
    
    Execute-Query $insertQuery $inventoryDB $server 1

}

###########################
#Website parse logic start#
###########################
$data = Invoke-WebRequest "https://sqlserverbuilds.blogspot.com/" -UseBasicParsing
$data.RawContent | Out-file "C:\temp\page.html"

$html = New-Object -ComObject "HTMLFile"
$html.IHTMLDocument2_write($(Get-Content "C:\temp\page.html" -raw))

[string[]]$fileArray = $html.all.tags("td") | % innerText

$temporalTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name = 'tmpBuildNumbers' AND xtype = 'U')
CREATE TABLE tmpBuildNumbers(
   [sp] [NVARCHAR](5) NULL,
   [cu] [NVARCHAR](5) NULL,
   [extra] [NVARCHAR](5) NULL,
   [build_number] [NVARCHAR](16) NULL,
   [release_date] [DATE] NULL
) ON [PRIMARY]
"
Execute-Query $temporalTableCreationQuery $inventoryDB $server 1

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(Cumulative update.*for SQL Server 2019)|(Security update.*for SQL Server 2019)|(On-demand hotfix update package.*for SQL Server 2019)|(Security update for the Remote Code Execution vulnerability in SQL Server 2019)|(SQL Server 2019 RTM)'
SQL-BuildNumbers $sqlArray "2019"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(Cumulative update.*for SQL Server 2017)|(Security update.*for SQL Server 2017)|(On-demand hotfix update package.*for SQL Server 2017)|(Security update for the Remote Code Execution vulnerability in SQL Server 2017)|(SQL Server 2017 RTM)'
SQL-BuildNumbers $sqlArray "2017"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2016 Service Pack.*)|(Cumulative update.*for SQL Server 2016)|(Security update.*for SQL Server 2016)|(On-demand hotfix update package.*for SQL Server 2016)|(Security update for the Remote Code Execution vulnerability in SQL Server 2016)|(SQL Server 2016 RTM)'
SQL-BuildNumbers $sqlArray "2016"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2014 Service Pack.*)|(Cumulative update.*for SQL Server 2014)|(Security update.*for SQL Server 2014)|(On-demand hotfix update package.*for SQL Server 2014)|(Security update for the Remote Code Execution vulnerability in SQL Server 2014)|(SQL Server 2014 RTM)'
SQL-BuildNumbers $sqlArray "2014"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2012 Service Pack.*)|(Cumulative update.*for SQL Server 2012)|(Security update.*for SQL Server 2012)|(On-demand hotfix update package.*for SQL Server 2012)|(Security update for the Remote Code Execution vulnerability in SQL Server 2012)|(SQL Server 2012 RTM)'
SQL-BuildNumbers $sqlArray "2012"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2008 R2 Service Pack.*)|(Cumulative update.*for SQL Server 2008 R2)|(Security update.*for SQL Server 2008 R2)|(On-demand hotfix update package.*for SQL Server 2008 R2)|(Security update for the Remote Code Execution vulnerability in SQL Server 2008 R2)|(SQL Server 2008 R2 RTM)'
SQL-BuildNumbers $sqlArray "2008 R2"

$sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2008 Service Pack.*)|(Cumulative update.*for SQL Server 2008)|(Security update.*for SQL Server 2008)|(On-demand hotfix update package.*for SQL Server 2008)|(Security update for the Remote Code Execution vulnerability in SQL Server 2008)|(SQL Server 2008 RTM)'
SQL-BuildNumbers $sqlArray "2008"

#Check if the inventory.MSSQLBuildNumbers table is empty or not
$buildNumbersCount = Execute-Query "SELECT COUNT(*) FROM inventory.MSSQLBuildNumbers" $inventoryDB $server 1

#Check if there is at least 1 that is not in the centralized table
$newBuildNumbersCheckQuery = "
SELECT COUNT(*)
FROM tmpBuildNumbers t
WHERE t.build_number NOT IN (SELECT build_number FROM inventory.MSSQLBuildNumbers)
"
$check = Execute-Query $newBuildNumbersCheckQuery $inventoryDB $server 1

#If there is at least 1 new build number to be added then insert it in the centralized table and send an email to the DBA team
if($check[0] -gt 0 -and $sendEmail -eq 1){
    #Send email to DBAs notifying that a new Build Number was added
    Start-Process powershell.exe -ArgumentList "& 'C:\temp\BuildNumbersMail.ps1'"

    while($test = (Get-WmiObject -Class win32_process -Filter "name='powershell.exe'" | Select-Object -Property CommandLine) -Match "BuildNumbersMail.ps1"){
        Start-Sleep -s 5
    }
}

if($check[0] -gt 0){    
    $insertNewBuildNumbersQuery = "
    INSERT INTO inventory.MSSQLBuildNumbers
    SELECT 
	      t.sp,
	      t.cu,
	      t.extra,
	      t.build_number,
	      t.release_date
    FROM  tmpBuildNumbers t
    WHERE t.build_number NOT IN (SELECT build_number FROM inventory.MSSQLBuildNumbers)
    "
    Execute-Query $insertNewBuildNumbersQuery $inventoryDB $server 1

    #If new build numbers were fetched and saved, run the Get-MSSQL-Instance-Values to see if any instance has to be immediately updated
    Start-Process powershell.exe -ArgumentList "& 'C:\temp\Get-MSSQL-Instance-Values.ps1'"
}

#After doing all the work, drop the tmpBuildNumbers table from the database
$temporalTableDeletionQuery = "
IF EXISTS (SELECT * FROM sysobjects WHERE name = 'tmpBuildNumbers' AND xtype = 'U')
DROP TABLE tmpBuildNumbers
"
Execute-Query $temporalTableDeletionQuery $inventoryDB $server 1

#Delete the generated HTML file
Remove-Item "C:\temp\page.html"

Write-Host 'Done!'