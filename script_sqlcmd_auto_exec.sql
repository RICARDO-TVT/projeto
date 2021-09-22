/*  SCRIPT: Executor_principal.sql - Responsavel pela Automa��o de execu��o dos script e chamador de cada script da GMUD*/
/*  Este script ira executar todos os scripts da GMUD , abortando a execu��o caso ocorrar algun erro nos script*/
/*  Gerar o arquivo zipado ( .zip)  deste script para anexa-lo no Formul�rio do ServiceNow na gera��o da REQ de execu��o dos scripts */
/*  Neste script temos duas etapas de parametriza��o  sendo :*/
/* 1- Informa��es para gera��o do Backup do database e garantia  de Rollback da GMUD.*/
/* 2- Informa��es da sequencia de execu��o dos scripts e do database onde ser�o executados. */
print '============================================================================================'
print 'INICIO DA EXECU��O AUTOMATIZADA DE SCRIPTS   '
print '============================================================================================'
SET NOCOUNT ON
GO
---------------------------------------------------------------------------------------------------------------------------
-- 1- Informa��es para gera��o do Backup do database e garantia de Rollback da GMUD
-----------------------------------------------------------------------------------------------------------------------------
--  exec [dbativit].[dbo].[backup_database] 'database_name'
--  database_name :  Nome da Base de Dados ser gerado o Backup em disco
--  Exemplo : 
print '============================================================================================'
print 'EXECU��O DE BACKUPS'
print '============================================================================================'
exec [dbativit].[dbo].[backup_database] 'dbativit'
------------------------------------------------------------------------------------------------------------------------------
/* 2- Informa��es da sequencia de execu��o dos scripts e do database onde ser�o executados. */
-------------------------------------------------------------------------------------------------------------------------------
-- Na instru��o USE informar o nome do database onde os scripts ser�o executados
-- USE database_name
-- database_name :  Nome da Base de Dados 
-- Exemplo :
USE DBA
GO
:On Error exit  -- Esta instru��o ira parar imediatamente a execu��o dos scripts na ocorrencia de algum erro na instru��o SQL.
------------------------------------------------------------------------------------------------------------------------------
--  Informar todos os scripts a serem executados na sequencia desejada e formato abaixo.
--  Os log de execu��o de todos os scripts ser�o disponibilizado no output da SCTASK da REQ criada  no ServiceNow e no formato arquivo texto (txt).
-- print '============================================================================================'
--  print 'EXECUTANDO SCRIPTS'
-- print '============================================================================================'
-- :r C:\caminho_do_script\script01.sql
-- :r C:\caminho_do_script\script02.sql
-- :r C:\caminho_do_script\script03.sql
-- :r C:\caminho_do_script\\script04.sql
-- Exemplo :
 print '============================================================================================'
 print 'EXECUTANDO SCRIPTS'
 print '============================================================================================'
:r C:\scripts_sqlcmd_teste\CREATE_TABLES.sql
:r C:\scripts_sqlcmd_teste\TABLE_INSERTS.sql
:r C:\scripts_sqlcmd_teste\CREATE_INDEXES.sql
:r C:\scripts_sqlcmd_teste\CREATE_PROCEDURES.sql

print 'TERMINO DA EXECU��O AUTOMATIZADA DE SCRIPTS'
GO