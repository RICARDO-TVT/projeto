USE [DBA]
GO

SELECT [serverId]
      ,[server_name]
      ,[instance]
      ,[ip]
      ,[port]
      ,[trusted]
      ,[is_active]
  FROM [inventory].[MasterServerList]

GO

--Você pode executar a consulta a seguir para ver se algum dos valores mudou desde a última execução.
SELECT * FROM audit.MSSQLInstanceValues
SELECT * FROM inventory.MSSQLInstanceValues
SELECT * FROM inventory.MSSQLInstanceValues

---to see if any of the values have changed since the last run.
SELECT * FROM audit.MSSQLInstanceValues
SELECT * FROM inventory.MSSQLBuildNumbers where build_number='11.0.6020.0'

---To check for errors query the monitoring.ErrorLog table. 
SELECT *
FROM monitoring.ErrorLog
WHERE script = 'Get-MSSQL-Instance-Values'

--Para verificar se há erros, consulte o monitoramento. Tabela ErrorLog.
SELECT *
FROM monitoring.ErrorLog
WHERE script = 'Get-MSSQL-Instance-Values'

--Consulta de dados coletados
SELECT 
   CASE WHEN msl.instance = 'MSSQLSERVER' 
   THEN msl.server_name
   ELSE CONCAT(msl.server_name,'\',msl.instance) 
   END AS 'Instance',
   v.version AS 'Version',
   e.edition AS 'Edition',
   bn.build_number AS 'BuildNumber',
   iv.min_server_memory AS 'Min Server Memory',
   iv.max_server_memory AS 'Max Server Memory',
   iv.server_memory AS 'Server Memory',
   iv.server_cores AS 'Server Cores',
   iv.sql_cores AS 'SQL Cores',
   iv.lpim_enabled AS 'LPIM Enabled',
   iv.ifi_enabled AS 'IFI Enabled',
   iv.sql_service_account AS 'SQL Service Account',
   iv.sql_agent_service_account AS 'SQL Agent Service Account',
   iv.installed_date AS 'Instance Installation Date',
   iv.startup_time AS 'Instance Latest Startup Time',
    iv.server_cores/iv.sql_cores as 'Cores to CPUs Ratio' ,
	CASE
	WHEN e.edition='Developer' THEN 'n/a'
	ELSE
	CASE 
	WHEN iv.server_cores = iv.sql_cores THEN  'No licensing changes'
   ELSE 
   'licensing costs increase in ' + CONVERT(VARCHAR,iv.server_cores/iv.sql_cores) +' times'
   END  
   END AS 'RESUMO'
FROM inventory.MSSQLInstanceValues iv
JOIN inventory.MasterServerList msl ON iv.serverId = msl.serverId
JOIN inventory.MSSQLBuildNumbers bn ON iv.mssql_build_number_id = bn.mssql_build_number_id
JOIN inventory.MSSQLEditions e ON iv.mssql_edition_id = e.mssql_edition_id
JOIN inventory.MSSQLVersions v ON iv.mssql_version_id = v.mssql_version_id



SELECT  numa_configuration_desc, sql_memory_model_desc FROM sys.dm_os_sys_info
