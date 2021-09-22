-- Mais detalhes: https://msdn.microsoft.com/pt-br/library/ms174396(v=sql.120).aspx

SELECT
	SERVERPROPERTY('servername') as 'Server Name',
	SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as 'Physical Name (Cluster)',
	SERVERPROPERTY('productversion') as 'Product Version',
	SERVERPROPERTY('productlevel') as 'Service Pack',
	SERVERPROPERTY('engineedition') as 'Engine Edition',
	SERVERPROPERTY('edition') as 'Edition',
CASE
	WHEN SERVERPROPERTY('IsFullTextInstalled') = 1 THEN 'Yes'
ELSE 'No'
END as 'Full Text Installed',
CASE
	WHEN SERVERPROPERTY('IsSingleUser') = 1 THEN 'Yes'
ELSE 'No'
END as 'Single User Mode',
CASE
	WHEN SERVERPROPERTY('isclustered') = 1 THEN 'Yes'
ELSE 'No'
END as 'Clustered',

CASE
	WHEN SERVERPROPERTY('IsHadrEnabled') = 1 THEN 'Yes'
ELSE 'No'
END as 'AlwaysOn',
CASE
	WHEN SERVERPROPERTY('instancename') IS null THEN 'Default'
ELSE SERVERPROPERTY('instancename')
END AS 'Instance'
