SELECT 
   CASE WHEN msl.instance = 'MSSQLSERVER' THEN msl.server_name ELSE CONCAT(msl.server_name,'\',msl.instance) END AS 'Instance',
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
   iv.startup_time AS 'Instance Latest Startup Time'
FROM inventory.MSSQLInstanceValues iv
JOIN inventory.MasterServerList msl ON iv.serverId = msl.serverId
JOIN inventory.MSSQLBuildNumbers bn ON iv.mssql_build_number_id = bn.mssql_build_number_id
JOIN inventory.MSSQLEditions e ON iv.mssql_edition_id = e.mssql_edition_id
JOIN inventory.MSSQLVersions v ON iv.mssql_version_id = v.mssql_version_id