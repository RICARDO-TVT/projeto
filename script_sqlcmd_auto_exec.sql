/*  SCRIPT: Executor_principal.sql - Responsavel pela Automação de execução dos script e chamador de cada script da GMUD*/
/*  Este script ira executar todos os scripts da GMUD , abortando a execução caso ocorrar algun erro nos script*/
/*  Gerar o arquivo zipado ( .zip)  deste script para anexa-lo no Formulário do ServiceNow na geração da REQ de execução dos scripts */
/*  Neste script temos duas etapas de parametrização  sendo :*/
/* 1- Informações para geração do Backup do database e garantia  de Rollback da GMUD.*/
/* 2- Informações da sequencia de execução dos scripts e do database onde serão executados. */
print '============================================================================================'
print 'INICIO DA EXECUÇÃO AUTOMATIZADA DE SCRIPTS   '
print '============================================================================================'
SET NOCOUNT ON
GO
---------------------------------------------------------------------------------------------------------------------------
-- 1- Informações para geração do Backup do database e garantia de Rollback da GMUD
-----------------------------------------------------------------------------------------------------------------------------
--  exec [dbativit].[dbo].[backup_database] 'database_name'
--  database_name :  Nome da Base de Dados ser gerado o Backup em disco
--  Exemplo : 
print '============================================================================================'
print 'EXECUÇÃO DE BACKUPS'
print '============================================================================================'
exec [dbativit].[dbo].[backup_database] 'dbativit'
------------------------------------------------------------------------------------------------------------------------------
/* 2- Informações da sequencia de execução dos scripts e do database onde serão executados. */
-------------------------------------------------------------------------------------------------------------------------------
-- Na instrução USE informar o nome do database onde os scripts serão executados
-- USE database_name
-- database_name :  Nome da Base de Dados 
-- Exemplo :
USE DBA
GO
:On Error exit  -- Esta instrução ira parar imediatamente a execução dos scripts na ocorrencia de algum erro na instrução SQL.
------------------------------------------------------------------------------------------------------------------------------
--  Informar todos os scripts a serem executados na sequencia desejada e formato abaixo.
--  Os log de execução de todos os scripts serão disponibilizado no output da SCTASK da REQ criada  no ServiceNow e no formato arquivo texto (txt).
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

print 'TERMINO DA EXECUÇÃO AUTOMATIZADA DE SCRIPTS'
GO