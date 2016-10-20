USE [master]
GO
-- Limit error logs
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, 15
GO

-- Set sp_configure settings
EXEC sys.sp_configure N'show advanced options', N'1'
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'remote admin connections', N'1'
RECONFIGURE WITH OVERRIDE
GO
-- Use 'backup compression default' when server is NOT CPU bound
IF CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff) >= 10
EXEC sys.sp_configure N'backup compression default', N'1'
RECONFIGURE WITH OVERRIDE
GO
-- Use 'optimize for ad hoc workloads' for OLTP workloads ONLY
IF CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff) >= 10
EXEC sys.sp_configure N'optimize for ad hoc workloads', N'1'
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'
RECONFIGURE WITH OVERRIDE
GO

USE [master]
GO
-- Set model defaults
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modeldev', FILEGROWTH = 102400KB )
GO
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modellog', FILEGROWTH = 102400KB )
GO

-- Set database option defaults (ignore errors on tempdb and read-only databases)
USE [master]
GO
EXEC master.dbo.sp_MSforeachdb @command1='USE master; ALTER DATABASE [?] SET AUTO_CLOSE OFF WITH NO_WAIT'
EXEC master.dbo.sp_MSforeachdb @command1='USE master; ALTER DATABASE [?] SET AUTO_SHRINK OFF WITH NO_WAIT'
EXEC master.dbo.sp_MSforeachdb @command1='USE master; ALTER DATABASE [?] SET PAGE_VERIFY CHECKSUM WITH NO_WAIT'
--EXEC master.dbo.sp_MSforeachdb @command1='USE master; ALTER DATABASE [?] SET AUTO_CREATE_STATISTICS ON'
--EXEC master.dbo.sp_MSforeachdb @command1='USE master; ALTER DATABASE [?] SET AUTO_UPDATE_STATISTICS ON'
GO

--SET proper MaxDOP
DECLARE @cpucount int, @numa int, @affined_cpus int, @sqlcmd NVARCHAR(255)
SELECT @affined_cpus = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE is_online = 1 AND scheduler_id < 255 AND parent_node_id < 64;
SELECT @cpucount = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64
SELECT @numa = COUNT(DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64;
SELECT @sqlcmd = 'sp_configure ''max degree of parallelism'', ' + CONVERT(NVARCHAR(255), CASE WHEN [value] > @affined_cpus THEN @affined_cpus
		WHEN @numa = 1 AND @affined_cpus > 8 AND ([value] = 0 OR [value] > 8) THEN 8
		WHEN @numa > 1 AND (@cpucount/@numa) < 8 AND ([value] = 0 OR [value] > (@cpucount/@numa)) THEN @cpucount/@numa
		WHEN @numa > 1 AND (@cpucount/@numa) >= 8 AND ([value] = 0 OR [value] > 8 OR [value] > (@cpucount/@numa)) THEN 8
		ELSE 0
	END)
FROM sys.configurations (NOLOCK) WHERE name = 'max degree of parallelism';	

EXECUTE sp_executesql @sqlcmd;
GO

EXEC sys.sp_configure N'show advanced options', N'0'
RECONFIGURE WITH OVERRIDE
GO