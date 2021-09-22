Import-Module SQLPS

Get-Content "C:\temp\Settings.ini" | foreach-object -begin {$h=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $h.Add($k[0], $k[1]) } }
$server        = $h.Get_Item("centralServer")
$inventoryDB   = $h.Get_Item("inventoryDB")

#Beginning of email logic
$sqlCommand = "
DECLARE @emailSubject VARCHAR(255),
        @textTitle    VARCHAR(255),
        @tableHTML    NVARCHAR(MAX)

SELECT @emailSubject = 'New SQL Server Patches released',
       @textTitle    = ''

SET @tableHTML = '
    <html>
        <head>
            <style>' +
                'td {border: solid black 0.5px;padding-left:5px;padding-right:5px;padding-top:1px;padding-bottom:1px;font-size:11pt;} ' +
            '</style>
        </head>
        <body>' +
            '<div style=''margin-top:20px; margin-left:5px; margin-bottom:15px; font-weight:bold; font-size:1.3em; font-family:calibri;''>' + @textTitle + '</div>' +
            '<div style=''margin-left:50px; font-family:Calibri;''>
             <table cellpadding=0 cellspacing=0 border=0>' +
                '<tr bgcolor=#89CFF0>' +
                     '<td align=center><font face=''calibri'' color=White><b>SQL Version</b></font></td>' +    
                     '<td align=center><font face=''calibri'' color=White><b>Service Pack</b></font></td>' +     
                     '<td align=center><font face=''calibri'' color=White><b>Build Number</b></font></td>' +
                     '<td align=center><font face=''calibri'' color=White><b>Release Date</b></font></td>
                 </tr>'  

DECLARE @body VARCHAR(MAX);

WITH BuildNumbers_CTE
AS(
    SELECT TOP 1000
	    CASE
            	WHEN LEFT(t.build_number,4) = '15.0' THEN 'SQL Server 2019'
            	WHEN LEFT(t.build_number,4) = '14.0' THEN 'SQL Server 2017'
            	WHEN LEFT(t.build_number,4) = '13.0' THEN 'SQL Server 2016'
            	WHEN LEFT(t.build_number,4) = '12.0' THEN 'SQL Server 2014'
            	WHEN LEFT(t.build_number,4) = '11.0' THEN 'SQL Server 2012'
            	WHEN LEFT(t.build_number,4) = '10.5' THEN 'SQL Server 2008R2'
            	WHEN LEFT(t.build_number,4) = '10.0' THEN 'SQL Server 2008'
            	WHEN LEFT(t.build_number,4) = '9.0' THEN 'SQL Server 2005'
            END AS 'Version',
	    CASE 
		    WHEN t.cu IS NULL THEN t.sp
		    ELSE CONCAT(t.sp,'-',t.cu)
	    END AS 'SP',
	    t.build_number AS 'BuildNumber',
	    t.release_date AS 'ReleaseDate'
    FROM tmpBuildNumbers t
    WHERE t.build_number NOT IN (SELECT build_number FROM inventory.MSSQLBuildNumbers)
    ORDER BY [Version]
)

SELECT @body =
(
   SELECT ROW_NUMBER() over(order by Version) % 2 as TRRow,
          td = Version,     
          td = SP,      
          td = BuildNumber,
          td = ReleaseDate       
   FROM BuildNumbers_CTE
   FOR XML raw('tr'), ELEMENTS
)

SET @body = REPLACE(@body, '<td>', '<td align=center><font face=''calibri''>')
SET @body = REPLACE(@body, '</td>', '</font></td>')
SET @body = REPLACE(@body, '_x0020_', space(1))
SET @body = REPLACE(@body, '_x003D_', '=')
SET @body = REPLACE(@body, '<tr><TRRow>0</TRRow>', '<tr bgcolor=#F8F8FD>')
SET @body = REPLACE(@body, '<tr><TRRow>1</TRRow>', '<tr bgcolor=#EEEEF4>')
SET @body = REPLACE(@body, '<TRRow>0</TRRow>', '')

SET @tableHTML = @tableHTML + @body + '</table></div></body></html>'

SET @tableHTML = '<div style=''color:Black; font-size:11pt; font-family:Calibri;''>' + @tableHTML + '</div>'
           
exec msdb.dbo.sp_send_dbmail
   @profile_name = 'ProfileName',
   @recipients = 'xxxx@yyyy.com',
   @body = @tableHTML,
   @subject = @emailSubject,
   @body_format = 'HTML' 
"

Invoke-Sqlcmd -Query $sqlCommand -Database $inventoryDB -ServerInstance $server
 
Write-Host "Done!"