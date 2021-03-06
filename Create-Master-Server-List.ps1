# 1 - script : Cria a tabela principal [inventory].[MasterServerList] onde ser? armazenado as informa??es sobre todas as inst?ncias a serem monitoradas#

Get-Content "C:\Users\ricardo.osilva\Desktop\Projeto\6354_scripts\Settings.ini" | foreach-object -begin {$h=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $h.Add($k[0], $k[1]) } }
$server        = $h.Get_Item("centralServer")
$inventoryDB   = $h.Get_Item("inventoryDB")
$usingCredentials = 0
#https://www.mssqltips.com/sqlservertip/6354/monitoring-sql-server-with-powershell-core-object-setup/
#coletar os dados e tamb?m para criar os objetos do banco de dados em um servidor centralizado de banco de dados
# Cria a tabela principal [inventory].[MasterServerList] onde ser? armazenado as informa??es sobre todas as inst?ncias a serem monitoradas#
if($server.length -eq 0){
    Write-Host "Informar um nome de servidor para 'centralServer' no Settings.ini !!!" -BackgroundColor Red
    exit
}
if($inventoryDB.length -eq 0){
    Write-Host "Informar um nome de database para 'inventoryDB' no Settings.ini !!!" -BackgroundColor Red
    exit
}

if($h.Get_Item("username").length -gt 0 -and $h.Get_Item("password").length -gt 0){
    $usingCredentials = 1
    $username         = $h.Get_Item("username")
    $password         = $h.Get_Item("password")
}

#Fun??o para executar consultas (dependendo se o usu?rio usar? credenciais espec?ficas ou n?o)
function Execute-Query([string]$query,[string]$database,[string]$instance){
    if($usingCredentials -eq 1){
        Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Username $username -Password $password -ErrorAction Stop
    }
    else{
        Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -ErrorAction Stop
    }
}

# Verifica??o ou cria??o do Central Database que armazena os dados de vers?es e instancias
##############################################################################################
$centralDBCreationQuery = "
IF DB_ID('$($inventoryDB)') IS NULL
CREATE DATABASE $($inventoryDB)
"
Execute-Query $centralDBCreationQuery "master" $server

################################################################
#Verifica??o ou cria??o dos Schemas audit,inventory e monitoring
################################################################
$auditSchemaCreationQuery = "
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'audit')
EXEC('CREATE SCHEMA [audit] AUTHORIZATION [dbo]')
"
Execute-Query $auditSchemaCreationQuery $inventoryDB $server

$inventorySchemaCreationQuery = "
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'inventory')
EXEC('CREATE SCHEMA [inventory] AUTHORIZATION [dbo]')
"
Execute-Query $inventorySchemaCreationQuery $inventoryDB $server

$monitoringSchemaCreationQuery = "
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'monitoring')
EXEC('CREATE SCHEMA [monitoring] AUTHORIZATION [dbo]')
"
Execute-Query $monitoringSchemaCreationQuery $inventoryDB $server

###########################################################################################################
#Cria a tabela principal onde ser? armazenado as informa??es sobre todas as inst?ncias a serem monitoradas#
###########################################################################################################
$mslTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[inventory].[MasterServerList]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE [inventory].[MasterServerList](
	[serverId]                  [int] IDENTITY(1,1) NOT NULL,
	[server_name]               [nvarchar](128) NOT NULL,
	[instance]                  [nvarchar](128) NOT NULL,
	[ip]                        [nvarchar](39) NOT NULL,
    [port]                      [int] NOT NULL DEFAULT 1433,
    [trusted]                   [bit] DEFAULT 1,
    [is_active]                 [bit] DEFAULT 1

CONSTRAINT PK_MasterServerList PRIMARY KEY CLUSTERED (serverId),

CONSTRAINT UQ_instance UNIQUE(server_name,instance)
) ON [PRIMARY]

END
"
Execute-Query $mslTableCreationQuery $inventoryDB $server

#############################################
#Verifica??o ou cria??o da tabela Error log #
#############################################
$errorLogTableCreationQuery = "
IF NOT EXISTS (SELECT * FROM dbo.sysobjects where id = object_id(N'[monitoring].[ErrorLog]') and OBJECTPROPERTY(id, N'IsTable') = 1)
BEGIN
CREATE TABLE [monitoring].[ErrorLog](
    [serverId]        [int]NOT NULL,
    [script]          [nvarchar](64) NOT NULL,
    [message]         [nvarchar](MAX) NOT NULL,
    [error_timestamp] [datetime] NOT NULL
    
    CONSTRAINT FK_ErrorLog_MasterServerList FOREIGN KEY (serverId) REFERENCES inventory.MasterServerList(serverId) ON DELETE NO ACTION ON UPDATE CASCADE
)ON [PRIMARY]
END
"
Execute-Query $errorLogTableCreationQuery $inventoryDB $server

#Logica para popular a tabela Master Server List usando um arquivo instances.txt com as instancias para monitorar
########################################################################################################
$flag = 0
foreach($line in Get-Content C:\Users\ricardo.osilva\Desktop\Projeto\6354_scripts\instances.txt){
    $insertMSLQuery = "INSERT INTO inventory.MasterServerList(server_name,instance,ip,port) VALUES($($line))"
    
    try{
        Execute-Query $insertMSLQuery $inventoryDB $server
    }
    catch{
        $flag = 1
        [string]$message = $_
        $query = "INSERT INTO monitoring.ErrorLog VALUES((SELECT serverId FROM inventory.MasterServerList WHERE CASE instance WHEN 'MSSQLSERVER' THEN server_name ELSE CONCAT(server_name,'\',instance) END = '$($server)'),'Create-Master-Server-List','"+$message.replace("'","''")+"',GETDATE())"
        Execute-Query $query $inventoryDB $server
    }
}
if($flag -eq 1){Write-Host "Verifique a tabela monitoring.ErrorLog ! Verificar se j? existe inst?ncia"}

Write-Host "Done!"