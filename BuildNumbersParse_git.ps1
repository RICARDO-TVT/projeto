# 3 script 3 : Popula a tabela [inventory].[MSSQLBuildNumbers] com as mais recente compilação disponível lançada pela Microsoft
# executar apos script 1 e 2
################################################################################################################################
#param( $sqlVersion = "ALL")
# Ensure the build fails if there is a problem.
# The build will fail if there are any errors on the remote machine too!
$ErrorActionPreference = 'Stop'

 # Create a PSCredential Object using the "User" and "Password" parameters that you passed to the job
$SecurePassword = $env:pass | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:user, $SecurePassword
  
$sqlVersion = "ALL"

#Import-Module SQLPS

$webRequest = Invoke-WebRequest https://raw.githubusercontent.com/RICARDO-TVT/projeto/main/Settingsteste.txt -UseBasicParsing
$paths = ConvertFrom-StringData -StringData $webRequest.Content
$server = $paths['centralServer']
Write-Host $server
$inventoryDB = $paths['inventoryDB']
Write-Host $inventoryDB

   $sql = "DELETE FROM [inventory].[MSSQLBuildNumbers]" 
        Write-Host $sql
        #Invoke-sqlcmd -Query $sql -ServerInstance $server -Database $inventoryDB -username $env:user_db  -password $env:password
Invoke-sqlcmd -Query $sql -ServerInstance $server -Database $inventoryDB  -Credential $cred

#Função para a lógica do SQL Server Versions 2017 (devido à remoção dos Service Packs)
function SQL-BuildNumbers([string[]]$Array,[string]$sqlVersion)
{  
  

    for($l = 0; $l -lt $fileArray.Count; $l++){
        for($i = 0; $i -lt $Array.Count; $i++){
            $cu = $extra = $buildNumber = $releaseDate = $Description = $WebLink = "NULL"
            $sp = "RTM"

            if($Array[$i].toString() -eq $fileArray[$l]){
                if($fileArray[$l].Contains("GDR") -or $fileArray[$l].Contains("Security update")  -or $fileArray[$l].Contains("security update") -or $fileArray[$l].Contains("TLS 1.2") -or $fileArray[$l].Contains("QFE")){
                    $extra = "GDR"
                }
                if($fileArray[$l].Contains('On-demand') -or $fileArray[$l].Contains("on-demand")){
                    $extra = "ON"
                }
                if($fileArray[$l].Contains("Customer Technology Preview") -or $fileArray[$l].Contains("Community Technology Preview") -or $fileArray[$l].Contains("CTP")){
                    $extra =  "CTP"
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

                  #$weblink = $fileArray[$l-3]  
                  
                #$Description = $fileArray[$l-4] 
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
                        Write-Host "SP:$($sp) CU:$($cu) Extra:$($extra) BuildNumber:$($buildNumber) Release Date:$($releaseDate) aaa:$Description bb:$WebLink
                         " 
                        Write-Output "SP:$($sp) CU:$($cu) Extra:$($extra) BuildNumber:$($buildNumber) Release Date:$($releaseDate)" >> export.txt Out-File export.txt
                         $sql = "INSERT INTO inventory.MSSQLBuildNumbers([sp],[cu],[extra],[build_number],[release_date])  VALUES ('$($sp)' ,'$($cu)','$($extra)', '$($buildNumber)','$($releaseDate)')" 
                          Write-Host $sql
                      Invoke-sqlcmd -Query $sql -ServerInstance $server -Database $inventoryDB -username $env:user_db  -password $env:password
                        }
                    }
                    else{   
                        Write-Host "SP;$($sp) CU;$($cu) Extra;$($extra) BuildNumber;$($buildNumber) Release Date;$($releaseDate) aaa:$Description bb:$WebLink" 
                        Write-Output "SP;$($sp) CU;$($cu) Extra;$($extra) BuildNumber;$($buildNumber) Release Date;$($releaseDate)" >> .\log.csv
                  
                    $sql = "INSERT INTO inventory.MSSQLBuildNumbers([sp],[cu],[extra],[build_number],[release_date])  VALUES ('$($sp)' ,'$($cu)','$($extra)', '$($buildNumber)','$($releaseDate)')" 
                    Write-Host $sql
                     Invoke-sqlcmd -Query $sql -ServerInstance $server -Database $inventoryDB -username $env:user_db  -password $env:password

                  
        
                    }  
                }
                   
        }  
    }
    }
  Write-Host "Results Count:" -BackgroundColor DarkBlue -ForegroundColor White -NoNewline 6 >> .\log.txt
                        Write-Host "" $Array.Count "Items`r`n" -ForegroundColor Red 6 >> .\log.txt
                        Write-Host $Array -Separator "`r`n" 6. >> .\log.txt
                        Write-Host "" "End of results." -ForegroundColor Green -Separator "`r`n" 6 >> .\log.txt
                         Out-File -FilePath .\log.txt       
            
}

#End Of Function

if($sqlVersion -ne '2019' -and $sqlVersion -ne '2017' -and $sqlVersion -ne '2016' -and $sqlVersion -ne '2014' -and $sqlVersion -ne '2012' -and $sqlVersion -ne '2008 R2' -and $sqlVersion -ne '2008R2' -and $sqlVersion -ne 'ALL'){
    Write-Host Invalid Parameter!!! -ForegroundColor White -BackgroundColor Red
    exit
}

$data = Invoke-WebRequest "https://sqlserverbuilds.blogspot.com/" -UseBasicParsing
$data.RawContent | Out-file "page.html"

$html = New-Object -ComObject "HTMLFile"

# This works in PowerShell with Office installed
$html.IHTMLDocument2_write($(Get-Content "page.html" -raw))

[string[]]$fileArray = $html.all.tags("td") | % innerText

if($sqlVersion -eq '2019' -or $sqlVersion -eq 'ALL'){
    Write-Host "SQL Server 2019 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(Cumulative update.*for SQL Server 2019)|(Security update.*for SQL Server 2019)|(On-demand hotfix update package.*for SQL Server 2019)|(Security update for the Remote Code Execution vulnerability in SQL Server 2019)|(SQL Server 2019 RTM)'
    SQL-BuildNumbers $sqlArray "2019" 
}
if($sqlVersion -eq '2017' -or $sqlVersion -eq 'ALL'){
    Write-Host "SQL Server 2017 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(Cumulative update.*for SQL Server 2017)|(Security update.*for SQL Server 2017)|(On-demand hotfix update package.*for SQL Server 2017)|(Security update for the Remote Code Execution vulnerability in SQL Server 2017)|(SQL Server 2017 RTM)'
    SQL-BuildNumbers $sqlArray "2017"
}
if($sqlVersion -eq '2016' -or $sqlVersion -eq 'ALL'){
     Write-Host "SQL Server 2016 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2016 Service Pack.*)|(Cumulative update.*for SQL Server 2016)|(Security update.*for SQL Server 2016)|(On-demand hotfix update package.*for SQL Server 2016)|(Security update for the Remote Code Execution vulnerability in SQL Server 2016)|(SQL Server 2016 RTM)'
    SQL-BuildNumbers $sqlArray "2016"
}
if($sqlVersion -eq '2014' -or $sqlVersion -eq 'ALL'){
      Write-Host "SQL Server 2014 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2014 Service Pack.*)|(Cumulative update.*for SQL Server 2014)|(Security update.*for SQL Server 2014)|(On-demand hotfix update package.*for SQL Server 2014)|(Security update for the Remote Code Execution vulnerability in SQL Server 2014)|(SQL Server 2014 RTM)'
    SQL-BuildNumbers $sqlArray "2014"
}
if($sqlVersion -eq '2012' -or $sqlVersion -eq 'ALL'){
   Write-Host "SQL Server 2012 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2012 Service Pack.*)|(Cumulative update.*for SQL Server 2012)|(Security update.*for SQL Server 2012)|(On-demand hotfix update package.*for SQL Server 2012)|(Security update for the Remote Code Execution vulnerability in SQL Server 2012)|(SQL Server 2012 RTM)'
    SQL-BuildNumbers $sqlArray "2012"
}
if($sqlVersion -eq '2008 R2' -or $sqlVersion -eq '2008R2' -or $sqlVersion -eq 'ALL'){
    Write-Host "SQL Server 2008R2 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2008 R2 Service Pack.*)|(Cumulative update.*for SQL Server 2008 R2)|(Security update.*for SQL Server 2008 R2)|(On-demand hotfix update package.*for SQL Server 2008 R2)|(Security update for the Remote Code Execution vulnerability in SQL Server 2008 R2)|(SQL Server 2008 R2 RTM)'
    SQL-BuildNumbers $sqlArray "2008 R2"
}
if($sqlVersion -eq '2008' -or $sqlVersion -eq 'ALL'){
    Write-Host "SQL Server 2008 Build Numbers" -ForegroundColor White -BackgroundColor Green
    $sqlArray = $html.all.tags("td") | % innerText | Select-String -Pattern '(SQL Server 2008 Service Pack.*)|(Cumulative update.*for SQL Server 2008)|(Security update.*for SQL Server 2008)|(On-demand hotfix update package.*for SQL Server 2008)|(Security update for the Remote Code Execution vulnerability in SQL Server 2008)|(SQL Server 2008 RTM)'
    SQL-BuildNumbers $sqlArray "2008"
}

#Delete the generated HTML file
#Remove-Item "page.html"
