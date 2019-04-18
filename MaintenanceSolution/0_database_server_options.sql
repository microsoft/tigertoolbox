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
SELECT @sqlcmd = 'sp_configure ''max degree of parallelism'', ' + CONVERT(NVARCHAR(255), 
		CASE 
		-- If not NUMA, and up to 16 @affined_cpus then MaxDOP up to 16
		WHEN @numa = 1 AND @affined_cpus <= 16 THEN @affined_cpus
		-- If not NUMA, and more than 16 @affined_cpus then MaxDOP 16
		WHEN @numa = 1 AND @affined_cpus > 16 THEN 16
		-- If NUMA and # logical CPUs per NUMA up to 16, then MaxDOP is set as # logical CPUs per NUMA, up to 16 
		WHEN @numa > 1 AND (@cpucount/@numa) <= 16 THEN CEILING(@cpucount/@numa)
		-- If NUMA and # logical CPUs per NUMA > 16, then MaxDOP is set as 1/2 of # logical CPUs per NUMA
		WHEN @numa > 1 AND (@cpucount/@numa) > 16 THEN CEILING((@cpucount/@numa)/2)
		ELSE 0
	END)
FROM sys.configurations (NOLOCK) WHERE name = 'max degree of parallelism';	

EXECUTE sp_executesql @sqlcmd;
GO

-- SET proper server memory (below calculations are for one instance only)
DECLARE @maxservermem bigint, @minservermem bigint, @systemmem bigint, @mwthreads_count int, @sqlmajorver int, @numa int, @numa_nodes_afinned tinyint, @arch NVARCHAR(10), @sqlcmd NVARCHAR(255)
-- Change below to 1 to set a max server memory config that is aligned with current affinied NUMA nodes.
DECLARE @numa_affined_config bit = 0

SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @arch = CASE WHEN @@VERSION LIKE '%<X64>%' THEN 64 WHEN @@VERSION LIKE '%<IA64>%' THEN 128 ELSE 32 END FROM sys.dm_os_windows_info WITH (NOLOCK);
SELECT @systemmem = total_physical_memory_kb/1024 FROM sys.dm_os_sys_memory;
SELECT @numa = COUNT(DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64;
SELECT @numa_nodes_afinned = COUNT (DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64 AND is_online = 1;
SELECT @minservermem = CONVERT(int, [value]) FROM sys.configurations WITH (NOLOCK) WHERE [Name] = 'min server memory (MB)';
SELECT @maxservermem = CONVERT(int, [value]) FROM sys.configurations WITH (NOLOCK) WHERE [Name] = 'max server memory (MB)';
SELECT @mwthreads_count = max_workers_count FROM sys.dm_os_sys_info;

IF (@maxservermem = 2147483647 OR @maxservermem > @systemmem) AND @numa_affined_config = 0
BEGIN
	SELECT @sqlcmd = 'sp_configure ''max server memory (MB)'', '+ CONVERT(NVARCHAR(20), 
		CASE WHEN @systemmem <= 2048 THEN @systemmem-512-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem BETWEEN 2049 AND 4096 THEN @systemmem-819-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem BETWEEN 4097 AND 8192 THEN @systemmem-1228-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem BETWEEN 8193 AND 12288 THEN @systemmem-2048-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem BETWEEN 12289 AND 24576 THEN @systemmem-2560-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem BETWEEN 24577 AND 32768 THEN @systemmem-3072-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') IN (284895786, 1293598313) THEN CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 65536) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 65536)) AS int) -- Find min of max mem for machine or max mem for Web and Business Intelligence SKU
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') = -1534726760 THEN CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 131072) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 131072)) AS int) -- Find min of max mem for machine or max mem for Standard SKU
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EngineEdition') IN (3,8) THEN @systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) -- Enterprise Edition or Managed Instance
		END);
	EXECUTE sp_executesql @sqlcmd;
END
ELSE IF (@maxservermem = 2147483647 OR @maxservermem > @systemmem) AND @numa_affined_config = 1
BEGIN
	SELECT @sqlcmd = 'sp_configure ''max server memory (MB)'', '+ CONVERT(NVARCHAR(20), 
		CASE WHEN @systemmem <= 2048 THEN ((@systemmem-512-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem BETWEEN 2049 AND 4096 THEN ((@systemmem-819-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem BETWEEN 4097 AND 8192 THEN ((@systemmem-1228-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem BETWEEN 8193 AND 12288 THEN ((@systemmem-2048-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem BETWEEN 12289 AND 24576 THEN ((@systemmem-2560-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem BETWEEN 24577 AND 32768 THEN ((@systemmem-3072-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') IN (284895786, 1293598313) THEN ((CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 65536) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 65536)) AS int))/@numa) * @numa_nodes_afinned -- Find min of max mem for machine or max mem for Web and Business Intelligence SKU
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') = -1534726760 THEN ((CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 131072) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 131072)) AS int))/@numa) * @numa_nodes_afinned -- Find min of max mem for machine or max mem for Standard SKU
			WHEN @systemmem > 32768 AND SERVERPROPERTY('EngineEdition') IN (3,8) THEN ((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END))/@numa) * @numa_nodes_afinned -- Enterprise Edition or Managed Instance
		END);
	EXECUTE sp_executesql @sqlcmd;
END;
GO

EXEC sys.sp_configure N'show advanced options', N'0'
RECONFIGURE WITH OVERRIDE
GO
