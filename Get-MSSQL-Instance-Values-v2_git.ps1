# Create a PSCredential Object using the "User" and "Password" parameters that you passed to the job
# Ensure the build fails if there is a problem.
# The build will fail if there are any errors on the remote machine too!
$ErrorActionPreference = 'Stop'

 # Create a PSCredential Object using the "User" and "Password" parameters that you passed to the job
$SecurePassword = $env:password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:user, $SecurePassword

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

#if ($h.Get_Item("username").length -gt 0 -and $h.Get_Item("password").length -gt 0) {
#    $username   = $h.Get_Item("username")
#    $password   = $h.Get_Item("password")
#}
Write-Host $instance
Write-Host $cred
#Função para executar as consultas (dependendo se o usuário usará credenciais específicas ou não) 
function Execute-Query([string]$query,[string]$database,[string]$instance,[int]$trusted){
    if($trusted -eq 1){ 
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Credential $cred -ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-Instance-Values','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop
        }
    }
    else{
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Username -Credential $cred -ErrorAction Stop
        }
        catch{
            [string]$message = $_
            $errorQuery = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($instance)'),'Get-MSSQL-Instance-Values','"+$message.replace("'","''")+"',GETDATE())"
            Invoke-Sqlcmd -Query $errorQuery -Database $inventoryDB -ServerInstance $server -Credential $cred -ErrorAction Stop
        }
    }
}

#################################
#Criação de tabelas de catálogo #
#################################

#SQL Server Editions
$sqlEditionsTableQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLEditions]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE [inventory].[MSSQLEditions](
	[mssql_edition_id] [int] NOT NULL IDENTITY(1,1) PRIMARY KEY,
	[edition]          [nvarchar](128) NOT NULL
) ON [PRIMARY]

INSERT INTO [inventory].[MSSQLEditions] VALUES
('Express Edition'),('Web Edition'),('Standard Edition'),('Enterprise Edition'),('Business Intelligence Edition'),('Developer Edition'),('Enterprise Evaluation Edition');

END
"
Execute-Query $sqlEditionsTableQuery $inventoryDB $server 1

#SQL Server Versions
$sqlVersionsTableQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLVersions]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE [inventory].[MSSQLVersions](
	[mssql_version_id] [int] NOT NULL IDENTITY(1,1) PRIMARY KEY,
	[version]          [nvarchar](64) NOT NULL
) ON [PRIMARY]

INSERT INTO [inventory].[MSSQLVersions] VALUES
('SQL Server 2005'),
('SQL Server 2008'),
('SQL Server 2008 R2'),
('SQL Server 2012'),
('SQL Server 2014'),
('SQL Server 2016'),
('SQL Server 2017'),
('SQL Server 2019');
END
"
Execute-Query $sqlVersionsTableQuery $inventoryDB $server 1

#SQL Server BuildNumbers
# Os inseerts para esta tabela estão em um arquivo .sql separado para que este script não fique muito saturado.
$sqlBuildNumbersTableQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLBuildNumbers]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE inventory.MSSQLBuildNumbers(
    [mssql_build_number_id] [int] NOT NULL IDENTITY PRIMARY KEY,
    [sp]                    [nvarchar](5) NULL,
    [cu]                    [nvarchar](5) NULL,
    [extra]                 [nvarchar](5) NULL,
    [build_number]          [nvarchar](16) NULL,
    [release_date]          [date] NULL
) ON [PRIMARY]
SELECT 1
END
ELSE
SELECT 0
"
$result = Execute-Query $sqlBuildNumbersTableQuery $inventoryDB $server 1

########################################
#Criação/verificação de funções úteis  # 
########################################
#O objetivo principal dessas funções é  #
#simplificar a gravação de vários       #
#queries que apresentam informações das #
#tabelas do catálogo.                   #
########################################
$fnGetBuildNumberIdCheck = "
IF OBJECT_ID('inventory.get_MSSQLBuildNumberId') IS NOT NULL
DROP FUNCTION inventory.get_MSSQLBuildNumberId
"
Execute-Query $fnGetBuildNumberIdCheck $inventoryDB $server 1

$fnGetBuildNumberIdCreate = "
CREATE FUNCTION [inventory].[get_MSSQLBuildNumberId]
(@buildNumber NVARCHAR(32))
RETURNS SMALLINT
AS
BEGIN
    DECLARE @buildNumberID INT;
    SELECT @buildNumberID = mssql_build_number_id FROM inventory.MSSQLBuildNumbers WHERE build_number = @buildNumber;
    RETURN @buildNumberID;
END
"
Execute-Query $fnGetBuildNumberIdCreate $inventoryDB $server 1

$fnGetInstanceIdCheck = "
IF OBJECT_ID('inventory.get_InstanceId') IS NOT NULL
DROP FUNCTION inventory.get_InstanceId
"
Execute-Query $fnGetInstanceIdCheck $inventoryDB $server 1

$fnGetInstanceIdCreate = "
CREATE FUNCTION [inventory].[get_InstanceId]
(@instance NVARCHAR(255))
RETURNS INT
AS
BEGIN
    DECLARE @serverId INT;
    SELECT @serverId = serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = @instance;
    RETURN @serverId;
END
"
Execute-Query $fnGetInstanceIdCreate $inventoryDB $server 1

$fnGetMSSQLEditionIdCheck = "
IF OBJECT_ID('inventory.get_MSSQLEditionId') IS NOT NULL
DROP FUNCTION inventory.get_MSSQLEditionId
"
Execute-Query $fnGetMSSQLEditionIdCheck $inventoryDB $server 1

$fnGetMSSQLEditionIdCreate = "
CREATE FUNCTION [inventory].[get_MSSQLEditionId]
(@edition VARCHAR(32))
RETURNS INT
AS
BEGIN
    DECLARE @editionID INT;
    SELECT @editionID = mssql_edition_id FROM inventory.MSSQLEditions WHERE edition = @edition;
    RETURN @editionID;
END
"
Execute-Query $fnGetMSSQLEditionIdCreate $inventoryDB $server 1

$fnGetMSSQLVersionIdCheck = "
IF OBJECT_ID('inventory.get_MSSQLVersionId') IS NOT NULL
DROP FUNCTION inventory.get_MSSQLVersionId
"
Execute-Query $fnGetMSSQLVersionIdCheck $inventoryDB $server 1

$fnGetMSSQLVersionIdCreate = " 
CREATE FUNCTION [inventory].[get_MSSQLVersionId]
(@version VARCHAR(32))
RETURNS INT
AS
BEGIN
    DECLARE @versionID INT;
    SELECT @versionID = mssql_version_id FROM inventory.MSSQLVersions WHERE version = @version;
    RETURN @versionID;
END
"
Execute-Query $fnGetMSSQLVersionIdCreate $inventoryDB $server 1

#############################################################################################################
#Crie a tabela principal onde será armazenadas as informações sobre todas as instâncias que são monitoradas #
#############################################################################################################
$mslValuesTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[MSSQLInstanceValues]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE [inventory].[MSSQLInstanceValues](
	[serverId]                  [int] NOT NULL,
	[mssql_version_id]          [int] NULL,
	[mssql_edition_id]          [int] NULL,
	[mssql_build_number_id]     [int] NULL,
	[min_server_memory]         [decimal](15, 2) NULL,
	[max_server_memory]         [decimal](15, 2) NULL,
	[server_memory]             [decimal](10, 2) NULL,
	[server_cores]              [smallint] NULL,
	[sql_cores]                 [smallint] NULL,
	[lpim_enabled]              [bit] NULL,
	[ifi_enabled]               [bit] NULL,
	[sql_service_account]       [nvarchar](128) NULL,
	[sql_agent_service_account] [nvarchar](128) NULL,
	[installed_date]            [datetime] NULL,
	[startup_time]              [datetime] NULL

CONSTRAINT PK_MSSQLInstanceValue PRIMARY KEY CLUSTERED (serverId),

CONSTRAINT FK_MSSQLInstanceValues_MasterServerList FOREIGN KEY (serverId) REFERENCES inventory.MasterServerList(serverId) ON DELETE NO ACTION ON UPDATE NO ACTION,

CONSTRAINT FK_MSSQLInstanceValues_MSSQLVersions FOREIGN KEY (mssql_version_id) REFERENCES inventory.MSSQLVersions(mssql_version_id) ON DELETE NO ACTION ON UPDATE CASCADE,

CONSTRAINT FK_MSSQLInstanceValues_MSSQLEditions FOREIGN KEY (mssql_edition_id) REFERENCES inventory.MSSQLEditions(mssql_edition_id) ON DELETE NO ACTION ON UPDATE CASCADE,

CONSTRAINT FK_MSSQLInstanceValues_MSSQLBuildNumbers FOREIGN KEY (mssql_build_number_id) REFERENCES inventory.MSSQLBuildNumbers(mssql_build_number_id) ON DELETE NO ACTION ON UPDATE CASCADE
) ON [PRIMARY]

END
"
Execute-Query $mslValuesTableCreationQuery $inventoryDB $server 1

#Popula a tabela inventory.MSSQLInstanceValues
$mslValuesTablePopulationQuery = "
INSERT INTO inventory.MSSQLInstanceValues(serverId)
SELECT serverId
FROM inventory.MasterServerList
wHERE serverId NOT IN (SELECT serverId FROM inventory.MSSQLInstanceValues)
"
Execute-Query $mslValuesTablePopulationQuery $inventoryDB $server 1

#Cria a tabela audit onde será armazenada as informações que mudaram para cada instância
$auditTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[audit].[MSSQLInstanceValues]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE audit.MSSQLInstanceValues(
   [serverId]                  [INT],
   [old_value]                 [VARCHAR](64) NOT NULL,
   [new_value]                 [VARCHAR](64) NOT NULL,
   [field]                     [VARCHAR](32) NOT NULL,
   [data_collection_timestamp] [DATETIME] NOT NULL

   CONSTRAINT FK_AuditMasterServerList_MasterServerList FOREIGN KEY (serverId) REFERENCES inventory.MasterServerList(serverId) ON DELETE NO ACTION ON UPDATE CASCADE
) ON [PRIMARY]
END
"
Execute-Query $auditTableCreationQuery $inventoryDB $server 1

#Crie uma tabela temporaria que armazenará as informações coletadas de todas as instâncias
$mslValuesTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[tmp_MSSQLInstanceValues]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE inventory.tmp_MSSQLInstanceValues(
   [t_serverId]                [INT] NOT NULL,
   [sql_version]               [VARCHAR](32) NOT NULL,
   [sql_edition]               [VARCHAR](64) NOT NULL,
   [build_number]              [VARCHAR](32) NOT NULL,
   [min_server_memory]         [DECIMAL](15,2) NOT NULL,
   [max_server_memory]         [DECIMAL](15,2) NOT NULL,
   [server_memory]             [DECIMAL](15,2) NOT NULL,
   [server_cores]              [SMALLINT] NOT NULL,
   [sql_cores]                 [SMALLINT] NOT NULL,
   [lpim_enabled]              [TINYINT] NOT NULL, 
   [ifi_enabled]               [TINYINT] NOT NULL,
   [installed_date]            [DATETIME] NOT NULL,
   [sql_service_account]       [VARCHAR](64) NOT NULL,
   [sql_agent_service_account] [VARCHAR](64) NOT NULL,
   [startup_time]              [DATETIME] NOT NULL
) ON [PRIMARY]
END
"
Execute-Query $mslValuesTableCreationQuery $inventoryDB $server 1

#Seleciona as instâncias da 'Master Server List' que serão percorridas
$instanceLookupQuery = "
SELECT
        serverId,
        trusted,
		CASE instance 
			WHEN 'MSSQLSERVER' THEN server_name                                   
			ELSE CONCAT(server_name,'\',instance)
		END AS 'instance',
		CASE instance 
			WHEN 'MSSQLSERVER' THEN ip                                   
			ELSE CONCAT(ip,'\',instance)
		END AS 'ip',
        CONCAT(ip,',',port) AS 'port'
FROM inventory.MasterServerList
WHERE is_active = 1
"
$instances = Execute-Query $instanceLookupQuery $inventoryDB $server 1

#Para cada instância, busca as informações desejadas 
$mslInformationQuery = "
SET NOCOUNT ON;

CREATE TABLE #CPUValues(
[index]        SMALLINT,
[description]  VARCHAR(128),
[server_cores] SMALLINT,
[value]        VARCHAR(5) 
)

CREATE TABLE #MemoryValues(
[index]         SMALLINT,
[description]   VARCHAR(128),
[server_memory] DECIMAL(10,2),
[value]         VARCHAR(64) 
)

INSERT INTO #CPUValues
EXEC xp_msver 'ProcessorCount'

INSERT INTO #MemoryValues 
EXEC xp_msver 'PhysicalMemory'

CREATE TABLE #IFI_Value(DataOut VarChar(2000))

DECLARE @show_advanced_options INT
DECLARE @xp_cmdshell_enabled INT
DECLARE @xp_regread_enabled INT

SELECT @show_advanced_options = CONVERT(INT, ISNULL(value, value_in_use))
FROM master.sys.configurations
WHERE name = 'show advanced options'

IF @show_advanced_options = 0 
BEGIN
  EXEC sp_configure 'show advanced options', 1
  RECONFIGURE WITH OVERRIDE 
END 

SELECT @xp_cmdshell_enabled = CONVERT(INT, ISNULL(value, value_in_use))
FROM master.sys.configurations
WHERE name = 'xp_cmdshell'

IF @xp_cmdshell_enabled = 0 
BEGIN
  EXEC sp_configure 'xp_cmdshell', 1
  RECONFIGURE WITH OVERRIDE 
END 

INSERT INTO #IFI_Value
EXEC xp_cmdshell 'whoami /priv | findstr `"SeManageVolumePrivilege`"'

IF @xp_cmdshell_enabled = 0 
BEGIN
  EXEC sp_configure 'xp_cmdshell', 0
  RECONFIGURE WITH OVERRIDE 
END 

IF @show_advanced_options = 0 
BEGIN
  EXEC sp_configure 'show advanced options', 0
  RECONFIGURE WITH OVERRIDE 
END

IF (SELECT CONVERT(INT, (REPLACE(SUBSTRING(CONVERT(NVARCHAR, SERVERPROPERTY('ProductVersion')), 1, 2), '.', '')))) > 10
BEGIN

SELECT 
  v.sql_version,
    (SELECT SUBSTRING(CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')),0,CHARINDEX('Edition',CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')))) + 'Edition') AS sql_edition,
  SERVERPROPERTY('ProductVersion') AS 'build_number',
  (SELECT [value] FROM sys.configurations WHERE name like '%min server memory%') min_server_memory,
  (SELECT [value] FROM sys.configurations WHERE name like '%max server memory%') max_server_memory,
  (SELECT ROUND(CONVERT(DECIMAL(10,2),server_memory/1024.0),1) FROM #MemoryValues) AS server_memory,
  server_cores, 
  (SELECT COUNT(*) AS 'sql_cores' FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE') AS sql_cores,
    (SELECT CASE locked_page_allocations_kb WHEN 0 THEN 0 ELSE 1 END FROM sys.dm_os_process_memory) AS lpim_enabled,
    (SELECT COUNT(1) FROM #IFI_Value WHERE DataOut LIKE '%SeManageVolumePrivilege%Enabled%') AS ifi_enabled,
    (SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000) AS installed_date,
    (SELECT service_account FROM sys.dm_server_services WHERE servicename = {fn CONCAT({fn CONCAT('SQL Server (',CONVERT(VARCHAR(32),ISNULL(SERVERPROPERTY('INSTANCENAME'),'MSSQLSERVER')))},')')}) AS sql_service_account,
    (SELECT service_account FROM sys.dm_server_services WHERE servicename = {fn CONCAT({fn CONCAT('SQL Server Agent (',CONVERT(VARCHAR(32),ISNULL(SERVERPROPERTY('INSTANCENAME'),'MSSQLSERVER')))},')')}) AS sql_agent_service_account,
    (SELECT login_time FROM sys.sysprocesses WHERE spid = 1) AS startup_time
FROM #CPUValues
LEFT JOIN (
      SELECT
        CASE 
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '8%'    THEN 'SQL Server 2000'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '9%'    THEN 'SQL Server 2005'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.0%' THEN 'SQL Server 2008'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.5%' THEN 'SQL Server 2008 R2'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '11%'   THEN 'SQL Server 2012'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '12%'   THEN 'SQL Server 2014'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '13%'   THEN 'SQL Server 2016'     
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '14%'   THEN 'SQL Server 2017'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '15%'   THEN 'SQL Server 2019' 
          ELSE 'UNKNOWN'
        END AS sql_version
      ) AS v ON 1 = 1
END

ELSE
BEGIN

DECLARE @instanceName VARCHAR(100)
SET @instanceName = CONVERT(VARCHAR,SERVERPROPERTY ('InstanceName'))
IF (@instanceName) IS NULL
BEGIN
--

END
ELSE
BEGIN
   --
   END
    SELECT 
        v.sql_version,
        (SELECT SUBSTRING(CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')),0,CHARINDEX('Edition',CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')))) + 'Edition') AS sql_edition,
        SERVERPROPERTY('ProductVersion') AS 'build_number',
        (SELECT [value] FROM sys.configurations WHERE name like '%min server memory%') min_server_memory,
        (SELECT [value] FROM sys.configurations WHERE name like '%max server memory%') max_server_memory,
        (SELECT ROUND(CONVERT(DECIMAL(10,2),server_memory/1024.0),1) FROM #MemoryValues) AS server_memory,
        server_cores, 
        (SELECT COUNT(*) AS 'sql_cores' FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE') AS sql_cores,
        (SELECT CASE locked_page_allocations_kb WHEN 0 THEN 0 ELSE 1 END FROM sys.dm_os_process_memory) AS lpim_enabled,
        (SELECT COUNT(1) FROM #IFI_Value WHERE DataOut LIKE '%SeManageVolumePrivilege%Enabled%') AS ifi_enabled,
        (SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000) AS installed_date,
        (SELECT @engineAccount AS sql_service_account) AS sql_service_account,
        (SELECT @agentAccount AS sql_agent_service_account) AS sql_agent_service_account,
        (SELECT login_time FROM sys.sysprocesses WHERE spid = 1) AS startup_time
    FROM #CPUValues
    LEFT JOIN (
        SELECT
        CASE 
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '8%'    THEN 'SQL Server 2000'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '9%'    THEN 'SQL Server 2005'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.0%' THEN 'SQL Server 2008'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.5%' THEN 'SQL Server 2008 R2'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '11%'   THEN 'SQL Server 2012'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '12%'   THEN 'SQL Server 2014'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '13%'   THEN 'SQL Server 2016'     
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '14%'   THEN 'SQL Server 2017'
          WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '15%'   THEN 'SQL Server 2019' 
          ELSE 'UNKNOWN'
        END AS sql_version
    ) AS v ON 1 = 1
END

DROP TABLE #CPUValues
DROP TABLE #MemoryValues
DROP TABLE #IFI_Value
"

foreach ($instance in $instances){
   if($instance.trusted -eq 'True'){$trusted = 1}else{$trusted = 0}
   $sqlInstance = $instance.instance

  #Vai pegar as informações complementares para a instância 
   Write-Host "Fetching information from instance" $instance.instance
   
   #Lógica especial para casos em que a instância não pode ser acessada pelo nome 
   try{
        $results = Execute-Query $mslInformationQuery "master" $sqlInstance $trusted
   }
   catch{
        $sqlInstance = $instance.ip
        [string]$message = $_
        $query = "INSERT INTO monitoring.ErrorLog VALUES("+$instance.serverId+",'Get-MSSQL-Instance-Values','"+$message.replace("'","''")+"',GETDATE())"
        Execute-Query $query $inventoryDB $server 1

        try{  
            $results = Execute-Query $mslInformationQuery "master" $sqlInstance $trusted
        }
        catch{
            $sqlInstance = $instance.port
            [string]$message = $_
            $query = "INSERT INTO monitoring.ErrorLog VALUES("+$instance.serverId+",'Get-MSSQL-Instance-Values','"+$message.replace("'","''")+"',GETDATE())"
            Execute-Query $query $inventoryDB $server 1

            try{
                $results = Execute-Query $mslInformationQuery "master" $sqlInstance $trusted
            }
            catch{
                [string]$message = $_
                $query = "INSERT INTO monitoring.ErrorLog VALUES("+$instance.serverId+",'Get-MSSQL-Instance-Values','"+$message.replace("'","''")+"',GETDATE())"
                Execute-Query $query $inventoryDB $server 1
            }
        }
   }
   
  # Executa o INSERT na tabela inventory.tmp_MSSQLInstanceValues apenas se retornar informações 
   if($results.Length -ne 0){

      #Build the insert statement
      $insert = "INSERT INTO inventory.tmp_MSSQLInstanceValues VALUES"
      foreach($result in $results){   
         $insert += "
         (
          '"+$instance.serverId+"',
          '"+$result['sql_version']+"',
          '"+$result['sql_edition']+"',
          '"+$result['build_number']+"',
          "+$result['min_server_memory']+",
          "+$result['max_server_memory']+",
          "+$result['server_memory']+",
          "+$result['server_cores']+",
          "+$result['sql_cores']+",
          "+$result['lpim_enabled']+",
          "+$result['ifi_enabled']+",
          '"+$result['installed_date']+"',
          '"+$result['sql_service_account']+"',
          '"+$result['sql_agent_service_account']+"',
          '"+$result['startup_time']+"'
         ),
         "
       }

       $insert = $insert -replace "''",'NULL'
       $insert = $insert -replace "NULLNULL",'NULL'
       Execute-Query $insert.Substring(0,$insert.LastIndexOf(',')) $inventoryDB $server 1
   }
}

#####################################################################################################################################################
#Nesta seção, será feita a comparação de cada campo e os diferentes serão atualizados na tabela inventário.MasterServerList  #
#####################################################################################################################################################

#Build Number
$compareBuildNumberQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.mssql_build_number_id,
	inventory.get_MSSQLBuildNumberId(t.build_number) AS t_mssql_build_number_id
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.mssql_build_number_id <> inventory.get_MSSQLBuildNumberId(t.build_number)) OR (m.mssql_build_number_id IS NULL AND inventory.get_MSSQLBuildNumberId(t.build_number) IS NOT NULL)
"
$changesInBuildNumber = Execute-Query $compareBuildNumberQuery $inventoryDB $server 1

if($changesInBuildNumber.Length -ne 0){
    $buildNumberAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInBuildNumber in $changesInBuildNumber){
        #Save each value that will be updated in the audit.MSSQLInstanceValues table
        $buildNumberAuditQuery += "('"+$changeInBuildNumber.serverId+"',"+
                                   "'"+$changeInBuildNumber.mssql_build_number_id+"',"+
                                   "'"+$changeInBuildNumber.t_mssql_build_number_id+"',
                                       'Build Number',
                                       GETDATE()
                                   ),"

        $buildNumberUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                   SET mssql_build_number_id = "+$changeInBuildNumber.t_mssql_build_number_id+"
                                   WHERE serverId ="+$changeInBuildNumber.serverId+" 
                                  "
        Execute-Query $buildNumberUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $buildNumberAuditQuery.Substring(0,$buildNumberAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Min Server Memory
$compareMinServerMemoryQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.min_server_memory,
	t.min_server_memory AS t_min_server_memory
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.min_server_memory <> t.min_server_memory) OR (m.min_server_memory IS NULL AND t.min_server_memory IS NOT NULL)
"
$changesInMinServerMemory = Execute-Query $compareMinServerMemoryQuery $inventoryDB $server 1

if($changesInMinServerMemory.Length -ne 0){
    $minServerMemoryAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInMinServerMemory in $changesInMinServerMemory){
       #Salva cada valor que será atualizado na tabela audit.MSSQLInstanceValues
        $minServerMemoryAuditQuery += "('"+$changeInMinServerMemory.serverId+"',"+
                                       "'"+$changeInMinServerMemory.min_server_memory+"',"+
                                       "'"+$changeInMinServerMemory.t_min_server_memory+"',
                                           'Min Server Memory',
                                           GETDATE()
                                       ),"

        $minServerMemoryUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                       SET min_server_memory = "+$changeInMinServerMemory.t_min_server_memory+"
                                       WHERE serverId ="+$changeInMinServerMemory.serverId+" 
                                      "
        Execute-Query $minServerMemoryUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $minServerMemoryAuditQuery.Substring(0,$minServerMemoryAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Max Server Memory
$compareMaxServerMemoryQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.max_server_memory,
	t.max_server_memory AS t_max_server_memory
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.max_server_memory <> t.max_server_memory) OR (m.max_server_memory IS NULL AND t.max_server_memory IS NOT NULL)
"
$changesInMaxServerMemory = Execute-Query $compareMaxServerMemoryQuery $inventoryDB $server 1

if($changesInMaxServerMemory.Length -ne 0){
    $maxServerMemoryAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInMaxServerMemory in $changesInMaxServerMemory){
      #Salva cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $maxServerMemoryAuditQuery += "('"+$changeInMaxServerMemory.serverId+"',"+
                                       "'"+$changeInMaxServerMemory.max_server_memory+"',"+
                                       "'"+$changeInMaxServerMemory.t_max_server_memory+"',
                                           'Max Server Memory',
                                           GETDATE()
                                       ),"

        $maxServerMemoryUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                       SET max_server_memory = "+$changeInMaxServerMemory.t_max_server_memory+"
                                       WHERE serverId ="+$changeInMaxServerMemory.serverId+" 
                                      "
        Execute-Query $maxServerMemoryUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $maxServerMemoryAuditQuery.Substring(0,$maxServerMemoryAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Server Memory
$compareServerMemoryQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.server_memory,
	t.server_memory AS t_server_memory
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.server_memory <> t.server_memory) OR (m.server_memory IS NULL AND t.server_memory IS NOT NULL)
"
$changesInServerMemory = Execute-Query $compareServerMemoryQuery $inventoryDB $server 1

if($changesInServerMemory.Length -ne 0){
    $serverMemoryAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInServerMemory in $changesInServerMemory){
       #Salva cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $serverMemoryAuditQuery += "('"+$changeInServerMemory.serverId+"',"+
                                    "'"+$changeInServerMemory.server_memory+"',"+
                                    "'"+$changeInServerMemory.t_server_memory+"',
                                        'Server Memory',
                                        GETDATE()
                                    ),"

        $serverMemoryUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                    SET server_memory = "+$changeInServerMemory.t_server_memory+"
                                    WHERE serverId ="+$changeInServerMemory.serverId+" 
                                   "
        Execute-Query $serverMemoryUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $serverMemoryAuditQuery.Substring(0,$serverMemoryAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Server Cores
$compareServerCoresQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.server_cores,
	t.server_cores AS t_server_cores
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.server_cores <> t.server_cores) OR (m.server_cores IS NULL AND t.server_cores IS NOT NULL)
"
$changesInServerCores = Execute-Query $compareServerCoresQuery $inventoryDB $server 1

if($changesInServerCores.Length -ne 0){
    $serverCoresAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInServerCores in $changesInServerCores){
        #Salva cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $serverCoresAuditQuery += "('"+$changeInServerCores.serverId+"',"+
                                   "'"+$changeInServerCores.server_cores+"',"+
                                   "'"+$changeInServerCores.t_server_cores+"',
                                       'Server Cores',
                                       GETDATE()
                                   ),"

        $serverCoresUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                   SET server_cores = "+$changeInServerCores.t_server_cores+"
                                   WHERE serverId ="+$changeInServerCores.serverId+" 
                                  "
        Execute-Query $serverCoresUpdateQuery $inventoryDB $server 1
    }
    Execute-Query $serverCoresAuditQuery.Substring(0,$serverCoresAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#SQL Cores
$compareSQLCoresQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.sql_cores,
	t.sql_cores AS t_sql_cores
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.sql_cores <> t.sql_cores) OR (m.sql_cores IS NULL AND t.sql_cores IS NOT NULL)
"
$changesInSQLCores = Execute-Query $compareSQLCoresQuery $inventoryDB $server 1

if($changesInSQLCores.Length -ne 0){
    $sqlCoresAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInSQLCores in $changesInSQLCores){
       #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $sqlCoresAuditQuery += "('"+$changeInSQLCores.serverId+"',"+
                                "'"+$changeInSQLCores.sql_cores+"',"+
                                "'"+$changeInSQLCores.t_sql_cores+"',
                                    'SQL Cores',
                                    GETDATE()
                                ),"

        $sqlCoresUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                SET sql_cores = "+$changeInSQLCores.t_sql_cores+"
                                WHERE serverId ="+$changeInSQLCores.serverId+" 
                               "
        Execute-Query $sqlCoresUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $sqlCoresAuditQuery.Substring(0,$sqlCoresAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#SQL Version
$compareSQLVersionQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.mssql_version_id,
	inventory.get_MSSQLVersionId(t.sql_version) AS t_mssql_version_id
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.mssql_version_id <> inventory.get_MSSQLVersionId(t.sql_version)) OR (m.mssql_version_id IS NULL AND inventory.get_MSSQLVersionId(t.sql_version) IS NOT NULL)
"
$changesInSQLVersion = Execute-Query $compareSQLVersionQuery $inventoryDB $server 1

if($changesInSQLVersion.Length -ne 0){
    $sqlVersionAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInSQLVersion in $changesInSQLVersion){
       #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $sqlVersionAuditQuery += "('"+$changeInSQLVersion.serverId+"',"+
                                  "'"+$changeInSQLVersion.mssql_version_id+"',"+
                                  "'"+$changeInSQLVersion.t_mssql_version_id+"',
                                      'SQL Version',
                                      GETDATE()
                                  ),"

        $sqlVersionUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                  SET mssql_version_id = "+$changeInSQLVersion.t_mssql_version_id+"
                                  WHERE serverId ="+$changeInSQLVersion.serverId+" 
                                 "
        Execute-Query $sqlVersionUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $sqlVersionAuditQuery.Substring(0,$sqlVersionAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#SQL Edition
$compareSQLEditionQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.mssql_edition_id,
	inventory.get_MSSQLEditionId(t.sql_edition) AS t_mssql_edition_id
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.mssql_edition_id <> inventory.get_MSSQLEditionId(t.sql_edition)) OR (m.mssql_edition_id IS NULL AND inventory.get_MSSQLEditionId(t.sql_edition) IS NOT NULL)
"
$changesInSQLEdition = Execute-Query $compareSQLEditionQuery $inventoryDB $server 1

if($changesInSQLEdition.Length -ne 0){
    $sqlEditionAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInSQLEdition in $changesInSQLEdition){
        #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $sqlEditionAuditQuery += "('"+$changeInSQLEdition.serverId+"',"+
                                  "'"+$changeInSQLEdition.mssql_edition_id+"',"+
                                  "'"+$changeInSQLEdition.t_mssql_edition_id+"',
                                      'SQL Edition',
                                      GETDATE()
                                  ),"

        $sqlEditionUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                  SET mssql_edition_id = "+$changeInSQLEdition.t_mssql_edition_id+"
                                  WHERE serverId ="+$changeInSQLEdition.serverId+" 
                                 "
        Execute-Query $sqlEditionUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $sqlEditionAuditQuery.Substring(0,$sqlEditionAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Lock Pages in Memory
$compareLPIMQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.lpim_enabled,
	t.lpim_enabled AS t_lpim_enabled
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.lpim_enabled <> t.lpim_enabled) OR (m.lpim_enabled IS NULL AND t.lpim_enabled IS NOT NULL)
"
$changesInLPIM = Execute-Query $compareLPIMQuery $inventoryDB $server 1

if($changesInLPIM.Length -ne 0){
    $lpimAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInLPIM in $changesInLPIM){
        #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $lpimAuditQuery += "('"+$changeInLPIM.serverId+"',"+
                            "'"+$changeInLPIM.lpim_enabled+"',"+
                            "'"+$changeInLPIM.t_lpim_enabled+"',
                                'LPIM',
                                GETDATE()
                            ),"

        $lpimUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                            SET lpim_enabled = "+$changeInLPIM.t_lpim_enabled+"
                            WHERE serverId ="+$changeInLPIM.serverId+" 
                           "
        Execute-Query $lpimUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $lpimAuditQuery.Substring(0,$lpimAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Instant File Initialization
$compareIFIQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.ifi_enabled,
	t.ifi_enabled AS t_ifi_enabled
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.ifi_enabled <> t.ifi_enabled) OR (m.ifi_enabled IS NULL AND t.ifi_enabled IS NOT NULL)
"
$changesInIFI = Execute-Query $compareIFIQuery $inventoryDB $server 1

if($changesInIFI.Length -ne 0){
    $ifiAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInIFI in $changesInIFI){
       #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $ifiAuditQuery += "('"+$changeInIFI.serverId+"',"+
                           "'"+$changeInIFI.ifi_enabled+"',"+
                           "'"+$changeInIFI.t_ifi_enabled+"',
                               'IFI',
                               GETDATE()
                           ),"

        $ifiUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                           SET ifi_enabled = "+$changeInIFI.t_ifi_enabled+"
                           WHERE serverId ="+$changeInIFI.serverId+" 
                          "
        Execute-Query $ifiUpdateQuery $inventoryDB $server 1 
    }
    Execute-Query $ifiAuditQuery.Substring(0,$ifiAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Installed Date
$compareInstalledDateQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.installed_date,
	t.installed_date AS t_installed_date
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.installed_date <> t.installed_date) OR (m.installed_date IS NULL AND t.installed_date IS NOT NULL)
"
$changesInInstalledDate = Execute-Query $compareInstalledDateQuery $inventoryDB $server 1 

if($changesInInstalledDate.Length -ne 0){
    $installedDateAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInInstalledDate in $changesInInstalledDate){
        #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $installedDateAuditQuery += "('"+$changeInInstalledDate.serverId+"',"+
                                        "'"+$changeInInstalledDate.installed_date+"',"+
                                        "'"+$changeInInstalledDate.t_installed_date+"',
                                           'Installed Date',
                                           GETDATE()
                                        ),"

        $installedDateUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                     SET installed_date = '"+$changeInInstalledDate.t_installed_date+"'
                                     WHERE serverId ="+$changeInInstalledDate.serverId+" 
                                    "
        Execute-Query $installedDateUpdateQuery $inventoryDB $server 1
    } 
    Execute-Query $installedDateAuditQuery.Substring(0,$installedDateAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#Last Startup Time
$compareStartupTimeQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.startup_time,
	t.startup_time AS t_startup_time
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.startup_time <> t.startup_time) OR (m.startup_time IS NULL AND t.startup_time IS NOT NULL)
"
$changesInStartupTime = Execute-Query $compareStartupTimeQuery $inventoryDB $server 1

if($changesInStartupTime.Length -ne 0){
    $startupTimeAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInStartupTime in $changesInStartupTime){
       #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $startupTimeAuditQuery += "('"+$changeInStartupTime.serverId+"',"+
                                   "'"+$changeInStartupTime.startup_time+"',"+
                                   "'"+$changeInStartupTime.t_startup_time+"',
                                       'Startup Time',
                                       GETDATE()
                                   ),"

        $startupTimeUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                   SET startup_time = '"+$changeInStartupTime.t_startup_time+"'
                                   WHERE serverId ="+$changeInStartupTime.serverId+" 
                                  "
        Execute-Query $startupTimeUpdateQuery $inventoryDB $server 1
    }
    Execute-Query $startupTimeAuditQuery.Substring(0,$startupTimeAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#SQL Service Account
$compareSQLServiceAccountQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.sql_service_account,
	t.sql_service_account AS t_sql_service_account
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.sql_service_account <> t.sql_service_account) OR (m.sql_service_account IS NULL AND t.sql_service_account IS NOT NULL)
"
$changesInSQLServiceAccount = Execute-Query $compareSQLServiceAccountQuery $inventoryDB $server 1

if($changesInSQLServiceAccount.Length -ne 0){
    $sqlServiceAccountAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInSQLServiceAccount in $changesInSQLServiceAccount){
        #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $sqlServiceAccountAuditQuery += "('"+$changeInSQLServiceAccount.serverId+"',"+
                                         "'"+$changeInSQLServiceAccount.sql_service_account+"',"+
                                         "'"+$changeInSQLServiceAccount.t_sql_service_account+"',
                                             'SQL Service Account',
                                             GETDATE()
                                         ),"

        $sqlServiceAccountUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                         SET sql_service_account = '"+$changeInSQLServiceAccount.t_sql_service_account+"'
                                         WHERE serverId ="+$changeInSQLServiceAccount.serverId+" 
                                        "
        Execute-Query $sqlServiceAccountUpdateQuery $inventoryDB $server 1      
    }
    Execute-Query $sqlServiceAccountAuditQuery.Substring(0,$sqlServiceAccountAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

#SQL Agent Service Account
$compareSQLAgentServiceAccountQuery = "
SELECT 
	m.serverId,
	t.t_serverId,
	m.sql_agent_service_account,
	t.sql_agent_service_account AS t_sql_agent_service_account
FROM inventory.MSSQLInstanceValues m
LEFT JOIN inventory.tmp_MSSQLInstanceValues t ON t.t_serverId = m.serverId
WHERE (m.sql_agent_service_account <> t.sql_agent_service_account) OR (m.sql_agent_service_account IS NULL AND t.sql_agent_service_account IS NOT NULL)
"
$changesInSQLAgentServiceAccount = Execute-Query $compareSQLAgentServiceAccountQuery $inventoryDB $server 1

if($changesInSQLAgentServiceAccount.Length -ne 0){
    $sqlAgentServiceAccountAuditQuery = "
    INSERT INTO audit.MSSQLInstanceValues VALUES
    "

    foreach($changeInSQLAgentServiceAccount in $changesInSQLAgentServiceAccount){
       #Salve cada valor que será atualizado na tabela audit.MSSQLInstanceValues 
        $sqlAgentServiceAccountAuditQuery += "('"+$changeInSQLAgentServiceAccount.serverId+"',"+
                                              "'"+$changeInSQLAgentServiceAccount.sql_agent_service_account+"',"+
                                              "'"+$changeInSQLAgentServiceAccount.t_sql_agent_service_account+"',
                                                  'SQL Agent Service Account',
                                                  GETDATE()
                                              ),"

        $sqlAgentServiceAccountUpdateQuery = "UPDATE inventory.MSSQLInstanceValues 
                                              SET sql_agent_service_account = '"+$changeInSQLAgentServiceAccount.t_sql_agent_service_account+"'
                                              WHERE serverId ="+$changeInSQLAgentServiceAccount.serverId+" 
                                             "
        Execute-Query $sqlAgentServiceAccountUpdateQuery $inventoryDB $server 1              
    }
    Execute-Query $sqlAgentServiceAccountAuditQuery.Substring(0,$sqlAgentServiceAccountAuditQuery.LastIndexOf(',')) $inventoryDB $server 1
}

Execute-Query "DROP TABLE inventory.tmp_MSSQLInstanceValues" $inventoryDB $server 1

Write-Host "Done!"