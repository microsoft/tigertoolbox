-- SQL 2019

-- Restore AdventureWorks
RESTORE DATABASE [AdventureWorks] 
FROM  DISK = N'C:\Labs\stress_tempdb\AdventureWorks2017.bak' 
WITH  FILE = 1
	,  MOVE N'AdventureWorks2017' TO N'F:\MSSQL\MSSQL15.SQL2019_CTP23\MSSQL\DATA\AdventureWorks.mdf'
	,  MOVE N'AdventureWorks2017_log' TO N'F:\MSSQL\MSSQL15.SQL2019_CTP23\MSSQL\DATA\AdventureWorks_log.ldf'
	,  NOUNLOAD,  STATS = 5

-- Turn off auto stats
USE [master]
GO
ALTER DATABASE [AdventureWorks] SET AUTO_CREATE_STATISTICS OFF
GO
ALTER DATABASE [AdventureWorks] SET AUTO_UPDATE_STATISTICS OFF WITH NO_WAIT
GO

-- Upgrade compatibility
ALTER DATABASE AdventureWorks
SET COMPATIBILITY_LEVEL = 150;  
GO
