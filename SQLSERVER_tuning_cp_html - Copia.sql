--- Ricardo 03/09/2021
--- check configuração
--  versão:1
-------------------------------------
use master
go
SET NOCOUNT ON
DECLARE
@sqlMajor INT
,@sqlMinor INT
,@cpuLogicals INT
,@cpuCores INT
,@numaConfig NVARCHAR(60)
,@allocType NVARCHAR(120)
,@stmt NVARCHAR(MAX)
,@paramDef NVARCHAR(500);
-----------------------------  VARIAVEIS PARA HTML  ----------------------
DECLARE @sql VARCHAR(MAX) 
DECLARE @strHTML VARCHAR(MAX) 
DECLARE @dbname VARCHAR(400) 
SET NOCOUNT ON
SET ANSI_WARNINGS off
Declare @Report_Name nvarchar(128) = 'SQL Server Status Report'
 set nocount on
SET ANSI_WARNINGS off
-- Apenas no caso de @@Servername ser null
Declare @Instance nvarchar(128) = ( Select isnull(@@Servername,cast(SERVERPROPERTY('MachineName') as nvarchar(128))+'\'+@@servicename) )
 
-- Obtem número de dias no log doSQL Agent log
Declare @Log_Days_Agent int = 5
 
-- Build uma tabela para report
Declare @SQL_Status_Report table ( Line_Number int NOT NULL identity(1,1),  Information nvarchar(max) )

DECLARE @serverMemory TABLE (SQL_MinMemory_MB BIGINT, SQL_UsedMemory_MB BIGINT, SQL_MaxMemory_MB BIGINT, Server_Physical_MB BIGINT, SQL_AllocationType NVARCHAR(60)
,Available_Physical_Memory_In_MB INT,Total_Page_File_In_MB INT,Available_Page_File_MB INT,Kernel_Paged_Pool_MB INT,Kernel_Nonpaged_Pool_MB INT,System_Memory_State_Desc NVARCHAR(60));


DECLARE @cpuInfo TABLE (VirtualMachineType NVARCHAR(60), NUMA_Config NVARCHAR(60), NUMA_Nodes INT, Physical_CPUs INT
,CPU_Cores INT,licensing VARCHAR(30), Logical_CPUs INT, Logical_CPUs_per_NUMA INT, CPU_AffinityType VARCHAR(60)
,ParallelCostThreshold_Current INT, MAXDOP_Current INT, MAXDOP_Optimal_Value NVARCHAR(60), MAXDOP_Optimal_Reason NVARCHAR(1024));
-- ========================================================================================================================================================================
-- carrega informações do SQL 
SELECT @sqlMajor = CAST((@@MicrosoftVersion / 0x01000000) AS INT), @sqlMinor = CAST((@@MicrosoftVersion / 0x010000 & 0xFF) AS INT);
 
-- ========================================================================================================================================================================
-- carrega informações da CPU 
--
IF @sqlMajor > 12
BEGIN
SELECT @stmt = 'SELECT @numaConfig = softnuma_configuration_desc, @allocType = sql_memory_model_desc FROM sys.dm_os_sys_info;'
,@paramDef = '@numaConfig NVARCHAR(60) OUTPUT, @allocType NVARCHAR(120) OUTPUT';
EXEC sp_executesql @stmt, @paramDef, @numaConfig = @numaConfig OUTPUT, @allocType = @allocType OUTPUT;
END
ELSE
SELECT @numaConfig = 'UNKNOWN', @allocType = 'UNKNOWN';
--
INSERT INTO @cpuInfo (VirtualMachineType, NUMA_Config, NUMA_Nodes, Logical_CPUs, CPU_AffinityType, MAXDOP_Current, ParallelCostThreshold_Current)
VALUES (
(SELECT virtual_machine_type_desc AS VirtualMachineType FROM sys.dm_os_sys_info)
,@numaConfig
,(SELECT COUNT(memory_node_id) FROM sys.dm_os_nodes WHERE memory_node_id < 64)
,(SELECT COUNT(scheduler_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255)
,(SELECT affinity_type_desc AS AffinityType FROM sys.dm_os_sys_info)
,CAST((SELECT [value] FROM sys.configurations WHERE [name] = 'max degree of parallelism') AS INT)
,CAST((SELECT [value] FROM sys.configurations WHERE [name] = 'cost threshold for parallelism') AS INT)
);
--
-- Obtem informações sobre a CPU
IF OBJECT_ID('tempdb..#cpu_output') IS NOT NULL
DROP TABLE #cpu_output;
CREATE TABLE #cpu_output ([output] VARCHAR(255));
 
INSERT INTO #cpu_output ([output]) EXEC xp_cmdshell 'wmic cpu get DeviceId,NumberOfCores,NumberOfLogicalProcessors /format:csv';
-- Exemplo [output]: CLVDODWI01,CPU0,4,8
--
-- Remove as linhas vazias, linha de cabeçalho e CrLf
DELETE FROM #cpu_output WHERE REPLACE(REPLACE(RTRIM(ISNULL([output],'')), CHAR(10), ''), CHAR(13), '') = '';
DELETE FROM #cpu_output WHERE [output] LIKE '%NumberOfCores,NumberOfLogicalProcessors%';
UPDATE #cpu_output SET [output] = REPLACE(REPLACE([output], CHAR(10), ''), CHAR(13), '');
--
--SELECT * FROM #cpu_output;
--
-- carrega informações da CPU cores e logical processors
SELECT @cpuCores = 0, @cpuLogicals = 0;
SELECT @cpuCores += PARSENAME(REPLACE([output], ',', '.'), 2)
,@cpuLogicals += PARSENAME(REPLACE([output], ',', '.'), 1)
FROM #cpu_output;
--
UPDATE @cpuInfo SET Physical_CPUs = (SELECT COUNT(*) FROM #cpu_output), CPU_Cores = @cpuCores, Logical_CPUs = @cpuLogicals;
UPDATE @cpuInfo SET licensing =  
 ( CASE
                 WHEN Physical_CPUs = CPU_Cores THEN  'No licensing changes'
                 ELSE 'licensing costs increase in ' + CONVERT(VARCHAR,Physical_CPUs /CPU_Cores) +' times'
               END )

--
IF OBJECT_ID('tempdb..#cpu_output') IS NOT NULL
DROP TABLE #cpu_output;
--
UPDATE @cpuInfo SET Logical_CPUs_per_NUMA = Logical_CPUs / NUMA_Nodes;
--
-- Calcula a melhor configuração MAXDOP de acordo com as diretrizes de um Microsoft Premier Filed Engineer
-- Hyper-threading enabled: não deve ser 0 e não deve ser maior que a metade do número de processadores lógicos
-- > Processor Affinity set: Should not be more than the number of cores available to the SQL Server instance
-- > Processor Affinity set: não deve ser maior do que o número de núcleos disponíveis para a instância do SQL Server
-- > NUMA:  Não deve ser maior do que o número de núcleos por nó NUMA para evitar que ocorra um dispendioso acesso à memória externa,
--  quando uma task precisa usar memória que não pertence ao seu node NUMA.
--> Genérico: se você não tiver certeza dos valores acima, uma configuração genérica não deve ser superior a 8.
-- Portanto, se você tiver mais de 8 processadores lógicos, deverá definir esse valor para no máximo 8.

UPDATE @cpuInfo
SET
MAXDOP_Optimal_Value = '0 - ' + CAST((CASE WHEN Logical_CPUs > 8 THEN 8 ELSE Logical_CPUs END) AS NVARCHAR)
,MAXDOP_Optimal_Reason = 'GENERIC: Not more than the amount of logical CPUs and not more than 8';
--
UPDATE @cpuInfo
SET
MAXDOP_Optimal_Value = '0 - assigned cores to the SQL Server instance'
,MAXDOP_Optimal_Reason = 'CPU AFFINITY: Not more than the amount of assigned CPUs to the SQL Server instance'
WHERE CPU_AffinityType = 'MANUAL';
--
UPDATE @cpuInfo
SET
MAXDOP_Optimal_Value = '1 - ' + CAST(Logical_CPUs_per_NUMA AS NVARCHAR)
,MAXDOP_Optimal_Reason = 'NUMA NODES: Not 0 and not more than the number of cores per NUMA node'
WHERE NUMA_Nodes > 1;
--
UPDATE @cpuInfo
SET
MAXDOP_Optimal_Value = '1 - ' + CAST((Logical_CPUs / 2) AS NVARCHAR)
,MAXDOP_Optimal_Reason = 'HYPER-THREADING: Not 0 and not be greater than half the number of logical processors'
WHERE Logical_CPUs / 2 = CPU_Cores;
--
-- ========================================================================================================================================================================
-- carrega informações da Memoria

INSERT INTO @serverMemory (SQL_MinMemory_MB, SQL_UsedMemory_MB, SQL_MaxMemory_MB, Server_Physical_MB, SQL_AllocationType,
Available_Physical_Memory_In_MB ,Total_Page_File_In_MB ,Available_Page_File_MB ,Kernel_Paged_Pool_MB ,Kernel_Nonpaged_Pool_MB,System_Memory_State_Desc )
VALUES (
CAST((SELECT [value] FROM sys.configurations WHERE [name] = 'min server memory (MB)') AS BIGINT)
,(SELECT cntr_value / 1024 FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Server Memory (KB)')
,CAST((SELECT [value] FROM sys.configurations WHERE [name] = 'max server memory (MB)') AS BIGINT)
,(SELECT (total_physical_memory_kb / 1024) AS total_physical_memory_mb FROM sys.dm_os_sys_memory)
,@allocType
,CAST((SELECT [available_page_file_kb] / 1024  FROM [master].[sys].[dm_os_sys_memory]) AS INT)
,CAST((SELECT [total_page_file_kb] / 1024  FROM [master].[sys].[dm_os_sys_memory]) AS INT)
,CAST((SELECT [available_page_file_kb] / 1024  FROM [master].[sys].[dm_os_sys_memory]) AS INT)
,CAST((SELECT [kernel_paged_pool_kb] / 1024  FROM [master].[sys].[dm_os_sys_memory]) AS INT)
,CAST((SELECT [kernel_nonpaged_pool_kb] / 1024  FROM [master].[sys].[dm_os_sys_memory]) AS INT)
,CAST((SELECT [system_memory_state_desc]  FROM [master].[sys].[dm_os_sys_memory]) AS varchar(40))
);

-----------------Print header do relatorio -------------------- 

SELECT @strHTML = '<HTML><HEAD><TITLE> Healt check </TITLE><STYLE>TD.Sub{FONT-WEIGHT:bold;BORDER-BOTTOM: 0pt solid #000000;BORDER-LEFT: 1pt solid #000000;BORDER-RIGHT: 0pt solid #000000;BORDER-TOP: 0pt solid #000000; FONT-FAMILY: Tahoma;FONT-SIZE: 8pt} BODY{FONT-FAMILY: Tahoma;FONT-SIZE: 8pt} TABLE{BORDER-BOTTOM: 1pt solid #000000;BORDER-LEFT: 0pt solid #000000;BORDER-RIGHT: 1pt solid #000000;BORDER-TOP: 0pt solid #000000; FONT-FAMILY: Tahoma;FONT-SIZE: 8pt} TD{BORDER-BOTTOM: 0pt solid #000000;BORDER-LEFT: 1pt solid #000000;BORDER-RIGHT: 0pt solid #000000;BORDER-TOP: 1pt solid #000000; FONT-FAMILY: Tahoma;FONT-SIZE: 8pt} TD.Title{FONT-WEIGHT:bold;BORDER-BOTTOM: 0pt solid #000000;BORDER-LEFT: 1pt solid #000000;BORDER-RIGHT: 0pt solid #000000;BORDER-TOP: 1pt solid #000000; FONT-FAMILY: Tahoma;FONT-SIZE: 12pt} A.Index{FONT-WEIGHT:bold;FONT-SIZE:8pt;COLOR:#000099;FONT-FAMILY:Tahoma;TEXT-DECORATION:none} A.Index:HOVER{FONT-WEIGHT:bold;FONT-SIZE:8pt;COLOR:#990000;FONT-FAMILY:Tahoma;TEXT-DECORATION:none}</STYLE></HEAD><BODY><A NAME="_top"></A><BR>' 
PRINT @strHTML 
-------------------------------------------------------------
SELECT @strHTML = '<BR><CENTER><FONT SIZE="5"><B>  ' + @sql+'</B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
-------------------------------------TIVIT - STATUS INSTANCIA-------------------------
SELECT @sql='TIVIT - STATUS INSTANCIA '+  @Instance +' at '+cast(getdate() as nvarchar(28))
PRINT '<tr bgcolor=#FFEFD8><td CLASS="Title" COLSPAN="1" ALIGN="center"><B><A NAME="_LoginInfomration"> ' + @sql+ '</A></B> </TD></TR>' 
------------------------------------ActiveNode---------------------------
SELECT @sql='ActiveNode : '+ cast(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as nvarchar(1024))
 SELECT @strHTML = '<TR><TD><B>' +@sql+ '</B> </TD>' +   '</TR>'
 PRINT @strHTML
 --------------------------------Versão-------------------------------
 SELECT @sql='Versão : '+ @@version 
 SELECT @strHTML = '<TR><TD><B>' + @sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
----------------------------------------------------------------
 SELECT @sql='Instancia:' + @@servername
 SELECT @strHTML = '<TR><TD><B>' +  @sql + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
----------------------------------Hostname------------------------------
 SELECT @sql='Hostname : ' +host_name()
 SELECT @strHTML = '<TR><TD><B>' + @sql   + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
---------------------------------Bancos no Ar a-------------------------------
SELECT @sql ='Bancos no Ar a ' + Cast(datediff(mi, login_time, getdate()) /60 as VarChar) + ' Horas' 
FROM master..sysprocesses WHERE spid = 1
SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
---------------------------------Database_Status-----------------------------
SELECT @sql ='Database_Status : '+convert(char(15),DatabasePropertyEx(name,'Status'))   from sysdatabases
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
---------------------------------Instance_Name-----------------------------
SELECT @sql ='Instance_Name : '+convert(char(20),SERVERPROPERTY('servername')) from sysprocesses where spid = 1
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
---------------------------------------------------------------
 -- Get the last restart date and time from sqlserver_start_time
SELECT @sql =  'Start time :' + cast(sqlserver_start_time as nvarchar (28)) FROM sys.dm_os_sys_info
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	

---------------------------Single User Mode-----------------------------------
select @sql =
CASE
	WHEN SERVERPROPERTY('IsSingleUser') = 1 THEN 
	  'Single User Mode : Yes'
	WHEN SERVERPROPERTY('IsSingleUser') = 0 THEN 
	  'Single User Mode : No'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
------------------------------Clustered--------------------------------
select @sql =
CASE
	WHEN  SERVERPROPERTY('isclustered') = 1 THEN 
	  'Clustered : Yes'
	WHEN SERVERPROPERTY('IsSingleUser') = 0 THEN 
	  'Clustered : No'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------AlwaysOn--------------------------------
select @sql =
CASE
	WHEN  SERVERPROPERTY('IsHadrEnabled') = 1 THEN 
	  'AlwaysOn : Yes'
	WHEN SERVERPROPERTY('IsSingleUser') = 0 THEN 
	  'AlwaysOn : No'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------Instance : Default--------------------------------
select @sql =
CASE
	WHEN SERVERPROPERTY('instancename') IS null THEN 
	  'Instance : Default'
	WHEN SERVERPROPERTY('IsSingleUser') = 0 THEN 
	  'AlwaysOn : Nomeada'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-------------------------------------------------------------
SELECT @sql ='SQL_Edition : '+convert(char(30),SERVERPROPERTY('edition')) from sysprocesses where spid = 1
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-------------------------------------------------------------
SELECT @sql ='SQL_Version : '+convert(char(30),SERVERPROPERTY('productversion')) from sysprocesses where spid = 1
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-------------------------------------------------------------
SELECT @sql ='SQL_ServicePack : '+convert(char(20),SERVERPROPERTY('productlevel')) from sysprocesses where spid = 1
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
--------------------- Windows Info ---------------------------------------
SELECT @sql = 'Windows_release : '+windows_release FROM sys.dm_os_windows_info WITH (NOLOCK) OPTION (RECOMPILE);
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------windows_service_pack_level --------------------------
SELECT @sql = 'windows_service_pack_level : '+ windows_service_pack_level FROM sys.dm_os_windows_info WITH (NOLOCK) OPTION (RECOMPILE);
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------windows_sku  --------------------------
SELECT @sql = 'windows_sku : '+ CONVERT(VARCHAR,windows_sku )FROM sys.dm_os_windows_info WITH (NOLOCK) OPTION (RECOMPILE);
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------os_language_version  --------------------------
SELECT @sql = 'os_language_version : '+ CONVERT(VARCHAR,os_language_version) FROM sys.dm_os_windows_info WITH (NOLOCK) OPTION (RECOMPILE);
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------'Default_Codpage  --------------------------
SELECT @sql = 'Default_Codpage: '+convert(varchar(10), collationproperty(convert (varchar(30),
	(select SERVERPROPERTY('collation'))), 'CodePage'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------Default_Collation  --------------------------
SELECT @sql = 'Default_Collation: '+convert(varchar(50),serverproperty('collation'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
-----------------------------------Default_Collation  --------------------------
SELECT @sql = 'Caracteres SQL da ordenação: '+convert(varchar(50),serverproperty('SqlCharSetName'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 

-----------------------------------Default_Collation  --------------------------
 DECLARE @sp_helpsort TABLE (
    [c_val] [varchar](128) NULL
    )
 
 INSERT INTO @sp_helpsort
exec sp_helpsort;

 SELECT @sql = 'Server default collation: '+ [c_val] from @sp_helpsort
  SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
 -----------------------------------Default_Collation  --------------------------

SELECT @sql =  'Sort Order: '+convert(varchar(50),serverproperty('SqlSortOrderName'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 

 -----------------------------modo de segurança integrado--------------------------------
select @sql =
CASE
	WHEN SERVERPROPERTY('IsIntegratedSecurityOnly') =1 THEN 
	  'Modo de segurança  : Autenticação do Windows'
	WHEN SERVERPROPERTY('IsIntegratedSecurityOnly') = 0 THEN 
	  'Modo de segurança : Autenticação do Windows e Autenticação do SQL Server'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------instância do SQL Server Express LocalDB--------------------------------
select @sql =
CASE
	WHEN SERVERPROPERTY('IsLocalDB') IS null THEN 
	  'instância do SQL Server Express LocalDB : N/A'
	WHEN SERVERPROPERTY('IsLocalDB') = 0 THEN 
	  'instância do SQL Server Express LocalDB : Yes'
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------instância do SQL Server Express LocalDB--------------------------------
select @sql =
CASE
	WHEN SERVERPROPERTY('ProductBuildType') IS null THEN 
	  'Tipo de build : N/A'
	ELSE
	  'Tipo de build :'+convert(varchar(50), SERVERPROPERTY('ProductBuildType'))
END 
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	

-----------------------------Type Licença--------------------------------
select @sql =
  	CASE SERVERPROPERTY('LicenseType')
		WHEN 'PER_SEAT' THEN '[10.6] Tipo Licença: PER SEAT'
		WHEN 'PER_PROCESSOR' THEN '[10.6] Tipo Licença: PER-PROCESSOR'
		WHEN 'DISABLED' THEN '[10.6] Tipo Licença: DISABLED'
	END
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------QTDE LICENCAS--------------------------------
select @sql =
  	'Qtde Lincenças [10.7] : '+CONVERT(VARCHAR, ISNULL(SERVERPROPERTY('NumLicenses'), 'NA'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	

-----------------------------ULTIMO UPDATE RESOURCE [10.9]S--------------------------------
select @sql ='Ultimo update Resource [10.9] : '+CONVERT(VARCHAR, ISNULL(SERVERPROPERTY('ResourceLastUpdateDateTime'), 'NA'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
-----------------------------VERSAO RESOURCE [10.10]--------------------------------
select @sql ='Versão Resource [10.10] : '+CONVERT(VARCHAR, ISNULL(SERVERPROPERTY('ResourceVersion'), 'NA'))
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML	
----------------------------------------------------------------------------------------------
SET @strHTML = '' 

PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="60%">' 
-------------------------------------------------------------

SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  Sql Server - CPU </B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 


SELECT @strHTML=''
SELECT @strHTML = N'<table>' +
N'<tr><th>[VirtualMachineType]</th>
<th>[NUMA_Config]</th>
<th>[Physical_CPUs]</th>
<th>[CPU_Cores]</th>
<th>[licensing]</th>
<th>[Logical_CPUs]</th>
<th>[Logical_CPUs_per_NUMA]</th>
<th>[CPU_AffinityType]</th>
</tr>' +
CAST ( (
SELECT td = [VirtualMachineType],'',
td =[NUMA_Config],'',
td =[Physical_CPUs],'',
td =[CPU_Cores],'',
td =[licensing],'',
td =[Logical_CPUs],'',
td =[Logical_CPUs_per_NUMA],'',
td =[CPU_AffinityType],'' 
FROM @cpuInfo
--ORDER BY [SpecialOfferID]
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML

-------------------------------------------------------------
--SELECT ParallelCostThreshold_Current, MAXDOP_Current, MAXDOP_Optimal_Value, MAXDOP_Optimal_Reason FROM @cpuInfo;

SELECT @strHTML=''

SELECT @strHTML = N'<table>' +
N'<tr><th>[ParallelCostThreshold_Current]</th>
<th>[MAXDOP_Current]</th>
<th>[MAXDOP_Optimal_Value]</th>
<th>[MAXDOP_Optimal_Reason]</th>
</tr>' +
CAST ( (
SELECT td = ParallelCostThreshold_Current,'',
td =MAXDOP_Current,'',
td =MAXDOP_Optimal_Value,'',
td =MAXDOP_Optimal_Reason,''
FROM @cpuInfo
--ORDER BY [SpecialOfferID]
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML
------------------------------------------------------------------------------------
---------------------------------CONFIGURAÇÕES - MEMÓRIA----------------------------
---SELECT * FROM @serverMemory;
SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  SQL Server - Memory </B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 

SELECT @strHTML=''
-- Query the data only if there are rows: 

  SELECT @strHTML = N'<table>' +
N'<tr><th>[SQL_MinMemory_MB]</th>
<th>[SQL_UsedMemory_MB]</th>
<th>[SQL_MaxMemory_MB]</th>
<th>[Server_Physical_MB]</th>
<th>[SQL_AllocationType]</th>
<th>[Available_Physical_Memory_In_MB]</th>
<th>[Total_Page_File_In_MB]</th>
<th>[Available_Page_File_MB]/th>
<th>[Kernel_Paged_Pool_MB]</th>
<th>[Kernel_Nonpaged_Pool_MB]</th>
<th>[System_Memory_State_Desc]</th>
</tr>' +
CAST ( (
SELECT td = SQL_MinMemory_MB,'',
td =SQL_UsedMemory_MB,'',
td =SQL_MaxMemory_MB,'',
td =Server_Physical_MB,'',
td =SQL_AllocationType,'',
td =Available_Physical_Memory_In_MB,'',
td =Total_Page_File_In_MB,'',
td =Available_Page_File_MB,'',
td =Kernel_Paged_Pool_MB,'',
td =Kernel_Nonpaged_Pool_MB,'',
td =System_Memory_State_Desc,'' 
FROM @serverMemory
--ORDER BY [SpecialOfferID]
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML
/* SQL Server componentes instalados         */

SET NOCOUNT ON
SET ANSI_WARNINGS off
/* ------------------------------------------ Inital Setup -----------------------------------------------------*/
CREATE TABLE #RegResult
(
ResultValue NVARCHAR(4)
)
CREATE TABLE #ServicesServiceStatus /*Create temp tables*/
(
RowID INT IDENTITY(1,1)
,ServerName NVARCHAR(128)
,ServiceName NVARCHAR(128)
,ServiceStatus varchar(128)
,StatusDateTime DATETIME DEFAULT (GETDATE())
,PhysicalSrverName NVARCHAR(128)
)
DECLARE
@ChkInstanceName nvarchar(128) /*Stores SQL Instance Name*/
,@ChkSrvName nvarchar(128) /*Stores Server Name*/
,@TrueSrvName nvarchar(128) /*Stores where code name needed */
,@SQLSrv NVARCHAR(128) /*Stores server name*/
,@PhysicalSrvName NVARCHAR(128) /*Stores physical name*/
,@FTS nvarchar(128) /*Stores Full Text Search Service name*/
,@RS nvarchar(128) /*Stores Reporting Service name*/
,@SQLAgent NVARCHAR(128) /*Stores SQL Agent Service name*/
,@OLAP nvarchar(128) /*Stores Analysis Service name*/
,@REGKEY NVARCHAR(128) /*Stores Registry Key information*/
SET @PhysicalSrvName = CAST(SERVERPROPERTY('MachineName') AS VARCHAR(128))
SET @ChkSrvName = CAST(SERVERPROPERTY('INSTANCENAME') AS VARCHAR(128))
SET @ChkInstanceName = @@serverName
IF @ChkSrvName IS NULL /*Detect default or named instance*/
BEGIN
SET @TrueSrvName = 'MSQLSERVER'
SELECT @OLAP = 'MSSQLServerOLAPService' /*Setting up proper service name*/
SELECT @FTS = 'MSFTESQL'
SELECT @RS = 'ReportServer'
SELECT @SQLAgent = 'SQLSERVERAGENT'
SELECT @SQLSrv = 'MSSQLSERVER'
END
ELSE
BEGIN
SET @TrueSrvName = CAST(SERVERPROPERTY('INSTANCENAME') AS VARCHAR(128))
SET @SQLSrv = '$'+@ChkSrvName
SELECT @OLAP = 'MSOLAP' + @SQLSrv /*Setting up proper service name*/
SELECT @FTS = 'MSFTESQL' + @SQLSrv
SELECT @RS = 'ReportServer' + @SQLSrv
SELECT @SQLAgent = 'SQLAgent' + @SQLSrv
SELECT @SQLSrv = 'MSSQL' + @SQLSrv
END
/* ---------------------------------- SQL Server Service Section ----------------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\'+@SQLSrv
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of SQL Sever service*/
EXEC xp_servicecontrol N'QUERYSTATE',@SQLSrv
UPDATE #ServicesServiceStatus set ServiceName = 'MS SQL Server Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'MS SQL Server Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- SQL Server Agent Service Section -----------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\'+@SQLAgent
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of SQL Agent service*/
EXEC xp_servicecontrol N'QUERYSTATE',@SQLAgent
UPDATE #ServicesServiceStatus set ServiceName = 'SQL Server Agent Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'SQL Server Agent Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- SQL Browser Service Section ----------------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\SQLBrowser'
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of SQL Browser Service*/
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE',N'sqlbrowser'
UPDATE #ServicesServiceStatus set ServiceName = 'SQL Browser Service - Instance Independent' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'SQL Browser Service - Instance Independent' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- Integration Service Section ----------------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\MsDtsServer'
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of Intergration Service*/
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE',N'MsDtsServer'
UPDATE #ServicesServiceStatus set ServiceName = 'Intergration Service - Instance Independent' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'Intergration Service - Instance Independent' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- Reporting Service Section ------------------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\'+@RS
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of Reporting service*/
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE',@RS
UPDATE #ServicesServiceStatus set ServiceName = 'Reporting Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'Reporting Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- Analysis Service Section -------------------------------------------------*/
IF @ChkSrvName IS NULL /*Detect default or named instance*/
BEGIN
SET @OLAP = 'MSSQLServerOLAPService'
END
ELSE
BEGIN
SET @OLAP = 'MSOLAP'+'$'+@ChkSrvName
SET @REGKEY = 'System\CurrentControlSet\Services\'+@OLAP
END
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of Analysis service*/
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE',@OLAP
UPDATE #ServicesServiceStatus set ServiceName = 'Analysis Services' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'Analysis Services' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
/* ---------------------------------- Full Text Search Service Section -----------------------------------------*/
SET @REGKEY = 'System\CurrentControlSet\Services\'+@FTS
INSERT #RegResult ( ResultValue ) EXEC master.sys.xp_regread @rootkey='HKEY_LOCAL_MACHINE', @key=@REGKEY
IF (SELECT ResultValue FROM #RegResult) = 1
BEGIN
INSERT #ServicesServiceStatus (ServiceStatus) /*Detecting staus of Full Text Search service*/
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE',@FTS
UPDATE #ServicesServiceStatus set ServiceName = 'Full Text Search Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
ELSE
BEGIN
INSERT INTO #ServicesServiceStatus (ServiceStatus) VALUES ('NOT INSTALLED')
UPDATE #ServicesServiceStatus set ServiceName = 'Full Text Search Service' where RowID = @@identity
UPDATE #ServicesServiceStatus set ServerName = @TrueSrvName where RowID = @@identity
UPDATE #ServicesServiceStatus set PhysicalSrverName = @PhysicalSrvName where RowID = @@identity
TRUNCATE TABLE #RegResult
END
--------------------------------------------------------------------------------------------------
SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  SQL Server Components Check  </B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
sELECT @strHTML=''
-- Query the data only if there are rows: 
print  @strHTML
  SELECT @strHTML = N'<table>' +
N'<tr><th>[Physical Server Name]</th>
<th>[SQL Instance Name]</th>
<th>[SQL Server Services]</th>
<th>[Current Service Service Status]</th>
<th>[Date/Time Service Status Checked]</th>
</tr>' +
CAST ( (
SELECT td = PhysicalSrverName,'',
td =ServerName,'',
td =ServiceName,'',
td =ServiceStatus,'',
td =StatusDateTime,''
FROM #ServicesServiceStatus
--ORDER BY [SpecialOfferID]
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML

DROP TABLE #ServicesServiceStatus /*Perform cleanup*/
DROP TABLE #RegResult

/* ---------------------------------------SQL Server Services Inf------------------------------------*/
SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B> SQL Server Services Inf</FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
sELECT @strHTML='' 
 SELECT @strHTML = N'<table>' +
N'<tr><th>[servicename]</th>
<th>[startup_type_desc]</th>
<th>[status_desc]</th>
<th>[last_startup_time]</th>
<th>[service_account]</th>
<th>[filename]</th>
</tr>' +
CAST ( (
SELECT     td =  servicename,'',
           td =  startup_type_desc,'',
           td =  status_desc,'',
           td =  isnull(last_startup_time,''),'',
           td =  service_account,'',
           td =  [filename],''
FROM sys.dm_server_services WITH (NOLOCK) 
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML
print ' '
 ------------------------------------------------------------------------------------------------------
SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  SQL Server Portas</FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
sELECT @strHTML=''
-- Query the data only if there are rows: 

  SELECT @strHTML = N'<table>' +
N'<tr><th>[Name]</th>
<th>[endpoint_id]</th>
<th>[principal_id]</th>
<th>[protocol]</th>
<th>[protocol_desc]</th>
<th>[local_net_address]</th>
<th>[local_tcp_port]</th>
<th>[type]</th>
<th>[type_desc]</th>
<th>[state]</th>
<th>[state_desc]</th>
<th>[is_admin_endpoint]</th>
</tr>' +
CAST ( (
SELECT     td =  e.name,'',
           td =  e.endpoint_id,'',
           td =  e.principal_id,'',
           td =  e.protocol,'',
           td =  e.protocol_desc,'',
           td =  isnull(ec.local_net_address,''),'',
           td =  isnull(ec.local_tcp_port,''),'',
           td =  e.[type],'',
           td =  e.type_desc,'',
           td =  e.[state],'',
           td =  e.state_desc,'',
           td =  e.is_admin_endpoint,''
FROM        sys.endpoints e 
            LEFT OUTER JOIN sys.dm_exec_connections ec
                ON ec.endpoint_id = e.endpoint_id
GROUP BY    e.name,
            e.endpoint_id,
            e.principal_id,
            e.protocol,
            e.protocol_desc,
            ec.local_net_address,
            ec.local_tcp_port,
            e.[type],
            e.type_desc,
            e.[state],
            e.state_desc,
            e.is_admin_endpoint 

FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML
print ' '
-------------------------------------- Encontra PATHS do SQL-------------------------------------
Set nocount on
--- DECLARA AS VARIAVEIS
declare @tblpaths table ([PROPERTY]	varchar (100),
			[PATH]		varchar (200))

declare @returncode	int,
	@instancename	varchar (100),
	@path		nvarchar(4000)

--- ENCONTRA O DATA PATH
exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\mssqlserver',N'defaultdata', @path output, 'no_output'

if @path is null
begin
	exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\setup',N'sqldataroot', @path output, 'no_output'
	set @path = @path + '\data'
	insert into @tblpaths ([PROPERTY], [PATH])
	select 'Database Data Directory', @path
end
else
	begin
	insert into @tblpaths ([PROPERTY], [PATH])
		select 'Database Data Directory',  @path
end
------------------------------ ENCONTRA O DATA PATH --------------------------------

exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\mssqlserver',N'defaultlog', @path output, 'no_output'

if @path is null
begin
	exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\setup',N'sqldataroot', @path output, 'no_output'
	set @path = @path + '\data'
	insert into @tblpaths ([PROPERTY], [PATH])
	select 'Database Log Directory', @path
end
else
begin
	insert into @tblpaths ([PROPERTY], [PATH])
	select 'Database Log Directory', @path
end

--- ENCONTRA O BINN PATH
exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\setup',N'sqlbinroot', @path output, 'no_output'

insert into @tblpaths ([PROPERTY], [PATH])
select 'Binn Directory', @path

------------------------------ ENCONTRA O BACKUP PATH ----------------------------------
exec @returncode = master.dbo.xp_instance_regread N'hkey_local_machine',N'software\microsoft\mssqlserver\mssqlserver',N'backupdirectory', @path output, 'no_output'
insert into @tblpaths ([PROPERTY], [PATH])
select 'Backup Directory', @path

SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  PATHS - SQL Server  </B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
sELECT @strHTML=''

print  @strHTML
  SELECT @strHTML = N'<table>' +
N'<tr><th>[PROPERTY]</th>
<th>[PATH]</th>
</tr>' +
CAST ( (
SELECT td = [PROPERTY],'',
td =[PATH],''
FROM @tblpaths
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML
print ' '

  SELECT @strHTML = N'<table>' +
N'<tr><th>[DB_name]</th>
<th>[name]</th>
<th>[physical_name]</th>
<th>[Total Size in MB]</th>
</tr>' +
CAST ( (
  SELECT 
  td = DB_NAME([database_id]),'', 
  td =name,'', 
  td =physical_name, '', 
   td=CONVERT(bigint, size/128.0) ,'' 
FROM sys.master_files 
WHERE[database_id] <=3 
AND [database_id] <> 32767
FOR XML PATH('tr'), TYPE
) AS NVARCHAR(MAX) ) +
N'</table>'

print @strHTML

--------------------------------SQL Server instance startup parameters ----------------------------------------
SELECT @strHTML = '<BR><CENTER><FONT SIZE="1"><B>  SQL Server instance startup parameters  </B></FONT></CENTER><BR>' 
PRINT @strHTML 
PRINT '<DIV ALIGN="center"><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" BORDERCOLOUR="003366" WIDTH="100%">' 
sELECT @strHTML=''

--- DECLARA AS VARIAVEIS
declare @parameters table ([PROPERTY]	varchar (10),			[PATH]		nvarchar (120))

insert into @parameters ([PROPERTY], [PATH])
	SELECT DSR.value_name,cast(DSR.value_data as nvarchar(100)) FROM sys.dm_server_registry AS DSR
	where DSR.registry_key LIKE N'%MSSQLServer\Parameters'
-------------------------------------------------------------
SELECT @sql ='SQLArg0 : '+[PATH]  from @parameters where [PROPERTY]='SQLArg0'
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 
SELECT @sql ='SQLArg1 : '+[PATH]  from @parameters where [PROPERTY]='SQLArg1'
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
 PRINT @strHTML
SELECT @sql ='SQLArg2 : '+[PATH]  from @parameters where [PROPERTY]='SQLArg2'
 SELECT @strHTML = '<TR><TD><B>' +@sql  + '</B> </TD>' +   '</TR>'
PRINT @strHTML 






