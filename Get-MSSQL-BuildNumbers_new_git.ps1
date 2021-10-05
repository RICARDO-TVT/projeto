# 4 - script :   Monitora a versão da instância cadastradas dos servidores SQL para a mais recente compilação disponível lançada pela Microsoft
#############################################################################################################################################
param(
    $sendEmail = 0
)
################################################################################################################################

# Ensure the build fails if there is a problem.
# The build will fail if there are any errors on the remote machine too!
$ErrorActionPreference = 'Stop'

 # Create a PSCredential Object using the "User" and "Password" parameters that you passed to the job
$SecurePassword = $env:password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:user, $SecurePassword

## Import-Module SQLPS

#https://www.mssqltips.com/sqlservertip/6628/sql-server-version-and-build-number-monitoring/
Write-Host "Monitorando a versão da instância do servidor SQL para a mais recente compilação disponível lançada pela Microsoft" 
$webRequest = Invoke-WebRequest https://raw.githubusercontent.com/RICARDO-TVT/projeto/main/Settingsteste.txt -UseBasicParsing
$paths = ConvertFrom-StringData -StringData $webRequest.Content
$server = $paths['centralServer']
Write-Host $server
$inventoryDB = $paths['inventoryDB']
Write-Host $inventoryDB

if($server.length -eq 0){
    Write-Host "Informar um Nome de servidor para o 'centralServer' no arquivo Settings.ini !!!" -BackgroundColor Red
    exit
}
if($inventoryDB.length -eq 0){
    Write-Host "Informar um Nome do database para o 'inventoryDB' no arquivo Settings.ini !!!" -BackgroundColor Red
    exit
}

$mslExistenceQuery = "
SELECT Count(*) FROM dbo.sysobjects where id = object_id(N'[inventory].[MasterServerList]') and OBJECTPROPERTY(id, N'IsTable') = 1
"
$result = Invoke-Sqlcmd -Query $mslExistenceQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "A tabela [inventory].[MasterServerList] não localizada!!!" -BackgroundColor Red 
    exit
}

$enoughInstancesInMSLQuery = "
SELECT COUNT(*) FROM inventory.MasterServerList WHERE is_active = 1
"
$result = Invoke-Sqlcmd -Query $enoughInstancesInMSLQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "Não há instâncias ativas registradas para trabalhar !!!" -BackgroundColor Red 
    exit
}

$mslValuesExistenceQuery = "
SELECT Count(*) FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLInstanceValues]') and OBJECTPROPERTY(id, N'IsTable') = 1
"
$result = Invoke-Sqlcmd -Query $mslValuesExistenceQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop 

if($result[0] -eq 0){
    Write-Host "Favor executar o script Get-MSSQL-Instance-Values antes deste procedimento!!!" -BackgroundColor Red 
    exit
}

if ($h.Get_Item("username").length -gt 0 -and $h.Get_Item("password").length -gt 0) {
    $username   = $h.Get_Item("username")
    $password   = $h.Get_Item("password")
}

#Função para executar consultas (dependendo se o usuário usará credenciais específicas ou não)
function Execute-Query([string]$query,[string]$database,[string]$instance,[int]$trusted){
    if($trusted -eq 1){ 
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Credential $cred-ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-BuildNumbers','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop
        }
    }
    else{
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Credential $cred -ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-BuildNumbers','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop
        }
    }
}

#Função para a lógica de versões do SQL Server < 2017 (devido à remoção dos Service Packs)
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

#Verifique se a tabela inventory.MSSQLBuildNumbers está vazia ou não
$buildNumbersCount = Execute-Query "SELECT COUNT(*) FROM inventory.MSSQLBuildNumbers" $inventoryDB $server 1

#Verifique se há pelo menos 1 que não está na tabela centralizada
$newBuildNumbersCheckQuery = "
SELECT COUNT(*)
FROM tmpBuildNumbers t
WHERE t.build_number NOT IN (SELECT build_number FROM inventory.MSSQLBuildNumbers)
"
$check = Execute-Query $newBuildNumbersCheckQuery $inventoryDB $server 1

#Se houver pelo menos 1 novo build number a ser adicionado, insira-o na tabela centralizada e envie um e-mail para a equipe de DBA
if($check[0] -gt 0 -and $sendEmail -eq 1){
    #Enviar e-mail para DBAs notificando que um novo  build number foi adicionado
    Start-Process powershell.exe -ArgumentList "& 'C:\Users\ricardo.osilva\Desktop\Projeto\6354_scripts\BuildNumbersMail.ps1'"
    Write-Host 'novo build number'
    while($test = (Get-WmiObject -Class win32_process -Filter "name='powershell.exe'" | Select-Object -Property CommandLine) -Match "BuildNumbersMail.ps1")
    {
        Start-Sleep -s 5
    }
}
    else
     {
    Write-Host 'Não localizado novo build number'
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

    #Se novos build numbers foram buscados e salvos, execute Get-MSSQL-Instance-Values para ver se alguma instância precisa ser atualizada imediatamente
    Start-Process powershell.exe -ArgumentList "& 'C:\Users\ricardo.osilva\Desktop\Projeto\6354_scripts\Get-MSSQL-Instance-Values-v2.ps1'"
}

#Depois de fazer todo o trabalho, elimine a tabela tmpBuildNumbers do database
$temporalTableDeletionQuery = "
IF EXISTS (SELECT * FROM sysobjects WHERE name = 'tmpBuildNumbers' AND xtype = 'U')
DROP TABLE tmpBuildNumbers
"
Execute-Query $temporalTableDeletionQuery $inventoryDB $server 1

#Delete the generated HTML file
Remove-Item "C:\temp\page.html"

Write-Host 'Done!'