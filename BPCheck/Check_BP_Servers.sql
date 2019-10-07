USE [msdb]
GO

/*
Replace CREATE PROCEDURE with ALTER PROCEDURE or CREATE OR ALTER PROCEDURE to allow new changes to the SP if the SP is already present.

Usage examples:
EXEC usp_bpcheck
EXEC usp_bpcheck @allow_xpcmdshell = 0, @ptochecks = 1, @duration = 60
*/
 
CREATE PROCEDURE usp_bpcheck 
	@custompath NVARCHAR(500) = NULL, -- = 'C:\<temp_location>',
	@dbScope VARCHAR(256) = NULL, -- (NULL = All DBs; '<database_name>')	
	@allow_xpcmdshell bit = 1, --(1 = ON; 0 = OFF)
	@ptochecks bit = 1, --(1 = ON; 0 = OFF)
	@duration tinyint = 90, 
	@logdetail bit = 0, --(1 = ON; 0 = OFF) 
	@diskfrag bit = 1, --(1 = ON; 0 = OFF)
	@ixfrag bit = 1, --(1 = ON; 0 = OFF)
	@ixfragscanmode VARCHAR(8) = 'LIMITED', --(Valid inputs are DEFAULT, NULL, LIMITED, SAMPLED, or DETAILED. The default (NULL) is LIMITED)
	@bpool_consumer bit = 1, --(1 = ON; 0 = OFF)
	@spn_check bit = 0, --(1 = ON; 0 = OFF)
	@gen_scripts bit = 0 --(1 = ON; 0 = OFF)
AS 

/*
BP Check READ ME - http://aka.ms/BPCheck;

Checks SQL Server in scope for Performance issues and some of most common skewed Best Practices. 

Supports SQL Server (starting with SQL Server 2008) and Azure SQL Database Managed Instance. 
Note: Does not support Azure SQL Database single database or Elastic Pool. 

Important parameters for executing BPCheck:
Set @custompath below and set the custom desired path for .ps1 files. 
	If not, default location for .ps1 files is the Log folder.
Set @dbScope to the appropriate list of database IDs if there's a need to have a specific scope for database specific checks.
	Valid input should be numeric value(s) between single quotes, as follows: '1,6,15,123'
	Leave NULL for all databases
Set @allow_xpcmdshell to OFF if you want to skip checks that are dependant on xp_cmdshell. 
	Note that original server setting for xp_cmdshell would be left unchanged if tests were allowed.
Set @ptochecks to OFF if you want to skip more performance tuning and optimization oriented checks.
Set @duration to the number of seconds between data collection points regarding perf counters, waits and latches. 
	Duration must be between 10s and 255s (4m 15s), with a default of 90s.
Set @logdetail to OFF if you want to get just the summary info on issues in the Errorlog, rather than the full detail.
Set @diskfrag to ON if you want to check for disk physical fragmentation. 
	Can take some time in large disks. Requires elevated privileges.
	See https://support.microsoft.com/help/3195161/defragmenting-sql-server-database-disk-drives
Set @ixfrag to ON if you want to check for index fragmentation. 
	Can take some time to collect data depending on number of databases and indexes, as well as the scan mode chosen in @ixfragscanmode.
Set @ixfragscanmode to the scanning mode you prefer. 
	More detail on scanning modes available at https://docs.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-index-physical-stats-transact-sql
Set @bpool_consumer to OFF if you want to list what are the Buffer Pool Consumers from Buffer Descriptors. 
	Mind that it may take some time in servers with large caches.
Set @spn_check to OFF if you want to skip SPN checks.
Set @gen_scripts to ON if you want to generate index related scripts.
	These include drops for Duplicate, Redundant, Hypothetical and Rarely Used indexes, as well as creation statements for FK and Missing Indexes.
	
DISCLAIMER:
This code and information are provided "AS IS" without warranty of any kind, either expressed or implied.
Furthermore, the author or Microsoft shall not be liable for any damages you may sustain by using this information, whether direct, indirect, special, incidental or consequential, even if it has been advised of the possibility of such damages.
			
IMPORTANT pre-requisites:
- Only a sysadmin/local host admin will be able to perform all checks.
- If you want to perform all checks under non-sysadmin credentials, then that login must be:
	Member of serveradmin server role or have the ALTER SETTINGS server permission; 
	Member of MSDB SQLAgentOperatorRole role, or have SELECT permission on the sysalerts table in MSDB;
	Granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_enumerrorlogs, xp_fileexist and xp_regenumvalues;
	Granted EXECUTE permissions on xp_msver;
	Granted the VIEW SERVER STATE permission;
	Granted the VIEW DATABASE STATE permission;
	Granted EXECUTE permissions on xp_cmdshell or a xp_cmdshell proxy account should exist to run checks that access disk or OS security configurations.
	Member of securityadmin role, or have EXECUTE permissions on sp_readerrorlog. 
 Otherwise some checks will be bypassed and warnings will be shown.
- Powershell must be installed to run checks that access disk configurations, as well as allow execution of remote signed or unsigned scripts.
*/

BEGIN
SET NOCOUNT ON;
SET ANSI_WARNINGS ON;
SET QUOTED_IDENTIFIER ON;
SET DATEFORMAT mdy;

RAISERROR (N'Starting Pre-requisites section', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Pre-requisites section
--------------------------------------------------------------------------------------------------------------------------------
DECLARE @sqlcmd NVARCHAR(max), @params NVARCHAR(600), @sqlmajorver int

/*
Reference: SERVERPROPERTY for sql major, minor and build versions supported after:
@sqlmajorver >= 13 OR (@sqlmajorver = 12 AND @sqlbuild >= 2556 AND @sqlbuild < 4100) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427)
*/

SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 0)
BEGIN
	RAISERROR('[WARNING: Only a sysadmin can run ALL the checks]', 16, 1, N'sysadmin')
	--RETURN
END;

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 0)
BEGIN
	DECLARE @pid int, @pname sysname, @msdbpid int, @masterpid int
	DECLARE @permstbl TABLE ([name] sysname);
	DECLARE @permstbl_msdb TABLE ([id] tinyint IDENTITY(1,1), [perm] tinyint)
	
	SET @params = '@msdbpid_in int'

	SELECT @pid = principal_id, @pname=name FROM master.sys.server_principals (NOLOCK) WHERE sid = SUSER_SID()

	SELECT @masterpid = principal_id FROM master.sys.database_principals (NOLOCK) WHERE sid = SUSER_SID()

	SELECT @msdbpid = principal_id FROM msdb.sys.database_principals (NOLOCK) WHERE sid = SUSER_SID()

	-- Perms 1
	IF (ISNULL(IS_SRVROLEMEMBER(N'serveradmin'), 0) <> 1) AND ((SELECT COUNT(l.name)
		FROM master.sys.server_permissions p (NOLOCK) INNER JOIN master.sys.server_principals l (NOLOCK)
		ON p.grantee_principal_id = l.principal_id
			AND p.class = 100 -- Server
			AND p.state IN ('G', 'W') -- Granted or Granted with Grant
			AND l.is_disabled = 0
			AND p.permission_name = 'ALTER SETTINGS'
			AND QUOTENAME(l.name) = QUOTENAME(@pname)) = 0)
	BEGIN
		RAISERROR('[WARNING: If not sysadmin, then you must be a member of serveradmin server role or have the ALTER SETTINGS server permission. Exiting...]', 16, 1, N'serveradmin')
		RETURN
	END
	ELSE IF (ISNULL(IS_SRVROLEMEMBER(N'serveradmin'), 0) <> 1) AND ((SELECT COUNT(l.name)
		FROM master.sys.server_permissions p (NOLOCK) INNER JOIN sys.server_principals l (NOLOCK)
		ON p.grantee_principal_id = l.principal_id
			AND p.class = 100 -- Server
			AND p.state IN ('G', 'W') -- Granted or Granted with Grant
			AND l.is_disabled = 0
			AND p.permission_name = 'VIEW SERVER STATE'
			AND QUOTENAME(l.name) = QUOTENAME(@pname)) = 0)
	BEGIN
		RAISERROR('[WARNING: If not sysadmin, then you must be a member of serveradmin server role or granted the VIEW SERVER STATE permission. Exiting...]', 16, 1, N'serveradmin')
		RETURN
	END

	-- Perms 2
	INSERT INTO @permstbl
	SELECT a.name
	FROM master.sys.all_objects a (NOLOCK) INNER JOIN master.sys.database_permissions b (NOLOCK) ON a.[object_id] = b.major_id
	WHERE a.type IN ('P', 'X') AND b.grantee_principal_id <>0 
	AND b.grantee_principal_id <>2
	AND b.grantee_principal_id = @masterpid;

	INSERT INTO @permstbl_msdb ([perm])
	EXECUTE sp_executesql N'USE msdb; SELECT COUNT([name]) 
FROM msdb.sys.sysusers (NOLOCK) WHERE [uid] IN (SELECT [groupuid] 
	FROM msdb.sys.sysmembers (NOLOCK) WHERE [memberuid] = @msdbpid_in) 
AND [name] = ''SQLAgentOperatorRole''', @params, @msdbpid_in = @msdbpid;

	INSERT INTO @permstbl_msdb ([perm])
	EXECUTE sp_executesql N'USE msdb; SELECT COUNT(dp.grantee_principal_id)
FROM msdb.sys.tables AS tbl (NOLOCK)
INNER JOIN msdb.sys.database_permissions AS dp (NOLOCK) ON dp.major_id=tbl.object_id AND dp.class=1
INNER JOIN msdb.sys.database_principals AS grantor_principal (NOLOCK) ON grantor_principal.principal_id = dp.grantor_principal_id
INNER JOIN msdb.sys.database_principals AS grantee_principal (NOLOCK) ON grantee_principal.principal_id = dp.grantee_principal_id
WHERE dp.state = ''G''
	AND dp.grantee_principal_id = @msdbpid_in
	AND dp.type = ''SL''', @params, @msdbpid_in = @msdbpid;

	IF (SELECT [perm] FROM @permstbl_msdb WHERE [id] = 1) = 0 AND (SELECT [perm] FROM @permstbl_msdb WHERE [id] = 2) = 0
	BEGIN
		RAISERROR('[WARNING: If not sysadmin, then you must be a member of MSDB SQLAgentOperatorRole role, or have SELECT permission on the sysalerts table in MSDB to run full scope of checks]', 16, 1, N'msdbperms')
		--RETURN
	END
	ELSE IF (ISNULL(IS_SRVROLEMEMBER(N'securityadmin'), 0) <> 1) AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_enumerrorlogs') = 0 OR (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_readerrorlog') = 0 OR (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_readerrorlog') = 0)
	BEGIN
		RAISERROR('[WARNING: If not sysadmin, then you must be a member of the securityadmin server role, or have EXECUTE permission on the following extended sprocs to run full scope of checks: xp_enumerrorlogs, xp_readerrorlog, sp_readerrorlog]', 16, 1, N'secperms')
		--RETURN
	END
	ELSE IF (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') = 0 OR (SELECT COUNT(credential_id) FROM master.sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') = 0
	BEGIN
		RAISERROR('[WARNING: If not sysadmin, then you must be granted EXECUTE permissions on xp_cmdshell and a xp_cmdshell proxy account should exist to run full scope of checks]', 16, 1, N'xp_cmdshellproxy')
		--RETURN
	END
	ELSE IF (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') = 0 OR 
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') = 0 OR
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_servicecontrol') = 0 
	BEGIN
		RAISERROR('[WARNING: Must be a granted EXECUTE permissions on the following extended sprocs to run full scope of checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_fileexist, xp_regread, xp_instance_regread, xp_servicecontrol and xp_regenumvalues]', 16, 1, N'extended_sprocs')
		--RETURN
	END
	ELSE IF (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_msver') = 0 AND @sqlmajorver < 11
	BEGIN
		RAISERROR('[WARNING: Must be granted EXECUTE permissions on xp_msver to run full scope of checks]', 16, 1, N'extended_sprocs')
		--RETURN
	END
END;

-- Declare Global Variables
DECLARE @UpTime VARCHAR(12),@StartDate DATETIME
DECLARE @agt smallint, @ole smallint, @sao smallint, @xcmd smallint
DECLARE @ErrorSeverity int, @ErrorState int, @ErrorMessage NVARCHAR(4000)
DECLARE @CMD NVARCHAR(4000)
DECLARE @path NVARCHAR(2048)
DECLARE @sqlminorver int, @sqlbuild int, @clustered bit
DECLARE @osver VARCHAR(5), @ostype VARCHAR(10), @osdistro VARCHAR(20), @server VARCHAR(128), @instancename NVARCHAR(128), @arch smallint, @ossp VARCHAR(25), @SystemManufacturer VARCHAR(128), @BIOSVendor AS VARCHAR(128), @Processor_Name AS VARCHAR(128)
DECLARE @existout int, @FSO int, @FS int, @OLEResult int, @FileID int
DECLARE @FileName VARCHAR(200), @Text1 VARCHAR(2000), @CMD2 VARCHAR(100)
DECLARE @src VARCHAR(255), @desc VARCHAR(255), @psavail VARCHAR(20), @psver tinyint
DECLARE @dbid int, @dbname NVARCHAR(1000)

SELECT @instancename = CONVERT(VARCHAR(128),SERVERPROPERTY('InstanceName')) 
SELECT @server = RTRIM(CONVERT(VARCHAR(128), SERVERPROPERTY('MachineName')))
--SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff);
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);
SELECT @clustered = CONVERT(bit,ISNULL(SERVERPROPERTY('IsClustered'),0));

-- Test Powershell policy
IF @allow_xpcmdshell = 1
BEGIN
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
			AND (SELECT COUNT(l.name)
			FROM sys.server_permissions p JOIN sys.server_principals l 
			ON p.grantee_principal_id = l.principal_id
				AND p.class = 100 -- Server
				AND p.state IN ('G', 'W') -- Granted or Granted with Grant
				AND l.is_disabled = 0
				AND p.permission_name = 'ALTER SETTINGS'
				AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0)))
	BEGIN
		DECLARE @pstbl_avail TABLE ([KeyExist] int)
		BEGIN TRY
			INSERT INTO @pstbl_avail
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\PowerShell\1' -- check if Powershell is installed
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Could not determine if Powershell is installed - Error raised in TRY block. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
		SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
		SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

		RAISERROR ('|-Configuration options set for Powershell enablement verification', 10, 1) WITH NOWAIT
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
		END
		
		IF (SELECT [KeyExist] FROM @pstbl_avail) = 1
		BEGIN
			DECLARE @psavail_output TABLE ([PS_OUTPUT] VARCHAR(2048));
			INSERT INTO @psavail_output
			EXEC master.dbo.xp_cmdshell N'%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -Command "Get-ExecutionPolicy"'
		
			SELECT @psavail = [PS_OUTPUT] FROM @psavail_output WHERE [PS_OUTPUT] IS NOT NULL;
		END
		ELSE
		BEGIN
			RAISERROR ('   [WARNING: Powershell is not installed. Install WinRM to proceed with PS based checks]',16,1);
		END
				
		IF (@psavail IS NOT NULL AND @psavail NOT IN ('RemoteSigned','Unrestricted'))
		RAISERROR ('   [WARNING: Execution of Powershell scripts is disabled on this system.
To change the execution policy, type the following command in Powershell console: Set-ExecutionPolicy RemoteSigned
The Set-ExecutionPolicy cmdlet enables you to determine which Windows PowerShell scripts (if any) will be allowed to run on your computer. Windows PowerShell has four different execution policies:
	Restricted - No scripts can be run. Windows PowerShell can be used only in interactive mode.
	AllSigned - Only scripts signed by a trusted publisher can be run.
	RemoteSigned - Downloaded scripts must be signed by a trusted publisher before they can be run.
		|- REQUIRED by BP Check
	Unrestricted - No restrictions; all Windows PowerShell scripts can be run.]',16,1);

		IF (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted'))
		BEGIN
			RAISERROR ('|- [INFORMATION: Powershell is installed and enabled for script execution]', 10, 1) WITH NOWAIT
			
			DECLARE @psver_output TABLE ([PS_OUTPUT] VARCHAR(1024));
			INSERT INTO @psver_output
			EXEC master.dbo.xp_cmdshell N'%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -Command "Get-Host | Format-Table -Property Version"'
		
			-- Gets PS version, as commands issued to PS v1 do not support -File
			SELECT @psver = ISNULL(LEFT([PS_OUTPUT],1),2) FROM @psver_output WHERE [PS_OUTPUT] IS NOT NULL AND ISNUMERIC(LEFT([PS_OUTPUT],1)) = 1;
			
			SET @ErrorMessage = '|- [INFORMATION: Installed Powershell is version ' + CONVERT(CHAR(1), @psver) + ']'
			RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
		END;
		
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
		END;
	END
	ELSE
	BEGIN
		RAISERROR('   [WARNING: Missing permissions for Powershell enablement verification]', 16, 1, N'sysadmin')
		--RETURN
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Information section
--------------------------------------------------------------------------------------------------------------------------------

RAISERROR (N'Starting Information section', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Uptime subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Uptime', 10, 1) WITH NOWAIT
IF @sqlmajorver < 10
BEGIN
	SET @sqlcmd = N'SELECT @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()), @StartDateOUT = login_time FROM master..sysprocesses (NOLOCK) WHERE spid = 1';
END
ELSE
BEGIN
	SET @sqlcmd = N'SELECT @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()), @StartDateOUT = sqlserver_start_time FROM sys.dm_os_sys_info (NOLOCK)';
END

SET @params = N'@UpTimeOUT VARCHAR(12) OUTPUT, @StartDateOUT DATETIME OUTPUT';

EXECUTE sp_executesql @sqlcmd, @params, @UpTimeOUT=@UpTime OUTPUT, @StartDateOUT=@StartDate OUTPUT;

SELECT 'Information' AS [Category], 'Uptime' AS [Information], GETDATE() AS [Current_Time], @StartDate AS Last_Startup, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'hr ' + CONVERT(VARCHAR(4),@UpTime%60) + 'min' AS Uptime

--------------------------------------------------------------------------------------------------------------------------------
-- OS Version and Architecture subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Windows Version and Architecture', 10, 1) WITH NOWAIT
IF (@sqlmajorver >= 11 AND @sqlmajorver < 14) OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
BEGIN
	SET @sqlcmd = N'SELECT @ostypeOUT = ''Windows'', @osdistroOUT = ''Windows'', @osverOUT = CASE WHEN windows_release IN (''6.3'',''10.0'') AND (@@VERSION LIKE ''%Build 10586%'' OR @@VERSION LIKE ''%Build 14393%'') THEN ''10.0'' ELSE windows_release END, @osspOUT = windows_service_pack_level, @archOUT = CASE WHEN @@VERSION LIKE ''%<X64>%'' THEN 64 WHEN @@VERSION LIKE ''%<IA64>%'' THEN 128 ELSE 32 END FROM sys.dm_os_windows_info (NOLOCK)';
	SET @params = N'@osverOUT VARCHAR(5) OUTPUT, @ostypeOUT VARCHAR(10) OUTPUT, @osdistroOUT VARCHAR(20) OUTPUT, @osspOUT VARCHAR(25) OUTPUT, @archOUT smallint OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @osverOUT=@osver OUTPUT, @ostypeOUT=@ostype OUTPUT, @osdistroOUT=@osdistro OUTPUT, @osspOUT=@ossp OUTPUT, @archOUT=@arch OUTPUT;
END
ELSE IF @sqlmajorver >= 14
BEGIN
	SET @sqlcmd = N'SELECT @ostypeOUT = host_platform, @osdistroOUT = host_distribution, @osverOUT = CASE WHEN host_platform = ''Windows'' AND host_release IN (''6.3'',''10.0'') THEN ''10.0'' ELSE host_release END, @osspOUT = host_service_pack_level, @archOUT = CASE WHEN @@VERSION LIKE ''%<X64>%'' THEN 64 ELSE 32 END FROM sys.dm_os_host_info (NOLOCK)';
	SET @params = N'@osverOUT VARCHAR(5) OUTPUT, @ostypeOUT VARCHAR(10) OUTPUT, @osdistroOUT VARCHAR(20) OUTPUT, @osspOUT VARCHAR(25) OUTPUT, @archOUT smallint OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @osverOUT=@osver OUTPUT, @ostypeOUT=@ostype OUTPUT, @osdistroOUT=@osdistro OUTPUT, @osspOUT=@ossp OUTPUT, @archOUT=@arch OUTPUT;
END
ELSE
BEGIN
	BEGIN TRY
		DECLARE @str VARCHAR(500), @str2 VARCHAR(500), @str3 VARCHAR(500)
		DECLARE @sysinfo TABLE (id int, 
			[Name] NVARCHAR(256), 
			Internal_Value bigint, 
			Character_Value NVARCHAR(256));
			
		INSERT INTO @sysinfo
		EXEC xp_msver;
		
		SELECT @osver = LEFT(Character_Value, CHARINDEX(' ', Character_Value)-1) -- 5.2 is WS2003; 6.0 is WS2008; 6.1 is WS2008R2; 6.2 is WS2012, 6.3 is WS2012R2, 6.3 (14396) is WS2016
		FROM @sysinfo
		WHERE [Name] LIKE 'WindowsVersion%';
		
		SELECT @arch = CASE WHEN RTRIM(Character_Value) LIKE '%x64%' OR RTRIM(Character_Value) LIKE '%AMD64%' THEN 64
			WHEN RTRIM(Character_Value) LIKE '%x86%' OR RTRIM(Character_Value) LIKE '%32%' THEN 32
			WHEN RTRIM(Character_Value) LIKE '%IA64%' THEN 128 END
		FROM @sysinfo
		WHERE [Name] LIKE 'Platform%';
		
		SET @str = (SELECT @@VERSION)
		SELECT @str2 = RIGHT(@str, LEN(@str)-CHARINDEX('Windows',@str) + 1)
		SELECT @str3 = RIGHT(@str2, LEN(@str2)-CHARINDEX(': ',@str2))
		SELECT @ossp = LTRIM(LEFT(@str3, CHARINDEX(')',@str3) -1))
		SET @ostype = 'Windows'
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Windows Version and Architecture subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END;

DECLARE @machineinfo TABLE ([Value] NVARCHAR(256), [Data] NVARCHAR(256))

IF @ostype = 'Windows'
BEGIN
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','SystemManufacturer';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','SystemProductName';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','SystemFamily';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','BIOSVendor';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','BIOSVersion';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\BIOS','BIOSReleaseDate';
	INSERT INTO @machineinfo
	EXEC xp_instance_regread 'HKEY_LOCAL_MACHINE','HARDWARE\DESCRIPTION\System\CentralProcessor\0','ProcessorNameString';
END;

SELECT @SystemManufacturer = [Data] FROM @machineinfo WHERE [Value] = 'SystemManufacturer';
SELECT @BIOSVendor = [Data] FROM @machineinfo WHERE [Value] = 'BIOSVendor';
SELECT @Processor_Name = [Data] FROM @machineinfo WHERE [Value] = 'ProcessorNameString';

SELECT 'Information' AS [Category], 'Machine' AS [Information], 
	CASE @osver WHEN '5.2' THEN 'XP/WS2003'
		WHEN '6.0' THEN 'Vista/WS2008'
		WHEN '6.1' THEN 'W7/WS2008R2'
		WHEN '6.2' THEN 'W8/WS2012'
		WHEN '6.3' THEN 'W8.1/WS2012R2'
		WHEN '10.0' THEN 'W10/WS2016'
		ELSE @ostype + ' ' + @osdistro
	END AS [OS_Version],
	CASE WHEN @ostype = 'Windows' THEN @ossp ELSE @osver END AS [Service_Pack_Level],
	@arch AS [Architecture],
	SERVERPROPERTY('MachineName') AS [Machine_Name],
	SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS [NetBIOS_Name],
	@SystemManufacturer AS [System_Manufacturer],
	(SELECT [Data] FROM @machineinfo WHERE [Value] = 'SystemFamily') AS [System_Family],
	(SELECT [Data] FROM @machineinfo WHERE [Value] = 'SystemProductName') AS [System_ProductName],
	@BIOSVendor AS [BIOS_Vendor],
	(SELECT [Data] FROM @machineinfo WHERE [Value] = 'BIOSVersion') AS [BIOS_Version],
	(SELECT [Data] FROM @machineinfo WHERE [Value] = 'BIOSReleaseDate') AS [BIOS_Release_Date],
	@Processor_Name AS [Processor_Name];

--------------------------------------------------------------------------------------------------------------------------------
-- Disk space subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 10 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
BEGIN
	RAISERROR (N'|-Starting Disk space', 10, 1) WITH NOWAIT
	SELECT DISTINCT 'Information' AS [Category], 'Disk_Space' AS [Information], vs.logical_volume_name,
		vs.volume_mount_point, vs.file_system_type, CONVERT(int,vs.total_bytes/1048576.0) AS TotalSpace_MB,
		CONVERT(int,vs.available_bytes/1048576.0) AS FreeSpace_MB, vs.is_compressed
	FROM sys.master_files mf
	CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.[file_id]) vs
	ORDER BY FreeSpace_MB ASC
END;
	
--------------------------------------------------------------------------------------------------------------------------------
-- HA Information subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting HA Information', 10, 1) WITH NOWAIT
IF @clustered = 1
BEGIN
	IF @sqlmajorver < 11
		BEGIN
			EXEC ('SELECT ''Information'' AS [Category], ''Cluster'' AS [Information], NodeName AS node_name FROM sys.dm_os_cluster_nodes (NOLOCK)')
		END
	ELSE
		BEGIN
			EXEC ('SELECT ''Information'' AS [Category], ''Cluster'' AS [Information], NodeName AS node_name, status_description, is_current_owner FROM sys.dm_os_cluster_nodes (NOLOCK)')
		END
	SELECT 'Information' AS [Category], 'Cluster' AS [Information], DriveName AS cluster_shared_drives FROM sys.dm_io_cluster_shared_drives (NOLOCK)
END
ELSE
BEGIN
	SELECT 'Information' AS [Category], 'Cluster' AS [Information], 'NOT_CLUSTERED' AS [Status]
END;

IF @sqlmajorver > 10
BEGIN
	DECLARE @IsHadrEnabled tinyint, @HadrManagerStatus tinyint
	SELECT @IsHadrEnabled = CASE WHEN SERVERPROPERTY('EngineEdition') = 8 THEN 1 ELSE CONVERT(tinyint, SERVERPROPERTY('IsHadrEnabled')) END;
	SELECT @HadrManagerStatus = CASE WHEN SERVERPROPERTY('EngineEdition') = 8 THEN 1 ELSE CONVERT(tinyint, SERVERPROPERTY('HadrManagerStatus')) END;
	
	SELECT 'Information' AS [Category], 'AlwaysOn_AG' AS [Information], 
		CASE @IsHadrEnabled WHEN 0 THEN 'Disabled'
			WHEN 1 THEN 'Enabled' END AS [AlwaysOn_Availability_Groups],
		CASE WHEN @IsHadrEnabled = 1 THEN
			CASE @HadrManagerStatus WHEN 0 THEN '[Not started, pending communication]'
				WHEN 1 THEN '[Started and running]'
				WHEN 2 THEN '[Not started and failed]'
			END
		END AS [Status];
	
	IF @IsHadrEnabled = 1
	BEGIN	
		IF EXISTS (SELECT 1 FROM sys.dm_hadr_cluster) 
		SELECT 'Information' AS [Category], 'AlwaysOn_Cluster' AS [Information], cluster_name, quorum_type_desc, quorum_state_desc 
		FROM sys.dm_hadr_cluster;

		IF EXISTS (SELECT 1 FROM sys.dm_hadr_cluster_members) 
		SELECT 'Information' AS [Category], 'AlwaysOn_Cluster_Members' AS [Information], member_name, member_type_desc, member_state_desc, number_of_quorum_votes 
		FROM sys.dm_hadr_cluster_members;
		
		IF EXISTS (SELECT 1 FROM sys.dm_hadr_cluster_networks) 
		SELECT 'Information' AS [Category], 'AlwaysOn_Cluster_Networks' AS [Information], member_name, network_subnet_ip, network_subnet_ipv4_mask, is_public, is_ipv4 
		FROM sys.dm_hadr_cluster_networks;
	END;
	
	IF @ptochecks = 1 AND @IsHadrEnabled = 1
	BEGIN
		-- Note: If low_water_mark_for_ghosts number is not increasing over time, it implies that ghost cleanup might not happen.
		SET @sqlcmd = 'SELECT ''Information'' AS [Category], ''AlwaysOn_Replicas'' AS [Information], database_id, group_id, replica_id, group_database_id, is_local, synchronization_state_desc, 
	is_commit_participant, synchronization_health_desc, database_state_desc, is_suspended, suspend_reason_desc, last_sent_time, last_received_time, last_hardened_time, 
	last_redone_time, log_send_queue_size, log_send_rate, redo_queue_size, redo_rate, filestream_send_rate, last_commit_time, 
	low_water_mark_for_ghosts' + CASE WHEN @sqlmajorver > 12 THEN ', secondary_lag_seconds' ELSE '' END + ' 
FROM sys.dm_hadr_database_replica_states'
		EXECUTE sp_executesql @sqlcmd

		SELECT 'Information' AS [Category], 'AlwaysOn_Replica_Cluster' AS [Information], replica_id, group_database_id, database_name, is_failover_ready, is_pending_secondary_suspend, 
			is_database_joined, recovery_lsn, truncation_lsn 
		FROM sys.dm_hadr_database_replica_cluster_states;
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Linked servers info subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Linked servers info', 10, 1) WITH NOWAIT
IF (SELECT COUNT(*) FROM sys.servers AS s INNER JOIN sys.linked_logins AS l (NOLOCK) ON s.server_id = l.server_id LEFT OUTER JOIN sys.server_principals AS p (NOLOCK) ON p.principal_id = l.local_principal_id WHERE s.is_linked = 1) > 0
BEGIN
	SET @sqlcmd = 'SELECT ''Information'' AS [Category], ''Linked_servers'' AS [Information], s.name, s.product, 
	s.provider, s.data_source, s.location, s.provider_string, s.catalog, s.connect_timeout, 
	s.query_timeout, s.is_linked, s.is_remote_login_enabled, s.is_rpc_out_enabled, 
	s.is_data_access_enabled, s.is_collation_compatible, s.uses_remote_collation, s.collation_name, 
	s.lazy_schema_validation, s.is_system, s.is_publisher, s.is_subscriber, s.is_distributor, 
	s.is_nonsql_subscriber' + CASE WHEN @sqlmajorver > 9 THEN ', s.is_remote_proc_transaction_promotion_enabled' ELSE '' END + ',
	s.modify_date, CASE WHEN l.local_principal_id = 0 THEN ''local or wildcard'' ELSE p.name END AS [local_principal], 
	CASE WHEN l.uses_self_credential = 0 THEN ''use own credentials'' ELSE ''use supplied username and pwd'' END AS uses_self_credential, 
	l.remote_name, l.modify_date AS [linked_login_modify_date]
FROM sys.servers AS s (NOLOCK)
INNER JOIN sys.linked_logins AS l (NOLOCK) ON s.server_id = l.server_id
LEFT OUTER JOIN sys.server_principals AS p (NOLOCK) ON p.principal_id = l.local_principal_id
WHERE s.is_linked = 1'
	EXECUTE sp_executesql @sqlcmd
END
ELSE
BEGIN
	SELECT 'Information' AS [Category], 'Linked_servers' AS [Information], '[None]' AS [Status]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Instance info subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Instance info', 10, 1) WITH NOWAIT
DECLARE @port VARCHAR(15), @replication int, @RegKey NVARCHAR(255), @cpuaffin VARCHAR(300), @cpucount int, @numa int
DECLARE @i int, @cpuaffin_fixed VARCHAR(300), @affinitymask NVARCHAR(64), @affinity64mask NVARCHAR(1024)--, @cpuover32 int

IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild < 2500)
BEGIN
	IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') = 1)
	BEGIN
		BEGIN TRY
			SELECT @RegKey = CASE WHEN CONVERT(VARCHAR(128), SERVERPROPERTY('InstanceName')) IS NULL THEN N'Software\Microsoft\MSSQLServer\MSSQLServer\SuperSocketNetLib\Tcp'
				ELSE N'Software\Microsoft\Microsoft SQL Server\' + CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(128)) + N'\MSSQLServer\SuperSocketNetLib\Tcp' END
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @RegKey, N'TcpPort', @port OUTPUT, NO_OUTPUT
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Instance info subsection - Error raised in TRY block 1. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Missing permissions for full "Instance info" checks. Bypassing TCP port check]', 16, 1, N'sysadmin')
		--RETURN
	END
END
ELSE
BEGIN
	BEGIN TRY
		/*
		SET @sqlcmd = N'SELECT @portOUT = MAX(CONVERT(VARCHAR(15),value_data)) FROM sys.dm_server_registry WHERE registry_key LIKE ''%MSSQLServer\SuperSocketNetLib\Tcp\%'' AND value_name LIKE N''%TcpPort%'' AND CONVERT(float,value_data) > 0;';
		SET @params = N'@portOUT VARCHAR(15) OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @portOUT = @port OUTPUT;
		IF @port IS NULL
		BEGIN
			SET @sqlcmd = N'SELECT @portOUT = CONVERT(VARCHAR(15),value_data) FROM sys.dm_server_registry WHERE registry_key LIKE ''%MSSQLServer\SuperSocketNetLib\Tcp\%'' AND value_name LIKE N''%TcpDynamicPort%'' AND CONVERT(float,value_data) > 0;';
			SET @params = N'@portOUT VARCHAR(15) OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @portOUT = @port OUTPUT;
		END
		*/
		SET @sqlcmd = N'SELECT @portOUT = MAX(CONVERT(VARCHAR(15),port)) FROM sys.dm_tcp_listener_states WHERE is_ipv4 = 1 AND [type] = 0 AND ip_address <> ''127.0.0.1'';';
		SET @params = N'@portOUT VARCHAR(15) OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @portOUT = @port OUTPUT;
		IF @port IS NULL
		BEGIN
			SET @sqlcmd = N'SELECT @portOUT = MAX(CONVERT(VARCHAR(15),port)) FROM sys.dm_tcp_listener_states WHERE is_ipv4 = 0 AND [type] = 0 AND ip_address <> ''127.0.0.1'';';
			SET @params = N'@portOUT VARCHAR(15) OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @portOUT = @port OUTPUT;
		END
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Instance info subsection - Error raised in TRY block 2. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') = 1)
BEGIN
	BEGIN TRY
		EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\Replication', N'IsInstalled', @replication OUTPUT, NO_OUTPUT
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Instance info subsection - Error raised in TRY block 3. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END
ELSE
BEGIN
	RAISERROR('[WARNING: Missing permissions for full "Instance info" checks. Bypassing replication check]', 16, 1, N'sysadmin')
	--RETURN
END

SELECT @cpucount = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64
SELECT @numa = COUNT(DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64;

;WITH bits AS 
(SELECT 7 AS N, 128 AS E UNION ALL SELECT 6, 64 UNION ALL 
SELECT 5, 32 UNION ALL SELECT 4, 16 UNION ALL SELECT 3, 8 UNION ALL 
SELECT 2, 4 UNION ALL SELECT 1, 2 UNION ALL SELECT 0, 1), 
bytes AS 
(SELECT 1 M UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL 
SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL 
SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)
-- CPU Affinity is shown highest to lowest CPU ID
SELECT @affinitymask = CASE WHEN [value] = 0 THEN REPLICATE('1', @cpucount)
	ELSE RIGHT((SELECT ((CONVERT(tinyint, SUBSTRING(CONVERT(binary(9), [value]), M, 1)) & E) / E) AS [text()] 
		FROM bits CROSS JOIN bytes
		ORDER BY M, N DESC
		FOR XML PATH('')), @cpucount) END
FROM sys.configurations (NOLOCK)
WHERE name = 'affinity mask';

IF @cpucount > 32
BEGIN
	;WITH bits AS 
	(SELECT 7 AS N, 128 AS E UNION ALL SELECT 6, 64 UNION ALL 
	SELECT 5, 32 UNION ALL SELECT 4, 16 UNION ALL SELECT 3, 8 UNION ALL 
	SELECT 2, 4 UNION ALL SELECT 1, 2 UNION ALL SELECT 0, 1), 
	bytes AS 
	(SELECT 1 M UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL 
	SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL 
	SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)
	-- CPU Affinity is shown highest to lowest CPU ID
	SELECT @affinity64mask = CASE WHEN [value] = 0 THEN REPLICATE('1', @cpucount)
		ELSE RIGHT((SELECT ((CONVERT(tinyint, SUBSTRING(CONVERT(binary(9), [value]), M, 1)) & E) / E) AS [text()] 
			FROM bits CROSS JOIN bytes
			ORDER BY M, N DESC
			FOR XML PATH('')), @cpucount) END
	FROM sys.configurations (NOLOCK)
	WHERE name = 'affinity64 mask';
END;

/*
IF @cpucount > 32
SELECT @cpuover32 = ABS(LEN(@affinity64mask) - (@cpucount-32))

SELECT @cpuaffin = CASE WHEN @cpucount > 32 THEN REVERSE(LEFT(REVERSE(@affinity64mask),@cpuover32)) + RIGHT(@affinitymask,32) ELSE RIGHT(@affinitymask,@cpucount) END
*/

SELECT @cpuaffin = CASE WHEN @cpucount > 32 THEN @affinity64mask ELSE @affinitymask END

SET @cpuaffin_fixed = @cpuaffin

IF @numa > 1
BEGIN
	-- format binary mask by node for better reading
	SET @i = CEILING(@cpucount*1.00/@numa) + 1
	WHILE @i < @cpucount + @numa
	BEGIN
		IF (@cpucount + @numa) - @i >= CEILING(@cpucount*1.00/@numa)
		BEGIN
			SELECT @cpuaffin_fixed = STUFF(@cpuaffin_fixed, @i, 1, '_' + SUBSTRING(@cpuaffin_fixed, @i, 1))
		END
		ELSE
		BEGIN
			SELECT @cpuaffin_fixed = STUFF(@cpuaffin_fixed, @i, CEILING(@cpucount*1.00/@numa), SUBSTRING(@cpuaffin_fixed, @i, CEILING(@cpucount*1.00/@numa)))
		END

		SET @i = @i + CEILING(@cpucount*1.00/@numa) + 1
	END
END

SELECT 'Information' AS [Category], 'Instance' AS [Information],
	(CASE WHEN CONVERT(VARCHAR(128), SERVERPROPERTY('InstanceName')) IS NULL THEN 'DEFAULT_INSTANCE'
		ELSE CONVERT(VARCHAR(128), SERVERPROPERTY('InstanceName')) END) AS Instance_Name,
	(CASE WHEN SERVERPROPERTY('IsClustered') = 1 THEN 'CLUSTERED' 
		WHEN SERVERPROPERTY('IsClustered') = 0 THEN 'NOT_CLUSTERED'
		ELSE 'INVALID INPUT/ERROR' END) AS Failover_Clustered,
	/*The version of SQL Server instance in the form: major.minor.build*/	
	CONVERT(VARCHAR(128), SERVERPROPERTY('ProductVersion')) AS Product_Version,
	/*Level of the version of SQL Server Instance*/
	CASE WHEN (@sqlmajorver = 11 AND @sqlminorver >= 6020) OR (@sqlmajorver = 12 AND @sqlminorver BETWEEN 2556 AND 2569) OR (@sqlmajorver = 12 AND @sqlminorver >= 4427) OR @sqlmajorver >= 13 THEN 
		CONVERT(VARCHAR(128), SERVERPROPERTY('ProductBuildType'))
	ELSE 'NA' END AS Product_Build_Type,
	CONVERT(VARCHAR(128), SERVERPROPERTY('ProductLevel')) AS Product_Level,
	CASE WHEN (@sqlmajorver = 11 AND @sqlminorver >= 6020) OR (@sqlmajorver = 12 AND @sqlminorver BETWEEN 2556 AND 2569) OR (@sqlmajorver = 12 AND @sqlminorver >= 4427) OR @sqlmajorver >= 13 THEN 
		CONVERT(VARCHAR(128), SERVERPROPERTY('ProductUpdateLevel'))
	ELSE 'NA' END AS Product_Update_Level,
	CASE WHEN (@sqlmajorver = 11 AND @sqlminorver >= 6020) OR (@sqlmajorver = 12 AND @sqlminorver BETWEEN 2556 AND 2569) OR (@sqlmajorver = 12 AND @sqlminorver >= 4427) OR @sqlmajorver >= 13 THEN 
		CONVERT(VARCHAR(128), SERVERPROPERTY('ProductUpdateReference'))
	ELSE 'NA' END AS Product_Update_Ref_KB,
	CONVERT(VARCHAR(128), SERVERPROPERTY('Edition')) AS Edition,
	CONVERT(VARCHAR(128), SERVERPROPERTY('MachineName')) AS Machine_Name,
	RTRIM(@port) AS TCP_Port,
	@@SERVICENAME AS Service_Name,
	/*To identify which sqlservr.exe belongs to this instance*/
	SERVERPROPERTY('ProcessID') AS Process_ID, 
	CONVERT(VARCHAR(128), SERVERPROPERTY('ServerName')) AS Server_Name,
	@cpuaffin_fixed AS Affinity_Mask_Bitmask,
	CONVERT(VARCHAR(128), SERVERPROPERTY('Collation')) AS [Server_Collation],
	(CASE WHEN @replication = 1 THEN 'Installed' 
		WHEN @replication = 0 THEN 'Not_Installed' 
		ELSE 'INVALID INPUT/ERROR' END) AS Replication_Components_Installation,
	(CASE WHEN SERVERPROPERTY('IsFullTextInstalled') = 1 THEN 'Installed' 
		WHEN SERVERPROPERTY('IsFulltextInstalled') = 0 THEN 'Not_Installed' 
		ELSE 'INVALID INPUT/ERROR' END) AS Full_Text_Installation,
	(CASE WHEN SERVERPROPERTY('IsIntegratedSecurityOnly') = 1 THEN 'Integrated_Security' 
		WHEN SERVERPROPERTY('IsIntegratedSecurityOnly') = 0 THEN 'SQL_Server_Security' 
		ELSE 'INVALID INPUT/ERROR' END) AS [Security],
	(CASE WHEN SERVERPROPERTY('IsSingleUser') = 1 THEN 'Single_User' 
		WHEN SERVERPROPERTY('IsSingleUser') = 0	THEN 'Multi_User' 
		ELSE 'INVALID INPUT/ERROR' END) AS [Single_User],
	(CASE WHEN CONVERT(VARCHAR(128), SERVERPROPERTY('LicenseType')) = 'PER_SEAT' THEN 'Per_Seat_Mode' 
		WHEN CONVERT(VARCHAR(128), SERVERPROPERTY('LicenseType')) = 'PER_PROCESSOR' THEN 'Per_Processor_Mode' 
		ELSE 'Disabled' END) AS License_Type, -- From SQL Server 2008R2 always returns DISABLED.
	CONVERT(NVARCHAR(128), SERVERPROPERTY('BuildClrVersion')) AS CLR_Version,
	CASE WHEN @sqlmajorver >= 10 THEN 
		CASE WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 0 THEN 'Disabled'
			WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 1 THEN 'Enabled_for_TSQL'
			ELSE 'Enabled for TSQL and Win32' END
	ELSE 'Not compatible' END AS Filestream_Configured_Level,
	CASE WHEN @sqlmajorver >= 10 THEN 
		CASE WHEN SERVERPROPERTY('FilestreamEffectiveLevel') = 0 THEN 'Disabled'
			WHEN SERVERPROPERTY('FilestreamEffectiveLevel') = 1 THEN 'Enabled_for_TSQL'
			ELSE 'Enabled for TSQL and Win32' END
	ELSE 'Not compatible' END AS Filestream_Effective_Level,
	CASE WHEN @sqlmajorver >= 10 THEN 
		SERVERPROPERTY('FilestreamShareName')
	ELSE 'Not compatible' END AS Filestream_Share_Name,
	CASE WHEN @sqlmajorver >= 12 THEN 
		SERVERPROPERTY('IsXTPSupported')
	ELSE 'Not compatible' END AS XTP_Compatible,
	CASE WHEN @sqlmajorver >= 13 THEN 
		SERVERPROPERTY('IsPolybaseInstalled')
	ELSE 'Not compatible' END AS Polybase_Installed,
	CASE WHEN @sqlmajorver >= 13 THEN 
		SERVERPROPERTY('IsAdvancedAnalyticsInstalled')
	ELSE 'Not compatible' END AS R_Services_Installed;
	
--------------------------------------------------------------------------------------------------------------------------------
-- Buffer Pool Extension info subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Buffer Pool Extension info', 10, 1) WITH NOWAIT

IF @sqlmajorver > 11
BEGIN
	SELECT 'Information' AS [Category], 'BP_Extension' AS [Information], 
		CASE WHEN state = 0 THEN 'BP_Extension_Disabled' 
			WHEN state = 1 THEN 'BP_Extension_is_Disabling'
			WHEN state = 3 THEN 'BP_Extension_is_Enabling'
			WHEN state = 5 THEN 'BP_Extension_Enabled'
		END AS state, 
		[path], current_size_in_kb
	FROM sys.dm_os_buffer_pool_extension_configuration
END
ELSE
BEGIN
	SELECT 'Information' AS [Category], 'BP_Extension' AS [Information], '[NA]' AS state
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Resource Governor info subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Resource Governor info', 10, 1) WITH NOWAIT

IF @sqlmajorver > 9
BEGIN
	SELECT 'Information' AS [Category], 'RG_Classifier_Function' AS [Information], CASE WHEN classifier_function_id = 0 THEN 'Default_Configuration' ELSE OBJECT_SCHEMA_NAME(classifier_function_id) + '.' + OBJECT_NAME(classifier_function_id) END AS classifier_function, is_reconfiguration_pending
	FROM sys.dm_resource_governor_configuration

	SET @sqlcmd = 'SELECT ''Information'' AS [Category], ''RG_Resource_Pool'' AS [Information], rp.pool_id, name, statistics_start_time, total_cpu_usage_ms, cache_memory_kb, compile_memory_kb, 
	used_memgrant_kb, total_memgrant_count, total_memgrant_timeout_count, active_memgrant_count, active_memgrant_kb, memgrant_waiter_count, max_memory_kb, used_memory_kb, target_memory_kb, 
	out_of_memory_count, min_cpu_percent, max_cpu_percent, min_memory_percent, max_memory_percent' + CASE WHEN @sqlmajorver > 10 THEN ', cap_cpu_percent, rpa.processor_group, rpa.scheduler_mask' ELSE '' END + '
FROM sys.dm_resource_governor_resource_pools rp' + CASE WHEN @sqlmajorver > 10 THEN ' LEFT JOIN sys.dm_resource_governor_resource_pool_affinity rpa ON rp.pool_id = rpa.pool_id' ELSE '' END
	EXECUTE sp_executesql @sqlcmd

	SET @sqlcmd = 'SELECT ''Information'' AS [Category], ''RG_Workload_Groups'' AS [Information], group_id, name, pool_id, statistics_start_time, total_request_count, total_queued_request_count, 
	active_request_count, queued_request_count, total_cpu_limit_violation_count, total_cpu_usage_ms, max_request_cpu_time_ms, blocked_task_count, total_lock_wait_count, 
	total_lock_wait_time_ms, total_query_optimization_count, total_suboptimal_plan_generation_count, total_reduced_memgrant_count, max_request_grant_memory_kb, 
	active_parallel_thread_count, importance, request_max_memory_grant_percent, request_max_cpu_time_sec, request_memory_grant_timeout_sec, 
	group_max_requests, max_dop' + CASE WHEN @sqlmajorver > 10 THEN ', effective_max_dop' ELSE '' END + ' 
FROM sys.dm_resource_governor_workload_groups'
	EXECUTE sp_executesql @sqlcmd
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Logon triggers subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Logon triggers', 10, 1) WITH NOWAIT
IF (SELECT COUNT([name]) FROM sys.server_triggers WHERE is_disabled = 0 AND is_ms_shipped = 0) > 0
BEGIN
	SELECT 'Information' AS [Category], 'Logon_Triggers' AS [Information], name AS [Trigger_Name], type_desc AS [Trigger_Type],create_date, modify_date
	FROM sys.server_triggers WHERE is_disabled = 0 AND is_ms_shipped = 0
	ORDER BY name;
END
ELSE
BEGIN
	SELECT 'Information' AS [Category], 'Logon_Triggers' AS [Information], '[NA]' AS [Comment]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Database Information subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Database Information', 10, 1) WITH NOWAIT
RAISERROR (N'  |-Building DB list', 10, 1) WITH NOWAIT
DECLARE @curdbname NVARCHAR(1000), @curdbid int, @currole tinyint, @cursecondary_role_allow_connections tinyint, @state tinyint

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs0'))
DROP TABLE #tmpdbs0;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs0'))
CREATE TABLE #tmpdbs0 (id int IDENTITY(1,1), [dbid] int, [dbname] NVARCHAR(1000), [compatibility_level] tinyint, is_read_only bit, [state] tinyint, is_distributor bit, [role] tinyint, [secondary_role_allow_connections] tinyint, is_database_joined bit, is_failover_ready bit, is_query_store_on bit, isdone bit);

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbfiledetail'))
DROP TABLE #tmpdbfiledetail;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbfiledetail'))
CREATE TABLE #tmpdbfiledetail([database_id] [int] NOT NULL, [file_id] int, [type_desc] NVARCHAR(60), [data_space_id] int, [name] sysname, [physical_name] NVARCHAR(260), [state_desc] NVARCHAR(60), [size] bigint, [max_size] bigint, [is_percent_growth] bit, [growth] int, [is_media_read_only] bit, [is_read_only] bit, [is_sparse] bit, [is_name_reserved] bit)

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tmpdbsizes'))
DROP TABLE ##tmpdbsizes;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tmpdbsizes'))
CREATE TABLE ##tmpdbsizes([database_id] [int] NOT NULL, [size] bigint, [type_desc] NVARCHAR(60))

IF @sqlmajorver < 11
BEGIN
	SET @sqlcmd = 'SELECT database_id, name, [compatibility_level], is_read_only, [state], is_distributor, 1, 1, 0, 0 FROM master.sys.databases (NOLOCK)'
	INSERT INTO #tmpdbs0 ([dbid], [dbname], [compatibility_level], is_read_only, [state], is_distributor, [role], [secondary_role_allow_connections], is_query_store_on, [isdone])
	EXEC sp_executesql @sqlcmd;
END;

IF @sqlmajorver IN (11,12)
BEGIN
	SET @sqlcmd = 'SELECT sd.database_id, sd.name, sd.[compatibility_level], sd.is_read_only, sd.[state], sd.is_distributor, MIN(COALESCE(ars.[role],1)) AS [role], ar.secondary_role_allow_connections, rcs.is_database_joined, rcs.is_failover_ready, 0, 0 
	FROM master.sys.databases (NOLOCK) sd
		LEFT JOIN sys.dm_hadr_database_replica_states (NOLOCK) d ON sd.database_id = d.database_id
		LEFT JOIN sys.availability_replicas ar (NOLOCK) ON d.group_id = ar.group_id AND d.replica_id = ar.replica_id
		LEFT JOIN sys.dm_hadr_availability_replica_states (NOLOCK) ars ON d.group_id = ars.group_id AND d.replica_id = ars.replica_id
		LEFT JOIN sys.dm_hadr_database_replica_cluster_states (NOLOCK) rcs ON rcs.database_name = sd.name AND rcs.replica_id = ar.replica_id
	GROUP BY sd.database_id, sd.name, sd.is_read_only, sd.[state], sd.is_distributor, ar.secondary_role_allow_connections, sd.[compatibility_level], rcs.is_database_joined, rcs.is_failover_ready;'
	INSERT INTO #tmpdbs0 ([dbid], [dbname], [compatibility_level], is_read_only, [state], is_distributor, [role], [secondary_role_allow_connections], is_database_joined, is_failover_ready, is_query_store_on, [isdone])
	EXEC sp_executesql @sqlcmd;
END;

IF @sqlmajorver > 12
BEGIN
	SET @sqlcmd = 'SELECT sd.database_id, sd.name, sd.[compatibility_level], sd.is_read_only, sd.[state], sd.is_distributor, MIN(COALESCE(ars.[role],1)) AS [role], ar.secondary_role_allow_connections, rcs.is_database_joined, rcs.is_failover_ready, sd.is_query_store_on, 0 
	FROM master.sys.databases (NOLOCK) sd
		LEFT JOIN sys.dm_hadr_database_replica_states (NOLOCK) d ON sd.database_id = d.database_id
		LEFT JOIN sys.availability_replicas ar (NOLOCK) ON d.group_id = ar.group_id AND d.replica_id = ar.replica_id
		LEFT JOIN sys.dm_hadr_availability_replica_states (NOLOCK) ars ON d.group_id = ars.group_id AND d.replica_id = ars.replica_id
		LEFT JOIN sys.dm_hadr_database_replica_cluster_states (NOLOCK) rcs ON rcs.database_name = sd.name AND rcs.replica_id = ar.replica_id
	GROUP BY sd.database_id, sd.name, sd.is_read_only, sd.[state], sd.is_distributor, ar.secondary_role_allow_connections, sd.[compatibility_level], rcs.is_database_joined, rcs.is_failover_ready, sd.is_query_store_on;'
	INSERT INTO #tmpdbs0 ([dbid], [dbname], [compatibility_level], is_read_only, [state], is_distributor, [role], [secondary_role_allow_connections], is_database_joined, is_failover_ready, is_query_store_on, [isdone])
	EXEC sp_executesql @sqlcmd;
END;

/* Validate if database scope is set */
IF @dbScope IS NOT NULL AND ISNUMERIC(@dbScope) <> 1 AND @dbScope NOT LIKE '%,%'
BEGIN
	RAISERROR('ERROR: Invalid parameter. Valid input consists of database IDs. If more than one ID is specified, the values must be comma separated.', 16, 42) WITH NOWAIT;
	RETURN
END;
	
RAISERROR (N'  |-Applying specific database scope list, if any', 10, 1) WITH NOWAIT
IF @dbScope IS NOT NULL
BEGIN
	SELECT @sqlcmd = 'DELETE FROM #tmpdbs0 WHERE [dbid] > 4 AND [dbid] NOT IN (' + REPLACE(@dbScope,' ','') + ')'
	EXEC sp_executesql @sqlcmd;
END;

/* Populate data file info*/
WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
BEGIN
	SELECT TOP 1 @curdbname = [dbname], @curdbid = [dbid], @currole = [role], @state = [state], @cursecondary_role_allow_connections = secondary_role_allow_connections FROM #tmpdbs0 WHERE isdone = 0
	IF (@currole = 2 AND @cursecondary_role_allow_connections = 0) OR @state <> 0
	BEGIN
		SET @sqlcmd = 'SELECT [database_id], [file_id], type_desc, data_space_id, name, physical_name, state_desc, size, max_size, is_percent_growth,growth, is_media_read_only, is_read_only, is_sparse, is_name_reserved
FROM sys.master_files (NOLOCK) WHERE [database_id] = ' + CONVERT(VARCHAR(10), @curdbid)
	END
	ELSE
	BEGIN
		SET @sqlcmd = 'USE ' + QUOTENAME(@curdbname) + ';
SELECT ' + CONVERT(VARCHAR(10), @curdbid) + ' AS [database_id], [file_id], type_desc, data_space_id, name, physical_name, state_desc, size, max_size, is_percent_growth,growth, is_media_read_only, is_read_only, is_sparse, is_name_reserved
FROM sys.database_files (NOLOCK)'
	END

	BEGIN TRY
		INSERT INTO #tmpdbfiledetail
		EXECUTE sp_executesql @sqlcmd
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Database Information subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
	
	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [dbid] = @curdbid
END;

BEGIN TRY
	INSERT INTO ##tmpdbsizes([database_id], [size], [type_desc])
	SELECT [database_id], SUM([size]) AS [size], [type_desc]
	FROM #tmpdbfiledetail
	WHERE [type_desc] <> 'LOG'
	GROUP BY [database_id], [type_desc]
END TRY
BEGIN CATCH
	SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
	SELECT @ErrorMessage = 'Database Information subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
	RAISERROR (@ErrorMessage, 16, 1);
END CATCH

IF @sqlmajorver < 11
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Databases'' AS [Information],
	db.[name] AS [Database_Name], SUSER_SNAME(db.owner_sid) AS [Owner_Name], db.[database_id], 
	db.recovery_model_desc AS [Recovery_Model], db.create_date, db.log_reuse_wait_desc AS [Log_Reuse_Wait_Description], 
	(dbsize.[size]*8)/1024 AS [Data_Size_MB], ISNULL((dbfssize.[size]*8)/1024,0) AS [Filestream_Size_MB], 
	ls.cntr_value/1024 AS [Log_Size_MB], lu.cntr_value/1024 AS [Log_Used_MB],
	CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log_Used_pct], 
	db.[compatibility_level] AS [Compatibility_Level], db.collation_name AS [DB_Collation], 
	db.page_verify_option_desc AS [Page_Verify_Option], db.is_auto_create_stats_on, db.is_auto_update_stats_on,
	db.is_auto_update_stats_async_on, db.is_parameterization_forced, 
	db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on,
	db.is_read_only, db.is_auto_close_on, db.is_auto_shrink_on, ''NA'' AS [is_indirect_checkpoint_on], 
	db.is_trustworthy_on, db.is_db_chaining_on, db.is_parameterization_forced
FROM master.sys.databases AS db (NOLOCK)
INNER JOIN ##tmpdbsizes AS dbsize (NOLOCK) ON db.database_id = dbsize.database_id
INNER JOIN sys.dm_os_performance_counters AS lu (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls (NOLOCK) ON db.name = ls.instance_name
LEFT JOIN ##tmpdbsizes AS dbfssize (NOLOCK) ON db.database_id = dbfssize.database_id AND dbfssize.[type_desc] = ''FILESTREAM''
WHERE dbsize.[type_desc] = ''ROWS''
	AND dbfssize.[type_desc] = ''FILESTREAM''
	AND lu.counter_name LIKE N''Log File(s) Used Size (KB)%'' 
	AND ls.counter_name LIKE N''Log File(s) Size (KB)%''
	AND ls.cntr_value > 0 AND ls.cntr_value > 0' + CASE WHEN @dbScope IS NOT NULL THEN CHAR(10) + ' AND db.[database_id] IN (' + REPLACE(@dbScope,' ','') + ')' ELSE '' END + '
ORDER BY [Database_Name]	
OPTION (RECOMPILE)'
END
ELSE IF @sqlmajorver = 11
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Databases'' AS [Information],
	db.[name] AS [Database_Name], SUSER_SNAME(db.owner_sid) AS [Owner_Name], db.[database_id], 
	db.recovery_model_desc AS [Recovery_Model], db.create_date, db.log_reuse_wait_desc AS [Log_Reuse_Wait_Description], 
	(dbsize.[size]*8)/1024 AS [Data_Size_MB], ISNULL((dbfssize.[size]*8)/1024,0) AS [Filestream_Size_MB], 
	ls.cntr_value/1024 AS [Log_Size_MB], lu.cntr_value/1024 AS [Log_Used_MB],
	CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log_Used_pct], 
	db.[compatibility_level] AS [Compatibility_Level], db.collation_name AS [DB_Collation], 
	db.page_verify_option_desc AS [Page_Verify_Option], db.is_auto_create_stats_on, db.is_auto_update_stats_on,
	db.is_auto_update_stats_async_on, db.is_parameterization_forced, 
	db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on,
	db.is_read_only, db.is_auto_close_on, db.is_auto_shrink_on, 
	CASE WHEN db.target_recovery_time_in_seconds > 0 THEN 1 ELSE 0 END AS is_indirect_checkpoint_on,
	db.target_recovery_time_in_seconds, db.is_encrypted, db.is_trustworthy_on, db.is_db_chaining_on, db.is_parameterization_forced
FROM master.sys.databases AS db (NOLOCK)
INNER JOIN ##tmpdbsizes AS dbsize (NOLOCK) ON db.database_id = dbsize.database_id
INNER JOIN sys.dm_os_performance_counters AS lu (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls (NOLOCK) ON db.name = ls.instance_name
LEFT JOIN ##tmpdbsizes AS dbfssize (NOLOCK) ON db.database_id = dbfssize.database_id AND dbfssize.[type_desc] = ''FILESTREAM''
WHERE dbsize.[type_desc] = ''ROWS''
	AND lu.counter_name LIKE N''Log File(s) Used Size (KB)%'' 
	AND ls.counter_name LIKE N''Log File(s) Size (KB)%''
	AND ls.cntr_value > 0 AND ls.cntr_value > 0' + CASE WHEN @dbScope IS NOT NULL THEN CHAR(10) + ' AND db.[database_id] IN (' + REPLACE(@dbScope,' ','') + ')' ELSE '' END + '
ORDER BY [Database_Name]	
OPTION (RECOMPILE)'
END
ELSE IF @sqlmajorver = 12
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Databases'' AS [Information],
	db.[name] AS [Database_Name], SUSER_SNAME(db.owner_sid) AS [Owner_Name], db.[database_id], 
	db.recovery_model_desc AS [Recovery_Model], db.create_date, db.log_reuse_wait_desc AS [Log_Reuse_Wait_Description], 
	(dbsize.[size]*8)/1024 AS [Data_Size_MB], ISNULL((dbfssize.[size]*8)/1024,0) AS [Filestream_Size_MB], 
	ls.cntr_value/1024 AS [Log_Size_MB], lu.cntr_value/1024 AS [Log_Used_MB],
	CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log_Used_pct], 
	db.[compatibility_level] AS [Compatibility_Level], db.collation_name AS [DB_Collation], 
	db.page_verify_option_desc AS [Page_Verify_Option], db.is_auto_create_stats_on, db.is_auto_create_stats_incremental_on,
	db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, db.delayed_durability_desc AS [delayed_durability_status], 
	db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on,
	db.is_read_only, db.is_auto_close_on, db.is_auto_shrink_on,
	CASE WHEN db.target_recovery_time_in_seconds > 0 THEN 1 ELSE 0 END AS is_indirect_checkpoint_on,
	db.target_recovery_time_in_seconds, db.is_encrypted, db.is_trustworthy_on, db.is_db_chaining_on, db.is_parameterization_forced
FROM master.sys.databases AS db (NOLOCK)
INNER JOIN ##tmpdbsizes AS dbsize (NOLOCK) ON db.database_id = dbsize.database_id
INNER JOIN sys.dm_os_performance_counters AS lu (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls (NOLOCK) ON db.name = ls.instance_name
LEFT JOIN ##tmpdbsizes AS dbfssize (NOLOCK) ON db.database_id = dbfssize.database_id AND dbfssize.[type_desc] = ''FILESTREAM''
WHERE dbsize.[type_desc] = ''ROWS''
	AND lu.counter_name LIKE N''Log File(s) Used Size (KB)%'' 
	AND ls.counter_name LIKE N''Log File(s) Size (KB)%''
	AND ls.cntr_value > 0 AND ls.cntr_value > 0' + CASE WHEN @dbScope IS NOT NULL THEN CHAR(10) + ' AND db.[database_id] IN (' + REPLACE(@dbScope,' ','') + ')' ELSE '' END + '
ORDER BY [Database_Name]	
OPTION (RECOMPILE)'
END
ELSE IF @sqlmajorver >= 13
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Databases'' AS [Information],
	db.[name] AS [Database_Name], SUSER_SNAME(db.owner_sid) AS [Owner_Name], db.[database_id], 
	db.recovery_model_desc AS [Recovery_Model], db.create_date, db.log_reuse_wait_desc AS [Log_Reuse_Wait_Description], 
	(dbsize.[size]*8)/1024 AS [Data_Size_MB], ISNULL((dbfssize.[size]*8)/1024,0) AS [Filestream_Size_MB], 
	ls.cntr_value/1024 AS [Log_Size_MB], lu.cntr_value/1024 AS [Log_Used_MB],
	CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log_Used_pct], 
	db.[compatibility_level] AS [Compatibility_Level], db.collation_name AS [DB_Collation], 
	db.page_verify_option_desc AS [Page_Verify_Option], db.is_auto_create_stats_on, db.is_auto_create_stats_incremental_on,
	db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, db.delayed_durability_desc AS [delayed_durability_status], 
	db.is_query_store_on, db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on,
	db.is_read_only, db.is_auto_close_on, db.is_auto_shrink_on, 
	CASE WHEN db.target_recovery_time_in_seconds > 0 THEN 1 ELSE 0 END AS is_indirect_checkpoint_on,
	db.target_recovery_time_in_seconds, db.is_encrypted, db.is_trustworthy_on, db.is_db_chaining_on, db.is_parameterization_forced, 
	db.is_memory_optimized_elevate_to_snapshot_on, db.is_remote_data_archive_enabled, db.is_mixed_page_allocation_on
FROM master.sys.databases AS db (NOLOCK)
INNER JOIN sys.dm_os_performance_counters AS lu (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls (NOLOCK) ON db.name = ls.instance_name
INNER JOIN ##tmpdbsizes AS dbsize (NOLOCK) ON db.database_id = dbsize.database_id
LEFT JOIN ##tmpdbsizes AS dbfssize (NOLOCK) ON db.database_id = dbfssize.database_id AND dbfssize.[type_desc] = ''FILESTREAM''
WHERE dbsize.[type_desc] = ''ROWS''
	AND lu.counter_name LIKE N''Log File(s) Used Size (KB)%'' 
	AND ls.counter_name LIKE N''Log File(s) Size (KB)%''
	AND ls.cntr_value > 0 AND ls.cntr_value > 0' + CASE WHEN @dbScope IS NOT NULL THEN CHAR(10) + ' AND db.[database_id] IN (' + REPLACE(@dbScope,' ','') + ')' ELSE '' END + '
ORDER BY [Database_Name]	
OPTION (RECOMPILE)'
END
ELSE IF @sqlmajorver >= 14
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Databases'' AS [Information],
	db.[name] AS [Database_Name], SUSER_SNAME(db.owner_sid) AS [Owner_Name], db.[database_id], 
	db.recovery_model_desc AS [Recovery_Model], db.create_date, db.log_reuse_wait_desc AS [Log_Reuse_Wait_Description], 
	(dbsize.[size]*8)/1024 AS [Data_Size_MB], ISNULL((dbfssize.[size]*8)/1024,0) AS [Filestream_Size_MB], 
	ls.cntr_value/1024 AS [Log_Size_MB], lu.cntr_value/1024 AS [Log_Used_MB],
	CAST(CAST(lu.cntr_value AS FLOAT) / CAST(ls.cntr_value AS FLOAT)AS DECIMAL(18,2)) * 100 AS [Log_Used_pct],
	CASE WHEN ssu.reserved_space_kb>0 THEN ssu.reserved_space_kb/1024 ELSE 0 END AS [Version_Store_Size_MB],
	db.[compatibility_level] AS [Compatibility_Level], db.collation_name AS [DB_Collation], 
	db.page_verify_option_desc AS [Page_Verify_Option], db.is_auto_create_stats_on, db.is_auto_create_stats_incremental_on,
	db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, db.delayed_durability_desc AS [delayed_durability_status], 
	db.is_query_store_on, db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on,
	db.is_read_only, db.is_auto_close_on, db.is_auto_shrink_on, 
	CASE WHEN db.target_recovery_time_in_seconds > 0 THEN 1 ELSE 0 END AS is_indirect_checkpoint_on,
	db.target_recovery_time_in_seconds, db.is_encrypted, db.is_trustworthy_on, db.is_db_chaining_on, db.is_parameterization_forced, 
	db.is_memory_optimized_elevate_to_snapshot_on, db.is_remote_data_archive_enabled, db.is_mixed_page_allocation_on
FROM master.sys.databases AS db (NOLOCK)
INNER JOIN ##tmpdbsizes AS dbsize (NOLOCK) ON db.database_id = dbsize.database_id
INNER JOIN sys.dm_os_performance_counters AS lu (NOLOCK) ON db.name = lu.instance_name
INNER JOIN sys.dm_os_performance_counters AS ls (NOLOCK) ON db.name = ls.instance_name
LEFT JOIN ##tmpdbsizes AS dbfssize (NOLOCK) ON db.database_id = dbfssize.database_id AND dbfssize.[type_desc] = ''FILESTREAM''
LEFT JOIN sys.dm_tran_version_store_space_usage AS ssu (NOLOCK) ON db.database_id = ssu.database_id
WHERE dbsize.[type_desc] = ''ROWS''
	AND lu.counter_name LIKE N''Log File(s) Used Size (KB)%'' 
	AND ls.counter_name LIKE N''Log File(s) Size (KB)%''
	AND ls.cntr_value > 0 AND ls.cntr_value > 0' + CASE WHEN @dbScope IS NOT NULL THEN CHAR(10) + ' AND db.[database_id] IN (' + REPLACE(@dbScope,' ','') + ')' ELSE '' END + '
ORDER BY [Database_Name]	
OPTION (RECOMPILE)'
END

EXECUTE sp_executesql @sqlcmd;
	
SELECT 'Information' AS [Category], 'Database_Files' AS [Information], DB_NAME(database_id) AS [Database_Name], [file_id], type_desc, data_space_id AS [Filegroup], name, physical_name,
	state_desc, (size * 8) / 1024 AS size_MB, CASE max_size WHEN -1 THEN 'Unlimited' ELSE CONVERT(VARCHAR(10), max_size) END AS max_size,
	CASE WHEN is_percent_growth = 0 THEN CONVERT(VARCHAR(10),((growth * 8) / 1024)) ELSE growth END AS [growth], CASE WHEN is_percent_growth = 1 THEN 'Pct' ELSE 'MB' END AS growth_type,
	is_media_read_only, is_read_only, is_sparse, is_name_reserved
FROM #tmpdbfiledetail
ORDER BY database_id, [file_id];

IF @sqlmajorver >= 12
BEGIN
	/*DECLARE @dbid int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000)*/

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblInMemDBs'))
	DROP TABLE #tblInMemDBs;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblInMemDBs'))
	CREATE TABLE #tblInMemDBs ([DBName] sysname, [Has_MemoryOptimizedObjects] bit, [MemoryAllocated_MemoryOptimizedObjects_KB] DECIMAL(18,2), [MemoryUsed_MemoryOptimizedObjects_KB] DECIMAL(18,2));
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN
		RAISERROR (N'  |-Starting Storage analysis for In-Memory OLTP Engine', 10, 1) WITH NOWAIT
	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], ISNULL((SELECT 1 FROM sys.filegroups FG WHERE FG.[type] = ''FX''), 0) AS [Has_MemoryOptimizedObjects],
ISNULL((SELECT CONVERT(DECIMAL(18,2), (SUM(tms.memory_allocated_for_table_kb) + SUM(tms.memory_allocated_for_indexes_kb))) FROM sys.dm_db_xtp_table_memory_stats tms), 0.00) AS [MemoryAllocated_MemoryOptimizedObjects_KB],
ISNULL((SELECT CONVERT(DECIMAL(18,2),(SUM(tms.memory_used_by_table_kb) + SUM(tms.memory_used_by_indexes_kb))) FROM sys.dm_db_xtp_table_memory_stats tms), 0.00) AS [MemoryUsed_MemoryOptimizedObjects_KB];'

			BEGIN TRY
				INSERT INTO #tblInMemDBs
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Storage analysis for In-Memory OLTP Engine subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;

	IF (SELECT COUNT([DBName]) FROM #tblInMemDBs WHERE [Has_MemoryOptimizedObjects] = 1) > 0
	BEGIN
		SELECT 'Information' AS [Category], 'InMem_Database_Storage' AS [Information], DBName AS [Database_Name],
			[MemoryAllocated_MemoryOptimizedObjects_KB], [MemoryUsed_MemoryOptimizedObjects_KB]
		FROM #tblInMemDBs WHERE Has_MemoryOptimizedObjects = 1
		ORDER BY DBName;
	END
	ELSE
	BEGIN
		SELECT 'Information' AS [Category], 'InMem_Database_Storage' AS [Information], '[NA]' AS [Comment]
	END
END;

-- http://support.microsoft.com/kb/2857849
IF @sqlmajorver > 10 AND @IsHadrEnabled = 1
BEGIN
	SELECT 'Information' AS [Category], 'AlwaysOn_AG_Databases' AS [Information], dc.database_name AS [Database_Name],
		d.synchronization_health_desc, d.synchronization_state_desc, d.database_state_desc
	FROM sys.dm_hadr_database_replica_states d
	INNER JOIN sys.availability_databases_cluster dc ON d.group_database_id=dc.group_database_id
	WHERE d.is_local=1
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Database file autogrows last 72h subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting database file autogrows last 72h', 10, 1) WITH NOWAIT
IF EXISTS (SELECT TOP 1 id FROM sys.traces WHERE is_default = 1)
BEGIN
	DECLARE @tracefilename VARCHAR(500)
	IF @ostype = 'Windows'
	SELECT @tracefilename = LEFT([path],LEN([path]) - PATINDEX('%\%', REVERSE([path]))) + '\log.trc' FROM sys.traces WHERE is_default = 1;
	
	IF @ostype <> 'Windows'
	SELECT @tracefilename = LEFT([path],LEN([path]) - PATINDEX('%/%', REVERSE([path]))) + '/log.trc' FROM sys.traces WHERE is_default = 1;

	WITH AutoGrow_CTE (databaseid, [filename], Growth, Duration, StartTime, EndTime)
	AS
	(
	SELECT databaseid, [filename], SUM(IntegerData*8) AS Growth, Duration, StartTime, EndTime--, CASE WHEN EventClass =
	FROM sys.fn_trace_gettable(@tracefilename, default)
	WHERE EventClass >= 92 AND EventClass <= 95 AND DATEDIFF(hh,StartTime,GETDATE()) < 72 -- Last 24h
	GROUP BY databaseid, [filename], IntegerData, Duration, StartTime, EndTime
	)
	SELECT 'Information' AS [Category], 'Recorded_Autogrows_Lst72H' AS [Information], DB_NAME(database_id) AS Database_Name, 
		mf.name AS logical_file_name, mf.size*8 / 1024 AS size_MB, mf.type_desc,
		ag.Growth AS [growth_KB], CASE WHEN is_percent_growth = 1 THEN 'Pct' ELSE 'MB' END AS growth_type,
		Duration/1000 AS Growth_Duration_ms, ag.StartTime, ag.EndTime
	FROM sys.master_files mf
	LEFT OUTER JOIN AutoGrow_CTE ag ON mf.database_id=ag.databaseid AND mf.name=ag.[filename]
	WHERE ag.Growth > 0 --Only where growth occurred
	GROUP BY database_id, mf.name, mf.size, ag.Growth, ag.Duration, ag.StartTime, ag.EndTime, is_percent_growth, mf.growth, mf.type_desc
	ORDER BY Database_Name, logical_file_name, ag.StartTime;
END
ELSE
BEGIN
	SELECT 'Information' AS [Category], 'Recorded_Autogrows_Lst72H' AS [Information], '[WARNING: Could not gather information on autogrow times]' AS [Comment]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Database triggers subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting database triggers', 10, 1) WITH NOWAIT
	/*DECLARE @dbid int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000)*/

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTriggers'))
	DROP TABLE #tblTriggers;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTriggers'))
	CREATE TABLE #tblTriggers ([DBName] sysname, [triggerName] sysname, [schemaName] sysname, [tableName] sysname, [type_desc] NVARCHAR(60), [parent_class_desc] NVARCHAR(60), [create_date] DATETIME, [modify_date] DATETIME, [is_disabled] bit, [is_instead_of_trigger] bit, [is_not_for_replication] bit);
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT N''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], st.name, ss.name, stb.name, st.type_desc, st.parent_class_desc, st.create_date, st.modify_date, st.is_disabled, st.is_instead_of_trigger, st.is_not_for_replication
FROM sys.triggers AS st
INNER JOIN sys.tables stb ON st.parent_id = stb.[object_id]
INNER JOIN sys.schemas ss ON stb.[schema_id] = ss.[schema_id]
WHERE st.is_ms_shipped = 0
ORDER BY stb.name, st.name;'

			BEGIN TRY
				INSERT INTO #tblTriggers
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Database triggers subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;
	
	IF (SELECT COUNT([triggerName]) FROM #tblTriggers) > 0
	BEGIN
		SELECT 'Information' AS [Category], 'Database_Triggers' AS [Information], DBName AS [Database_Name],
			triggerName AS [Trigger_Name], schemaName AS [Schema_Name], tableName AS [Table_Name], 
			type_desc AS [Trigger_Type], parent_class_desc AS [Trigger_Parent], 
			CASE is_instead_of_trigger WHEN 1 THEN 'INSTEAD_OF' ELSE 'AFTER' END AS [Trigger_Behavior],
			create_date, modify_date, 
			CASE WHEN is_disabled = 1 THEN 'YES' ELSE 'NO' END AS [is_disabled], 
			CASE WHEN is_not_for_replication = 1 THEN 'YES' ELSE 'NO' END AS [is_not_for_replication]
		FROM #tblTriggers
		ORDER BY DBName, tableName, triggerName;
	END
	ELSE
	BEGIN
		SELECT 'Information' AS [Category], 'Database_Triggers' AS [Information], '[NA]' AS [Comment]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Feature usage subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 9
BEGIN
	RAISERROR (N'|-Starting Feature usage', 10, 1) WITH NOWAIT
	/*DECLARE @dbid int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000)*/

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerSku'))
	DROP TABLE #tblPerSku;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerSku'))
	CREATE TABLE #tblPerSku ([DBName] sysname NULL, [Feature_Name] VARCHAR(100));
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], feature_name FROM sys.dm_db_persisted_sku_features (NOLOCK)
UNION ALL
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Change_Tracking'' AS feature_name FROM sys.change_tracking_databases (NOLOCK) WHERE database_id = DB_ID()
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Fine_grained_auditing'' AS feature_name FROM sys.database_audit_specifications (NOLOCK)'

			IF @sqlmajorver >= 13
			SET @sqlcmd = @sqlcmd + CHAR(10) + 'UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Polybase'' AS feature_name FROM sys.external_data_sources (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Row_Level_Security'' AS feature_name FROM sys.security_policies (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Always_Encrypted'' AS feature_name FROM sys.column_master_keys (NOLOCK)
UNION ALL
SELECT TOP 1 ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [dbname], ''Dynamic_Data_Masking'' AS feature_name FROM sys.masked_columns (NOLOCK) WHERE is_masked = 1'

			BEGIN TRY
				INSERT INTO #tblPerSku
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Feature usage subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;
	
	IF @sqlmajorver > 10 AND ((@sqlmajorver = 13 AND @sqlbuild < 4000) OR @sqlmajorver < 13) AND @IsHadrEnabled = 1
	BEGIN
		INSERT INTO #tblPerSku
		SELECT [dbname], 'Always_On' AS feature_name FROM #tmpdbs0 WHERE is_database_joined = 1;
	END;
	
	IF (SELECT COUNT(DISTINCT [name]) FROM master.sys.databases (NOLOCK) WHERE database_id NOT IN (2,3) AND source_database_id IS NOT NULL) > 0 -- Snapshot
	BEGIN
		INSERT INTO #tblPerSku
		SELECT DISTINCT [name], 'DB_Snapshot' AS feature_name FROM master.sys.databases (NOLOCK) WHERE database_id NOT IN (2,3) AND source_database_id IS NOT NULL;
	END;

	IF (SELECT COUNT(DISTINCT [name]) FROM master.sys.master_files (NOLOCK) WHERE database_id NOT IN (2,3) AND [type] = 2 and file_guid IS NOT NULL) > 0 -- Filestream
	BEGIN
		INSERT INTO #tblPerSku
		SELECT DISTINCT DB_NAME(database_id), 'Filestream' AS feature_name FROM sys.master_files (NOLOCK) WHERE database_id NOT IN (2,3) AND [type] = 2 and file_guid IS NOT NULL;	
	END;
	
	IF (SELECT COUNT([Feature_Name]) FROM #tblPerSku) > 0
	BEGIN
		SELECT 'Information' AS [Category], 'Feature_usage' AS [Check], '[INFORMATION: Some databases are using features that are not common to all editions]' AS [Comment]
		SELECT 'Information' AS [Category], 'Feature_usage' AS [Information], DBName AS [Database_Name], [Feature_Name]
		FROM #tblPerSku
		ORDER BY 2, 3
	END
	ELSE
	BEGIN
		SELECT 'Information' AS [Category], 'Feature_usage' AS [Check], '[NA]' AS [Comment]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Backups since last Full Information subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Backups', 10, 1) WITH NOWAIT
IF @sqlmajorver > 10
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Backups_since_last_Full'' AS [Information], 
[database_name] AS [Database_Name], CASE WHEN type = ''D'' THEN ''Database''
	WHEN type = ''I'' THEN ''Diff_Database''
	WHEN type = ''L'' THEN ''Log''
	WHEN type = ''F'' THEN ''File''
	WHEN type = ''G'' THEN ''Diff_file''
	WHEN type = ''P'' THEN ''Partial''
	WHEN type = ''Q'' THEN ''Diff_partial''
	ELSE NULL END AS [bck_type],
[backup_start_date], [backup_finish_date],
CONVERT(decimal(20,2),backup_size/1024.00/1024.00) AS [backup_size_MB],
CONVERT(decimal(20,2),compressed_backup_size/1024.00/1024.00) AS [compressed_backup_size_MB],
[recovery_model], [user_name],
database_backup_lsn AS [full_base_lsn], [differential_base_lsn], [expiration_date], 
[is_password_protected], [has_backup_checksums], [is_readonly], is_copy_only, [has_incomplete_metadata] AS [Tail_log]
FROM msdb.dbo.backupset bck1 (NOLOCK)
WHERE is_copy_only = 0 -- No COPY_ONLY backups
AND backup_start_date >= (SELECT MAX(backup_start_date) FROM msdb.dbo.backupset bck2 (NOLOCK) WHERE bck2.type IN (''D'',''F'',''P'') AND is_copy_only = 0 AND bck1.database_name = bck2.database_name)
ORDER BY database_name, backup_start_date DESC'
END
ELSE 
BEGIN
	SET @sqlcmd = N'SELECT ''Information'' AS [Category], ''Backups_since_last_Full'' AS [Information], 
[database_name] AS [Database_Name], CASE WHEN type = ''D'' THEN ''Database''
	WHEN type = ''I'' THEN ''Diff_Database''
	WHEN type = ''L'' THEN ''Log''
	WHEN type = ''F'' THEN ''File''
	WHEN type = ''G'' THEN ''Diff_file''
	WHEN type = ''P'' THEN ''Partial''
	WHEN type = ''Q'' THEN ''Diff_partial''
	ELSE NULL END AS [bck_type],
[backup_start_date], [backup_finish_date], 
CONVERT(decimal(20,2),backup_size/1024.00/1024.00) AS [backup_size_MB],
''[NA]'' AS [compressed_backup_size_MB], 
[recovery_model], [user_name],
database_backup_lsn AS [full_base_lsn], [differential_base_lsn], [expiration_date], 
[is_password_protected], [has_backup_checksums], [is_readonly], is_copy_only, [has_incomplete_metadata] AS [Tail_log]
FROM msdb.dbo.backupset bck1 (NOLOCK)
WHERE is_copy_only = 0 -- No COPY_ONLY backups
AND backup_start_date >= (SELECT MAX(backup_start_date) FROM msdb.dbo.backupset bck2 (NOLOCK) WHERE bck2.type IN (''D'',''F'',''P'') AND is_copy_only = 0 AND bck1.database_name = bck2.database_name)
ORDER BY database_name, backup_start_date DESC'
END;

EXECUTE sp_executesql @sqlcmd;

--------------------------------------------------------------------------------------------------------------------------------
-- System Configuration subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting System Configuration', 10, 1) WITH NOWAIT
SELECT 'Information' AS [Category], 'All_System_Configurations' AS [Information],
	name AS [Name],
	configuration_id AS [Number],
	minimum AS [Minimum],
	maximum AS [Maximum],
	is_dynamic AS [Dynamic],
	is_advanced AS [Advanced],
	value AS [ConfigValue],
	value_in_use AS [RunValue],
	description AS [Description]
FROM sys.configurations (NOLOCK)
ORDER BY name OPTION (RECOMPILE);

--------------------------------------------------------------------------------------------------------------------------------
-- Pre-checks section
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'Starting Pre-Checks - Building DB list excluding MS shipped', 10, 1) WITH NOWAIT
DECLARE @MSdb int

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs1'))
DROP TABLE #tmpdbs1;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs1'))
CREATE TABLE #tmpdbs1 (id int IDENTITY(1,1), [dbid] int, [dbname] NVARCHAR(1000), [role] tinyint, [secondary_role_allow_connections] tinyint, isdone bit)

RAISERROR (N'|-Excluding MS shipped by standard names and databases belonging to non-readable AG secondary replicas (if available)', 10, 1) WITH NOWAIT
-- Ignore MS shipped databases and databases belonging to non-readable AG secondary replicas
INSERT INTO #tmpdbs1 ([dbid], [dbname], [role], [secondary_role_allow_connections], [isdone])
SELECT [dbid], [dbname], [role], [secondary_role_allow_connections], 0 
FROM #tmpdbs0 (NOLOCK) 
WHERE is_read_only = 0 AND [state] = 0 AND [dbid] > 4 AND is_distributor = 0
	AND [role] <> 2 AND (secondary_role_allow_connections <> 0 OR secondary_role_allow_connections IS NULL)
	AND lower([dbname]) NOT IN ('virtualmanagerdb', --Virtual Machine Manager
		'scspfdb', --Service Provider Foundation
		'semanticsdb', --Semantic Search
		'servicemanager','service manager','dwstagingandconfig','dwrepository','dwdatamart','dwasdatabase','omdwdatamart','cmdwdatamart', --SCSM
		'ssodb','bamanalysis','bamarchive','bamalertsapplication','bamalertsnsmain','bamprimaryimport','bamstarschema','biztalkmgmtdb','biztalkmsgboxdb','biztalkdtadb','biztalkruleenginedb','bamprimaryimport','biztalkedidb','biztalkhwsdb','tpm','biztalkanalysisdb','bamprimaryimportsuccessfully', --BizTalk
		'aspstate','aspnet', --ASP.NET
		'mscrm_config', --Dynamics CRM
		'cpsdyn','lcslog','lcscdr','lis','lyss','mgc','qoemetrics','rgsconfig','rgsdyn','rtc','rtcab','rtcab1','rtcdyn','rtcshared','rtcxds','xds', --Lync
		'activitylog','branchdb','clienttracelog','eventlog','listingssettings','servicegroupdb','tservercontroller','vodbackend', --MediaRoom
		'operationsmanager','operationsmanagerdw','operationsmanagerac', --SCOM
		'orchestrator', --Orchestrator
		'sso','wss_search','wss_search_config','sharedservices_db','sharedservices_search_db','wss_content','profiledb', 'social db','sync db',	--Sharepoint
		'susdb', --WSUS
		'projectserver_archive','projectserver_draft','projectserver_published','projectserver_reporting', --Project Server
		'reportserver','reportservertempdb','rsdb','rstempdb', --SSRS
		'fastsearchadmindatabase', --Fast Search
		'ppsmonitoring','ppsplanningservice','ppsplanningsystem', --PerformancePoint Services
		'dynamics', --Dynamics GP
		'microsoftdynamicsax','microsoftdynamicsaxbaseline', --Dynamics AX
		'fimservice','fimsynchronizationservice', --Forefront Identity Manager
		'sbgatewaydatabase','sbmanagementdb', --Service Bus
		'wfinstancemanagementdb','wfmanagementdb','wfresourcemanagementdb' --Workflow Manager
	)
	AND [dbname] NOT LIKE 'reportingservice[_]%' --SSRS
	AND [dbname] NOT LIKE 'tfs[_]%' --TFS
	AND [dbname] NOT LIKE 'defaultpowerpivotserviceapplicationdb%' --PowerPivot
	AND [dbname] NOT LIKE 'performancepoint service[_]%' --PerformancePoint Services
	AND [dbname] NOT LIKE '%database nav%' --Dynamics NAV
	AND [dbname] NOT LIKE '%[_]mscrm' --Dynamics CRM
	AND [dbname] NOT LIKE 'dpmdb[_]%' --DPM
	AND [dbname] NOT LIKE 'sbmessagecontainer%' --Service Bus
	AND [dbname] NOT LIKE 'sma%' --SCSMA
	AND [dbname] NOT LIKE 'releasemanagement%' --TFS Release Management
	AND [dbname] NOT LIKE 'projectwebapp%' --Project Server
	AND [dbname] NOT LIKE 'sms[_]%' AND [dbname] NOT LIKE 'cm[_]%' --SCCM
	AND [dbname] NOT LIKE 'fepdw%' AND [dbname] NOT LIKE 'FEPDB[_]%' --Forefront Endpoint Protection
	--Sharepoint
	AND [dbname] NOT LIKE 'sharepoint[_]admincontent%' AND [dbname] NOT LIKE 'sharepoint[_]config%' AND [dbname] NOT LIKE 'wss[_]content%' AND [dbname] NOT LIKE 'wss[_]search%'
	AND [dbname] NOT LIKE 'sharedservices[_]db%' AND [dbname] NOT LIKE 'sharedservices[_]search[_]db%' AND [dbname] NOT LIKE 'sharedservices[_][_]db%' AND [dbname] NOT LIKE 'sharedservices[_][_]search[_]db%'
	AND [dbname] NOT LIKE 'sharedservicescontent%' AND [dbname] NOT LIKE 'application[_]registry[_]service[_]db%' AND [dbname] NOT LIKE 'search[_]service[_]application[_]propertystoredb[_]%'
	AND [dbname] NOT LIKE 'subscriptionsettings[_]%' AND [dbname] NOT LIKE 'webanalyticsserviceapplication[_]stagingdb[_]%' AND [dbname] NOT LIKE 'webanalyticsserviceapplication[_]reportingdb[_]%'
	AND [dbname] NOT LIKE 'bdc[_]service[_]db[_]%' AND [dbname] NOT LIKE 'managed metadata service[_]%' AND [dbname] NOT LIKE 'performancepoint service application[_]%' 
	AND [dbname] NOT LIKE 'search[_]service[_]application[_]crawlstoredb[_]%' AND [dbname] NOT LIKE 'search[_]service[_]application[_]db[_]%' AND [dbname] NOT LIKE 'secure[_]store[_]service[_]db[_]%' AND [dbname] NOT LIKE 'stateservice%' 
	AND [dbname] NOT LIKE 'user profile service application[_]profiledb[_]%' AND [dbname] NOT LIKE 'user profile service application[_]syncdb[_]%' AND [dbname] NOT LIKE 'user profile service application[_]socialdb[_]%' 
	AND [dbname] NOT LIKE 'wordautomationservices[_]%' AND [dbname] NOT LIKE 'wss[_]logging%' AND [dbname] NOT LIKE 'wss[_]usageapplication%' AND [dbname] NOT LIKE 'appmng[_]service[_]db%' 
	AND [dbname] NOT LIKE 'search[_]service[_]application[_]analyticsreportingstoredb[_]%' AND [dbname] NOT LIKE 'search[_]service[_]application[_]linksstoredb[_]%' AND [dbname] NOT LIKE 'sharepoint[_]logging[_]%' 
	AND [dbname] NOT LIKE 'settingsservicedb%' AND [dbname] NOT LIKE 'sharepoint[_]logging[_]%' AND [dbname] NOT LIKE 'translationservice[_]%' AND [dbname] NOT LIKE 'sharepoint translation services[_]%' AND [dbname] NOT LIKE 'sessionstateservice%' 

IF EXISTS (SELECT name FROM msdb.sys.objects (NOLOCK) WHERE name='MSdistributiondbs' AND is_ms_shipped = 1) 
BEGIN 
	DELETE FROM #tmpdbs1 WHERE [dbid] IN (SELECT DB_ID(name) FROM msdb.dbo.MSdistributiondbs)
END;

RAISERROR (N'|-Excluding MS shipped by notable object names', 10, 1) WITH NOWAIT
-- Removing other noticeable MS shipped DBs
WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
BEGIN
	SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
	SET @sqlcmd = N'USE ' + QUOTENAME(@dbname) + N';
IF (OBJECT_ID(''dbo.AR_Class'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.AR_Entity'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.AR_System'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_ar_CreateEntity'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_ar_CreateMethod'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.Versions'',''U'') IS NOT NULL 
	AND (OBJECT_ID(''dbo.ECMApplicationLog'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.ECMTerm'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_ECM_GetPackage'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_ECM_GetGroups'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.Configuration'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MonthlyPartitions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Search_GetCrawlPipeline'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.prc_EnumSandboxedRequests'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.MSSConfiguration'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MSSOrdinal'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_MSS_GetConfigurationProperty'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.Tenants'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_Admin_ListPartitionedTables'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_DefragmentIndices'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.WAScope'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.WASetting'',''U'') IS NOT NULL AND SCHEMA_ID(''Processing'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.Groups'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Items'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_GetGroups'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_GetVersion'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.Mapping'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.PropertySet'',''U'') IS NOT NULL AND SCHEMA_ID(''SubscriptionSettingsService_Application_Pool'') IS NOT NULL) 
	OR (OBJECT_ID(''dbo.Sessions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_AddItem'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_GetItemWithLock'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.SiteMap'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SiteCounts'',''U'') IS NOT NULL AND SCHEMA_ID(''WSS_Content_Application_Pools'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.PPSAnnotations'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.PPSParameterValues'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_PPS_GetAnnotation'',''P'') IS NOT NULL)	 
	OR (OBJECT_ID(''dbo.AM_Licenses'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.AM_DeploymentIds'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_AM_GetApps'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_AM_SetDeploymentId'',''P'') IS NOT NULL)	
	OR (OBJECT_ID(''dbo.MSSDefinitions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MSSSecurityDescriptors'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_MSS_GetCrawls'',''P'') IS NOT NULL)
)
OR (OBJECT_ID(''dbo.SSSApplication'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSSAudit'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSSConfig'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_sss_GetConfig'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.Actions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.VersionInfo'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.mms_extensions'',''U'') IS NOT NULL AND SCHEMA_ID(''persistenceUsers'') IS NOT NULL AND SCHEMA_ID(''state_persistence_users'') IS NOT NULL)
OR (OBJECT_ID(''dbo.AllDocs'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.AllLists'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.NameValuePair'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.proc_GetWorkItems'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.proc_EnumLists'',''P'') IS NOT NULL)	
OR (OBJECT_ID(''dbo.SSO_Application'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSO_Ticket'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSO_Config'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.sso_InsertAudit'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.sso_RetrieveSSOConfig'',''P'') IS NOT NULL)
-- End Sharepoint
OR ((OBJECT_ID(''dbo.ASPStateTempSessions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.ASPStateTempApplications'',''U'') IS NOT NULL) OR OBJECT_ID(''dbo.CreateTempTables'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.DeleteExpiredSessions'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.aspnet_Applications'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.aspnet_Profile'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.aspnet_Users'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.aspnet_CheckSchemaVersion'',''P'') IS NOT NULL)
-- End ASP.NET
OR (OBJECT_ID(''DataRefresh.Runs'',''U'') IS NOT NULL AND OBJECT_ID(''GeminiService.Version'',''U'') IS NOT NULL AND OBJECT_ID(''Usage.Requests'',''U'') IS NOT NULL AND SCHEMA_ID(''HealthRule'') IS NOT NULL)
-- End PowerPivot
OR (OBJECT_ID(''dbo.LICENSES'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.VERSION'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.TASK_RUNPROGRAM'',''U'') IS NOT NULL AND SCHEMA_ID(''Microsoft.SystemCenter.Orchestrator'') IS NOT NULL)
-- End Orchestrator
OR (OBJECT_ID(''dbo.tbl_Cloud_Cloud'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.tbl_PXE_PxeServer'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.tbl_VMM_Server'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.prc_VMM_AddVmmServer'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.prc_Cloud_Cloud_GetParent'',''P'') IS NOT NULL)
-- End VMM
OR (OBJECT_ID(''scspf.EventHandlers'',''U'') IS NOT NULL AND OBJECT_ID(''scspf.Servers'',''U'') IS NOT NULL AND OBJECT_ID(''scspf.Tenants'',''U'') IS NOT NULL)
-- End Service Provider Foundation
OR ((OBJECT_ID(''dbo.SSOX_AuditTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSOX_GlobalInfo'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SSOX_Servers'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.sp_BackupBizTalkFull'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.ssox_spGetDBVersion'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.BizTalkDBVersion'',''U'') IS NOT NULL AND SCHEMA_ID(''BTS_ADMIN_USERS'') IS NOT NULL AND SCHEMA_ID(''BTS_OPERATORS'') IS NOT NULL))
-- End BizTalk
OR (OBJECT_ID(''dbo.Layer'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.ModelGroup'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SchemaVersion'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.XI_GetUserName'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.XU_AssignAxId'',''P'') IS NOT NULL)
-- End Dynamics AX
OR (OBJECT_ID(''dbo.Notification'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SystemUserRoles'',''U'') IS NOT NULL 
	AND (OBJECT_ID(''dbo.p_GetCrmUserId'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.p_GetPrivilegesInRole'',''P'') IS NOT NULL)
	OR (OBJECT_ID(''dbo.p_AccountOVRollup'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.p_GetDbSize'',''P'') IS NOT NULL))
-- End Dynamics CRM
OR (OBJECT_ID(''dbo.User Personalization'',''U'') IS NOT NULL AND EXISTS(SELECT 1 FROM sys.all_objects (NOLOCK) WHERE type=''U'' AND (name like ''%$G[_]L Entry'' OR name LIKE ''%$Item Ledger Entry'')))
-- End Dynamics NAV
OR (OBJECT_ID(''dbo.DBVERSION'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.PATH'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SY_SQL_Options'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.zDP_ActivitySD'',''P'') IS NOT NULL)
-- End Dynamics GP
OR (OBJECT_ID(''dbo.Agents'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.DistributionPoints'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SysResList'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.PXE_GetPXECert'',''P'') IS NOT NULL)
-- End SCCM
OR (OBJECT_ID(''dbo.dtFEP_Infra_InstalledJobs'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.dtFEP_Common_User'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.dtAN_Infra_JobLastRun'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.spFEP_Infra_CreateJob'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.spAN_Infra_ScheduleJob'',''P'') IS NOT NULL)
-- End Forefront Endpoint Protection
OR (OBJECT_ID(''admin.categories'',''U'') IS NOT NULL AND OBJECT_ID(''admin.keyword'',''U'') IS NOT NULL AND OBJECT_ID(''admin.storeentry'',''U'') IS NOT NULL)
-- End Fast Search
OR (OBJECT_ID(''fim.Objects'',''U'') IS NOT NULL AND SCHEMA_ID(''debug'') IS NOT NULL)
OR (OBJECT_ID(''dbo.mms_extensions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.mms_partition'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.mms_addmvlink'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.mms_getcsguidfromanchor'',''P'') IS NOT NULL)
-- End Forefront Identity Manager
OR (OBJECT_ID(''dbo.Annotations'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.BsmUsers'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.FCObjects'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.BsmUserCreate'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.BsmUserDelete'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.DBSchemaVersion'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.QueueStatus'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.ServerStates'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.bsp_UpdateQueueSizeLimit'',''P'') IS NOT NULL)
-- End PerformancePoint Services
OR (OBJECT_ID(''dbo.Versions'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MSP_DAL_GetDatabaseCacheExceptions'',''P'') IS NOT NULL AND (OBJECT_ID(''dbo.MSP_DAL_GetSprocInfo'',''P'') IS NOT NULL OR OBJECT_ID(''dbo.MSP_DAL_GetSprocList'',''P'') IS NOT NULL))
-- End Project Server
OR (OBJECT_ID(''apm.MESSAGES'',''U'') IS NOT NULL AND SCHEMA_ID(''CS'') IS NOT NULL OR SCHEMA_ID(''CM'') IS NOT NULL)
OR (OBJECT_ID(''dbo.Event_00'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MT_Database'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.PerformanceData_00'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.p_MPSelectViews'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.AemApplication'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.EventLoggingComputer'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.HealthState'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.p_MOMManagementGroupInfoSelect'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.dtMachine'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.dtPartition'',''U'') IS NOT NULL AND SCHEMA_ID(''AdtServer'') IS NOT NULL)
-- End SCOM
OR (OBJECT_ID(''dbo.version'',''U'') IS NOT NULL AND EXISTS(SELECT 1 FROM sys.internal_tables (NOLOCK) WHERE name LIKE ''language[_]model[_]%''))
-- End Semantic Search
OR (OBJECT_ID(''dbo.tbComputerTarget'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.tbTarget'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.tbUpdate'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.spGetUpdateByID'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.spSearchUpdates'',''P'') IS NOT NULL)
-- End WSUS
OR (OBJECT_ID(''dbo.tbl_DPM_InstalledUpdates'',''U'') IS NOT NULL AND SCHEMA_ID(''MSDPMExecRole'') IS NOT NULL AND SCHEMA_ID(''MSDPMRecoveryRole'') IS NOT NULL)
-- End DPM
OR ((OBJECT_ID(''dbo.DomainTable'',''U'') IS NOT NULL AND OBJECT_ID(''etl.Source'',''U'') IS NOT NULL)
OR (OBJECT_ID(''dbo.Module'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MT_Computer'',''U'') IS NOT NULL AND OBJECT_ID(''LFXSTG.vex_Collection'',''U'') IS NOT NULL AND SCHEMA_ID(''LFX'') IS NOT NULL)
OR (OBJECT_ID(''dbo.DomainTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.State'',''U'') IS NOT NULL AND SCHEMA_ID(''etl'') IS NOT NULL))
-- End SCSM
OR (OBJECT_ID(''dbo.ChunkData'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SegmentedChunk'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.SnapshotData'',''U'') IS NOT NULL AND SCHEMA_ID(''RSExecRole'') IS NOT NULL)
-- End SSRS
OR (OBJECT_ID(''dbo.prc_ChangeHostId'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.prc_EnablePrefixCompression'',''P'') IS NOT NULL 
AND (OBJECT_ID(''dbo.tbl_RegistryItems'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.tbl_OAuthToken'',''U'') IS NOT NULL AND	OBJECT_ID(''dbo.tbl_Content'',''U'') IS NOT NULL)
OR (OBJECT_ID(''dbo.DimBuild'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.FactCurrentWorkItem'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.FactBuildProject'',''U'') IS NOT NULL))
OR (OBJECT_ID(''dbo.LoadTestCase'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.LoadTestReport'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.LoadTestScenario'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.prc_GetAgents'',''P'') IS NOT NULL	AND OBJECT_ID(''dbo.prc_QueryLoadTestRuns'',''P'') IS NOT NULL)
-- End TFS
OR (OBJECT_ID(''dbo.Release'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Server'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.TeamProject'',''U'') IS NOT NULL AND SCHEMA_ID(''System.Activities.DurableInstancing'') IS NOT NULL)
-- End TFS Release Management
OR (OBJECT_ID(''dbo.ContainersTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Quotas'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Tenants'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.GetAllEntities'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.UpdateGatewayEntity'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.LockResourcesTable'',''U'') IS NOT NULL AND OBJECT_ID(''Store.Nodes'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.OperationsTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.AcquireLock'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.UpdateOperation'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.CursorsTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.LogsTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.MessagesTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.GetCursorState'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.LockEntity'',''P'') IS NOT NULL)
-- End Service Bus
OR (OBJECT_ID(''dbo.DebugTraces'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Instances'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.StoreVersionTable'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.GetInstanceCount'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.GetStoreVersion'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.StoreVersionTable'',''U'') IS NOT NULL AND OBJECT_ID(''Store.Clusters'',''U'') IS NOT NULL AND OBJECT_ID(''Store.Services'',''U'') IS NOT NULL AND OBJECT_ID(''Store.GetNode'',''P'') IS NOT NULL AND OBJECT_ID(''Store.UpdateCluster'',''P'') IS NOT NULL)
OR (OBJECT_ID(''dbo.Activities'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.Scopes'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.WorkflowServices'',''U'') IS NOT NULL AND OBJECT_ID(''dbo.GetActivities'',''P'') IS NOT NULL AND OBJECT_ID(''dbo.TenantCheck'',''P'') IS NOT NULL)
-- End Workflow Manager
OR (OBJECT_ID(''Core.Runbooks'',''U'') IS NOT NULL AND OBJECT_ID(''Core.Activities'',''U'') IS NOT NULL AND OBJECT_ID(''Core.Connections'',''U'') IS NOT NULL AND SCHEMA_ID(''Common'') IS NOT NULL)
-- End SCSMA
BEGIN
	SELECT @MSdbOUT = ' + CONVERT(VARCHAR(10), @dbid) + N'
END'
	SET @params = N'@MSdbOUT int OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @MSdbOUT=@MSdb OUTPUT
	
	IF @MSdb = @dbid
	BEGIN
		DELETE FROM #tmpdbs1 
		WHERE [dbid] = @dbid;
	END
	ELSE
	BEGIN
		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END
END;

UPDATE #tmpdbs1
SET isdone = 0;

RAISERROR (N'|-Applying 2nd layer of specific database scope, if any', 10, 1) WITH NOWAIT

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs_userchoice'))
DROP TABLE #tmpdbs_userchoice;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs_userchoice'))
CREATE TABLE #tmpdbs_userchoice ([dbid] int PRIMARY KEY, [dbname] NVARCHAR(1000))
	
IF @dbScope IS NOT NULL
BEGIN
	SELECT @sqlcmd = 'SELECT [dbid], [dbname] 
FROM #tmpdbs0 (NOLOCK) 
WHERE is_read_only = 0 AND [state] = 0 AND [dbid] > 4 AND is_distributor = 0
	AND [role] <> 2 AND (secondary_role_allow_connections <> 0 OR secondary_role_allow_connections IS NULL)
	AND [dbid] IN (' + REPLACE(@dbScope,' ','') + ')'
	
	INSERT INTO #tmpdbs_userchoice ([dbid], [dbname])
	EXEC sp_executesql @sqlcmd;

	SELECT @sqlcmd = 'DELETE FROM #tmpdbs1 WHERE [dbid] NOT IN (' + REPLACE(@dbScope,' ','') + ')'
	EXEC sp_executesql @sqlcmd;
END 
ELSE 
BEGIN 
	SELECT @sqlcmd = 'SELECT [dbid], [dbname]  
FROM #tmpdbs0 (NOLOCK)  
WHERE is_read_only = 0 AND [state] = 0 AND [dbid] > 4 AND is_distributor = 0 
	AND [role] <> 2 AND (secondary_role_allow_connections <> 0 OR secondary_role_allow_connections IS NULL)' 

	INSERT INTO #tmpdbs_userchoice ([dbid], [dbname]) 
	EXEC sp_executesql @sqlcmd;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Checks section
--------------------------------------------------------------------------------------------------------------------------------

RAISERROR (N'Starting Checks section', 10, 1) WITH NOWAIT

RAISERROR (N'|-Starting Processor Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Number of available Processors for this instance vs. MaxDOP setting subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Number of available Processors for this instance vs. MaxDOP setting', 10, 1) WITH NOWAIT
DECLARE /*@cpucount int, @numa int, */@affined_cpus int

/*
DECLARE @i int, @cpuaffin_fixed VARCHAR(1024)
SET @cpuaffin_fixed = @cpuaffin
SET @i = @cpucount/@numa + 1
WHILE @i < @cpucount + @numa
BEGIN
	IF (@cpucount + @numa) - @i >= CEILING(@cpucount*1.00/@numa)
	BEGIN
		SELECT @cpuaffin_fixed = STUFF(@cpuaffin_fixed, @i, 1, '_' + SUBSTRING(@cpuaffin_fixed, @i, 1))
	END
	ELSE
	BEGIN
		SELECT @cpuaffin_fixed = STUFF(@cpuaffin_fixed, @i, CEILING(@cpucount*1.00/@numa), SUBSTRING(@cpuaffin_fixed, @i, CEILING(@cpucount*1.00/@numa)))
	END

	SET @i = @i + CEILING(@cpucount*1.00/@numa) + 1
END;
*/

-- MaxDOP should be between 8 and 15. This is handled specifically on NUMA scenarios below.
SELECT @affined_cpus = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE is_online = 1 AND scheduler_id < 255 AND parent_node_id < 64;
--SELECT @cpucount = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64
SELECT 'Processor_checks' AS [Category], 'Parallelism_MaxDOP' AS [Check],
	CASE WHEN [value] > @affined_cpus THEN '[WARNING: MaxDOP setting exceeds available processor count (affinity)'
		WHEN @numa = 1 AND @affined_cpus <= 8 AND [value] > 0 AND [value] <> @affined_cpus THEN '[WARNING: MaxDOP setting is not recommended for current processor count (affinity)]'
		WHEN @numa = 1 AND @affined_cpus > 8 AND ([value] = 0 OR [value] > 8) THEN '[WARNING: MaxDOP setting is not recommended for current processor count (affinity)]'
		WHEN @sqlmajorver >= 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) <= 15 AND ([value] = 0 OR [value] > CEILING(@cpucount*1.00/@numa)) THEN '[WARNING: MaxDOP setting is not recommended for current NUMA node to processor count (affinity) ratio]'
		WHEN @sqlmajorver >= 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) > 15 AND ([value] = 0 OR [value] > CEILING(@cpucount*1.00/@numa/2)) THEN '[WARNING: MaxDOP setting is not recommended for current NUMA node to processor count (affinity) ratio]'
		WHEN @sqlmajorver < 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) < 8 AND ([value] = 0 OR [value] > CEILING(@cpucount*1.00/@numa)) THEN '[WARNING: MaxDOP setting is not recommended for current NUMA node to processor count (affinity) ratio]'
		WHEN @sqlmajorver < 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) >= 8 AND ([value] = 0 OR [value] > 8 OR [value] > CEILING(@cpucount*1.00/@numa)) THEN 'WARNING: MaxDOP setting is not recommended for current NUMA node to processor count (affinity) ratio]'
		ELSE '[OK]'
	END AS [Deviation]
FROM sys.configurations (NOLOCK) WHERE name = 'max degree of parallelism';	

SELECT 'Processor_checks' AS [Category], 'Parallelism_MaxDOP' AS [Information], 
	CASE 
		-- If not NUMA, and up to 8 @affined_cpus then MaxDOP up to 8
		WHEN @numa = 1 AND @affined_cpus <= 8 THEN @affined_cpus
		-- If not NUMA, and more than 8 @affined_cpus then MaxDOP 8 
		WHEN @numa = 1 AND @affined_cpus > 8 THEN 8
		-- If SQL 2016 or higher and has NUMA and # logical CPUs per NUMA up to 15, then MaxDOP is set as # logical CPUs per NUMA, up to 15 
		WHEN @sqlmajorver >= 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) <= 15 THEN CEILING((@cpucount*1.00)/@numa)
		-- If SQL 2016 or higher and has NUMA and # logical CPUs per NUMA > 15, then MaxDOP is set as 1/2 of # logical CPUs per NUMA
		WHEN @sqlmajorver >= 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) > 15 THEN 
			CASE WHEN CEILING(@cpucount*1.00/@numa/2) > 16 THEN 16 ELSE CEILING(@cpucount*1.00/@numa/2) END
		-- If up to SQL 2016 and has NUMA and # logical CPUs per NUMA up to 8, then MaxDOP is set as # logical CPUs per NUMA 
		WHEN @sqlmajorver < 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) < 8 THEN CEILING(@cpucount*1.00/@numa)
		-- If up to SQL 2016 and has NUMA and # logical CPUs per NUMA > 8, then MaxDOP 8
		WHEN @sqlmajorver < 13 AND @numa > 1 AND CEILING(@cpucount*1.00/@numa) >= 8 THEN 8
		ELSE 0
	END AS [Recommended_MaxDOP],
	[value] AS [Current_MaxDOP], @cpucount AS [Available_Processors], @affined_cpus AS [Affined_Processors], 
	-- Processor Affinity is shown highest to lowest CPU ID
	@cpuaffin_fixed AS Affinity_Mask_Bitmask
FROM sys.configurations (NOLOCK) WHERE name = 'max degree of parallelism';

--------------------------------------------------------------------------------------------------------------------------------
-- Processor Affinity in NUMA architecture subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Processor Affinity in NUMA architecture', 10, 1) WITH NOWAIT
IF @numa > 1
BEGIN
	WITH ncpuCTE (ncpus) AS (SELECT COUNT(cpu_id) AS ncpus from sys.dm_os_schedulers WHERE is_online = 1 AND scheduler_id < 255 AND parent_node_id < 64 GROUP BY parent_node_id, is_online HAVING COUNT(cpu_id) = 1),
	cpuCTE (node, afin) AS (SELECT DISTINCT(parent_node_id), is_online FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64 GROUP BY parent_node_id, is_online)
	SELECT 'Processor_checks' AS [Category], 'Affinity_NUMA' AS [Check],
		CASE WHEN (SELECT COUNT(*) FROM ncpuCTE) > 0 THEN '[WARNING: Current NUMA configuration is not recommended. At least one node has a single assigned CPU]' 
			WHEN (SELECT COUNT(DISTINCT(node)) FROM cpuCTE WHERE afin = 0 AND node NOT IN (SELECT DISTINCT(node) FROM cpuCTE WHERE afin = 1)) > 0 THEN '[WARNING: Current NUMA configuration is not recommended. At least one node does not have assigned CPUs]' 
			ELSE '[OK]' END AS [Deviation]
	FROM sys.dm_os_sys_info (NOLOCK) 
	OPTION (RECOMPILE);
	
	SELECT 'Processor_checks' AS [Category], 'Affinity_NUMA' AS [Information], cpu_count AS [Logical_CPU_Count], 
		(SELECT COUNT(DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64) AS [NUMA_Nodes],
		-- Processor Affinity is shown highest to lowest CPU ID
		@cpuaffin_fixed AS Affinity_Mask_Bitmask
	FROM sys.dm_os_sys_info (NOLOCK) 
	OPTION (RECOMPILE);
END
ELSE
BEGIN
	SELECT 'Processor_checks' AS [Category], 'Affinity_NUMA' AS [Check], '[Not_NUMA]' AS [Deviation]
	FROM sys.dm_os_sys_info (NOLOCK)
	OPTION (RECOMPILE);
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Check for HP Logical Processor issue (https://support.hpe.com/hpsc/doc/public/display?docId=emr_na-c04650594) subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Check for HP Logical Processor issue', 10, 1) WITH NOWAIT

IF LOWER(@SystemManufacturer) <> 'microsoft' AND LOWER(@SystemManufacturer) <> 'vmware' AND LOWER(@ostype) = 'windows'
BEGIN
	IF LOWER(@BIOSVendor) = 'hp' AND LOWER(@Processor_Name) like '%xeon%e5%' --and
	BEGIN
		SELECT 'Processor_checks' AS [Category], 'HP Logical Processor Issue' AS [Information], '[WARNING: You may be affected by HP Logical Processor issue outlined in https://support.hpe.com/hpsc/doc/public/display?docId=emr_na-c04650594]' AS [Deviation]
	END    
	ELSE
    BEGIN
        SELECT 'Processor_checks' AS [Category], 'HP Logical Processor Issue' AS [Check], '[INFORMATION: Not an affected HP Machine]' AS [Deviation];
    END;
END
ELSE
BEGIN
	SELECT 'Processor_checks' AS [Category], 'HP_Logical_Processor_Issue' AS [Check], '[Not a Physical Machine]' AS [Deviation];
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Additional Processor information subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Additional Processor information', 10, 1) WITH NOWAIT

-- Processor Info
SELECT 'Processor_checks' AS [Category], 'Processor_Summary' AS [Information], cpu_count AS [Logical_CPU_Count], hyperthread_ratio AS [Cores2Socket_Ratio],
	cpu_count/hyperthread_ratio AS [CPU_Sockets], 
	CASE WHEN @numa > 1 THEN (SELECT COUNT(DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64) ELSE 0 END AS [NUMA_Nodes],
	@affined_cpus AS [Affined_Processors], 
	-- Processor Affinity is shown highest to lowest Processor ID
	@cpuaffin_fixed AS Affinity_Mask_Bitmask
FROM sys.dm_os_sys_info (NOLOCK)
OPTION (RECOMPILE);

IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Processor utilization rate in the last 2 hours', 10, 1) WITH NOWAIT
	-- Processor utilization rate in the last 2 hours
	DECLARE @ts_now bigint
	DECLARE @tblAggCPU TABLE (SQLProc tinyint, SysIdle tinyint, OtherProc tinyint, Minutes tinyint)
	SELECT @ts_now = ms_ticks FROM sys.dm_os_sys_info (NOLOCK);

	WITH cteCPU (record_id, SystemIdle, SQLProcessUtilization, [timestamp]) AS (SELECT 
			record.value('(./Record/@id)[1]', 'int') AS record_id,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
			[TIMESTAMP] FROM (SELECT [TIMESTAMP], CONVERT(xml, record) AS record 
				FROM sys.dm_os_ring_buffers (NOLOCK)
				WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
				AND record LIKE '%<SystemHealth>%') AS x
		)
	INSERT INTO @tblAggCPU
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 10 
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -10, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 20
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -10, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -20, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 30
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -20, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -30, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 40
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -30, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -40, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 50
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -40, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -50, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 60
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -50, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -60, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 70
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -60, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -70, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 80
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -70, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -80, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 90
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -80, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -90, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 100
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -90, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -100, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 110
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -100, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -110, GETDATE())
	UNION ALL 
		SELECT AVG(SQLProcessUtilization), AVG(SystemIdle), CASE WHEN AVG(SystemIdle) + AVG(SQLProcessUtilization) < 100 THEN 100 - AVG(SystemIdle) - AVG(SQLProcessUtilization) ELSE 0 END, 120
		FROM cteCPU 
		WHERE DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) <= DATEADD(mi, -110, GETDATE()) AND 
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) > DATEADD(mi, -120, GETDATE())
	
	IF (SELECT COUNT(SysIdle) FROM @tblAggCPU WHERE SysIdle < 30) > 0
	BEGIN
		SELECT 'Processor_checks' AS [Category], 'Processor_Usage_last_2h' AS [Check], '[WARNING: Detected CPU usage over 70 pct]' AS [Deviation];
	END
	ELSE IF (SELECT COUNT(SysIdle) FROM @tblAggCPU WHERE SysIdle < 10) > 0
	BEGIN
		SELECT 'Processor_checks' AS [Category], 'Processor_Usage_last_2h' AS [Check], '[WARNING: Detected CPU usage over 90 pct]' AS [Deviation];
	END
	ELSE
	BEGIN
		SELECT 'Processor_checks' AS [Category], 'Processor_Usage_last_2h' AS [Check], '[OK]' AS [Deviation];
	END;

	SELECT 'Processor_checks' AS [Category], 'Agg_Processor_Usage_last_2h' AS [Information], SQLProc AS [SQL_Process_Utilization], SysIdle AS [System_Idle], OtherProc AS [Other_Process_Utilization], Minutes AS [Time_Slice_min]
	FROM @tblAggCPU;
END;

RAISERROR (N'|-Starting Memory Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Server Memory subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Server Memory', 10, 1) WITH NOWAIT
DECLARE @maxservermem bigint, @minservermem bigint, @systemmem bigint, @systemfreemem bigint, @numa_nodes_afinned tinyint, @LowMemoryThreshold int
DECLARE @commit_target bigint -- Includes stolen and reserved memory in the memory manager
DECLARE @committed bigint -- Does not include reserved memory in the memory manager
DECLARE @mwthreads_count int, @xtp int

IF @sqlmajorver = 9
BEGIN
	SET @sqlcmd = N'SELECT @systemmemOUT = t1.record.value(''(./Record/MemoryRecord/TotalPhysicalMemory)[1]'', ''bigint'')/1024, 
	@systemfreememOUT = t1.record.value(''(./Record/MemoryRecord/AvailablePhysicalMemory)[1]'', ''bigint'')/1024
FROM (SELECT MAX([TIMESTAMP]) AS [TIMESTAMP], CONVERT(xml, record) AS record 
	FROM sys.dm_os_ring_buffers (NOLOCK)
	WHERE ring_buffer_type = N''RING_BUFFER_RESOURCE_MONITOR''
		AND record LIKE ''%RESOURCE_MEMPHYSICAL%''
	GROUP BY record) AS t1';
END
ELSE
BEGIN
	SET @sqlcmd = N'SELECT @systemmemOUT = total_physical_memory_kb/1024, @systemfreememOUT = available_physical_memory_kb/1024 FROM sys.dm_os_sys_memory';
END

SET @params = N'@systemmemOUT bigint OUTPUT, @systemfreememOUT bigint OUTPUT';

EXECUTE sp_executesql @sqlcmd, @params, @systemmemOUT=@systemmem OUTPUT, @systemfreememOUT=@systemfreemem OUTPUT;

IF @sqlmajorver >= 9 AND @sqlmajorver < 11
BEGIN
	SET @sqlcmd = N'SELECT @commit_targetOUT=bpool_commit_target*8, @committedOUT=bpool_committed*8 FROM sys.dm_os_sys_info (NOLOCK)'
END
ELSE IF @sqlmajorver >= 11
BEGIN
	SET @sqlcmd = N'SELECT @commit_targetOUT=committed_target_kb, @committedOUT=committed_kb FROM sys.dm_os_sys_info (NOLOCK)'
END

SET @params = N'@commit_targetOUT bigint OUTPUT, @committedOUT bigint OUTPUT';

EXECUTE sp_executesql @sqlcmd, @params, @commit_targetOUT=@commit_target OUTPUT, @committedOUT=@committed OUTPUT;

SELECT @minservermem = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE [Name] = 'min server memory (MB)';
SELECT @maxservermem = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE [Name] = 'max server memory (MB)';
SELECT @mwthreads_count = max_workers_count FROM sys.dm_os_sys_info;
SELECT @numa_nodes_afinned = COUNT (DISTINCT parent_node_id) FROM sys.dm_os_schedulers WHERE scheduler_id < 255 AND parent_node_id < 64 AND is_online = 1

/* 
From Windows Internals book by David Solomon and Mark Russinovich:
"The default level of available memory that signals a low-memory-resource notification event is approximately 32 MB per 4 GB, 
to a maximum of 64 MB. The default level that signals a high-memory-resource notification event is three times the default low-memory value."
*/ 

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') = 1)
BEGIN
	BEGIN TRY
		SELECT @RegKey = N'System\CurrentControlSet\Control\SessionManager\MemoryManagement'
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @RegKey, N'LowMemoryThreshold', @LowMemoryThreshold OUTPUT, NO_OUTPUT
		
		IF @LowMemoryThreshold IS NULL
		SELECT @LowMemoryThreshold = CASE WHEN @systemmem <= 4096 THEN 32 ELSE 64 END
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Server Memory subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END
ELSE
BEGIN
	RAISERROR('[WARNING: Missing permissions for full "Instance info" checks. Bypassing LowMemoryThreshold check]', 16, 1, N'sysadmin')
	--RETURN
END;

SELECT 'Memory_checks' AS [Category], 'Memory_issues_MaxServerMem' AS [Check],
	CASE WHEN @maxservermem = 2147483647 THEN '[WARNING: MaxMem setting is default. Please revise memory settings]'
		WHEN @maxservermem > @systemmem THEN '[WARNING: MaxMem setting exceeds available system memory]'
		WHEN SERVERPROPERTY('EditionID') IN (284895786, 1293598313) AND @maxservermem > 67108864 THEN '[WARNING: MaxMem setting exceeds Web and Business Intelligence Edition limits]'
		WHEN SERVERPROPERTY('EditionID') = -1534726760 AND @maxservermem > 134217728 THEN '[WARNING: MaxMem setting exceeds Standard Edition limits]'
		WHEN SERVERPROPERTY('EngineEdition') = 4 AND @maxservermem > 1443840 THEN '[WARNING: MaxMem setting exceeds Express Edition limits]'
		WHEN @numa > 1 AND (@maxservermem/@numa) * @numa_nodes_afinned > (@systemmem/@numa) * @numa_nodes_afinned THEN '[WARNING: Current MaxMem setting will leverage node foreign memory. 
Maximum value for MaxMem setting on this configuration is ' + CONVERT(NVARCHAR,(@systemmem/@numa) * @numa_nodes_afinned) + ' for a single instance]'
		ELSE '[OK]'
	END AS [Deviation], @maxservermem AS [sql_max_mem_MB];

SELECT 'Memory_checks' AS [Category], 'Memory_issues_MinServerMem' AS [Check],
	CASE WHEN @minservermem = 0 AND (LOWER(@SystemManufacturer) = 'microsoft' OR LOWER(@SystemManufacturer) = 'vmware') THEN '[WARNING: Min Server Mem setting is not set in a VM, allowing memory pressure on the Host to attempt to deallocate memory on a guest SQL Server]'
		WHEN @minservermem = 0 AND @clustered = 1 THEN '[INFORMATION: Min Server Mem setting is default in a clustered instance. Leverage Min Server Mem for the purpose of limiting memory concurrency between instances]'
		WHEN @minservermem = @maxservermem THEN '[WARNING: Min Server Mem setting is equal to Max Server Mem. This will not allow dynamic memory. Please revise memory settings]'
		WHEN @numa > 1 AND (@minservermem/@numa) * @numa_nodes_afinned > (@systemmem/@numa) * @numa_nodes_afinned THEN '[WARNING: Current MinMem setting will leverage node foreign memory]'
		ELSE '[OK]'
	END AS [Deviation], @minservermem AS [sql_min_mem_MB];

SELECT 'Memory_checks' AS [Category], 'Memory_issues_FreeMem' AS [Check],
	CASE WHEN (@systemfreemem*100)/@systemmem <= 5 THEN '[WARNING: Less than 5 percent of Free Memory available. Please revise memory settings]'
		/* 64 is the default LowMemThreshold for windows on a system with 8GB of mem or more*/
		WHEN @systemfreemem <= 64*3 THEN '[WARNING: System Free Memory is dangerously low. Please revise memory settings]'
		ELSE '[OK]'
	END AS [Deviation], @systemmem AS system_total_physical_memory_MB, @systemfreemem AS system_available_physical_memory_MB;

SELECT 'Memory_checks' AS [Category], 'Memory_issues_CommitedMem' AS [Check],
	CASE WHEN @commit_target > @committed AND @sqlmajorver >= 11 THEN '[INFORMATION: Memory manager will try to obtain additional memory]'
		WHEN @commit_target < @committed AND @sqlmajorver >= 11  THEN '[INFORMATION: Memory manager will try to shrink the amount of memory committed]'
		WHEN @commit_target > @committed AND @sqlmajorver < 11 THEN '[INFORMATION: Buffer Pool will try to obtain additional memory]'
		WHEN @commit_target < @committed AND @sqlmajorver < 11  THEN '[INFORMATION: Buffer Pool will try to shrink]'
		ELSE '[OK]'
	END AS [Deviation], @commit_target/1024 AS sql_commit_target_MB, @committed/1024 AS sql_commited_MB;

SELECT 'Memory_checks' AS [Category], 'Memory_reference' AS [Check],
	CASE WHEN @arch IS NULL THEN '[WARNING: Could not determine architecture needed for check]'
		WHEN (@systemmem <= 2048 AND @maxservermem > @systemmem-512-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem BETWEEN 2049 AND 4096 AND @maxservermem > @systemmem-819-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem BETWEEN 4097 AND 8192 AND @maxservermem > @systemmem-1228-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem BETWEEN 8193 AND 12288 AND @maxservermem > @systemmem-2048-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem BETWEEN 12289 AND 24576 AND @maxservermem > @systemmem-2560-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem BETWEEN 24577 AND 32768 AND @maxservermem > @systemmem-3072-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END))- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) OR
		(@systemmem > 32768 AND SERVERPROPERTY('EditionID') IN (284895786, 1293598313) AND @maxservermem > CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 65536) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 65536)) AS int)) OR -- Find min of max mem for machine or max mem for Web and Business Intelligence SKU
		(@systemmem > 32768 AND SERVERPROPERTY('EditionID') = -1534726760 AND @maxservermem > CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 131072) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 131072)) AS int)) OR -- Find min of max mem for machine or max mem for Standard SKU
		(@systemmem > 32768 AND SERVERPROPERTY('EngineEdition') IN (3,8) AND @maxservermem > @systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) THEN '[WARNING: Not at the recommended MaxMem setting for this server memory configuration, with a single instance]' -- Enterprise Edition or Managed Instance
		ELSE 'OK'
	END AS [Deviation],		
	CASE WHEN @systemmem <= 2048 THEN @systemmem-512-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem BETWEEN 2049 AND 4096 THEN @systemmem-819-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem BETWEEN 4097 AND 8192 THEN @systemmem-1228-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem BETWEEN 8193 AND 12288 THEN @systemmem-2048-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem BETWEEN 12289 AND 24576 THEN @systemmem-2560-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem BETWEEN 24577 AND 32768 THEN @systemmem-3072-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)
		WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') IN (284895786, 1293598313) THEN CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 65536) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 65536)) AS int) -- Find min of max mem for machine or max mem for Web and Business Intelligence SKU
		WHEN @systemmem > 32768 AND SERVERPROPERTY('EditionID') = -1534726760 THEN CAST(0.5 * (((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) + 131072) - ABS((@systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END)) - 131072)) AS int) -- Find min of max mem for machine or max mem for Standard SKU
		WHEN @systemmem > 32768 AND SERVERPROPERTY('EngineEdition') IN (3,8) THEN @systemmem-4096-(@mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)- CASE WHEN @arch = 32 THEN 256 ELSE 0 END) -- Enterprise Edition or Managed Instance
	END AS [Recommended_MaxMem_MB_SingleInstance],
	CASE WHEN @systemmem <= 2048 THEN 512
		WHEN @systemmem BETWEEN 2049 AND 4096 THEN 819
		WHEN @systemmem BETWEEN 4097 AND 8192 THEN 1228
		WHEN @systemmem BETWEEN 8193 AND 12288 THEN 2048
		WHEN @systemmem BETWEEN 12289 AND 24576 THEN 2560
		WHEN @systemmem BETWEEN 24577 AND 32768 THEN 3072
		WHEN @systemmem > 32768 THEN 4096
	END AS [Mem_MB_for_OS],
	CASE WHEN @systemmem <= 2048 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem BETWEEN 2049 AND 4096 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem BETWEEN 4097 AND 8192 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem BETWEEN 8193 AND 12288 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem BETWEEN 12289 AND 24576 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem BETWEEN 24577 AND 32768 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
		WHEN @systemmem > 32768 THEN @mwthreads_count*(CASE WHEN @arch = 64 THEN 2 WHEN @arch = 128 THEN 4 WHEN @arch = 32 THEN 0.5 END)
	END AS [Potential_threads_mem_MB],
	@mwthreads_count AS [Configured_workers];

IF @sqlmajorver = 9
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Memory_Summary' AS [Information], 
		@maxservermem AS sql_max_mem_MB, @minservermem AS sql_min_mem_MB,
		@commit_target/1024 AS sql_commit_target_MB, --BPool in SQL 2005 to 2008R2
		@committed/1024 AS sql_commited_MB, --BPool in SQL 2005 to 2008R2
		@systemmem AS system_total_physical_memory_MB, 
		@systemfreemem AS system_available_physical_memory_MB
END
ELSE
BEGIN
	SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], ''Memory_Summary'' AS [Information], 
	@maxservermemIN AS sql_max_mem_MB, @minservermemIN AS sql_min_mem_MB, 
	@commit_targetIN/1024 AS sql_commit_target_MB, --BPool in SQL 2005 to 2008R2
	@committedIN/1024 AS sql_commited_MB, --BPool in SQL 2005 to 2008R2
	physical_memory_in_use_kb/1024 AS sql_physical_memory_in_use_MB, 
	large_page_allocations_kb/1024 AS sql_large_page_allocations_MB, 
	locked_page_allocations_kb/1024 AS sql_locked_page_allocations_MB,	
	@systemmemIN AS system_total_physical_memory_MB, 
	@systemfreememIN AS system_available_physical_memory_MB, 
	total_virtual_address_space_kb/1024 AS sql_total_VAS_MB, 
	virtual_address_space_reserved_kb/1024 AS sql_VAS_reserved_MB, 
	virtual_address_space_committed_kb/1024 AS sql_VAS_committed_MB, 
	virtual_address_space_available_kb/1024 AS sql_VAS_available_MB,
	page_fault_count AS sql_page_fault_count,
	memory_utilization_percentage AS sql_memory_utilization_percentage, 
	process_physical_memory_low AS sql_process_physical_memory_low, 
	process_virtual_memory_low AS sql_process_virtual_memory_low	
FROM sys.dm_os_process_memory (NOLOCK)'
	SET @params = N'@maxservermemIN bigint, @minservermemIN bigint, @systemmemIN bigint, @systemfreememIN bigint, @commit_targetIN bigint, @committedIN bigint';
	EXECUTE sp_executesql @sqlcmd, @params, @maxservermemIN=@maxservermem, @minservermemIN=@minservermem,@systemmemIN=@systemmem, @systemfreememIN=@systemfreemem, @commit_targetIN=@commit_target, @committedIN=@committed
END;

IF @numa > 1 AND @sqlmajorver > 10
BEGIN
	EXEC ('SELECT ''Memory_checks'' AS [Category], ''NUMA_Memory_Distribution'' AS [Information], memory_node_id, virtual_address_space_reserved_kb, virtual_address_space_committed_kb, locked_page_allocations_kb, pages_kb, foreign_committed_kb, shared_memory_reserved_kb, shared_memory_committed_kb, processor_group FROM sys.dm_os_memory_nodes;')
END
ELSE IF @numa > 1 AND @sqlmajorver = 10
BEGIN
	EXEC ('SELECT ''Memory_checks'' AS [Category], ''NUMA_Memory_Distribution'' AS [Information], memory_node_id, virtual_address_space_reserved_kb, virtual_address_space_committed_kb, locked_page_allocations_kb, single_pages_kb, multi_pages_kb, shared_memory_reserved_kb, shared_memory_committed_kb, processor_group FROM sys.dm_os_memory_nodes;')
END;

IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting RM Task', 10, 1) WITH NOWAIT

	IF @LowMemoryThreshold IS NOT NULL
	SELECT 'Memory_checks' AS [Category], 'Memory_RM_Tresholds' AS [Information], @LowMemoryThreshold AS [MEMPHYSICAL_LOW_Threshold], @LowMemoryThreshold * 3 AS [MEMPHYSICAL_HIGH_Threshold]

	SELECT 'Memory_checks' AS [Category], 'Memory_RM_Notifications' AS [Information], 
	CASE WHEN x.[TIMESTAMP] BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks BETWEEN -2147483648 AND 2147483647 THEN DATEADD(ms, x.[TIMESTAMP] - si.ms_ticks, GETDATE()) 
		ELSE DATEADD(s, ([TIMESTAMP]/1000) - (si.ms_ticks/1000), GETDATE()) END AS Event_Time,
		record.value('(./Record/ResourceMonitor/Notification)[1]', 'VARCHAR(max)') AS [Notification],
		record.value('(./Record/MemoryRecord/TotalPhysicalMemory)[1]', 'bigint')/1024 AS [Total_Physical_Mem_MB],
		record.value('(./Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint')/1024 AS [Avail_Physical_Mem_MB],
		record.value('(./Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint')/1024 AS [Avail_VAS_MB],
		record.value('(./Record/MemoryRecord/TotalPageFile)[1]', 'bigint')/1024 AS [Total_Pagefile_MB],
		record.value('(./Record/MemoryRecord/AvailablePageFile)[1]', 'bigint')/1024 AS [Avail_Pagefile_MB]
	FROM (SELECT [TIMESTAMP], CONVERT(xml, record) AS record 
				FROM sys.dm_os_ring_buffers (NOLOCK)
				WHERE ring_buffer_type = N'RING_BUFFER_RESOURCE_MONITOR') AS x
	CROSS JOIN sys.dm_os_sys_info si (NOLOCK)
	--WHERE CASE WHEN x.[timestamp] BETWEEN -2147483648 AND 2147483648 THEN DATEADD(ms, x.[timestamp] - si.ms_ticks, GETDATE()) 
	--	ELSE DATEADD(s, (x.[timestamp]/1000) - (si.ms_ticks/1000), GETDATE()) END >= DATEADD(hh, -12, GETDATE())
	ORDER BY 2 DESC;

	RAISERROR (N'  |-Starting Hand Movements from Cache Clock Hands', 10, 1) WITH NOWAIT

	IF (SELECT COUNT(rounds_count) FROM sys.dm_os_memory_cache_clock_hands (NOLOCK) WHERE rounds_count > 0) > 0
	BEGIN
		IF @sqlmajorver >= 11
		BEGIN
			SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], ''Clock_Hand_Notifications'' AS [Information], mcch.name, mcch.[type], 
	mcch.clock_hand, mcch.clock_status, SUM(mcch.rounds_count) AS rounds_count,
	SUM(mcch.removed_all_rounds_count) AS cache_entries_removed_all_rounds, 
	SUM(mcch.removed_last_round_count) AS cache_entries_removed_last_round,
	SUM(mcch.updated_last_round_count) AS cache_entries_updated_last_round,
	SUM(mcc.pages_kb) AS cache_pages_kb,
	SUM(mcc.pages_in_use_kb) AS cache_pages_in_use_kb,
	SUM(mcc.entries_count) AS cache_entries_count, 
	SUM(mcc.entries_in_use_count) AS cache_entries_in_use_count, 
	CASE WHEN mcch.last_tick_time BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks BETWEEN -2147483648 AND 2147483647 THEN DATEADD(ms, mcch.last_tick_time - si.ms_ticks, GETDATE()) 
		WHEN mcch.last_tick_time/1000 BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks/1000 BETWEEN -2147483648 AND 2147483647 THEN DATEADD(s, (mcch.last_tick_time/1000) - (si.ms_ticks/1000), GETDATE()) 
		ELSE NULL END AS last_clock_hand_move
FROM sys.dm_os_memory_cache_counters mcc (NOLOCK)
INNER JOIN sys.dm_os_memory_cache_clock_hands mcch (NOLOCK) ON mcc.cache_address = mcch.cache_address
CROSS JOIN sys.dm_os_sys_info si (NOLOCK)
WHERE mcch.rounds_count > 0
GROUP BY mcch.name, mcch.[type], mcch.clock_hand, mcch.clock_status, mcc.pages_kb, mcc.pages_in_use_kb, mcch.last_tick_time, si.ms_ticks, mcc.entries_count, mcc.entries_in_use_count
ORDER BY SUM(mcch.removed_all_rounds_count) DESC, mcch.[type];'
		END
		ELSE
		BEGIN
			SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], ''Clock_Hand_Notifications'' AS [Information], mcch.name, mcch.[type], 
	mcch.clock_hand, mcch.clock_status, SUM(mcch.rounds_count) AS rounds_count,
	SUM(mcch.removed_all_rounds_count) AS cache_entries_removed_all_rounds, 
	SUM(mcch.removed_last_round_count) AS cache_entries_removed_last_round,
	SUM(mcch.updated_last_round_count) AS cache_entries_updated_last_round,
	SUM(mcc.single_pages_kb) AS cache_single_pages_kb,
	SUM(mcc.multi_pages_kb) AS cache_multi_pages_kb,
	SUM(mcc.single_pages_in_use_kb) AS cache_single_pages_in_use_kb,
	SUM(mcc.multi_pages_in_use_kb) AS cache_multi_pages_in_use_kb,
	SUM(mcc.entries_count) AS cache_entries_count, 
	SUM(mcc.entries_in_use_count) AS cache_entries_in_use_count, 
	CASE WHEN mcch.last_tick_time BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks BETWEEN -2147483648 AND 2147483647 THEN DATEADD(ms, mcch.last_tick_time - si.ms_ticks, GETDATE()) 
		WHEN mcch.last_tick_time/1000 BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks/1000 BETWEEN -2147483648 AND 2147483647 THEN DATEADD(s, (mcch.last_tick_time/1000) - (si.ms_ticks/1000), GETDATE()) 
		ELSE NULL END AS last_clock_hand_move
FROM sys.dm_os_memory_cache_counters mcc (NOLOCK)
INNER JOIN sys.dm_os_memory_cache_clock_hands mcch (NOLOCK) ON mcc.cache_address = mcch.cache_address
CROSS JOIN sys.dm_os_sys_info si (NOLOCK)
WHERE mcch.rounds_count > 0
GROUP BY mcch.name, mcch.[type], mcch.clock_hand, mcch.clock_status, mcc.single_pages_kb, mcc.multi_pages_kb, mcc.single_pages_in_use_kb, mcc.multi_pages_in_use_kb, mcch.last_tick_time, si.ms_ticks, mcc.entries_count, mcc.entries_in_use_count
ORDER BY SUM(mcch.removed_all_rounds_count) DESC, mcch.[type];'
		END
		EXECUTE sp_executesql @sqlcmd;
	END
	ELSE
	BEGIN
		SELECT 'Memory_checks' AS [Category], 'Clock_Hand_Notifications' AS [Information], '[OK]' AS Comment
	END;
	
	IF @bpool_consumer = 1
	BEGIN
		RAISERROR (N'  |-Starting Buffer Pool Consumers from Buffer Descriptors', 10, 1) WITH NOWAIT
		
		-- Note: in case of NUMA architecture, more than one entry per database is expected

		SET @sqlcmd = 'SELECT ''Memory_checks'' AS [Category], ''Buffer_Pool_Consumers'' AS [Information], 
	numa_node, COUNT_BIG(DISTINCT page_id)*8/1024 AS total_pages_MB, 
	CASE database_id WHEN 32767 THEN ''ResourceDB'' ELSE DB_NAME(database_id) END AS database_name,
	SUM(CONVERT(BIGINT,row_count))/COUNT_BIG(DISTINCT page_id) AS avg_row_count_per_page, 
	SUM(CONVERT(BIGINT, free_space_in_bytes))/COUNT_BIG(DISTINCT page_id) AS avg_free_space_bytes_per_page
	' + CASE WHEN @sqlmajorver >= 12 THEN ',is_in_bpool_extension' ELSE '' END + '
	' + CASE WHEN @sqlmajorver = 10 THEN ',numa_node' ELSE '' END + '
	' + CASE WHEN @sqlmajorver >= 11 THEN ',AVG(read_microsec) AS avg_read_microsec' ELSE '' END + '
FROM sys.dm_os_buffer_descriptors
--WHERE bd.page_type IN (''DATA_PAGE'', ''INDEX_PAGE'')
GROUP BY database_id' + CASE WHEN @sqlmajorver >= 10 THEN ', numa_node' ELSE '' END + CASE WHEN @sqlmajorver >= 12 THEN ', is_in_bpool_extension' ELSE '' END + '
ORDER BY total_pages_MB DESC;'
		EXECUTE sp_executesql @sqlcmd;
	END

	RAISERROR (N'  |-Starting Memory Allocations from Memory Clerks', 10, 1) WITH NOWAIT
	
	SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], [type] AS Alloc_Type, 
	' + CASE WHEN @sqlmajorver < 11 THEN 'SUM(single_pages_kb + multi_pages_kb + virtual_memory_committed_kb + shared_memory_committed_kb + awe_allocated_kb) AS Alloc_Mem_KB'
		ELSE 'SUM(pages_kb + virtual_memory_committed_kb + shared_memory_committed_kb + awe_allocated_kb) AS Alloc_Mem_KB' END + '
FROM sys.dm_os_memory_clerks 
WHERE type IN (''CACHESTORE_COLUMNSTOREOBJECTPOOL'',''CACHESTORE_CLRPROC'',''CACHESTORE_OBJCP'',''CACHESTORE_PHDR'',''CACHESTORE_SQLCP'',''CACHESTORE_TEMPTABLES'',
	''MEMORYCLERK_SQLBUFFERPOOL'',''MEMORYCLERK_SQLCLR'',''MEMORYCLERK_SQLGENERAL'',''MEMORYCLERK_SQLLOGPOOL'',''MEMORYCLERK_SQLOPTIMIZER'',
	''MEMORYCLERK_SQLQUERYCOMPILE'',''MEMORYCLERK_SQLQUERYEXEC'',''MEMORYCLERK_SQLQUERYPLAN'',''MEMORYCLERK_SQLSTORENG'',''MEMORYCLERK_XTP'',
	''OBJECTSTORE_LOCK_MANAGER'',''OBJECTSTORE_SNI_PACKET'',''USERSTORE_DBMETADATA'',''USERSTORE_OBJPERM'')
GROUP BY [type]
UNION ALL
SELECT ''Memory_checks'' AS [Category], ''Others'' AS Alloc_Type, 
	' + CASE WHEN @sqlmajorver < 11 THEN 'SUM(single_pages_kb + multi_pages_kb + virtual_memory_committed_kb + shared_memory_committed_kb) AS Alloc_Mem_KB'
		ELSE 'SUM(pages_kb + virtual_memory_committed_kb + shared_memory_committed_kb) AS Alloc_Mem_KB' END + '
FROM sys.dm_os_memory_clerks 
WHERE type NOT IN (''CACHESTORE_COLUMNSTOREOBJECTPOOL'',''CACHESTORE_CLRPROC'',''CACHESTORE_OBJCP'',''CACHESTORE_PHDR'',''CACHESTORE_SQLCP'',''CACHESTORE_TEMPTABLES'',
	''MEMORYCLERK_SQLBUFFERPOOL'',''MEMORYCLERK_SQLCLR'',''MEMORYCLERK_SQLGENERAL'',''MEMORYCLERK_SQLLOGPOOL'',''MEMORYCLERK_SQLOPTIMIZER'',
	''MEMORYCLERK_SQLQUERYCOMPILE'',''MEMORYCLERK_SQLQUERYEXEC'',''MEMORYCLERK_SQLQUERYPLAN'',''MEMORYCLERK_SQLSTORENG'',''MEMORYCLERK_XTP'',
	''OBJECTSTORE_LOCK_MANAGER'',''OBJECTSTORE_SNI_PACKET'',''USERSTORE_DBMETADATA'',''USERSTORE_OBJPERM'')
ORDER BY Alloc_Mem_KB DESC'
	EXECUTE sp_executesql @sqlcmd;
	
	IF @sqlmajorver >= 12
	BEGIN
		SET @sqlcmd = N'SELECT @xtpOUT = COUNT(*) FROM sys.dm_db_xtp_memory_consumers';
		SET @params = N'@xtpOUT int OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @xtpOUT = @xtp OUTPUT;
		
		IF @xtp > 0
		BEGIN
			RAISERROR (N'  |-Starting Memory Consumers from In-Memory OLTP Engine', 10, 1) WITH NOWAIT
			SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], ''InMemory_Consumers'' AS Alloc_Type, 
	OBJECT_NAME([object_id]) AS [Object_Name], memory_consumer_type_desc, [object_id], index_id, 
	allocated_bytes/(1024*1024) AS Allocated_MB, used_bytes/(1024*1024) AS Used_MB, 
	CASE WHEN used_bytes IS NULL THEN ''used_bytes_is_varheap_only'' ELSE '''' END AS [Comment]
FROM sys.dm_db_xtp_memory_consumers
WHERE [object_id] > 0
ORDER BY Allocated_MB DESC' -- Only user objects; system objects are negative numbers
			EXECUTE sp_executesql @sqlcmd;

			RAISERROR (N'  |-Starting Memory Allocations from In-Memory OLTP Engine', 10, 1) WITH NOWAIT
			SET @sqlcmd = N'SELECT ''Memory_checks'' AS [Category], ''InMemory_Alloc'' AS Alloc_Type, 
	SUM(allocated_bytes)/(1024*1024) AS total_allocated_MB, SUM(used_bytes)/(1024*1024) AS total_used_MB
FROM sys.dm_db_xtp_memory_consumers
ORDER BY total_allocated_MB DESC'
			EXECUTE sp_executesql @sqlcmd;
		END;
	END;
END;

RAISERROR (N'  |-Starting OOM', 10, 1) WITH NOWAIT

IF (SELECT COUNT([TIMESTAMP]) FROM sys.dm_os_ring_buffers (NOLOCK) WHERE ring_buffer_type = N'RING_BUFFER_OOM') > 0
BEGIN		
	SELECT 'Memory_checks' AS [Category], 'OOM_Notifications' AS [Information], 
	CASE WHEN x.[TIMESTAMP] BETWEEN -2147483648 AND 2147483647 AND si.ms_ticks BETWEEN -2147483648 AND 2147483647 THEN DATEADD(ms, x.[TIMESTAMP] - si.ms_ticks, GETDATE()) 
		ELSE DATEADD(s, ([TIMESTAMP]/1000) - (si.ms_ticks/1000), GETDATE()) END AS Event_Time,
		record.value('(./Record/OOM/Action)[1]', 'varchar(50)') AS [Action],
		record.value('(./Record/OOM/Resources)[1]', 'int') AS [Resources],
		record.value('(./Record/OOM/Task)[1]', 'varchar(20)') AS [Task],
		record.value('(./Record/OOM/Pool)[1]', 'int') AS [PoolID],
		rgrp.name AS [PoolName],
		record.value('(./Record/MemoryRecord/MemoryUtilization)[1]', 'bigint') AS [MemoryUtilPct],
		record.value('(./Record/MemoryRecord/TotalPhysicalMemory)[1]', 'bigint')/1024 AS [Total_Physical_Mem_MB],
		record.value('(./Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint')/1024 AS [Avail_Physical_Mem_MB],
		record.value('(./Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint')/1024 AS [Avail_VAS_MB],
		record.value('(./Record/MemoryRecord/TotalPageFile)[1]', 'bigint')/1024 AS [Total_Pagefile_MB],
		record.value('(./Record/MemoryRecord/AvailablePageFile)[1]', 'bigint')/1024 AS [Avail_Pagefile_MB]
	FROM (SELECT [TIMESTAMP], CONVERT(xml, record) AS record 
				FROM sys.dm_os_ring_buffers (NOLOCK)
				WHERE ring_buffer_type = N'RING_BUFFER_OOM') AS x
	CROSS JOIN sys.dm_os_sys_info si (NOLOCK)
	LEFT JOIN sys.resource_governor_resource_pools rgrp (NOLOCK) ON rgrp.pool_id = record.value('(./Record/OOM/Pool)[1]', 'int')
	--WHERE CASE WHEN x.[timestamp] BETWEEN -2147483648 AND 2147483648 THEN DATEADD(ms, x.[timestamp] - si.ms_ticks, GETDATE()) 
	--	ELSE DATEADD(s, (x.[timestamp]/1000) - (si.ms_ticks/1000), GETDATE()) END >= DATEADD(hh, -12, GETDATE())
	ORDER BY 2 DESC;
END
ELSE
BEGIN
	SELECT 'Memory_checks' AS [Category], 'OOM_Notifications' AS [Information], '[OK]' AS Comment
END;

--------------------------------------------------------------------------------------------------------------------------------
-- LPIM subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting LPIM', 10, 1) WITH NOWAIT
DECLARE @lpim bit, @lognumber int, @logcount int

IF ((@sqlmajorver = 13 AND @sqlbuild >= 4000) OR @sqlmajorver > 13)
BEGIN
	SET @sqlcmd = N'SELECT @lpimOUT = CASE WHEN sql_memory_model = 2 THEN 1 ELSE 0 END FROM sys.dm_os_sys_info (NOLOCK)';
	SET @params = N'@lpimOUT bit OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @lpimOUT=@lpim OUTPUT;
END

IF ((@sqlmajorver = 13 AND @sqlbuild < 4000) OR (@sqlmajorver >= 10 AND @sqlmajorver < 13))
BEGIN
	SET @sqlcmd = N'SELECT @lpimOUT = CASE WHEN locked_page_allocations_kb > 0 THEN 1 ELSE 0 END FROM sys.dm_os_process_memory (NOLOCK)'
	SET @params = N'@lpimOUT bit OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @lpimOUT=@lpim OUTPUT
END

IF @sqlmajorver = 9
BEGIN
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
		OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin'), 0) = 1 -- Is securityadmin
		OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_readerrorlog') > 0
			AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_readerrorlog') > 0
			AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_enumerrorlogs') > 0)
	BEGIN
		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#lpimdbcc'))
		DROP TABLE #lpimdbcc;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#lpimdbcc'))
		CREATE TABLE #lpimdbcc (logdate DATETIME, spid VARCHAR(50), logmsg VARCHAR(4000))

		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#lpimavail_logs'))
		DROP TABLE #lpimavail_logs;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#lpimavail_logs'))
		CREATE TABLE #lpimavail_logs (lognum int, logdate DATETIME, logsize int) 

		-- Get the number of available logs 
		INSERT INTO #lpimavail_logs 
		EXEC xp_enumerrorlogs 
		
		SELECT @lognumber = MIN(lognum) FROM #lpimavail_logs WHERE DATEADD(dd, DATEDIFF(dd, 0, logdate), 0) >= DATEADD(dd, DATEDIFF(dd, 0, @StartDate), 0)

		SELECT @logcount = ISNULL(MAX(lognum),@lognumber) FROM #lpimavail_logs WHERE DATEADD(dd, DATEDIFF(dd, 0, logdate), 0) >= DATEADD(dd, DATEDIFF(dd, 0, @StartDate), 0)

		IF @lognumber IS NULL
		BEGIN
			SELECT @ErrorMessage = '[WARNING: Could not retrieve information about Locked pages usage in SQL Server 2005]'
			RAISERROR (@ErrorMessage, 16, 1);
		END
		ELSE
		WHILE @lognumber < @logcount 
		BEGIN
			-- Cycle through sql error logs (Cannot use Large Page Extensions:  lock memory privilege was not granted)
			SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''Using locked pages for buffer pool'''
			BEGIN TRY
				INSERT INTO #lpimdbcc (logdate, spid, logmsg) 
				EXECUTE (@sqlcmd);
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 1. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			-- Next log 
			--SET @lognumber = @lognumber + 1 
			SELECT @lognumber = MIN(lognum) FROM #lpimavail_logs WHERE lognum > @lognumber
		END 

		IF (SELECT COUNT(*) FROM #lpimdbcc) > 0
		BEGIN
			SET @lpim = 1
		END
		ELSE IF (SELECT COUNT(*) FROM #lpimdbcc) = 0 AND @lognumber IS NOT NULL
		BEGIN
			SET @lpim = 0
		END;
		
		DROP TABLE #lpimavail_logs;
		DROP TABLE #lpimdbcc;
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Only a sysadmin or securityadmin can run the "Locked_pages" check. Bypassing check]', 16, 1, N'permissions')
		RAISERROR('[WARNING: If not sysadmin or securityadmin, then user must be a granted EXECUTE permissions on the following sprocs to run checks: xp_enumerrorlogs and sp_readerrorlog. Bypassing check]', 16, 1, N'extended_sprocs')
		--RETURN
	END;
END

IF @lpim = 0 AND CONVERT(DECIMAL(3,1), @osver) < 6.0 AND @arch = 64
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Locked_pages' AS [Check], '[WARNING: Locked pages are not in use by SQL Server. In a WS2003 x64 architecture it is recommended to enable LPIM]' AS [Deviation]
END
ELSE IF @lpim = 1 AND CONVERT(DECIMAL(3,1), @osver) < 6.0 AND @arch = 64
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Locked_pages' AS [Check], '[INFORMATION: Locked pages are being used by SQL Server. This is recommended in a WS2003 x64 architecture]' AS [Deviation]
END
ELSE IF @lpim = 1 AND CONVERT(DECIMAL(3,1), @osver) >= 6.0 AND @arch = 64
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Locked_pages' AS [Check], '[INFORMATION: Locked pages are being used by SQL Server. This is recommended in WS2008 or above only when there are signs of paging]' AS [Deviation]
END
ELSE IF @lpim IS NULL
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Locked_pages' AS [Check], '[Could_not_retrieve_information]' AS [Deviation]
END
ELSE
BEGIN
	SELECT 'Memory_checks' AS [Category], 'Locked_pages' AS [Check], '[Not_used]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Pagefile subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Pagefile Checks', 10, 1) WITH NOWAIT
DECLARE @pf_value tinyint--, @RegKey NVARCHAR(255)
DECLARE @pagefile bigint, @freepagefile bigint, @paged bigint
DECLARE @tbl_pf_value TABLE (Value VARCHAR(25), Data VARCHAR(50))

IF @sqlmajorver = 9
BEGIN
	SET @sqlcmd = N'SELECT @pagefileOUT = (t1.record.value(''(./Record/MemoryRecord/TotalPageFile)[1]'', ''bigint'')-t1.record.value(''(./Record/MemoryRecord/TotalPhysicalMemory)[1]'', ''bigint''))/1024,
	@freepagefileOUT = (t1.record.value(''(./Record/MemoryRecord/AvailablePageFile)[1]'', ''bigint'')-t1.record.value(''(./Record/MemoryRecord/AvailablePhysicalMemory)[1]'', ''bigint''))/1024,
	@pagedOUT = ((t1.record.value(''(./Record/MemoryRecord/TotalPageFile)[1]'', ''bigint'')-t1.record.value(''(./Record/MemoryRecord/AvailablePageFile)[1]'', ''bigint''))/t1.record.value(''(./Record/MemoryRecord/TotalPageFile)[1]'', ''bigint''))/1024
FROM (SELECT MAX([TIMESTAMP]) AS [TIMESTAMP], CONVERT(xml, record) AS record 
	FROM sys.dm_os_ring_buffers (NOLOCK)
	WHERE ring_buffer_type = N''RING_BUFFER_RESOURCE_MONITOR''
		AND record LIKE ''%RESOURCE_MEMPHYSICAL%''
	GROUP BY record) AS t1';
END
ELSE
BEGIN
	SET @sqlcmd = N'SELECT @pagefileOUT = (total_page_file_kb-total_physical_memory_kb)/1024, 
	@freepagefileOUT = (available_page_file_kb-available_physical_memory_kb)/1024, 
	@pagedOUT = ((total_page_file_kb-available_page_file_kb)/total_page_file_kb) 
FROM sys.dm_os_sys_memory (NOLOCK)';
END

SET @params = N'@pagefileOUT bigint OUTPUT, @freepagefileOUT bigint OUTPUT, @pagedOUT bigint OUTPUT';

EXECUTE sp_executesql @sqlcmd, @params, @pagefileOUT=@pagefile OUTPUT, @freepagefileOUT=@freepagefile OUTPUT, @pagedOUT=@paged OUTPUT;

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') = 1)
BEGIN
	BEGIN TRY
		SELECT @RegKey = N'System\CurrentControlSet\Control\Session Manager\Memory Management'
		INSERT INTO @tbl_pf_value
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @RegKey, N'PagingFiles', NO_OUTPUT
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Pagefile subsection - Error raised in TRY block 1. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END
ELSE
BEGIN
	RAISERROR('[WARNING: Missing permissions for full "Pagefile" checks. Bypassing System managed pagefile check]', 16, 1, N'sysadmin')
	--RETURN
END;

IF (SELECT COUNT(*) FROM @tbl_pf_value) > 0 
BEGIN
	SELECT @pf_value = CASE WHEN (SELECT COUNT(*) FROM @tbl_pf_value WHERE Data = '') > 0 THEN 1
			WHEN (SELECT COUNT(*) FROM @tbl_pf_value WHERE Data = '?:\pagefile.sys') > 0 THEN 2
			WHEN (SELECT COUNT(*) FROM @tbl_pf_value WHERE Data LIKE '%:\pagefile.sys 0 0%') > 0 THEN 3
		ELSE 0 END
	FROM @tbl_pf_value

	SELECT 'Pagefile_checks' AS [Category], 'Pagefile_management' AS [Check], 
		CASE WHEN @pf_value = 1 THEN '[WARNING: No pagefile is configured]'
			WHEN @pf_value = 2 THEN '[WARNING: Pagefile is managed automatically on ALL drives]'
			WHEN @pf_value = 3 THEN '[WARNING: Pagefile is managed automatically]'
		ELSE '[OK]' END AS [Deviation]
END

SELECT 'Pagefile_checks' AS [Category], 'Pagefile_free_space' AS [Check],
	CASE WHEN @freepagefile <= 150 THEN '[WARNING: Pagefile free space is dangerously low. Please revise Pagefile settings]'
		WHEN (@freepagefile*100)/@pagefile <= 10 THEN '[WARNING: Less than 10 percent of Pagefile is available. Please revise Pagefile settings]'
		WHEN (@freepagefile*100)/@pagefile <= 30 THEN '[INFORMATION: Less than 30 percent of Pagefile is available]'
		ELSE '[OK]' END AS [Deviation], 
	@pagefile AS total_pagefile_MB, @freepagefile AS available_pagefile_MB;

SELECT 'Pagefile_checks' AS [Category], 'Pagefile_minimum_size' AS [Check],
	CASE WHEN @osver = '5.2' AND @arch = 64 AND @pagefile < 8192 THEN '[WARNING: Pagefile is smaller than 8GB on a WS2003 x64 system. Please revise Pagefile settings]'
		WHEN @osver = '5.2' AND @arch = 32 AND @pagefile < 2048 THEN '[WARNING: Pagefile is smaller than 2GB on a WS2003 x86 system. Please revise Pagefile settings]'
		WHEN @osver <> '5.2' THEN '[NA]'
		ELSE '[OK]' END AS [Deviation], 
	@pagefile AS total_pagefile_MB;
	
SELECT 'Pagefile_checks' AS [Category], 'Process_paged_out' AS [Check],
	CASE WHEN @paged > 0 THEN '[WARNING: Part of SQL Server process memory has been paged out. Please revise LPIM settings]'
		ELSE '[OK]' END AS [Deviation], 
	@paged AS paged_out_MB;

IF @ptochecks = 1
RAISERROR (N'|-Starting I/O Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- I/O stall in database files over 50% of cumulative sampled time or I/O latencies over 20ms in the last 5s subsection
-- io_stall refers to user processes waited for I/O. This number can be much greater than the sample_ms.
-- Might indicate that your I/O has insufficient service capabilities (HBA queue depths, reduced throughput, etc). 
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting I/O Stall subsection (wait for 5s)', 10, 1) WITH NOWAIT

	DECLARE @mincol DATETIME, @maxcol DATETIME

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_io_virtual_file_stats'))
	DROP TABLE #tmp_dm_io_virtual_file_stats;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_io_virtual_file_stats'))	
	CREATE TABLE [dbo].[#tmp_dm_io_virtual_file_stats]([retrieval_time] [datetime],database_id int, [file_id] int, [DBName] sysname, [logical_file_name] NVARCHAR(255), [type_desc] NVARCHAR(60), 
		[physical_location] NVARCHAR(260),[sample_ms] bigint,[num_of_reads] bigint,[num_of_bytes_read] bigint,[io_stall_read_ms] bigint,[num_of_writes] bigint,
		[num_of_bytes_written] bigint,[io_stall_write_ms] bigint,[io_stall] bigint,[size_on_disk_bytes] bigint,
		CONSTRAINT PK_dm_io_virtual_file_stats PRIMARY KEY CLUSTERED(database_id, [file_id], [retrieval_time]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIOStall'))
	DROP TABLE #tblIOStall;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIOStall'))
	CREATE TABLE #tblIOStall (database_id int, [file_id] int, [DBName] sysname, [logical_file_name] NVARCHAR(255), [type_desc] NVARCHAR(60),
		[physical_location] NVARCHAR(260), size_on_disk_Mbytes int, num_of_reads bigint, num_of_writes bigint, num_of_KBytes_read bigint, num_of_KBytes_written bigint,
		io_stall_ms int, io_stall_read_ms int, io_stall_write_ms int, avg_read_latency_ms int, avg_write_latency_ms int, avg_io_stall_read_pct int, cumulative_io_stall_read_pct int, 
		avg_io_stall_write_pct int, cumulative_io_stall_write_pct int, cumulative_sample_HH int, io_stall_pct_of_cumulative_sample int, 		
		CONSTRAINT PK_IOStall PRIMARY KEY CLUSTERED(database_id, [file_id]));

	SELECT @mincol = GETDATE()

	INSERT INTO #tmp_dm_io_virtual_file_stats
	SELECT @mincol, f.database_id, f.[file_id], DB_NAME(f.database_id), f.name AS logical_file_name, f.type_desc, 
		CAST (CASE 
			-- Handle UNC paths (e.g. '\\fileserver\readonlydbs\dept_dw.ndf')
			WHEN LEFT (LTRIM (f.physical_name), 2) = '\\' 
				THEN LEFT (LTRIM (f.physical_name),CHARINDEX('\',LTRIM(f.physical_name),CHARINDEX('\',LTRIM(f.physical_name), 3) + 1) - 1)
				-- Handle local paths (e.g. 'C:\Program Files\...\master.mdf') 
				WHEN CHARINDEX('\', LTRIM(f.physical_name), 3) > 0 
				THEN UPPER(LEFT(LTRIM(f.physical_name), CHARINDEX ('\', LTRIM(f.physical_name), 3) - 1))
			ELSE f.physical_name
		END AS NVARCHAR(255)) AS physical_location,
		fs.[sample_ms],fs.[num_of_reads],fs.[num_of_bytes_read],fs.[io_stall_read_ms],fs.[num_of_writes],
		fs.[num_of_bytes_written],fs.[io_stall_write_ms],fs.[io_stall],fs.[size_on_disk_bytes]
	FROM sys.dm_io_virtual_file_stats (default, default) AS fs
	INNER JOIN sys.master_files AS f ON fs.database_id = f.database_id AND fs.[file_id] = f.[file_id]
	
	WAITFOR DELAY '00:00:05' -- wait 5s between pooling
	
	SELECT @maxcol = GETDATE()

	INSERT INTO #tmp_dm_io_virtual_file_stats
	SELECT @maxcol, f.database_id, f.[file_id], DB_NAME(f.database_id), f.name AS logical_file_name, f.type_desc, 
		CAST (CASE 
			-- Handle UNC paths (e.g. '\\fileserver\readonlydbs\dept_dw.ndf')
			WHEN LEFT (LTRIM (f.physical_name), 2) = '\\' 
				THEN LEFT (LTRIM (f.physical_name),CHARINDEX('\',LTRIM(f.physical_name),CHARINDEX('\',LTRIM(f.physical_name), 3) + 1) - 1)
				-- Handle local paths (e.g. 'C:\Program Files\...\master.mdf') 
				WHEN CHARINDEX('\', LTRIM(f.physical_name), 3) > 0 
				THEN UPPER(LEFT(LTRIM(f.physical_name), CHARINDEX ('\', LTRIM(f.physical_name), 3) - 1))
			ELSE f.physical_name
		END AS NVARCHAR(255)) AS physical_location,
		fs.[sample_ms],fs.[num_of_reads],fs.[num_of_bytes_read],fs.[io_stall_read_ms],fs.[num_of_writes],
		fs.[num_of_bytes_written],fs.[io_stall_write_ms],fs.[io_stall],fs.[size_on_disk_bytes]
	FROM sys.dm_io_virtual_file_stats (default, default) AS fs
	INNER JOIN sys.master_files AS f ON fs.database_id = f.database_id AND fs.[file_id] = f.[file_id]
	
	;WITH cteFileStats1 AS (SELECT database_id,[file_id],[DBName],[logical_file_name],[type_desc], 
			[physical_location],[sample_ms],[num_of_reads],[num_of_bytes_read],[io_stall_read_ms],[num_of_writes],
			[num_of_bytes_written],[io_stall_write_ms],[io_stall],[size_on_disk_bytes]
		FROM #tmp_dm_io_virtual_file_stats WHERE [retrieval_time] = @mincol),
		cteFileStats2 AS (SELECT database_id,[file_id],[DBName],[logical_file_name],[type_desc], 
			[physical_location],[sample_ms],[num_of_reads],[num_of_bytes_read],[io_stall_read_ms],[num_of_writes],
			[num_of_bytes_written],[io_stall_write_ms],[io_stall],[size_on_disk_bytes]
		FROM #tmp_dm_io_virtual_file_stats WHERE [retrieval_time] = @maxcol)
	INSERT INTO #tblIOStall
	SELECT t1.database_id, t1.[file_id], t1.[DBName], t1.logical_file_name, t1.type_desc, t1.physical_location,
		t1.size_on_disk_bytes/1024/1024 AS size_on_disk_Mbytes,
		(t2.num_of_reads-t1.num_of_reads) AS num_of_reads, 
		(t2.num_of_writes-t1.num_of_writes) AS num_of_writes,
		(t2.num_of_bytes_read-t1.num_of_bytes_read)/1024 AS num_of_KBytes_read,
		(t2.num_of_bytes_written-t1.num_of_bytes_written)/1024 AS num_of_KBytes_written,
		(t2.io_stall-t1.io_stall) AS io_stall_ms, 
		(t2.io_stall_read_ms-t1.io_stall_read_ms) AS io_stall_read_ms, 
		(t2.io_stall_write_ms-t1.io_stall_write_ms) AS io_stall_write_ms,
		((t2.io_stall_read_ms-t1.io_stall_read_ms) / (1.0 + (t2.num_of_reads-t1.num_of_reads))) AS avg_read_latency_ms,
		((t2.io_stall_write_ms-t1.io_stall_write_ms) / (1.0 + (t2.num_of_writes-t1.num_of_writes))) AS avg_write_latency_ms,
		((t2.io_stall_read_ms - t1.io_stall_read_ms) * 100.) / (CASE WHEN (t2.io_stall - t1.io_stall) <= 0 THEN 1 ELSE (t2.io_stall - t1.io_stall) END) AS avg_io_stall_read_pct,
		((t2.io_stall_read_ms)*100)/(CASE WHEN t2.io_stall = 0 THEN 1 ELSE t2.io_stall END) AS cumulative_io_stall_read_pct,
		((t2.io_stall_write_ms - t1.io_stall_write_ms) * 100.) / (CASE WHEN (t2.io_stall - t1.io_stall) <= 0 THEN 1 ELSE (t2.io_stall - t1.io_stall) END) AS avg_io_stall_write_pct,
		((t2.io_stall_write_ms)*100)/(CASE WHEN t2.io_stall = 0 THEN 1 ELSE t2.io_stall END) AS cumulative_io_stall_write_pct,
		ABS((t2.sample_ms/1000)/60/60) AS cumulative_sample_HH,
		((t2.io_stall/1000/60)*100)/(ABS((t2.sample_ms/1000)/60)) AS io_stall_pct_of_cumulative_sample
	FROM cteFileStats1 t1 INNER JOIN cteFileStats2 t2 ON t1.database_id = t2.database_id AND t1.[file_id] = t2.[file_id]
		
	IF (SELECT COUNT([logical_file_name]) FROM #tblIOStall WHERE avg_read_latency_ms >= 20) > 0
		OR (SELECT COUNT([logical_file_name]) FROM #tblIOStall WHERE avg_write_latency_ms >= 20) > 0
	BEGIN
		SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Check], '[WARNING: Some database files have latencies >= 20ms in the last 5s. Review I/O related performance counters and storage-related configurations.]' AS [Deviation]
		SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Information], [DBName] AS [Database_Name], [logical_file_name], [type_desc], avg_read_latency_ms, avg_write_latency_ms, 
			[physical_location], size_on_disk_Mbytes, num_of_reads AS physical_reads, num_of_writes AS physical_writes, 
			num_of_KBytes_read, num_of_KBytes_written, io_stall_ms, io_stall_read_ms, io_stall_write_ms,
			avg_io_stall_read_pct, cumulative_io_stall_read_pct, avg_io_stall_write_pct, cumulative_io_stall_write_pct, cumulative_sample_HH, io_stall_pct_of_cumulative_sample
		FROM #tblIOStall
		WHERE avg_read_latency_ms >= 20 OR avg_write_latency_ms >= 20
		ORDER BY avg_read_latency_ms DESC, avg_write_latency_ms DESC, [DBName], [type_desc], [logical_file_name]
	END
	ELSE IF (SELECT COUNT([logical_file_name]) FROM #tblIOStall WHERE io_stall_pct_of_cumulative_sample > 50) > 0
	BEGIN
		SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Check], '[WARNING: Some database files have stall I/O exceeding 50 pct of cumulative sampled time. Review I/O related performance counters and storage-related configurations.]' AS [Deviation]
		SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Information], [DBName] AS [Database_Name], [logical_file_name], [type_desc], avg_read_latency_ms, avg_write_latency_ms, 
			[physical_location], size_on_disk_Mbytes, num_of_reads AS physical_reads, num_of_writes AS physical_writes, 
			num_of_KBytes_read, num_of_KBytes_written, io_stall_ms, io_stall_read_ms, io_stall_write_ms,
			avg_io_stall_read_pct, cumulative_io_stall_read_pct, avg_io_stall_write_pct, cumulative_io_stall_write_pct, cumulative_sample_HH, io_stall_pct_of_cumulative_sample
		FROM #tblIOStall
		WHERE io_stall_pct_of_cumulative_sample > 50
		ORDER BY io_stall_pct_of_cumulative_sample DESC, [DBName], [type_desc], [logical_file_name]
	END
	ELSE
	BEGIN
		SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Check], '[OK]' AS [Deviation]
		/*SELECT 'IO_checks' AS [Category], 'Stalled_IO' AS [Information], [DBName] AS [Database_Name], [logical_file_name], [type_desc], avg_read_latency_ms, avg_write_latency_ms, 
			[physical_location], size_on_disk_Mbytes, num_of_reads AS physical_reads, num_of_writes AS physical_writes, 
			num_of_KBytes_read, num_of_KBytes_written, io_stall_ms, io_stall_read_ms, io_stall_write_ms,
			avg_io_stall_read_pct, cumulative_io_stall_read_pct, avg_io_stall_write_pct, cumulative_io_stall_write_pct, cumulative_sample_HH, io_stall_pct_of_cumulative_sample
		FROM #tblIOStall
		ORDER BY [DBName], [type_desc], [logical_file_name]*/
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Pending disk I/O Requests subsection
-- Indicate that your I/O has insufficient service capabilities (HBA queue depths, reduced throughput, etc). 
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Pending disk I/O Requests subsection (wait for a max of 5s)', 10, 1) WITH NOWAIT
	DECLARE @IOCnt tinyint
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIOReq'))
	DROP TABLE #tblPendingIOReq;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIOReq'))
	CREATE TABLE #tblPendingIOReq (io_completion_request_address varbinary(8), io_handle varbinary(8), io_type VARCHAR(7), io_pending bigint, io_pending_ms_ticks bigint, scheduler_address varbinary(8));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIO'))
	DROP TABLE #tblPendingIO;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIO'))
	CREATE TABLE #tblPendingIO (database_id int, [file_id] int, [DBName] sysname, [logical_file_name] NVARCHAR(255), [type_desc] NVARCHAR(60),
		[physical_location] NVARCHAR(260), io_stall_min int, io_stall_read_min int, io_stall_write_min int, avg_read_latency_ms int,
		avg_write_latency_ms int, io_stall_read_pct int, io_stall_write_pct int, sampled_HH int, 
		io_stall_pct_of_overall_sample int, io_completion_request_address varbinary(8), io_handle varbinary(8), io_type VARCHAR(7), io_pending bigint, io_pending_ms_ticks bigint, scheduler_address varbinary(8),
		scheduler_id int, pending_disk_io_count int, work_queue_count bigint);

	SET @IOCnt = 1
	WHILE @IOCnt < 5
	BEGIN
		INSERT INTO #tblPendingIOReq
		SELECT io_completion_request_address, io_handle, io_type, io_pending, io_pending_ms_ticks, scheduler_address
		FROM sys.dm_io_pending_io_requests;

		IF (SELECT COUNT(io_pending) FROM #tblPendingIOReq WHERE io_type = 'disk') > 1
		BREAK

		WAITFOR DELAY '00:00:01' -- wait 1s between pooling

		SET @IOCnt = @IOCnt + 1
	END;

	IF (SELECT COUNT(io_pending) FROM #tblPendingIOReq WHERE io_type = 'disk') > 0
	BEGIN
		INSERT INTO #tblPendingIO
		SELECT DISTINCT f.database_id, f.[file_id], DB_NAME(f.database_id) AS database_name, f.name AS logical_file_name, f.type_desc, 
			CAST (CASE 
				-- Handle UNC paths (e.g. '\\fileserver\readonlydbs\dept_dw.ndf')
				WHEN LEFT (LTRIM (f.physical_name), 2) = '\\' 
					THEN LEFT (LTRIM (f.physical_name),CHARINDEX('\',LTRIM(f.physical_name),CHARINDEX('\',LTRIM(f.physical_name), 3) + 1) - 1)
					-- Handle local paths (e.g. 'C:\Program Files\...\master.mdf') 
					WHEN CHARINDEX('\', LTRIM(f.physical_name), 3) > 0 
					THEN UPPER(LEFT(LTRIM(f.physical_name), CHARINDEX ('\', LTRIM(f.physical_name), 3) - 1))
				ELSE f.physical_name
			END AS NVARCHAR(255)) AS physical_location,
			fs.io_stall/1000/60 AS io_stall_min, 
			fs.io_stall_read_ms/1000/60 AS io_stall_read_min, 
			fs.io_stall_write_ms/1000/60 AS io_stall_write_min,
			(fs.io_stall_read_ms / (1.0 + fs.num_of_reads)) AS avg_read_latency_ms,
			(fs.io_stall_write_ms / (1.0 + fs.num_of_writes)) AS avg_write_latency_ms,
			((fs.io_stall_read_ms/1000/60)*100)/(CASE WHEN fs.io_stall/1000/60 = 0 THEN 1 ELSE fs.io_stall/1000/60 END) AS io_stall_read_pct, 
			((fs.io_stall_write_ms/1000/60)*100)/(CASE WHEN fs.io_stall/1000/60 = 0 THEN 1 ELSE fs.io_stall/1000/60 END) AS io_stall_write_pct,
			ABS((fs.sample_ms/1000)/60/60) AS 'sample_HH', 
			((fs.io_stall/1000/60)*100)/(ABS((fs.sample_ms/1000)/60))AS 'io_stall_pct_of_overall_sample',
			pio.io_completion_request_address, pio.io_handle, pio.io_type, pio.io_pending,
			pio.io_pending_ms_ticks, pio.scheduler_address, os.scheduler_id, os.pending_disk_io_count, os.work_queue_count
		FROM #tblPendingIOReq AS pio 
		INNER JOIN sys.dm_io_virtual_file_stats (NULL,NULL) AS fs ON fs.file_handle = pio.io_handle
		INNER JOIN sys.dm_os_schedulers AS os ON pio.scheduler_address = os.scheduler_address
		INNER JOIN sys.master_files AS f ON fs.database_id = f.database_id AND fs.[file_id] = f.[file_id];
	END;

	IF (SELECT COUNT(io_pending) FROM #tblPendingIOReq WHERE io_type = 'disk') > 0
	BEGIN
		SELECT 'IO_checks' AS [Category], 'Pending_IO' AS [Check], '[WARNING: Pending disk I/O requests were found. Review I/O related performance counters and storage-related configurations]' AS [Deviation]
		SELECT 'IO_checks' AS [Category], 'Pending_IO' AS [Information], [DBName] AS [Database_Name], [logical_file_name], [type_desc], avg_read_latency_ms, avg_write_latency_ms, 
		io_stall_read_pct, io_stall_write_pct, sampled_HH, io_stall_pct_of_overall_sample, [physical_location], io_stall_min, io_stall_read_min, io_stall_write_min,
		io_completion_request_address, io_type, CASE WHEN io_pending = 1 THEN 'Pending_Context_Switching' ELSE 'Pending_WindowsOS' END AS io_pending_type,
		io_pending_ms_ticks, scheduler_address, scheduler_id, pending_disk_io_count, work_queue_count
		FROM #tblPendingIO
		ORDER BY scheduler_address, [DBName], [type_desc], [logical_file_name]
	END
	ELSE
	BEGIN
		SELECT 'IO_checks' AS [Category], 'Pending_IO' AS [Check], '[OK]' AS [Deviation]
	END;
END;

RAISERROR (N'|-Starting Server Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Power plan subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Power plan', 10, 1) WITH NOWAIT

DECLARE @planguid NVARCHAR(64), @powerkey1 NVARCHAR(255), @powerkey2 NVARCHAR(255) 
--SELECT @powerkey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}'
--SELECT @powerkey = 'SYSTEM\CurrentControlSet\Control\Power\User\Default\PowerSchemes'
SELECT @powerkey1 = 'SOFTWARE\Policies\Microsoft\Power\PowerSettings'
SELECT @powerkey2 = 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'

IF CONVERT(DECIMAL(3,1), @osver) >= 6.0
BEGIN
	BEGIN TRY
		-- Check if was set by GPO, if not, look in user settings 
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @powerkey1, 'ActivePowerScheme', @planguid OUTPUT, NO_OUTPUT

		IF @planguid IS NULL 
		BEGIN 
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @powerkey2, 'ActivePowerScheme', @planguid OUTPUT, NO_OUTPUT 
		END 
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Power plan subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
END

-- http://support.microsoft.com/kb/935799/en-us

IF @osver IS NULL 
BEGIN
	SELECT 'Server_checks' AS [Category], 'Current_Power_Plan' AS [Check], '[WARNING: Could not determine Windows version for check]' AS [Deviation]
END
ELSE IF @planguid IS NOT NULL AND @planguid <> N'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
BEGIN
	SELECT 'Server_checks' AS [Category], 'Current_Power_Plan' AS [Check], '[WARNING: The current power plan scheme is not recommended for database servers. Please reconfigure for High Performance mode]' AS [Deviation]
	SELECT 'Server_checks' AS [Category], 'Current_Power_Plan' AS [Information], CASE WHEN @planguid = N'381b4222-f694-41f0-9685-ff5bb260df2e' THEN 'Balanced'
		WHEN @planguid = N'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' THEN 'High Performance'
		WHEN @planguid = N'a1841308-3541-4fab-bc81-f71556f20b4a' THEN 'Power Saver'
		ELSE 'Other' END AS [Power_Plan]
END
ELSE IF @planguid IS NOT NULL AND @planguid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
BEGIN
	SELECT 'Server_checks' AS [Category], 'Current_Power_Plan' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Disk Partition alignment offset < 64KB subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Disk Partition alignment offset < 64KB', 10, 1) WITH NOWAIT
IF @ostype <> 'Windows'
BEGIN
	RAISERROR('    |- [INFORMATION: "partition alignment offset" check was skipped: not Windows OS.]', 10, 1, N'not_windows')
	--RETURN
END
ELSE IF @ostype = 'Windows' AND @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted'))
BEGIN
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
			AND (SELECT COUNT(l.name)
			FROM sys.server_permissions p JOIN sys.server_principals l 
			ON p.grantee_principal_id = l.principal_id
				AND p.class = 100 -- Server
				AND p.state IN ('G', 'W') -- Granted or Granted with Grant
				AND l.is_disabled = 0
				AND p.permission_name = 'ALTER SETTINGS'
				AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') > 0)))
	BEGIN
		DECLARE @diskpart int

		SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
		SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
		SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

		RAISERROR ('    |-Configuration options set for Disk partition alignment offset check', 10, 1) WITH NOWAIT
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
		END
		
		DECLARE @output_hw_tot_diskpart TABLE ([PS_OUTPUT] VARCHAR(2048));
		DECLARE @output_hw_format_diskpart TABLE ([volid] smallint IDENTITY(1,1), [HD_Partition] VARCHAR(50) NULL, StartingOffset bigint NULL)

		IF @custompath IS NULL
		BEGIN
			IF @sqlmajorver < 11
			BEGIN
				EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\Setup',N'SQLPath', @path OUTPUT
				SET @path = @path + '\LOG'
			END
			ELSE
			BEGIN
				SET @sqlcmd = N'SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations';
				SET @params = N'@pathOUT NVARCHAR(2048) OUTPUT';
				EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
			END

			-- Create COM object with FSO
			EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FSO OUT
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END
			ELSE
			BEGIN
				EXEC @OLEResult = master.dbo.sp_OAMethod @FSO, 'FolderExists', @existout OUT, @path
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling FolderExists Method 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					IF @existout <> 1
					BEGIN
						SET @path = CONVERT(NVARCHAR(500), SERVERPROPERTY('ErrorLogFileName'))
						SET @path = LEFT(@path,LEN(@path)-CHARINDEX('\', REVERSE(@path)))
					END 
				END
				EXEC @OLEResult = sp_OADestroy @FSO
			END
		END
		ELSE
		BEGIN
			SELECT @path = CASE WHEN @custompath LIKE '%\' THEN LEFT(@custompath, LEN(@custompath)-1) ELSE @custompath END
		END
			
		SET @FileName = @path + '\checkbp_diskpart_' + RTRIM(@server) + '.ps1'
				
		EXEC master.dbo.xp_fileexist @FileName, @existout out
		IF @existout = 0
		BEGIN -- Scan for local disks
			SET @Text1 = '[string] $serverName = ''localhost''
$partitions = Get-WmiObject -computername $serverName -query "SELECT * FROM Win32_DiskPartition"
foreach ($partition in $partitions)
{
[string] $diskpart = "{0}_{1};{2}" -f $partition.DiskIndex,$partition.Index,$partition.StartingOffset
Write-Output $diskpart
}
'
			EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FS OUT
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END

			--Open file
			EXEC @OLEResult = master.dbo.sp_OAMethod @FS, 'OpenTextFile', @FileID OUT, @FileName, 2, 1
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Calling OpenTextFile Method 0x%x, %s, %s' + CHAR(10) + 'Could not create file ' + @FileName
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END
			ELSE
			BEGIN
				SELECT @ErrorMessage = '    |-Created file ' + @FileName
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
			END

			--Write Text1
			EXEC @OLEResult = master.dbo.sp_OAMethod @FileID, 'WriteLine', NULL, @Text1
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Calling WriteLine Method 0x%x, %s, %s' + CHAR(10) + 'Could not write to file ' + @FileName
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END

			EXEC @OLEResult = sp_OADestroy @FileID
			EXEC @OLEResult = sp_OADestroy @FS
		END
		ELSE
		BEGIN
			SELECT @ErrorMessage = '    |-Reusing file ' + @FileName
			RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
		END
			
		IF @psver = 1
		BEGIN
			SET @CMD = 'powershell -NoLogo -NoProfile "' + @FileName + '" -ExecutionPolicy RemoteSigned'
		END
		ELSE
		BEGIN
			SET @CMD = 'powershell -NoLogo -NoProfile -File "' + @FileName + '" -ExecutionPolicy RemoteSigned'
		END;
		
		INSERT INTO @output_hw_tot_diskpart
		EXEC master.dbo.xp_cmdshell @CMD
			
		SET @CMD = 'del /Q "' + @FileName + '"'
		EXEC master.dbo.xp_cmdshell @CMD, NO_OUTPUT
		
		INSERT INTO @output_hw_format_diskpart ([HD_Partition],StartingOffset)
		SELECT LEFT(RTRIM([PS_OUTPUT]), CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT]))-1 END),
				RIGHT(RTRIM([PS_OUTPUT]), LEN(RTRIM([PS_OUTPUT]))-CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT])) END)
		FROM @output_hw_tot_diskpart
		WHERE [PS_OUTPUT] IS NOT NULL;
		
		SET @CMD2 = 'del ' + @FileName
		EXEC master.dbo.xp_cmdshell @CMD2, NO_OUTPUT;
					
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
		END;
					
		;WITH diskpartcte (StartingOffset) AS (
			SELECT StartingOffset
			FROM @output_hw_format_diskpart
			WHERE StartingOffset IS NOT NULL OR LEN(StartingOffset) > 0)
		SELECT @diskpart = CASE WHEN (SELECT COUNT(*) FROM diskpartcte) = 0 THEN NULL ELSE COUNT(cte1.[StartingOffset]) END
		FROM diskpartcte cte1
		WHERE cte1.[StartingOffset] < 65536;
		
		IF @diskpart > 0 AND @diskpart IS NOT NULL
		BEGIN
			SELECT 'Server_checks' AS [Category], 'Partition_Alignment' AS [Check], '[WARNING: Some disk partitions are not using a minimum recommended alignment offset of 64KB]' AS [Deviation]
			SELECT 'Server_checks' AS [Category], 'Partition_Alignment' AS [Information], LEFT(t1.[HD_Partition],LEN(t1.[HD_Partition])-CHARINDEX('_',t1.[HD_Partition])) AS HD_Volume, 
				RIGHT(t1.[HD_Partition],LEN(t1.[HD_Partition])-CHARINDEX('_',t1.[HD_Partition])) AS [HD_Partition], 
				(t1.StartingOffset/1024) AS [StartingOffset_KB]
			FROM @output_hw_format_diskpart t1
			WHERE t1.StartingOffset IS NOT NULL OR LEN(t1.StartingOffset) > 0
			ORDER BY t1.[HD_Partition]
			OPTION (RECOMPILE);
		END
		ELSE IF @diskpart IS NULL
		BEGIN
			SELECT 'Server_checks' AS [Category], 'Partition_Alignment' AS [Check], '[WARNING: Could not gather information on disk partition offset size]' AS [Deviation]
		END
		ELSE
		BEGIN
			SELECT 'Server_checks' AS [Category], 'Partition_Alignment' AS [Check], '[OK]' AS [Deviation]
		END;
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Only a sysadmin can run the "partition alignment offset" checks. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
		RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_cmdshell, xp_instance_regread, xp_regread, xp_fileexist and xp_regenumvalues. Bypassing check]', 16, 1, N'extended_sprocs')
		--RETURN
	END
END
ELSE
BEGIN
	RAISERROR('    |- [INFORMATION: "partition alignment offset" check was skipped: either xp_cmdshell or execution of PS scripts was not allowed.]', 10, 1, N'disallow_xp_cmdshell')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- NTFS block size in volumes that hold database files <> 64KB subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting NTFS block size in volumes that hold database files <> 64KB', 10, 1) WITH NOWAIT
IF @ostype <> 'Windows'
BEGIN
	RAISERROR('    |- [INFORMATION: "NTFS block size" check was skipped: not Windows OS.]', 10, 1, N'not_windows')
	--RETURN
END
ELSE IF @ostype = 'Windows' AND @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted'))
BEGIN
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
			AND (SELECT COUNT(l.name)
			FROM sys.server_permissions p JOIN sys.server_principals l 
			ON p.grantee_principal_id = l.principal_id
				AND p.class = 100 -- Server
				AND p.state IN ('G', 'W') -- Granted or Granted with Grant
				AND l.is_disabled = 0
				AND p.permission_name = 'ALTER SETTINGS'
				AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0 AND
			(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') > 0)))
	BEGIN
		DECLARE @ntfs int

		SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
		SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
		SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

		RAISERROR ('    |-Configuration options set for NTFS Block size check', 10, 1) WITH NOWAIT
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
		END

		DECLARE @output_hw_tot_ntfs TABLE ([PS_OUTPUT] VARCHAR(2048));
		DECLARE @output_hw_format_ntfs TABLE ([volid] smallint IDENTITY(1,1), [HD_Volume] NVARCHAR(2048) NULL, [NTFS_Block] NVARCHAR(8) NULL)

		IF @custompath IS NULL
		BEGIN
			IF @sqlmajorver < 11
			BEGIN
				EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\Setup',N'SQLPath', @path OUTPUT
				SET @path = @path + '\LOG'
			END
			ELSE
			BEGIN
				SET @sqlcmd = N'SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations';
				SET @params = N'@pathOUT NVARCHAR(2048) OUTPUT';
				EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
			END

			-- Create COM object with FSO
			EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FSO OUT
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END
			ELSE
			BEGIN
				EXEC @OLEResult = master.dbo.sp_OAMethod @FSO, 'FolderExists', @existout OUT, @path
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling FolderExists Method 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					IF @existout <> 1
					BEGIN
						SET @path = CONVERT(NVARCHAR(500), SERVERPROPERTY('ErrorLogFileName'))
						SET @path = LEFT(@path,LEN(@path)-CHARINDEX('\', REVERSE(@path)))
					END 
				END
				EXEC @OLEResult = sp_OADestroy @FSO
			END
		END
		ELSE
		BEGIN
			SELECT @path = CASE WHEN @custompath LIKE '%\' THEN LEFT(@custompath, LEN(@custompath)-1) ELSE @custompath END
		END
			
		SET @FileName = @path + '\checkbp_ntfs_' + RTRIM(@server) + '.ps1'
				
		EXEC master.dbo.xp_fileexist @FileName, @existout out
		IF @existout = 0
		BEGIN -- Scan for local disks
			SET @Text1 = '[string] $serverName = ''localhost''
$vols = Get-WmiObject -computername $serverName -query "select name, blocksize from Win32_Volume where Capacity <> NULL and DriveType = 3"
foreach($vol in $vols)
{
[string] $drive = "{0};{1}" -f $vol.name,$vol.blocksize
Write-Output $drive
} '
			EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FS OUT
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END

			--Open file
			EXEC @OLEResult = master.dbo.sp_OAMethod @FS, 'OpenTextFile', @FileID OUT, @FileName, 2, 1
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Calling OpenTextFile Method 0x%x, %s, %s' + CHAR(10) + 'Could not create file ' + @FileName
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END
			ELSE
			BEGIN
				SELECT @ErrorMessage = '    |-Created file ' + @FileName
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
			END

			--Write Text1
			EXEC @OLEResult = master.dbo.sp_OAMethod @FileID, 'WriteLine', NULL, @Text1
			IF @OLEResult <> 0
			BEGIN
				EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
				SELECT @ErrorMessage = 'Error Calling WriteLine Method 0x%x, %s, %s' + CHAR(10) + 'Could not write to file ' + @FileName
				RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
			END

			EXEC @OLEResult = sp_OADestroy @FileID
			EXEC @OLEResult = sp_OADestroy @FS
		END
		ELSE
		BEGIN
			SELECT @ErrorMessage = '    |-Reusing file ' + @FileName
			RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
		END

		IF @psver = 1
		BEGIN
			SET @CMD = 'powershell -NoLogo -NoProfile "' + @FileName + '" -ExecutionPolicy RemoteSigned'
		END
		ELSE
		BEGIN
			SET @CMD = 'powershell -NoLogo -NoProfile -File "' + @FileName + '" -ExecutionPolicy RemoteSigned'
		END;

		INSERT INTO @output_hw_tot_ntfs
		EXEC master.dbo.xp_cmdshell @CMD

		SET @CMD = 'del /Q "' + @FileName + '"'
		EXEC master.dbo.xp_cmdshell @CMD, NO_OUTPUT
		
		INSERT INTO @output_hw_format_ntfs ([HD_Volume],[NTFS_Block])
		SELECT LEFT(RTRIM([PS_OUTPUT]), CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT]))-1 END),
				RIGHT(RTRIM([PS_OUTPUT]), LEN(RTRIM([PS_OUTPUT]))-CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT])) END)
		FROM @output_hw_tot_ntfs
		WHERE [PS_OUTPUT] IS NOT NULL;
		
		SET @CMD2 = 'del ' + @FileName
		EXEC master.dbo.xp_cmdshell @CMD2, NO_OUTPUT;
			
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @ole = 0
		BEGIN
			EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
		END;
			
		WITH ntfscte (physical_name, ntfsblock) AS (
			SELECT DISTINCT(LEFT(physical_name, LEN(t2.HD_Volume))), [NTFS_Block]
			FROM sys.master_files t1 INNER JOIN @output_hw_format_ntfs t2
			ON LEFT(physical_name, LEN(t2.HD_Volume)) = t2.HD_Volume
			WHERE [database_id] <> 32767 AND (t2.[NTFS_Block] IS NOT NULL OR LEN(t2.[NTFS_Block]) > 0)
		)
		SELECT @ntfs = CASE WHEN (SELECT COUNT(*) FROM ntfscte) = 0 THEN NULL ELSE COUNT(cte1.[ntfsblock]) END
		FROM ntfscte cte1
		WHERE cte1.[ntfsblock] <> 65536;
		
		IF @ntfs > 0 AND @ntfs IS NOT NULL
		BEGIN
			SELECT 'Server_checks' AS [Category], 'NTFS_Block_Size' AS [Check], '[WARNING: Some volumes that hold database files are not formatted using the recommended NTFS block size of 64KB]' AS [Deviation]
			SELECT 'Server_checks' AS [Category], 'NTFS_Block_Size' AS [Information], t1.HD_Volume, (t1.[NTFS_Block]/1024) AS [NTFS_Block_Size_KB]
			FROM (SELECT DISTINCT(LEFT(physical_name, LEN(t2.HD_Volume))) AS [HD_Volume], [NTFS_Block]
				FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format_ntfs t2
					ON LEFT(physical_name, LEN(t2.HD_Volume)) = t2.HD_Volume
					WHERE [database_id] <> 32767 AND (t2.[NTFS_Block] IS NOT NULL OR LEN(t2.[NTFS_Block]) > 0)) t1
			ORDER BY t1.HD_Volume OPTION (RECOMPILE);
		END
		ELSE IF @ntfs IS NULL
		BEGIN
			SELECT 'Server_checks' AS [Category], 'NTFS_Block_Size' AS [Check], '[WARNING: Could not gather information on NTFS block size]' AS [Deviation]
		END
		ELSE
		BEGIN
			SELECT 'Server_checks' AS [Category], 'NTFS_Block_Size' AS [Check], '[OK]' AS [Deviation]
		END;
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Only a sysadmin can run the "NTFS block size" checks. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
		RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_cmdshell, xp_instance_regread, xp_regread, xp_fileexist and xp_regenumvalues. Bypassing check]', 16, 1, N'extended_sprocs')
		--RETURN
	END
	END
ELSE
BEGIN
	RAISERROR('    |- [INFORMATION: "NTFS block size" check was skipped: either xp_cmdshell or execution of PS scripts was not allowed.]', 10, 1, N'disallow_xp_cmdshell')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Disk Fragmentation Analysis subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @diskfrag = 1
BEGIN
	RAISERROR (N'  |-Starting Disk Fragmentation Analysis', 10, 1) WITH NOWAIT
	IF @ostype <> 'Windows'
	BEGIN
		RAISERROR('    |- [INFORMATION: "Disk Fragmentation Analysis" check was skipped: not Windows OS.]', 10, 1, N'not_windows')
		--RETURN
	END
	ELSE IF @ostype = 'Windows' AND @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted'))
	BEGIN
		IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
				AND (SELECT COUNT(l.name)
				FROM sys.server_permissions p JOIN sys.server_principals l 
				ON p.grantee_principal_id = l.principal_id
					AND p.class = 100 -- Server
					AND p.state IN ('G', 'W') -- Granted or Granted with Grant
					AND l.is_disabled = 0
					AND p.permission_name = 'ALTER SETTINGS'
					AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') > 0)))
		BEGIN
			DECLARE @frag int
		
			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
			SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

			RAISERROR ('    |-Configuration options set for Disk Fragmentation Analysis', 10, 1) WITH NOWAIT

			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
			END
		
			DECLARE @output_hw_frag TABLE ([PS_OUTPUT] VARCHAR(2048));
			DECLARE @output_hw_format_frag TABLE ([volid] smallint IDENTITY(1,1), [volfrag] VARCHAR(255), [fragrec] VARCHAR(10) NULL)

			IF @custompath IS NULL
			BEGIN
				IF @sqlmajorver < 11
				BEGIN
					EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\Setup',N'SQLPath', @path OUTPUT
					SET @path = @path + '\LOG'
				END
				ELSE
				BEGIN
					SET @sqlcmd = N'SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations';
					SET @params = N'@pathOUT NVARCHAR(2048) OUTPUT';
					EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
				END

				-- Create COM object with FSO
				EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FSO OUT
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					EXEC @OLEResult = master.dbo.sp_OAMethod @FSO, 'FolderExists', @existout OUT, @path
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Calling FolderExists Method 0x%x, %s, %s'
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END
					ELSE
					BEGIN
						IF @existout <> 1
						BEGIN
							SET @path = CONVERT(NVARCHAR(500), SERVERPROPERTY('ErrorLogFileName'))
							SET @path = LEFT(@path,LEN(@path)-CHARINDEX('\', REVERSE(@path)))
						END 
					END
					EXEC @OLEResult = sp_OADestroy @FSO
				END
			END
			ELSE
			BEGIN
				SELECT @path = CASE WHEN @custompath LIKE '%\' THEN LEFT(@custompath, LEN(@custompath)-1) ELSE @custompath END
			END
			
			SET @FileName = @path + '\checkbp_frag_' + RTRIM(@server) + '.ps1'
				
			EXEC master.dbo.xp_fileexist @FileName, @existout out
			IF @existout = 0
			BEGIN -- Scan for frag
				SET @Text1 = '$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if ($myWindowsPrincipal.IsInRole($adminRole))
{
	[string] $serverName = ''localhost''
	$DiskResults = @()
	$objDisks = Get-WmiObject -Computername $serverName -Class Win32_Volume | Where-Object { $_.DriveType -eq 3 -and $_.Name -like "*:\"}
	ForEach( $disk in $objDisks)
	{
		$objDefrag = $disk.DefragAnalysis()
		$rec = $objDefrag.DefragRecommended
		$objDefragDetail = $objDefrag.DefragAnalysis
		$diskFragmentation = $objDefragDetail.TotalPercentFragmentation
		$FreeFragmentation = $objDefragDetail.FreeSpacePercentFragmentation
		$FileFragmentation = $objDefragDetail.FilePercentFragmentation

		[string] $ThisVolume = "{0}TotalFragPct {1} :: FreeSpaceFragPct {2} :: FileFragPct {3};{4}" -f $($disk.Name),$diskFragmentation,$FreeFragmentation,$FileFragmentation,$rec
		$DiskResults += $ThisVolume
	}
	$DiskResults
}
else
{
	Write-Host "NotAdmin"
}
'
				EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FS OUT
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END

				--Open file
				EXEC @OLEResult = master.dbo.sp_OAMethod @FS, 'OpenTextFile', @FileID OUT, @FileName, 2, 1
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling OpenTextFile Method 0x%x, %s, %s' + CHAR(10) + 'Could not create file ' + @FileName
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					SELECT @ErrorMessage = '    |-Created file ' + @FileName
					RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
				END

				--Write Text1
				EXEC @OLEResult = master.dbo.sp_OAMethod @FileID, 'WriteLine', NULL, @Text1
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling WriteLine Method 0x%x, %s, %s' + CHAR(10) + 'Could not write to file ' + @FileName
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END

				EXEC @OLEResult = sp_OADestroy @FileID
				EXEC @OLEResult = sp_OADestroy @FS
			END
			ELSE
			BEGIN
				SELECT @ErrorMessage = '    |-Reusing file ' + @FileName
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
			END
			
			RAISERROR ('    |-Getting Disk(s) Fragmentation. This may take some time...', 10, 1) WITH NOWAIT

			IF @psver = 1
			BEGIN
				SET @CMD = 'powershell -NoLogo -NoProfile "' + @FileName + '" -ExecutionPolicy RemoteSigned'
			END
			ELSE
			BEGIN
				SET @CMD = 'powershell -NoLogo -NoProfile -File "' + @FileName + '" -ExecutionPolicy RemoteSigned'
			END;

			INSERT INTO @output_hw_frag
			EXEC master.dbo.xp_cmdshell @CMD
			
			SET @CMD = 'del /Q "' + @FileName + '"'
			EXEC master.dbo.xp_cmdshell @CMD, NO_OUTPUT

			IF (SELECT COUNT([PS_OUTPUT]) FROM @output_hw_frag WHERE [PS_OUTPUT] LIKE '%NotAdmin%') = 1
			BEGIN
				RAISERROR ('[WARNING: Powershell not running under Elevated Privileges. Bypassing Disk Fragmentation Analysis]',16,1);
			END
			ELSE
			BEGIN
				INSERT INTO @output_hw_format_frag ([volfrag],fragrec)
				SELECT LEFT(RTRIM([PS_OUTPUT]), CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT]))-1 END),
						RIGHT(RTRIM([PS_OUTPUT]), LEN(RTRIM([PS_OUTPUT]))-CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT])) END)
				FROM @output_hw_frag
				WHERE [PS_OUTPUT] IS NOT NULL
			END
		
			SET @CMD2 = 'del ' + @FileName
			EXEC master.dbo.xp_cmdshell @CMD2, NO_OUTPUT;
			
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END;

			;WITH fragcte (fragrec) AS (
				SELECT fragrec
				FROM @output_hw_format_frag
				WHERE fragrec IS NOT NULL OR LEN(fragrec) > 0)
			SELECT @frag = CASE WHEN (SELECT COUNT(*) FROM fragcte) = 0 THEN NULL ELSE COUNT(cte1.[fragrec]) END
			FROM fragcte cte1
			WHERE cte1.[fragrec] = 'True';
		
			IF @frag > 0 AND @frag IS NOT NULL
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Disk_Fragmentation' AS [Check], '[WARNING: Found volumes with physical fragmentation. Determine how and when these can be defragmented]' AS [Deviation]
				SELECT 'Server_checks' AS [Category], 'Disk_Fragmentation' AS [Information], 
					LEFT(t1.[volfrag],1) AS HD_Volume, 
					RIGHT(t1.[volfrag],(LEN(t1.[volfrag])-3)) AS [Fragmentation_Percent], 
					t1.fragrec AS [Defragmentation_Recommended]
				FROM @output_hw_format_frag t1
				WHERE t1.fragrec = 'True'
				ORDER BY t1.[volfrag]
				OPTION (RECOMPILE);
			END
			ELSE IF @frag IS NULL
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Disk_Fragmentation' AS [Check], '[WARNING: Could not gather information on Disk Fragmentation Analysis]' AS [Deviation]
			END
			ELSE
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Disk_Fragmentation' AS [Check], '[OK]' AS [Deviation]
				SELECT 'Server_checks' AS [Category], 'Disk_Fragmentation' AS [Information], 
					LEFT(t1.[volfrag],1) AS HD_Volume, 
					RIGHT(t1.[volfrag],(LEN(t1.[volfrag])-3)) AS [Fragmentation_Percent],
					t1.fragrec AS [Defragmentation_Recommended]
				FROM @output_hw_format_frag t1
				ORDER BY t1.[volfrag]
				OPTION (RECOMPILE);
			END;
		END
		ELSE
		BEGIN
			RAISERROR('[WARNING: Only a sysadmin can run the "Disk Fragmentation Analysis" checks. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
			RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_cmdshell, xp_instance_regread, xp_regread, xp_fileexist and xp_regenumvalues. Bypassing check]', 16, 1, N'extended_sprocs')
			--RETURN
		END
		END
	ELSE
	BEGIN
		RAISERROR('    |- [INFORMATION: "Disk Fragmentation Analysis" check was skipped: either xp_cmdshell or execution of PS scripts was not allowed]', 10, 1, N'disallow_xp_cmdshell')
		--RETURN
	END
END
ELSE
BEGIN
	RAISERROR('  |- [INFORMATION: "Disk Fragmentation Analysis" check is disabled]', 10, 1, N'disallow_diskfrag')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Cluster Quorum Model subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @clustered = 1 AND @osver <> '5.2'
BEGIN
	RAISERROR (N'  |-Starting Cluster Quorum Model', 10, 1) WITH NOWAIT
	IF @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted')) AND @psver > 1
	BEGIN
		IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0)) -- Is not sysadmin but proxy account exists
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0))
		BEGIN
			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'

			RAISERROR ('    |-Configuration options set for Cluster Quorum Model check', 10, 1) WITH NOWAIT
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END
			
			DECLARE /*@CMD NVARCHAR(4000), @line int, @linemax int, */ @CntNodes tinyint, @CntVotes tinyint
				
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluNodesOutput'))
			DROP TABLE #xp_cmdshell_CluNodesOutput;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluNodesOutput'))
			CREATE TABLE #xp_cmdshell_CluNodesOutput (line int IDENTITY(1,1) PRIMARY KEY, [Output] VARCHAR(50));
				
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluOutput'))
			DROP TABLE #xp_cmdshell_CluOutput;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluOutput'))
			CREATE TABLE #xp_cmdshell_CluOutput (line int IDENTITY(1,1) PRIMARY KEY, [Output] VARCHAR(50));

			IF @osver <> '5.2'
			BEGIN
				SELECT @CMD = N'powershell -NoLogo -NoProfile "Import-Module FailoverClusters"; "Get-ClusterNode | Format-Table -Autosize -HideTableHeaders NodeWeight"' 
				INSERT INTO #xp_cmdshell_CluNodesOutput ([Output])
				EXEC master.dbo.xp_cmdshell @CMD;
			END
				
			SELECT @CMD = N'powershell -NoLogo -NoProfile "Import-Module FailoverClusters"; "Get-ClusterQuorum | Format-Table -Autosize -HideTableHeaders QuorumType"' 
			INSERT INTO #xp_cmdshell_CluOutput ([Output])
			EXEC master.dbo.xp_cmdshell @CMD;
				
			IF (SELECT COUNT([Output]) FROM #xp_cmdshell_CluNodesOutput WHERE [Output] = '') > 0
			BEGIN				
				SELECT @CntNodes = COUNT(NodeName) FROM sys.dm_os_cluster_nodes (NOLOCK)
				
				SELECT 'Server_checks' AS [Category], 'Cluster_Quorum' AS [Check], 
					CASE WHEN REPLACE([Output], CHAR(9), '') = 'DiskOnly' AND @osver <> '5.2' THEN '[WARNING: The current quorum model is not recommended since WS2003]'
						WHEN REPLACE([Output], CHAR(9), '') = 'NodeAndDiskMajority' AND @CntNodes % 2 = 1 THEN '[WARNING: The current quorum model is not recommended for a cluster with ODD number of nodes]'
						WHEN REPLACE([Output], CHAR(9), '') = 'NodeMajority' AND @CntNodes % 2 = 0 THEN '[WARNING: The current quorum model is not recommended for a cluster with EVEN number of nodes]'
						WHEN REPLACE([Output], CHAR(9), '') = 'NodeAndFileShareMajority' THEN '[INFORMATION: The current quorum model is recommended for clusters with special configurations]'
						ELSE '[OK]' END AS [Deviation], 
					QUOTENAME(REPLACE([Output], CHAR(9), '')) AS QuorumModel,
					'[WARNING: No count of votes available, using count of nodes instead. Check if KB2494036 applies and is installed]' AS [Comment] -- http://support.microsoft.com/kb/2494036
				FROM #xp_cmdshell_CluOutput WHERE [Output] IS NOT NULL
			END
			ELSE
			BEGIN
				SELECT @CntVotes = SUM(CONVERT(int, [Output])) FROM #xp_cmdshell_CluNodesOutput WHERE [Output] IS NOT NULL

				IF EXISTS (SELECT TOP 1 [Output] FROM #xp_cmdshell_CluOutput WHERE [Output] LIKE '%Majority%' OR [Output] LIKE '%Disk%')
				BEGIN
					SELECT 'Server_checks' AS [Category], 'Cluster_Quorum' AS [Check], 
						CASE WHEN REPLACE([Output], CHAR(9), '') = 'DiskOnly' AND @osver <> '5.2' THEN '[WARNING: The current quorum model is not recommended since WS2003]'
							WHEN REPLACE([Output], CHAR(9), '') = 'NodeAndDiskMajority' AND @CntVotes % 2 = 1 THEN '[WARNING: The current quorum model is not recommended for a cluster with ODD number of node votes]'
							WHEN REPLACE([Output], CHAR(9), '') = 'NodeMajority' AND @CntVotes % 2 = 0 THEN '[WARNING: The current quorum model is not recommended for a cluster with EVEN number of node votes]'
							WHEN REPLACE([Output], CHAR(9), '') = 'NodeAndFileShareMajority' THEN '[INFORMATION: The current quorum model is recommended for clusters with special configurations]'
							ELSE '[OK]' END AS [Deviation], 
						QUOTENAME(REPLACE([Output], CHAR(9), '')) AS QuorumModel 
					FROM #xp_cmdshell_CluOutput WHERE [Output] IS NOT NULL 
				END
			END
			
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END
			
			
		END
		ELSE
		BEGIN
			RAISERROR('[WARNING: Only a sysadmin can run the "Cluster Quorum Model" check. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
			RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: xp_cmdshell. Bypassing check]', 16, 1, N'extended_sprocs')
			--RETURN
		END
	END
	ELSE IF @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted')) AND @psver = 1
	BEGIN
		RAISERROR('    |- [INFORMATION: "Cluster Quorum Model" check was skipped: cannot execute with PS v1]', 10, 1, N'disallow_ps')
		--RETURN
	END
	ELSE
	BEGIN
		RAISERROR('    |- [INFORMATION: "Cluster Quorum Model" check was skipped: either xp_cmdshell or execution of PS scripts was not allowed]', 10, 1, N'disallow_xp_cmdshell')
		--RETURN
	END
END
ELSE
BEGIN
	SELECT 'Server_checks' AS [Category], 'Cluster_Quorum' AS [Check], 'NOT_CLUSTERED' AS [Deviation]
END;

IF @IsHadrEnabled = 1
BEGIN
	SET @sqlcmd	= N'DECLARE @osver VARCHAR(5), @CntNodes tinyint
SELECT @osver = windows_release FROM sys.dm_os_windows_info (NOLOCK)	
SELECT @CntNodes = SUM(number_of_quorum_votes) FROM sys.dm_hadr_cluster_members (NOLOCK)

SELECT ''Server_checks'' AS [Category], ''AlwaysOn_Cluster_Quorum'' AS [Check], cluster_name,
	CASE WHEN quorum_type = 3 AND @osver <> ''5.2'' THEN ''[WARNING: The current quorum model is not recommended since WS2003]''
		WHEN quorum_type = 1 AND @CntNodes % 2 = 1 THEN ''[WARNING: The current quorum model is not recommended for a cluster with ODD number of nodes]''
		WHEN quorum_type = 0 AND @CntNodes % 2 = 0 THEN ''[WARNING: The current quorum model is not recommended for a cluster with EVEN number of nodes]''
		WHEN quorum_type = 2 THEN ''[INFORMATION: The current quorum model is recommended for clusters with special configurations]''
		ELSE ''[OK]'' END AS [Deviation], 
	QUOTENAME(quorum_type_desc) AS QuorumModel
FROM sys.dm_hadr_cluster;'

	EXECUTE sp_executesql @sqlcmd
END;

IF @sqlmajorver >= 13 AND @IsHadrEnabled = 1
BEGIN
	SET @sqlcmd	= N'IF EXISTS (SELECT 1 FROM sys.availability_groups where db_failover = 0) 
	SELECT ''Server_checks'' AS [Category], ''AlwaysOn_Replica_Cluster_Database_Health_Detection'' AS [Information], ''[INFORMATION: Consider enabling Database Health Detection]''
	SELECT ''Server_checks'' AS [Category], ''AlwaysOn_Replica_Cluster_Database_Health_Detection'' AS [Information], name, failure_condition_level, db_failover 
	FROM sys.availability_groups where db_failover = 0;'

	EXECUTE sp_executesql @sqlcmd
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Cluster NIC Binding order subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @allow_xpcmdshell = 1 and @clustered = 1
BEGIN
	RAISERROR (N'  |-Starting Cluster NIC Binding order', 10, 1) WITH NOWAIT
	IF @allow_xpcmdshell = 1 AND (@psavail IS NOT NULL AND @psavail IN ('RemoteSigned','Unrestricted'))
	BEGIN
		IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
				AND (SELECT COUNT(l.name)
				FROM sys.server_permissions p JOIN sys.server_principals l 
				ON p.grantee_principal_id = l.principal_id
					AND p.class = 100 -- Server
					AND p.state IN ('G', 'W') -- Granted or Granted with Grant
					AND l.is_disabled = 0
					AND p.permission_name = 'ALTER SETTINGS'
					AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0 AND
				(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') > 0)))
		BEGIN
			DECLARE @clunic int, @maxnic int

			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
			SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

			RAISERROR ('    |-Configuration options set for Cluster NIC Binding Order check', 10, 1) WITH NOWAIT
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
			END
		
			DECLARE @output_hw_nics TABLE ([PS_OUTPUT] VARCHAR(2048));
			DECLARE @output_hw_format_nics TABLE ([nicid] smallint, [nicname] VARCHAR(255) NULL)

			IF @custompath IS NULL
			BEGIN
				IF @sqlmajorver < 11
				BEGIN
					EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\Setup',N'SQLPath', @path OUTPUT
					SET @path = @path + '\LOG'
				END
				ELSE
				BEGIN
					SET @sqlcmd = N'SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations';
					SET @params = N'@pathOUT NVARCHAR(2048) OUTPUT';
					EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
				END

				-- Create COM object with FSO
				EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FSO OUT
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					EXEC @OLEResult = master.dbo.sp_OAMethod @FSO, 'FolderExists', @existout OUT, @path
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Calling FolderExists Method 0x%x, %s, %s'
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END
					ELSE
					BEGIN
						IF @existout <> 1
						BEGIN
							SET @path = CONVERT(NVARCHAR(500), SERVERPROPERTY('ErrorLogFileName'))
							SET @path = LEFT(@path,LEN(@path)-CHARINDEX('\', REVERSE(@path)))
						END 
					END
					EXEC @OLEResult = sp_OADestroy @FSO
				END
			END
			ELSE
			BEGIN
				SELECT @path = CASE WHEN @custompath LIKE '%\' THEN LEFT(@custompath, LEN(@custompath)-1) ELSE @custompath END
			END
			
			SET @FileName = @path + '\checkbp_nics_' + RTRIM(@server) + '.ps1'
				
			EXEC master.dbo.xp_fileexist @FileName, @existout out
			IF @existout = 0
			BEGIN -- Scan for nics
				SET @Text1 = '[string] $serverName = ''localhost''
$nics = Get-WmiObject -Computername $serverName -query "SELECT Description, Index FROM Win32_NetworkAdapterConfiguration"
foreach ($nic in $nics)
{
[string] $allnics = "{0};{1}" -f $nic.Index,$nic.Description
Write-Output $allnics
}
'
				EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FS OUT
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END

				--Open file
				EXEC @OLEResult = master.dbo.sp_OAMethod @FS, 'OpenTextFile', @FileID OUT, @FileName, 2, 1
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling OpenTextFile Method 0x%x, %s, %s' + CHAR(10) + 'Could not create file ' + @FileName
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END
				ELSE
				BEGIN
					SELECT @ErrorMessage = '    |-Created file ' + @FileName
					RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
				END

				--Write Text1
				EXEC @OLEResult = master.dbo.sp_OAMethod @FileID, 'WriteLine', NULL, @Text1
				IF @OLEResult <> 0
				BEGIN
					EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
					SELECT @ErrorMessage = 'Error Calling WriteLine Method 0x%x, %s, %s' + CHAR(10) + 'Could not write to file ' + @FileName
					RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
				END

				EXEC @OLEResult = sp_OADestroy @FileID
				EXEC @OLEResult = sp_OADestroy @FS
			END
			ELSE
			BEGIN
				SELECT @ErrorMessage = '    |-Reusing file ' + @FileName
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
			END
			
			IF @psver = 1
			BEGIN
				SET @CMD = 'powershell -NoLogo -NoProfile "' + @FileName + '" -ExecutionPolicy RemoteSigned'
			END
			ELSE
			BEGIN
				SET @CMD = 'powershell -NoLogo -NoProfile -File "' + @FileName + '" -ExecutionPolicy RemoteSigned'
			END;

			INSERT INTO @output_hw_nics
			EXEC master.dbo.xp_cmdshell @CMD
			
			SET @CMD = 'del /Q "' + @FileName + '"'
			EXEC master.dbo.xp_cmdshell @CMD, NO_OUTPUT
						
			INSERT INTO @output_hw_format_nics ([nicid],nicname)
			SELECT LEFT(RTRIM([PS_OUTPUT]), CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT]))-1 END),
					RIGHT(RTRIM([PS_OUTPUT]), LEN(RTRIM([PS_OUTPUT]))-CASE WHEN CHARINDEX(';', RTRIM([PS_OUTPUT])) = 0 THEN LEN(RTRIM([PS_OUTPUT])) ELSE CHARINDEX(';', RTRIM([PS_OUTPUT])) END)
			FROM @output_hw_nics
			WHERE [PS_OUTPUT] IS NOT NULL;
		
			SET @CMD2 = 'del ' + @FileName
			EXEC master.dbo.xp_cmdshell @CMD2, NO_OUTPUT;
			
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END;
			
			SELECT @maxnic = MAX(nicid) FROM @output_hw_format_nics;
			SELECT TOP 1 @clunic = nicid FROM @output_hw_format_nics WHERE nicname LIKE '%Cluster Virtual Adapter%';
		
			IF @clunic < @maxnic OR @clunic IS NULL --http://support2.microsoft.com/kb/955963
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Cluster_NIC_Binding' AS [Check], '[WARNING: The Microsoft Failover Cluster Virtual Adapter is not in the correct binding order. Should be the lowest of all present NICs]' AS [Deviation]
				SELECT 'Server_checks' AS [Category], 'Cluster_NIC_Binding' AS [Information], nicid AS NIC_ID, nicname AS NIC_Name
				FROM @output_hw_format_nics t1
				ORDER BY t1.[nicid]
				OPTION (RECOMPILE);
			END
			ELSE IF @clunic = @maxnic
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Cluster_NIC_Binding' AS [Check], '[OK]' AS [Deviation]
			END
			ELSE
			BEGIN
				SELECT 'Server_checks' AS [Category], 'Cluster_NIC_Binding' AS [Check], '[WARNING: Could not gather information on NIC binding order]' AS [Deviation]
			END;
		END
		ELSE
		BEGIN
			RAISERROR('[WARNING: Only a sysadmin can run the "Cluster NIC Binding Order" checks. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
			RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_cmdshell, xp_instance_regread, xp_regread, xp_fileexist and xp_regenumvalues. Bypassing check]', 16, 1, N'extended_sprocs')
			--RETURN
		END
		END
	ELSE
	BEGIN
		RAISERROR('    |- [INFORMATION: "Cluster NIC Binding Order" check was skipped: either xp_cmdshell or execution of PS scripts was not allowed.]', 10, 1, N'disallow_xp_cmdshell')
		--RETURN
	END
END
ELSE
BEGIN
	SELECT 'Server_checks' AS [Category], 'Cluster_NIC_Binding' AS [Check], 'NOT_CLUSTERED' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Cluster QFE node equality subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @clustered = 1
BEGIN
	RAISERROR (N'  |-Starting QFE node equality', 10, 1) WITH NOWAIT
	IF @allow_xpcmdshell = 1
	BEGIN
		IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0)) -- Is not sysadmin but proxy account exists
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0))
		BEGIN
			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'

			RAISERROR ('    |-Configuration options set for QFE node equality check', 10, 1) WITH NOWAIT
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END
			
			DECLARE /* @CMD NVARCHAR(4000), @line int, @linemax int, */ @Node VARCHAR(50)
				
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_Nodes'))
			DROP TABLE #xp_cmdshell_Nodes;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_Nodes'))
			CREATE TABLE #xp_cmdshell_Nodes (NodeName VARCHAR(50), isdone bit NOT NULL);
				
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEOutput'))
			DROP TABLE #xp_cmdshell_QFEOutput;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEOutput'))
			CREATE TABLE #xp_cmdshell_QFEOutput (line int IDENTITY(1,1) PRIMARY KEY, [Output] VARCHAR(150));
				
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEFinal'))
			DROP TABLE #xp_cmdshell_QFEFinal;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEFinal'))
			CREATE TABLE #xp_cmdshell_QFEFinal (NodeName VARCHAR(50), [QFE] VARCHAR(150));
				
			INSERT INTO #xp_cmdshell_Nodes
			SELECT NodeName, 0 FROM sys.dm_os_cluster_nodes (NOLOCK);
				
			WHILE (SELECT COUNT(NodeName) FROM #xp_cmdshell_Nodes WHERE isdone = 0) > 0
			BEGIN
				SELECT TOP 1 @Node = NodeName FROM #xp_cmdshell_Nodes WHERE isdone = 0;
					
				SET @CMD = 'wmic /node:"' + @Node + '" qfe get hotfixid' 
				INSERT INTO #xp_cmdshell_QFEOutput ([Output])
				EXEC master.dbo.xp_cmdshell @CMD;
					
				IF (SELECT COUNT([Output]) FROM #xp_cmdshell_QFEOutput WHERE [Output] LIKE '%Access is denied%') = 0
				BEGIN
					INSERT INTO #xp_cmdshell_QFEFinal
					SELECT @Node, RTRIM(REPLACE([Output],CHAR(13),'')) FROM #xp_cmdshell_QFEOutput WHERE RTRIM(REPLACE([Output],CHAR(13),'')) NOT IN ('','HotFixID');
				END
				ELSE
				BEGIN
					SET @ErrorMessage = '[WARNING: Access Denied error while trying to get updates from node ' + @Node + ']'
					RAISERROR (@ErrorMessage,16,1);
				END;
					
				TRUNCATE TABLE #xp_cmdshell_QFEOutput;

				UPDATE #xp_cmdshell_Nodes 
				SET isdone = 1
				WHERE NodeName = @Node;
			END;
				
			IF (SELECT COUNT(DISTINCT NodeName) FROM #xp_cmdshell_QFEFinal) = (SELECT COUNT(DISTINCT NodeName) FROM #xp_cmdshell_Nodes)
			BEGIN
				IF (SELECT COUNT(*) FROM #xp_cmdshell_QFEFinal t1 WHERE t1.[QFE] NOT IN (SELECT DISTINCT t2.[QFE] FROM #xp_cmdshell_QFEFinal t2 WHERE t2.NodeName <> t1.NodeName)) > 0
				BEGIN
					SELECT 'Server_checks' AS [Category], 'Cluster_QFE_Equality' AS [Check], '[WARNING: Missing updates found in some of the nodes]' AS [Deviation]
					SELECT t1.NodeName, t1.[QFE] AS MissingUpdates FROM #xp_cmdshell_QFEFinal t1
					WHERE t1.[QFE] NOT IN (SELECT DISTINCT t2.[QFE] FROM #xp_cmdshell_QFEFinal t2 WHERE t2.NodeName <> t1.NodeName);
				END
				ELSE
				BEGIN
					SELECT 'Server_checks' AS [Category], 'Cluster_QFE_Equality' AS [Check], '[OK]' AS [Deviation];
					SELECT DISTINCT t1.[QFE] AS InstalledUpdates FROM #xp_cmdshell_QFEFinal t1;
				END
			END
			ELSE
			BEGIN
				RAISERROR ('[WARNING: Could not collect data from all cluster nodes. Bypassing QFE node equality check]',16,1);
			END
			
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END
		END
		ELSE
		BEGIN
			RAISERROR('[WARNING: Only a sysadmin can run the "QFE node equality" check. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
			RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: xp_cmdshell. Bypassing check]', 16, 1, N'extended_sprocs')
			--RETURN
		END
	END
	ELSE
	BEGIN
		RAISERROR('  |- [INFORMATION: "QFE node equality" check was skipped because xp_cmdshell was not allowed.]', 10, 1, N'disallow_xp_cmdshell')
		--RETURN
	END
END
ELSE
BEGIN
	SELECT 'Server_checks' AS [Category], 'Cluster_QFE_Equality' AS [Check], 'NOT_CLUSTERED' AS [Deviation]
END;

RAISERROR (N'|-Starting Service Accounts Checks', 10, 1) WITH NOWAIT
--------------------------------------------------------------------------------------------------------------------------------
-- Service Accounts Status subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Service Accounts Status', 10, 1) WITH NOWAIT
IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) 
	OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') = 1 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_servicecontrol') = 1)
BEGIN
	DECLARE @rc int, @profile NVARCHAR(128)
	DECLARE @sqlservice NVARCHAR(128), @sqlagentservice NVARCHAR(128), @dtsservice NVARCHAR(128), @ftservice NVARCHAR(128)
	DECLARE @browservice NVARCHAR(128), @olapservice NVARCHAR(128), @rsservice NVARCHAR(128)
	DECLARE @statussqlservice NVARCHAR(20), @statussqlagentservice NVARCHAR(20), @statusdtsservice NVARCHAR(20), @statusftservice NVARCHAR(20)
	DECLARE @statusbrowservice NVARCHAR(20), @statusolapservice NVARCHAR(20), @statusrsservice NVARCHAR(20)
	DECLARE @regkeysqlservice NVARCHAR(256), @regkeysqlagentservice NVARCHAR(256), @regkeydtsservice NVARCHAR(256), @regkeyftservice NVARCHAR(256)
	DECLARE @regkeybrowservice NVARCHAR(256), @regkeyolapservice NVARCHAR(256), @regkeyrsservice NVARCHAR(256)
	DECLARE @accntsqlservice NVARCHAR(128), @accntsqlagentservice NVARCHAR(128), @accntdtsservice NVARCHAR(128), @accntftservice NVARCHAR(128)
	DECLARE @accntbrowservice NVARCHAR(128), @accntolapservice NVARCHAR(128), @accntrsservice NVARCHAR(128)

	-- Get service names
	IF (@instancename IS NULL) 
	BEGIN
		IF @sqlmajorver < 11
		BEGIN
			SELECT @sqlservice = N'MSSQLServer' 
			SELECT @sqlagentservice = N'SQLServerAgent'
		END
		SELECT @olapservice = N'MSSQLServerOLAPService' 
		SELECT @rsservice = N'ReportServer' 
	END 
	ELSE 
	BEGIN
		IF @sqlmajorver < 11
		BEGIN
			SELECT @sqlservice = N'MSSQL$' + @instancename
			SELECT @sqlagentservice = N'SQLAgent$' + @instancename
		END 
		SELECT @olapservice = N'MSOLAP$' + @instancename
		SELECT @rsservice = N'ReportServer$' + @instancename 
	END

	IF @sqlmajorver = 9
	BEGIN
		SELECT @dtsservice = N'MsDtsServer'
	END
	ELSE
	BEGIN
		SELECT @dtsservice = N'MsDtsServer' + CONVERT(VARCHAR, @sqlmajorver) + '0'
	END

	IF (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 1
	BEGIN
		IF (@instancename IS NULL) AND @sqlmajorver = 10
		BEGIN 
			SELECT @ftservice = N'MSSQLFDLauncher'
		END 
		ELSE IF (@instancename IS NOT NULL) AND @sqlmajorver = 10
		BEGIN 
			SELECT @ftservice = N'MSSQLFDLauncher$' + @instancename
		END
		ELSE IF (@instancename IS NULL) AND @sqlmajorver = 9
		BEGIN 
			SELECT @ftservice = N'msftesql'
		END
		ELSE IF (@instancename IS NOT NULL) AND @sqlmajorver = 9 
		BEGIN 
			SELECT @ftservice = N'msftesql$' + @instancename
		END
	END

	SELECT @browservice = N'SQLBrowser'

	IF @sqlmajorver < 11
	BEGIN
		SELECT @regkeysqlservice = N'SYSTEM\CurrentControlSet\Services\' + @sqlservice
		SELECT @regkeysqlagentservice = N'SYSTEM\CurrentControlSet\Services\' + @sqlagentservice
		IF (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 1
		BEGIN
			SELECT @regkeyftservice = N'SYSTEM\CurrentControlSet\Services\' + @ftservice
		END
	END
	SELECT @regkeyolapservice = N'SYSTEM\CurrentControlSet\Services\' + @olapservice
	SELECT @regkeyrsservice = N'SYSTEM\CurrentControlSet\Services\' + @rsservice
	SELECT @regkeydtsservice = N'SYSTEM\CurrentControlSet\Services\' + @dtsservice
	SELECT @regkeybrowservice = N'SYSTEM\CurrentControlSet\Services\' + @browservice
	
	-- Service status
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#RegResult'))
	CREATE TABLE #RegResult (ResultValue bit)
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#ServiceStatus'))
	CREATE TABLE #ServiceStatus (ServiceStatus VARCHAR(128))

	IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
	BEGIN
		BEGIN TRY
			INSERT INTO #RegResult (ResultValue)
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeysqlservice
			IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
			BEGIN
				INSERT INTO #ServiceStatus (ServiceStatus)
				EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @sqlservice
				SELECT @statussqlservice = ServiceStatus FROM #ServiceStatus
				TRUNCATE TABLE #ServiceStatus;
			END
			ELSE
			BEGIN
				SET @statussqlservice = 'Not Installed'
			END
			TRUNCATE TABLE #RegResult;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 1. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	ELSE
	BEGIN
		SET @sqlcmd = N'SELECT @statussqlserviceOUT = status_desc FROM sys.dm_server_services WHERE servicename LIKE ''SQL Server%'' AND servicename NOT LIKE ''SQL Server Agent%''';
		SET @params = N'@statussqlserviceOUT NVARCHAR(20) OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @statussqlserviceOUT=@statussqlservice OUTPUT;
		IF @statussqlservice IS NULL
		BEGIN
			SET @statussqlservice = 'Not Installed'
		END
	END

	IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
	BEGIN
		BEGIN TRY
			INSERT INTO #RegResult (ResultValue)
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeysqlagentservice
			IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
			BEGIN
				INSERT INTO #ServiceStatus (ServiceStatus)
				EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @sqlagentservice
				SELECT @statussqlagentservice = ServiceStatus FROM #ServiceStatus
				TRUNCATE TABLE #ServiceStatus;
			END
			ELSE
			BEGIN
				SET @statussqlagentservice = 'Not Installed'
			END
			TRUNCATE TABLE #RegResult;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 2. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	ELSE
	BEGIN
		SET @sqlcmd = N'SELECT @statussqlagentserviceOUT = status_desc FROM sys.dm_server_services WHERE servicename LIKE ''SQL Server Agent%''';
		SET @params = N'@statussqlagentserviceOUT NVARCHAR(20) OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @statussqlagentserviceOUT=@statussqlagentservice OUTPUT;
		IF @statussqlagentservice IS NULL
		BEGIN
			SET @statussqlagentservice = 'Not Installed'
		END
	END

	IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
	BEGIN
		IF (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 1
		BEGIN
			BEGIN TRY
				INSERT INTO #RegResult (ResultValue)
				EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyftservice
				IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
				BEGIN
					INSERT INTO #ServiceStatus (ServiceStatus)
					EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @ftservice
					SELECT @statusftservice = ServiceStatus FROM #ServiceStatus
					TRUNCATE TABLE #ServiceStatus;
				END
				ELSE
				BEGIN
					SET @statusftservice = '[INFORMATION: Service is not installed]'
				END
				TRUNCATE TABLE #RegResult;
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 3. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
		END
	END
	ELSE
	BEGIN
		SET @sqlcmd = N'SELECT @statusftserviceOUT = status_desc FROM sys.dm_server_services WHERE servicename LIKE ''SQL Full-text Filter Daemon Launcher%''';
		SET @params = N'@statusftserviceOUT NVARCHAR(20) OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @statusftserviceOUT=@statusftservice OUTPUT;
		IF @statusftservice IS NULL
		BEGIN
			SET @statusftservice = '[INFORMATION: Service is not installed]'
		END
	END

	BEGIN TRY
		INSERT INTO #RegResult (ResultValue)
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyolapservice
		IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
		BEGIN
			INSERT INTO #ServiceStatus (ServiceStatus)
			EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @olapservice
			SELECT @statusolapservice = ServiceStatus FROM #ServiceStatus
			TRUNCATE TABLE #ServiceStatus;
		END
		ELSE
		BEGIN
			SET @statusolapservice = 'Not Installed'
		END
		TRUNCATE TABLE #RegResult;
	END TRY
		BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 4. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH

	BEGIN TRY
		INSERT INTO #RegResult (ResultValue)
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyrsservice
		IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
		BEGIN
			INSERT INTO #ServiceStatus (ServiceStatus)
			EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @rsservice
			SELECT @statusrsservice = ServiceStatus FROM #ServiceStatus
			TRUNCATE TABLE #ServiceStatus;
		END
		ELSE
		BEGIN
			SET @statusrsservice = 'Not Installed'
		END
		TRUNCATE TABLE #RegResult;
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 5. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH

	BEGIN TRY
		INSERT INTO #RegResult (ResultValue)
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeydtsservice
		IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
		BEGIN
			INSERT INTO #ServiceStatus (ServiceStatus)
			EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @dtsservice
			SELECT @statusdtsservice = ServiceStatus FROM #ServiceStatus
			TRUNCATE TABLE #ServiceStatus;
		END
		ELSE
		BEGIN
			SET @statusdtsservice = 'Not Installed'
		END
		TRUNCATE TABLE #RegResult;
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 6. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH

	BEGIN TRY
		INSERT INTO #RegResult (ResultValue)
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeybrowservice
		IF (SELECT TOP 1 ResultValue FROM #RegResult) = 1 
		BEGIN
			INSERT INTO #ServiceStatus (ServiceStatus)
			EXEC master.sys.xp_servicecontrol N'QUERYSTATE', @browservice
			SELECT @statusbrowservice = ServiceStatus FROM #ServiceStatus
			TRUNCATE TABLE #ServiceStatus;
		END
		ELSE
		BEGIN
			SET @statusbrowservice = 'Not Installed'
		END
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 7. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH

	DROP TABLE #RegResult;
	DROP TABLE #ServiceStatus;

	-- Accounts
	IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500)
	BEGIN
		BEGIN TRY
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeysqlservice, N'ObjectName', @accntsqlservice OUTPUT, NO_OUTPUT
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeysqlagentservice, N'ObjectName', @accntsqlagentservice OUTPUT, NO_OUTPUT
			EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyftservice, N'ObjectName', @accntftservice OUTPUT, NO_OUTPUT
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 8. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	ELSE
	BEGIN
		BEGIN TRY
			SET @sqlcmd = N'SELECT @accntsqlserviceOUT = service_account FROM sys.dm_server_services WHERE servicename LIKE ''SQL Server%'' AND servicename NOT LIKE ''SQL Server Agent%''';
			SET @params = N'@accntsqlserviceOUT NVARCHAR(128) OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @accntsqlserviceOUT=@accntsqlservice OUTPUT;
			SET @sqlcmd = N'SELECT @accntsqlagentserviceOUT = service_account FROM sys.dm_server_services WHERE servicename LIKE ''SQL Server Agent%''';
			SET @params = N'@accntsqlagentserviceOUT NVARCHAR(128) OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @accntsqlagentserviceOUT=@accntsqlagentservice OUTPUT;
			SET @sqlcmd = N'SELECT @accntftserviceOUT = service_account FROM sys.dm_server_services WHERE servicename LIKE ''SQL Full-text Filter Daemon Launcher%''';
			SET @params = N'@accntftserviceOUT NVARCHAR(128) OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @accntftserviceOUT=@accntftservice OUTPUT;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 9. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	
	BEGIN TRY
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyolapservice, N'ObjectName', @accntolapservice OUTPUT, NO_OUTPUT
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeyrsservice, N'ObjectName', @accntrsservice OUTPUT, NO_OUTPUT
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeydtsservice, N'ObjectName', @accntdtsservice OUTPUT, NO_OUTPUT
		EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @regkeybrowservice, N'ObjectName', @accntbrowservice OUTPUT, NO_OUTPUT
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Service Accounts and Status subsection - Error raised in TRY block 10. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
	
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server' AS [Service], @statussqlservice AS [Status], @accntsqlservice AS [Account],
		CASE WHEN @statussqlservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statussqlservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
			WHEN @accntsqlservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntsqlservice = 'NT AUTHORITY\LOCALSERVICE' THEN '[WARNING: Running SQL Server under this account is not supported]'
			WHEN @clustered = 1 AND @accntsqlservice = 'NT AUTHORITY\SYSTEM' THEN '[WARNING: Running SQL Server under this account is not supported]' 
			WHEN @clustered = 1 AND @accntsqlservice = 'LocalSystem' THEN '[WARNING: Running SQL Server under this account is not supported]' 
			WHEN @clustered = 1 AND @accntsqlservice = 'NT AUTHORITY\NETWORKSERVICE' THEN '[WARNING: Running SQL Server under this account is not supported]' 
			WHEN @clustered = 0 AND @accntsqlservice = 'NT AUTHORITY\SYSTEM' THEN '[WARNING: Running SQL Server under this account is not recommended]' 
			WHEN @clustered = 0 AND @accntsqlservice = 'LocalSystem' THEN '[WARNING: Running SQL Server under this account is not recommended]' 
			WHEN @clustered = 0 AND @accntsqlservice = 'NT AUTHORITY\NETWORKSERVICE' THEN '[WARNING: Running SQL Server under this account is not recommended]'
			-- MSA for WS2008R2 or higher, SQL Server 2012 or higher, non-clustered (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
			WHEN @clustered = 0 AND @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntsqlservice <> 'NT SERVICE\MSSQLSERVER' AND @accntsqlservice NOT LIKE 'NT SERVICE\MSSQL$%' THEN '[INFORMATION: SQL Server is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server_Agent' AS [Service], @statussqlagentservice AS [Status], @accntsqlagentservice AS [Account],
		CASE WHEN @statussqlagentservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statussqlagentservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
			WHEN @accntsqlagentservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntsqlagentservice = 'NT AUTHORITY\LOCALSERVICE' THEN '[WARNING: Running SQL Server Agent under this account is not supported]'
			WHEN @accntsqlagentservice = @accntsqlservice THEN '[WARNING: Running SQL Server Agent under the same account as SQL Server is not recommended]' 
			WHEN @clustered = 1 AND @accntsqlagentservice = 'NT AUTHORITY\SYSTEM' THEN '[WARNING: Running SQL Server Agent under this account is not supported]' 
			WHEN @clustered = 1 AND @accntsqlagentservice = 'NT AUTHORITY\NETWORKSERVICE' THEN '[WARNING: Running SQL Server Agent under this account is not supported]' 
			WHEN @clustered = 0 AND @accntsqlagentservice = 'NT AUTHORITY\SYSTEM' THEN '[WARNING: Running SQL Server Agent under this account is not recommended]' 
			WHEN @clustered = 0 AND @accntsqlagentservice = 'NT AUTHORITY\NETWORKSERVICE' THEN '[WARNING: Running SQL Server Agent under this account is not recommended]' 
			WHEN @osver IS NULL THEN '[WARNING: Could not determine Windows version for check]'
			-- MSA for WS2008R2 or higher, SQL Server 2012 or higher, non-clustered (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
			WHEN @clustered = 0 AND @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntsqlagentservice <> 'NT SERVICE\SQLSERVERAGENT' AND @accntsqlagentservice NOT LIKE 'NT SERVICE\SQLAGENT$%' THEN '[INFORMATION: SQL Server Agent is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server_Analysis_Services' AS [Service], @statusolapservice AS [Status], @accntolapservice AS [Account],
		CASE WHEN @statusolapservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statusolapservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
			WHEN @accntolapservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntolapservice = @accntsqlservice THEN '[WARNING: Running SQL Server Analysis Services under the same account as SQL Server is not recommended]' 
			WHEN @clustered = 0 AND @sqlmajorver <= 10 AND @accntolapservice <> 'NT AUTHORITY\NETWORKSERVICE' AND @accntdtsservice <> 'NT AUTHORITY\LOCALSERVICE' THEN '[INFORMATION: SQL Server Analysis Services is not running with the default account]'
			WHEN @osver IS NULL THEN '[WARNING: Could not determine Windows version for check]'
			WHEN @clustered = 0 AND @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) <= 6.0 AND @accntolapservice <> 'NT AUTHORITY\NETWORKSERVICE' THEN '[INFORMATION: SQL Server Analysis Services is not running with the default account]'
			-- MSA for WS2008R2 or higher, SQL Server 2005 or higher, non-clustered (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
			WHEN @clustered = 0 AND @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntolapservice <> 'NT SERVICE\MSSQLServerOLAPService' AND @accntolapservice NOT LIKE 'NT SERVICE\MSOLAP$%' THEN '[INFORMATION: SQL Server Analysis Services is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server_Integration_Services' AS [Service], @statusdtsservice AS [Status], @accntdtsservice AS [Account],
		CASE WHEN @statusdtsservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statusdtsservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
			WHEN @accntdtsservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntdtsservice = @accntsqlservice THEN '[WARNING: Running SQL Server Integration Services under the same account as SQL Server is not recommended]' 
			WHEN @osver IS NULL THEN '[WARNING: Could not determine Windows version for check]'
			WHEN CONVERT(DECIMAL(3,1), @osver) <= 6.0 AND @accntdtsservice <> 'NT AUTHORITY\NETWORKSERVICE' AND @accntdtsservice <> 'NT AUTHORITY\LOCALSYSTEM' THEN '[INFORMATION: SQL Server Integration Services is not running with the default account]'
			-- MSA for WS2008R2 or higher, SQL Server 2012 or higher (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
			WHEN @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntdtsservice NOT IN ('NT SERVICE\MSDTSSERVER100', 'NT SERVICE\MSDTSSERVER110') THEN '[INFORMATION: SQL Server Integration Services is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server_Reporting_Services' AS [Service], @statusrsservice AS [Status], @accntrsservice AS [Account],
		CASE WHEN @statusrsservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statusrsservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
			WHEN @accntrsservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntrsservice = @accntsqlservice THEN '[WARNING: Running SQL Server Reporting Services under the same account as SQL Server is not recommended]' 
			WHEN @clustered = 0 AND @sqlmajorver <= 10 AND @accntrsservice <> 'NT AUTHORITY\NETWORKSERVICE' AND @accntdtsservice <> 'NT AUTHORITY\LOCALSYSTEM' THEN '[INFORMATION: SQL Server Reporting Services is not running with the default account]'
			WHEN @osver IS NULL THEN '[WARNING: Could not determine Windows version for check]'
			WHEN @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) <= 6.0 AND @accntrsservice <> 'NT AUTHORITY\NETWORKSERVICE' THEN '[INFORMATION: SQL Server Reporting Services is not running with the default account]'
			-- MSA for WS2008R2 or higher, SQL Server 2012 or higher (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
			WHEN @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntrsservice <> 'NT SERVICE\ReportServer' AND @accntrsservice NOT LIKE 'NT SERVICE\ReportServer$%' THEN '[INFORMATION: SQL Server Reporting Services is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'Full-Text' AS [Service], ISNULL(@statusftservice, 'Not Installed') AS [Status], ISNULL(@accntftservice,'') AS [Account], 
		CASE WHEN (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 1 THEN 
			CASE WHEN @statusftservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
				WHEN @statusftservice LIKE 'Stopped%' THEN '[WARNING: Service is stopped]'
				WHEN @accntftservice IS NULL THEN '[WARNING: Could not detect account for check]' 
				WHEN @accntftservice = @accntsqlservice THEN '[WARNING: Running Full-Text Daemon under the same account as SQL Server is not recommended]' 
				WHEN @accntftservice = 'NT AUTHORITY\SYSTEM' THEN '[WARNING: Running Full-Text Service under this account is not recommended]' 
				WHEN @osver IS NULL THEN '[WARNING: Could not determine Windows version for check]'
				WHEN @sqlmajorver <= 10 AND @accntftservice = 'NT AUTHORITY\NETWORKSERVICE' THEN '[WARNING: Running Full-Text Service under this account is not recommended]' 
				WHEN @sqlmajorver <= 10 AND @accntftservice <> 'NT AUTHORITY\LOCALSERVICE' THEN '[WARNING: Full-Text Daemon is not running with the default account]'
				WHEN @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) <= 6.0 AND @accntftservice <> 'NT AUTHORITY\LOCALSERVICE' THEN '[WARNING: Full-Text Daemon is not running with the default account]'
				-- MSA for WS2008R2 or higher, SQL Server 2012 or higher (https://docs.microsoft.com/previous-versions/sql/sql-server-2012/ms143504(v=sql.110)#Default_Accts))
				WHEN @sqlmajorver >= 11 AND CONVERT(DECIMAL(3,1), @osver) >= 6.1 AND @accntftservice <> 'NT SERVICE\MSSQLFDLauncher' AND @accntftservice NOT LIKE 'NT SERVICE\MSSQLFDLauncher$%' THEN '[WARNING: Full-Text Daemon is not running with the default account]'
			ELSE '[OK]' END 
		ELSE '[INFORMATION: Service is not installed]' 
		END AS [Deviation]
	UNION ALL
	SELECT 'Service_Account_checks' AS [Category], 'Service_Status' AS [Check], 'SQL_Server_Browser' AS [Service], @statusbrowservice AS [Status], @accntbrowservice AS [Account],
		CASE WHEN @statusbrowservice = 'Not Installed' THEN '[INFORMATION: Service is not installed]'
			WHEN @statusbrowservice LIKE 'Stopped%' AND @instancename IS NOT NULL THEN '[WARNING: Service is stopped on a named instance]'
			WHEN @statusbrowservice LIKE 'Stopped%' AND @instancename IS NULL THEN '[WARNING: Service is stopped]'
			WHEN @accntbrowservice IS NULL THEN '[WARNING: Could not detect account for check]' 
			WHEN @accntbrowservice = @accntsqlservice THEN '[WARNING: Running SQL Server Browser under the same account as SQL Server is not recommended]' 
			WHEN @accntbrowservice <> 'NT AUTHORITY\LOCALSERVICE' THEN '[WARNING: SQL Server Browser is not running with the default account]'
			ELSE '[OK]' 
		END AS [Deviation];
END
ELSE
BEGIN
	RAISERROR('[WARNING: Only a sysadmin can run the "Service Accounts Status" checks. Otherwise, you must be a granted EXECUTE permissions on xp_regread and xp_servicecontrol. Bypassing check]', 16, 1, N'sysadmin')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Service Accounts and SPN registration subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Service Accounts and SPN registration', 10, 1) WITH NOWAIT
IF @accntsqlservice IS NOT NULL AND @accntsqlservice NOT IN ('NT AUTHORITY\LOCALSERVICE','NT AUTHORITY\SYSTEM','LocalSystem','NT AUTHORITY\NETWORKSERVICE') AND @allow_xpcmdshell = 1 AND @spn_check = 1
BEGIN
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0)) -- Is not sysadmin but proxy account exists
		OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
			AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0))
	BEGIN
		RAISERROR ('    |-Configuration options set for SPN check', 10, 1) WITH NOWAIT
		SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
		SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
		END
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
		END

		BEGIN TRY
			DECLARE /*@CMD NVARCHAR(4000),*/ @line int, @linemax int, @SPN VARCHAR(8000), @SPNMachine VARCHAR(8000)
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_AcctSPNoutput'))
			DROP TABLE #xp_cmdshell_AcctSPNoutput;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_AcctSPNoutput'))
			CREATE TABLE #xp_cmdshell_AcctSPNoutput (line int IDENTITY(1,1) PRIMARY KEY, [Output] VARCHAR (8000));
			
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_DupSPNoutput'))
			DROP TABLE #xp_cmdshell_DupSPNoutput;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_DupSPNoutput'))
			CREATE TABLE #xp_cmdshell_DupSPNoutput (line int IDENTITY(1,1) PRIMARY KEY, [Output] VARCHAR (8000));
			
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#FinalDupSPN'))
			DROP TABLE #FinalDupSPN;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#FinalDupSPN'))
			CREATE TABLE #FinalDupSPN ([SPN] VARCHAR (8000), [Accounts] VARCHAR (8000));
			
			IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#ScopedDupSPN'))
			DROP TABLE #ScopedDupSPN;
			IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#ScopedDupSPN'))
			CREATE TABLE #ScopedDupSPN ([SPN] VARCHAR (8000), [Accounts] VARCHAR (8000));

			SELECT @CMD = N'SETSPN -P -L ' + @accntsqlservice 
			INSERT INTO #xp_cmdshell_AcctSPNoutput ([Output])
			EXEC master.dbo.xp_cmdshell @CMD;

			SET @CMD = N'SETSPN -P -X'
			INSERT INTO #xp_cmdshell_DupSPNoutput ([Output])
			EXEC master.dbo.xp_cmdshell @CMD;

			SELECT @SPNMachine = '%MSSQLSvc/' + CONVERT(NVARCHAR(100),SERVERPROPERTY('MachineName')) + '%';

			IF EXISTS (SELECT TOP 1 b.line FROM #xp_cmdshell_AcctSPNoutput a INNER JOIN #xp_cmdshell_DupSPNoutput b ON REPLACE(UPPER(a.[Output]),CHAR(9), '') = LEFT(REPLACE(UPPER(b.[Output]),CHAR(9), ''), LEN(REPLACE(UPPER(a.[Output]),' ', ''))))
			BEGIN
				DECLARE curSPN CURSOR FAST_FORWARD FOR SELECT b.line, REPLACE(a.[Output], CHAR(9), '') FROM #xp_cmdshell_AcctSPNoutput a INNER JOIN #xp_cmdshell_DupSPNoutput b ON REPLACE(UPPER(a.[Output]),CHAR(9), '') = LEFT(REPLACE(UPPER(b.[Output]),CHAR(9), ''), LEN(REPLACE(UPPER(a.[Output]),' ', ''))) WHERE a.[Output] LIKE '%MSSQLSvc%'
				OPEN curSPN
				FETCH NEXT FROM curSPN INTO @line, @SPN

				WHILE @@FETCH_STATUS = 0
				BEGIN
					SELECT TOP 1 @linemax = line FROM #xp_cmdshell_DupSPNoutput WHERE line > @line AND [Output] IS NULL;
					INSERT INTO #FinalDupSPN
					SELECT QUOTENAME(@SPN), QUOTENAME(REPLACE([Output], CHAR(9), '')) FROM #xp_cmdshell_DupSPNoutput WHERE line > @line AND line < @linemax;
				
					IF EXISTS (SELECT [Output] FROM #xp_cmdshell_DupSPNoutput WHERE line = @line AND [Output] LIKE @SPNMachine)
					BEGIN
						INSERT INTO #ScopedDupSPN
						SELECT QUOTENAME(@SPN), QUOTENAME(REPLACE([Output], CHAR(9), '')) FROM #xp_cmdshell_DupSPNoutput WHERE line > @line AND line < @linemax;
					END
					FETCH NEXT FROM curSPN INTO @line, @SPN
				END

				CLOSE curSPN
				DEALLOCATE curSPN
			END

			IF EXISTS (SELECT TOP 1 [Output] FROM #xp_cmdshell_AcctSPNoutput WHERE [Output] LIKE '%MSSQLSvc%')
			BEGIN				
				IF EXISTS (SELECT [Output] FROM #xp_cmdshell_AcctSPNoutput WHERE [Output] LIKE '%MSSQLSvc%' AND [Output] LIKE @SPNMachine)
				BEGIN
					SELECT 'Service_Account_checks' AS [Category], 'MSSQLSvc_SPNs_SvcAcct_CurrServer' AS [Check], '[OK]' AS [Deviation], QUOTENAME(REPLACE([Output], CHAR(9), '')) AS SPN FROM #xp_cmdshell_AcctSPNoutput WHERE [Output] LIKE @SPNMachine
				END
				ELSE
				BEGIN
					SELECT 'Service_Account_checks' AS [Category], 'MSSQLSvc_SPNs_SvcAcct_CurrServer' AS [Check], '[WARNING: There is no registered MSSQLSvc SPN for the current service account in the scoped server name, preventing the use of Kerberos authentication]' AS [Deviation];
				END

				IF EXISTS (SELECT [Output] FROM #xp_cmdshell_AcctSPNoutput WHERE [Output] LIKE '%MSSQLSvc%' AND [Output] NOT LIKE @SPNMachine)
				BEGIN
					SELECT 'Service_Account_checks' AS [Category], 'MSSQLSvc_SPNs_SvcAcct' AS [Check], '[INFORMATION: There are other MSSQLSvc SPNs registered for the current service account]' AS [Deviation], QUOTENAME(REPLACE([Output], CHAR(9), '')) AS SPN FROM #xp_cmdshell_AcctSPNoutput WHERE [Output] LIKE '%MSSQLSvc%' AND [Output] NOT LIKE @SPNMachine
				END
			END
			ELSE
			BEGIN
				SELECT 'Service_Account_checks' AS [Category], 'MSSQLSvc_SPNs_SvcAcct' AS [Check], '[WARNING: There is no registered MSSQLSvc SPN for the current service account, preventing the use of Kerberos authentication]' AS [Deviation];
			END

			IF (SELECT COUNT(*) FROM #ScopedDupSPN) > 0
			BEGIN
				SELECT 'Service_Account_checks' AS [Category], 'Dup_MSSQLSvc_SPNs_Acct_CurrServer' AS [Check], '[WARNING: There are duplicate registered MSSQLSvc SPNs in the domain, for the SPN in the scoped server name]' AS [Deviation], REPLACE([SPN], CHAR(9), ''), [Accounts] AS [Information] FROM #ScopedDupSPN
			END
			ELSE
			BEGIN
				SELECT 'Service_Account_checks' AS [Category], 'Dup_MSSQLSvc_SPNs_Acct_CurrServer' AS [Check], '[OK]' AS [Deviation];
			END

			IF (SELECT COUNT(*) FROM #FinalDupSPN) > 0
			BEGIN
				SELECT 'Service_Account_checks' AS [Category], 'Dup_MSSQLSvc_SPNs_Acct' AS [Check], '[WARNING: There are duplicate registered MSSQLSvc SPNs in the domain]' AS [Deviation], [SPN], [Accounts] FROM #FinalDupSPN
			END
			ELSE
			BEGIN
				SELECT 'Service_Account_checks' AS [Category], 'Dup_MSSQLSvc_SPNs_Acct' AS [Check], '[OK]' AS [Deviation];
			END
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Service Accounts and SPN registration subsection - Error raised in TRY block 9. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		
		IF @xcmd = 0
		BEGIN
			EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
		END
		IF @sao = 0
		BEGIN
			EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
		END
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Only a sysadmin can run the "Service Accounts and SPN registration" check. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
		RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: xp_cmdshell. Bypassing check]', 16, 1, N'extended_sprocs')
		--RETURN
	END
END
ELSE
BEGIN
	RAISERROR('    |- [INFORMATION: "Service Accounts and SPN registration" check was skipped: either spn checks were not allowed, xp_cmdshell was not allowed or the service account is not a domain account.]', 10, 1, N'disallow_xp_cmdshell')
	--RETURN
END;

RAISERROR (N'|-Starting Instance Checks', 10, 1) WITH NOWAIT
--------------------------------------------------------------------------------------------------------------------------------
-- Recommended build check subsection
--------------------------------------------------------------------------------------------------------------------------------
/*
RAISERROR (N'  |-Starting Recommended build check', 10, 1) WITH NOWAIT
SELECT 'Instance_checks' AS [Category], 'Recommended_Build' AS [Check],
	CASE WHEN (@sqlmajorver = 9 AND @sqlbuild < 5000)
			OR (@sqlmajorver = 10 AND @sqlminorver = 0 AND @sqlbuild < 6000)
			OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild < 6000)
			OR (@sqlmajorver = 11 AND @sqlbuild < 7001)
			OR (@sqlmajorver = 12 AND @sqlbuild < 5000)
			OR (@sqlmajorver = 13 AND @sqlbuild < 4000)
		THEN '[WARNING: current service pack has been superseded in the current SQL Server version. Install the latest service pack as soon as possible.]'
		ELSE '[OK]'
	END AS [Deviation], 
	CASE WHEN @sqlmajorver = 9 THEN '2005'
		WHEN @sqlmajorver = 10 AND @sqlminorver = 0 THEN '2008'
		WHEN @sqlmajorver = 10 AND @sqlminorver = 50 THEN '2008R2'
		WHEN @sqlmajorver = 11 THEN '2012'
		WHEN @sqlmajorver = 12 THEN '2014'
		WHEN @sqlmajorver = 13 THEN '2016'
		WHEN @sqlmajorver = 14 THEN '2017'
		WHEN @sqlmajorver = 15 THEN '2019'
	END AS [Product_Major_Version],
	CONVERT(VARCHAR(128), SERVERPROPERTY('ProductLevel')) AS Product_Level,
	CASE WHEN @sqlmajorver >= 13 OR (@sqlmajorver = 12 AND @sqlbuild >= 2556 AND @sqlbuild < 4100) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427) THEN CONVERT(VARCHAR(128), SERVERPROPERTY('ProductBuildType')) ELSE 'NA' END AS Product_Build_Type,
	CASE WHEN @sqlmajorver >= 13 OR (@sqlmajorver = 12 AND @sqlbuild >= 2556 AND @sqlbuild < 4100) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427) THEN CONVERT(VARCHAR(128), SERVERPROPERTY('ProductUpdateLevel')) ELSE 'NA' END AS Product_Update_Level,
	CASE WHEN @sqlmajorver >= 13 OR (@sqlmajorver = 12 AND @sqlbuild >= 2556 AND @sqlbuild < 4100) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427) THEN CONVERT(VARCHAR(128), SERVERPROPERTY('ProductUpdateReference')) ELSE 'NA' END AS Product_Update_Ref_KB;
*/

--------------------------------------------------------------------------------------------------------------------------------
-- Backup checks subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Backup checks', 10, 1) WITH NOWAIT
DECLARE @nolog int, @nobck int, @nolog24h int, @neverlog int, @neverbck int

-- No Full backups
SELECT @neverbck = COUNT(DISTINCT d.name) 
FROM master.sys.databases d (NOLOCK)
INNER JOIN #tmpdbs_userchoice tuc ON d.database_id = tuc.[dbid]
WHERE database_id NOT IN (2,3)
	AND source_database_id IS NULL -- no snapshots
	AND d.name NOT IN (SELECT b.database_name FROM msdb.dbo.backupset b WHERE b.type = 'D' AND b.is_copy_only = 0) -- Full backup and no COPY_ONLY backups

-- No Full backups in last 7 days
;WITH cteFullBcks (cnt) AS (SELECT DISTINCT database_name AS cnt
FROM msdb.dbo.backupset b (NOLOCK)
INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
WHERE b.type = 'D' -- Full backup
	AND b.is_copy_only = 0 -- No COPY_ONLY backups
	AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
		WHERE database_id NOT IN (2,3)
			AND source_database_id IS NULL) -- no snapshots
GROUP BY database_name
HAVING MAX(backup_finish_date) <= DATEADD(dd, -7, DATEADD(dd, DATEDIFF(dd, 0, GETDATE()) + 1, 0)))
SELECT @nobck = COUNT(cnt)
FROM cteFullBcks;

-- Last Log backup precedes last full or diff backup, and DB in Full or Bulk-logged RM
;WITH cteLogBcks (cnt) AS (SELECT DISTINCT database_name 
FROM msdb.dbo.backupset b (NOLOCK)
INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
WHERE b.type = 'L' -- Log backup
	AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
		WHERE database_id NOT IN (2,3)
			AND source_database_id IS NULL -- no snapshots
			AND recovery_model < 3) -- not SIMPLE recovery model
GROUP BY [database_name]
HAVING MAX(backup_finish_date) < (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset c (NOLOCK) WHERE c.type IN ('D','I') -- Full or Differential backup
								AND c.is_copy_only = 0 -- No COPY_ONLY backups
								AND c.database_name = b.database_name))
SELECT @nolog = COUNT(cnt)
FROM cteLogBcks;

-- No Log backup since last full or diff backup, and DB in Full or Bulk-logged RM
SELECT @neverlog = COUNT(DISTINCT database_name)
FROM msdb.dbo.backupset b (NOLOCK)
INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
WHERE database_name IN (SELECT name 
			FROM master.sys.databases (NOLOCK)
			WHERE database_id NOT IN (2,3)
				AND source_database_id IS NULL -- no snapshots
				AND recovery_model < 3) -- not SIMPLE recovery model
	AND EXISTS (SELECT DISTINCT database_name 
			FROM msdb.dbo.backupset c (NOLOCK)
			WHERE c.type IN ('D','I') -- Full or Differential backup
			AND c.is_copy_only = 0 -- No COPY_ONLY backups
			AND c.database_name = b.database_name) -- Log backup
	AND NOT EXISTS (SELECT DISTINCT database_name 
			FROM msdb.dbo.backupset c (NOLOCK)
			WHERE c.type = 'L' -- Log Backup
			AND c.database_name = b.database_name);

-- Log backup since last full or diff backup is older than 24h, and DB in Full ar Bulk-logged RM
;WITH cteLogBcks2 (cnt) AS (SELECT DISTINCT database_name 
FROM msdb.dbo.backupset b (NOLOCK)
INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
WHERE b.type = 'L' -- Log backup
	AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
		WHERE database_id NOT IN (2,3)
			AND source_database_id IS NULL -- no snapshots
			AND recovery_model < 3) -- not SIMPLE recovery model
GROUP BY database_name
HAVING MAX(backup_finish_date) > (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset c (NOLOCK) WHERE c.type IN ('D','I') -- Full or Differential backup
								AND c.is_copy_only = 0 -- No COPY_ONLY backups
								AND c.database_name = b.database_name)
	AND MAX(backup_finish_date) <= DATEADD(hh, -24, GETDATE()))
SELECT @nolog24h = COUNT(cnt)
FROM cteLogBcks2;

IF @nobck > 0 OR @neverbck > 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'No_Full_Backups' AS [Check], '[WARNING: Some databases do not have any Full backups, or the last Full backup is over 7 days]' AS [Deviation]
	-- No full backups in last 7 days
	SELECT DISTINCT 'Instance_checks' AS [Category], 'No_Full_Backups' AS [Information], database_name AS [Database_Name], MAX(backup_finish_date) AS Lst_Full_Backup
	FROM msdb.dbo.backupset b (NOLOCK)
	INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
	WHERE b.type = 'D' -- Full backup
		AND b.is_copy_only = 0 -- No COPY_ONLY backups
		AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
			WHERE database_id NOT IN (2,3)
				AND source_database_id IS NULL) -- no snapshots
	GROUP BY database_name
	HAVING MAX(backup_finish_date) <= DATEADD(dd, -7, DATEADD(dd, DATEDIFF(dd, 0, GETDATE()) + 1, 0))
	UNION ALL
	-- No full backups in history
	SELECT DISTINCT 'Instance_checks' AS [Category], 'No_Full_Backups' AS [Information], d.name AS [Database_Name], NULL AS Lst_Full_Backup
	FROM master.sys.databases d (NOLOCK)
	INNER JOIN #tmpdbs_userchoice tuc ON d.database_id = tuc.[dbid]
	WHERE database_id NOT IN (2,3)
		AND source_database_id IS NULL -- no snapshots
		AND recovery_model < 3 -- not SIMPLE recovery model
		AND d.name NOT IN (SELECT b.database_name FROM msdb.dbo.backupset b WHERE b.type = 'D' AND b.is_copy_only = 0) -- Full backup and no COPY_ONLY backups
		AND d.name NOT IN (SELECT b.database_name FROM msdb.dbo.backupset b WHERE b.type = 'L') -- Log backup
	ORDER BY [Database_Name]
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'No_Full_Backups' AS [Check], '[OK]' AS [Deviation]
END;

IF @nolog > 0 OR @neverlog > 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'No_Log_Bcks_since_LstFullorDiff' AS [Check], '[WARNING: Some databases in Full or Bulk-Logged recovery model do not have any corresponding transaction Log backups since the last Full or Differential backup]' AS [Deviation]
	;WITH Bck AS (SELECT database_name, MAX(backup_finish_date) AS backup_finish_date
					FROM msdb.dbo.backupset (NOLOCK) b
					INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
					WHERE [type] IN ('D','I') -- Full or Differential backup
					GROUP BY database_name)
	-- Log backups since last full or diff is older than 24h
	SELECT DISTINCT 'Instance_checks' AS [Category], 'No_Log_Bcks_since_LstFullorDiff' AS [Information], database_name AS [Database_Name], MAX(backup_finish_date) AS Lst_Log_Backup,
		(SELECT backup_finish_date FROM Bck c WHERE c.database_name = b.database_name) AS Lst_FullDiff_Backup
	FROM msdb.dbo.backupset b (NOLOCK)
	INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
	WHERE b.type = 'L' -- Log backup
		AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
			WHERE database_id NOT IN (2,3)
				AND source_database_id IS NULL -- no snapshots
				AND recovery_model < 3) -- not SIMPLE recovery model
	GROUP BY [database_name]
	HAVING MAX(backup_finish_date) < (SELECT backup_finish_date FROM Bck c WHERE c.database_name = b.database_name)
	UNION ALL
	-- No log backup in history but full backup exists
	SELECT DISTINCT 'Instance_checks' AS [Category], 'No_Log_Bcks_since_LstFullorDiff' AS [Information], database_name AS [Database_Name], NULL AS Lst_Log_Backup, MAX(backup_finish_date) AS Lst_FullDiff_Backup
	FROM msdb.dbo.backupset b (NOLOCK)
	INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
	WHERE database_name IN (SELECT name 
				FROM master.sys.databases (NOLOCK)
				WHERE database_id NOT IN (2,3)
					AND source_database_id IS NULL -- no snapshots
					AND recovery_model < 3) -- not SIMPLE recovery model
		AND EXISTS (SELECT DISTINCT database_name 
				FROM msdb.dbo.backupset c (NOLOCK)
				WHERE c.type IN ('D','I') -- Full or Differential backup
				AND c.is_copy_only = 0 -- No COPY_ONLY backups
				AND c.database_name = b.database_name) -- Log backup
		AND NOT EXISTS (SELECT DISTINCT database_name 
				FROM msdb.dbo.backupset c (NOLOCK)
				WHERE c.type = 'L' -- Log Backup
				AND c.database_name = b.database_name)
	GROUP BY database_name
	ORDER BY database_name;
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'No_Log_Bcks_since_LstFullorDiff' AS [Check], '[OK]' AS [Deviation]
END;

IF @nolog24h > 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Log_Bcks_since_LstFullorDiff_are_older_than_24H' AS [Check], '[WARNING: Some databases in Full or Bulk-Logged recovery model have their latest log backup older than 24H]' AS [Deviation]
	SELECT DISTINCT 'Instance_checks' AS [Category], 'Log_Bcks_since_LstFullorDiff_are_older_than_24H' AS [Information], database_name AS [Database_Name], MAX(backup_finish_date) AS Lst_Log_Backup
	FROM msdb.dbo.backupset b (NOLOCK)
	INNER JOIN #tmpdbs_userchoice tuc ON b.database_name = tuc.[dbname]
	WHERE b.type = 'L' -- Log backup
		AND database_name IN (SELECT name FROM master.sys.databases (NOLOCK)
			WHERE database_id NOT IN (2,3)
				AND recovery_model < 3) -- not SIMPLE recovery model
	GROUP BY database_name
	HAVING MAX(backup_finish_date) > (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset c (NOLOCK) WHERE c.type IN ('D', 'I') -- Full or Differential backup
									AND c.is_copy_only = 0 -- No COPY_ONLY backups
									AND c.database_name = b.database_name)
		AND MAX(backup_finish_date) <= DATEADD(hh, -24, GETDATE())
	ORDER BY [database_name];
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Log_Bcks_since_LstFullorDiff_are_older_than_24H' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Global trace flags subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Global trace flags', 10, 1) WITH NOWAIT
DECLARE @tracestatus TABLE (TraceFlag NVARCHAR(40), [Status] tinyint, [Global] tinyint, [Session] tinyint);

INSERT INTO @tracestatus 
EXEC ('DBCC TRACESTATUS WITH NO_INFOMSGS')

IF @sqlmajorver >= 11
BEGIN
	DECLARE @dbname0 NVARCHAR(1000), @dbid0 int, @sqlcmd0 NVARCHAR(4000), @has_colstrix int, @min_compat_level tinyint

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblColStoreIXs'))
	DROP TABLE #tblColStoreIXs;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblColStoreIXs'))
	CREATE TABLE #tblColStoreIXs ([DBName] NVARCHAR(1000), [Schema] VARCHAR(100), [Table] VARCHAR(255), [Object] VARCHAR(255));

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;

	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname0 = [dbname], @dbid0 = [dbid] FROM #tmpdbs0 WHERE isdone = 0

			SET @sqlcmd0 = 'USE ' + QUOTENAME(@dbname0) + ';
SELECT ''' + REPLACE(@dbname0, CHAR(39), CHAR(95)) + ''' AS [DBName], QUOTENAME(t.name), QUOTENAME(o.[name]), i.name 
FROM sys.indexes AS i (NOLOCK)
INNER JOIN sys.objects AS o (NOLOCK) ON o.[object_id] = i.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = i.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE i.[type] IN (5,6,7)' -- 5 = Clustered columnstore; 6 = Nonclustered columnstore; 7 = Nonclustered hash

			BEGIN TRY
				INSERT INTO #tblColStoreIXs
				EXECUTE sp_executesql @sqlcmd0
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Global trace flags subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid0
		END
	END;
	
	SELECT @has_colstrix = COUNT(*) FROM #tblColStoreIXs

	SELECT @min_compat_level = min([compatibility_level]) from #tmpdbs0

END;

IF (SELECT COUNT(TraceFlag) FROM @tracestatus WHERE [Global]=1) = 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], '[There are no Global Trace Flags active]' AS [Deviation]
END;

-- Plan affecting TFs: http://support.microsoft.com/kb/2801413 and https://support.microsoft.com/kb/2964518
-- All supported TFs: http://aka.ms/traceflags
IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1)
BEGIN
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 174)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: TF174 increases the SQL Server Database Engine plan cache bucket count from 40,009 to 160,001 on 64-bit systems]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 174
	END;

	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 174)
		AND ((@sqlmajorver = 11 AND @sqlbuild >= 3368)
				OR (@sqlmajorver = 12 AND @sqlbuild >= 2480)
				OR (@sqlmajorver >= 13)		
		)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF174 to increase the SQL Server plan cache bucket count from 40,009 to 160,001 on 64-bit systems]'
			AS [Deviation], NULL AS 'TraceFlag' 
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 174
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 634)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: TF634 disables the background columnstore compression task]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 634
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 652)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: TF652 disables read-aheads during scans]' --http://support.microsoft.com/kb/920093
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 652
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 661)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: TF661 disables the ghost cleanup background task]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 661
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 834)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 11
				AND @has_colstrix > 0
				THEN '[WARNING: TF834 (Large Page Support for BP) is discouraged when Columnstore Indexes are used. In SQL Server 2019, use TF876 instead (preview) to set large-page allocations for columnstore only]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus
		WHERE [Global] = 1 AND TraceFlag = 834
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 845)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			CASE WHEN SERVERPROPERTY('EngineEdition') = 2 --Standard SKU
					AND ((@sqlmajorver = 10 AND ((@sqlminorver = 0 AND @sqlbuild >= 2714) OR @sqlminorver = 50)) 
						OR (@sqlmajorver = 9 AND @sqlbuild >= 4226))
					THEN '[INFORMATION: TF845 supports locking pages in memory in SQL Server Standard Edition]'
				WHEN SERVERPROPERTY('EngineEdition') = 2 --Standard SKU
					AND @sqlmajorver >= 11 
					THEN '[WARNING: TF845 is not needed in SQL 2012 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 845
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 902)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[WARNING: TF902 Bypasses execution of database upgrade script when installing a Cumulative Update or Service Pack]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 902
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1117)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
		CASE WHEN @sqlmajorver >= 13 --SQL 2016
			THEN '[WARNING: TF1117 is not needed in SQL 2016 and higher versions]'
			ELSE '[INFORMATION: TF1117 autogrows all files at the same time and affects all databases]' 
		END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1117
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1117)
		AND (@sqlmajorver < 13)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF1117 to autogrow all files at the same time and affects all databases]'
			AS [Deviation], NULL AS 'TraceFlag';
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1118)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
		CASE WHEN @sqlmajorver >= 13 --SQL 2016
			THEN '[WARNING: TF1118 is not needed in SQL 2016 and higher versions]'
			ELSE '[INFORMATION: TF1118 forces uniform extent allocations instead of mixed page allocations]'
		END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1118
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1118)
		AND (@sqlmajorver < 13)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF1118 to force uniform extent allocations instead of mixed page allocations]'
			AS [Deviation], NULL AS 'TraceFlag';
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1204)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF1204 returns the resources and types of locks participating in a deadlock and also the current command affected]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1204
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1211)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[WARNING: TF1211 disables lock escalation based on memory pressure, or based on number of locks, increasing the amount of locks held]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1211
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1222)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF1222 returns the resources and types of locks participating in a deadlock and also the current command affected]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1222
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1224)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[WARNING: TF1224 disables lock escalation based on the number of locks, and only escalates locks under memory pressure, increasing the amount of locks held]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1224
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1229)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[WARNING: TF1229 disables lock partitioning, which is a locking mechanism optimization on 16+ CPU servers]' --https://docs.microsoft.com/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide#lock_partitioning
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1229
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1236)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			CASE WHEN @sqlmajorver = 9 OR @sqlmajorver = 10 OR (@sqlmajorver = 11 AND @sqlbuild < 6020) OR (@sqlmajorver = 12 AND @sqlbuild < 4100)
					THEN '[INFORMATION: TF1236 enables database-level lock partitioning]'
				WHEN (@sqlmajorver = 11 AND @sqlbuild >= 6020) OR (@sqlmajorver = 12 AND @sqlbuild >= 4100) OR @sqlmajorver >= 13
					THEN '[WARNING: TF1236 is not needed in SQL 2012 SP3, SQL Server 2014 SP1 and above]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1236
	END;

	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1236)
		AND (@sqlmajorver = 9 OR @sqlmajorver = 10 OR (@sqlmajorver = 11 AND @sqlbuild < 6020) OR (@sqlmajorver = 12 AND @sqlbuild < 4100))
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[WARNING: Consider enabling TF1236 to allow database lock partitioning]'
			AS [Deviation]
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 1462)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[WARNING: TF1462 disables log stream compression for asynchronous availability groups]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 1462
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2312)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver = 12
				THEN '[INFORMATION: TF2312 enables the default CE model for SQL Server 2014 and higher versions, dependent of the compatibility level of the database]' 
			WHEN @sqlmajorver >= 13
				THEN '[INFORMATION: TF2312 enables the default CE model for SQL Server 2014 and higher versions, dependent of the compatibility level of the database]' 
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2312
	END;

/*	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2330)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver = 9
				THEN '[INFORMATION: TF2330 supresses recording of index usage stats, which can lead to a non-yielding condition in SQL Server 2005]' --http://support.microsoft.com/kb/2003031
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2330
	END;
*/
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2335)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 9
				AND @maxservermem >= 102400 -- 100GB
				AND @maxservermem <> 2147483647
				THEN '[INFORMATION: TF2335 assumes a fixed amount of memory is available during query optimization. Recommended when server has more than 100GB of memory]'
			WHEN @sqlmajorver >= 9
				AND @maxservermem < 102400 -- 100GB
				AND @maxservermem <> 2147483647
				THEN '[WARNING: TF2335 should not be set on servers with less than 100GB of memory]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2335
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2335)
		AND @sqlmajorver >= 9
		AND @maxservermem >= 102400 -- 100GB
		AND @maxservermem <> 2147483647
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF2335 to use a fixed amount of memory is available during query optimization. Recommended when server has more than 100GB of memory]' --http://support.microsoft.com/kb/2413549/en-us
			AS [Deviation]
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2340)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2340 causes SQL Server not to use a sort operation (batch sort) for optimized nested loop joins when generating a plan]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2340
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2371)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500) OR @sqlmajorver BETWEEN 11 AND 12 OR (@sqlmajorver >= 13 AND @min_compat_level < 130)
				THEN '[INFORMATION: TF2371 changes the fixed rate of the 20pct threshold for update statistics into a dynamic percentage rate]'
			WHEN @sqlmajorver >= 13 AND @min_compat_level >= 130
				--TF2371 has no effect if all databases are at least at compatibility level 130.
				THEN '[WARNING: TF2371 is not needed in SQL 2016 and above when all databases are at compatibility level 130 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2371
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2371)
		AND ((@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2500) OR @sqlmajorver < 13)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF2371 to change the 20pct fixed rate threshold for update statistics into a dynamic percentage rate]' --http://blogs.msdn.com/b/saponsqlserver/archive/2011/09/07/changes-to-automatic-update-statistics-in-sql-server-traceflag-2371.aspx
			AS [Deviation]
	END;

	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2371)
		AND (@sqlmajorver >= 13 AND @min_compat_level < 130)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Some databases have a compatibility level < 130. Consider enabling TF2371 to change the 20pct fixed rate threshold for update statistics into a dynamic percentage rate]' --http://blogs.msdn.com/b/saponsqlserver/archive/2011/09/07/changes-to-automatic-update-statistics-in-sql-server-traceflag-2371.aspx
			AS [Deviation]
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2389)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2389 enables automatically generated quick statistics for ascending keys (histogram amendment)]' 
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2389
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2528)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2528 disables parallel checking of objects by DBCC CHECKDB, DBCC CHECKFILEGROUP, and DBCC CHECKTABLE]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2528
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2549)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2549 forces the DBCC CHECKDB command to assume each database file is on a unique disk drive, but treating different physical files as one logical file]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2549
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2562)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2562 forces the DBCC CHECKDB command to execute in a single batch regardless of the number of indexes in the database]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2562
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 2566)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF2566 runs the DBCC CHECKDB command without data purity check unless DATA_PURITY option is specified]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 2566
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 3023)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF3023 enables CHECKSUM option as default for BACKUP command]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 3023
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 3042)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF3042 bypasses the default backup compression pre-allocation algorithm to allow the backup file to grow only as needed to reach its final size]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 3042
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 3226)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF3226 prevents SQL Server from recording an entry to Errorlog on every successful backup operation]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 3226
	END;
	
	/*
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4135)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 10 AND @sqlminorver = 0 AND @sqlbuild BETWEEN 1818 AND 1835)
					OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 1702)
				THEN '[WARNING: TF4199 should be used instead of TF4135 in this SQL build]'
			ELSE '[INFORMATION: TF4135 enables query optimizer changes released in SQL Server Cumulative Updates and Service Packs]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4135
	END;
	*/
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4136)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 9 AND @sqlbuild >= 4294)
					OR (@sqlmajorver = 10 AND @sqlminorver = 0 AND @sqlbuild >= 2766)
					OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 1720)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 2316)
					OR @sqlmajorver >= 12
				THEN '[INFORMATION: TF4136 disables parameter sniffing unless OPTION(RECOMPILE), WITH RECOMPILE or OPTIMIZE FOR value is used]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4136
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4137)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 10 AND @sqlminorver = 0 AND @sqlbuild >= 5794)
					OR (@sqlmajorver = 10 AND @sqlminorver = 0 AND @sqlbuild BETWEEN 4326 AND 4371)
					OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 2806)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 2316)
					OR @sqlmajorver >= 12
				THEN '[INFORMATION: TF4137 causes SQL Server to generate a plan using minimum selectivity when estimating AND predicates for filters to account for partial correlation under CE 70]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4137
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4138)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4260)
					OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild BETWEEN 2817 AND 2881)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 2325)
					OR @sqlmajorver >= 12
				THEN '[INFORMATION: TF4138 causes SQL Server to generate a plan that does not use row goal adjustments with queries that contain TOP, OPTION (FAST N), IN, or EXISTS keywords]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4138
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4139)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 11 AND @sqlbuild >= 5532)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 3431 AND @sqlbuild < 5058)
					OR @sqlmajorver >= 12
				THEN '[INFORMATION: TF4139 enables automatically generated quick statistics (histogram amendment) regardless of key column status]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4139
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 6498)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 12 AND @sqlbuild >= 4416 AND @sqlbuild < 5000)
					OR (@sqlmajorver = 12 AND @sqlbuild BETWEEN 2474 AND 2480)
				THEN '[INFORMATION: TF6498 enables more than one large query compilation to gain access to the big gateway when there is sufficient memory available, avoiding compilation waits for concurrent large queries]'
			WHEN (@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver >= 13
				THEN '[WARNING: TF6498 is not needed in SQL 2014 SP2, SQL Server 2016 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 6498
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag IN (6532,6533))
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 11 AND @sqlbuild = 6020)
				THEN '[INFORMATION: TF6532 enable performance improvements of query operations with spatial data types]'
			WHEN (@sqlmajorver = 12 AND @sqlbuild >= 5000)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 6518)
				THEN '[INFORMATION: TF6532 and TF 6533 enable performance improvements of query operations with spatial data types]'
			WHEN @sqlmajorver >= 13
				THEN '[WARNING: TF6532 and TF 6533 are not needed in SQL Server 2016 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag IN (6532,6533)
	END;

	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 6532)
		AND (@sqlmajorver = 11 AND @sqlbuild = 6020)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF6532 to enable performance improvements of query operations with spatial data types]' 
			AS [Deviation]
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag IN (6532,6533))
		AND ((@sqlmajorver = 11 AND @sqlbuild >= 6518) OR (@sqlmajorver = 12 AND @sqlbuild >= 5000))
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF6532 and TF6533 to enable performance improvements of query operations with spatial data types]' 
			AS [Deviation]
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 6534)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 12 AND @sqlbuild >= 5000)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 6020)
					OR @sqlmajorver >= 13
				THEN '[INFORMATION: TF6534 enables performance improvement of query operations with spatial data types]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 6534
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 6534)
		AND ((@sqlmajorver = 12 AND @sqlbuild >= 5000) OR (@sqlmajorver = 11 AND @sqlbuild >= 6020)	OR @sqlmajorver >= 13)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF6534 to enable performance improvements of query operations with spatial data types]' 
			AS [Deviation]
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 7412)
		AND ((@sqlmajorver = 13 AND @sqlbuild >= 4001) OR (@sqlmajorver = 14))
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			'[INFORMATION: Consider enabling TF7412 to enable the lightweight profiling infrastructure]' -- https://docs.microsoft.com/sql/relational-databases/performance/query-profiling-infrastructure
			AS [Deviation]
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 8015)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN (@sqlmajorver = 11 AND @sqlbuild >= 3349)
					OR @sqlmajorver >= 12
				THEN '[WARNING: TF8015 disables auto-detection and NUMA setup]' --https://techcommunity.microsoft.com/t5/SQL-Server-Support/How-It-Works-Soft-NUMA-I-O-Completion-Thread-Lazy-Writer-Workers/ba-p/316044
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 8015
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 8032)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 10
				THEN '[WARNING: TF8032 reverts the cache limit parameters to the SQL Server 2005 RTM setting but can cause poor performance if large caches make less memory available for other memory consumers like BP]' 
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 8032
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 8048)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN ((@sqlmajorver = 12 AND @sqlbuild < 4100)
					OR (@sqlmajorver BETWEEN 9 AND 11))
					AND (@cpucount/@numa) > 8
				THEN '[INFORMATION: TF8048 converts NUMA partitioned memory objects into CPU partitioned]' --https://techcommunity.microsoft.com/t5/SQL-Server-Support/Running-SQL-Server-on-Machines-with-More-Than-8-CPUs-per-NUMA/ba-p/318513
			WHEN (@sqlmajorver = 12 AND @sqlbuild >= 4100) OR @sqlmajorver >= 13
				THEN '[WARNING: TF8048 is not needed in SQL Server 2014 SP2, SQL Server 2016 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 8048
	END;

	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 8048)
		AND ((@sqlmajorver = 12 AND @sqlbuild < 4100)
		OR (@sqlmajorver BETWEEN 9 AND 11))
		AND (@cpucount/@numa) > 8
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: Consider enabling TF8048 to convert NUMA partitioned memory objects into CPU partitioned. Look in dm_os_wait_stats and dm_os_spin_stats for wait types (CMEMTHREAD and SOS_SUSPEND_QUEUE). Microsoft CSS usually sees the spins jump into the trillions and the waits become a hot spot]' --https://techcommunity.microsoft.com/t5/SQL-Server-Support/Running-SQL-Server-on-Machines-with-More-Than-8-CPUs-per-NUMA/ba-p/318513
			AS [Deviation];
			
		-- If the top consumers are partitioned by Node, then use startup trace flag 8048 to further partition by CPU.
		IF @sqlmajorver < 11
		BEGIN
			SELECT 'Instance_checks' AS [Category], 'Is_TF8048_Applicable' AS [Check], [type], 
				SUM(page_size_in_bytes)/8192 AS [pages], 
				SUM(page_size_in_bytes)/1024 AS pages_in_KB,
				CASE WHEN (0x20 = creation_options & 0x20) THEN 'Global PMO. Cannot be partitioned by CPU/NUMA Node. TF8048 not applicable.'
					WHEN (0x40 = creation_options & 0x40) THEN 'Partitioned by CPU. TF8048 not applicable.'
					WHEN (0x80 = creation_options & 0x80) THEN 'Partitioned by Node. Use TF8048 to further partition by CPU'
					ELSE 'Unknown' END AS [Comment]
			FROM sys.dm_os_memory_objects
			GROUP BY [type], creation_options
			ORDER BY SUM(page_size_in_bytes) DESC;
		END
		ELSE
		BEGIN
			SET @sqlcmd = N'SELECT ''Instance_checks'' AS [Category], ''Is_TF8048_Applicable'' AS [Check], [type], 
	SUM(pages_in_bytes)/8192 AS [pages], 
	SUM(pages_in_bytes)/1024 AS pages_in_KB,
	CASE WHEN (0x20 = creation_options & 0x20) THEN ''Global PMO. Cannot be partitioned by CPU/NUMA Node. TF8048 not applicable.''
		WHEN (0x40 = creation_options & 0x40) THEN ''Partitioned by CPU. TF8048 not applicable.''
		WHEN (0x80 = creation_options & 0x80) THEN ''Partitioned by Node. Use TF8048 to further partition by CPU''
		ELSE ''Unknown'' END AS [Comment]
FROM sys.dm_os_memory_objects
GROUP BY [type], creation_options
ORDER BY SUM(pages_in_bytes) DESC;'
			EXECUTE sp_executesql @sqlcmd
		END;
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 8744)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 12 THEN
				'[INFORMATION: TF8744 disables pre-fetching for the Nested Loop operator]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 8744
	END;	
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9024)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN ((@sqlmajorver = 12 AND @sqlbuild < 4100)
					OR (@sqlmajorver = 11 AND @sqlbuild >= 3349 AND @sqlbuild < 6020))
					AND (@cpucount/@numa) > 8
				THEN '[INFORMATION: TF9024 converts a global log pool memory object into NUMA node partitioned memory object]'
			WHEN (@sqlmajorver = 11 AND @sqlbuild >= 6020) OR (@sqlmajorver = 12 AND @sqlbuild >= 4427) OR @sqlmajorver > 12
				THEN '[WARNING: TF9024 is not needed in SQL Server 2012 SP3, SQL Server 2014 SP1 and above]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9024
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9347)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 13 THEN
				'[INFORMATION: TF9347 disables batch mode for sort operator]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9347
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9349)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 13 THEN
				'[INFORMATION: TF9349 disables batch mode for top N sort operator]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9349
	END;

	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9389)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 13 THEN
				'[INFORMATION: TF9389 enables dynamic memory grant for batch mode operators]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9389
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9476)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 13 THEN
				'[INFORMATION: TF9476 causes SQL Server to generate a plan using the Simple Containment instead of the default Base Containment under New CE]'
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9476
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 9481)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 12
				THEN '[INFORMATION: TF9481 enables Legacy CE model, irrespective of the compatibility level of the database]' 
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 9481
	END;
	
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 10204)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			CASE WHEN @sqlmajorver >= 13
				THEN '[INFORMATION: TF10204 disables merge/recompress during columnstore index reorganization]' 
			ELSE '[WARNING: Verify need to set a Non-default TF with current system build and configuration]'
			END AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 10204
	END;
		
	IF EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4199)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: TF4199 enables query optimizer changes released in SQL Server Cumulative Updates and Service Packs]'
			AS [Deviation], TraceFlag
		FROM @tracestatus 
		WHERE [Global] = 1 AND TraceFlag = 4199;
		
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			[name] AS [DBName], sd.compatibility_level, 'On' AS [TF_4199],
			'Enabled' AS 'QO_changes_from_previous_DB_compat_levels',
			'Enabled' AS 'QO_changes_for_current_version_post_RTM'
		FROM sys.databases sd
		INNER JOIN #tmpdbs0 tdbs ON sd.database_id = tdbs.[dbid];
	END;
	
	IF NOT EXISTS (SELECT TraceFlag FROM @tracestatus WHERE [Global] = 1 AND TraceFlag = 4199)
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check],
			'[INFORMATION: Consider enabling TF4199 to enable query optimizer changes released in SQL Server Cumulative Updates and Service Packs]'
			AS [Deviation], NULL AS 'TraceFlag';
		
		SELECT 'Instance_checks' AS [Category], 'Global_Trace_Flags' AS [Check], 
			[name] AS [DBName], sd.compatibility_level, 'Off' AS [TF_4199],
			CASE WHEN sd.compatibility_level >= 130 THEN 'Enabled' ELSE 'Disabled' END AS 'QO_changes_from_previous_DB_compat_levels',
			'Disabled' AS 'QO_changes_for_current_version_post_RTM'
		FROM sys.databases sd
		INNER JOIN #tmpdbs0 tdbs ON sd.database_id = tdbs.[dbid];
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- System configurations subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting System configurations', 10, 1) WITH NOWAIT
-- Focus on:
-- backup compression default
-- clr enabled (only enable if needed)
-- lightweight pooling (should be zero)
-- max degree of parallelism
-- cost threshold for parallelism 
-- max server memory (MB) (set to an appropriate value)
-- priority boost (should be zero)
-- remote admin connections (should be enabled in a cluster configuration, to allow remote DAC)
-- scan for startup procs (should be disabled unless business requirement, like replication)
-- min memory per query (default is 1024KB)
-- allow updates (no effect in 2005 or above, but should be off)
-- max worker threads (should be zero in 2005 or above)
-- affinity mask and affinity I/O mask (must not overlap)

DECLARE @awe tinyint, @ssp bit, @bckcomp bit, @clr bit, @costparallel smallint, @chain bit, @lpooling bit
DECLARE @adhoc smallint, @pboost bit, @qtimeout int, @cmdshell bit, @deftrace bit, @remote bit, @autoNUMA bit
DECLARE @minmemqry int, @allowupd bit, @mwthreads int, @recinterval int, @netsize smallint
DECLARE @ixmem smallint, @adhocqry bit, @locks int, @qrywait int--, @mwthreads_count int
DECLARE @affin int, @affinIO int, @affin64 int, @affin64IO int, @block_threshold int, @oleauto int

--SELECT @mwthreads_count = max_workers_count FROM sys.dm_os_sys_info;

SELECT @adhocqry = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'Ad Hoc Distributed Queries';
SELECT @affin = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'affinity mask';
SELECT @affinIO = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'affinity I/O mask';
SELECT @affin64 = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'affinity64 mask';
SELECT @affin64IO = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'affinity64 I/O mask';
SELECT @allowupd = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'allow updates';
SELECT @block_threshold = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'blocked process threshold (s)';
SELECT @awe = CONVERT(tinyint, [value]) FROM sys.configurations WHERE [Name] = 'awe enabled';
SELECT @autoNUMA = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'automatic soft-NUMA disabled';
SELECT @bckcomp = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'backup compression default';
SELECT @clr = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'clr enabled';
SELECT @costparallel = CONVERT(smallint, [value]) FROM sys.configurations WHERE [Name] = 'cost threshold for parallelism';
SELECT @chain = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'cross db ownership chaining';
SELECT @deftrace = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'default trace enabled';
SELECT @ixmem = CONVERT(smallint, [value]) FROM sys.configurations WHERE [Name] = 'index create memory (KB)';
SELECT @locks = CONVERT(int, [value]) FROM sys.configurations WHERE [Name] = 'locks';
SELECT @minmemqry = CONVERT(int, [value]) FROM sys.configurations WHERE [Name] = 'min memory per query (KB)';
SELECT @mwthreads = CONVERT(smallint, [value]) FROM sys.configurations WHERE [Name] = 'max worker threads';
SELECT @netsize = CONVERT(smallint, [value]) FROM sys.configurations WHERE [Name] = 'network packet size (B)';
SELECT @lpooling = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'lightweight pooling';
SELECT @recinterval = CONVERT(int, [value]) FROM sys.configurations WHERE [Name] = 'recovery interval (min)';
SELECT @remote = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'remote admin connections';
SELECT @qrywait = CONVERT(int, [value]) FROM sys.configurations WHERE [Name] = 'query wait (s)';
SELECT @adhoc = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'optimize for ad hoc workloads';
SELECT @oleauto = CONVERT(int, [value]) FROM sys.configurations (NOLOCK) WHERE name = 'Ole Automation Procedures';
SELECT @pboost = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'priority boost';
SELECT @qtimeout = CONVERT(int, [value]) FROM sys.configurations WHERE [Name] = 'remote query timeout (s)';
SELECT @ssp = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'scan for startup procs';
SELECT @cmdshell = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'xp_cmdshell';

SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Allow updates' AS [Setting], @allowupd AS [Current Value], CASE WHEN @allowupd = 0 THEN '[OK]' ELSE '[WARNING: Microsoft does not support direct catalog updates]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Ad Hoc Distributed Queries' AS [Setting], @adhocqry AS [Current Value], CASE WHEN @adhocqry = 0 THEN '[OK]' ELSE '[WARNING: Ad Hoc Distributed Queries are enabled]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Auto Soft NUMA Enabled' AS [Setting], @autoNUMA AS [Current Value], CASE WHEN @sqlmajorver >= 13 AND @autoNUMA = 1 THEN '[WARNING: Auto Soft NUMA is not enabled]' WHEN @sqlmajorver < 13 THEN '[NA]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Affinity Mask' AS [Setting], @affin AS [Current Value], CASE WHEN (@affin & @affinIO <> 0) OR (@affin & @affinIO <> 0 AND @affin64 & @affin64IO <> 0) THEN '[WARNING: Current Affinity Mask and Affinity I/O Mask are overlaping]' ELSE '[OK]' END AS [Deviation], '[INFORMATION: Configured values for AffinityMask = ' + CONVERT(VARCHAR(10), @affin) + '; Affinity64Mask = ' + CONVERT(VARCHAR(10), @affin64) + '; AffinityIOMask = ' + CONVERT(VARCHAR(10), @affinIO) + '; Affinity64IOMask = ' + CONVERT(VARCHAR(10), @affin64IO) + ']' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Affinity I/O Mask' AS [Setting], @affinIO AS [Current Value], CASE WHEN (@affin & @affinIO <> 0) OR (@affin & @affinIO <> 0 AND @affin64 & @affin64IO <> 0) THEN '[WARNING: Current Affinity Mask and Affinity I/O Mask are overlaping]' ELSE '[OK]' END AS [Deviation], '[INFORMATION: Configured values for AffinityMask = ' + CONVERT(VARCHAR(10), @affin) + '; Affinity64Mask = ' + CONVERT(VARCHAR(10), @affin64) + '; AffinityIOMask = ' + CONVERT(VARCHAR(10), @affinIO) + '; Affinity64IOMask = ' + CONVERT(VARCHAR(10), @affin64IO) + ']' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'AWE' AS [Setting], @awe AS [Current Value], CASE WHEN @sqlmajorver < 11 AND @arch = 32 AND @systemmem >= 4000 AND @awe = 0 THEN '[WARNING: Current AWE setting is not optimal for this configuration]' WHEN @sqlmajorver < 11 AND @arch IS NULL THEN '[WARNING: Could not determine architecture needed for check]' WHEN @sqlmajorver > 10 THEN '[INFORMATION: AWE is not used from SQL Server 2012 onwards]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Backup Compression' AS [Setting], @bckcomp AS [Current Value], CASE WHEN @sqlmajorver > 9 AND @bckcomp = 0 THEN '[INFORMATION: Backup compression setting is not the recommended value]' WHEN @sqlmajorver < 10 THEN '[NA]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Blocked Process Threshold' AS [Setting], @block_threshold AS [Current Value], CASE WHEN @block_threshold > 0 AND @block_threshold < 5 THEN '[WARNING: Blocked Process Threshold setting is not the recommended value. If not disabled, value should be higher than 4]' WHEN @block_threshold >= 5 THEN '[INFORMATION: Blocked Process Threshold setting is not the default value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'CLR' AS [Setting], @clr AS [Current Value], CASE WHEN @clr = 1 THEN '[INFORMATION: CLR user code execution setting is enabled]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Cost threshold for Parallelism' AS [Setting], @costparallel AS [Current Value], CASE WHEN @costparallel = 5 THEN '[OK]' ELSE '[WARNING: Cost threshold for Parallelism setting is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Cross DB ownership Chaining' AS [Setting], @chain AS [Current Value], CASE WHEN @chain = 1 THEN '[WARNING: Cross DB ownership chaining setting is not the recommended value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Default trace' AS [Setting], @deftrace AS [Current Value], CASE WHEN @deftrace = 0 THEN '[WARNING: Default trace setting is NOT enabled]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Index create memory (KB)' AS [Setting], @ixmem AS [Current Value], CASE WHEN @ixmem = 0 THEN '[OK]' WHEN @ixmem > 0 AND @ixmem < @minmemqry THEN '[WARNING: Index create memory should not be less than Min memory per query]' ELSE '[WARNING: Index create memory is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Lightweight pooling' AS [Setting], @lpooling AS [Current Value], CASE WHEN @lpooling = 1 THEN '[WARNING: Lightweight pooling setting is not the recommended value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Locks' AS [Setting], @locks AS [Current Value], CASE WHEN @locks = 0 THEN '[OK]' ELSE '[WARNING: Locks option is not set with the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Max worker threads' AS [Setting], @mwthreads AS [Current Value], CASE WHEN @mwthreads = 0 THEN '[OK]' WHEN @mwthreads > 2048 AND @arch = 64 THEN '[WARNING: Max worker threads is larger than 2048 on a x64 system]' WHEN @mwthreads > 1024 AND @arch = 32 THEN '[WARNING: Max worker threads is larger than 1024 on a x86 system]' ELSE '[WARNING: Max worker threads is not the default value]' END AS [Deviation], CASE WHEN @mwthreads = 0 THEN '[INFORMATION: Configured workers = ' + CONVERT(VARCHAR(10),@mwthreads_count) + ']' ELSE '' END AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Min memory per query (KB)' AS [Setting], @minmemqry AS [Current Value], CASE WHEN @minmemqry = 1024 THEN '[OK]' ELSE '[WARNING: Min memory per query (KB) setting is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Network packet size (B)' AS [Setting], @netsize AS [Current Value], CASE WHEN @netsize = 4096 THEN '[OK]' ELSE '[WARNING: Network packet size is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Ole Automation Procedures' AS [Setting], @oleauto AS [Current Value], CASE WHEN @oleauto = 1 THEN '[WARNING: Ole Automation Procedures setting is not the recommended value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Optimize for ad-hoc workloads' AS [Setting], @adhoc AS [Current Value], CASE WHEN @sqlmajorver > 9 AND @adhoc = 0 THEN '[INFORMATION: Consider enabling the Optimize for ad hoc workloads setting on heavy OLTP ad-hoc workloads to conserve resources]' WHEN @sqlmajorver < 10 THEN '[NA]' ELSE '[OK]' END AS [Deviation], CASE WHEN @sqlmajorver > 9 AND @adhoc = 0 THEN '[INFORMATION: Should be ON if SQL Server 2008 or higher and OLTP workload]' ELSE '' END AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Priority Boost' AS [Setting], @pboost AS [Current Value], CASE WHEN @pboost = 1 THEN '[CRITICAL: Priority boost setting is not the recommended value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Query wait (s)' AS [Setting], @qrywait AS [Current Value], CASE WHEN @qrywait = -1 THEN '[OK]' ELSE '[CRITICAL: Query wait is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Recovery Interval (min)' AS [Setting], @recinterval AS [Current Value], CASE WHEN @recinterval = 0 THEN '[OK]' ELSE '[WARNING: Recovery interval is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Remote Admin Connections' AS [Setting], @remote AS [Current Value], CASE WHEN @remote = 0 AND @clustered = 1 THEN '[WARNING: Consider enabling the DAC listener to access a remote connections on a clustered configuration]' WHEN @remote = 0 AND @clustered = 0 THEN '[INFORMATION: Consider enabling remote connections access to the DAC listener on a stand-alone configuration, should local resources be exhausted]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Remote query timeout' AS [Setting], @qtimeout AS [Current Value], CASE WHEN @qtimeout = 600 THEN '[OK]' ELSE '[WARNING: Remote query timeout is not the default value]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'Startup Stored Procedures' AS [Setting], @ssp AS [Current Value], CASE WHEN @ssp = 1 AND (@replication IS NULL OR @replication = 0) THEN '[WARNING: Scanning for startup stored procedures setting is not the recommended value]' ELSE '[OK]' END AS [Deviation], '' AS [Comment]
UNION ALL
SELECT 'Instance_checks' AS [Category], 'System_Configurations' AS [Check], 'xp_cmdshell' AS [Setting], @cmdshell AS [Current Value], CASE WHEN @cmdshell = 1 THEN '[WARNING: xp_cmdshell setting is enabled]' ELSE '[OK]' END AS [Deviation], '' AS [Comment];

IF (SELECT COUNT([name]) FROM master.sys.configurations WHERE [value] <> [value_in_use] AND [is_dynamic] = 0) > 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'System_Configurations_Pending' AS [Check], '[WARNING: There are system configurations with differences between running and configured values]' AS [Deviation]
	SELECT 'Instance_checks' AS [Category], 'System_Configurations_Pending' AS [Information], [name] AS [Setting],
		[value] AS 'Config_Value',
		[value_in_use] AS 'Run_Value'
	FROM master.sys.configurations (NOLOCK)
	WHERE [value] <> [value_in_use] AND [is_dynamic] = 0;
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'System_Configurations_Pending'AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- IFI subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting IFI', 10, 1) WITH NOWAIT
DECLARE @ifi bit, @IFIStatus NVARCHAR(256)
IF ((@sqlmajorver = 13 AND @sqlbuild < 4000) OR @sqlmajorver < 13)
BEGIN
	IF @allow_xpcmdshell = 1
	BEGIN
		IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0)) -- Is not sysadmin but proxy account exists
			OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
				AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0))
		BEGIN
			RAISERROR ('    |-Configuration options set for IFI check', 10, 1) WITH NOWAIT
			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END

			BEGIN TRY
				DECLARE @xp_cmdshell_output2 TABLE ([Output] VARCHAR (8000));
				SET @CMD = ('whoami /priv')
				INSERT INTO @xp_cmdshell_output2
				EXEC master.dbo.xp_cmdshell @CMD;
				
				IF EXISTS (SELECT * FROM @xp_cmdshell_output2 WHERE [Output] LIKE '%SeManageVolumePrivilege%')
				BEGIN
					SELECT 'Instance_checks' AS [Category], 'Instant_Initialization' AS [Check], '[OK]' AS [Deviation];
					SET @ifi = 1;
				END
				ELSE
				BEGIN
					SELECT 'Instance_checks' AS [Category], 'Instant_Initialization' AS [Check], '[WARNING: Instant File Initialization is disabled. This can impact data file autogrowth times]' AS [Deviation];
					SET @ifi = 0
				END
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'IFI subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH

			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END
		END
		ELSE
		BEGIN
			RAISERROR('[WARNING: Only a sysadmin can run the "Instant Initialization" check. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
			RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: xp_cmdshell. Bypassing check]', 16, 1, N'extended_sprocs')
			--RETURN
		END
	END
	ELSE
	BEGIN
		RAISERROR('    |- [INFORMATION: "Instant Initialization" check was skipped because xp_cmdshell was not allowed.]', 10, 1, N'disallow_xp_cmdshell')
		--RETURN
	END
END
ELSE IF ((@sqlmajorver = 13 AND @sqlbuild >= 4000) OR @sqlmajorver > 13)
BEGIN
	SET @sqlcmd = N'SELECT @IFIStatusOUT = instant_file_initialization_enabled FROM sys.dm_server_services WHERE servicename LIKE ''SQL Server%'' AND servicename NOT LIKE ''SQL Server Agent%''';
	SET @params = N'@IFIStatusOUT NVARCHAR(256) OUTPUT';
	EXECUTE sp_executesql @sqlcmd, @params, @IFIStatusOUT=@IFIStatus OUTPUT;
	IF @IFIStatus = 'Y'
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Instant_Initialization' AS [Check], '[OK]' AS [Deviation];
		SET @ifi = 1;
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Instant_Initialization' AS [Check], '[WARNING: Instant File Initialization is disabled. This can impact data file autogrowth times]' AS [Deviation];
		SET @ifi = 0
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Full Text Configurations subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Full Text Configurations', 10, 1) WITH NOWAIT
DECLARE @FullTextDefaultPath NVARCHAR(512), @fterr tinyint
DECLARE @fttbl TABLE ([KeyExist] int)
DECLARE @FullTextDetails TABLE (FullText_ResourceUsage tinyint,
	[DefaultPath] NVARCHAR(512),
	[ConnectTimeout] int,
	[DataTimeout] int,
	[AllowUnsignedBinaries] bit,
	[LoadOSResourcesEnabled] bit,
	[CatalogUpgradeOption] tinyint)
SET @fterr = 0

IF (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 1
BEGIN
	IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1) OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') = 1)
	BEGIN
		BEGIN TRY
			INSERT INTO @fttbl
			EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\Setup' -- check if Full-Text path exists

			IF (SELECT [KeyExist] FROM @fttbl) = 1
			BEGIN
				EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\Setup', N'FullTextDefaultPath', @FullTextDefaultPath OUTPUT, NO_OUTPUT;
			END
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Full Text Configurations subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Missing permissions for full "Full Text Configurations" checks. Bypassing Full Text path check]', 16, 1, N'sysadmin')
		--RETURN
	END
	
	INSERT INTO @FullTextDetails
	SELECT FULLTEXTSERVICEPROPERTY('ResourceUsage'), ISNULL(@FullTextDefaultPath, N'') AS [Default Path],
	ISNULL(FULLTEXTSERVICEPROPERTY('ConnectTimeout'),0), ISNULL(FULLTEXTSERVICEPROPERTY('DataTimeout'),0),
	CASE WHEN @sqlmajorver >= 9 THEN
			FULLTEXTSERVICEPROPERTY('VerifySignature') ELSE NULL 
	END AS [AllowUnsignedBinaries],
	CASE WHEN @sqlmajorver >= 9 THEN
		FULLTEXTSERVICEPROPERTY('LoadOSResources') ELSE NULL 
	END AS [LoadOSResourcesEnabled],
	CASE WHEN @sqlmajorver >= 10 THEN
		FULLTEXTSERVICEPROPERTY('UpgradeOption') ELSE NULL 
	END AS [CatalogUpgradeOption];
	
	IF @sqlmajorver <= 9 AND (SELECT FullText_ResourceUsage FROM @FullTextDetails) <> 3
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Full_Text' AS [Check], '[INFORMATION: FullText Resource usage setting is not default]' AS [Deviation],
			CASE WHEN FullText_ResourceUsage < 3 THEN '[Least Aggressive Usage Level]'
					WHEN FullText_ResourceUsage = 4 THEN '[More Aggressive Usage Level]'
					WHEN FullText_ResourceUsage = 5 THEN '[Most Aggressive Usage Level]'
			END AS [Comment]
		FROM @FullTextDetails;
		SET @fterr = @fterr + 1
	END
	IF @sqlmajorver >= 9 AND (SELECT [AllowUnsignedBinaries] FROM @FullTextDetails) = 0
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Full_Text' AS [Check], '[WARNING: FullText Binaries verification setting is not default]' AS [Deviation], 
			'[Do not verify whether or not binaries are signed]' AS [Comment];
		SET @fterr = @fterr + 1
	END
	IF @sqlmajorver >= 9 AND (SELECT [LoadOSResourcesEnabled] FROM @FullTextDetails) = 1
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Full_Text' AS [Check], '[WARNING: FullText OS Resource utilization setting is not default]' AS [Deviation], 
			'[Load OS filters and word breakers]' AS [Comment];
		SET @fterr = @fterr + 1
	END
	IF @fterr = 0
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Full_Text' AS [Check], '[OK]' AS [Deviation], 
			'[All FullText settings are aligned with defaults]' AS [Comment];
	END
END;

IF (SELECT ISNULL(FULLTEXTSERVICEPROPERTY('IsFulltextInstalled'),0)) = 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Full_Text' AS [Check], NULL AS [Deviation], '[FullText search is not installed]' AS [Comment];
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Deprecated features subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Deprecated or Discontinued features', 10, 1) WITH NOWAIT
IF (SELECT COUNT(instance_name) FROM sys.dm_os_performance_counters WHERE [object_name] = 'SQLServer:Deprecated Features' AND cntr_value > 0) > 0
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features' AS [Check], '[WARNING: Deprecated or Discontinued features are being used. Deprecated features are scheduled to be removed in a future release of SQL Server. Discontinued features have been removed from specific versions of SQL Server]' AS [Deviation]
	SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features' AS [Information], instance_name, cntr_value AS [Times_used_since_startup]
	FROM sys.dm_os_performance_counters (NOLOCK)
	WHERE [object_name] LIKE '%Deprecated Features%' AND cntr_value > 0
	ORDER BY instance_name;
	
	RAISERROR (N'    |-Deprecated or Discontinued Features are being used - finding usage in SQL modules and SQL Agent jobs', 10, 1) WITH NOWAIT
		
	/*DECLARE @dbid int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000)*/

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecated'))
	DROP TABLE #tblDeprecated;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecated'))
	CREATE TABLE #tblDeprecated ([DBName] sysname, [Schema] VARCHAR(100), [Object] VARCHAR(255), [Type] VARCHAR(100), DeprecatedFeature VARCHAR(30), DeprecatedIn tinyint, DiscontinuedIn tinyint);
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecatedJobs'))
	DROP TABLE #tblDeprecatedJobs;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecatedJobs'))
	CREATE TABLE #tblDeprecatedJobs ([JobName] sysname, [Step] VARCHAR(100), DeprecatedFeature VARCHAR(30), DeprecatedIn tinyint, DiscontinuedIn tinyint);
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tblKeywords'))
	DROP TABLE ##tblKeywords;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tblKeywords'))
	CREATE TABLE ##tblKeywords (
		KeywordID int IDENTITY(1,1) PRIMARY KEY,
		Keyword VARCHAR(64), -- the keyword itself
		DeprecatedIn tinyint,
		DiscontinuedIn tinyint
		);

	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.indexes (NOLOCK) WHERE name = N'UI_Keywords' AND [object_id] = OBJECT_ID('tempdb.dbo.##tblKeywords'))
	CREATE UNIQUE INDEX UI_Keywords ON ##tblKeywords(Keyword);

	INSERT INTO ##tblKeywords (Keyword, DeprecatedIn, DiscontinuedIn)
	-- discontinued on sql 2005
	SELECT 'disk init', NULL, 9 UNION ALL
	SELECT 'disk resize', NULL, 9 UNION ALL
	SELECT 'for load', NULL, 9 UNION ALL
	SELECT 'dbcc dbrepair', NULL, 9 UNION ALL
	SELECT 'dbcc newalloc', NULL, 9 UNION ALL
	SELECT 'dbcc pintable', NULL, 9 UNION ALL
	SELECT 'dbcc unpintable', NULL, 9 UNION ALL
	SELECT 'dbcc rowlock', NULL, 9 UNION ALL
	SELECT 'dbcc textall', NULL, 9 UNION ALL
	SELECT 'dbcc textalloc', NULL, 9 UNION ALL
	SELECT '*=', NULL, 9 UNION ALL
	SELECT '=*', NULL, 9 UNION ALL
	-- deprecated on sql 2005 and not yet discontinued
	SELECT 'setuser', 9, NULL UNION ALL
	SELECT 'sp_helpdevice', 9, NULL UNION ALL
	SELECT 'sp_addtype', 9, NULL UNION ALL
	SELECT 'sp_attach_db', 9, NULL UNION ALL
	SELECT 'sp_attach_single_file_db', 9, NULL UNION ALL
	SELECT 'sp_bindefault', 9, NULL UNION ALL
	SELECT 'sp_unbindefault', 9, NULL UNION ALL
	SELECT 'sp_bindrule', 9, NULL UNION ALL
	SELECT 'sp_unbindrule', 9, NULL UNION ALL
	SELECT 'create default', 9, NULL UNION ALL
	SELECT 'drop default', 9, NULL UNION ALL
	SELECT 'create rule', 9, NULL UNION ALL
	SELECT 'drop rule', 9, NULL UNION ALL
	SELECT 'sp_renamedb', 9, NULL UNION ALL
	SELECT 'sp_resetstatus', 9, NULL UNION ALL
	SELECT 'dbcc dbreindex', 9, NULL UNION ALL
	SELECT 'dbcc indexdefrag', 9, NULL UNION ALL
	SELECT 'dbcc showcontig', 9, NULL UNION ALL
	SELECT 'sp_addextendedproc', 9, NULL UNION ALL
	SELECT 'sp_dropextendedproc', 9, NULL UNION ALL
	SELECT 'sp_helpextendedproc', 9, NULL UNION ALL
	SELECT 'xp_loginconfig', 1, NULL UNION ALL
	SELECT 'sp_fulltext_catalog', 9, NULL UNION ALL
	SELECT 'sp_fulltext_table', 9, NULL UNION ALL
	SELECT 'sp_fulltext_column', 9, NULL UNION ALL
	SELECT 'sp_fulltext_database', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_tables', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_columns', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_catalogs', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_tables_cursor', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_columns_cursor', 9, NULL UNION ALL
	SELECT 'sp_help_fulltext_catalogs_cursor', 9, NULL UNION ALL
	SELECT 'fn_get_sql', 9, NULL UNION ALL
	SELECT 'sp_indexoption', 9, NULL UNION ALL
	SELECT 'sp_lock', 9, NULL UNION ALL
	SELECT 'indexkey_property', 9, NULL UNION ALL
	SELECT 'file_id', 9, NULL UNION ALL
	SELECT 'sp_certify_removable', 9, NULL UNION ALL
	SELECT 'sp_create_removable', 9, NULL UNION ALL
	SELECT 'sp_dbremove', 9, NULL UNION ALL
	SELECT 'sp_addapprole', 9, NULL UNION ALL
	SELECT 'sp_dropapprole', 9, NULL UNION ALL
	SELECT 'sp_addlogin', 9, NULL UNION ALL
	SELECT 'sp_droplogin', 9, NULL UNION ALL
	SELECT 'sp_adduser', 9, NULL UNION ALL
	SELECT 'sp_dropuser', 9, NULL UNION ALL
	SELECT 'sp_grantdbaccess', 9, NULL UNION ALL
	SELECT 'sp_revokedbaccess', 9, NULL UNION ALL
	SELECT 'sp_addrole', 9, NULL UNION ALL
	SELECT 'sp_droprole', 9, NULL UNION ALL
	SELECT 'sp_approlepassword', 9, NULL UNION ALL
	SELECT 'sp_password', 9, NULL UNION ALL
	SELECT 'sp_changeobjectowner', 9, NULL UNION ALL
	SELECT 'sp_defaultdb', 9, NULL UNION ALL
	SELECT 'sp_defaultlanguage', 9, NULL UNION ALL
	SELECT 'sp_denylogin', 9, NULL UNION ALL
	SELECT 'sp_grantlogin', 9, NULL UNION ALL
	SELECT 'sp_revokelogin', 9, NULL UNION ALL
	SELECT 'user_id', 9, NULL UNION ALL
	SELECT 'sp_srvrolepermission', 9, NULL UNION ALL
	SELECT 'sp_dbfixedrolepermission', 9, NULL UNION ALL
	SELECT 'text', 9, NULL UNION ALL
	SELECT 'ntext', 9, NULL UNION ALL
	SELECT 'image', 9, NULL UNION ALL
	SELECT 'textptr', 9, NULL UNION ALL
	SELECT 'textvalid', 9, NULL UNION ALL
	-- discontinued on sql 2008
	SELECT 'sp_addalias', 9, 10 UNION ALL
	SELECT 'no_log', 9, 10 UNION ALL
	SELECT 'truncate_only', 9, 10 UNION ALL
	SELECT 'backup transaction', 9, 10 UNION ALL
	SELECT 'dbcc concurrencyviolation', 9, 10 UNION ALL
	SELECT 'sp_addgroup', 9, 10 UNION ALL
	SELECT 'sp_changegroup', 9, 10 UNION ALL
	SELECT 'sp_dropgroup', 9, 10 UNION ALL
	SELECT 'sp_helpgroup', 9, 10 UNION ALL
	SELECT 'sp_makewebtask', NULL, 10 UNION ALL
	SELECT 'sp_dropwebtask', NULL, 10 UNION ALL
	SELECT 'sp_runwebtask', NULL, 10 UNION ALL
	SELECT 'sp_enumcodepages', NULL, 10 UNION ALL
	SELECT 'dump', 9, 10 UNION ALL
	SELECT 'load', 9, 10 UNION ALL
	-- undocumented system stored procedures are removed from sql server:
	SELECT 'sp_articlesynctranprocs', NULL, 10 UNION ALL
	SELECT 'sp_diskdefault', NULL, 10 UNION ALL
	SELECT 'sp_eventlog', NULL, 10 UNION ALL
	SELECT 'sp_getmbcscharlen', NULL, 10 UNION ALL
	SELECT 'sp_helplog', NULL, 10 UNION ALL
	SELECT 'sp_helpsql', NULL, 10 UNION ALL
	SELECT 'sp_ismbcsleadbyte', NULL, 10 UNION ALL
	SELECT 'sp_lock2', NULL, 10 UNION ALL
	SELECT 'sp_msget_current_activity', NULL, 10 UNION ALL
	SELECT 'sp_msset_current_activity', NULL, 10 UNION ALL
	SELECT 'sp_msobjessearch', NULL, 10 UNION ALL
	SELECT 'xp_enum_activescriptengines', NULL, 10 UNION ALL
	SELECT 'xp_eventlog', NULL, 10 UNION ALL
	SELECT 'xp_getadmingroupname', NULL, 10 UNION ALL
	SELECT 'xp_getfiledetails', NULL, 10 UNION ALL
	SELECT 'xp_getlocalsystemaccountname', NULL, 10 UNION ALL
	SELECT 'xp_isntadmin', NULL, 10 UNION ALL
	SELECT 'xp_mslocalsystem', NULL, 10 UNION ALL
	SELECT 'xp_msnt2000', NULL, 10 UNION ALL
	SELECT 'xp_msplatform', NULL, 10 UNION ALL
	SELECT 'xp_setsecurity', NULL, 10 UNION ALL
	SELECT 'xp_varbintohexstr', NULL, 10 UNION ALL
	-- undocumented system tables are removed from sql server:
	SELECT 'spt_datatype_info', NULL, 10 UNION ALL
	SELECT 'spt_datatype_info_ext', NULL, 10 UNION ALL
	SELECT 'spt_provider_types', NULL, 10 UNION ALL
	SELECT 'spt_server_info', NULL, 10 UNION ALL
	SELECT 'spt_values', NULL, 10 UNION ALL
	SELECT 'sysfulltextnotify ', NULL, 10 UNION ALL
	SELECT 'syslocks', NULL, 10 UNION ALL
	SELECT 'sysproperties', NULL, 10 UNION ALL
	SELECT 'sysprotects_aux', NULL, 10 UNION ALL
	SELECT 'sysprotects_view', NULL, 10 UNION ALL
	SELECT 'sysremote_catalogs', NULL, 10 UNION ALL
	SELECT 'sysremote_column_privileges', NULL, 10 UNION ALL
	SELECT 'sysremote_columns', NULL, 10 UNION ALL
	SELECT 'sysremote_foreign_keys', NULL, 10 UNION ALL
	SELECT 'sysremote_indexes', NULL, 10 UNION ALL
	SELECT 'sysremote_primary_keys', NULL, 10 UNION ALL
	SELECT 'sysremote_provider_types', NULL, 10 UNION ALL
	SELECT 'sysremote_schemata', NULL, 10 UNION ALL
	SELECT 'sysremote_statistics', NULL, 10 UNION ALL
	SELECT 'sysremote_table_privileges', NULL, 10 UNION ALL
	SELECT 'sysremote_tables', NULL, 10 UNION ALL
	SELECT 'sysremote_views', NULL, 10 UNION ALL
	SELECT 'syssegments', NULL, 10 UNION ALL
	SELECT 'sysxlogins', NULL, 10 UNION ALL
	-- deprecated on sql 2008 and not yet discontinued
	SELECT 'sp_droptype', 10, NULL UNION ALL
	SELECT '@@remserver', 10, NULL UNION ALL
	SELECT 'remote_proc_transactions', 10, NULL UNION ALL
	SELECT 'sp_addumpdevice', 10, NULL UNION ALL
	SELECT 'xp_grantlogin', 10, NULL UNION ALL
	SELECT 'xp_revokelogin', 10, NULL UNION ALL
	SELECT 'grant all', 10, NULL UNION ALL
	SELECT 'deny all', 10, NULL UNION ALL
	SELECT 'revoke all', 10, NULL UNION ALL
	SELECT 'fn_virtualservernodes', 10, NULL UNION ALL
	SELECT 'fn_servershareddrives', 10, NULL UNION ALL
	SELECT 'writetext', 10, NULL UNION ALL
	SELECT 'updatetext', 10, NULL UNION ALL
	SELECT 'readtext', 10, NULL UNION ALL
	SELECT 'torn_page_detection', 10, NULL UNION ALL
	SELECT 'set rowcount', 10, NULL UNION ALL
	-- discontinued on sql 2012
	SELECT 'dbo_only', 9, 11 UNION ALL -- on restore statements
	SELECT 'mediapassword', 9, 11 UNION ALL -- on backup statements
	SELECT 'password', 9, 11 UNION ALL -- on backup statements except for media
	SELECT 'with append', 10, 11 UNION ALL -- on triggers
	SELECT 'sp_dboption', 9, 11 UNION ALL
	SELECT 'databaseproperty', 9, 11 UNION ALL
	SELECT 'fastfirstrow', 10, 11 UNION ALL
	SELECT 'sp_addserver', 10, 11 UNION ALL -- for linked servers
	SELECT 'sp_dropalias', 9, 11 UNION ALL
	SELECT 'disable_def_cnst_chk', 10, 11 UNION ALL
	SELECT 'sp_activedirectory_obj', NULL, 11 UNION ALL
	SELECT 'sp_activedirectory_scp', NULL, 11 UNION ALL
	SELECT 'sp_activedirectory_start', NULL, 11 UNION ALL
	SELECT 'sys.database_principal_aliases', NULL, 11 UNION ALL
	SELECT 'compute', 10, 11 UNION ALL
	SELECT 'compute by', 10, 11 UNION ALL
	-- deprecated on sql 2012 and not yet discontinued
	SELECT 'sp_change_users_login', 11, NULL UNION ALL
	SELECT 'sp_depends', 11, NULL UNION ALL
	SELECT 'sp_getbindtoken', 11, NULL UNION ALL
	SELECT 'sp_bindsession', 11, NULL UNION ALL
	SELECT 'fmtonly', 11, NULL UNION ALL
	SELECT 'raiserror', 11, NULL UNION ALL
	SELECT 'sp_db_increased_partitions', 11, NULL UNION ALL
	SELECT 'databasepropertyex(''isfulltextenabled'')', 11, NULL UNION ALL
	SELECT 'sp_dbcmptlevel', 11, NULL UNION ALL
	SELECT 'set ansi_nulls off', 11, NULL UNION ALL
	SELECT 'set ansi_padding off', 11, NULL UNION ALL
	SELECT 'set concat_null_yields_null off', 11, NULL UNION ALL
	SELECT 'set offsets', 11, NULL UNION ALL
	-- deprecated on sql 2014 and not yet discontinued
	SELECT 'sys.numbered_procedures', 12, NULL UNION ALL
	SELECT 'sys.numbered_procedure_parameters', 12, NULL UNION ALL
	SELECT 'sys.sql_dependencies', 12, NULL UNION ALL
	SELECT 'sp_db_vardecimal_storage_format', 12, NULL UNION ALL
	SELECT 'sp_estimated_rowsize_reduction_for_vardecimal', 12, NULL UNION ALL
	SELECT 'sp_trace_create', 12, NULL UNION ALL
	SELECT 'sp_trace_setevent', 12, NULL UNION ALL
	SELECT 'sp_trace_setstatus', 12, NULL UNION ALL
	SELECT 'fn_trace_geteventinfo', 12, NULL UNION ALL
	SELECT 'fn_trace_getfilterinfo', 12, NULL UNION ALL
	SELECT 'fn_trace_gettable', 12, NULL UNION ALL
	SELECT 'sys.traces', 12, NULL UNION ALL
	SELECT 'sys.trace_events', 12, NULL UNION ALL
	SELECT 'sys.trace_event_bindings', 12, NULL UNION ALL
	SELECT 'sys.trace_categories', 12, NULL UNION ALL
	SELECT 'sys.trace_columns', 12, NULL UNION ALL
	SELECT 'sys.trace_subclass_values', 12, NULL UNION ALL
	-- discontinued on sql 2019
	SELECT 'disable_interleaved_execution_tvf', 10, 15 UNION ALL -- as DB Scoped config
	SELECT 'disable_batch_mode_memory_grant_feedback', 10, 15 UNION ALL -- as DB Scoped config
	SELECT 'disable_batch_mode_adaptive_joins', 10, 15 -- as DB Scoped config
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;

	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0

			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT N''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], ss.name AS [Schema_Name], so.name AS [Object_Name], so.type_desc, tk.Keyword, tk.DeprecatedIn, tk.DiscontinuedIn
FROM sys.sql_modules sm (NOLOCK)
INNER JOIN sys.objects so (NOLOCK) ON sm.[object_id] = so.[object_id]
INNER JOIN sys.schemas ss (NOLOCK) ON so.[schema_id] = ss.[schema_id]
CROSS JOIN ##tblKeywords tk (NOLOCK)
WHERE PATINDEX(''%'' + tk.Keyword + ''%'', LOWER(sm.[definition]) COLLATE DATABASE_DEFAULT) > 1
AND OBJECTPROPERTY(sm.[object_id],''IsMSShipped'') = 0;'

			BEGIN TRY
				INSERT INTO #tblDeprecated
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Deprecated or Discontinued Features usage subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
		
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;
	
	SET @sqlcmd = 'USE [msdb];
SELECT sj.[name], sjs.step_name, tk.Keyword, tk.DeprecatedIn, tk.DiscontinuedIn
FROM msdb.dbo.sysjobsteps sjs (NOLOCK)
INNER JOIN msdb.dbo.sysjobs sj (NOLOCK) ON sjs.job_id = sj.job_id
CROSS JOIN ##tblKeywords tk (NOLOCK)
WHERE PATINDEX(''%'' + tk.Keyword + ''%'', LOWER(sjs.[command]) COLLATE DATABASE_DEFAULT) > 1
AND sjs.[subsystem] IN (''TSQL'',''PowerShell'');'

	BEGIN TRY
		INSERT INTO #tblDeprecatedJobs
		EXECUTE sp_executesql @sqlcmd
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Deprecated or Discontinued Features usage subsection - Error raised in jobs TRY block. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH

	IF (SELECT COUNT(*) FROM #tblDeprecated) > 0
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features_usage_in_Objects' AS [Information], DBName, [Schema], [Object], [Type], DeprecatedFeature, 		
			CASE [DeprecatedIn] WHEN 9 THEN '2005' WHEN 10 THEN '2008/2008R2' WHEN 11 THEN '2012' WHEN 12 THEN '2014' WHEN 13 THEN '2016' WHEN 14 THEN '2017' ELSE NULL END AS [DeprecatedIn],
			CASE [DiscontinuedIn] WHEN 9 THEN '2005' WHEN 10 THEN '2008/2008R2' WHEN 11 THEN '2012' WHEN 12 THEN '2014' WHEN 13 THEN '2016' WHEN 14 THEN '2017' ELSE NULL END AS [DiscontinuedIn],
			CASE WHEN [DiscontinuedIn] IS NULL THEN '[INFORMATION: Deprecated Features are being used. Plan to review objects found using deprecated features and replace deprecated constructs]' 
				ELSE '[WARNING: Discontinued Features are being used. Refactor objects found using discontinued features before migrating to a higher version of SQL Server]' END AS [Comment]
		FROM #tblDeprecated (NOLOCK);
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features' AS [Information], NULL AS [DBName], NULL AS [Schema], NULL AS [Object], NULL AS [Type], 
			NULL AS [DeprecatedFeature], NULL AS [DeprecatedIn], NULL AS [DiscontinuedIn],
			'[INFORMATION: Deprecated or Discontinued Features may be in use with ad-hoc code]' AS Comment
	END;
	
	IF (SELECT COUNT(*) FROM #tblDeprecatedJobs) > 0
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features_usage_in_SQLAgent_jobs' AS [Information], JobName, [Step], DeprecatedFeature, 		
			CASE [DeprecatedIn] WHEN 9 THEN '2005' WHEN 10 THEN '2008/2008R2' WHEN 11 THEN '2012' WHEN 12 THEN '2014' WHEN 13 THEN '2016' WHEN 14 THEN '2017' ELSE NULL END AS [DeprecatedIn],
			CASE [DiscontinuedIn] WHEN 9 THEN '2005' WHEN 10 THEN '2008/2008R2' WHEN 11 THEN '2012' WHEN 12 THEN '2014' WHEN 13 THEN '2016' WHEN 14 THEN '2017' ELSE NULL END AS [DiscontinuedIn],
			CASE WHEN [DiscontinuedIn] IS NULL THEN '[INFORMATION: Deprecated Features are being used in SQL Agent jobs. Plan to review job steps found using deprecated features and replace deprecated constructs]' 
				ELSE '[WARNING: Discontinued Features are being used in SQL Agent jobs. Refactor job steps found using discontinued features before migrating to a higher version of SQL Server]' END AS [Comment]
		FROM #tblDeprecatedJobs (NOLOCK);
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features' AS [Information], NULL AS [JobName], NULL AS [Step], 
			NULL AS [DeprecatedFeature], NULL AS [DeprecatedIn], NULL AS [DiscontinuedIn],
			'[INFORMATION: No Deprecated or Discontinued Features found in SQL Agent jobs]' AS Comment
	END;
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Deprecated_Discontinued_features' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Default data collections subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting default data collections', 10, 1) WITH NOWAIT
IF EXISTS (SELECT TOP 1 id FROM sys.traces WHERE is_default = 1 AND status = 1)
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Default_Trace' AS [Check], '[OK]' AS [Deviation]
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Default_Trace' AS [Information], '[WARNING: No default trace was found or is not active]' AS [Deviation], '[Default trace provides troubleshooting assistance to database administrators by ensuring that they have the log data necessary to diagnose problems the first time they occur]' AS [Comment]
END;

IF EXISTS (SELECT TOP 1 id FROM sys.traces WHERE [path] LIKE '%blackbox%.trc' AND status = 1)
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Blackbox_Trace' AS [Check], '[WARNING: Blackbox trace is configured and running]' AS [Deviation], '[This trace is designed to behave similarly to an airplane black box, to help you diagnose intermittent server crashes. It consumes more resources than the default trace and should not be running for extended periods of time]' AS [Comment]
END
ELSE
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Blackbox_Trace' AS [Information], '[OK]' AS [Deviation]
END;

IF EXISTS (SELECT TOP 1 id FROM sys.traces WHERE (is_default = 1 OR [path] LIKE '%blackbox%.trc') AND status = 1)
BEGIN
	SELECT 'Instance_checks' AS [Category], 'Default_or_Blackbox_Trace' AS [Information], [id] As trace_id, [path], max_size, max_files, buffer_count, buffer_size, is_default, event_count, dropped_event_count, start_time, last_event_time 
	FROM sys.traces
	WHERE (is_default = 1 OR [path] LIKE '%blackbox%.trc') AND status = 1
END;

IF @sqlmajorver > 10
BEGIN
	IF EXISTS (SELECT TOP 1 name FROM sys.dm_xe_sessions WHERE [name] = 'system_health')
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'xEvent_Session_SystemHealth' AS [Check], '[OK]' AS [Deviation]
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'xEvent_Session_SystemHealth' AS [Information], '[WARNING: The system_health xEvent session is not active]' AS [Deviation], '[This session starts automatically when the SQL Server Database Engine starts, and runs without any noticeable performance effects. The session collects system data that you can use to help troubleshoot performance issues in the Database Engine]' AS [Comment]
	END;

	IF EXISTS (SELECT TOP 1 name FROM sys.dm_xe_sessions WHERE [name] = 'sp_server_diagnostics session')
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'xEvent_Session_sp_server_diagnostics' AS [Check], '[OK]' AS [Deviation]
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'xEvent_Session_sp_server_diagnostics' AS [Information], '[WARNING: The sp_server_diagnostics xEvent session is not active]' AS [Deviation], '[This session starts automatically when the SQL Server Database Engine starts, and runs without any noticeable performance effects. The session collects system data that you can use to help troubleshoot performance issues in the Database Engine]' AS [Comment]
	END;

	IF EXISTS (SELECT TOP 1 name FROM sys.dm_xe_sessions WHERE [name] IN ('system_health', 'sp_server_diagnostics session'))
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'xEvent_Session_SystemHealth_sp_server_diagnostics' AS [Information], name, pending_buffers, total_regular_buffers, regular_buffer_size, total_large_buffers, large_buffer_size, total_buffer_size, buffer_policy_desc, flag_desc, 
			dropped_event_count, dropped_buffer_count, blocked_event_fire_time, create_time, largest_event_dropped_size
		FROM sys.dm_xe_sessions
		WHERE [name] IN ('system_health', 'sp_server_diagnostics session')
	END;
END;


RAISERROR (N'|-Starting Database and tempDB Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- User objects in master DB
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting User Objects in master DB', 10, 1) WITH NOWAIT
IF (SELECT COUNT(name) FROM master.sys.all_objects WHERE is_ms_shipped = 0 AND [type] IN ('AF','FN','P','IF','PC','TF','TR','T','V')) >= 1
BEGIN
	SELECT 'Database_checks' AS [Category], 'User_Objects_in_master' AS [Check], '[WARNING: User objects are created in the master database]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'User_Objects_in_master' AS [Information], ss.name AS [Schema_Name], sao.name AS [Object_Name], sao.[type_desc] AS [Object_Type], sao.create_date, sao.modify_date 
	FROM master.sys.all_objects sao
	INNER JOIN master.sys.schemas ss ON sao.[schema_id] = ss.[schema_id]
	WHERE sao.is_ms_shipped = 0
	AND sao.[type] IN ('AF','FN','P','IF','PC','TF','TR','T','V')
	ORDER BY sao.name, sao.type_desc;
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'User_Objects_in_master' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBs with collation <> master subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBs with collation <> master', 10, 1) WITH NOWAIT
DECLARE @master_collate NVARCHAR(128), @dif_collate int
SELECT @master_collate = collation_name FROM master.sys.databases (NOLOCK) WHERE database_id = 1;
SELECT @dif_collate = COUNT(collation_name) FROM master.sys.databases (NOLOCK) WHERE collation_name <> @master_collate;

IF @dif_collate >= 1
BEGIN
	SELECT 'Database_checks' AS [Category], 'Collations' AS [Check], '[WARNING: Some user databases collation differ from the master Database_Collation]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Collations' AS [Information], name AS [Database_Name], collation_name AS [Database_Collation], @master_collate AS [Master_Collation]
	FROM master.sys.databases (NOLOCK)
	WHERE collation_name <> @master_collate;
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Collations' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBs with skewed compatibility level subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBs with skewed compatibility level', 10, 1) WITH NOWAIT
DECLARE @dif_compat int
SELECT @dif_compat = COUNT([compatibility_level]) FROM master.sys.databases (NOLOCK) WHERE [compatibility_level] <> @sqlmajorver * 10;

IF @dif_compat >= 1
BEGIN
	SELECT 'Database_checks' AS [Category], 'Compatibility_Level' AS [Check], '[WARNING: Some user databases have a non-optimal compatibility level]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Compatibility_Level' AS [Information], name AS [Database_Name], [compatibility_level] AS [Compatibility_Level]
	FROM master.sys.databases (NOLOCK)
	WHERE [compatibility_level] <> @sqlmajorver * 10;
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Compatibility_Level' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- User DBs with non-default options subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting User DBs with non-default options', 10, 1) WITH NOWAIT
DECLARE @cnt int, @cnt_i int
DECLARE @is_auto_close_on bit, @is_auto_shrink_on bit, @page_verify_option bit
DECLARE @is_auto_create_stats_on bit, @is_auto_update_stats_on bit
DECLARE @is_db_chaining_on bit, @is_auto_create_stats_incremental_on bit--, @is_indirect_checkpoint_on bit
DECLARE @is_trustworthy_on bit, @is_parameterization_forced bit

DECLARE @dbopterrtb TABLE (id int, 
	name sysname, 
	is_auto_close_on bit, 
	is_auto_shrink_on bit, 
	page_verify_option tinyint, 
	page_verify_option_desc NVARCHAR(60),
	is_auto_create_stats_on bit, 
	is_auto_update_stats_on bit,
	is_db_chaining_on bit,
	--is_indirect_checkpoint_on bit,
	is_auto_create_stats_incremental_on bit NULL,
	is_trustworthy_on bit,
	is_parameterization_forced bit)

IF @sqlmajorver < 12
BEGIN
	SET @sqlcmd = 'SELECT ROW_NUMBER() OVER(ORDER BY name), name, is_auto_close_on, 
	is_auto_shrink_on, page_verify_option, page_verify_option_desc,	
	is_auto_create_stats_on, is_auto_update_stats_on, is_db_chaining_on,
	--0 AS is_indirect_checkpoint_on, 
	NULL AS is_auto_create_stats_incremental_on, 
	is_trustworthy_on, is_parameterization_forced
FROM master.sys.databases (NOLOCK)
WHERE database_id > 4 OR name = ''model'''
END
ELSE
BEGIN
	SET @sqlcmd = 'SELECT ROW_NUMBER() OVER(ORDER BY name), name, is_auto_close_on, 
	is_auto_shrink_on, page_verify_option, page_verify_option_desc,	
	is_auto_create_stats_on, is_auto_update_stats_on, 
	is_db_chaining_on, 
	--CASE WHEN target_recovery_time_in_seconds > 0 THEN 1 ELSE 0 END AS is_indirect_checkpoint_on, 
	is_auto_create_stats_incremental_on, 
	is_trustworthy_on, is_parameterization_forced
FROM master.sys.databases (NOLOCK)
WHERE database_id > 4 OR name = ''model'''
END;

INSERT INTO @dbopterrtb
EXECUTE sp_executesql @sqlcmd;

SET @cnt = (SELECT COUNT(id) FROM @dbopterrtb)
SET @cnt_i = 1

SELECT @is_auto_close_on = 0, @is_auto_shrink_on = 0, @page_verify_option = 0, @is_auto_create_stats_on = 0, @is_auto_update_stats_on = 0, @is_db_chaining_on = 0, @is_trustworthy_on = 0, @is_parameterization_forced = 0, @is_auto_create_stats_incremental_on = 0--, @is_indirect_checkpoint_on = 0

WHILE @cnt_i <> @cnt
BEGIN 
	SELECT @is_auto_close_on = CASE WHEN is_auto_close_on = 1 AND @is_auto_close_on = 0 THEN 1 ELSE @is_auto_close_on END,
		@is_auto_shrink_on = CASE WHEN is_auto_shrink_on = 1 AND @is_auto_shrink_on = 0 THEN 1 ELSE @is_auto_shrink_on END, 
		@page_verify_option = CASE WHEN page_verify_option <> 2 AND @page_verify_option = 0 THEN 1 ELSE @page_verify_option END, 
		@is_auto_create_stats_on = CASE WHEN is_auto_create_stats_on = 0 AND @is_auto_create_stats_on = 0 THEN 1 ELSE @is_auto_create_stats_on END, 
		@is_auto_update_stats_on = CASE WHEN is_auto_update_stats_on = 0 AND @is_auto_update_stats_on = 0 THEN 1 ELSE @is_auto_update_stats_on END, 
		@is_db_chaining_on = CASE WHEN is_db_chaining_on = 1 AND @is_db_chaining_on = 0 THEN 1 ELSE @is_db_chaining_on END,
		--@is_indirect_checkpoint_on = CASE WHEN is_indirect_checkpoint_on = 1 AND @is_indirect_checkpoint_on = 0 THEN 1 ELSE @is_indirect_checkpoint_on END,
		@is_auto_create_stats_incremental_on = CASE WHEN is_auto_create_stats_incremental_on = 1 AND @is_auto_create_stats_incremental_on IS NULL THEN 1 ELSE @is_auto_create_stats_incremental_on END,
		@is_trustworthy_on = CASE WHEN is_trustworthy_on = 1 AND @is_trustworthy_on = 0 THEN 1 ELSE @is_trustworthy_on END,
		@is_parameterization_forced = CASE WHEN is_parameterization_forced = 1 AND @is_parameterization_forced = 0 THEN 1 ELSE @is_parameterization_forced END
	FROM @dbopterrtb
	WHERE id = @cnt_i;
	SET @cnt_i = @cnt_i + 1
END

IF @is_auto_close_on = 1 OR @is_auto_shrink_on = 1 OR @page_verify_option = 1 OR @is_auto_create_stats_on = 1 OR @is_auto_update_stats_on = 1 OR @is_db_chaining_on = 1 OR @is_auto_create_stats_incremental_on = 0 --OR @is_indirect_checkpoint_on = 1
BEGIN
	SELECT 'Database_checks' AS [Category], 'Database_Options' AS [Check], '[WARNING: Some user databases may have Non-optimal_Settings]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Database_Options' AS [Information],
		name AS [Database_Name],
		RTRIM(
			CASE WHEN is_auto_close_on = 1 THEN 'Auto_Close;' ELSE '' END + 
			CASE WHEN is_auto_shrink_on = 1 THEN 'Auto_Shrink;' ELSE '' END +
			CASE WHEN page_verify_option <> 2 THEN 'Page_Verify;' ELSE '' END +
			CASE WHEN is_auto_create_stats_on = 0 THEN 'Auto_Create_Stats;' ELSE '' END +
			CASE WHEN is_auto_update_stats_on = 0 THEN 'Auto_Update_Stats;' ELSE '' END +
			CASE WHEN is_db_chaining_on = 1 THEN 'DB_Chaining;' ELSE '' END +
			--CASE WHEN is_indirect_checkpoint_on = 1 THEN 'Indirect_Checkpoint;' ELSE '' END +
			CASE WHEN is_auto_create_stats_incremental_on = 0 THEN 'Incremental_Stats;' ELSE '' END +
			CASE WHEN is_trustworthy_on = 1 THEN 'Trustworthy_bit;' ELSE '' END +
			CASE WHEN is_parameterization_forced = 1 THEN 'Forced_Parameterization;' ELSE '' END
		) AS [Non-optimal_Settings],
		CASE WHEN is_auto_close_on = 1 THEN 'ON' ELSE 'OFF' END AS [Auto_Close],
		CASE WHEN is_auto_shrink_on = 1 THEN 'ON' ELSE 'OFF' END AS [Auto_Shrink], 
		page_verify_option_desc AS [Page_Verify], 
		CASE WHEN is_auto_create_stats_on = 1 THEN 'ON' ELSE 'OFF' END AS [Auto_Create_Stats],
		CASE WHEN is_auto_update_stats_on = 1 THEN 'ON' ELSE 'OFF' END AS [Auto_Update_Stats], 
		CASE WHEN is_db_chaining_on = 1 THEN 'ON' ELSE 'OFF' END AS [DB_Chaining],
		--CASE WHEN is_indirect_checkpoint_on = 1 THEN 'ON' ELSE 'OFF' END AS [Indirect_Checkpoint], -- Meant just as a warning that Indirect_Checkpoint is ON. Should be OFF in OLTP systems. Check for high Background Writer Pages/sec counter.
		CASE WHEN is_auto_create_stats_incremental_on = 1 THEN 'ON' WHEN is_auto_create_stats_incremental_on = 1 THEN 'NA' ELSE 'OFF' END AS [Incremental_Stats],
		CASE WHEN is_trustworthy_on = 1 THEN 'ON' ELSE 'OFF' END AS [Trustworthy_bit],
		CASE WHEN is_parameterization_forced = 1 THEN 'ON' ELSE 'OFF' END AS [Forced_Parameterization]
	FROM @dbopterrtb
	WHERE is_auto_close_on = 1 OR is_auto_shrink_on = 1 OR page_verify_option <> 2 OR is_db_chaining_on = 1 OR (is_auto_create_stats_on = 0 AND @sqlmajorver >= 12)
		OR is_auto_update_stats_on = 0 OR is_trustworthy_on = 1 OR is_parameterization_forced = 1 OR is_auto_create_stats_incremental_on = 0--OR is_indirect_checkpoint_on = 1;
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Database_Options' AS [Check], '[OK]' AS [Deviation]
END;

IF (SELECT COUNT(*) FROM master.sys.databases (NOLOCK) WHERE is_auto_update_stats_on = 0 AND is_auto_update_stats_async_on = 1) > 0
BEGIN
	SELECT 'Database_checks' AS [Category], 'Database_Options_Disabled_Async_AutoUpdate' AS [Check], '[WARNING: Some databases have Auto_Update_Statistics_Asynchronously ENABLED while Auto_Update_Statistics is DISABLED. If asynch auto statistics update is intended, also enable Auto_Update_Statistics]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Database_Options_Disabled_Async_AutoUpdate' AS [Check], [name] FROM master.sys.databases (NOLOCK) WHERE is_auto_update_stats_on = 0 AND is_auto_update_stats_async_on = 1
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Database_Options_Disabled_Async_AutoUpdate' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Query Store info subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 12
BEGIN
	RAISERROR (N'  |-Starting Query Store info', 10, 1) WITH NOWAIT
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblQStoreInfo'))
	DROP TABLE #tblQStoreInfo;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblQStoreInfo'))
	CREATE TABLE #tblQStoreInfo ([DBName] sysname, Actual_State NVARCHAR(60), Flush_Interval_Sec bigint, Interval_Length_Min bigint, Query_CaptureMode NVARCHAR(60), Max_Storage_Size_MB bigint, Current_Storage_Size_MB bigint);

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE is_query_store_on = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], actual_state_desc, flush_interval_seconds, interval_length_minutes, query_capture_mode_desc, max_storage_size_mb, current_storage_size_mb 
FROM sys.database_query_store_options;'

			BEGIN TRY
				INSERT INTO #tblQStoreInfo
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Query Store subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END
	
	IF (SELECT COUNT([DBName]) FROM #tblQStoreInfo) > 0
	BEGIN
		SELECT 'Information' AS [Category], 'Query_Store' AS [Information], DBName AS [Database_Name],
			Actual_State, Flush_Interval_Sec, Interval_Length_Min, Query_CaptureMode, Max_Storage_Size_MB, Current_Storage_Size_MB
		FROM #tblQStoreInfo
		ORDER BY DBName;
	END
	ELSE
	BEGIN
		SELECT 'Information' AS [Category], 'Query_Store' AS [Information] , '[INFORMATION: No databases have Query Store enabled]' AS [Comment];
	END
END;		

--------------------------------------------------------------------------------------------------------------------------------
-- Automatic Tuning info subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Automatic Tuning info', 10, 1) WITH NOWAIT

IF @sqlmajorver > 13
BEGIN
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblAutoTuningInfo'))
	DROP TABLE #tblAutoTuningInfo;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblAutoTuningInfo'))
	CREATE TABLE #tblAutoTuningInfo ([DBName] sysname, AutoTuning_Option NVARCHAR(128), Desired_State NVARCHAR(60), Actual_State NVARCHAR(60), Desired_diff_Actual_reason NVARCHAR(60));
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;'

			BEGIN TRY
				INSERT INTO #tblAutoTuningInfo
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Automatic Tuning subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END
	
	IF (SELECT COUNT(AutoTuning_Option) FROM #tblAutoTuningInfo) > 0
	BEGIN
		SELECT 'Information' AS [Category], 'Automatic_Tuning' AS [Information], DBName AS [Database_Name],
			AutoTuning_Option, Desired_State, Actual_State, Desired_diff_Actual_reason
		FROM #tblAutoTuningInfo
		ORDER BY DBName;
	END
	ELSE
	BEGIN
		SELECT 'Information' AS [Category], 'Automatic_Tuning' AS [Information] , '[INFORMATION: No databases have Automatic Tuning enabled]' AS [Comment];
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBs with Sparse files subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBs with Sparse files', 10, 1) WITH NOWAIT
-- https://techcommunity.microsoft.com/t5/SQL-Server-Support/Did-your-backup-program-utility-leave-your-SQL-Server-running-in/ba-p/315840
IF (SELECT COUNT(sd.database_id) FROM sys.databases sd INNER JOIN sys.master_files smf ON sd.database_id = smf.database_id WHERE sd.source_database_id IS NULL AND smf.is_sparse = 1) > 0
BEGIN
	SELECT 'Database_checks' AS [Category], 'DB_nonSnap_Sparse' AS [Check], '[WARNING: Sparse files were detected that do not belong to a Database Snapshot. You might also notice unexplained performance degradation when query data from these files]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'DB_nonSnap_Sparse' AS [Information], DB_NAME(sd.database_id) AS database_name, smf.name, smf.physical_name
	FROM sys.databases sd 
	INNER JOIN sys.master_files smf ON sd.database_id = smf.database_id
	WHERE sd.source_database_id IS NULL AND smf.is_sparse = 1
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'DB_nonSnap_Sparse' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBs Autogrow in percentage subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBs Autogrow in percentage', 10, 1) WITH NOWAIT
IF (SELECT COUNT(is_percent_growth) FROM sys.master_files WHERE is_percent_growth = 1) > 0
BEGIN
	SELECT 'Database_checks' AS [Category], 'Percent_Autogrows' AS [Check], '[WARNING: Some database files have a growth ratio set in percentage. Over time, this could lead to uncontrolled disk space allocation and extended time to perform these growths]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Percent_Autogrows' AS [Information], database_id,
		DB_NAME(database_id) AS [Database_Name], 
		mf.name AS [Logical_Name],
		mf.size*8 AS [Current_Size_KB],
		mf.type_desc AS [File_Type],
		mf.[state_desc] AS [File_State],
		CASE WHEN is_percent_growth = 1 THEN 'pct' ELSE 'pages' END AS [Growth_Type],
		CASE WHEN is_percent_growth = 1 THEN mf.growth ELSE mf.growth*8 END AS [Growth_Amount_KB],
		CASE WHEN is_percent_growth = 1 AND mf.growth > 0 THEN ((mf.size*8)*CONVERT(bigint, mf.growth))/100 
			WHEN is_percent_growth = 0 AND mf.growth > 0 THEN mf.growth*8 
			ELSE 0 END AS [Next_Growth_KB],
		CASE WHEN @ifi = 0 AND mf.type = 0 THEN 'Instant File Initialization is disabled'
			WHEN @ifi = 1 AND mf.type = 0 THEN 'Instant File Initialization is enabled'
			ELSE '' END AS [Comments],
		mf.is_read_only
	FROM sys.master_files mf (NOLOCK)
	WHERE is_percent_growth = 1
	GROUP BY database_id, mf.name, mf.size, is_percent_growth, mf.growth, mf.type_desc, mf.[type], mf.[state_desc], mf.is_read_only
	ORDER BY DB_NAME(mf.database_id), mf.name
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Percent_Autogrows' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBs Autogrowth > 1GB in Logs or Data (when IFI is disabled) subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBs Autogrowth > 1GB in Logs or Data (when IFI is disabled)', 10, 1) WITH NOWAIT
IF (SELECT COUNT(growth) FROM sys.master_files (NOLOCK)
	WHERE [type] >= CASE WHEN @ifi = 1 THEN 1 ELSE 0 END 
		AND [type] < 2 
		AND ((is_percent_growth = 1 AND ((CONVERT(bigint,size)*8)*growth)/100 > 1048576) 
		OR (is_percent_growth = 0 AND growth*8 > 1048576))) > 0
BEGIN
	SELECT 'Database_checks' AS [Category], 'Large_Autogrows' AS [Check], '[WARNING: Some database files have set growth over 1GB. This could lead to extended growth times, slowing down your system]' AS [Deviation]
	SELECT 'Database_checks' AS [Category], 'Large_Autogrows' AS [Information], database_id,
		DB_NAME(database_id) AS [Database_Name], 
		mf.name AS [Logical_Name],
		mf.size*8 AS [Current_Size_KB],
		mf.[type_desc] AS [File_Type],
		mf.[state_desc] AS [File_State],
		CASE WHEN is_percent_growth = 1 THEN 'pct' ELSE 'pages' END AS [Growth_Type],
		CASE WHEN is_percent_growth = 1 THEN mf.growth ELSE mf.growth*8 END AS [Growth_Amount],
		CASE WHEN is_percent_growth = 1 AND mf.growth > 0 THEN ((CONVERT(bigint,mf.size)*8)*mf.growth)/100 
			WHEN is_percent_growth = 0 AND mf.growth > 0 THEN mf.growth*8 
			ELSE 0 END AS [Next_Growth_KB],
		CASE WHEN @ifi = 0 AND mf.type = 0 THEN 'Instant File Initialization is disabled'
			WHEN @ifi = 1 AND mf.type = 0 THEN 'Instant File Initialization is enabled'
			ELSE '' END AS [Comments],
		mf.is_read_only
	FROM sys.master_files mf (NOLOCK)
	WHERE mf.[type] >= CASE WHEN @ifi = 1 THEN 1 ELSE 0 END 
		AND mf.[type] < 2
		AND ((is_percent_growth = 1 AND ((CONVERT(bigint,mf.size)*8)*mf.growth)/100 > 1048576) 
			OR (is_percent_growth = 0 AND mf.growth*8 > 1048576))
	GROUP BY database_id, mf.name, mf.size, is_percent_growth, mf.growth, mf.[type_desc], mf.[type], mf.[state_desc], mf.is_read_only
	ORDER BY DB_NAME(mf.database_id), mf.name
END
ELSE
BEGIN
	SELECT 'Database_checks' AS [Category], 'Large_Autogrows' AS [Check], '[OK]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- VLF subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting VLF', 10, 1) WITH NOWAIT
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1
BEGIN
	DECLARE /*@dbid int,*/ @query NVARCHAR(1000)/*, @dbname VARCHAR(1000)*/, @count int, @count_used int, @logsize DECIMAL(20,1), @usedlogsize DECIMAL(20,1), @avgvlfsize DECIMAL(20,1)
	DECLARE @potsize DECIMAL(20,1), @n_iter int, @n_iter_final int, @initgrow DECIMAL(20,1), @n_init_iter int

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info1'))
	DROP TABLE #log_info1;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info1'))
	CREATE TABLE #log_info1 (dbname NVARCHAR(100), 
		Current_log_size_MB DECIMAL(20,1), 
		Used_Log_size_MB DECIMAL(20,1),
		Potential_log_size_MB DECIMAL(20,1), 
		Current_VLFs int,
		Used_VLFs int,
		Avg_VLF_size_KB DECIMAL(20,1),
		Potential_VLFs int, 
		Growth_iterations int,
		Log_Initial_size_MB DECIMAL(20,1),
		File_autogrow_MB DECIMAL(20,1))
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info2'))
	DROP TABLE #log_info2;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info2'))
	CREATE TABLE #log_info2 (dbname NVARCHAR(100), 
		Current_VLFs int, 
		VLF_size_KB DECIMAL(20,1), 
		growth_iteration int)
		
	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;

	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0

			IF (SELECT CHARINDEX(CHAR(39), @dbname)) > 0
				OR (SELECT CHARINDEX(CHAR(45), @dbname)) > 0
				OR (SELECT CHARINDEX(CHAR(47), @dbname)) > 0
			BEGIN
				SELECT @ErrorMessage = '    |-Skipping Database ID ' + CONVERT(NVARCHAR, DB_ID(QUOTENAME(@dbname))) + ' due to potential of SQL Injection'
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT;
			END
			ELSE
			BEGIN
				IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info3'))
				DROP TABLE #log_info3;
				IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info3'))
				CREATE TABLE #log_info3 (recoveryunitid int NULL,
					fileid tinyint,
					file_size bigint,
					start_offset bigint,
					FSeqNo int,
					[status] tinyint,
					parity tinyint,
					create_lsn numeric(25,0))
				SET @query = N'DBCC LOGINFO (N''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + N''') WITH NO_INFOMSGS'

				IF @sqlmajorver < 11
				BEGIN
					INSERT INTO #log_info3 (fileid, file_size, start_offset, FSeqNo, [status], parity, create_lsn)
					EXEC (@query)
				END
				ELSE
				BEGIN
					INSERT INTO #log_info3 (recoveryunitid, fileid, file_size, start_offset, FSeqNo, [status], parity, create_lsn)
					EXEC (@query)
				END

				SET @count = @@ROWCOUNT
				SET @count_used = (SELECT COUNT(fileid) FROM #log_info3 l WHERE l.[status] = 2)
				SET @logsize = (SELECT (MIN(l.start_offset) + SUM(l.file_size))/1048576.00 FROM #log_info3 l)
				SET @usedlogsize = (SELECT (MIN(l.start_offset) + SUM(CASE WHEN l.status <> 0 THEN l.file_size ELSE 0 END))/1048576.00 FROM #log_info3 l)
				SET @avgvlfsize = (SELECT AVG(l.file_size)/1024.00 FROM #log_info3 l)

				INSERT INTO #log_info2
				SELECT @dbname, COUNT(create_lsn), MIN(l.file_size)/1024.00,
					ROW_NUMBER() OVER(ORDER BY l.create_lsn) FROM #log_info3 l 
				GROUP BY l.create_lsn 
				ORDER BY l.create_lsn

				DROP TABLE #log_info3;

				-- Grow logs in MB instead of GB because of known issue prior to SQL 2012.
				-- More detail here: http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
				-- and http://connect.microsoft.com/SQLServer/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
				-- or https://connect.microsoft.com/SQLServer/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb
				IF @sqlmajorver >= 11
				BEGIN
					SET @n_iter = (SELECT CASE WHEN @logsize <= 64 THEN 1
						WHEN @logsize > 64 AND @logsize < 256 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/256, 0)
						WHEN @logsize >= 256 AND @logsize < 1024 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/512, 0)
						WHEN @logsize >= 1024 AND @logsize < 4096 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/1024, 0)
						WHEN @logsize >= 4096 AND @logsize < 8192 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/2048, 0)
						WHEN @logsize >= 8192 AND @logsize < 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/4096, 0)
						WHEN @logsize >= 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/8192, 0)
						END)
					SET @potsize = (SELECT CASE WHEN @logsize <= 64 THEN 1*64
						WHEN @logsize > 64 AND @logsize < 256 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/256, 0)*256
						WHEN @logsize >= 256 AND @logsize < 1024 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/512, 0)*512
						WHEN @logsize >= 1024 AND @logsize < 4096 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/1024, 0)*1024
						WHEN @logsize >= 4096 AND @logsize < 8192 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/2048, 0)*2048
						WHEN @logsize >= 8192 AND @logsize < 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/4096, 0)*4096
						WHEN @logsize >= 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/8192, 0)*8192
						END)
				END
				ELSE
				BEGIN
					SET @n_iter = (SELECT CASE WHEN @logsize <= 64 THEN 1
						WHEN @logsize > 64 AND @logsize < 256 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/256, 0)
						WHEN @logsize >= 256 AND @logsize < 1024 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/512, 0)
						WHEN @logsize >= 1024 AND @logsize < 4096 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/1024, 0)
						WHEN @logsize >= 4096 AND @logsize < 8192 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/2048, 0)
						WHEN @logsize >= 8192 AND @logsize < 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/4000, 0)
						WHEN @logsize >= 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/8000, 0)
						END)
					SET @potsize = (SELECT CASE WHEN @logsize <= 64 THEN 1*64
						WHEN @logsize > 64 AND @logsize < 256 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/256, 0)*256
						WHEN @logsize >= 256 AND @logsize < 1024 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/512, 0)*512
						WHEN @logsize >= 1024 AND @logsize < 4096 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/1024, 0)*1024
						WHEN @logsize >= 4096 AND @logsize < 8192 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/2048, 0)*2048
						WHEN @logsize >= 8192 AND @logsize < 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/4000, 0)*4000
						WHEN @logsize >= 16384 THEN ROUND(CONVERT(FLOAT, ROUND(@logsize, -2))/8000, 0)*8000
						END)
				END
			
				-- If the proposed log size is smaller than current log, and also smaller than 4GB,
				-- and there is less than 512MB of diff between the current size and proposed size, add 1 grow.
				SET @n_iter_final = @n_iter
				IF @logsize > @potsize AND @potsize <= 4096 AND ABS(@logsize - @potsize) < 512
				BEGIN
					SET @n_iter_final = @n_iter + 1
				END
				-- If the proposed log size is larger than current log, and also larger than 50GB, 
				-- and there is less than 1GB of diff between the current size and proposed size, take 1 grow.
				ELSE IF @logsize < @potsize AND @potsize <= 51200 AND ABS(@logsize - @potsize) > 1024
				BEGIN
					SET @n_iter_final = @n_iter - 1
				END

				IF @potsize = 0 
				BEGIN 
					SET @potsize = 64 
				END
				IF @n_iter = 0 
				BEGIN 
					SET @n_iter = 1
				END
			
				SET @potsize = (SELECT CASE WHEN @n_iter < @n_iter_final THEN @potsize + (@potsize/@n_iter) 
						WHEN @n_iter > @n_iter_final THEN @potsize - (@potsize/@n_iter) 
						ELSE @potsize END)
			
				SET @n_init_iter = @n_iter_final
				IF @potsize >= 8192
				BEGIN
					SET @initgrow = @potsize/@n_iter_final
				END
				IF @potsize >= 64 AND @potsize <= 512
				BEGIN
					SET @n_init_iter = 1
					SET @initgrow = 512
				END
				IF @potsize > 512 AND @potsize <= 1024
				BEGIN
					SET @n_init_iter = 1
					SET @initgrow = 1023
				END
				IF @potsize > 1024 AND @potsize < 8192
				BEGIN
					SET @n_init_iter = 1
					SET @initgrow = @potsize
				END

				INSERT INTO #log_info1
				VALUES(@dbname, @logsize, @usedlogsize, @potsize, @count, @count_used, @avgvlfsize, 
					CASE WHEN @potsize <= 64 THEN (@potsize/(@potsize/@n_init_iter))*4
						WHEN @potsize > 64 AND @potsize < 1024 THEN (@potsize/(@potsize/@n_init_iter))*8
						WHEN @potsize >= 1024 THEN (@potsize/(@potsize/@n_init_iter))*16
						END,
					@n_init_iter, @initgrow, 
					CASE WHEN (@potsize/@n_iter_final) <= 1024 THEN (@potsize/@n_iter_final) ELSE 1024 END
					);
			END;

			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;

	IF (SELECT COUNT(dbname) FROM #log_info1 WHERE Current_VLFs >= 50) > 0
	BEGIN
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files' AS [Check], '[WARNING: Some user databases have many VLFs. Please review these]' AS [Deviation]
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files' AS [Information], dbname AS [Database_Name], Current_log_size_MB, Used_Log_size_MB,
			Potential_log_size_MB, Current_VLFs, Used_VLFs, Potential_VLFs, Growth_iterations, Log_Initial_size_MB, File_autogrow_MB
		FROM #log_info1
		WHERE Current_VLFs >= 50 -- My rule of thumb is 50 VLFs. Your mileage may vary.
		ORDER BY dbname;
		
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files_per_growth' AS [Information], #log_info2.dbname AS [Database_Name], #log_info2.Current_VLFs AS VLFs_remain_per_spawn, VLF_size_KB, growth_iteration
		FROM #log_info2
		INNER JOIN #log_info1 ON #log_info2.dbname = #log_info1.dbname
		WHERE #log_info1.Current_VLFs >= 50 -- My rule of thumb is 50 VLFs. Your mileage may vary.
		ORDER BY #log_info2.dbname, growth_iteration

		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files_agg_per_size' AS [Information], #log_info2.dbname AS [Database_Name], SUM(#log_info2.Current_VLFs) AS VLFs_per_size, VLF_size_KB
		FROM #log_info2
		INNER JOIN #log_info1 ON #log_info2.dbname = #log_info1.dbname
		WHERE #log_info1.Current_VLFs >= 50 -- My rule of thumb is 50 VLFs. Your mileage may vary.
		GROUP BY #log_info2.dbname, VLF_size_KB
		ORDER BY #log_info2.dbname, VLF_size_KB DESC
	END
	ELSE
	BEGIN
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files' AS [Check], '[OK]' AS [Deviation]

		/*
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files' AS [Information], dbname AS [Database_Name], Current_log_size_MB, Used_Log_size_MB, Current_VLFs, Used_VLFs
		FROM #log_info1
		ORDER BY dbname;
		
		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files_per_growth' AS [Information], dbname AS [Database_Name], Current_VLFs AS VLFs_remain_per_spawn, VLF_size_KB, growth_iteration
		FROM #log_info2
		ORDER BY dbname, growth_iteration

		SELECT 'Database_checks' AS [Category], 'Virtual_Log_Files_agg_per_size' AS [Information], dbname AS [Database_Name], SUM(Current_VLFs) AS VLFs_per_size, VLF_size_KB
		FROM #log_info2
		GROUP BY dbname, VLF_size_KB
		ORDER BY dbname, VLF_size_KB DESC
		*/
	END
END
ELSE
BEGIN
	RAISERROR('[WARNING: Only a sysadmin can run the "VLF" check. Bypassing check]', 16, 1, N'sysadmin')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Data files and Logs / tempDB and user Databases / Backups and Database files in same volume (Mountpoint aware) subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Data files and Logs / tempDB and user Databases / Backups and Database files in same volume (Mountpoint aware)', 10, 1) WITH NOWAIT
IF @allow_xpcmdshell = 1
BEGIN
	DECLARE /*@dbid int,*/ @ctr2 int, @ctr3 int, @ctr4 int, @pserr bit
	SET @pserr = 0
	IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
	OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
		AND (SELECT COUNT(credential_id) FROM sys.credentials WHERE name = '##xp_cmdshell_proxy_account##') > 0) -- Is not sysadmin but proxy account exists
		AND (SELECT COUNT(l.name)
		FROM sys.server_permissions p (NOLOCK) INNER JOIN sys.server_principals l (NOLOCK)
		ON p.grantee_principal_id = l.principal_id
			AND p.class = 100 -- Server
			AND p.state IN ('G', 'W') -- Granted or Granted with Grant
			AND l.is_disabled = 0
			AND p.permission_name = 'ALTER SETTINGS'
			AND QUOTENAME(l.name) = QUOTENAME(USER_NAME())) = 0) -- Is not sysadmin but has alter settings permission 
	OR ((ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1 
		AND ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_fileexist') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_instance_regread') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regread') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OAGetErrorInfo') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OACreate') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_OADestroy') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_cmdshell') > 0 AND
		(SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_regenumvalues') > 0)))
	BEGIN
		IF @sqlmajorver < 11 OR (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild <= 2500)
		BEGIN
			DECLARE @pstbl TABLE ([KeyExist] int)
			BEGIN TRY
				INSERT INTO @pstbl
				EXEC master.sys.xp_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\PowerShell\1' -- check if Powershell is installed
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Data files and Logs in same volume (Mountpoint aware) subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH

			SELECT @sao = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'show advanced options'
			SELECT @xcmd = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'xp_cmdshell'
			SELECT @ole = CAST([value] AS smallint) FROM sys.configurations (NOLOCK) WHERE [name] = 'Ole Automation Procedures'

			RAISERROR ('  |-Configuration options set for Data and Log location check', 10, 1) WITH NOWAIT
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE WITH OVERRIDE;
			END
		
			IF (SELECT [KeyExist] FROM @pstbl) = 1
			BEGIN
				DECLARE @ctr int
				DECLARE @output_hw_tot TABLE ([PS_OUTPUT] NVARCHAR(2048));
				DECLARE @output_hw_format TABLE ([volid] smallint IDENTITY(1,1), [HD_Volume] NVARCHAR(2048) NULL)
				
				IF @custompath IS NULL
				BEGIN
					IF @sqlmajorver < 11
					BEGIN
						EXEC master..xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\Setup',N'SQLPath', @path OUTPUT
						SET @path = @path + '\LOG'
					END
					ELSE
					BEGIN
						SET @sqlcmd = N'SELECT @pathOUT = LEFT([path], LEN([path])-1) FROM sys.dm_os_server_diagnostics_log_configurations';
						SET @params = N'@pathOUT NVARCHAR(2048) OUTPUT';
						EXECUTE sp_executesql @sqlcmd, @params, @pathOUT=@path OUTPUT;
					END
					
					-- Create COM object with FSO
					EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FSO OUT
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END
					ELSE
					BEGIN
						EXEC @OLEResult = master.dbo.sp_OAMethod @FSO, 'FolderExists', @existout OUT, @path
						IF @OLEResult <> 0
						BEGIN
							EXEC sp_OAGetErrorInfo @FSO, @src OUT, @desc OUT
							SELECT @ErrorMessage = 'Error Calling FolderExists Method 0x%x, %s, %s'
							RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
						END
						ELSE
						BEGIN
							IF @existout <> 1
							BEGIN
								SET @path = CONVERT(NVARCHAR(500), SERVERPROPERTY('ErrorLogFileName'))
								SET @path = LEFT(@path,LEN(@path)-CHARINDEX('\', REVERSE(@path)))
							END 
						END
						EXEC @OLEResult = sp_OADestroy @FSO
					END
				END
				ELSE
				BEGIN
					SELECT @path = CASE WHEN @custompath LIKE '%\' THEN LEFT(@custompath, LEN(@custompath)-1) ELSE @custompath END
				END
				
				SET @FileName = @path + '\checkbp_' + RTRIM(@server) + '.ps1'
				
				EXEC master.dbo.xp_fileexist @FileName, @existout out
				IF @existout = 0
				BEGIN 
					-- Scan for local disks
					SET @Text1 = '[string] $serverName = ''localhost''
$vols = Get-WmiObject -computername $serverName -query "select Name from Win32_Volume where Capacity <> NULL and DriveType = 3"
foreach($vol in $vols)
{
	[string] $drive = "{0}" -f $vol.name
	Write-Output $drive
}'
					-- Create COM object with FSO
					EXEC @OLEResult = master.dbo.sp_OACreate 'Scripting.FileSystemObject', @FS OUT
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Creating COM Component 0x%x, %s, %s'
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END

					--Open file
					EXEC @OLEResult = master.dbo.sp_OAMethod @FS, 'OpenTextFile', @FileID OUT, @FileName, 2, 1
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Calling OpenTextFile Method 0x%x, %s, %s' + CHAR(10) + 'Could not create file ' + @FileName
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END
					ELSE
					BEGIN
						SELECT @ErrorMessage = '    |-Created file ' + @FileName
						RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
					END

					--Write Text1
					EXEC @OLEResult = master.dbo.sp_OAMethod @FileID, 'WriteLine', NULL, @Text1
					IF @OLEResult <> 0
					BEGIN
						EXEC sp_OAGetErrorInfo @FS, @src OUT, @desc OUT
						SELECT @ErrorMessage = 'Error Calling WriteLine Method 0x%x, %s, %s' + CHAR(10) + 'Could not write to file ' + @FileName
						RAISERROR (@ErrorMessage, 16, 1, @OLEResult, @src, @desc);
					END

					EXEC @OLEResult = sp_OADestroy @FileID
					EXEC @OLEResult = sp_OADestroy @FS
				END;
				ELSE
				BEGIN
					SELECT @ErrorMessage = '    |-Reusing file ' + @FileName
					RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
				END

				IF @psver = 1
				BEGIN
					SET @CMD = 'powershell -NoLogo -NoProfile "' + @FileName + '" -ExecutionPolicy RemoteSigned'
				END
				ELSE
				BEGIN
					SET @CMD = 'powershell -NoLogo -NoProfile -File "' + @FileName + '" -ExecutionPolicy RemoteSigned'
				END;

				INSERT INTO @output_hw_tot 
				EXEC master.dbo.xp_cmdshell @CMD

				SET @CMD = 'del /Q "' + @FileName + '"'
				EXEC master.dbo.xp_cmdshell @CMD, NO_OUTPUT

				IF (SELECT COUNT([PS_OUTPUT]) 
				FROM @output_hw_tot WHERE [PS_OUTPUT] LIKE '%cannot be loaded because%'
					OR [PS_OUTPUT] LIKE '%scripts is disabled%'
					OR [PS_OUTPUT] LIKE '%scripts est désactivée%') = 0
				BEGIN
					INSERT INTO @output_hw_format ([HD_Volume])
					SELECT RTRIM([PS_OUTPUT]) 
					FROM @output_hw_tot 
					WHERE [PS_OUTPUT] IS NOT NULL
				END
				ELSE
				BEGIN
					SET @pserr = 1
					RAISERROR ('[WARNING: Powershell script cannot be loaded because the execution of scripts is disabled on this system.
To change the execution policy, type the following command in Powershell console: Set-ExecutionPolicy RemoteSigned
The Set-ExecutionPolicy cmdlet enables you to determine which Windows PowerShell scripts (if any) will be allowed to run on your computer. 
Windows PowerShell has four different execution policies:
	Restricted - No scripts can be run. Windows PowerShell can be used only in interactive mode.
	AllSigned - Only scripts signed by a trusted publisher can be run.
	RemoteSigned - Downloaded scripts must be signed by a trusted publisher before they can be run.
		|- REQUIRED by BP Check
	Unrestricted - No restrictions; all Windows PowerShell scripts can be run.]
',16,1);
				END
		
				SET @CMD2 = 'del ' + @FileName
				EXEC master.dbo.xp_cmdshell @CMD2, NO_OUTPUT;
			END
			ELSE
			BEGIN
				SET @pserr = 1
				RAISERROR ('[WARNING: Powershell is not present. Bypassing Data files and Logs in same volume check]',16,1);
			END
			
			IF @xcmd = 0
			BEGIN
				EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @ole = 0
			BEGIN
				EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE WITH OVERRIDE;
			END
			IF @sao = 0
			BEGIN
				EXEC sp_configure 'show advanced options', 0; RECONFIGURE WITH OVERRIDE;
			END
		END
		ELSE
		BEGIN
			INSERT INTO @output_hw_format ([HD_Volume])
			EXEC ('SELECT DISTINCT(volume_mount_point) FROM sys.master_files mf CROSS APPLY sys.dm_os_volume_stats (database_id, [file_id]) WHERE mf.[file_id] < 65537')
		END;

		IF @pserr = 0
		BEGIN
			-- select mountpoints only
			DECLARE @intertbl TABLE (physical_name nvarchar(260))
			INSERT INTO @intertbl
			SELECT physical_name
			FROM sys.master_files t1 (NOLOCK) 
			INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE ([database_id] > 4 OR [database_id] = 2)
				AND [database_id] <> 32767 AND LEN(t2.HD_Volume) > 3

			-- select database files in mountpoints		
			DECLARE @filetbl TABLE (database_id int, type tinyint, file_id int, physical_name nvarchar(260), volid smallint)
			INSERT INTO @filetbl
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) 
			INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE ([database_id] > 4 OR [database_id] = 2) AND [database_id] <> 32767 AND LEN(t2.HD_Volume) > 3
			UNION ALL
			-- select database files not in mountpoints
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) 
			INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE ([database_id] > 4 OR [database_id] = 2) AND [database_id] <> 32767 AND physical_name NOT IN (SELECT physical_name FROM @intertbl)
				
			SELECT @ctr = COUNT(DISTINCT(t1.[database_id])) FROM @filetbl t1 
			INNER JOIN @filetbl t2 ON t1.database_id = t2.database_id
				AND t1.[type] <> t2.[type]
				AND ((t1.[type] = 1 AND t2.[type] <> 1) OR (t2.[type] = 1 AND t1.[type] <> 1))
				AND t1.volid = t2.volid;

			IF @ctr > 0
			BEGIN
				SELECT 'Database_checks' AS [Category], 'Data_and_Log_locations' AS [Check], '[WARNING: Some user databases have Data and Log files in the same physical volume]' AS [Deviation]
				SELECT DISTINCT 'Database_checks' AS [Category], 'Data_and_Log_locations' AS [Information], DB_NAME(mf.[database_id]) AS [Database_Name], type_desc AS [Type], mf.physical_name
				FROM sys.master_files mf (NOLOCK) INNER JOIN @filetbl t1 ON mf.database_id = t1.database_id AND mf.physical_name = t1.physical_name
					INNER JOIN @filetbl t2 ON t1.database_id = t2.database_id
						AND t1.[type] <> t2.[type]
						AND ((t1.[type] = 1 AND t2.[type] <> 1) OR (t2.[type] = 1 AND t1.[type] <> 1))
						AND t1.volid = t2.volid
				ORDER BY mf.physical_name OPTION (RECOMPILE);
			END
			ELSE
			BEGIN
				SELECT 'Database_checks' AS [Category], 'Data_and_Log_locations' AS [Check], '[OK]' AS [Deviation]
			END;

			-- select backup mountpoints only
			DECLARE @interbcktbl TABLE (physical_device_name nvarchar(260))
			INSERT INTO @interbcktbl
			SELECT physical_device_name
			FROM msdb.dbo.backupmediafamily t1 (NOLOCK) 
			INNER JOIN @output_hw_format t2 ON LEFT(physical_device_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE LEN(t2.HD_Volume) > 3

			-- select backups in mountpoints only
			DECLARE @bcktbl TABLE (physical_device_name nvarchar(260), HD_Volume nvarchar(260))
			INSERT INTO @bcktbl
			SELECT physical_device_name, RTRIM(t2.HD_Volume)
			FROM msdb.dbo.backupmediafamily t1 (NOLOCK) 
			INNER JOIN @output_hw_format t2 ON LEFT(physical_device_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE LEN(t2.HD_Volume) > 3
			-- select backups not in mountpoints
			UNION ALL
			SELECT physical_device_name, RTRIM(t2.HD_Volume)
			FROM msdb.dbo.backupmediafamily t1 (NOLOCK)
			INNER JOIN @output_hw_format t2 ON LEFT(physical_device_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE physical_device_name NOT IN (SELECT physical_device_name FROM @interbcktbl);

			SELECT @ctr4 = COUNT(DISTINCT(physical_device_name)) FROM @bcktbl;

			IF @ctr4 > 0
			BEGIN
				SELECT 'Database_checks' AS [Category], 'Backup_and_Database_locations' AS [Check], '[WARNING: Some backups and database files are in the same physical volume]' AS [Deviation]
				SELECT DISTINCT 'Database_checks' AS [Category], 'Backup_and_Database_locations' AS [Information], physical_device_name AS [Backup_Location], HD_Volume AS [Volume_with_DB_Files]
				FROM @bcktbl
				OPTION (RECOMPILE);
			END
			ELSE
			BEGIN
				SELECT 'Database_checks' AS [Category], 'Backup_and_Database_locations' AS [Check], '[OK]' AS [Deviation]
			END;

			-- select tempDB mountpoints only
			DECLARE @intertbl2 TABLE (physical_name nvarchar(260))
			INSERT INTO @intertbl2
			SELECT physical_name
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2
			ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] = 2 AND LEN(t2.HD_Volume) > 3 AND [type] = 0
			
			-- select user DBs mountpoints only
			DECLARE @intertbl3 TABLE (physical_name nvarchar(260))
			INSERT INTO @intertbl3
			SELECT physical_name
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2
			ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] > 4 AND [database_id] <> 32767 AND LEN(t2.HD_Volume) > 3 AND [type] = 0
			
			-- select tempDB files in mountpoints		
			DECLARE @tempDBtbl TABLE (database_id int, type tinyint, file_id int, physical_name nvarchar(260), volid smallint)
			INSERT INTO @tempDBtbl
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] = 2 AND LEN(t2.HD_Volume) > 3 AND [type] = 0
			UNION ALL
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] = 2 AND [type] = 0 AND physical_name NOT IN (SELECT physical_name FROM @intertbl2)

			-- select user DBs files in mountpoints		
			DECLARE @otherstbl TABLE (database_id int, type tinyint, file_id int, physical_name nvarchar(260), volid smallint)
			INSERT INTO @otherstbl
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] > 4 AND [database_id] <> 32767 AND LEN(t2.HD_Volume) > 3 AND [type] = 0
			UNION ALL
			SELECT database_id, type, file_id, physical_name, volid
			FROM sys.master_files t1 (NOLOCK) INNER JOIN @output_hw_format t2 ON LEFT(physical_name, LEN(t2.HD_Volume)) = RTRIM(t2.HD_Volume)
			WHERE [database_id] > 4 AND [database_id] <> 32767 AND [type] = 0 AND physical_name NOT IN (SELECT physical_name FROM @intertbl3)

			SELECT @ctr2 = COUNT(*) FROM @tempDBtbl WHERE LEFT(physical_name, 1) = 'C'

			SELECT @ctr3 = COUNT(DISTINCT(t1.[database_id])) FROM @otherstbl t1 INNER JOIN @tempDBtbl t2 ON t1.volid = t2.volid;

			IF @ctr3 > 0
			BEGIN
				SELECT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Check], '[WARNING: tempDB is on the same physical volume as user databases]' AS [Deviation];
			END
			ELSE IF @ctr2 > 0
			BEGIN
				SELECT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Check], '[WARNING: tempDB is on C: drive]' AS [Deviation]
			END
			ELSE
			BEGIN
				SELECT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Check], '[OK]' AS [Deviation]
			END;
			
			IF @ctr2 > 0 OR @ctr3 > 0
			BEGIN
				SELECT DISTINCT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Information], DB_NAME(mf.[database_id]) AS [Database_Name], type_desc AS [Type], mf.physical_name
				FROM sys.master_files mf (NOLOCK) INNER JOIN @otherstbl t1 ON mf.database_id = t1.database_id AND mf.physical_name = t1.physical_name
					INNER JOIN @tempDBtbl t2 ON t1.volid = t2.volid
				UNION ALL
				SELECT DISTINCT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Information], DB_NAME(mf.[database_id]) AS [Database_Name], type_desc AS [Type], mf.physical_name
				FROM sys.master_files mf (NOLOCK) INNER JOIN @tempDBtbl t1 ON mf.database_id = t1.database_id AND mf.physical_name = t1.physical_name
				ORDER BY DB_NAME(mf.[database_id]) OPTION (RECOMPILE);
			END
		END
		ELSE
		BEGIN
			SELECT 'Database_checks' AS [Category], 'Data_and_Log_locations' AS [Check], '[WARNING: Could not gather information on file locations]' AS [Deviation]
			SELECT 'tempDB_checks' AS [Category], 'tempDB_location' AS [Check], '[WARNING: Could not gather information on file locations]' AS [Deviation]
		END
	END
	ELSE
	BEGIN
		RAISERROR('[WARNING: Only a sysadmin can run the "Data files and Logs / tempDB and user Databases in same volume" checks. A regular user can also run this check if a xp_cmdshell proxy account exists. Bypassing check]', 16, 1, N'xp_cmdshellproxy')
		RAISERROR('[WARNING: If not sysadmin, then must be a granted EXECUTE permissions on the following extended sprocs to run checks: sp_OACreate, sp_OADestroy, sp_OAGetErrorInfo, xp_cmdshell, xp_instance_regread, xp_regread, xp_fileexist and xp_regenumvalues. Bypassing check]', 16, 1, N'extended_sprocs')
		--RETURN
	END
END
ELSE
BEGIN
	RAISERROR('    |- [INFORMATION: "Data files and Logs / tempDB and user Databases in same volume" check was skipped because xp_cmdshell was not allowed]', 10, 1, N'disallow_xp_cmdshell')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- tempDB data file configurations subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting tempDB data file configurations', 10, 1) WITH NOWAIT
DECLARE @tdb_files int, @online_count int, @filesizes smallint
SELECT @tdb_files = COUNT(physical_name) FROM sys.master_files (NOLOCK) WHERE database_id = 2 AND [type] = 0;
SELECT @online_count = COUNT(cpu_id) FROM sys.dm_os_schedulers WHERE is_online = 1 AND scheduler_id < 255 AND parent_node_id < 64;
SELECT @filesizes = COUNT(DISTINCT size) FROM tempdb.sys.database_files WHERE [type] = 0;

IF (SELECT CASE WHEN @filesizes = 1 AND ((@tdb_files >= 4 AND @tdb_files <= 8 AND @tdb_files % 4 = 0) /*OR (@tdb_files >= 8 AND @tdb_files % 4 = 0)*/ 
	OR (@tdb_files >= (@online_count / 2) AND @tdb_files >= 8 AND @tdb_files % 4 = 0)) THEN 0 ELSE 1 END) = 0
BEGIN
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files' AS [Check], '[OK]' AS [Deviation]
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files' AS [Information], physical_name AS [tempDB_Files], CAST((size*8)/1024.0 AS DECIMAL(18,2)) AS [File_Size_MB]
	FROM tempdb.sys.database_files (NOLOCK)
	WHERE type = 0;
END
ELSE 
BEGIN
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files' AS [Check], 
		CASE WHEN @tdb_files < 4 THEN '[WARNING: tempDB has only ' + CONVERT(VARCHAR(10), @tdb_files) + ' file(s). Consider creating between 4 and 8 tempDB data files of the same size, with a minimum of 4]'
			WHEN @filesizes = 1 AND @tdb_files < (@online_count / 2) AND @tdb_files >= 8 AND @tdb_files % 4 = 0 THEN '[INFORMATION: Number of Data files to Scheduler ratio might not be Optimal. Consider creating 1 data file per each 2 cores, in multiples of 4, all of the same size]'
			WHEN @filesizes > 1 AND @tdb_files >= 4 AND @tdb_files % 4 > 0 THEN '[WARNING: Data file sizes do not match and Number of data files is not multiple of 4]'
			WHEN @filesizes = 1 AND @tdb_files >= 4 AND @tdb_files % 4 > 0 THEN '[WARNING: Number of data files is not multiple of 4]'
			WHEN @filesizes > 1 AND @tdb_files >= 4 AND @tdb_files % 4 = 0 THEN '[WARNING: Data file sizes do not match]'
			ELSE '[OK]' END AS [Deviation];
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files' AS [Information], physical_name AS [tempDB_Files], CAST((size*8)/1024.0 AS DECIMAL(18,2)) AS [File_Size_MB]
	FROM tempdb.sys.database_files (NOLOCK)
	WHERE type = 0;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- tempDB data files autogrow of equal size subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting tempDB Files autogrow of equal size', 10, 1) WITH NOWAIT
IF (SELECT COUNT(DISTINCT growth) FROM sys.master_files WHERE [database_id] = 2 AND [type] = 0) > 1
	OR (SELECT COUNT(DISTINCT is_percent_growth) FROM sys.master_files WHERE [database_id] = 2 AND [type] = 0) > 1
BEGIN
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files_Autogrow' AS [Check], '[WARNING: Some tempDB data files have different growth settings]' AS [Deviation]
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files_Autogrow' AS [Information], 
		DB_NAME(2) AS [Database_Name], 
		mf.name AS [Logical_Name],
		mf.[size]*8 AS [Current_Size_KB],
		mf.type_desc AS [File_Type],
		CASE WHEN is_percent_growth = 1 THEN 'pct' ELSE 'pages' END AS [Growth_Type],
		CASE WHEN is_percent_growth = 1 THEN mf.growth ELSE mf.growth*8 END AS [Growth_Amount],
		CASE WHEN is_percent_growth = 1 AND mf.growth > 0 THEN ((mf.size*8)*CONVERT(bigint, mf.growth))/100 
			WHEN is_percent_growth = 0 AND mf.growth > 0 THEN mf.growth*8 
			ELSE 0 END AS [Next_Growth_KB],
		CASE WHEN @ifi = 0 AND mf.type = 0 THEN 'Instant File Initialization is disabled'
			WHEN @ifi = 1 AND mf.type = 0 THEN 'Instant File Initialization is enabled'
			ELSE '' END AS [Comments]
	FROM tempdb.sys.database_files mf (NOLOCK)
	WHERE [type] = 0
	GROUP BY mf.name, mf.[size], is_percent_growth, mf.growth, mf.type_desc, mf.[type]
	ORDER BY 3, 4
END
ELSE
BEGIN
	SELECT 'tempDB_checks' AS [Category], 'tempDB_files_Autogrow' AS [Check], '[OK]' AS [Deviation]
END;

IF @ptochecks = 1
RAISERROR (N'|-Starting Performance Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Perf counters, Waits, Latches and Spinlocks subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	SELECT @ErrorMessage = '  |-Starting Perf counters, Waits and Latches (wait for ' + CONVERT(VARCHAR(3), @duration) + 's)'
	RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT
	DECLARE @minctr DATETIME, @maxctr DATETIME, @durationstr NVARCHAR(24)
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerfCount'))
	DROP TABLE #tblPerfCount;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerfCount'))
	CREATE TABLE #tblPerfCount (
		[retrieval_time] [datetime],
		[object_name] [NVARCHAR](128),
		[counter_name] [NVARCHAR](128),
		[instance_name] [NVARCHAR](128),
		[counter_name_type] int,
		[cntr_value] float NULL
		);
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.tblPerfThresholds'))
	DROP TABLE tempdb.dbo.tblPerfThresholds;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.tblPerfThresholds'))
	CREATE TABLE tempdb.dbo.tblPerfThresholds (
		[counter_family] [NVARCHAR](128),
		[counter_name] [NVARCHAR](128),
		[counter_instance] [NVARCHAR](128),
		[counter_name_type] int,
		[counter_value] float NULL
		);
		
	-- Create the helper function
	EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_perfctr'')) DROP FUNCTION dbo.fn_perfctr')
	EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_perfctr (@ctr1Fam NVARCHAR(128), @ctr1 NVARCHAR(128))
RETURNS float
AS
BEGIN
	DECLARE @ReturnVals float, @ctr1Val float, @ctr2Val float, @ctr2Fam NVARCHAR(128), @ctr2 NVARCHAR(128), @type tinyint
	
	-- ctr1Fam = source counter object; ctr1 = source counter; ctr2Fam = counter object to compare with; ctr2 = counter to compare with
	-- Type 1 = ratio between source and compare (Ex. 1 per each 10); 2 = pct ratio between source and compare (Ex. 10 pct of compare counter); 3 = ratio between compare and source; 4 = pct ratio between compare and source

	IF @ctr1 IN (''''Forwarded Records/sec'''',''''FreeSpace Scans/sec'''',''''Page Splits/sec'''',''''Workfiles Created/sec'''',''''Page lookups/sec'''',''''SQL Compilations/sec'''') 
		SELECT @ctr2Fam = ''''SQLServer:SQL Statistics'''', @ctr2 = ''''Batch Requests/sec'''', @type = 1 
	ELSE IF @ctr1 = ''''Lock Requests/sec''''
		SELECT @ctr2Fam = ''''SQLServer:SQL Statistics'''', @ctr2 = ''''Batch Requests/sec'''', @type = 0
	ELSE IF @ctr1 = ''''Full Scans/sec'''' 
		SELECT @ctr2Fam = ''''SQLServer:Access Methods'''', @ctr2 = ''''Index Searches/sec'''', @type = 1
	ELSE IF @ctr1 = ''''Index Searches/sec'''' 
		SELECT @ctr2Fam = ''''SQLServer:Access Methods'''', @ctr2 = ''''Full Scans/sec'''', @type = 3 
	ELSE IF @ctr1 = ''''Readahead pages/sec'''' 
		SELECT @ctr2Fam = ''''SQLServer:Buffer Manager'''', @ctr2 = ''''Page reads/sec'''', @type = 1
	ELSE IF @ctr1 = ''''Target Server Memory (KB)'''' 
		SELECT @ctr2Fam = ''''SQLServer:Memory Manager'''', @ctr2 = ''''Total Server Memory (KB)'''', @type = 2
	ELSE IF @ctr1 = ''''SQL Re-Compilations/sec'''' 
		SELECT @ctr2Fam = ''''SQLServer:SQL Statistics'''', @ctr2 = ''''SQL Compilations/sec'''', @type = 1
	ELSE IF @ctr1 = ''''Page writes/sec'''' 
		SELECT @ctr2Fam = ''''SQLServer:Buffer Manager'''', @ctr2 = ''''Page reads/sec'''', @type = 3

	SELECT @ctr1Val = [counter_value] FROM tempdb.dbo.tblPerfThresholds WHERE [counter_family] = @ctr1Fam AND [counter_name] = @ctr1
	SELECT @ctr2Val = [counter_value] FROM tempdb.dbo.tblPerfThresholds WHERE [counter_family] = @ctr2Fam AND [counter_name] = @ctr2

	IF @ctr1 = ''''Target Server Memory (KB)''''
	SELECT @ctr1Val = @ctr1Val / 1024, @ctr2Val = @ctr2Val / 1024
	
	--Find ratio between counter 1 and 2
	IF @ctr1Val IS NULL OR @ctr2Val IS NULL
	BEGIN
		SELECT @ReturnVals = NULL
	END
	ELSE IF @ctr1Val > 1 AND @ctr2Val > 1
	BEGIN
		IF @type = 0
		SELECT @ReturnVals = (@ctr1Val / @ctr2Val)
		IF @type = 1
		SELECT @ReturnVals = (@ctr1Val / @ctr2Val) * 100
		If @type = 2
		SELECT @ReturnVals = (@ctr1Val - @ctr2Val)
		IF @type = 3
		SELECT @ReturnVals = (@ctr2Val / @ctr1Val) * 100
	END
	ELSE
	BEGIN
		SELECT @ReturnVals = 0
	END

	RETURN (@ReturnVals)
END'')
	')		
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWaits'))
	DROP TABLE #tblWaits;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWaits'))
	CREATE TABLE [dbo].[#tblWaits](
		[retrieval_time] [datetime],
		[wait_type] [nvarchar](60) NOT NULL,
		[wait_time_ms] bigint NULL,
		[signal_wait_time_ms] bigint NULL,
		[resource_wait_time_ms] bigint NULL
		);

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalWaits'))
	DROP TABLE #tblFinalWaits;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalWaits'))
	CREATE TABLE [dbo].[#tblFinalWaits](
		[wait_type] [nvarchar](60) NOT NULL,
		[wait_time_s] [numeric](16, 6) NULL,
		[signal_wait_time_s] [numeric](16, 6) NULL,
		[resource_wait_time_s] [numeric](16, 6) NULL,
		[pct] [numeric](12, 2) NULL,
		[rn] [bigint] NULL,
		[signal_wait_pct] [numeric](12, 2) NULL,
		[resource_wait_pct] [numeric](12, 2) NULL
		);
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblLatches'))
	DROP TABLE #tblLatches;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblLatches'))
	CREATE TABLE [dbo].[#tblLatches](
		[retrieval_time] [datetime],
		[latch_class] [nvarchar](60) NOT NULL,
		[wait_time_ms] bigint NULL,
		[waiting_requests_count] [bigint] NULL
		);
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalLatches'))
	DROP TABLE #tblFinalLatches;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalLatches'))
	CREATE TABLE [dbo].[#tblFinalLatches](
		[latch_class] [nvarchar](60) NOT NULL,
		[wait_time_s] [decimal](16, 6) NULL,
		[waiting_requests_count] [bigint] NULL,
		[pct] [decimal](12, 2) NULL,
		[rn] [bigint] NULL
		);
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksBefore'))
	DROP TABLE #tblSpinlocksBefore;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksBefore'))
	CREATE TABLE [dbo].[#tblSpinlocksBefore](
		[name] NVARCHAR(512) NOT NULL,
		[collisions] bigint NULL,
		[spins] bigint NULL,
		[spins_per_collision] real NULL,
		[sleep_time] bigint NULL,
		[backoffs] int NULL
		);

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksAfter'))
	DROP TABLE #tblSpinlocksAfter;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksAfter'))
	CREATE TABLE [dbo].[#tblSpinlocksAfter](
		[name] NVARCHAR(512) NOT NULL,
		[collisions] bigint NULL,
		[spins] bigint NULL,
		[spins_per_collision] real NULL,
		[sleep_time] bigint NULL,
		[backoffs] int NULL
		);
			
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalSpinlocks'))
	DROP TABLE #tblFinalSpinlocks;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalSpinlocks'))
	CREATE TABLE [dbo].[#tblFinalSpinlocks](
		[name] NVARCHAR(512) NOT NULL,
		[collisions] bigint NULL,
		[spins] bigint NULL,
		[spins_per_collision] real NULL,
		[sleep_time] bigint NULL,
		[backoffs] int NULL,
		[spins_pct] [decimal](12, 2) NULL,
		[rn] [bigint] NULL
		);

	SELECT @minctr = GETDATE()

	-- When counter type = 272696576 (find delta from two collection points)
	-- When counter type = 65792 (face value)
	-- When counter type = 1073939712 (base value, check next counter types)
	-- When counter type = 1073874176 (find delta from current value and base value between two collection points). Base value is counter with type 1073939712.
	-- When counter type = 537003264 (find delta from current value and base value). Base value is counter with type 1073939712.

	INSERT INTO #tblPerfCount
	SELECT @minctr, [object_name], counter_name, instance_name, cntr_type AS counter_name_type, cntr_value
	FROM sys.dm_os_performance_counters pc0 (NOLOCK)
	WHERE ([object_name] LIKE '%:Access Methods%'
			OR [object_name] LIKE '%:Buffer Manager%'
			OR [object_name] LIKE '%:Buffer Node%'
			OR [object_name] LIKE '%:Latches%'
			OR [object_name] LIKE '%:Locks%'
			OR [object_name] LIKE '%:Memory Manager%'
			OR [object_name] LIKE '%:Memory Node%'
			OR [object_name] LIKE '%:Plan Cache%'
			OR [object_name] LIKE '%:SQL Statistics%'
			OR [object_name] LIKE '%:Wait Statistics%'
			OR [object_name] LIKE '%:Workload Group Stats%'
			OR [object_name] LIKE '%:Memory Broker Clerks%'
			OR [object_name] LIKE '%:Databases%'
			OR [object_name] LIKE '%:Database Replica%') 
		AND (counter_name LIKE '%FreeSpace Scans/sec%'
			OR counter_name LIKE '%Forwarded Records/sec%'
			OR counter_name LIKE '%Full Scans/sec%'
			OR counter_name LIKE '%Index Searches/sec%'
			OR counter_name LIKE '%Page Splits/sec%'
			OR counter_name LIKE '%Scan Point Revalidations/sec%'
			OR counter_name LIKE '%Table Lock Escalations/sec%'
			OR counter_name LIKE '%Workfiles Created/sec%'
			OR counter_name LIKE '%Worktables Created/sec%'
			OR counter_name LIKE '%Worktables From Cache%'
			OR counter_name LIKE '%Buffer cache hit ratio%'
			OR counter_name LIKE '%Buffer cache hit ratio base%'
			OR counter_name LIKE '%Checkpoint pages/sec%'
			OR counter_name LIKE '%Background writer pages/sec%' 
			OR counter_name LIKE '%Lazy writes/sec%'
			OR counter_name LIKE '%Free pages%'     
			OR counter_name LIKE '%Page life expectancy%'  
			OR counter_name LIKE '%Page lookups/sec%'
			OR counter_name LIKE '%Page reads/sec%'
			OR counter_name LIKE '%Page writes/sec%'
			OR counter_name LIKE '%Readahead pages/sec%'
			OR counter_name LIKE '%Average Latch Wait Time (ms)%'
			OR counter_name LIKE '%Average Latch Wait Time Base%'
			OR counter_name LIKE '%Total Latch Wait Time (ms)%'
			OR counter_name LIKE '%Average Wait Time (ms)%'
			OR counter_name LIKE '%Average Wait Time Base%'
			OR counter_name LIKE '%Number of Deadlocks/sec%'
			OR counter_name LIKE '%Free Memory (KB)%'
			OR counter_name LIKE '%Stolen Server Memory (KB)%'                                                                                              
			OR counter_name LIKE '%Target Server Memory (KB)%'
			OR counter_name LIKE '%Total Server Memory (KB)%'
			OR counter_name LIKE '%Free Node Memory (KB)%'
			OR counter_name LIKE '%Foreign Node Memory (KB)%'
			OR counter_name LIKE '%Stolen Node Memory (KB)%'
			OR counter_name LIKE '%Target Node Memory (KB)%'
			OR counter_name LIKE '%Total Node Memory (KB)%'
			OR counter_name LIKE '%Batch Requests/sec%'
			OR counter_name LIKE '%SQL Compilations/sec%'  
			OR counter_name LIKE '%SQL Re-Compilations/sec%'
			OR counter_name LIKE '%Lock waits%'
			OR counter_name LIKE '%Log buffer waits%'      
			OR counter_name LIKE '%Log write waits%'       
			OR counter_name LIKE '%Memory grant queue waits%'
			OR counter_name LIKE '%Network IO waits%'      
			OR counter_name LIKE '%Non-Page latch waits%'  
			OR counter_name LIKE '%Page IO latch waits%'   
			OR counter_name LIKE '%Page latch waits%'      
			OR counter_name LIKE '%Active parallel threads%'
			OR counter_name LIKE '%Blocked tasks%'         
			OR counter_name LIKE '%CPU usage %'           
			OR counter_name LIKE '%CPU usage % base%'      
			OR counter_name LIKE '%Query optimizations/sec%'
			OR counter_name LIKE '%Requests completed/sec%'
			OR counter_name LIKE '%Suboptimal plans/sec%'
			OR counter_name LIKE '%Temporary Tables & Table Variables%'
			OR counter_name LIKE '%Extended Stored Procedures%'
			OR counter_name LIKE '%Bound Trees%'           
			OR counter_name LIKE '%SQL Plans%'             
			OR counter_name LIKE '%Object Plans%'          
			OR counter_name LIKE '%_Total%'
			OR counter_name LIKE 'Transactions/sec%'
			OR counter_name LIKE '%Log Flush Wait Time%'
			OR counter_name LIKE '%Log Flush Waits/sec%'
			OR counter_name LIKE '%Recovery Queue%'
			OR counter_name LIKE '%Log Send Queue%'
			OR counter_name LIKE '%Transaction Delay%'
			OR counter_name LIKE '%Redo blocked/sec%'
			OR counter_name LIKE '%Resent Messages/sec%'
			OR instance_name LIKE '%Buffer Pool%'
			OR instance_name LIKE '%Column store object pool%');

	INSERT INTO #tblWaits
	SELECT @minctr, wait_type, wait_time_ms, signal_wait_time_ms,(wait_time_ms-signal_wait_time_ms) AS resource_wait_time_ms
	FROM sys.dm_os_wait_stats (NOLOCK)
	WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
		AND wait_type NOT LIKE N'SLEEP_%'
		AND wait_time_ms > 0;

	INSERT INTO #tblLatches
	SELECT @minctr, latch_class, wait_time_ms, waiting_requests_count
	FROM sys.dm_os_latch_stats (NOLOCK)
	WHERE /*latch_class NOT IN ('BUFFER')
		AND*/ wait_time_ms > 0;

	IF @sqlmajorver > 9
	BEGIN
		INSERT INTO #tblSpinlocksBefore
		SELECT name, collisions, spins, spins_per_collision, sleep_time, backoffs
		FROM sys.dm_os_spinlock_stats;
	END
	ELSE IF @sqlmajorver = 9
	BEGIN
		INSERT INTO #tblSpinlocksBefore 
		EXEC ('DBCC SQLPERF(''spinlockstats'')');
	END;

	IF @duration > 255
	SET @duration = 255;
	
	IF @duration < 10
	SET @duration = 10;
	
	SELECT @durationstr = 'WAITFOR DELAY ''00:' + CASE WHEN LEN(CONVERT(VARCHAR(3),@duration/60%60)) = 1 
		THEN '0' + CONVERT(VARCHAR(3),@duration/60%60) 
			ELSE CONVERT(VARCHAR(3),@duration/60%60) END 
		+ ':' + CONVERT(VARCHAR(3),@duration-(@duration/60)*60) + ''''
	EXECUTE sp_executesql @durationstr;

	SELECT @maxctr = GETDATE()
		
	INSERT INTO #tblPerfCount
	SELECT @maxctr, [object_name], counter_name, instance_name, cntr_type AS counter_name_type, cntr_value
	FROM sys.dm_os_performance_counters pc0 (NOLOCK)
WHERE (cntr_type = 272696576 OR cntr_type = 1073874176 OR cntr_type = 1073939712) -- Get only counters whose delta between collection points matters
	AND ([object_name] LIKE '%:Access Methods%'
		OR [object_name] LIKE '%:Buffer Manager%'
		OR [object_name] LIKE '%:Buffer Node%'
		OR [object_name] LIKE '%:Latches%'
		OR [object_name] LIKE '%:Locks%'
		OR [object_name] LIKE '%:Memory Manager%'
		OR [object_name] LIKE '%:Memory Node%'
		OR [object_name] LIKE '%:Plan Cache%'
		OR [object_name] LIKE '%:SQL Statistics%'
		OR [object_name] LIKE '%:Wait Statistics%'
		OR [object_name] LIKE '%:Workload Group Stats%'
		OR [object_name] LIKE '%:Memory Broker Clerks%'
		OR [object_name] LIKE '%:Databases%'
		OR [object_name] LIKE '%:Database Replica%') 
	AND (counter_name LIKE '%FreeSpace Scans/sec%'
		OR counter_name LIKE '%Forwarded Records/sec%'
		OR counter_name LIKE '%Full Scans/sec%'
		OR counter_name LIKE '%Index Searches/sec%'
		OR counter_name LIKE '%Page Splits/sec%'
		OR counter_name LIKE '%Scan Point Revalidations/sec%'
		OR counter_name LIKE '%Table Lock Escalations/sec%'
		OR counter_name LIKE '%Workfiles Created/sec%'
		OR counter_name LIKE '%Worktables Created/sec%'
		OR counter_name LIKE '%Worktables From Cache%'
		OR counter_name LIKE '%Buffer cache hit ratio%'
		OR counter_name LIKE '%Buffer cache hit ratio base%'
		OR counter_name LIKE '%Checkpoint pages/sec%'
		OR counter_name LIKE '%Background writer pages/sec%' 
		OR counter_name LIKE '%Lazy writes/sec%'
		OR counter_name LIKE '%Free pages%'     
		OR counter_name LIKE '%Page life expectancy%'  
		OR counter_name LIKE '%Page lookups/sec%'
		OR counter_name LIKE '%Page reads/sec%'
		OR counter_name LIKE '%Page writes/sec%'
		OR counter_name LIKE '%Readahead pages/sec%'
		OR counter_name LIKE '%Average Latch Wait Time (ms)%'
		OR counter_name LIKE '%Average Latch Wait Time Base%'
		OR counter_name LIKE '%Total Latch Wait Time (ms)%'
		OR counter_name LIKE '%Average Wait Time (ms)%'
		OR counter_name LIKE '%Average Wait Time Base%'
		OR counter_name LIKE '%Number of Deadlocks/sec%'
		OR counter_name LIKE '%Free Memory (KB)%'
		OR counter_name LIKE '%Stolen Server Memory (KB)%'                                                                                              
		OR counter_name LIKE '%Target Server Memory (KB)%'
		OR counter_name LIKE '%Total Server Memory (KB)%'
		OR counter_name LIKE '%Free Node Memory (KB)%'
		OR counter_name LIKE '%Foreign Node Memory (KB)%'
		OR counter_name LIKE '%Stolen Node Memory (KB)%'
		OR counter_name LIKE '%Target Node Memory (KB)%'
		OR counter_name LIKE '%Total Node Memory (KB)%'
		OR counter_name LIKE '%Batch Requests/sec%'
		OR counter_name LIKE '%SQL Compilations/sec%'  
		OR counter_name LIKE '%SQL Re-Compilations/sec%'
		OR counter_name LIKE '%Lock waits%'
		OR counter_name LIKE '%Log buffer waits%'      
		OR counter_name LIKE '%Log write waits%'       
		OR counter_name LIKE '%Memory grant queue waits%'
		OR counter_name LIKE '%Network IO waits%'      
		OR counter_name LIKE '%Non-Page latch waits%'  
		OR counter_name LIKE '%Page IO latch waits%'   
		OR counter_name LIKE '%Page latch waits%'      
		OR counter_name LIKE '%Active parallel threads%'
		OR counter_name LIKE '%Blocked tasks%'         
		OR counter_name LIKE '%CPU usage %'           
		OR counter_name LIKE '%CPU usage % base%'      
		OR counter_name LIKE '%Query optimizations/sec%'
		OR counter_name LIKE '%Requests completed/sec%'
		OR counter_name LIKE '%Suboptimal plans/sec%'
		OR counter_name LIKE '%Temporary Tables & Table Variables%'
		OR counter_name LIKE '%Extended Stored Procedures%'
		OR counter_name LIKE '%Bound Trees%'           
		OR counter_name LIKE '%SQL Plans%'             
		OR counter_name LIKE '%Object Plans%'          
		OR counter_name LIKE '%_Total%'
		OR counter_name LIKE 'Transactions/sec%'
		OR counter_name LIKE '%Log Flush Wait Time%'
		OR counter_name LIKE '%Log Flush Waits/sec%'
		OR counter_name LIKE '%Recovery Queue%'
		OR counter_name LIKE '%Log Send Queue%'
		OR counter_name LIKE '%Transaction Delay%'
		OR counter_name LIKE '%Redo blocked/sec%'
		OR counter_name LIKE '%Resent Messages/sec%'
		OR instance_name LIKE '%Buffer Pool%'
		OR instance_name LIKE '%Column store object pool%');
			
	INSERT INTO #tblWaits
	SELECT @maxctr, wait_type, wait_time_ms, signal_wait_time_ms,(wait_time_ms-signal_wait_time_ms) AS resource_wait_time_ms
	FROM sys.dm_os_wait_stats (NOLOCK)
	WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
		AND wait_type NOT LIKE N'SLEEP_%'
		AND wait_time_ms > 0;

	INSERT INTO #tblLatches
	SELECT @maxctr, latch_class, wait_time_ms, waiting_requests_count
	FROM sys.dm_os_latch_stats (NOLOCK)
	WHERE /*latch_class NOT IN ('BUFFER')
		AND*/ wait_time_ms > 0;

	IF @sqlmajorver > 9
	BEGIN
		INSERT INTO #tblSpinlocksAfter
		SELECT name, collisions, spins, spins_per_collision, sleep_time, backoffs
		FROM sys.dm_os_spinlock_stats;
	END
	ELSE IF @sqlmajorver = 9
	BEGIN
		INSERT INTO #tblSpinlocksAfter 
		EXEC ('DBCC SQLPERF(''spinlockstats'')');
	END;
	
	INSERT INTO tempdb.dbo.tblPerfThresholds
	SELECT DISTINCT t1.[object_name], t1.counter_name, t1.instance_name, t1.[counter_name_type],
		CASE WHEN t1.counter_name_type = 272696576
			THEN CONVERT(float,(
			(SELECT t2.cntr_value FROM #tblPerfCount t2 WHERE t2.[retrieval_time] = @maxctr AND t2.counter_name = t1.counter_name AND t2.instance_name = t1.instance_name) -
			(SELECT t2.cntr_value FROM #tblPerfCount t2 WHERE t2.[retrieval_time] = @minctr AND t2.counter_name = t1.counter_name AND t2.instance_name = t1.instance_name)
			) / DATEDIFF(ss,@minctr,@maxctr)) -- Get value per s over last xx s
		WHEN t1.counter_name_type = 537003264
			THEN (SELECT CONVERT(float,(t2.cntr_value / CASE WHEN t3.cntr_value <= 0 THEN 1 ELSE t3.cntr_value END) * 100.0)
					FROM #tblPerfCount t2 INNER JOIN #tblPerfCount t3 ON t2.[object_name] = t3.[object_name] AND t2.instance_name = t3.instance_name AND t3.counter_name IN (RTRIM(t2.counter_name) + N' base', 'Worktables From Cache Base') 
					WHERE t2.counter_name_type = t1.counter_name_type AND t3.counter_name_type = 1073939712 AND t2.counter_name = t1.counter_name AND t2.instance_name = t1.instance_name AND t2.[retrieval_time] = @minctr AND t3.[retrieval_time] = @minctr
					GROUP BY t2.[retrieval_time], t2.cntr_value, t3.cntr_value, t2.counter_name)
		WHEN t1.counter_name_type = 1073874176 AND t1.counter_name = 'Average Latch Wait Time (ms)'
			THEN CONVERT(float,(
			(
			(SELECT t2.cntr_value - t3.cntr_value 
			FROM #tblPerfCount t2 INNER JOIN #tblPerfCount t3 ON t2.[object_name] = t3.[object_name] AND t2.counter_name = t3.counter_name
			WHERE t2.counter_name = t1.counter_name /*AND t2.counter_name_type = t1.counter_name_type AND t2.instance_name = t1.instance_name*/ AND t2.[retrieval_time] = @maxctr AND t3.[retrieval_time] = @minctr
			GROUP BY t2.[retrieval_time], t2.cntr_value, t3.cntr_value, t2.counter_name)
			/
			(SELECT CASE WHEN t2.cntr_value - t3.cntr_value <= 0 THEN 1 ELSE t2.cntr_value - t3.cntr_value END 
			FROM #tblPerfCount t2 INNER JOIN #tblPerfCount t3 ON t2.[object_name] = t3.[object_name] AND t2.counter_name = t3.counter_name
			WHERE t2.counter_name = 'Average Latch Wait Time Base' AND t2.counter_name_type = 1073939712 AND t2.instance_name = t1.instance_name AND t2.[retrieval_time] = @maxctr AND t3.[retrieval_time] = @minctr
			GROUP BY t2.[retrieval_time], t2.cntr_value, t3.cntr_value, t2.counter_name)
			)
			/ DATEDIFF(ss,@minctr,@maxctr))) -- Get value per s over last xx s
		WHEN t1.counter_name_type = 1073874176 AND t1.counter_name = 'Average Wait Time (ms)'
			THEN CONVERT(float,(
			(
			SELECT (t4.cntr_value / CASE WHEN t5.cntr_value <= 0 THEN 1 ELSE t5.cntr_value END) / DATEDIFF(ss,@minctr,@maxctr)
			FROM
				(SELECT t2.cntr_value - t3.cntr_value AS cntr_value, t2.instance_name FROM #tblPerfCount t2 INNER JOIN #tblPerfCount t3 ON t2.[object_name] = t3.[object_name] AND t2.counter_name = t3.counter_name AND t2.instance_name = t3.instance_name 
				WHERE t2.counter_name = t1.counter_name /*AND t2.counter_name_type = t1.counter_name_type AND t2.instance_name = t1.instance_name*/ AND t2.[retrieval_time] = @maxctr AND t3.[retrieval_time] = @minctr
				GROUP BY t2.[retrieval_time], t2.cntr_value, t3.cntr_value, t2.counter_name, t2.instance_name) AS t4
				INNER JOIN
				(SELECT t2.cntr_value - t3.cntr_value AS cntr_value, t2.instance_name FROM #tblPerfCount t2 INNER JOIN #tblPerfCount t3 ON t2.[object_name] = t3.[object_name] AND t2.counter_name = t3.counter_name AND t2.instance_name = t3.instance_name 
				WHERE t2.counter_name = 'Average Wait Time Base' AND t2.counter_name_type = 1073939712 AND t2.instance_name = t1.instance_name AND t2.[retrieval_time] = @maxctr AND t3.[retrieval_time] = @minctr
				GROUP BY t2.[retrieval_time], t2.cntr_value, t3.cntr_value, t2.counter_name, t2.instance_name) AS t5
			ON t4.instance_name = t5.instance_name
			))) -- Get value per s over last xx s
		ELSE CONVERT(float,t1.cntr_value)
	END
	FROM #tblPerfCount t1
	WHERE (t1.counter_name_type <> 1073939712)
	GROUP BY t1.[object_name], t1.[counter_name], t1.instance_name, t1.counter_name_type, t1.cntr_value
	ORDER BY t1.[object_name], t1.[counter_name], t1.instance_name;

	;WITH ctectr AS (SELECT [counter_family],[counter_name],[counter_instance],[counter_value],
		CASE WHEN [counter_name] IN ('Worktables Created/sec','Worktables From Cache Ratio','Buffer cache hit ratio',
				'Free list stalls/sec','Free pages','Free Memory (KB)','Lazy writes/sec','Page life expectancy',
				'Page reads/sec','Log Flush Wait Time','Log Flush Waits/sec','Average Latch Wait Time (ms)',
				'Total Latch Wait Time (ms)','Lock Waits/sec','Number of Deadlocks/sec','Batch Requests/sec') THEN [counter_value] 
			ELSE tempdb.dbo.fn_perfctr([counter_family],[counter_name]) END AS [counter_calculated_threshold_value]
	FROM tempdb.dbo.tblPerfThresholds)
	SELECT 'Performance_checks' AS [Category], 'Perf_Counters' AS [Check],[counter_family],[counter_name],[counter_instance],[counter_value],[counter_calculated_threshold_value],
		CASE WHEN [counter_name] = 'Forwarded Records/sec' AND [counter_calculated_threshold_value] > 10 THEN '[WARNING: A ratio of more than 1 forwarded record for every 10 batch requests]'
			WHEN [counter_name] = 'FreeSpace Scans/sec' AND [counter_calculated_threshold_value] > 10 THEN '[WARNING: A ratio of more than 1 freespace scan for every 10 batch requests]'
			WHEN [counter_name] IN ('Full Scans/sec','Index Searches/sec') AND [counter_calculated_threshold_value] > 0.1 THEN '[WARNING: A ratio of more than 1 SQL Full Scan for every 1000 Index Searches]'
			WHEN [counter_name] = 'Page Splits/sec' AND [counter_calculated_threshold_value] > 5 THEN '[WARNING: A ratio of more than 1 page split for every 20 batch requests]'
			WHEN [counter_name] = 'Workfiles Created/sec' AND [counter_calculated_threshold_value] > 5 THEN '[WARNING: A ratio of more than 1 workfile created for every 20 batch requests]'
			WHEN [counter_name] = 'Worktables Created/sec' AND [counter_calculated_threshold_value] > 20 THEN '[WARNING: Greater than 20 Worktables created per second]'
			WHEN [counter_name] = 'Worktables From Cache Ratio' AND [counter_calculated_threshold_value] < 90 THEN '[WARNING: Less than 90 percent Worktables from Cache Ratio]'
			WHEN [counter_name] = 'Buffer cache hit ratio' AND [counter_calculated_threshold_value] < 97 THEN '[WARNING: Less than 97 percent buffer cache hit ratio]'
			WHEN [counter_name] = 'Buffer cache hit ratio' AND [counter_calculated_threshold_value] < 90 THEN '[WARNING: Less than 90 percent buffer cache hit ratio]'
			WHEN [counter_name] = 'Free list stalls/sec' AND [counter_calculated_threshold_value] < 2 THEN '[WARNING: Free list stalls per second is less than 2]' 
			WHEN [counter_name] = 'Free pages' AND [counter_calculated_threshold_value] < 640 THEN '[WARNING: Less than 640 Free Pages]'
			WHEN [counter_name] = 'Free Memory (KB)' AND [counter_calculated_threshold_value] < 5 THEN '[WARNING: Less than 5MB]'
			WHEN [counter_name] = 'Lazy writes/sec' AND [counter_calculated_threshold_value] > 20 THEN '[WARNING: Greater than 20 Lazy Writes per second]'
			WHEN [counter_name] = 'Page life expectancy' AND [counter_calculated_threshold_value] < 300 THEN '[WARNING: Less than 300 seconds of Page Life Expectancy]'
			WHEN [counter_name] = 'Page life expectancy' AND [counter_calculated_threshold_value] < 700 THEN '[WARNING: Less than 700 seconds of Page Life Expectancy]'
			WHEN [counter_name] = 'Page lookups/sec' AND [counter_calculated_threshold_value] > 1 THEN '[WARNING: A ratio of more than 1 page lookup for every 100 batch requests]'
			WHEN [counter_name] = 'Page reads/sec' AND [counter_calculated_threshold_value] > 90 THEN '[WARNING: Greater than 90 page reads per second]'
			WHEN [counter_name] = 'Page writes/sec' AND [counter_calculated_threshold_value] > 30 THEN '[WARNING: Page writes are more than 30 percent of page reads per second]'
			WHEN [counter_name] = 'Page writes/sec' AND [counter_value] > 90 THEN '[WARNING: Greater than 90 page writes per second]'
			WHEN [counter_name] = 'Readahead pages/sec' AND [counter_calculated_threshold_value] > 20 THEN '[WARNING: More than 20 percent of page reads per second]'
			WHEN [counter_name] IN ('Log Flush Wait Time','Log Flush Waits/sec','Lock Waits/sec','Number of Deadlocks/sec') AND [counter_calculated_threshold_value] > 0 THEN '[WARNING: Greater than 0]'
			WHEN [counter_name] = 'Average Latch Wait Time (ms)' AND [counter_calculated_threshold_value] > 10 THEN '[WARNING: Latch wait is more than 10 milliseconds on average]'
			WHEN [counter_name] = 'Total Latch Wait Time (ms)' AND [counter_calculated_threshold_value] > 500 THEN '[WARNING: Total latch wait time is above 500 ms per each second on average]'
			WHEN [counter_name] = 'Total Latch Wait Time (ms)' AND [counter_calculated_threshold_value] > 750 THEN '[WARNING: Total latch wait time is above 750 ms per each second on average]'
			WHEN [counter_name] = 'Lock Requests/sec' AND [counter_calculated_threshold_value] > 500 THEN '[WARNING: A ratio of more than 500 lock requests per batch request]'
			WHEN [counter_name] = 'Target Server Memory (KB)' AND [counter_calculated_threshold_value] > 500 THEN '[WARNING: Target Server Memory is more than 500MBs above Total Server Memory]'
			WHEN [counter_name] = 'Batch Requests/sec' AND [counter_calculated_threshold_value] > 1000 THEN '[WARNING: Greater than 1000 batch requests per second]'
			WHEN [counter_name] = 'SQL Compilations/sec' AND [counter_calculated_threshold_value] > 10 THEN '[WARNING: A ratio of more than 1 SQL Compilation for every 10 Batch Requests per second]'
			WHEN [counter_name] = 'SQL Re-Compilations/sec' AND [counter_calculated_threshold_value] > 10 THEN '[WARNING: A ratio of more than 1 SQL Re-Compilation for every 10 SQL Compilations]'
			WHEN [counter_calculated_threshold_value] IS NULL THEN NULL
		ELSE '[OK]' END AS [Deviation]
	FROM ctectr
	ORDER BY [counter_family],[counter_name],[counter_instance];
	
	IF @sqlmajorver >= 11
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Perf_Counters' AS [Information], [counter_name] AS Counter_name, "CPU Time:Total(ms)", "CPU Time:Requests", "Elapsed Time:Total(ms)", "Elapsed Time:Requests"
		FROM (SELECT [counter_name],[instance_name],[cntr_value] FROM #tblPerfCount WHERE [object_name] LIKE '%Batch Resp Statistics%') AS pc
		PIVOT(AVG([cntr_value]) FOR [instance_name]
		IN ("CPU Time:Total(ms)", "CPU Time:Requests", "Elapsed Time:Total(ms)", "Elapsed Time:Requests")
		) AS Pvt;
	END

	;WITH cteWaits1 (wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms) AS (SELECT wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms FROM #tblWaits WHERE [retrieval_time] = @minctr),
		cteWaits2 (wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms) AS (SELECT wait_type,wait_time_ms,signal_wait_time_ms,resource_wait_time_ms FROM #tblWaits WHERE [retrieval_time] = @maxctr)
	INSERT INTO #tblFinalWaits
	SELECT DISTINCT t1.wait_type, (t2.wait_time_ms-t1.wait_time_ms) / 1000. AS wait_time_s,
		(t2.signal_wait_time_ms-t1.signal_wait_time_ms) / 1000. AS signal_wait_time_s,
		((t2.wait_time_ms-t2.signal_wait_time_ms)-(t1.wait_time_ms-t1.signal_wait_time_ms)) / 1000. AS resource_wait_time_s,
		100.0 * (t2.wait_time_ms-t1.wait_time_ms) / SUM(t2.wait_time_ms-t1.wait_time_ms) OVER() AS pct,
		ROW_NUMBER() OVER(ORDER BY (t2.wait_time_ms-t1.wait_time_ms) DESC) AS rn,
		SUM(t2.signal_wait_time_ms-t1.signal_wait_time_ms) * 1.0 / SUM(t2.wait_time_ms-t1.wait_time_ms) * 100 AS signal_wait_pct,
		(SUM(t2.wait_time_ms-t2.signal_wait_time_ms)-SUM(t1.wait_time_ms-t1.signal_wait_time_ms)) * 1.0 / (SUM(t2.wait_time_ms)-SUM(t1.wait_time_ms)) * 100 AS resource_wait_pct
	FROM cteWaits1 t1 INNER JOIN cteWaits2 t2 ON t1.wait_type = t2.wait_type
	GROUP BY t1.wait_type, t1.wait_time_ms, t1.signal_wait_time_ms, t1.resource_wait_time_ms, t2.wait_time_ms, t2.signal_wait_time_ms, t2.resource_wait_time_ms
	HAVING (t2.wait_time_ms-t1.wait_time_ms) > 0
	ORDER BY wait_time_s DESC;

	-- SOS_SCHEDULER_YIELD = Might indicate CPU pressure if very high overall percentage. Check yielding conditions in http://technet.microsoft.com/library/cc917684.aspx
	-- THREADPOOL = Look for high blocking or contention problems with workers. This will not show up in sys.dm_exec_requests;
	-- LATCH = indicates contention for access to some non-page structures. ACCESS_METHODS_DATASET_PARENT, ACCESS_METHODS_SCAN_RANGE_GENERATOR or NESTING_TRANSACTION_FULL latches indicate parallelism issues;
	-- PAGELATCH = indicates contention for access to in-memory copies of pages, like PFS, SGAM and GAM; 
	-- PAGELATCH_UP = Does the filegroup have enough files? Contention in PFS?
	-- PAGELATCH_EX = Contention while doing many UPDATE statements against small tables? 
	-- PAGELATCH_EX = Many concurrent INSERT statements into a table that has an index on an IDENTITY or NEWSEQUENTIALID column? -> https://techcommunity.microsoft.com/t5/SQL-Server/PAGELATCH-EX-waits-and-heavy-inserts/ba-p/384289
	-- PAGEIOLATCH = indicates IO problems, or BP pressure.
	-- PREEMPTIVE_OS_WRITEFILEGATHERER (2008+) = usually autogrow scenarios, usually together with WRITELOG;
	-- IO_COMPLETION = usually TempDB spilling; 
	-- ASYNC_IO_COMPLETION = usually when not using IFI, or waiting on backups.
	-- DISKIO_SUSPEND = High wait times here indicate the SNAPSHOT BACKUP may be taking longer than expected. Typically the delay is within the VDI application perform the snapshot backup;
	-- BACKUPIO = check for slow backup media slow, like Tapes or Disks;
	-- BACKUPBUFFER = usually when backing up to Tape;
	-- Check sys.dm_os_waiting_tasks for Exchange wait types in https://docs.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-os-waiting-tasks-transact-sql
	-- Wait Resource e_waitPipeNewRow in CXPACKET waits Producer waiting on consumer for a packet to fill;
	-- Wait Resource e_waitPipeGetRow in CXPACKET waits Consumer waiting on producer to fill a packet;
	-- CXPACKET = if OLTP, check for parallelism issues if above 20 pct. If combined with a high number of PAGEIOLATCH_XX waits, it could be large parallel table scans going on because of incorrect non-clustered indexes, or out-of-date statistics causing a bad query plan;
	-- HT* = batch mode syncpoint waits, probably large parallel table scans;   
	-- WRITELOG = log management system waiting for a log flush to disk. Examine the I/O latency for the log file
	-- CMEMTHREAD =  indicates that the rate of insertion of entries into the plan cache is very high and there is contention -> https://techcommunity.microsoft.com/t5/SQL-Server-Support/How-It-Works-CMemThread-and-Debugging-Them/ba-p/317488
	-- SOS_RESERVEDMEMBLOCKLIST = look for procedures with a large number of parameters, or queries with a long list of expression values specified in an IN clause, which would require multi-page allocations
	-- RESOURCE_SEMAPHORE_SMALL_QUERY or RESOURCE_SEMAPHORE = queries are waiting for execution memory. Look for plans with excessive hashing or sorts.
	-- RESOURCE_SEMAPHORE_QUERY_COMPILE = usually high compilation or recompilation scenario (higher ratio of prepared plans vs. compiled plans). On x64 usually memory hungry queries and compiles. On x86 perhaps short on VAS. -> http://technet.microsoft.com/library/cc293620.aspx
	-- DBMIRROR_DBM_MUTEX = indicates contention for the send buffer that database mirroring shares between all the mirroring sessions. 
	
	SELECT 'Performance_checks' AS [Category], 'Waits_Last_' + CONVERT(VARCHAR(3), @duration) + 's' AS [Information], W1.wait_type, 
		CAST(W1.wait_time_s AS DECIMAL(14, 2)) AS wait_time_s,
		CAST(W1.signal_wait_time_s AS DECIMAL(14, 2)) AS signal_wait_time_s,
		CAST(W1.resource_wait_time_s AS DECIMAL(14, 2)) AS resource_wait_time_s,
		CAST(W1.pct AS DECIMAL(14, 2)) AS pct,
		CAST(SUM(W2.pct) AS DECIMAL(14, 2)) AS overall_running_pct,
		CAST(W1.signal_wait_pct AS DECIMAL(14, 2)) AS signal_wait_pct,
		CAST(W1.resource_wait_pct AS DECIMAL(14, 2)) AS resource_wait_pct,
		CASE WHEN W1.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU' 
			WHEN W1.wait_type = N'THREADPOOL' THEN 'CPU - Unavailable Worker Threads'
			WHEN W1.wait_type LIKE N'LCK_%' OR W1.wait_type = N'LOCK' THEN N'Lock' 
			WHEN W1.wait_type LIKE N'LATCH_%' THEN N'Latch' 
			WHEN W1.wait_type LIKE N'PAGELATCH_%' THEN N'Buffer Latch' 
			WHEN W1.wait_type LIKE N'PAGEIOLATCH_%' THEN N'Buffer IO' 
			WHEN W1.wait_type LIKE N'HADR_SYNC_COMMIT' THEN N'Always On - Secondary Synch' 
			WHEN W1.wait_type LIKE N'HADR_%' OR W1.wait_type LIKE N'PWAIT_HADR_%' THEN N'Always On'
			WHEN W1.wait_type LIKE N'FFT_%' THEN N'FileTable'
			WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Memory - Compilation'
			WHEN W1.wait_type IN (N'UTIL_PAGE_ALLOC', N'SOS_VIRTUALMEMORY_LOW', N'SOS_RESERVEDMEMBLOCKLIST', N'RESOURCE_SEMAPHORE', N'CMEMTHREAD', N'CMEMPARTITIONED', N'EE_PMOLOCK', N'MEMORY_ALLOCATION_EXT', N'RESERVED_MEMORY_ALLOCATION_EXT', N'MEMORY_GRANT_UPDATE') THEN N'Memory'
			WHEN W1.wait_type LIKE N'CLR%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'SQL CLR' 
			WHEN W1.wait_type LIKE N'DBMIRROR%' OR W1.wait_type = N'MIRROR_SEND_MESSAGE' THEN N'Mirroring' 
			WHEN W1.wait_type LIKE N'XACT%' or W1.wait_type LIKE N'DTC%' or W1.wait_type LIKE N'TRAN_MARKLATCH_%' or W1.wait_type LIKE N'MSQL_XACT_%' or W1.wait_type = N'TRANSACTION_MUTEX' THEN N'Transaction' 
			WHEN W1.wait_type LIKE N'PREEMPTIVE_%' THEN N'External APIs or XPs' 
			WHEN W1.wait_type LIKE N'BROKER_%' AND W1.wait_type <> N'BROKER_RECEIVE_WAITFOR' THEN N'Service Broker' 
			WHEN W1.wait_type IN (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'LOGMGR_PMM_LOG', N'CHKPT', N'WRITELOG') THEN N'Tran Log IO' 
			WHEN W1.wait_type IN (N'ASYNC_NETWORK_IO', N'NET_WAITFOR_PACKET', N'PROXY_NETWORK_IO', N'EXTERNAL_SCRIPT_NETWORK_IO') THEN N'Network IO' 
			WHEN W1.wait_type IN (N'CXPACKET', N'EXCHANGE', N'CXCONSUMER', N'HTBUILD', N'HTDELETE', N'HTMEMO', N'HTREINIT', N'HTREPARTITION') THEN N'CPU - Parallelism'
			WHEN W1.wait_type IN (N'WAITFOR', N'WAIT_FOR_RESULTS', N'BROKER_RECEIVE_WAITFOR') THEN N'User Wait' 
			WHEN W1.wait_type IN (N'TRACEWRITE', N'SQLTRACE_LOCK', N'SQLTRACE_FILE_BUFFER', N'SQLTRACE_FILE_WRITE_IO_COMPLETION', N'SQLTRACE_FILE_READ_IO_COMPLETION', N'SQLTRACE_PENDING_BUFFER_WRITERS', N'SQLTRACE_SHUTDOWN', N'QUERY_TRACEOUT', N'TRACE_EVTNOTIF') THEN N'Tracing' 
			WHEN W1.wait_type LIKE N'FT_%' OR W1.wait_type IN (N'FULLTEXT GATHERER', N'MSSEARCH', N'PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC') THEN N'Full Text Search' 
			WHEN W1.wait_type IN (N'ASYNC_IO_COMPLETION', N'IO_COMPLETION', N'WRITE_COMPLETION', N'IO_QUEUE_LIMIT', /*N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',*/ N'IO_RETRY') THEN N'Other Disk IO' 
			WHEN W1.wait_type IN (N'BACKUPIO', N'BACKUPBUFFER') THEN 'Backup IO'
			WHEN W1.wait_type LIKE N'SE_REPL_%' or W1.wait_type LIKE N'REPL_%'  or W1.wait_type IN (N'REPLICA_WRITES', N'FCB_REPLICA_WRITE', N'FCB_REPLICA_READ', N'PWAIT_HADRSIM') THEN N'Replication' 
			WHEN W1.wait_type IN (N'LOG_RATE_GOVERNOR', N'POOL_LOG_RATE_GOVERNOR', N'HADR_THROTTLE_LOG_RATE_GOVERNOR', N'INSTANCE_LOG_RATE_GOVERNOR') THEN N'Log Rate Governor' 
			WHEN W1.wait_type = N'REPLICA_WRITE' THEN 'Snapshots'
			WHEN W1.wait_type = N'WAIT_XTP_OFFLINE_CKPT_LOG_IO' OR W1.wait_type = N'WAIT_XTP_CKPT_CLOSE' THEN 'In-Memory OLTP Logging'
			WHEN W1.wait_type LIKE N'QDS%' THEN N'Query Store'
			WHEN W1.wait_type LIKE N'XTP%' OR W1.wait_type LIKE N'WAIT_XTP%' THEN N'In-Memory OLTP'
			WHEN W1.wait_type LIKE N'PARALLEL_REDO%' THEN N'Parallel Redo'
			WHEN W1.wait_type LIKE N'COLUMNSTORE%' THEN N'Columnstore'
		ELSE N'Other' END AS 'wait_category'
	FROM #tblFinalWaits AS W1 INNER JOIN #tblFinalWaits AS W2 ON W2.rn <= W1.rn
	GROUP BY W1.rn, W1.wait_type, CAST(W1.wait_time_s AS DECIMAL(14, 2)), CAST(W1.pct AS DECIMAL(14, 2)), CAST(W1.signal_wait_time_s AS DECIMAL(14, 2)), CAST(W1.resource_wait_time_s AS DECIMAL(14, 2)), CAST(W1.signal_wait_pct AS DECIMAL(14, 2)), CAST(W1.resource_wait_pct AS DECIMAL(14, 2))
	HAVING CAST(W1.wait_time_s as DECIMAL(14, 2)) >= 0.01 AND (SUM(W2.pct)-CAST(W1.pct AS DECIMAL(14, 2))) < 100  -- percentage threshold
	ORDER BY W1.rn;

	;WITH Waits AS
	(SELECT wait_type, wait_time_ms / 1000. AS wait_time_s,
		signal_wait_time_ms / 1000. AS signal_wait_time_s,
		(wait_time_ms-signal_wait_time_ms) / 1000. AS resource_wait_time_s,
		SUM(signal_wait_time_ms) * 1.0 / SUM(wait_time_ms) * 100 AS signal_wait_pct,
		SUM(wait_time_ms-signal_wait_time_ms) * 1.0 / SUM(wait_time_ms) * 100 AS resource_wait_pct,
		100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct,
		ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS rn
		FROM sys.dm_os_wait_stats
		WHERE wait_type NOT IN ('RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
	'SP_SERVER_DIAGNOSTICS_SLEEP', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
	'BROKER_TASK_STOP','CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT','BROKER_TO_FLUSH',
	'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'MSQL_XP', 'WAIT_FOR_RESULTS', 'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'SLEEP_TASK',
	'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_EVENTHANDLER', 'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'BROKER_RECEIVE_WAITFOR', 
	'ONDEMAND_TASK_QUEUE', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRRORING_CMD', 'BROKER_TRANSMITTER', 'SQLTRACE_WAIT_ENTRIES', 'SLEEP_BPOOL_FLUSH', 'SQLTRACE_LOCK',
	'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
	'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'SOSHOST_SLEEP', 'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP') 
			AND wait_type NOT LIKE N'SLEEP_%'
		GROUP BY wait_type, wait_time_ms, signal_wait_time_ms)
	SELECT 'Performance_checks' AS [Category], 'Cumulative_Waits' AS [Information], W1.wait_type, 
		CAST(W1.wait_time_s AS DECIMAL(14, 2)) AS wait_time_s,
		CAST(W1.signal_wait_time_s AS DECIMAL(14, 2)) AS signal_wait_time_s,
		CAST(W1.resource_wait_time_s AS DECIMAL(14, 2)) AS resource_wait_time_s,
		CAST(W1.pct AS DECIMAL(14, 2)) AS pct,
		CAST(SUM(W2.pct) AS DECIMAL(14, 2)) AS overall_running_pct,
		CAST(W1.signal_wait_pct AS DECIMAL(14, 2)) AS signal_wait_pct,
		CAST(W1.resource_wait_pct AS DECIMAL(14, 2)) AS resource_wait_pct,
		CASE WHEN W1.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU' 
			WHEN W1.wait_type = N'THREADPOOL' THEN 'CPU - Unavailable Worker Threads'
			WHEN W1.wait_type LIKE N'LCK_%' OR W1.wait_type = N'LOCK' THEN N'Lock' 
			WHEN W1.wait_type LIKE N'LATCH_%' THEN N'Latch'
			WHEN W1.wait_type LIKE N'PAGELATCH_%' THEN N'Buffer Latch'
			WHEN W1.wait_type LIKE N'PAGEIOLATCH_%' THEN N'Buffer IO'
			WHEN W1.wait_type LIKE N'HADR_SYNC_COMMIT' THEN N'Always On - Secondary Synch' 
			WHEN W1.wait_type LIKE N'HADR_%' OR W1.wait_type LIKE N'PWAIT_HADR_%' THEN N'Always On'
			WHEN W1.wait_type LIKE N'FFT_%' THEN N'FileTable'
			WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Memory - Compilation'
			WHEN W1.wait_type IN (N'UTIL_PAGE_ALLOC', N'SOS_VIRTUALMEMORY_LOW', N'SOS_RESERVEDMEMBLOCKLIST', N'RESOURCE_SEMAPHORE', N'CMEMTHREAD', N'CMEMPARTITIONED', N'EE_PMOLOCK', N'MEMORY_ALLOCATION_EXT', N'RESERVED_MEMORY_ALLOCATION_EXT', N'MEMORY_GRANT_UPDATE') THEN N'Memory'
			WHEN W1.wait_type LIKE N'CLR%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'SQL CLR' 
			WHEN W1.wait_type LIKE N'DBMIRROR%' OR W1.wait_type = N'MIRROR_SEND_MESSAGE' THEN N'Mirroring' 
			WHEN W1.wait_type LIKE N'XACT%' or W1.wait_type LIKE N'DTC%' or W1.wait_type LIKE N'TRAN_MARKLATCH_%' or W1.wait_type LIKE N'MSQL_XACT_%' or W1.wait_type = N'TRANSACTION_MUTEX' THEN N'Transaction' 
			WHEN W1.wait_type LIKE N'PREEMPTIVE_%' THEN N'External APIs or XPs' -- Used to indicate a worker is running code that is not under the SQLOS Scheduling;
			WHEN W1.wait_type LIKE N'BROKER_%' AND W1.wait_type <> N'BROKER_RECEIVE_WAITFOR' THEN N'Service Broker' 
			WHEN W1.wait_type IN (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'LOGMGR_PMM_LOG', N'CHKPT', N'WRITELOG') THEN N'Tran Log IO' 
			WHEN W1.wait_type IN (N'ASYNC_NETWORK_IO', N'NET_WAITFOR_PACKET', N'PROXY_NETWORK_IO', N'EXTERNAL_SCRIPT_NETWORK_IO') THEN N'Network IO' 
			WHEN W1.wait_type IN (N'CXPACKET', N'EXCHANGE', N'CXCONSUMER') THEN N'CPU - Parallelism'
			WHEN W1.wait_type IN (N'WAITFOR', N'WAIT_FOR_RESULTS', N'BROKER_RECEIVE_WAITFOR') THEN N'User Wait' 
			WHEN W1.wait_type IN (N'TRACEWRITE', N'SQLTRACE_LOCK', N'SQLTRACE_FILE_BUFFER', N'SQLTRACE_FILE_WRITE_IO_COMPLETION', N'SQLTRACE_FILE_READ_IO_COMPLETION', N'SQLTRACE_PENDING_BUFFER_WRITERS', N'SQLTRACE_SHUTDOWN', N'QUERY_TRACEOUT', N'TRACE_EVTNOTIF') THEN N'Tracing' 
			WHEN W1.wait_type LIKE N'FT_%' OR W1.wait_type IN (N'FULLTEXT GATHERER', N'MSSEARCH', N'PWAIT_RESOURCE_SEMAPHORE_FT_PARALLEL_QUERY_SYNC') THEN N'Full Text Search' 
			WHEN W1.wait_type IN (N'ASYNC_IO_COMPLETION', N'IO_COMPLETION', N'WRITE_COMPLETION', N'IO_QUEUE_LIMIT', /*N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',*/ N'IO_RETRY') THEN N'Other Disk IO' 
			WHEN W1.wait_type IN(N'BACKUPIO', N'BACKUPBUFFER') THEN 'Backup IO'
			WHEN W1.wait_type IN (N'CXPACKET', N'EXCHANGE', N'CXCONSUMER') THEN N'CPU - Parallelism'
			WHEN W1.wait_type IN (N'LOGMGR', N'LOGBUFFER', N'LOGMGR_RESERVE_APPEND', N'LOGMGR_FLUSH', N'WRITELOG') THEN N'Logging'
			WHEN W1.wait_type IN (N'NET_WAITFOR_PACKET',N'NETWORK_IO') THEN N'Network IO'
			WHEN W1.wait_type = N'ASYNC_NETWORK_IO' THEN N'Client Network IO'
			WHEN W1.wait_type IN (N'UTIL_PAGE_ALLOC',N'SOS_VIRTUALMEMORY_LOW',N'CMEMTHREAD', N'SOS_RESERVEDMEMBLOCKLIST') THEN N'Memory' 
			WHEN W1.wait_type IN (N'RESOURCE_SEMAPHORE_SMALL_QUERY', N'RESOURCE_SEMAPHORE') THEN N'Memory - Hash or Sort'
			WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Memory - Compilation'
			WHEN W1.wait_type LIKE N'CLR_%' OR W1.wait_type LIKE N'SQLCLR%' THEN N'CLR'
			WHEN W1.wait_type LIKE N'DBMIRROR%' OR W1.wait_type = N'MIRROR_SEND_MESSAGE' THEN N'Mirroring'
			WHEN W1.wait_type LIKE N'RESOURCE_SEMAPHORE_%' OR W1.wait_type LIKE N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Compilation' 
			WHEN W1.wait_type LIKE N'XACT%' OR W1.wait_type LIKE N'DTC_%' OR W1.wait_type LIKE N'TRAN_MARKLATCH_%' OR W1.wait_type LIKE N'MSQL_XACT_%' OR W1.wait_type = N'TRANSACTION_MUTEX' THEN N'Transaction'
			WHEN W1.wait_type IN (N'LOG_RATE_GOVERNOR', N'POOL_LOG_RATE_GOVERNOR', N'HADR_THROTTLE_LOG_RATE_GOVERNOR', N'INSTANCE_LOG_RATE_GOVERNOR') THEN N'Log Rate Governor' 
			WHEN W1.wait_type = N'REPLICA_WRITE' THEN 'Snapshots'
			WHEN W1.wait_type = N'WAIT_XTP_OFFLINE_CKPT_LOG_IO' OR W1.wait_type = N'WAIT_XTP_CKPT_CLOSE' THEN 'In-Memory OLTP Logging'
			WHEN W1.wait_type LIKE N'QDS%' THEN N'Query Store'
			WHEN W1.wait_type LIKE N'XTP%' OR W1.wait_type LIKE N'WAIT_XTP%' THEN N'In-Memory OLTP'
			WHEN W1.wait_type LIKE N'PARALLEL_REDO%' THEN N'Parallel Redo'
			WHEN W1.wait_type LIKE N'COLUMNSTORE%' THEN N'Columnstore'
		ELSE N'Other' END AS 'wait_category'
	FROM Waits AS W1 INNER JOIN Waits AS W2 ON W2.rn <= W1.rn
	GROUP BY W1.rn, W1.wait_type, CAST(W1.wait_time_s AS DECIMAL(14, 2)), CAST(W1.pct AS DECIMAL(14, 2)), CAST(W1.signal_wait_time_s AS DECIMAL(14, 2)), CAST(W1.resource_wait_time_s AS DECIMAL(14, 2)), CAST(W1.signal_wait_pct AS DECIMAL(14, 2)), CAST(W1.resource_wait_pct AS DECIMAL(14, 2))
	HAVING CAST(W1.wait_time_s as DECIMAL(14, 2)) >= 0.01 AND (SUM(W2.pct)-CAST(W1.pct AS DECIMAL(14, 2))) < 100  -- percentage threshold
	ORDER BY W1.rn;

	-- ACCESS_METHODS_HOBT_VIRTUAL_ROOT = This latch is used to access the metadata for an index that contains the page ID of the index's root page. Contention on this latch can occur when a B-tree root page split occurs (requiring the latch in EX mode) and threads wanting to navigate down the B-tree (requiring the latch in SH mode) have to wait. This could be from very fast population of a small index using many concurrent connections, with or without page splits from random key values causing cascading page splits (from leaf to root).
	-- ACCESS_METHODS_HOBT_COUNT = This latch is used to flush out page and row count deltas for a HoBt (Heap-or-B-tree) to the Storage Engine metadata tables. Contention would indicate *lots* of small, concurrent DML operations on a single table. 
	-- ACCESS_METHODS_DATASET_PARENT and ACCESS_METHODS_SCAN_RANGE_GENERATOR = These two latches are used during parallel scans to give each thread a range of page IDs to scan. The LATCH_XX waits for these latches will typically appear with CXPACKET waits and PAGEIOLATCH_XX waits (if the data being scanned is not memory-resident). Use normal parallelism troubleshooting methods to investigate further (e.g. is the parallelism warranted? maybe increase 'cost threshold for parallelism', lower MAXDOP, use a MAXDOP hint, use Resource Governor to limit DOP using a workload group with a MAX_DOP limit. Did a plan change from index seeks to parallel table scans because a tipping point was reached or a plan recompiled with an atypical SP parameter or poor statistics? Do NOT knee-jerk and set server MAXDOP to 1 – that's some of the worst advice I see on the Internet.);
	-- NESTING_TRANSACTION_FULL  = This latch, along with NESTING_TRANSACTION_READONLY, is used to control access to transaction description structures (called an XDES) for parallel nested transactions. The _FULL is for a transaction that's 'active', i.e. it's changed the database (usually for an index build/rebuild), and that makes the _READONLY description obvious. A query that involves a parallel operator must start a sub-transaction for each parallel thread that is used – these transactions are sub-transactions of the parallel nested transaction. For contention on these, I'd investigate unwanted parallelism but I don't have a definite "it's usually this problem". Also check out the comments for some info about these also sometimes being a problem when RCSI is used.
	-- LOG_MANAGER = you see this latch it is almost certainly because a transaction log is growing because it could not clear/truncate for some reason. Find the database where the log is growing and then figure out what's preventing log clearing using sys.databases.
	-- DBCC_MULTIOBJECT_SCANNER  = This latch appears on Enterprise Edition when DBCC CHECK_ commands are allowed to run in parallel. It is used by threads to request the next data file page to process. Late last year this was identified as a major contention point inside DBCC CHECK* and there was work done to reduce the contention and make DBCC CHECK* run faster.
	-- https://techcommunity.microsoft.com/t5/SQL-Server-Support/A-faster-CHECKDB-8211-Part-II/ba-p/316882
	-- FGCB_ADD_REMOVE = FGCB stands for File Group Control Block. This latch is required whenever a file is added or dropped from the filegroup, whenever a file is grown (manually or automatically), when recalculating proportional-fill weightings, and when cycling through the files in the filegroup as part of round-robin allocation. If you're seeing this, the most common cause is that there's a lot of file auto-growth happening. It could also be from a filegroup with lots of file (e.g. the primary filegroup in tempdb) where there are thousands of concurrent connections doing allocations. The proportional-fill weightings are recalculated every 8192 allocations, so there's the possibility of a slowdown with frequent recalculations over many files.

	;WITH cteLatches1 (latch_class,wait_time_ms,waiting_requests_count) AS (SELECT latch_class,wait_time_ms,waiting_requests_count FROM #tblLatches WHERE [retrieval_time] = @minctr),
		cteLatches2 (latch_class,wait_time_ms,waiting_requests_count) AS (SELECT latch_class,wait_time_ms,waiting_requests_count FROM #tblLatches WHERE [retrieval_time] = @maxctr)
	INSERT INTO #tblFinalLatches
	SELECT DISTINCT t1.latch_class,
			CAST((t2.wait_time_ms-t1.wait_time_ms) / 1000.0 AS DECIMAL(14, 2)) AS wait_time_s,
			(t2.waiting_requests_count-t1.waiting_requests_count) AS waiting_requests_count,
			100.0 * (t2.wait_time_ms-t1.wait_time_ms) / SUM(t2.wait_time_ms-t1.wait_time_ms) OVER() AS pct,
			ROW_NUMBER() OVER(ORDER BY t1.wait_time_ms DESC) AS rn
	FROM cteLatches1 t1 INNER JOIN cteLatches2 t2 ON t1.latch_class = t2.latch_class
	GROUP BY t1.latch_class, t1.wait_time_ms, t2.wait_time_ms, t1.waiting_requests_count, t2.waiting_requests_count
	HAVING (t2.wait_time_ms-t1.wait_time_ms) > 0
	ORDER BY wait_time_s DESC;
	
	SELECT 'Performance_checks' AS [Category], 'Latches_Last_' + CONVERT(VARCHAR(3), @duration) + 's' AS [Information], W1.latch_class, 
		W1.wait_time_s,
		W1.waiting_requests_count,
		CAST(W1.pct AS DECIMAL(14, 2)) AS pct,
		CAST(SUM(W2.pct) AS DECIMAL(14, 2)) AS overall_running_pct,
		CAST ((W1.wait_time_s / W1.waiting_requests_count) AS DECIMAL (14, 4)) AS avg_wait_s,
	CASE WHEN W1.latch_class LIKE N'ACCESS_METHODS_HOBT_COUNT' 
			OR W1.latch_class LIKE N'ACCESS_METHODS_HOBT_VIRTUAL_ROOT' THEN N'[HoBT - Metadata]'
		WHEN W1.latch_class LIKE N'ACCESS_METHODS_DATASET_PARENT' 
			OR W1.latch_class LIKE N'ACCESS_METHODS_SCAN_RANGE_GENERATOR' 
			OR W1.latch_class LIKE N'NESTING_TRANSACTION%' THEN N'[Parallelism]'
		WHEN W1.latch_class LIKE N'LOG_MANAGER' THEN N'[Log IO]'
		WHEN W1.latch_class LIKE N'TRACE_CONTROLLER' THEN N'[Trace]'
		WHEN W1.latch_class LIKE N'DBCC_MULTIOBJECT_SCANNER' THEN N'[Parallelism - DBCC CHECK_]'
		WHEN W1.latch_class LIKE N'FGCB_ADD_REMOVE' THEN N'[Other IO]'
		WHEN W1.latch_class LIKE N'DATABASE_MIRRORING_CONNECTION' THEN N'[Mirroring - Busy]'
		WHEN W1.latch_class LIKE N'BUFFER' THEN N'[Buffer Pool]'
		ELSE N'[Other]' END AS 'latch_category'
	FROM #tblFinalLatches AS W1 INNER JOIN #tblFinalLatches AS W2 ON W2.rn <= W1.rn
	GROUP BY W1.rn, W1.latch_class, W1.wait_time_s, W1.waiting_requests_count, CAST(W1.pct AS DECIMAL(14, 2))
	HAVING SUM(W2.pct) - CAST(W1.pct AS DECIMAL(14, 2)) < 100; -- percentage threshold
	
	;WITH Latches AS
		(SELECT latch_class,
			 CAST(wait_time_ms / 1000.0 AS DECIMAL(14, 2)) AS wait_time_s,
			 waiting_requests_count,
			 100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct,
			 ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS rn
		FROM sys.dm_os_latch_stats
		WHERE /*latch_class NOT IN ('BUFFER')
				AND*/ wait_time_ms > 0
		)
	SELECT 'Performance_checks' AS [Category], 'Cumulative_Latches' AS [Information], W1.latch_class, 
		W1.wait_time_s,
		W1.waiting_requests_count,
		CAST(W1.pct AS DECIMAL(14, 2)) AS pct,
		CAST(SUM(W2.pct) AS DECIMAL(14, 2)) AS overall_running_pct,
		CAST((W1.wait_time_s / W1.waiting_requests_count) AS DECIMAL (14, 4)) AS avg_wait_s,
		CASE WHEN W1.latch_class LIKE N'ACCESS_METHODS_HOBT_COUNT' 
			OR W1.latch_class LIKE N'ACCESS_METHODS_HOBT_VIRTUAL_ROOT' THEN N'[HoBT - Metadata]'
			WHEN W1.latch_class LIKE N'ACCESS_METHODS_DATASET_PARENT' 
				OR W1.latch_class LIKE N'ACCESS_METHODS_SCAN_RANGE_GENERATOR' 
				OR W1.latch_class LIKE N'NESTING_TRANSACTION_FULL' THEN N'[Parallelism]'
			WHEN W1.latch_class LIKE N'LOG_MANAGER' THEN N'[IO - Log]'
			WHEN W1.latch_class LIKE N'TRACE_CONTROLLER' THEN N'[Trace]'
			WHEN W1.latch_class LIKE N'DBCC_MULTIOBJECT_SCANNER ' THEN N'[Parallelism - DBCC CHECK_]'
			WHEN W1.latch_class LIKE N'FGCB_ADD_REMOVE' THEN N'[IO Operations]'
			WHEN W1.latch_class LIKE N'DATABASE_MIRRORING_CONNECTION ' THEN N'[Mirroring - Busy]'
			WHEN W1.latch_class LIKE N'BUFFER' THEN N'[Buffer Pool - PAGELATCH or PAGEIOLATCH]'
			ELSE N'Other' END AS 'latch_category'
	FROM Latches AS W1
	INNER JOIN Latches AS W2
		ON W2.rn <= W1.rn
	GROUP BY W1.rn, W1.latch_class, W1.wait_time_s, W1.waiting_requests_count, CAST(W1.pct AS DECIMAL(14, 2))
	HAVING SUM(W2.pct) - CAST(W1.pct AS DECIMAL(14, 2)) < 100; -- percentage threshold
	
	;WITH Latches AS
		(SELECT latch_class,
			 CAST(wait_time_ms / 1000.0 AS DECIMAL(14, 2)) AS wait_time_s,
			 waiting_requests_count,
			 100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS pct,
			 ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS rn
		FROM sys.dm_os_latch_stats (NOLOCK)
		WHERE latch_class NOT IN ('BUFFER')
				AND wait_time_ms > 0
		)
	SELECT 'Performance_checks' AS [Category], 'Cumulative_Latches_wo_BUFFER' AS [Information], W1.latch_class, 
		W1.wait_time_s,
		W1.waiting_requests_count,
		CAST(W1.pct AS DECIMAL(14, 2)) AS pct,
		CAST(SUM(W2.pct) AS DECIMAL(14, 2)) AS overall_running_pct,
		CAST((W1.wait_time_s / W1.waiting_requests_count) AS DECIMAL (14, 4)) AS avg_wait_s,
		CASE WHEN W1.latch_class LIKE N'ACCESS_METHODS_HOBT_COUNT' 
			OR W1.latch_class LIKE N'ACCESS_METHODS_HOBT_VIRTUAL_ROOT' THEN N'[HoBT - Metadata]'
			WHEN W1.latch_class LIKE N'ACCESS_METHODS_DATASET_PARENT' 
				OR W1.latch_class LIKE N'ACCESS_METHODS_SCAN_RANGE_GENERATOR' 
				OR W1.latch_class LIKE N'NESTING_TRANSACTION_FULL' THEN N'[Parallelism]'
			WHEN W1.latch_class LIKE N'LOG_MANAGER' THEN N'[IO - Log]'
			WHEN W1.latch_class LIKE N'TRACE_CONTROLLER' THEN N'[Trace]'
			WHEN W1.latch_class LIKE N'DBCC_MULTIOBJECT_SCANNER ' THEN N'[Parallelism - DBCC CHECK_]'
			WHEN W1.latch_class LIKE N'FGCB_ADD_REMOVE' THEN N'[IO Operations]'
			WHEN W1.latch_class LIKE N'DATABASE_MIRRORING_CONNECTION ' THEN N'[Mirroring - Busy]'
			WHEN W1.latch_class LIKE N'BUFFER' THEN N'[Buffer Pool - PAGELATCH or PAGEIOLATCH]'
			ELSE N'Other' END AS 'latch_category'
	FROM Latches AS W1
	INNER JOIN Latches AS W2
		ON W2.rn <= W1.rn
	GROUP BY W1.rn, W1.latch_class, W1.wait_time_s, W1.waiting_requests_count, CAST(W1.pct AS DECIMAL(14, 2))
	HAVING SUM(W2.pct) - CAST(W1.pct AS DECIMAL(14, 2)) < 100; -- percentage threshold

	;WITH cteSpinlocks1 AS (SELECT name, collisions, spins, spins_per_collision, sleep_time, backoffs FROM #tblSpinlocksBefore),
		cteSpinlocks2 AS (SELECT name, collisions, spins, spins_per_collision, sleep_time, backoffs FROM #tblSpinlocksAfter)
	INSERT INTO #tblFinalSpinlocks
	SELECT DISTINCT t1.name,
			(t2.collisions-t1.collisions) AS collisions,
			(t2.spins-t1.spins) AS spins,
			(t2.spins_per_collision-t1.spins_per_collision) AS spins_per_collision,
			(t2.sleep_time-t1.sleep_time) AS sleep_time,
			(t2.backoffs-t1.backoffs) AS backoffs,
			100.0 * (t2.spins-t1.spins) / SUM(t2.spins-t1.spins) OVER() AS spins_pct,
			ROW_NUMBER() OVER(ORDER BY t2.spins DESC) AS rn
	FROM cteSpinlocks1 t1 INNER JOIN cteSpinlocks2 t2 ON t1.name = t2.name
	GROUP BY t1.name, t1.collisions, t2.collisions, t1.spins, t2.spins, t1.spins_per_collision, t2.spins_per_collision, t1.sleep_time, t2.sleep_time, t1.backoffs, t2.backoffs
	HAVING (t2.spins-t1.spins) > 0
	ORDER BY spins DESC;

	SELECT 'Performance_checks' AS [Category], 'Spinlocks_Last_' + CONVERT(VARCHAR(3), @duration) + 's' AS [Information], S1.name, 
		S1.collisions, S1.spins, S1.spins_per_collision, S1.sleep_time, S1.backoffs,
		CAST(S1.spins_pct AS DECIMAL(14, 2)) AS spins_pct,
		CAST(SUM(S2.spins_pct) AS DECIMAL(14, 2)) AS overall_running_spins_pct
	FROM #tblFinalSpinlocks AS S1 INNER JOIN #tblFinalSpinlocks AS S2 ON S2.rn <= S1.rn
	GROUP BY S1.rn, S1.name, S1.collisions, S1.spins, S1.spins_per_collision, S1.sleep_time, S1.backoffs, S1.spins_pct
	HAVING CAST(SUM(S2.spins_pct) AS DECIMAL(14, 2)) - CAST(S1.spins_pct AS DECIMAL(14, 2)) < 100 -- percentage threshold
	ORDER BY spins DESC;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Worker thread exhaustion subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Worker thread exhaustion', 10, 1) WITH NOWAIT
	
	DECLARE @avgtskcnt int, @workqcnt int
	SELECT @avgtskcnt = SUM(runnable_tasks_count)/COUNT(scheduler_id), @workqcnt = SUM(work_queue_count) FROM sys.dm_os_schedulers
	WHERE parent_node_id < 64 AND scheduler_id < 255

	IF @avgtskcnt <= 2 AND @workqcnt > 1
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Worker_thread_exhaustion' AS [Check], '[WARNING: Possible worker thread exhaustion (schedulers work queue count is ' + CONVERT(NVARCHAR(10), @workqcnt) + '). Because overall runnable tasks count is ' + CONVERT(NVARCHAR(10), @avgtskcnt) + ' (<= 2), indicating the server might not be CPU bound, there might be room to increase max_worker_threads]' AS [Deviation], '[Configured workers = ' + CONVERT(VARCHAR(10),@mwthreads_count) + ']' AS [Comment]
	END
	ELSE IF @avgtskcnt > 2 AND @workqcnt > 1
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Worker_thread_exhaustion' AS [Check], '[WARNING: Possible worker thread exhaustion (schedulers work queue count is ' + CONVERT(NVARCHAR(10), @workqcnt) + '). Overall runnable tasks count is ' + CONVERT(NVARCHAR(10), @avgtskcnt) + ' (> 2), also indicating the server might be CPU bound]' AS [Deviation], '[Configured workers = ' + CONVERT(VARCHAR(10),@mwthreads_count) + ']' AS [Comment]
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Worker_thread_exhaustion' AS [Check], '[OK]' AS [Deviation], '' AS [Comment]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Blocking Chains subsection
-- Checks for blocking chains taking over 5s.
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Blocking Chains', 10, 1) WITH NOWAIT
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblBlkChains'))
	DROP TABLE #tblBlkChains;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblBlkChains'))
	CREATE TABLE #tblBlkChains ([blocked_spid] [smallint], [blocked_spid_status] NVARCHAR(30), [blocked_task_status] NVARCHAR(60),
		[blocked_spid_wait_type] NVARCHAR(60), [blocked_spid_wait_time_ms] [bigint], [blocked_spid_res_desc] NVARCHAR(1024),
		[blocked_pageid] [int], [blocked_spid_res_type] VARCHAR(24), [blocked_batch] [xml], [blocked_statement] [xml],
		[blocked_last_start] [datetime], [blocked_tran_isolation_level] VARCHAR(30), [blocker_spid] [smallint],
		[is_head_blocker] [int], [blocker_batch] [xml], [blocker_statement] [xml], [blocker_last_start] [datetime],
		[blocker_tran_isolation_level] VARCHAR(30), [blocked_database] NVARCHAR(128), [blocked_host] NVARCHAR(128),
		[blocked_program] NVARCHAR(128), [blocked_login] NVARCHAR(128), [blocked_session_comment] VARCHAR(25),
		[blocked_is_user_process] [bit], [blocker_database] NVARCHAR(128), [blocker_host] NVARCHAR(128),
		[blocker_program] NVARCHAR(128), [blocker_login] NVARCHAR(128), [blocker_session_comment] VARCHAR(25), [blocker_is_user_process] [bit])

	INSERT INTO #tblBlkChains
	SELECT 
		-- blocked
		es.session_id AS blocked_spid,
		es.[status] AS [blocked_spid_status],
		ot.task_state AS [blocked_task_status],
		owt.wait_type AS blocked_spid_wait_type,
		COALESCE(owt.wait_duration_ms, ABS(CONVERT(BIGINT,(DATEDIFF(mi, es.last_request_start_time, GETDATE())))*60)) AS blocked_spid_wait_time_ms,
		--er.total_elapsed_time AS blocked_elapsed_time_ms,
		/* 
			Check sys.dm_os_waiting_tasks for Exchange wait types in http://technet.microsoft.com/library/ms188743.aspx.
			- Wait Resource e_waitPipeNewRow in CXPACKET waits – Producer waiting on consumer for a packet to fill.
			- Wait Resource e_waitPipeGetRow in CXPACKET waits – Consumer waiting on producer to fill a packet.
		*/
		owt.resource_description AS blocked_spid_res_desc,
		owt.pageid AS blocked_pageid,
		CASE WHEN owt.pageid = 1 OR owt.pageid % 8088 = 0 THEN 'Is_PFS_Page'
			WHEN owt.pageid = 2 OR owt.pageid % 511232 = 0 THEN 'Is_GAM_Page'
			WHEN owt.pageid = 3 OR (owt.pageid - 1) % 511232 = 0 THEN 'Is_SGAM_Page'
			WHEN owt.pageid IS NULL THEN NULL
			ELSE 'Is_not_PFS_GAM_SGAM_page' END AS blocked_spid_res_type,
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			qt.[text],
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt 
			FOR XML PATH(''), TYPE) AS [blocked_batch],
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			SUBSTRING(qt2.text, 
			1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
			1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt2
			FOR XML PATH(''), TYPE) AS [blocked_statement],
		es.last_request_start_time AS blocked_last_start,
		LEFT (CASE COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot'
			ELSE CONVERT (VARCHAR(30), COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocked_tran_isolation_level,

		-- blocker
		er.blocking_session_id As blocker_spid,
		CASE 
			-- session has an active request, is blocked, but is blocking others or session is idle but has an open tran and is blocking others
			WHEN (er2.session_id IS NULL OR owt.blocking_session_id IS NULL) AND (er.blocking_session_id = 0 OR er.session_id IS NULL) THEN 1
			-- session is either not blocking someone, or is blocking someone but is blocked by another party
			ELSE 0
		END AS is_head_blocker,
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			qt2.[text],
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_batch],
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			SUBSTRING(qt2.text, 
			1+(CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END),
			1+(CASE WHEN er2.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er2.statement_end_offset/2 END - (CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END))),
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_statement],
		es2.last_request_start_time AS blocker_last_start,
		LEFT (CASE COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot' 
			ELSE CONVERT (VARCHAR(30), COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocker_tran_isolation_level,

		-- blocked - other data
		DB_NAME(er.database_id) AS blocked_database, 
		es.[host_name] AS blocked_host,
		es.[program_name] AS blocked_program, 
		es.login_name AS blocked_login,
		CASE WHEN es.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocked_session_comment,
		es.is_user_process AS [blocked_is_user_process],

		-- blocker - other data
		DB_NAME(er2.database_id) AS blocker_database,
		es2.[host_name] AS blocker_host,
		es2.[program_name] AS blocker_program,	
		es2.login_name AS blocker_login,
		CASE WHEN es2.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es2.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es2.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocker_session_comment,
		es2.is_user_process AS [blocker_is_user_process]
	FROM sys.dm_exec_sessions es
	LEFT OUTER JOIN sys.dm_exec_requests er ON es.session_id = er.session_id
	LEFT OUTER JOIN sys.dm_exec_connections ec ON es.session_id = ec.session_id
	LEFT OUTER JOIN sys.dm_os_tasks ot ON er.session_id = ot.session_id AND er.request_id = ot.request_id
	LEFT OUTER JOIN sys.dm_exec_sessions es2 ON er.blocking_session_id = es2.session_id
	LEFT OUTER JOIN sys.dm_exec_requests er2 ON es2.session_id = er2.session_id
	LEFT OUTER JOIN sys.dm_exec_connections ec2 ON es2.session_id = ec2.session_id
	LEFT OUTER JOIN 
	(
		-- In some cases (e.g. parallel queries, also waiting for a worker), one thread can be flagged as 
		-- waiting for several different threads.  This will cause that thread to show up in multiple rows 
		-- in our grid, which we don't want.  Use ROW_NUMBER to select the longest wait for each thread, 
		-- and use it as representative of the other wait relationships this thread is involved in. 
		SELECT  waiting_task_address, session_id, exec_context_id, wait_duration_ms, 
			wait_type, resource_address, blocking_task_address, blocking_session_id, 
			blocking_exec_context_id, resource_description,
			CASE WHEN [wait_type] LIKE 'PAGE%' AND [resource_description] LIKE '%:%' THEN CAST(RIGHT([resource_description], LEN([resource_description]) - CHARINDEX(':', [resource_description], LEN([resource_description])-CHARINDEX(':', REVERSE([resource_description])))) AS int)
				ELSE NULL END AS pageid,
			ROW_NUMBER() OVER (PARTITION BY waiting_task_address ORDER BY wait_duration_ms DESC) AS row_num
		FROM sys.dm_os_waiting_tasks
		WHERE wait_type <> 'SP_SERVER_DIAGNOSTICS_SLEEP'
	) owt ON ot.task_address = owt.waiting_task_address AND owt.row_num = 1
	--OUTER APPLY sys.dm_exec_sql_text (er.sql_handle) est
	--OUTER APPLY sys.dm_exec_query_plan (er.plan_handle) eqp
	WHERE es.session_id <> @@SPID AND es.is_user_process = 1 
		AND ((owt.wait_duration_ms/1000) > 5 OR (er.total_elapsed_time/1000) > 5 OR er.total_elapsed_time IS NULL) --Only report blocks > 5 Seconds plus head blocker
		AND (es.session_id IN (SELECT er3.blocking_session_id FROM sys.dm_exec_requests er3) OR er.blocking_session_id IS NOT NULL)
	ORDER BY blocked_spid, is_head_blocker DESC, blocked_spid_wait_time_ms DESC, blocker_spid;
		
	IF (SELECT COUNT(blocked_spid) FROM #tblBlkChains WHERE CONVERT(VARCHAR(max), blocked_batch) <> 'sp_server_diagnostics') > 0
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Blocking_Chains_over_5s' AS [Check], '[WARNING: Blocking chains in excess of 5s were found.]' AS [Deviation]
		SELECT 'Performance_checks' AS [Category], 'Blocking_Chains_over_5s' AS [Information],[blocked_spid],[blocked_spid_status],[blocked_task_status],
			[blocked_spid_wait_type],[blocked_spid_wait_time_ms],[blocked_spid_res_desc],[blocked_pageid],[blocked_spid_res_type],
			[blocked_batch],[blocked_statement],[blocked_last_start],[blocked_tran_isolation_level],[blocker_spid],[is_head_blocker],
			[blocker_batch],[blocker_statement],[blocker_last_start],[blocker_tran_isolation_level],[blocked_database],
			[blocked_host],[blocked_program],[blocked_login],[blocked_session_comment],[blocked_is_user_process],[blocker_database],
			[blocker_host],[blocker_program],[blocker_login],[blocker_session_comment],[blocker_is_user_process]
		FROM #tblBlkChains
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Blocking_Chains_over_5s' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Plan use ratio subsection
-- Refer to BOL for more information (https://docs.microsoft.com/sql/database-engine/configure-windows/optimize-for-ad-hoc-workloads-server-configuration-option)
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Plan use ratio', 10, 1) WITH NOWAIT

	IF (SELECT SUM(CAST(size_in_bytes AS bigint))/1024/1024 AS Size_MB
		FROM sys.dm_exec_cached_plans (NOLOCK)
		WHERE cacheobjtype LIKE '%Plan%' AND usecounts = 1) 
		>= 
		(SELECT SUM(CAST(size_in_bytes AS bigint))/1024/1024 AS Size_MB
		FROM sys.dm_exec_cached_plans (NOLOCK)
		WHERE cacheobjtype LIKE '%Plan%' AND usecounts > 1)
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Plan_use_ratio' AS [Check], '[WARNING: Amount of single use plans in cache is high]' AS [Deviation], CASE WHEN @sqlmajorver > 9 AND @adhoc = 0 THEN '[Consider enabling the Optimize for ad hoc workloads setting on heavy OLTP ad-hoc workloads to conserve resources]' ELSE '' END AS [Comment]
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Plan_use_ratio' AS [Check], '[OK]' AS [Deviation], '' AS [Comment]
	END;

	--High number of cached plans with usecounts = 1.
	SELECT 'Performance_checks' AS [Category], 'Plan_use_ratio' AS [Information], objtype, cacheobjtype, AVG(CAST(usecounts AS bigint)) AS Avg_UseCount_perPlan, SUM(refcounts) AS AllRefObjects, SUM(CAST(size_in_bytes AS bigint))/1024/1024 AS Size_MB
	FROM sys.dm_exec_cached_plans (NOLOCK)
	WHERE cacheobjtype LIKE '%Plan%' AND usecounts = 1
	GROUP BY objtype, cacheobjtype
	UNION ALL
	--High number of cached plans with usecounts > 1.
	SELECT 'Performance_checks' AS [Category], 'Plan_use_ratio' AS [Information], objtype, cacheobjtype, AVG(CAST(usecounts AS bigint)) AS Avg_UseCount_perPlan, SUM(refcounts) AS AllRefObjects, SUM(CAST(size_in_bytes AS bigint))/1024/1024 AS Size_MB
	FROM sys.dm_exec_cached_plans (NOLOCK)
	WHERE cacheobjtype LIKE '%Plan%' AND usecounts > 1
	GROUP BY objtype, cacheobjtype
	ORDER BY objtype, cacheobjtype;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Hints usage subsection
-- Refer to "Hints" BOL entry for more information (https://docs.microsoft.com/sql/t-sql/queries/hints-transact-sql)
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Hints usage', 10, 1) WITH NOWAIT
	IF (SELECT COUNT([counter]) FROM sys.dm_exec_query_optimizer_info WHERE ([counter] = 'order hint' OR [counter] = 'join hint') AND occurrence > 1) > 0
	BEGIN
		RAISERROR (N'    |-Hints are being used - finding usage in SQL modules', 10, 1) WITH NOWAIT
		
		/*DECLARE @dbid int, @dbname VARCHAR(1000), @sqlcmd NVARCHAR(4000)*/

		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHints'))
		DROP TABLE #tblHints;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHints'))
		CREATE TABLE #tblHints ([DBName] sysname, [Schema] VARCHAR(100), [Object] VARCHAR(255), [Type] VARCHAR(100), Hint VARCHAR(30));

		UPDATE #tmpdbs0
		SET isdone = 0;

		UPDATE #tmpdbs0
		SET isdone = 1
		WHERE [state] <> 0 OR [dbid] < 5;

		UPDATE #tmpdbs0
		SET isdone = 1
		WHERE [role] = 2 AND secondary_role_allow_connections = 0;

		IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
			BEGIN
				SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			
				SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], ss.name AS [Schema_Name], so.name AS [Object_Name], so.type_desc, 
	CASE WHEN sm.[definition] LIKE ''%FORCE ORDER%'' THEN ''[FORCE ORDER Hint]''
	WHEN sm.[definition] LIKE ''%MERGE JOIN%''
		OR sm.[definition] LIKE ''%LOOP JOIN%''
		OR sm.[definition] LIKE ''%HASH JOIN%'' THEN ''[JOIN Hint]'' END AS Hint
FROM sys.sql_modules sm
INNER JOIN sys.objects so ON sm.[object_id] = so.[object_id]
INNER JOIN sys.schemas ss ON so.[schema_id] = ss.[schema_id]
WHERE (sm.[definition] LIKE ''%FORCE ORDER%''
	OR sm.[definition] LIKE ''%MERGE JOIN%''
	OR sm.[definition] LIKE ''%LOOP JOIN%''
	OR sm.[definition] LIKE ''%HASH JOIN%'') 
AND OBJECTPROPERTY(sm.[object_id],''IsMSShipped'') = 0;'

				BEGIN TRY
					INSERT INTO #tblHints
					EXECUTE sp_executesql @sqlcmd
				END TRY
				BEGIN CATCH
					SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
					SELECT @ErrorMessage = 'Hints usage subsection - Error raised in TRY block. ' + ERROR_MESSAGE()
					RAISERROR (@ErrorMessage, 16, 1);
				END CATCH
			
				UPDATE #tmpdbs0
				SET isdone = 1
				WHERE [dbid] = @dbid
			END
		END;

		SELECT 'Performance_checks' AS [Category], 'Hints_usage' AS [Check], '[WARNING: Hints are being used. These can hinder the QO ability to optimize queries]' AS [Deviation]
		SELECT 'Performance_checks' AS [Category], 'Hints_usage' AS [Information], CASE WHEN [counter] = 'order hint' THEN '[FORCE ORDER Hint]' WHEN [counter] = 'join hint' THEN '[JOIN Hint]' END AS [Hint], occurrence
		FROM sys.dm_exec_query_optimizer_info (NOLOCK)
		WHERE ([counter] = 'order hint' OR [counter] = 'join hint') AND occurrence > 1;
		
		IF (SELECT COUNT(*) FROM #tblHints WHERE [DBName] IS NOT NULL) > 0
		BEGIN
			SELECT 'Performance_checks' AS [Category], 'Hints_usage_in_Objects' AS [Information], [DBName], [Schema], [Object], [Type], Hint, '' AS Comment
			FROM #tblHints (NOLOCK)
			ORDER BY [DBName], Hint, [Type], [Object];
		END
		ELSE
		BEGIN
			SELECT 'Performance_checks' AS [Category], 'Hints_usage_in_Objects' AS [Information], NULL AS [DBName], NULL AS [Schema], NULL AS [Object], NULL AS [Type],
				CASE WHEN [counter] = 'order hint' THEN '[FORCE ORDER Hint]' WHEN [counter] = 'join hint' THEN '[JOIN Hint]' END AS [Hint], '[INFORMATION: Hints may be in use with ad-hoc code]' AS Comment
			FROM sys.dm_exec_query_optimizer_info (NOLOCK)
			WHERE ([counter] = 'order hint' OR [counter] = 'join hint') AND occurrence > 1;
		END
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Hints_usage' AS [Check], '[OK]' AS [Deviation]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Cached Query Plans issues subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Cached Query Plans issues', 10, 1) WITH NOWAIT
	--DECLARE @sqlcmd NVARCHAR(max), @params NVARCHAR(500), @sqlmajorver int, @sqlminorver int, @sqlbuild int
	--SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
	--SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff);
	--SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_exec_query_stats')) 
	DROP TABLE #tmp_dm_exec_query_stats;

	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_exec_query_stats')) 
	CREATE TABLE #tmp_dm_exec_query_stats ([plan_id] [int] NOT NULL IDENTITY(1, 1),
		[sql_handle] [varbinary](64) NOT NULL,
		[statement_start_offset] [int] NOT NULL,
		[statement_end_offset] [int] NOT NULL,
		[plan_generation_num] [bigint] NOT NULL,
		[plan_handle] [varbinary](64) NOT NULL,
		[creation_time] [datetime] NOT NULL,
		[last_execution_time] [datetime] NOT NULL,
		[execution_count] [bigint] NOT NULL,
		[total_worker_time] [bigint] NOT NULL,
		[last_worker_time] [bigint] NOT NULL,
		[min_worker_time] [bigint] NOT NULL,
		[max_worker_time] [bigint] NOT NULL,
		[total_physical_reads] [bigint] NOT NULL,
		[last_physical_reads] [bigint] NOT NULL,
		[min_physical_reads] [bigint] NOT NULL,
		[max_physical_reads] [bigint] NOT NULL,
		[total_logical_writes] [bigint] NOT NULL,
		[last_logical_writes] [bigint] NOT NULL,
		[min_logical_writes] [bigint] NOT NULL,
		[max_logical_writes] [bigint] NOT NULL,
		[total_logical_reads] [bigint] NOT NULL,
		[last_logical_reads] [bigint] NOT NULL,
		[min_logical_reads] [bigint] NOT NULL,
		[max_logical_reads] [bigint] NOT NULL,
		[total_clr_time] [bigint] NOT NULL,
		[last_clr_time] [bigint] NOT NULL,
		[min_clr_time] [bigint] NOT NULL,
		[max_clr_time] [bigint] NOT NULL,
		[total_elapsed_time] [bigint] NOT NULL,
		[last_elapsed_time] [bigint] NOT NULL,
		[min_elapsed_time] [bigint] NOT NULL,
		[max_elapsed_time] [bigint] NOT NULL,
		--2008 only
		[query_hash] [binary](8) NULL,
		[query_plan_hash] [binary](8) NULL,
		--2008R2 only
		[total_rows] bigint NULL,
		[last_rows] bigint NULL,
		[min_rows] bigint NULL,
		[max_rows] bigint NULL,
		--post 2012 SP3, 2014 SP2 and 2016
		[Last_grant_kb] bigint NULL,
		[Min_grant_kb] bigint NULL,
		[Max_grant_kb] bigint NULL,
		[Total_grant_kb] bigint NULL,
		[Last_used_grant_kb] bigint NULL,
		[Min_used_grant_kb] bigint NULL,
		[Max_used_grant_kb] bigint NULL,
		[Total_used_grant_kb] bigint NULL,
		[Last_ideal_grant_kb] bigint NULL,
		[Min_ideal_grant_kb] bigint NULL,
		[Max_ideal_grant_kb] bigint NULL,
		[Total_ideal_grant_kb] bigint NULL,
		[Last_dop] bigint NULL,
		[Min_dop] bigint NULL,
		[Max_dop] bigint NULL,
		[Total_dop] bigint NULL,
		[Last_reserved_threads] bigint NULL,
		[Min_reserved_threads] bigint NULL,
		[Max_reserved_threads] bigint NULL,
		[Total_reserved_threads] bigint NULL,
		[Last_used_threads] bigint NULL,
		[Min_used_threads] bigint NULL,
		[Max_used_threads] bigint NULL,
		[Total_used_threads] bigint NULL,
		[Grant2Used_Ratio] float NULL)

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dm_exec_query_stats')) 
	DROP TABLE #dm_exec_query_stats;

	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dm_exec_query_stats')) 
	CREATE TABLE #dm_exec_query_stats ([plan_id] [int] NOT NULL IDENTITY(1, 1),
		[sql_handle] [varbinary](64) NOT NULL,
		[statement_start_offset] [int] NOT NULL,
		[statement_end_offset] [int] NOT NULL,
		[plan_generation_num] [bigint] NOT NULL,
		[plan_handle] [varbinary](64) NOT NULL,
		[creation_time] [datetime] NOT NULL,
		[last_execution_time] [datetime] NOT NULL,
		[execution_count] [bigint] NOT NULL,
		[total_worker_time] [bigint] NOT NULL,
		[last_worker_time] [bigint] NOT NULL,
		[min_worker_time] [bigint] NOT NULL,
		[max_worker_time] [bigint] NOT NULL,
		[total_physical_reads] [bigint] NOT NULL,
		[last_physical_reads] [bigint] NOT NULL,
		[min_physical_reads] [bigint] NOT NULL,
		[max_physical_reads] [bigint] NOT NULL,
		[total_logical_writes] [bigint] NOT NULL,
		[last_logical_writes] [bigint] NOT NULL,
		[min_logical_writes] [bigint] NOT NULL,
		[max_logical_writes] [bigint] NOT NULL,
		[total_logical_reads] [bigint] NOT NULL,
		[last_logical_reads] [bigint] NOT NULL,
		[min_logical_reads] [bigint] NOT NULL,
		[max_logical_reads] [bigint] NOT NULL,
		[total_clr_time] [bigint] NOT NULL,
		[last_clr_time] [bigint] NOT NULL,
		[min_clr_time] [bigint] NOT NULL,
		[max_clr_time] [bigint] NOT NULL,
		[total_elapsed_time] [bigint] NOT NULL,
		[last_elapsed_time] [bigint] NOT NULL,
		[min_elapsed_time] [bigint] NOT NULL,
		[max_elapsed_time] [bigint] NOT NULL,
		--2008 only
		[query_hash] [binary](8) NULL,
		[query_plan_hash] [binary](8) NULL,
		--2008R2 only
		[total_rows] bigint NULL,
		[last_rows] bigint NULL,
		[min_rows] bigint NULL,
		[max_rows] bigint NULL,
		--post 2012 SP3, 2014 SP2 and 2016
		[Last_grant_kb] bigint NULL,
		[Min_grant_kb] bigint NULL,
		[Max_grant_kb] bigint NULL,
		[Total_grant_kb] bigint NULL,
		[Last_used_grant_kb] bigint NULL,
		[Min_used_grant_kb] bigint NULL,
		[Max_used_grant_kb] bigint NULL,
		[Total_used_grant_kb] bigint NULL,
		[Last_ideal_grant_kb] bigint NULL,
		[Min_ideal_grant_kb] bigint NULL,
		[Max_ideal_grant_kb] bigint NULL,
		[Total_ideal_grant_kb] bigint NULL,
		[Last_dop] bigint NULL,
		[Min_dop] bigint NULL,
		[Max_dop] bigint NULL,
		[Total_dop] bigint NULL,
		[Last_reserved_threads] bigint NULL,
		[Min_reserved_threads] bigint NULL,
		[Max_reserved_threads] bigint NULL,
		[Total_reserved_threads] bigint NULL,
		[Last_used_threads] bigint NULL,
		[Min_used_threads] bigint NULL,
		[Max_used_threads] bigint NULL,
		[Total_used_threads] bigint NULL,
		[Grant2Used_Ratio] float NULL,
		--end
		[query_plan] [xml] NULL,
		[text] [nvarchar](MAX) COLLATE database_default NULL,
		[text_filtered] [nvarchar](MAX) COLLATE database_default NULL)

	IF @sqlmajorver = 9
	BEGIN
		--CPU 
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
		--FROM sys.dm_exec_query_stats qs (NOLOCK) 
		--ORDER BY qs.total_worker_time DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_worker_time DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_worker_time DESC');
		--IO
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_logical_reads DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_logical_reads DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_logical_reads DESC');
		--Recompiles
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.plan_generation_num DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.plan_generation_num DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.plan_generation_num DESC');
	END
	ELSE IF @sqlmajorver = 10 AND (@sqlminorver = 0 OR (@sqlminorver = 50 AND @sqlbuild < 2500))
	BEGIN
		--CPU 
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_worker_time DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_worker_time DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_worker_time DESC');
		--IO
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_logical_reads DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_logical_reads DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_logical_reads DESC');
		--Recompiles
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.plan_generation_num DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.plan_generation_num DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.plan_generation_num DESC');
	END
	ELSE IF (@sqlmajorver = 10 AND @sqlminorver = 50) OR (@sqlmajorver = 11 AND @sqlbuild < 6020) OR (@sqlmajorver = 12 AND @sqlbuild < 5000)
	BEGIN
		--CPU 
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_worker_time DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_worker_time DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_worker_time DESC');
		--IO
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_logical_reads DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_logical_reads DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_logical_reads DESC');
		--Recompiles
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.plan_generation_num DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.plan_generation_num DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],ix.query(''.'') AS StmtSimple
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.plan_generation_num DESC');
	END
	ELSE IF (@sqlmajorver = 11 AND @sqlbuild >= 6020) OR (@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver >= 13
	BEGIN
		--CPU 
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_worker_time DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],COALESCE((([Total_used_grant_kb] * 100.00) / NULLIF([Total_grant_kb],0)), 0) AS Grant2Used_Ratio
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_worker_time DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],ix.query(''.'') AS StmtSimple, Grant2Used_Ratio
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads], Grant2Used_Ratio
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_worker_time DESC');
		--IO
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.total_logical_reads DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],COALESCE((([Total_used_grant_kb] * 100.00) / NULLIF([Total_grant_kb],0)), 0) AS Grant2Used_Ratio
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.total_logical_reads DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],ix.query(''.'') AS StmtSimple, Grant2Used_Ratio
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads], Grant2Used_Ratio
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.total_logical_reads DESC');
		--Recompiles
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.plan_generation_num DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],COALESCE((([Total_used_grant_kb] * 100.00) / NULLIF([Total_grant_kb],0)), 0) AS Grant2Used_Ratio
FROM sys.dm_exec_query_stats qs (NOLOCK)
ORDER BY qs.plan_generation_num DESC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],ix.query(''.'') AS StmtSimple, Grant2Used_Ratio
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads], Grant2Used_Ratio
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.plan_generation_num DESC');
		--Mem Grants
		INSERT INTO #tmp_dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio])
		--EXEC ('SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads]
		--FROM sys.dm_exec_query_stats qs (NOLOCK)
		--ORDER BY qs.Total_grant_kb DESC');
		EXEC (';WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''), 
TopSearch AS (SELECT DISTINCT TOP 25 [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],COALESCE((([Total_used_grant_kb] * 100.00) / NULLIF([Total_grant_kb],0)), 0) AS Grant2Used_Ratio
FROM sys.dm_exec_query_stats qs (NOLOCK)
WHERE [Total_used_grant_kb] > 0
ORDER BY Total_used_grant_kb DESC, COALESCE((([Total_used_grant_kb] * 100.00) / NULLIF([Total_grant_kb],0)), 0) ASC),
TopFineSearch AS (SELECT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],ix.query(''.'') AS StmtSimple, Grant2Used_Ratio
FROM TopSearch ts
OUTER APPLY sys.dm_exec_query_plan(ts.plan_handle) qp
CROSS APPLY qp.query_plan.nodes(''//StmtSimple'') AS p(ix))
SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads], Grant2Used_Ratio
FROM TopFineSearch tfs
CROSS APPLY StmtSimple.nodes(''//Object'') AS o(obj)
WHERE obj.value(''@Database'',''sysname'') NOT IN (''[master]'',''[mssqlsystemresource]'')
ORDER BY tfs.Grant2Used_Ratio ASC');
	END;

	-- Remove duplicates before inserting XML
	IF @sqlmajorver = 9
	BEGIN
		INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time])
		SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time]
		FROM #tmp_dm_exec_query_stats;
	END
	ELSE IF @sqlmajorver = 10 AND (@sqlminorver = 0 OR (@sqlminorver = 50 AND @sqlbuild < 2500))
	BEGIN
		INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash])
		SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash]
		FROM #tmp_dm_exec_query_stats;
	END
	ELSE IF (@sqlmajorver = 10 AND @sqlminorver = 50) OR (@sqlmajorver = 11 AND @sqlbuild < 6020) OR (@sqlmajorver = 12 AND @sqlbuild < 5000)
	BEGIN
		INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows])
		SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows]
		FROM #tmp_dm_exec_query_stats;
	END
	ELSE IF (@sqlmajorver = 11 AND @sqlbuild >= 6020) OR (@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver >= 13
	BEGIN
		INSERT INTO #dm_exec_query_stats ([sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio])
		SELECT DISTINCT [sql_handle],[statement_start_offset],[statement_end_offset],[plan_generation_num],[plan_handle],[creation_time],[last_execution_time],[execution_count],[total_worker_time],[last_worker_time],[min_worker_time],[max_worker_time],[total_physical_reads],[last_physical_reads],[min_physical_reads],[max_physical_reads],[total_logical_writes],[last_logical_writes],[min_logical_writes],[max_logical_writes],[total_logical_reads],[last_logical_reads],[min_logical_reads],[max_logical_reads],[total_clr_time],[last_clr_time],[min_clr_time],[max_clr_time],[total_elapsed_time],[last_elapsed_time],[min_elapsed_time],[max_elapsed_time],[query_hash],[query_plan_hash],[total_rows],[last_rows],[min_rows],[max_rows],[Last_grant_kb],[Min_grant_kb],[Max_grant_kb],[Total_grant_kb],[Last_used_grant_kb],[Min_used_grant_kb],[Max_used_grant_kb],[Total_used_grant_kb],[Last_ideal_grant_kb],[Min_ideal_grant_kb],[Max_ideal_grant_kb],[Total_ideal_grant_kb],[Last_dop],[Min_dop],[Max_dop],[Total_dop],[Last_reserved_threads],[Min_reserved_threads],[Max_reserved_threads],[Total_reserved_threads],[Last_used_threads],[Min_used_threads],[Max_used_threads],[Total_used_threads],[Grant2Used_Ratio]
		FROM #tmp_dm_exec_query_stats;
	END;

	UPDATE #dm_exec_query_stats
	SET query_plan = qp.query_plan, 
		[text] = st.[text],
		text_filtered = SUBSTRING(st.[text], 
			(CASE WHEN qs.statement_start_offset = 0 THEN 0 ELSE qs.statement_start_offset/2 END),
			(CASE WHEN qs.statement_end_offset = -1 THEN DATALENGTH(st.[text]) ELSE qs.statement_end_offset/2 END - (CASE WHEN qs.statement_start_offset = 0 THEN 0 ELSE qs.statement_start_offset/2 END)))
	FROM #dm_exec_query_stats qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
	 
	-- Delete own queries
	DELETE FROM #dm_exec_query_stats
	WHERE CAST(query_plan AS NVARCHAR(MAX)) LIKE '%Query_Plan_Warnings%';

	-- Aggregate results
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#qpwarnings')) 
	DROP TABLE #qpwarnings;

	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#qpwarnings')) 
	CREATE TABLE #qpwarnings ([Deviation] VARCHAR(50), [Comment] VARCHAR(255), query_plan XML, [statement] XML)

	-- Find issues
	INSERT INTO #qpwarnings
	SELECT 'Scalar_UDFs'AS [Deviation],
		('[WARNING: Scalar UDF found in a top resource-intensive query, which that may inhibit parallelism]') AS [Comment],
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%UserDefinedFunction%'
	UNION ALL
	SELECT 'Implicit_Conversion_with_IX_Scan'AS [Deviation],
		('[WARNING: Implicit type conversions found where an Index Scan is present]') AS Details ,
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
		AND CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Index Scan"%'
	UNION ALL
	SELECT 'Missing_Index'AS [Deviation],
		('[WARNING: One of the top resource-intensive queries may be improved by adding an index]') AS [Comment],
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%MissingIndexGroup%'
	UNION ALL
	SELECT 'Cursor'AS [Deviation],
		('[WARNING: Cursor usage found in a top resource-intensive query. Check if it can be rewritten as a WHILE cycle]') AS [Comment],
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<CursorType%'
	UNION ALL
	SELECT 'Missing_Join_Predicate'AS [Deviation],
		('[WARNING: NO JOIN predicate event fired for a top resource-intensive query]') AS [Comment],
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<Warnings NoJoinPredicate="true"%'
	UNION ALL
	SELECT 'Columns_with_no_Statistics'AS [Deviation],
		('[WARNING: Missing Column Statistics event fired for a top resource-intensive query]') AS [Comment],
		qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
	FROM #dm_exec_query_stats qs
	WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<Warnings ColumnsWithNoStatistics%';

	IF @sqlmajorver > 10
	BEGIN
		INSERT INTO #qpwarnings
		-- Note that currently SpillToTempDb warnings are only found in actual execution plans
		SELECT 'Spill_to_TempDb'AS [Deviation],
			('[WARNING: Spill to TempDB found during a HASH or SORT operation]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<SpillToTempDb SpillLevel%'
		UNION ALL
		SELECT 'Implicit_Convert_affecting_Seek_Plan'AS [Deviation],
			('[WARNING: Implicit type conversions found, which can be affecting the choice of seek plans]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<PlanAffectingConvert ConvertIssue="Seek Plan" Expression="CONVERT_IMPLICIT%'
		UNION ALL
		SELECT 'Explicit_Conversion_affecting_Cardinality'AS [Deviation],
			('[WARNING: Explicit type conversions found, which can be affecting cardinality estimates]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<PlanAffectingConvert ConvertIssue="Cardinality Estimate" Expression="CONVERT%'
		UNION ALL
		SELECT 'Implicit_Conversion_affecting_Cardinality'AS [Deviation],
			('[WARNING: Implicit type conversions found, which can be affecting cardinality estimates]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<PlanAffectingConvert ConvertIssue="Cardinality Estimate" Expression="CONVERT_IMPLICIT%'
		UNION ALL
		SELECT 'Unmatched_Indexes'AS [Deviation],
			('[WARNING: An unmatched indexes warning fired, where an index could not be used due to parameterization]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<Warnings UnmatchedIndexes="true"%';
	END;

	IF (@sqlmajorver = 12 AND @sqlbuild >= 5000) OR @sqlmajorver >= 13
	BEGIN
		INSERT INTO #qpwarnings
		-- Note that currently MemoryGrant warnings are only found in actual execution plans
		SELECT 'Excessive_Memory_Grant'AS [Deviation],
			('[WARNING: Granted memory was much larger than maximum used memory]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<MemoryGrantWarning GrantWarningKind="Excessive Grant"%'
		UNION ALL
		SELECT 'Excessive_Memory_Grant'AS [Deviation],
			('[WARNING: Maximum used memory exceeds granted memory]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<MemoryGrantWarning GrantWarningKind="Used More Than Granted"%'
		UNION ALL
		SELECT 'Excessive_Memory_Grant'AS [Deviation],
			('[WARNING: Dynamic grant increased too much when compared to initial grant request]') AS [Comment],
			qs.query_plan, (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qs.text_filtered, 
		NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
		FOR XML PATH(''), TYPE) AS [statement]
		FROM #dm_exec_query_stats qs
		WHERE CAST(qs.query_plan AS NVARCHAR(MAX)) LIKE '%<MemoryGrantWarning GrantWarningKind="Grant Increase"%'
	END;		

	IF (SELECT COUNT(*) FROM #qpwarnings) > 0
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Query_Plan_Warnings' AS [Check], '[WARNING: Top resource-intensive queries issued plan level warnings]' AS [Deviation]
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Query_Plan_Warnings' AS [Check], '[OK]' AS [Deviation]
	END;

	IF (SELECT COUNT(*) FROM #qpwarnings) > 0
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Query_Plan_Warnings' AS [Check], [Comment], query_plan, [statement]
		FROM #qpwarnings;
	END;

	IF (SELECT COUNT(*) FROM #dm_exec_query_stats) > 0
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Inefficient_Plans_Reads' AS [Check], query_plan, 
			(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				text_filtered, 
				NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
				FOR XML PATH(''), TYPE) AS [statement],
			[execution_count], [total_worker_time]/[execution_count] AS [Avg_Worker_Time],
			[total_physical_reads]/[execution_count] AS [Avg_Physical_Reads],
			[total_logical_reads]/[execution_count] AS [Avg_Logical_Reads],
			CASE WHEN [Total_grant_kb] IS NOT NULL THEN [Total_grant_kb]/[execution_count] ELSE -1 END AS [Avg_grant_kb],
			CASE WHEN [Total_used_grant_kb] IS NOT NULL THEN [Total_used_grant_kb]/[execution_count] ELSE -1 END AS [Avg_used_grant_kb],
			[Grant2Used_Ratio],
			CASE WHEN [Total_ideal_grant_kb] IS NOT NULL THEN [Total_ideal_grant_kb]/[execution_count] ELSE -1 END AS [Avg_ideal_grant_kb],
			CASE WHEN [Total_dop] IS NOT NULL THEN [Total_dop]/[execution_count] ELSE -1 END AS [Avg_dop],
			CASE WHEN [Total_reserved_threads] IS NOT NULL THEN [Total_reserved_threads]/[execution_count] ELSE -1 END AS [Avg_reserved_threads],
			CASE WHEN [Total_used_threads] IS NOT NULL THEN [Total_used_threads]/[execution_count] ELSE -1 END AS [Avg_used_threads]
		FROM #dm_exec_query_stats
		ORDER BY [Avg_Logical_Reads] DESC;
		
		SELECT 'Performance_checks' AS [Category], 'Inefficient_Plans_CPU' AS [Check], query_plan, 
			(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				text_filtered, 
				NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
				FOR XML PATH(''), TYPE) AS [statement],
			[execution_count], [total_worker_time]/[execution_count] AS [Avg_Worker_Time], 
			[total_physical_reads]/[execution_count] AS [Avg_Physical_Reads],
			[total_logical_reads]/[execution_count] AS [Avg_Logical_Reads],
			CASE WHEN [Total_grant_kb] IS NOT NULL THEN [Total_grant_kb]/[execution_count] ELSE -1 END AS [Avg_grant_kb],
			CASE WHEN [Total_used_grant_kb] IS NOT NULL THEN [Total_used_grant_kb]/[execution_count] ELSE -1 END AS [Avg_used_grant_kb],
			[Grant2Used_Ratio],
			CASE WHEN [Total_ideal_grant_kb] IS NOT NULL THEN [Total_ideal_grant_kb]/[execution_count] ELSE -1 END AS [Avg_ideal_grant_kb],
			CASE WHEN [Total_dop] IS NOT NULL THEN [Total_dop]/[execution_count] ELSE -1 END AS [Avg_dop],
			CASE WHEN [Total_reserved_threads] IS NOT NULL THEN [Total_reserved_threads]/[execution_count] ELSE -1 END AS [Avg_reserved_threads],
			CASE WHEN [Total_used_threads] IS NOT NULL THEN [Total_used_threads]/[execution_count] ELSE -1 END AS [Avg_used_threads]
		FROM #dm_exec_query_stats
		ORDER BY [Avg_Worker_Time] DESC;
		
		SELECT 'Performance_checks' AS [Category], 'Inefficient_Memory_Use' AS [Check], query_plan, 
			(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				text_filtered, 
				NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
				FOR XML PATH(''), TYPE) AS [statement],
			[execution_count], [total_worker_time]/[execution_count] AS [Avg_Worker_Time],
			[total_physical_reads]/[execution_count] AS [Avg_Physical_Reads],
			[total_logical_reads]/[execution_count] AS [Avg_Logical_Reads],
			CASE WHEN [Total_grant_kb] IS NOT NULL THEN [Total_grant_kb]/[execution_count] ELSE -1 END AS [Avg_grant_kb],
			CASE WHEN [Total_used_grant_kb] IS NOT NULL THEN [Total_used_grant_kb]/[execution_count] ELSE -1 END AS [Avg_used_grant_kb],
			[Grant2Used_Ratio],
			CASE WHEN [Total_ideal_grant_kb] IS NOT NULL THEN [Total_ideal_grant_kb]/[execution_count] ELSE -1 END AS [Avg_ideal_grant_kb],
			CASE WHEN [Total_dop] IS NOT NULL THEN [Total_dop]/[execution_count] ELSE -1 END AS [Avg_dop],
			CASE WHEN [Total_reserved_threads] IS NOT NULL THEN [Total_reserved_threads]/[execution_count] ELSE -1 END AS [Avg_reserved_threads],
			CASE WHEN [Total_used_threads] IS NOT NULL THEN [Total_used_threads]/[execution_count] ELSE -1 END AS [Avg_used_threads]
		FROM #dm_exec_query_stats
		ORDER BY Grant2Used_Ratio ASC;
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Tuning recommendations info subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 13 AND @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Tuning recommendations', 10, 1) WITH NOWAIT
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendationsCnt'))
	DROP TABLE #tblTuningRecommendationsCnt;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendationsCnt'))
	CREATE TABLE #tblTuningRecommendationsCnt ([DBName] sysname, [dbid] int, [HasRecommendations] bit);
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendations'))
	DROP TABLE #tblTuningRecommendations;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendations'))
	CREATE TABLE #tblTuningRecommendations ([DBName] sysname, [query_id] bigint,
		[reason] NVARCHAR(4000), [score] int, [CurrentState] NVARCHAR(4000), [CurrentStateReason] NVARCHAR(4000), [query_sql_text] NVARCHAR(max),
		[RegressedPlan] [xml], [SuggestedPlan] [xml], [ImplementationScript] NVARCHAR(100));

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] = 2;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], ''' + REPLACE(@dbid, CHAR(39), CHAR(95)) + ''' AS [dbid], CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM sys.dm_db_tuning_recommendations;'

			BEGIN TRY
				INSERT INTO #tblTuningRecommendationsCnt
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Tuning Recommendations subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;

	IF EXISTS (SELECT COUNT([DBName]) FROM #tblTuningRecommendationsCnt WHERE [HasRecommendations] = 1)
	BEGIN
		UPDATE #tmpdbs0
		SET isdone = 0
		FROM #tblTuningRecommendationsCnt AS trc
		INNER JOIN #tmpdbs0 ON #tmpdbs0.[dbid] = trc.[dbid]
		WHERE [state] <> 0 AND trc.[HasRecommendations] = 1;
	
		IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN	
			WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
			BEGIN
				SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
				SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
;WITH CTE_Tuning_Recs AS (SELECT tr.reason, 
		tr.score, 
		JSON_VALUE(tr.details,''$.query_id'') AS query_id, 
		JSON_VALUE(tr.details,''$.regressedPlanId'') AS regressedPlanId, 
		JSON_VALUE(tr.details,''$.recommendedPlanId'') AS recommendedPlanId,
		JSON_VALUE(tr.state,''$.currentValue'') AS CurrentState,
		JSON_VALUE(tr.state,''$.reason'') AS CurrentStateReason,
		(CAST(JSON_VALUE(tr.state,''$.regressedPlanExecutionCount'') AS int) + CAST(JSON_VALUE(tr.state,''$.recommendedPlanExecutionCount'') AS int)) 
		* (CAST(JSON_VALUE(tr.state,''$.regressedPlanCpuTimeAverage'') AS float) - CAST(JSON_VALUE(tr.state,''$.recommendedPlanCpuTimeAverage'') AS float))/1000000 AS Estimated_Gain,
		CASE WHEN CAST(JSON_VALUE(tr.state,''$.regressedPlanErrorCount'') AS int) > CAST(JSON_VALUE(tr.state,''$.recommendedPlanErrorCount'') AS int) THEN 1 ELSE 0 END AS Error_Prone,
		JSON_VALUE(tr.details,''$.implementationDetails.script'') AS ImplementationScript
	FROM sys.dm_db_tuning_recommendations AS tr
	)
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], qsq.query_id, cte.reason, cte.score, cte.CurrentState, cte.CurrentStateReason, qsqt.query_sql_text,
	CAST(rp.query_plan AS XML) AS RegressedPlan, CAST(sp.query_plan AS XML) AS SuggestedPlan, cte.ImplementationScript
FROM CTE_Tuning_Recs AS cte
INNER JOIN sys.query_store_plan AS rp ON rp.query_id = cte.[query_id] AND rp.plan_id = cte.regressedPlanId
INNER JOIN sys.query_store_plan AS sp ON sp.query_id = cte.[query_id] AND sp.plan_id = cte.recommendedPlanId
INNER JOIN sys.query_store_query AS qsq	ON qsq.query_id = rp.query_id 
INNER JOIN sys.query_store_query_text AS qsqt ON qsqt.query_text_id = qsq.query_text_id;'

			BEGIN TRY
				INSERT INTO #tblTuningRecommendations
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Tuning Recommendations List subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
			END
		END
		
		IF (SELECT COUNT(query_id) FROM #tblTuningRecommendations) > 0
		BEGIN
		SELECT 'Performance_checks' AS [Category], 'Automatic_Tuning_Recommendations' AS [Check], '[INFORMATION: Found tuning recommendations. If Automatic Tuning is not configured to deploy these recommednations, review manually and decide which ones to deploy]' AS Comment
		SELECT 'Performance_checks' AS [Category], 'Automatic_Tuning_Recommendations' AS [Check], DBName AS [Database_Name], 
			[query_id], [reason], [score], [CurrentState], [CurrentStateReason],
			(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				tr2.query_sql_text,
				NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
				AS [text()]
				FROM #tblTuningRecommendations (NOLOCK) AS tr2
				WHERE tr2.DBName = tr.DBName AND tr2.query_id = tr.query_id
				FOR XML PATH(''), TYPE) AS [query_sql_text],
			[RegressedPlan], [SuggestedPlan], [ImplementationScript]
		FROM #tblTuningRecommendations AS tr;
		END
		ELSE
		BEGIN
			SELECT 'Performance_checks' AS [Category], 'Automatic_Tuning_Recommendations' AS [Check], '[INFORMATION: Found tuning recommendations but Query Store does not contain any information on the queries anymore. Skipping]' AS Comment
		END
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'Automatic_Tuning_Recommendations' AS [Check], '[NA]' AS Comment
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Declarative Referential Integrity - Untrusted Constraints subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Declarative Referential Integrity - Untrusted Constraints', 10, 1) WITH NOWAIT
	/*
	Declarative Referential Integrity (DRI), meaning “trusting” constraints will allow SQL Server to introduce optimizations that would otherwise not be possible, 
	such as eliminating JOINs or even not reading any table for particular queries. 
	For example, if a search argument is looking for when a column IS NULL, but there is a NOT NULL constraint in place, the table might not even be accessed from a data read standpoint. 
	*/
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDRI'))
	DROP TABLE #tblDRI;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDRI'))
	CREATE TABLE #tblDRI ([databaseID] int, [database_name] sysname, [schema_id] int, [schema_name] VARCHAR(100), [object_id] int, [table_name] VARCHAR(200), [constraint_name] VARCHAR(200), [constraint_type] VARCHAR(10)
		CONSTRAINT PK_DRI PRIMARY KEY CLUSTERED(databaseID, [schema_id], [object_id], [constraint_name]))

	UPDATE #tmpdbs1
	SET isdone = 0

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
	SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE ' + QUOTENAME(@dbname) + '
SELECT ''' + CONVERT(VARCHAR(12),@dbid) + ''' AS [databaseID], ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [database_name], o.[schema_id], t.name AS [schema_name], mst.[object_id], mst.name AS [table_name], FKC.name AS [constraint_name], ''ForeignKey'' As [constraint_type]
FROM sys.foreign_keys FKC (NOLOCK)
INNER JOIN sys.objects o (NOLOCK) ON FKC.parent_object_id = o.[object_id]
INNER JOIN sys.tables mst (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.type = ''U'' AND FKC.is_not_trusted = 1 AND FKC.is_not_for_replication = 0
GROUP BY o.[schema_id], mst.[object_id], FKC.name, t.name, mst.name
UNION ALL
SELECT ''' + CONVERT(VARCHAR(12),@dbid) + ''' AS [databaseID], ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [database_name], t.[schema_id], t.name AS [schema_name], mst.[object_id], mst.name AS [table_name], CC.name AS [constraint_name], ''Check'' As [constraint_type]
FROM sys.check_constraints CC (NOLOCK)
INNER JOIN sys.objects o (NOLOCK) ON CC.parent_object_id = o.[object_id]
INNER JOIN sys.tables mst (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.type = ''U'' AND CC.is_not_trusted = 1 AND CC.is_not_for_replication = 0 AND CC.is_disabled = 0
GROUP BY t.[schema_id], mst.[object_id], CC.name, t.name, mst.name
ORDER BY mst.name, [constraint_name];'
		BEGIN TRY
			INSERT INTO #tblDRI
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Declarative Referential Integrity subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END;

	IF (SELECT COUNT(*) FROM #tblDRI) > 0
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'DRI_UntrustedConstraints' AS [Check], '[WARNING: Some constraints are not trusted for referential integrity. It is recommended to revise these due to possible performance issues]' AS [Deviation]
		SELECT 'Performance_checks' AS [Category], 'DRI_UntrustedConstraints' AS [Information], [database_name] AS [Database_Name], constraint_name AS [Constraint_Name],
			[schema_name] AS [Schema_Name], table_name AS [Table_Name], [constraint_type] AS [Constraint_Type]
		FROM #tblDRI
		ORDER BY [database_name], [schema_name], table_name, [constraint_type];
		
		IF @gen_scripts = 1
		BEGIN
			DECLARE @strSQL1 NVARCHAR(4000)
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			PRINT CHAR(10) + '--############# Trust untrusted Contraints statements #############' + CHAR(10)
			DECLARE cDRI CURSOR FAST_FORWARD FOR SELECT 'USE ' + [database_name] + CHAR(10) + 'GO' + CHAR(10) + 
			'ALTER TABLE ' + QUOTENAME([schema_name]) + '.' + QUOTENAME(table_name) + CHAR(10) +
			'WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(constraint_name) + CHAR(10) + 'GO'
			FROM #tblDRI
			ORDER BY [database_name], [schema_name], table_name, [constraint_type]
				
			OPEN cDRI
			FETCH NEXT FROM cDRI INTO @strSQL1
			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				PRINT @strSQL1
				FETCH NEXT FROM cDRI INTO @strSQL1
			END
			CLOSE cDRI
			DEALLOCATE cDRI
			PRINT CHAR(10) + '--############# Ended Trust untrusted Contraints statements #############' + CHAR(10)
		END;
	END
	ELSE
	BEGIN
		SELECT 'Performance_checks' AS [Category], 'DRI_UntrustedConstraints' AS [Check], '[OK]' AS [Deviation]
	END;
END;

IF @ptochecks = 1
RAISERROR (N'|-Starting Indexes and Statistics Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Statistics update subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Statistics update', 10, 1) WITH NOWAIT

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	DECLARE @dbcmptlevel int

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsUpd'))
	DROP TABLE #tblStatsUpd;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsUpd'))
	CREATE TABLE #tblStatsUpd ([DatabaseName] sysname, [databaseID] int, objectID int, schemaName VARCHAR(100), [tableName] VARCHAR(250), last_updated DATETIME, [rows] bigint, modification_counter bigint, [stats_id] int, [stat_name] VARCHAR(255), auto_created bit, user_created bit, has_filter bit NULL, filter_definition NVARCHAR(MAX) NULL, unfiltered_rows bigint, steps int)

	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid], @dbcmptlevel = [compatibility_level] FROM #tmpdbs0 WHERE isdone = 0
			IF ((@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4000) OR (@sqlmajorver = 11 AND @sqlbuild >= 3000) OR @sqlmajorver > 11) AND @dbcmptlevel > 80
			BEGIN
				SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT DISTINCT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DatabaseName], ''' + CONVERT(VARCHAR(12),@dbid) + ''' AS [databaseID], mst.[object_id] AS objectID, t.name AS schemaName, OBJECT_NAME(mst.[object_id]) AS tableName, 
	sp.last_updated, sp.[rows], sp.modification_counter, ss.[stats_id], ss.name AS [stat_name], ss.auto_created, ss.user_created, ss.has_filter, ss.filter_definition, sp.unfiltered_rows, sp.steps
FROM sys.objects AS o
	INNER JOIN sys.tables AS mst ON mst.[object_id] = o.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.stats AS ss ON ss.[object_id] = mst.[object_id]
	CROSS APPLY sys.dm_db_stats_properties(ss.[object_id], ss.[stats_id]) AS sp
WHERE sp.[rows] > 0
	AND	((sp.[rows] <= 500 AND sp.modification_counter >= 500)
		OR (sp.[rows] > 500 AND sp.modification_counter >= (500 + sp.[rows] * 0.20)))'
			END
			ELSE
			BEGIN
				SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT DISTINCT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DatabaseName], ''' + CONVERT(VARCHAR(12),@dbid) + ''' AS [databaseID], mst.[object_id] AS objectID, t.name AS schemaName, OBJECT_NAME(mst.[object_id]) AS tableName, 
	STATS_DATE(mst.[object_id], ss.stats_id) AS last_updated, SUM(p.[rows]) AS [rows], si.rowmodctr AS modification_counter, ss.stats_id, ss.name AS [stat_name], ss.auto_created, ss.user_created, NULL, NULL, NULL, NULL
FROM sys.sysindexes AS si
	INNER JOIN sys.objects AS o ON si.id = o.[object_id]
	INNER JOIN sys.tables AS mst ON mst.[object_id] = o.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.stats AS ss ON ss.[object_id] = o.[object_id]
	INNER JOIN sys.partitions AS p ON p.[object_id] = ss.[object_id]
	LEFT JOIN sys.indexes i ON si.id = i.[object_id] AND si.indid = i.index_id
WHERE o.type <> ''S'' AND i.name IS NOT NULL
GROUP BY mst.[object_id], t.name, rowmodctr, ss.stats_id, ss.name, ss.auto_created, ss.user_created
HAVING SUM(p.[rows]) > 0
	AND	((SUM(p.[rows]) <= 500 AND rowmodctr >= 500)
		OR (SUM(p.[rows]) > 500 AND rowmodctr >= (500 + SUM(p.[rows]) * 0.20)))'
			END

			BEGIN TRY
				INSERT INTO #tblStatsUpd
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Statistics update subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;
	
	CREATE INDEX IX_Stats ON #tblStatsUpd([databaseID]);

	IF (SELECT COUNT(*) FROM #tblStatsUpd) > 0
	BEGIN
	IF (SELECT COUNT(*) FROM master.sys.databases (NOLOCK) WHERE is_auto_update_stats_on = 0) > 0 AND (SELECT COUNT(*) FROM #tblStatsUpd AS su INNER JOIN master.sys.databases AS sd (NOLOCK) ON su.[databaseID] = sd.[database_id] WHERE sd.is_auto_update_stats_on = 0) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_to_update' AS [Check], '[WARNING: Some databases have Auto_Update_Statistics DISABLED and statistics that might need to be updated]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_to_update' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [tableName] AS [Table_Name], [stats_id] AS [statsID], [stat_name] AS [Statistic_Name],
			last_updated, [rows], modification_counter, CAST((su.modification_counter*1.00/(su.[rows]*1.00))*100.0 AS DECIMAL(18,2)) AS [RowMod_Pct],
			CASE WHEN su.auto_created = 0 AND su.user_created = 0 THEN 'Index_Statistic'
				WHEN su.auto_created = 0 AND su.user_created = 1 THEN 'User_Created'
				WHEN su.auto_created = 1 AND su.user_created = 0 THEN 'Auto_Created'
				ELSE NULL
			END AS [Statistic_Type],
			su.steps, su.has_filter AS [Is_Filtered], su.filter_definition AS [Filter_Definition], su.unfiltered_rows AS [Unfiltered_Rows]
			FROM #tblStatsUpd AS su INNER JOIN master.sys.databases AS sd (NOLOCK) ON su.[databaseID] = sd.[database_id] 
			WHERE sd.is_auto_update_stats_on = 0
			ORDER BY [DatabaseName], [tableName], [stats_id] DESC
		END;

	IF (SELECT COUNT(*) FROM #tblStatsUpd AS su INNER JOIN master.sys.databases AS sd (NOLOCK) ON su.[databaseID] = sd.[database_id] WHERE sd.is_auto_update_stats_on = 1) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_to_update' AS [Check], '[WARNING: Some databases have Auto_Update_Statistics ENABLED and statistics that might need to be updated]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_to_update' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [tableName] AS [Table_Name], [stats_id] AS [statsID], [stat_name] AS [Statistic_Name],
			last_updated, [rows], modification_counter, CAST((su.modification_counter*1.00/(su.[rows]*1.00))*100.0 AS DECIMAL(18,2)) AS [RowMod_Pct],
			CASE WHEN su.auto_created = 0 AND su.user_created = 0 THEN 'Index_Statistic'
				WHEN su.auto_created = 0 AND su.user_created = 1 THEN 'User_Created'
				WHEN su.auto_created = 1 AND su.user_created = 0 THEN 'Auto_Created'
				ELSE NULL
			END AS [Statistic_Type],
			su.steps, su.has_filter AS [Is_Filtered], su.filter_definition AS [Filter_Definition]
			FROM #tblStatsUpd AS su INNER JOIN master.sys.databases AS sd (NOLOCK) ON su.[databaseID] = sd.[database_id] 
			WHERE sd.is_auto_update_stats_on = 1
			ORDER BY [DatabaseName], [tableName], [stats_id] DESC
		END;
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_to_update' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Statistics sampling subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	IF (@sqlmajorver = 10 AND @sqlminorver = 50 AND @sqlbuild >= 4000) OR (@sqlmajorver = 11 AND @sqlbuild >= 3000) OR @sqlmajorver > 11
	BEGIN
		RAISERROR (N'  |-Starting Statistics sampling', 10, 1) WITH NOWAIT

		IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsSamp'))
		DROP TABLE #tblStatsSamp;
		IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsSamp'))
		CREATE TABLE #tblStatsSamp ([DatabaseName] sysname, [databaseID] int, objectID int, schemaName VARCHAR(100), [tableName] VARCHAR(250), last_updated DATETIME, [rows] bigint, modification_counter bigint, [stats_id] int, [stat_name] VARCHAR(255), rows_sampled bigint, auto_created bit, user_created bit, has_filter bit NULL, filter_definition NVARCHAR(MAX) NULL, unfiltered_rows bigint, steps int)

		UPDATE #tmpdbs0
		SET isdone = 0;

		UPDATE #tmpdbs0
		SET isdone = 1
		WHERE [state] <> 0 OR [dbid] < 5;

		UPDATE #tmpdbs0
		SET isdone = 1
		WHERE [role] = 2 AND secondary_role_allow_connections = 0;

		IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN		
			WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
			BEGIN
				SELECT TOP 1 @dbname = [dbname], @dbid = [dbid], @dbcmptlevel = [compatibility_level] FROM #tmpdbs0 WHERE isdone = 0
				IF @dbcmptlevel > 80
				BEGIN
					SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT DISTINCT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DatabaseName], ''' + CONVERT(VARCHAR(12),@dbid) + ''' AS [databaseID], mst.[object_id] AS objectID, t.name AS schemaName, OBJECT_NAME(mst.[object_id]) AS tableName, 
	sp.last_updated, sp.[rows], sp.modification_counter, ss.[stats_id], ss.name AS [stat_name], sp.rows_sampled, ss.auto_created, ss.user_created, ss.has_filter, ss.filter_definition, sp.unfiltered_rows, sp.steps
FROM sys.objects AS o
	INNER JOIN sys.tables AS mst ON mst.[object_id] = o.[object_id]
	INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
	INNER JOIN sys.stats AS ss ON ss.[object_id] = mst.[object_id]
	CROSS APPLY sys.dm_db_stats_properties(ss.[object_id], ss.[stats_id]) AS sp
WHERE sp.[rows] > 0
	AND	CAST((sp.rows_sampled/(sp.[rows]*1.00))*100.0 AS DECIMAL(5,2)) < 25'

					BEGIN TRY
						INSERT INTO #tblStatsSamp
						EXECUTE sp_executesql @sqlcmd
					END TRY
					BEGIN CATCH
						SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
						SELECT @ErrorMessage = 'Statistics sampling subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
						RAISERROR (@ErrorMessage, 16, 1);
					END CATCH
				END
				
				UPDATE #tmpdbs0
				SET isdone = 1
				WHERE [dbid] = @dbid
			END
		END;
		
		CREATE INDEX IX_Stats ON #tblStatsSamp([databaseID]);

		IF (SELECT COUNT(*) FROM #tblStatsSamp) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_sampling_lt_25pct' AS [Check], '[WARNING: Some statistics have sampling rates less than 25 pct, consider updating with a larger sample or fullscan if key is not uniformly distributed]' AS [Deviation]
			SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_sampling_lt_25pct' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [tableName] AS [Table_Name], [stats_id] AS [statsID], [stat_name] AS [Statistic_Name], 
				last_updated, [rows], rows_sampled, CAST((rows_sampled/([rows]*1.00))*100.0 AS DECIMAL(5,2)) AS [Sample_Pct],
				CASE WHEN su.auto_created = 0 AND su.user_created = 0 THEN 'Index_Statistic'
					WHEN su.auto_created = 0 AND su.user_created = 1 THEN 'User_Created'
					WHEN su.auto_created = 1 AND su.user_created = 0 THEN 'Auto_Created'
					ELSE NULL
				END AS [Statistic_Type],
				su.steps, su.has_filter AS [Is_Filtered], su.filter_definition AS [Filter_Definition]
			FROM #tblStatsSamp AS su
			ORDER BY [DatabaseName], [tableName], [stats_id] DESC
		END
		ELSE
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'Statistics_sampling_lt_25pct' AS [Check], '[OK]' AS [Deviation]
		END;
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Hypothetical objects subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Hypothetical objects', 10, 1) WITH NOWAIT

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHypObj'))
	DROP TABLE #tblHypObj;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHypObj'))
	CREATE TABLE #tblHypObj ([DBName] sysname, [Schema] VARCHAR(100), [Table] VARCHAR(255), [Object] VARCHAR(255), [Type] VARCHAR(10));

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] = 2;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;
	
	IF (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
	BEGIN	
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0
			SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], QUOTENAME(t.name), QUOTENAME(o.[name]), i.name, ''INDEX'' 
FROM sys.indexes i 
INNER JOIN sys.objects o ON o.[object_id] = i.[object_id] 
INNER JOIN sys.tables AS mst ON mst.[object_id] = i.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE i.is_hypothetical = 1
UNION ALL
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], QUOTENAME(t.name), QUOTENAME(o.[name]), s.name, ''STATISTICS'' 
FROM sys.stats s 
INNER JOIN sys.objects o (NOLOCK) ON o.[object_id] = s.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = s.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE (s.name LIKE ''hind_%'' OR s.name LIKE ''_dta_stat%'') AND auto_created = 0
AND s.name NOT IN (SELECT name FROM ' + QUOTENAME(@dbname) + '.sys.indexes)'

			BEGIN TRY
				INSERT INTO #tblHypObj
				EXECUTE sp_executesql @sqlcmd
			END TRY
			BEGIN CATCH
				SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				SELECT @ErrorMessage = 'Hypothetical objects subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
				RAISERROR (@ErrorMessage, 16, 1);
			END CATCH
			
			UPDATE #tmpdbs0
			SET isdone = 1
			WHERE [dbid] = @dbid
		END
	END;
	
	UPDATE #tmpdbs0
	SET isdone = 0;

	IF (SELECT COUNT([Object]) FROM #tblHypObj) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Hypothetical_objects' AS [Check], '[WARNING: Some databases have indexes or statistics that are marked as hypothetical. Hypothetical indexes are created by the Database Tuning Assistant (DTA) during its tests. If a DTA session was interrupted, these indexes may not be deleted. It is recommended to drop these objects as soon as possible]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Hypothetical_objects' AS [Information], DBName AS [Database_Name], [Table] AS [Table_Name], [Object] AS [Object_Name], [Type] AS [Object_Type]
		FROM #tblHypObj
		ORDER BY 2, 3, 5

		IF @gen_scripts = 1
		BEGIN
			DECLARE @strSQL NVARCHAR(4000)
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			PRINT CHAR(10) + '--############# Existing Hypothetical objects drop statements #############' + CHAR(10)
			DECLARE ITW_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DBName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM ' + CASE WHEN [Type] = 'STATISTICS' THEN 'sys.stats' ELSE 'sys.indexes' END + ' WHERE name = N'''+ [Object] + ''')' + CHAR(10) +
			CASE WHEN [Type] = 'STATISTICS' THEN 'DROP STATISTICS ' + [Schema] + '.' + [Table] + '.' + QUOTENAME([Object]) + ';' + CHAR(10) + 'GO' + CHAR(10)
				ELSE 'DROP INDEX ' + QUOTENAME([Object]) + ' ON ' + [Schema] + '.' + [Table] + ';' + CHAR(10) + 'GO' + CHAR(10) 
				END
			FROM #tblHypObj
			ORDER BY DBName, [Table]
			
			OPEN ITW_Stats
			FETCH NEXT FROM ITW_Stats INTO @strSQL
			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				PRINT @strSQL
				FETCH NEXT FROM ITW_Stats INTO @strSQL
			END
			CLOSE ITW_Stats
			DEALLOCATE ITW_Stats
			PRINT CHAR(10) + '--############# Ended Hypothetical objects drop statements #############' + CHAR(10)
		END;
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Hypothetical_objects' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Index Health Analysis subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ixfrag = 1 AND @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Index Health Analysis check', 10, 1) WITH NOWAIT
	DECLARE /*@dbid int, */@objectid int, @indexid int, @partition_nr int, @type_desc NVARCHAR(60)
	DECLARE @ColumnStoreGetIXSQL NVARCHAR(2000), @ColumnStoreGetIXSQL_Param NVARCHAR(1000), @HasInMem bit
	DECLARE /*@sqlcmd NVARCHAR(4000), @params NVARCHAR(500),*/ @schema_name VARCHAR(100), @table_name VARCHAR(300), @KeyCols VARCHAR(4000), @distinctCnt bigint, @OptimBucketCnt bigint
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
	DROP TABLE #tmpIPS;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
	CREATE TABLE #tmpIPS ([database_id] int, [object_id] int, [index_id] int, [partition_number] int, fragmentation DECIMAL(18,3), [page_count] bigint, [size_MB] DECIMAL(26,3), record_count bigint, forwarded_record_count int NULL,
		CONSTRAINT PK_IPS PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS_CI'))
	DROP TABLE #tmpIPS_CI;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS_CI'))
	CREATE TABLE #tmpIPS_CI ([database_id] int, [object_id] int, [index_id] int, [partition_number] int, fragmentation DECIMAL(18,3), [page_count] bigint, [size_MB] DECIMAL(26,3), record_count bigint, delta_store_hobt_id bigint, row_group_id int , [state] tinyint, state_description VARCHAR(60),
		CONSTRAINT PK_IPS_CI PRIMARY KEY CLUSTERED(database_id, [object_id], [index_id], [partition_number], row_group_id));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
	DROP TABLE #tmpXIS;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
	CREATE TABLE #tmpXIS ([database_id] int, [object_id] int, [xtp_object_id] int, [schema_name] VARCHAR(100) COLLATE database_default, [table_name] VARCHAR(300) COLLATE database_default, [index_id] int, [index_name] VARCHAR(300) COLLATE database_default, type_desc NVARCHAR(60), total_bucket_count bigint, empty_bucket_count bigint, avg_chain_length bigint, max_chain_length bigint, KeyCols VARCHAR(4000) COLLATE database_default, DistinctCnt bigint NULL, OptimBucketCnt bigint NULL, isdone bit, 
		CONSTRAINT PK_tmpXIS PRIMARY KEY CLUSTERED(database_id, [object_id], [xtp_object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
	DROP TABLE #tmpXNCIS;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
	CREATE TABLE #tmpXNCIS ([database_id] int, [object_id] int, [xtp_object_id] int, [schema_name] VARCHAR(100) COLLATE database_default, [table_name] VARCHAR(300) COLLATE database_default, [index_id] int, [index_name] VARCHAR(300) COLLATE database_default, type_desc NVARCHAR(60), delta_pages bigint, internal_pages bigint, leaf_pages bigint, page_update_count bigint, page_update_retry_count bigint, page_consolidation_count bigint, page_consolidation_retry_count bigint, page_split_count bigint, page_split_retry_count bigint, key_split_count bigint, key_split_retry_count bigint, page_merge_count bigint, page_merge_retry_count bigint, key_merge_count bigint, key_merge_retry_count bigint, scans_started bigint, scans_retries bigint, 
		CONSTRAINT PK_tmpXNCIS PRIMARY KEY CLUSTERED(database_id, [object_id], [xtp_object_id], [index_id]));

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
	DROP TABLE #tblWorking;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
	CREATE TABLE #tblWorking (database_id int, [database_name] NVARCHAR(255), [object_id] int, [object_name] NVARCHAR(255), index_id int, index_name NVARCHAR(255), [schema_name] NVARCHAR(255), partition_number int, [type] tinyint, type_desc NVARCHAR(60), is_done bit)
	-- type 0 = Heap; 1 = Clustered; 2 = Nonclustered; 3 = XML; 4 = Spatial; 5 = Clustered columnstore; 6 = Nonclustered columnstore; 7 = Nonclustered hash

	RAISERROR (N'    |-Populating support table...', 10, 1) WITH NOWAIT

	UPDATE #tmpdbs0
	SET isdone = 0;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [state] <> 0 OR [dbid] < 5;

	UPDATE #tmpdbs0
	SET isdone = 1
	WHERE [role] = 2 AND secondary_role_allow_connections = 0;

	IF EXISTS (SELECT TOP 1 id FROM #tmpdbs0 WHERE isdone = 0)
	BEGIN
		WHILE (SELECT COUNT(id) FROM #tmpdbs0 WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs0 WHERE isdone = 0

			IF (SELECT CHARINDEX(CHAR(39), @dbname)) > 0
				OR (SELECT CHARINDEX(CHAR(45), @dbname)) > 0
				OR (SELECT CHARINDEX(CHAR(47), @dbname)) > 0
			BEGIN
				SELECT @ErrorMessage = '    |-Skipping Database ID ' + CONVERT(VARCHAR, DB_ID(QUOTENAME(@dbname))) + ' due to potential of SQL Injection'
				RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT;
			END
			ELSE
			BEGIN
				SELECT @sqlcmd = 'SELECT ' + CONVERT(VARCHAR(10), @dbid) + ', ''' + DB_NAME(@dbid) + ''', si.[object_id], mst.[name], si.index_id, si.name, t.name, sp.partition_number, si.[type], si.type_desc, 0
FROM [' + @dbname + '].sys.indexes si
INNER JOIN [' + @dbname + '].sys.partitions sp ON si.[object_id] = sp.[object_id] AND si.index_id = sp.index_id
INNER JOIN [' + @dbname + '].sys.tables AS mst ON mst.[object_id] = si.[object_id]
INNER JOIN [' + @dbname + '].sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE mst.is_ms_shipped = 0 AND ' + CASE WHEN @sqlmajorver <= 11 THEN ' si.[type] <= 2;' ELSE ' si.[type] IN (0,1,2,5,6,7);' END

				INSERT INTO #tblWorking
				EXEC sp_executesql @sqlcmd;

				IF @sqlmajorver >= 12
				BEGIN
					SELECT @sqlcmd = 'SELECT @HasInMemOUT = ISNULL((SELECT TOP 1 1 FROM [' + @dbname + '].sys.filegroups FG where FG.[type] = ''FX''), 0)'
					SET @params = N'@HasInMemOUT bit OUTPUT';
					EXECUTE sp_executesql @sqlcmd, @params, @HasInMemOUT=@HasInMem OUTPUT

					IF @HasInMem = 1
					BEGIN
						INSERT INTO #tmpIPS_CI ([database_id], [object_id], [index_id], [partition_number], fragmentation, [page_count], [size_MB], record_count, delta_store_hobt_id, row_group_id, [state], state_description)		
						EXECUTE sp_executesql @ColumnStoreGetIXSQL, @ColumnStoreGetIXSQL_Param, @dbid_In = @dbid, @objectid_In = @objectid, @indexid_In = @indexid, @partition_nr_In = @partition_nr;

						SELECT @ErrorMessage = '    |-Gathering sys.dm_db_xtp_hash_index_stats and sys.dm_db_xtp_nonclustered_index_stats data in ' + @dbname + '...'
						RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT;

						SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id], xis.[object_id], xhis.xtp_object_id, t.name, o.name, xis.index_id, si.name, si.type_desc, xhis.total_bucket_count, xhis.empty_bucket_count, xhis.avg_chain_length, xhis.max_chain_length,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE si.[object_id] = i.[object_id] AND si.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS KeyCols, NULL, NULL, 0
FROM sys.dm_db_xtp_hash_index_stats AS xhis
INNER JOIN sys.dm_db_xtp_index_stats AS xis ON xis.[object_id] = xhis.[object_id] AND xis.[index_id] = xhis.[index_id] 
INNER JOIN sys.indexes AS si (NOLOCK) ON xis.[object_id] = si.[object_id] AND xis.[index_id] = si.[index_id]
INNER JOIN sys.objects AS o (NOLOCK) ON si.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U'''

						BEGIN TRY
							INSERT INTO #tmpXIS
							EXECUTE sp_executesql @sqlcmd
						END TRY
						BEGIN CATCH						
							SET @ErrorMessage = '      |-Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while analyzing hash indexes. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
							RAISERROR(@ErrorMessage, 0, 42) WITH NOWAIT;
						END CATCH

						SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE [' + @dbname + '];
SELECT DISTINCT ' + CONVERT(NVARCHAR(20), @dbid) + ' AS [database_id],
	xis.[object_id], xnis.xtp_object_id, t.name, o.name, xis.index_id, si.name, si.type_desc,
	xnis.delta_pages, xnis.internal_pages, xnis.leaf_pages, xnis.page_update_count,
	xnis.page_update_retry_count, xnis.page_consolidation_count,
	xnis.page_consolidation_retry_count, xnis.page_split_count, xnis.page_split_retry_count,
	xnis.key_split_count, xnis.key_split_retry_count, xnis.page_merge_count, xnis.page_merge_retry_count,
	xnis.key_merge_count, xnis.key_merge_retry_count,
	xis.scans_started, xis.scans_retries
FROM sys.dm_db_xtp_nonclustered_index_stats AS xnis (NOLOCK)
INNER JOIN sys.dm_db_xtp_index_stats AS xis (NOLOCK) ON xis.[object_id] = xnis.[object_id] AND xis.[index_id] = xnis.[index_id]
INNER JOIN sys.indexes AS si (NOLOCK) ON xis.[object_id] = si.[object_id] AND xis.[index_id] = si.[index_id]
INNER JOIN sys.objects AS o (NOLOCK) ON si.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE o.[type] = ''U'''

						BEGIN TRY
							INSERT INTO #tmpXNCIS
							EXECUTE sp_executesql @sqlcmd
						END TRY
						BEGIN CATCH						
							SET @ErrorMessage = '      |-Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while analyzing nonclustered hash indexes. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
							RAISERROR(@ErrorMessage, 0, 42) WITH NOWAIT;
						END CATCH
					END;
					/*ELSE
					BEGIN
						SELECT @ErrorMessage = '    |-Skipping ' + DB_NAME(@dbid) + '. No memory optimized filegroup was found...'
						RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT;
					END;*/
			END;
		END;
			
		UPDATE #tmpdbs0
		SET isdone = 1
		WHERE [dbid] = @dbid;
		END;
	END;

	IF EXISTS (SELECT TOP 1 database_id FROM #tmpXIS WHERE isdone = 0)
	BEGIN
		RAISERROR ('    |-Gathering additional data on xtp hash indexes...', 10, 1) WITH NOWAIT;
		WHILE (SELECT COUNT(database_id) FROM #tmpXIS WHERE isdone = 0) > 0
		BEGIN
			SELECT TOP 1 @dbid = database_id, @objectid = [object_id], @indexid = [index_id], @schema_name = [schema_name], @table_name = [table_name], @KeyCols = KeyCols FROM #tmpXIS WHERE isdone = 0
						
			SELECT @sqlcmd = 'USE ' + QUOTENAME(DB_NAME(@dbid)) + '; SELECT @distinctCntOUT = COUNT(*), @OptimBucketCntOUT = POWER(2,CEILING(LOG(CASE WHEN COUNT(*) = 0 THEN 1 ELSE COUNT(*) END)/LOG(2))) FROM (SELECT DISTINCT ' + @KeyCols + ' FROM ' + @schema_name + '.' + @table_name + ') t1;'

			SET @params = N'@distinctCntOUT bigint OUTPUT, @OptimBucketCntOUT bigint OUTPUT';
			EXECUTE sp_executesql @sqlcmd, @params, @distinctCntOUT=@distinctCnt OUTPUT, @OptimBucketCntOUT=@OptimBucketCnt OUTPUT;
			
			UPDATE #tmpXIS
			SET DistinctCnt = @distinctCnt, OptimBucketCnt = @OptimBucketCnt, isdone = 1
			WHERE database_id = @dbid AND [object_id] = @objectid AND [index_id] = @indexid;
		END;
	END;

	IF (SELECT COUNT(*) FROM #tblWorking WHERE is_done = 0 AND [type] <= 2) > 0
	BEGIN
		RAISERROR ('    |-Gathering sys.dm_db_index_physical_stats data...', 10, 1) WITH NOWAIT;

		WHILE (SELECT COUNT(*) FROM #tblWorking WHERE is_done = 0 AND [type] <= 2) > 0
		BEGIN
			SELECT TOP 1 @dbid = database_id, @objectid = [object_id], @indexid = index_id, @partition_nr = partition_number
			FROM #tblWorking WHERE is_done = 0 AND [type] <= 2
			
			INSERT INTO #tmpIPS
			SELECT ps.database_id, ps.[object_id], ps.index_id, ps.partition_number, SUM(ps.avg_fragmentation_in_percent), SUM(ps.page_count), 
				CAST((SUM(ps.page_count)*8)/1024 AS DECIMAL(26,3)) AS [size_MB], ps.record_count, ps.forwarded_record_count -- for heaps
			FROM sys.dm_db_index_physical_stats(@dbid, @objectid, @indexid , @partition_nr, @ixfragscanmode) AS ps
			WHERE /*ps.index_id > 0 -- ignore heaps
				AND */ps.index_level = 0 -- leaf-level nodes only
				AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'
			GROUP BY ps.database_id, ps.[object_id], ps.index_id, ps.partition_number, ps.record_count, ps.forwarded_record_count
			OPTION (MAXDOP 2);
			
			UPDATE #tblWorking
			SET is_done = 1
			WHERE database_id = @dbid AND [object_id] = @objectid AND index_id = @indexid AND partition_number = @partition_nr
		END
	END;

	IF (SELECT COUNT(*) FROM #tblWorking WHERE is_done = 0 AND type = 5) > 0
	BEGIN
		RAISERROR ('    |-Gathering sys.column_store_row_groups data...', 10, 1) WITH NOWAIT;

		WHILE (SELECT COUNT(*) FROM #tblWorking WHERE is_done = 0 AND type IN (5,6)) > 0
		BEGIN
			SELECT TOP 1 @dbid = database_id, @objectid = [object_id], @indexid = index_id, @partition_nr = partition_number
			FROM #tblWorking WHERE is_done = 0 AND type IN (5,6)
			
			BEGIN TRY
				SELECT @ColumnStoreGetIXSQL = 'SELECT @dbid_In, rg.object_id, rg.index_id, rg.partition_number, SUM((ISNULL(rg.deleted_rows,1)*100)/CASE WHEN rg.total_rows = 0 THEN 1 ELSE rg.total_rows END) AS [fragmentation], SUM(ISNULL(rg.size_in_bytes,1)/1024/8) AS [simulated_page_count], CAST(SUM(rg.size_in_bytes)/1024/1024 AS DECIMAL(26,3)) AS [size_MB], rg.total_rows, rg.delta_store_hobt_id, rg.row_group_id, rg.state, rg.state_description
FROM [' + DB_NAME(@dbid) + '].sys.column_store_row_groups rg 
WHERE rg.object_id = @objectid_In
	AND rg.index_id = @indexid_In
	AND rg.partition_number = @partition_nr_In
	--AND rg.state = 3 -- Only COMPRESSED row groups
GROUP BY rg.object_id, rg.index_id, rg.partition_number, rg.total_rows, rg.delta_store_hobt_id, rg.row_group_id, rg.state, rg.state_description
OPTION (MAXDOP 2)'
				SET @ColumnStoreGetIXSQL_Param = N'@dbid_In int, @objectid_In int, @indexid_In int, @partition_nr_In int';

				INSERT INTO #tmpIPS_CI ([database_id], [object_id], [index_id], [partition_number], fragmentation, [page_count], [size_MB], record_count, delta_store_hobt_id, row_group_id, [state], state_description)		
				EXECUTE sp_executesql @ColumnStoreGetIXSQL, @ColumnStoreGetIXSQL_Param, @dbid_In = @dbid, @objectid_In = @objectid, @indexid_In = @indexid, @partition_nr_In = @partition_nr;
			END TRY
			BEGIN CATCH						
				SET @ErrorMessage = '      |-Error ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ' has occurred while analyzing columnstore indexes. Message: ' + ERROR_MESSAGE() + ' (Line Number: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')'
				RAISERROR(@ErrorMessage, 0, 42) WITH NOWAIT;
			END CATCH
			
			UPDATE #tblWorking
			SET is_done = 1
			WHERE database_id = @dbid AND [object_id] = @objectid AND index_id = @indexid AND partition_number = @partition_nr
		END
	END;

	-- Check for index fragmentation over 5 pct when index has more than 1 extent allocated, or in CCI, all compressed row groups
	IF (SELECT COUNT(*) FROM #tmpIPS WHERE fragmentation > 5 AND [page_count] > 8) > 0
		OR (SELECT COUNT(*) FROM #tmpIPS_CI WHERE fragmentation > 5 AND [state] = 3) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Fragmentation' AS [Check], '[WARNING: Some databases have fragmented indexes. It is recommended to remove fragmentation on a regular basis to maintain performance]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Fragmentation' AS [Check], wk.database_name, wk.[schema_name], wk.[object_name], wk.index_name, wk.type_desc AS index_type, ips.partition_number, ips.fragmentation, 
			ips.page_count, ips.[size_MB], ips.record_count, ips.forwarded_record_count, -- for heaps
			NULL AS row_group_id, NULL AS [Comment]
		FROM #tmpIPS ips
		INNER JOIN #tblWorking wk ON ips.database_id = wk.database_id AND ips.[object_id] = wk.[object_id] AND ips.index_id = wk.index_id AND ips.partition_number = wk.partition_number
		WHERE ips.fragmentation > 5 AND ips.[page_count] > 8
		UNION ALL
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Fragmentation' AS [Check], wk.database_name, wk.[schema_name], wk.[object_name], wk.index_name, wk.type_desc AS index_type, ipsci.partition_number, ipsci.fragmentation, 
			ipsci.page_count, ipsci.[size_MB], ipsci.record_count, NULL AS forwarded_record_count, ipsci.row_group_id,
			'Fragmentation for CCI is the ratio of deleted_rows to total_rows; Page count is a simulated value coming from the size in bytes taken by the index]' AS [Comment]
		FROM #tmpIPS_CI ipsci
		INNER JOIN #tblWorking wk ON ipsci.database_id = wk.database_id AND ipsci.[object_id] = wk.[object_id] AND ipsci.index_id = wk.index_id AND ipsci.partition_number = wk.partition_number
		WHERE ipsci.fragmentation > 5 AND ipsci.[state] = 3
		ORDER BY fragmentation DESC, [page_count] ASC
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Fragmentation' AS [Check], '[OK]' AS [Deviation]
	END;

	IF @sqlmajorver >= 12
	BEGIN
		-- For the below values, your mileage may vary. Assuming more than 50 percent empty buckets and an average chain length over 5 requires investigation
		-- http://blogs.technet.com/b/dataplatforminsider/archive/2014/01/30/in-memory-oltp-index-troubleshooting-part-ii.aspx
		IF (SELECT COUNT(*) FROM #tmpXIS WHERE FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) > 50 AND [avg_chain_length] > 5) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_AvgChain_EmptyBuckets' AS [Check], '[WARNING: Some databases have high avg chain lenght (>5) and high empty buckets count (>50 pct). Verify if there are many rows with duplicate index key values or there is a skew in the key values]' AS [Deviation]
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_AvgChain_EmptyBuckets' AS [Check], DB_NAME([database_id]) AS [database_name], [schema_name], [table_name], [index_name], [type_desc] AS index_type,
				DistinctCnt AS [distinct_keys], OptimBucketCnt AS [optimal_bucket_count], total_bucket_count, empty_bucket_count, 
				FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) AS [empty_bucket_pct], avg_chain_length, max_chain_length
			FROM #tmpXIS
			WHERE FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) > 50 AND [avg_chain_length] > 5
			ORDER BY [database_name], [schema_name], table_name, [total_bucket_count] DESC;
		END
		ELSE
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_AvgChain_EmptyBuckets' AS [Check], '[OK]' AS [Deviation]
		END;
		
		IF (SELECT COUNT(*) FROM #tmpXIS WHERE total_bucket_count > DistinctCnt) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooManyBuckets' AS [Check], '[WARNING: Some databases have a total bucket count larger than the number of distinct rows in the table, which is wasting memory and marginally slowing down full table scans]' AS [Deviation]
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooManyBuckets' AS [Check], DB_NAME([database_id]) AS [database_name], [schema_name], [table_name], [index_name], [type_desc] AS index_type,
				DistinctCnt AS [distinct_keys], OptimBucketCnt AS [optimal_bucket_count], total_bucket_count, empty_bucket_count, 
				FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) AS [empty_bucket_pct], avg_chain_length, max_chain_length
			FROM #tmpXIS
			WHERE total_bucket_count > DistinctCnt
			ORDER BY [database_name], [schema_name], table_name, [total_bucket_count] DESC;
		END
		ELSE
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooManyBuckets' AS [Check], '[OK]' AS [Deviation]
		END;

		IF (SELECT COUNT(*) FROM #tmpXIS WHERE total_bucket_count < DistinctCnt) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooFewBuckets' AS [Check], '[WARNING: Some databases have a total bucket count smaller than the number of distinct rows in the table, which leads to chaining records]' AS [Deviation]
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooFewBuckets' AS [Check], DB_NAME([database_id]) AS [database_name], [schema_name], [table_name], [index_name], [type_desc] AS index_type,
				DistinctCnt AS [distinct_keys], OptimBucketCnt AS [optimal_bucket_count], total_bucket_count, empty_bucket_count, 
				FLOOR((CAST(empty_bucket_count AS FLOAT)/total_bucket_count) * 100) AS [empty_bucket_pct], avg_chain_length, max_chain_length
			FROM #tmpXIS
			WHERE total_bucket_count < DistinctCnt
			ORDER BY [database_name], [schema_name], table_name, [total_bucket_count] DESC;
		END
		ELSE
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_HashIX_Health_TooFewBuckets' AS [Check], '[OK]' AS [Deviation]
		END;

		-- For the below values, your mileage may vary. Assuming more than 5 percent retries requires investigation	.
		-- https://docs.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-xtp-nonclustered-index-stats-transact-sql	
		IF (SELECT COUNT(*) FROM #tmpXNCIS WHERE FLOOR((CAST(page_update_retry_count AS FLOAT)/CASE WHEN page_update_count = 0 THEN 1 ELSE page_update_count END) * 100) > 5
			OR FLOOR((CAST(page_consolidation_retry_count AS FLOAT)/CASE WHEN page_consolidation_count = 0 THEN 1 ELSE page_consolidation_count END) * 100) > 5
			OR FLOOR((CAST(page_split_retry_count AS FLOAT)/CASE WHEN page_split_count = 0 THEN 1 ELSE page_split_count END) * 100) > 5
			OR FLOOR((CAST(key_split_retry_count AS FLOAT)/CASE WHEN key_split_count = 0 THEN 1 ELSE key_split_count END) * 100) > 5
			OR FLOOR((CAST(page_merge_retry_count AS FLOAT)/CASE WHEN page_merge_count = 0 THEN 1 ELSE page_merge_count END) * 100) > 5
			OR FLOOR((CAST(key_merge_retry_count AS FLOAT)/CASE WHEN key_merge_count = 0 THEN 1 ELSE key_merge_count END) * 100) > 5
			) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_RangeIX_Health' AS [Check], '[WARNING: Some databases have retry count over 5 percent of total, indicating possible concurrency issues]' AS [Deviation]
			SELECT 'Index_and_Stats_checks' AS [Category], 'XTP_RangeIX_Health' AS [Category], DB_NAME([database_id]) AS [database_name], [schema_name], [table_name], [index_name], [type_desc] AS index_type,
				delta_pages, internal_pages, leaf_pages, 
				page_update_count, page_update_retry_count, FLOOR((CAST(page_update_retry_count AS FLOAT)/CASE WHEN page_update_count = 0 THEN 1 ELSE page_update_count END) * 100) AS [page_update_retry_pct_of_total],
				page_consolidation_count, page_consolidation_retry_count, FLOOR((CAST(page_consolidation_retry_count AS FLOAT)/CASE WHEN page_consolidation_count = 0 THEN 1 ELSE page_consolidation_count END) * 100) AS [page_consolidation_retry_pct_of_total],
				page_split_count, page_split_retry_count, FLOOR((CAST(page_split_retry_count AS FLOAT)/CASE WHEN page_split_count = 0 THEN 1 ELSE page_split_count END) * 100) AS [page_split_retry_pct_of_total],
				key_split_count, key_split_retry_count, FLOOR((CAST(key_split_retry_count AS FLOAT)/CASE WHEN key_split_count = 0 THEN 1 ELSE key_split_count END) * 100) AS [key_split_retry_pct_of_total],
				page_merge_count, page_merge_retry_count, FLOOR((CAST(page_merge_retry_count AS FLOAT)/CASE WHEN page_merge_count = 0 THEN 1 ELSE page_merge_count END) * 100) AS [page_merge_retry_pct_of_total],
				key_merge_count, key_merge_retry_count, FLOOR((CAST(key_merge_retry_count AS FLOAT)/CASE WHEN key_merge_count = 0 THEN 1 ELSE key_merge_count END) * 100) AS [key_merge_retry_pct_of_total]
			FROM #tmpXNCIS
			WHERE FLOOR((CAST(page_update_retry_count AS FLOAT)/CASE WHEN page_update_count = 0 THEN 1 ELSE page_update_count END) * 100) > 5
				OR FLOOR((CAST(page_consolidation_retry_count AS FLOAT)/CASE WHEN page_consolidation_count = 0 THEN 1 ELSE page_consolidation_count END) * 100) > 5
				OR FLOOR((CAST(page_split_retry_count AS FLOAT)/CASE WHEN page_split_count = 0 THEN 1 ELSE page_split_count END) * 100) > 5
				OR FLOOR((CAST(key_split_retry_count AS FLOAT)/CASE WHEN key_split_count = 0 THEN 1 ELSE key_split_count END) * 100) > 5
				OR FLOOR((CAST(page_merge_retry_count AS FLOAT)/CASE WHEN page_merge_count = 0 THEN 1 ELSE page_merge_count END) * 100) > 5
				OR FLOOR((CAST(key_merge_retry_count AS FLOAT)/CASE WHEN key_merge_count = 0 THEN 1 ELSE key_merge_count END) * 100) > 5
			ORDER BY [database_name], [schema_name], table_name, [leaf_pages] DESC;
		END;
	END;
END
ELSE
BEGIN
	RAISERROR('  |- [INFORMATION: "Index Health Analysis" check is disabled]', 10, 1, N'disallow_ixfrag')
	--RETURN
END;
	
--------------------------------------------------------------------------------------------------------------------------------
-- Duplicate or Redundant indexes subsection (clustered, non-clustered, clustered and non-clustered columnstore indexes only)
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Duplicate or Redundant indexes', 10, 1) WITH NOWAIT
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs1'))
	DROP TABLE #tblIxs1;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs1'))
	CREATE TABLE #tblIxs1 ([databaseID] int, [DatabaseName] sysname, [objectID] int, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), 
		[indexID] int, [indexName] NVARCHAR(200), [indexType] tinyint, is_primary_key bit, [is_unique_constraint] bit, is_unique bit, is_disabled bit, fill_factor tinyint, is_padded bit, has_filter bit, filter_definition NVARCHAR(max),
		KeyCols VARCHAR(4000), KeyColsOrdered VARCHAR(4000), IncludedCols VARCHAR(4000) NULL, IncludedColsOrdered VARCHAR(4000) NULL, AllColsOrdered VARCHAR(4000) NULL, [KeyCols_data_length_bytes] int,
		CONSTRAINT PK_Ixs PRIMARY KEY CLUSTERED(databaseID, [objectID], [indexID]));
		
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
	DROP TABLE #tblCode;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
	CREATE TABLE #tblCode ([DatabaseName] sysname, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), [indexName] NVARCHAR(200), type_desc NVARCHAR(60));

	UPDATE #tmpdbs1
	SET isdone = 0;

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
		SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE ' + QUOTENAME(@dbname) + ';
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ' AS Database_ID, N''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS Database_Name,
	mst.[object_id] AS objectID, t.name AS schemaName, mst.[name] AS objectName, mi.index_id AS indexID, 
	mi.[name] AS Index_Name, mi.[type] AS [indexType], mi.is_primary_key, mi.[is_unique_constraint], mi.is_unique, mi.is_disabled,
	mi.fill_factor, mi.is_padded, ' + CASE WHEN @sqlmajorver > 9 THEN 'mi.has_filter, mi.filter_definition,' ELSE 'NULL, NULL,' END + ' 
	SUBSTRING(( SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS KeyCols,
	SUBSTRING(( SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS KeyColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS IncludedCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 1
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS IncludedColsOrdered,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id]
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS AllColsOrdered,
	(SELECT SUM(CASE sty.name WHEN ''nvarchar'' THEN sc.max_length/2 ELSE sc.max_length END) FROM sys.indexes AS i
		INNER JOIN sys.tables AS t ON t.[object_id] = i.[object_id]
		INNER JOIN sys.schemas ss ON ss.[schema_id] = t.[schema_id]
		INNER JOIN sys.index_columns AS sic ON sic.object_id = mst.object_id AND sic.index_id = mi.index_id
		INNER JOIN sys.columns AS sc ON sc.object_id = t.object_id AND sc.column_id = sic.column_id
		INNER JOIN sys.types AS sty ON sc.user_type_id = sty.user_type_id
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND sic.key_ordinal > 0) AS [KeyCols_data_length_bytes]
FROM sys.indexes AS mi
INNER JOIN sys.tables AS mst ON mst.[object_id] = mi.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE mi.type IN (1,2,5,6) AND mst.is_ms_shipped = 0
ORDER BY objectName
OPTION (MAXDOP 2);'

		BEGIN TRY
			INSERT INTO #tblIxs1
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Duplicate or Redundant indexes subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		
		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid;
	END

	IF (SELECT COUNT(*) FROM #tblIxs1 I INNER JOIN #tblIxs1 I2 ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
		AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
		AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes' AS [Check], '[WARNING: Some databases have duplicate indexes. It is recommended to revise the need to maintain all these objects as soon as possible]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], 
			I.[indexID], I.[indexName] AS [Index_Name], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition,
			I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedCols IS NULL THEN I.[KeyCols] ELSE I.[KeyCols] + ',' + I.IncludedCols END AS [AllColsOrdered]
		FROM #tblIxs1 I INNER JOIN #tblIxs1 I2
			ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
			AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
			AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
		WHERE I.indexType IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
			AND I2.indexType IN (1,2,5,6)	-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
		GROUP BY I.[databaseID], I.[DatabaseName], I.[schemaName], I.[objectName], I.[indexID], I.[indexName], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.is_primary_key, I.is_unique_constraint, I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition
		ORDER BY I.DatabaseName, I.[objectName], I.[indexID]
		
		SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes_toDrop' AS [Check], I.[DatabaseName], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name],
			I.[indexID], I.[indexName] AS [Index_Name], I.is_primary_key, I.is_unique_constraint, I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition,
			I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedCols IS NULL THEN I.[KeyCols] ELSE I.[KeyCols] + ',' + I.IncludedCols END AS [AllColsOrdered]
		FROM #tblIxs1 I INNER JOIN #tblIxs1 I2
			ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
			AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
			AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
		WHERE I.indexType IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
			AND I2.indexType IN (1,2,5,6)	-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
			AND I.[indexID] NOT IN (
				SELECT COALESCE((SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
				))
		GROUP BY I.[databaseID], I.[DatabaseName], I.[schemaName], I.[objectName], I.[indexID], I.[indexName], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.is_primary_key, I.is_unique_constraint, I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition
		ORDER BY I.DatabaseName, I.[objectName], I.[indexID];

		DECLARE @strSQL2 NVARCHAR(4000), @DatabaseName sysname, @indexName sysname

		IF @gen_scripts = 1
		BEGIN
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			PRINT CHAR(10) + '/*
NOTE: It is possible that a clustered index (unique or not) is among the duplicate indexes to be dropped, namely if a non-clustered primary key exists on the table.
In this case, make the appropriate changes in the clustered index (making it unique and/or primary key in this case), and drop the non-clustered instead.
*/'
			PRINT CHAR(10) + '--############# Existing Duplicate indexes drop statements #############' + CHAR(10)
			DECLARE Dup_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + I.[DatabaseName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ I.[indexName] + ''')' + CHAR(10) +
			'DROP INDEX ' + QUOTENAME(I.[indexName]) + ' ON ' + QUOTENAME(I.[schemaName]) + '.' + QUOTENAME(I.[objectName]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
			FROM #tblIxs1 I INNER JOIN #tblIxs1 I2
				ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
				AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
				AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
			WHERE I.indexType IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
				AND I2.indexType IN (1,2,5,6)	-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
				AND I.[indexID] NOT IN (
					SELECT COALESCE((SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
					WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
						AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
						AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
					GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
					(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
					WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
						AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
						AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
					GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
					(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
					WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
						AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
					))
			GROUP BY I.[databaseID], I.[DatabaseName], I.[schemaName], I.[objectName], I.[indexID], I.[indexName], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered
			ORDER BY I.DatabaseName, I.[objectName], I.[indexID];

			OPEN Dup_Stats
			FETCH NEXT FROM Dup_Stats INTO @strSQL2
			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				PRINT @strSQL2
				FETCH NEXT FROM Dup_Stats INTO @strSQL2
			END
			CLOSE Dup_Stats
			DEALLOCATE Dup_Stats
			PRINT '--############# Ended Duplicate indexes drop statements #############' + CHAR(10)
		END;
		
		RAISERROR (N'    |-Starting index search in sql modules...', 10, 1) WITH NOWAIT

		DECLARE Dup_HardCoded CURSOR FAST_FORWARD FOR SELECT I.[DatabaseName],I.[indexName] 
		FROM #tblIxs1 I INNER JOIN #tblIxs1 I2
			ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
			AND I.[KeyCols] = I2.[KeyCols] AND (I.IncludedCols = I2.IncludedCols OR (I.IncludedCols IS NULL AND I2.IncludedCols IS NULL))
			AND ((I.filter_definition = I2.filter_definition) OR (I.filter_definition IS NULL AND I2.filter_definition IS NULL))
		WHERE I.indexType IN (1,2,5,6)		-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
			AND I2.indexType IN (1,2,5,6)	-- clustered, non-clustered, clustered and non-clustered columnstore indexes only
			AND I.[indexID] NOT IN (
				SELECT COALESCE((SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 AND tI3.is_primary_key = 1)
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
					AND (tI3.is_unique = 1 OR tI3.is_primary_key = 1)
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered),
				(SELECT MIN(tI3.[indexID]) FROM #tblIxs1 tI3
				WHERE tI3.[databaseID] = I.[databaseID] AND tI3.[objectID] = I.[objectID] 
					AND tI3.[KeyCols] = I.[KeyCols] AND (tI3.IncludedCols = I.IncludedCols OR (tI3.IncludedCols IS NULL AND I.IncludedCols IS NULL))
				GROUP BY tI3.[objectID], tI3.KeyCols, tI3.IncludedCols, tI3.[KeyColsOrdered], tI3.IncludedColsOrdered)
				))
		GROUP BY I.[databaseID], I.[DatabaseName], I.[schemaName], I.[objectName], I.[indexID], I.[indexName], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered
		ORDER BY I.DatabaseName, I.[objectName], I.[indexID];

		OPEN Dup_HardCoded
		FETCH NEXT FROM Dup_HardCoded INTO @DatabaseName,@indexName
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
			SET @sqlcmd = N'USE [' + @DatabaseName + N'];
SELECT ''' + @DatabaseName + N''' AS [database], ss.name AS [schemaName], so.name AS [objectName], ''' + @indexName + N''' AS indexName, so.type_desc
FROM sys.sql_modules sm
INNER JOIN sys.objects so ON sm.[object_id] = so.[object_id]
INNER JOIN sys.schemas ss ON ss.[schema_id] = so.[schema_id]
WHERE sm.[definition] LIKE ''%' + @indexName + N'%'''

			INSERT INTO #tblCode
			EXECUTE sp_executesql @sqlcmd

			FETCH NEXT FROM Dup_HardCoded INTO @DatabaseName,@indexName
		END
		CLOSE Dup_HardCoded
		DEALLOCATE Dup_HardCoded

		RAISERROR (N'    |-Ended index search in sql modules', 10, 1) WITH NOWAIT

		IF (SELECT COUNT(*) FROM #tblCode) > 0
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes_HardCoded' AS [Check], '[WARNING: Some sql modules have references to these duplicate indexes. Fix these references to be able to drop duplicate indexes]' AS [Deviation]
			SELECT [DatabaseName],[schemaName],[objectName] AS [referedIn_objectName], indexName AS [referenced_indexName], type_desc AS [refered_objectType]
			FROM #tblCode
			ORDER BY [DatabaseName], [objectName]
		END
		ELSE
		BEGIN
			SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes_HardCoded' AS [Check], '[OK]' AS [Deviation]
		END
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Duplicate_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;

	IF (SELECT COUNT(*) FROM #tblIxs1 I INNER JOIN #tblIxs1 I2 ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
		AND (I.[KeyCols] <> I2.[KeyCols] OR I.IncludedCols <> I2.IncludedCols)
		AND (((I.[KeyColsOrdered] <> I2.[KeyColsOrdered] OR I.IncludedColsOrdered <> I2.IncludedColsOrdered)
				AND ((CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END) = (CASE WHEN I2.IncludedColsOrdered IS NULL THEN I2.[KeyColsOrdered] ELSE I2.[KeyColsOrdered] + ',' + I2.IncludedColsOrdered END)
					OR I.[AllColsOrdered] = I2.[AllColsOrdered]))
			OR (I.[KeyColsOrdered] <> I2.[KeyColsOrdered] AND I.IncludedColsOrdered = I2.IncludedColsOrdered)
			OR (I.[KeyColsOrdered] = I2.[KeyColsOrdered] AND I.IncludedColsOrdered <> I2.IncludedColsOrdered)
			OR ((I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NULL AND I2.filter_definition IS NOT NULL) OR (I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NOT NULL AND I2.filter_definition IS NULL)))
		AND I.indexID NOT IN (SELECT I3.[indexID]
			FROM #tblIxs1 I3 INNER JOIN #tblIxs1 I4
			ON I3.[databaseID] = I4.[databaseID] AND I3.[objectID] = I4.[objectID] AND I3.[indexID] <> I4.[indexID] 
				AND I3.[KeyCols] = I4.[KeyCols] AND (I3.IncludedCols = I4.IncludedCols OR (I3.IncludedCols IS NULL AND I4.IncludedCols IS NULL))
			WHERE I3.[databaseID] = I.[databaseID] AND I3.[objectID] = I.[objectID]
			GROUP BY I3.[indexID])
		WHERE I.indexType IN (1,2,5,6)		-- 1 = clustered, 2 = non-clustered, 5 = clustered and 7 = non-clustered columnstore indexes only
			AND I2.indexType IN (1,2,5,6)	-- 1 = clustered, 2 = non-clustered, 5 = clustered and 7 = non-clustered columnstore indexes only
			AND I.is_unique_constraint = 0	-- no unique constraints
			AND I2.is_unique_constraint = 0	-- no unique constraints
		) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Redundant_Indexes' AS [Check], '[WARNING: Some databases have possibly redundant indexes. It is recommended to revise the need to maintain all these objects as soon as possible]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Redundant_Indexes' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name],
			I.[indexID], I.[indexName] AS [Index_Name], I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition,
			I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END AS [KeyInclColsOrdered]
		FROM #tblIxs1 I INNER JOIN #tblIxs1 I2
		ON I.[databaseID] = I2.[databaseID] AND I.[objectID] = I2.[objectID] AND I.[indexID] <> I2.[indexID] 
			AND (((I.[KeyColsOrdered] <> I2.[KeyColsOrdered] OR I.IncludedColsOrdered <> I2.IncludedColsOrdered)
				AND ((CASE WHEN I.IncludedColsOrdered IS NULL THEN I.[KeyColsOrdered] ELSE I.[KeyColsOrdered] + ',' + I.IncludedColsOrdered END) = (CASE WHEN I2.IncludedColsOrdered IS NULL THEN I2.[KeyColsOrdered] ELSE I2.[KeyColsOrdered] + ',' + I2.IncludedColsOrdered END)
					OR I.[AllColsOrdered] = I2.[AllColsOrdered]))
			OR (I.[KeyColsOrdered] <> I2.[KeyColsOrdered] AND I.IncludedColsOrdered = I2.IncludedColsOrdered)
			OR (I.[KeyColsOrdered] = I2.[KeyColsOrdered] AND I.IncludedColsOrdered <> I2.IncludedColsOrdered)
			OR ((I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NULL AND I2.filter_definition IS NOT NULL) OR (I.[AllColsOrdered] = I2.[AllColsOrdered] AND I.filter_definition IS NOT NULL AND I2.filter_definition IS NULL)))
			AND I.indexID NOT IN (SELECT I3.[indexID]
				FROM #tblIxs1 I3 INNER JOIN #tblIxs1 I4
				ON I3.[databaseID] = I4.[databaseID] AND I3.[objectID] = I4.[objectID] AND I3.[indexID] <> I4.[indexID] 
					AND I3.[KeyCols] = I4.[KeyCols] AND (I3.IncludedCols = I4.IncludedCols OR (I3.IncludedCols IS NULL AND I4.IncludedCols IS NULL))
				WHERE I3.[databaseID] = I.[databaseID] AND I3.[objectID] = I.[objectID]
				GROUP BY I3.[indexID])
		WHERE I.indexType IN (1,2,5,6)		-- 1 = clustered, 2 = non-clustered, 5 = clustered and 7 = non-clustered columnstore indexes only
			AND I2.indexType IN (1,2,5,6)	-- 1 = clustered, 2 = non-clustered, 5 = clustered and 7 = non-clustered columnstore indexes only
			AND I.is_unique_constraint = 0	-- no unique constraints
			AND I2.is_unique_constraint = 0	-- no unique constraints
		GROUP BY I.[DatabaseName], I.[schemaName], I.[objectName], I.[indexID], I.[indexName], I.KeyCols, I.IncludedCols, I.[KeyColsOrdered], I.IncludedColsOrdered, I.is_unique, I.fill_factor, I.is_padded, I.has_filter, I.filter_definition
		ORDER BY I.DatabaseName, I.[objectName], I.[KeyColsOrdered], I.IncludedColsOrdered, I.[indexID]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Redundant_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Unused and rarely used indexes subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Unused and rarely used indexes', 10, 1) WITH NOWAIT
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs2'))
	DROP TABLE #tblIxs2;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs2'))
	CREATE TABLE #tblIxs2 ([databaseID] int, [DatabaseName] sysname, [objectID] int, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), 
		[indexID] int, [indexName] NVARCHAR(200), [Hits] bigint NULL, [Reads_Ratio] DECIMAL(5,2), [Writes_Ratio] DECIMAL(5,2),
		user_updates bigint, last_user_seek DATETIME NULL, last_user_scan DATETIME NULL, last_user_lookup DATETIME NULL, 
		last_user_update DATETIME NULL, is_unique bit, [type] tinyint, is_primary_key bit, is_unique_constraint bit, is_disabled bit,
		CONSTRAINT PK_Ixs2 PRIMARY KEY CLUSTERED(databaseID, [objectID], [indexID]))

	UPDATE #tmpdbs1
	SET isdone = 0;

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
		SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ' AS Database_ID, ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS Database_Name,
	mst.[object_id] AS objectID, t.name AS schemaName, mst.[name] AS objectName, si.index_id AS indexID, si.[name] AS Index_Name,
	(s.user_seeks + s.user_scans + s.user_lookups) AS [Hits],
	RTRIM(CONVERT(NVARCHAR(10),CAST(CASE WHEN (s.user_seeks + s.user_scans + s.user_lookups) = 0 THEN 0 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups)) * 100 /
		CASE (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates) WHEN 0 THEN 1 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates)) END END AS DECIMAL(18,2)))) AS [Reads_Ratio],
	RTRIM(CONVERT(NVARCHAR(10),CAST(CASE WHEN s.user_updates = 0 THEN 0 ELSE CONVERT(REAL, s.user_updates) * 100 /
		CASE (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates) WHEN 0 THEN 1 ELSE CONVERT(REAL, (s.user_seeks + s.user_scans + s.user_lookups + s.user_updates)) END END AS DECIMAL(18,2)))) AS [Writes_Ratio],
	s.user_updates,
	MAX(s.last_user_seek) AS last_user_seek,
	MAX(s.last_user_scan) AS last_user_scan,
	MAX(s.last_user_lookup) AS last_user_lookup,
	MAX(s.last_user_update) AS last_user_update,
	si.is_unique, si.[type], si.is_primary_key, si.is_unique_constraint, si.is_disabled	
FROM sys.indexes AS si (NOLOCK)
INNER JOIN sys.objects AS o (NOLOCK) ON si.[object_id] = o.[object_id]
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = si.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
INNER JOIN sys.dm_db_index_usage_stats AS s (NOLOCK) ON s.database_id = ' + CONVERT(VARCHAR(8), @dbid) + ' 
	AND s.object_id = si.object_id AND s.index_id = si.index_id
WHERE mst.is_ms_shipped = 0
	--AND OBJECTPROPERTY(o.object_id,''IsUserTable'') = 1 -- sys.tables only returns type U
	AND si.type IN (2,6) 			-- non-clustered and non-clustered columnstore indexes only
	AND si.is_primary_key = 0 		-- no primary keys
	AND si.is_unique_constraint = 0	-- no unique constraints
	--AND si.is_unique = 0 			-- no alternate keys
GROUP BY mst.[object_id], t.[name], mst.[name], si.index_id, si.[name], s.user_seeks, s.user_scans, s.user_lookups, s.user_updates, si.is_unique,
	si.[type], si.is_primary_key, si.is_unique_constraint, si.is_disabled
ORDER BY objectName	
OPTION (MAXDOP 2);'
		BEGIN TRY
			INSERT INTO #tblIxs2
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Unused and rarely used indexes subsection - Error raised in TRY block 1 in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		
		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END

	UPDATE #tmpdbs1
	SET isdone = 0;

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
		SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ' AS Database_ID, ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS Database_Name, 
	si.[object_id] AS objectID, t.name AS schemaName, OBJECT_NAME(si.[object_id], ' + CONVERT(VARCHAR(8), @dbid) + ') AS objectName, si.index_id AS indexID, 
	si.[name] AS Index_Name, 0, 0, 0, 0, NULL, NULL, NULL, NULL,
	si.is_unique, si.[type], si.is_primary_key, si.is_unique_constraint, si.is_disabled
FROM sys.indexes AS si (NOLOCK)
INNER JOIN sys.objects AS so (NOLOCK) ON si.object_id = so.object_id 
INNER JOIN sys.tables AS mst (NOLOCK) ON mst.[object_id] = si.[object_id]
INNER JOIN sys.schemas AS t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
WHERE OBJECTPROPERTY(so.object_id,''IsUserTable'') = 1
	AND mst.is_ms_shipped = 0
	AND si.index_id NOT IN (SELECT s.index_id
		FROM sys.dm_db_index_usage_stats s
		WHERE s.object_id = si.object_id 
			AND si.index_id = s.index_id 
			AND database_id = ' + CONVERT(VARCHAR(8), @dbid) + ')
	AND si.name IS NOT NULL
	AND si.type IN (2,6) 			-- non-clustered and non-clustered columnstore indexes only
	AND si.is_primary_key = 0 		-- no primary keys
	AND si.is_unique_constraint = 0	-- no unique constraints
	--AND si.is_unique = 0 			-- no alternate keys
'

		BEGIN TRY
			INSERT INTO #tblIxs2
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Unused and rarely used indexes subsection - Error raised in TRY block 2 in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END;

	IF (SELECT COUNT(*) FROM #tblIxs2 WHERE [Hits] = 0 /*AND is_disabled = 0*/) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Unused_Indexes' AS [Check], '[WARNING: Some databases have unused indexes. It is recommended to revise the need to maintain all these objects as soon as possible]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Unused_Indexes_With_Updates' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [indexID], [indexName] AS [Index_Name], is_unique, 
		[Hits], CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
		user_updates, last_user_update
		FROM #tblIxs2
		WHERE [Hits] = 0 AND last_user_update > 0
		UNION ALL
		SELECT 'Index_and_Stats_checks' AS [Category], 'Unused_Indexes_No_Updates' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [indexID], [indexName] AS [Index_Name], is_unique, 
		[Hits], CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
		user_updates, last_user_update
		FROM #tblIxs2
		WHERE [Hits] = 0 AND (last_user_update = 0 OR last_user_update IS NULL)
		ORDER BY [Information], [Database_Name], [Table_Name], [R/W_Ratio] DESC;

		IF @gen_scripts = 1
		BEGIN
			DECLARE @strSQL3 NVARCHAR(4000)
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			
			IF (SELECT COUNT(*) FROM #tblIxs2 WHERE [Hits] = 0 AND last_user_update > 0) > 0
			BEGIN
				PRINT CHAR(10) + '--############# Existing unused indexes with updates drop statements #############' + CHAR(10)
				DECLARE Un_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DatabaseName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [indexName] + ''')' + CHAR(10) +
				'DROP INDEX ' + QUOTENAME([indexName]) + ' ON ' + QUOTENAME([schemaName]) + '.' + QUOTENAME([objectName]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
				FROM #tblIxs2
				WHERE [Hits] = 0 AND last_user_update > 0
				ORDER BY [DatabaseName], [objectName], [Reads_Ratio] DESC;

				OPEN Un_Stats
				FETCH NEXT FROM Un_Stats INTO @strSQL3
				WHILE (@@FETCH_STATUS = 0)
				BEGIN
					PRINT @strSQL3
					FETCH NEXT FROM Un_Stats INTO @strSQL3
				END
				CLOSE Un_Stats
				DEALLOCATE Un_Stats
				PRINT CHAR(10) + '--############# Ended unused indexes with updates drop statements #############' + CHAR(10)
			END;

			IF (SELECT COUNT(*) FROM #tblIxs2 WHERE [Hits] = 0 AND (last_user_update = 0 OR last_user_update IS NULL)) > 0
			BEGIN
				PRINT CHAR(10) + '--############# Existing unused indexes with no updates drop statements #############' + CHAR(10)
				DECLARE Un_Stats CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DatabaseName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [indexName] + ''')' + CHAR(10) +
				'DROP INDEX ' + QUOTENAME([indexName]) + ' ON ' + QUOTENAME([schemaName]) + '.' + QUOTENAME([objectName]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
				FROM #tblIxs2
				WHERE [Hits] = 0 AND (last_user_update = 0 OR last_user_update IS NULL)
				ORDER BY [DatabaseName], [objectName], [Reads_Ratio] DESC;

				OPEN Un_Stats
				FETCH NEXT FROM Un_Stats INTO @strSQL3
				WHILE (@@FETCH_STATUS = 0)
				BEGIN
					PRINT @strSQL3
					FETCH NEXT FROM Un_Stats INTO @strSQL3
				END
				CLOSE Un_Stats
				DEALLOCATE Un_Stats
				PRINT CHAR(10) + '--############# Ended unused indexes with no updates drop statements #############' + CHAR(10)
			END
		END;
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Unused_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;

	IF (SELECT COUNT(*) FROM #tblIxs2 WHERE [Hits] > 0 AND [Reads_Ratio] < 5 AND type IN (1,2,5,6) AND is_primary_key = 0 AND is_unique_constraint = 0 /*AND is_disabled = 0*/) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Rarely_Used_Indexes' AS [Check], '[WARNING: Some databases have rarely used indexes. It is recommended to revise the need to maintain all these objects as soon as possible]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Rarely_Used_Indexes' AS [Information], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [indexID], [indexName] AS [Index_Name], is_unique, 
		[Hits], CONVERT(NVARCHAR,[Reads_Ratio]) COLLATE database_default + '/' + CONVERT(NVARCHAR,[Writes_Ratio]) COLLATE database_default AS [R/W_Ratio],
		user_updates, last_user_seek, last_user_scan, last_user_lookup, last_user_update
		FROM #tblIxs2
		WHERE [Hits] > 0 AND [Reads_Ratio] < 5
		ORDER BY [DatabaseName], [objectName], [Reads_Ratio] DESC

		IF @gen_scripts = 1
		BEGIN		
			DECLARE @strSQL4 NVARCHAR(4000)
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			PRINT CHAR(10) + '--############# Existing rarely used indexes drop statements #############' + CHAR(10)
			DECLARE curRarUsed CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DatabaseName] + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sys.indexes WHERE name = N'''+ [indexName] + ''')' + CHAR(10) +
			'DROP INDEX ' + QUOTENAME([indexName]) + ' ON ' + QUOTENAME([schemaName]) + '.' + QUOTENAME([objectName]) + ';' + CHAR(10) + 'GO' + CHAR(10) 
			FROM #tblIxs2
			WHERE [Hits] > 0 AND [Reads_Ratio] < 5
			ORDER BY [DatabaseName], [objectName], [Reads_Ratio] DESC

			OPEN curRarUsed
			FETCH NEXT FROM curRarUsed INTO @strSQL4
			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				PRINT @strSQL4
				FETCH NEXT FROM curRarUsed INTO @strSQL4
			END
			CLOSE curRarUsed
			DEALLOCATE curRarUsed
			PRINT '--############# Ended rarely used indexes drop statements #############' + CHAR(10)
		END;
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Rarely_Used_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Indexes with large keys (> 900 bytes for clustered index; 1700 bytes for nonclustered index) subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Indexes with large keys', 10, 1) WITH NOWAIT
	IF (SELECT COUNT(*) FROM #tblIxs1 WHERE ([KeyCols_data_length_bytes] > 900 AND @sqlmajorver < 13)
			OR ([KeyCols_data_length_bytes] > 900 AND indexType IN (1,5) AND @sqlmajorver >= 13)
			OR ([KeyCols_data_length_bytes] > 1700 AND indexType IN (2,6) AND @sqlmajorver >= 13)) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Large_Index_Key' AS [Check], 
			CASE WHEN @sqlmajorver < 13 THEN '[WARNING: Some indexes have keys larger than 900 bytes. It is recommended to revise these]' 
				ELSE '[WARNING: Some indexes have keys larger than allowed (900 bytes for clustered index; 1700 bytes for nonclustered index). It is recommended to revise these]' END AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Large_Index_Key' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], I.[indexID], I.[indexName] AS [Index_Name], I.indexType, I.KeyCols, [KeyCols_data_length_bytes]
		FROM #tblIxs1 I
		WHERE ([KeyCols_data_length_bytes] > 900 AND @sqlmajorver < 13)
			OR ([KeyCols_data_length_bytes] > 900 AND indexType IN (1,5) AND @sqlmajorver >= 13)
			OR ([KeyCols_data_length_bytes] > 1700 AND indexType IN (2,6) AND @sqlmajorver >= 13)
		ORDER BY I.[DatabaseName], I.schemaName, I.[objectName], I.[indexID]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Large_Index_Key' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Indexes with fill factor < 80 pct subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Indexes with fill factor < 80 pct', 10, 1) WITH NOWAIT
	IF (SELECT COUNT(*) FROM #tblIxs1 WHERE [fill_factor] BETWEEN 1 AND 79) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Low_Fill_Factor' AS [Check], '[WARNING: Some indexes have a fill factor lower than 80 percent. Revise the need to maintain such a low value]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Low_Fill_Factor' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], I.[indexID], I.[indexName] AS [Index_Name], 
			[fill_factor], I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedCols IS NULL THEN I.[KeyCols] ELSE I.[KeyCols] + ',' + I.IncludedCols END AS [AllColsOrdered]
		FROM #tblIxs1 I
		WHERE [fill_factor] BETWEEN 1 AND 79
		ORDER BY I.[DatabaseName], I.schemaName, I.[objectName], I.[indexID]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Low_Fill_Factor' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Disabled indexes subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Disabled indexes', 10, 1) WITH NOWAIT
	IF (SELECT COUNT(*) FROM #tblIxs1 WHERE [is_disabled] = 1) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Disabled_IXs' AS [Check], '[WARNING: Some indexes are disabled. Revise the need to maintain these]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Disabled_IXs' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], I.[indexID], I.[indexName] AS [Index_Name], 
			CASE WHEN [indexType] = 1 THEN 'Clustered' 
			WHEN [indexType] = 2 THEN 'Non-clustered'
			WHEN [indexType] = 3 THEN 'Clustered columnstore'
			ELSE 'Non-clustered columnstore' END AS [Index_Type],
		I.KeyCols, I.IncludedCols, CASE WHEN I.IncludedCols IS NULL THEN I.[KeyCols] ELSE I.[KeyCols] + ',' + I.IncludedCols END AS [AllColsOrdered]
		FROM #tblIxs1 I
		WHERE [is_disabled] = 1
		ORDER BY I.[DatabaseName], I.schemaName, I.[objectName], I.[indexID]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Disabled_IXs' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Non-unique clustered indexes subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Non-unique clustered indexes', 10, 1) WITH NOWAIT
	IF (SELECT COUNT(*) FROM #tblIxs1 WHERE [is_unique] = 0 AND indexID = 1) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'NonUnique_CIXs' AS [Check], '[WARNING: Some clustered indexes are non-unique. Revise the need to have non-unique clustering keys to which a uniquefier is added]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'NonUnique_CIXs' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], I.[indexID], I.[indexName] AS [Index_Name], I.[KeyCols]
		FROM #tblIxs1 I
		WHERE [is_unique] = 0 AND indexID = 1
		ORDER BY I.[DatabaseName], I.schemaName, I.[objectName]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'NonUnique_CIXs' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Clustered Indexes with GUIDs in key subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Clustered Indexes with GUIDs in key', 10, 1) WITH NOWAIT
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs6'))
	DROP TABLE #tblIxs6;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs6'))
	CREATE TABLE #tblIxs6 ([databaseID] int, [DatabaseName] sysname, [objectID] int, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), 
		[indexID] int, [indexName] NVARCHAR(200), [indexType] tinyint, [is_unique_constraint] bit, is_unique bit, is_disabled bit, fill_factor tinyint, is_padded bit,
		KeyCols NVARCHAR(4000), KeyColsOrdered NVARCHAR(4000), Key_has_GUID int,
		CONSTRAINT PK_Ixs3 PRIMARY KEY CLUSTERED(databaseID, [objectID], [indexID]));

	UPDATE #tmpdbs1
	SET isdone = 0;

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
		SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE ' + QUOTENAME(@dbname) + ';
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ' AS Database_ID, ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS Database_Name,
	mst.[object_id] AS objectID, t.name AS schemaName, mst.[name] AS objectName, mi.index_id AS indexID, 
	mi.[name] AS Index_Name, mi.[type] AS [indexType], mi.[is_unique_constraint], mi.is_unique, mi.is_disabled,
	mi.fill_factor, mi.is_padded,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ic.key_ordinal
	FOR XML PATH('''')), 2, 8000) AS KeyCols,
	SUBSTRING((SELECT '','' + ac.name FROM sys.tables AS st
		INNER JOIN sys.indexes AS i ON st.[object_id] = i.[object_id]
		INNER JOIN sys.index_columns AS ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND ic.is_included_column = 0
		ORDER BY ac.name
	FOR XML PATH('''')), 2, 8000) AS KeyColsOrdered,
	(SELECT COUNT(sty.name) FROM sys.indexes AS i
		INNER JOIN sys.tables AS t ON t.[object_id] = i.[object_id]
		INNER JOIN sys.schemas ss ON ss.[schema_id] = t.[schema_id]
		INNER JOIN sys.index_columns AS sic ON sic.object_id = mst.object_id AND sic.index_id = mi.index_id
		INNER JOIN sys.columns AS sc ON sc.object_id = t.object_id AND sc.column_id = sic.column_id
		INNER JOIN sys.types AS sty ON sc.user_type_id = sty.user_type_id
		WHERE mi.[object_id] = i.[object_id] AND mi.index_id = i.index_id AND sic.is_included_column = 0 AND sty.name = ''uniqueidentifier'') AS [Key_has_GUID]
FROM sys.indexes AS mi
INNER JOIN sys.tables AS mst ON mst.[object_id] = mi.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE mi.type = 1 AND mi.is_unique_constraint = 0
	AND mst.is_ms_shipped = 0
	--AND OBJECTPROPERTY(o.object_id,''IsUserTable'') = 1 -- sys.tables only returns type U
ORDER BY objectName
OPTION (MAXDOP 2);'

		BEGIN TRY
			INSERT INTO #tblIxs6
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Clustered Indexes with GUIDs in key subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
			
		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END;

	IF (SELECT COUNT(*) FROM #tblIxs6 WHERE [Key_has_GUID] > 0) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Key_GUID' AS [Check], '[WARNING: Some clustered indexes have GUIDs in the key. It is recommended to revise these]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Key_GUID' AS [Information], I.[DatabaseName] AS [Database_Name], I.schemaName AS [Schema_Name], I.[objectName] AS [Table_Name], I.[indexID], I.[indexName] AS [Index_Name], I.KeyCols
		FROM #tblIxs6 I
		WHERE [Key_has_GUID] > 0
		ORDER BY I.[DatabaseName], I.schemaName, I.[objectName], I.[indexID]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Index_Key_GUID' AS [Check], '[OK]' AS [Deviation]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Foreign Keys with no Index subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Foreign Keys with no Index', 10, 1) WITH NOWAIT
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFK'))
	DROP TABLE #tblFK;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFK'))
	CREATE TABLE #tblFK ([databaseID] int, [DatabaseName] sysname, [constraint_name] NVARCHAR(200), [parent_schema_name] NVARCHAR(100), 
	[parent_table_name] NVARCHAR(200), parent_columns NVARCHAR(4000), [referenced_schema] NVARCHAR(100), [referenced_table_name] NVARCHAR(200), referenced_columns NVARCHAR(4000),
	CONSTRAINT PK_FK PRIMARY KEY CLUSTERED(databaseID, [constraint_name], [parent_schema_name]))
	
	UPDATE #tmpdbs1
	SET isdone = 0

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
	SET @sqlcmd = 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
USE ' + QUOTENAME(@dbname) + '
;WITH cteFK AS (
SELECT t.name AS [parent_schema_name],
	OBJECT_NAME(FKC.parent_object_id) [parent_table_name],
	OBJECT_NAME(constraint_object_id) AS [constraint_name],
	t2.name AS [referenced_schema],
	OBJECT_NAME(referenced_object_id) AS [referenced_table_name],
	SUBSTRING((SELECT '','' + RTRIM(COL_NAME(k.parent_object_id,parent_column_id)) AS [data()]
		FROM sys.foreign_key_columns k (NOLOCK)
		INNER JOIN sys.foreign_keys (NOLOCK) ON k.constraint_object_id = [object_id]
			AND k.constraint_object_id = FKC.constraint_object_id
		ORDER BY constraint_column_id
		FOR XML PATH('''')), 2, 8000) AS [parent_columns],
	SUBSTRING((SELECT '','' + RTRIM(COL_NAME(k.referenced_object_id,referenced_column_id)) AS [data()]
		FROM sys.foreign_key_columns k (NOLOCK)
		INNER JOIN sys.foreign_keys (NOLOCK) ON k.constraint_object_id = [object_id]
			AND k.constraint_object_id = FKC.constraint_object_id
		ORDER BY constraint_column_id
		FOR XML PATH('''')), 2, 8000) AS [referenced_columns]
FROM sys.foreign_key_columns FKC (NOLOCK)
INNER JOIN sys.objects o (NOLOCK) ON FKC.parent_object_id = o.[object_id]
INNER JOIN sys.tables mst (NOLOCK) ON mst.[object_id] = o.[object_id]
INNER JOIN sys.schemas t (NOLOCK) ON t.[schema_id] = mst.[schema_id]
INNER JOIN sys.objects so (NOLOCK) ON FKC.referenced_object_id = so.[object_id]
INNER JOIN sys.tables AS mst2 (NOLOCK) ON mst2.[object_id] = so.[object_id]
INNER JOIN sys.schemas AS t2 (NOLOCK) ON t2.[schema_id] = mst2.[schema_id]
WHERE o.type = ''U'' AND so.type = ''U''
GROUP BY o.[schema_id],so.[schema_id],FKC.parent_object_id,constraint_object_id,referenced_object_id,t.name,t2.name
),
cteIndexCols AS (
SELECT t.name AS schemaName,
OBJECT_NAME(mst.[object_id]) AS objectName,
SUBSTRING(( SELECT '','' + RTRIM(ac.name) FROM sys.tables AS st
	INNER JOIN sys.indexes AS mi ON st.[object_id] = mi.[object_id]
	INNER JOIN sys.index_columns AS ic ON mi.[object_id] = ic.[object_id] AND mi.[index_id] = ic.[index_id] 
	INNER JOIN sys.all_columns AS ac ON st.[object_id] = ac.[object_id] AND ic.[column_id] = ac.[column_id]
	WHERE i.[object_id] = mi.[object_id] AND i.index_id = mi.index_id AND ic.is_included_column = 0
	ORDER BY ac.column_id
FOR XML PATH('''')), 2, 8000) AS KeyCols
FROM sys.indexes AS i
INNER JOIN sys.tables AS mst ON mst.[object_id] = i.[object_id]
INNER JOIN sys.schemas AS t ON t.[schema_id] = mst.[schema_id]
WHERE i.[type] IN (1,2,5,6) AND i.is_unique_constraint = 0
	AND mst.is_ms_shipped = 0
)
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ' AS Database_ID, ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS Database_Name, fk.constraint_name AS constraintName,
	fk.parent_schema_name AS schemaName, fk.parent_table_name AS tableName,
	REPLACE(fk.parent_columns,'' ,'','','') AS parentColumns, fk.referenced_schema AS referencedSchemaName,
	fk.referenced_table_name AS referencedTableName, REPLACE(fk.referenced_columns,'' ,'','','') AS referencedColumns
FROM cteFK fk
WHERE NOT EXISTS (SELECT 1 FROM cteIndexCols ict 
					WHERE fk.parent_schema_name = ict.schemaName
						AND fk.parent_table_name = ict.objectName 
						AND REPLACE(fk.parent_columns,'' ,'','','') = ict.KeyCols);'
		BEGIN TRY
			INSERT INTO #tblFK
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Foreign Keys with no Index subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END;
	
	IF (SELECT COUNT(*) FROM #tblFK) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'FK_no_Index' AS [Check], '[WARNING: Some Foreign Key constraints are not supported by an Index. It is recommended to revise these]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'FK_no_Index' AS [Information], FK.[DatabaseName] AS [Database_Name], constraint_name AS [Constraint_Name],
			FK.parent_schema_name AS [Schema_Name], FK.parent_table_name AS [Table_Name],
			FK.parent_columns AS parentColumns, FK.referenced_schema AS Referenced_Schema_Name,
			FK.referenced_table_name AS Referenced_Table_Name, FK.referenced_columns AS referencedColumns
		FROM #tblFK FK
		ORDER BY [DatabaseName], parent_schema_name, parent_table_name, referenced_schema, referenced_table_name

		IF @gen_scripts = 1
		BEGIN
			DECLARE @strSQL5 NVARCHAR(4000)
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */'
			PRINT CHAR(10) + '--############# FK index creation statements #############' + CHAR(10)
			DECLARE curFKs CURSOR FAST_FORWARD FOR SELECT 'USE ' + [DatabaseName] + CHAR(10) + 'GO' + CHAR(10) +
			'CREATE INDEX IX_' + REPLACE(constraint_name,' ','_') + ' ON ' + QUOTENAME(parent_schema_name) + '.' + QUOTENAME(parent_table_name) + ' ([' + REPLACE(REPLACE(parent_columns,',','],['),']]',']') + ']);' + CHAR(10) + 'GO' + CHAR(10) 
			FROM #tblFK
			ORDER BY [DatabaseName], parent_schema_name, parent_table_name, referenced_schema, referenced_table_name

			OPEN curFKs
			FETCH NEXT FROM curFKs INTO @strSQL5
			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				PRINT @strSQL5
				FETCH NEXT FROM curFKs INTO @strSQL5
			END
			CLOSE curFKs
			DEALLOCATE curFKs
			PRINT '--############# Ended FK index creation statements #############' + CHAR(10)
		END;
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'FK_no_Index' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Indexing per Table subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Indexing per Table', 10, 1) WITH NOWAIT

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs3'))
	DROP TABLE #tblIxs3;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs3'))
	CREATE TABLE #tblIxs3 ([Operation] tinyint, [databaseID] int, [DatabaseName] sysname, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200),[Rows] BIGINT)

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs4'))
	DROP TABLE #tblIxs4;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs4'))
	CREATE TABLE #tblIxs4 ([databaseID] int, [DatabaseName] sysname, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), [CntCols] int, [CntIxs] int)
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs5'))
	DROP TABLE #tblIxs5;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs5'))
	CREATE TABLE #tblIxs5 ([databaseID] int, [DatabaseName] sysname, [schemaName] NVARCHAR(100), [objectName] NVARCHAR(200), [indexName] NVARCHAR(200), [indexLocation]  NVARCHAR(200))

	UPDATE #tmpdbs1
	SET isdone = 0

	WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
	BEGIN
		SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
		SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT 1 AS [Check], ' + CONVERT(VARCHAR(8), @dbid) + ', ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''',	
s.name, t.name, SUM(p.rows)
FROM sys.indexes AS si (NOLOCK)
INNER JOIN sys.tables AS t (NOLOCK) ON si.[object_id] = t.[object_id]
INNER JOIN sys.schemas AS s (NOLOCK) ON s.[schema_id] = t.[schema_id]
INNER JOIN sys.partitions AS p (NOLOCK) ON  si.[object_id]=p.[object_id] and si.[index_id]=p.[index_id]
WHERE si.is_hypothetical = 0
GROUP BY si.[object_id], t.name, s.name
HAVING COUNT(si.index_id) = 1 AND MAX(si.index_id) = 0
UNION ALL
SELECT 2 AS [Check], ' + CONVERT(VARCHAR(8), @dbid) + ', ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''',	
s.name, t.name, SUM(p.rows)
FROM sys.indexes AS si (NOLOCK) 
INNER JOIN sys.tables AS t (NOLOCK) ON si.[object_id] = t.[object_id]
INNER JOIN sys.schemas AS s (NOLOCK) ON s.[schema_id] = t.[schema_id]
INNER JOIN sys.partitions AS p (NOLOCK) ON  si.[object_id]=p.[object_id] and si.[index_id]=p.[index_id]
WHERE si.is_hypothetical = 0
GROUP BY t.name, s.name
HAVING COUNT(si.index_id) > 1 AND MIN(si.index_id) = 0;'
		BEGIN TRY
			INSERT INTO #tblIxs3
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Indexing per Table subsection - Error raised in TRY block 1 in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ' + CONVERT(VARCHAR(8), @dbid) + ', ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''',	s.name, t.name, COUNT(c.column_id), 
(SELECT COUNT(si.index_id) FROM sys.tables AS t2 INNER JOIN sys.indexes AS si ON si.[object_id] = t2.[object_id]
	WHERE si.index_id > 0 AND si.[object_id] = t.[object_id] AND si.is_hypothetical = 0
	GROUP BY si.[object_id])
FROM sys.tables AS t (NOLOCK)
INNER JOIN sys.columns AS c (NOLOCK) ON t.[object_id] = c.[object_id] 
INNER JOIN sys.schemas AS s (NOLOCK) ON s.[schema_id] = t.[schema_id]
GROUP BY s.name, t.name, t.[object_id];'
		BEGIN TRY
			INSERT INTO #tblIxs4
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Indexing per Table subsection - Error raised in TRY block 2 in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH

		SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT DISTINCT ' + CONVERT(VARCHAR(8), @dbid) + ', ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''', s.name, t.name, i.name, ds.name
FROM sys.tables AS t (NOLOCK)
INNER JOIN sys.indexes AS i (NOLOCK) ON t.[object_id] = i.[object_id] 
INNER JOIN sys.data_spaces AS ds (NOLOCK) ON ds.data_space_id = i.data_space_id
INNER JOIN sys.schemas AS s (NOLOCK) ON s.[schema_id] = t.[schema_id]
WHERE t.[type] = ''U''
	AND i.[type] IN (1,2)
	AND i.is_hypothetical = 0
	-- Get partitioned tables
	AND t.name IN (SELECT ob.name 
			FROM sys.tables AS ob (NOLOCK)
			INNER JOIN sys.indexes AS ind (NOLOCK) ON ind.[object_id] = ob.[object_id] 
			INNER JOIN sys.data_spaces AS sds (NOLOCK) ON sds.data_space_id = ind.data_space_id
			WHERE sds.[type] = ''PS''
			GROUP BY ob.name)
	AND ds.[type] <> ''PS'';'
		BEGIN TRY
			INSERT INTO #tblIxs5
			EXECUTE sp_executesql @sqlcmd
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Indexing per Table subsection - Error raised in TRY block 3 in database ' + @dbname +'. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		
		UPDATE #tmpdbs1
		SET isdone = 1
		WHERE [dbid] = @dbid
	END;

	IF (SELECT COUNT(*) FROM #tblIxs3 WHERE [Operation] = 1) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_Indexes' AS [Check], '[WARNING: Some tables do not have indexes]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_Indexes' AS [Check], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [Rows] AS [Row_Count] FROM #tblIxs3 WHERE [Operation] = 1
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;

	IF (SELECT COUNT(*) FROM #tblIxs3 WHERE [Operation] = 2) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_CL_Index' AS [Check], '[WARNING: Some tables do not have a clustered index, but have non-clustered index(es)]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_CL_Index' AS [Check], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [Rows] AS [Row_Count] FROM #tblIxs3 WHERE [Operation] = 2
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_no_CL_Index' AS [Check], '[OK]' AS [Deviation]
	END;

	IF (SELECT COUNT(*) FROM #tblIxs4 WHERE [CntCols] < [CntIxs]) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_more_Indexes_than_Cols' AS [Check], '[WARNING: Some tables have more indexes than columns]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_more_Indexes_than_Cols' AS [Check], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [CntCols] AS [Cnt_Columns], [CntIxs] AS [Cnt_Indexes] FROM #tblIxs4 WHERE [CntCols] < [CntIxs]
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_more_Indexes_than_Cols' AS [Check], '[OK]' AS [Deviation]
	END;
	
	IF (SELECT COUNT(*) FROM #tblIxs5) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_partition_misaligned_Indexes' AS [Check], '[WARNING: Some partitioned tables have indexes that are not aligned with the partition schema]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_partition_misaligned_Indexes' AS [Check], [DatabaseName] AS [Database_Name], schemaName AS [Schema_Name], [objectName] AS [Table_Name], [indexName] AS [Index_Name], [indexLocation] FROM #tblIxs5
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Tables_with_partition_misaligned_Indexes' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Missing Indexes subsection
-- Outputs only potentially most relevant, based in scoring method - use at you own discretion)
--------------------------------------------------------------------------------------------------------------------------------
IF @ptochecks = 1
BEGIN
	RAISERROR (N'  |-Starting Missing Indexes', 10, 1) WITH NOWAIT
	DECLARE @IC NVARCHAR(4000), @ICWI NVARCHAR(4000), @editionCheck bit

	/* Refer to https://docs.microsoft.com/sql/t-sql/functions/serverproperty-transact-sql */	
	IF (SELECT SERVERPROPERTY('EditionID')) IN (1804890536, 1872460670, 610778273, -2117995310)	
	SET @editionCheck = 1 -- supports enterprise only features
	ELSE	
	SET @editionCheck = 0; -- does not support enterprise only features
	
	-- Create the helper functions
	EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_allcols'')) DROP FUNCTION dbo.fn_createindex_allcols')
	EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_allcols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle 
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
	')
	EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_keycols'')) DROP FUNCTION dbo.fn_createindex_keycols')
	EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_keycols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle
		AND (ic.column_usage = ''''EQUALITY'''' OR ic.column_usage = ''''INEQUALITY'''')
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
	')
	EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_includecols'')) DROP FUNCTION dbo.fn_createindex_includecols')
	EXEC ('USE tempdb; EXEC(''
CREATE FUNCTION dbo.fn_createindex_includecols (@ix_handle int)
RETURNS NVARCHAR(max)
AS
BEGIN
	DECLARE @ReturnCols NVARCHAR(max)
	;WITH ColumnToPivot ([data()]) AS ( 
		SELECT CONVERT(VARCHAR(3),ic.column_id) + N'''','''' 
		FROM sys.dm_db_missing_index_details id 
		CROSS APPLY sys.dm_db_missing_index_columns(id.index_handle) ic
		WHERE id.index_handle = @ix_handle
		AND ic.column_usage = ''''INCLUDE''''
		ORDER BY ic.column_id ASC
		FOR XML PATH(''''''''), TYPE 
		), 
		XmlRawData (CSVString) AS ( 
			SELECT (SELECT [data()] AS InputData 
			FROM ColumnToPivot AS d FOR XML RAW, TYPE).value(''''/row[1]/InputData[1]'''', ''''NVARCHAR(max)'''') AS CSVCol 
		) 
	SELECT @ReturnCols = CASE WHEN LEN(CSVString) <= 1 THEN NULL ELSE LEFT(CSVString, LEN(CSVString)-1) END
	FROM XmlRawData
	RETURN (@ReturnCols)
END'')
	')

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexCreation'))
	DROP TABLE #IndexCreation;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexCreation'))
	CREATE TABLE #IndexCreation (
		[database_id] int,
		DBName NVARCHAR(1000),
		[Table] NVARCHAR(255),
		[ix_handle] int,
		[User_Hits_on_Missing_Index] bigint,
		[Estimated_Improvement_Percent] DECIMAL(5,2),
		[Avg_Total_User_Cost] float,
		[Unique_Compiles] bigint,
		[Score] NUMERIC(19,3),
		[KeyCols] NVARCHAR(1000),
		[IncludedCols] NVARCHAR(4000),
		[Ix_Name] NVARCHAR(255),
		[AllCols] NVARCHAR(max),
		[KeyColsOrdered] NVARCHAR(max),
		[IncludedColsOrdered] NVARCHAR(max)
		)

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexRedundant'))
	DROP TABLE #IndexRedundant;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexRedundant'))
	CREATE TABLE #IndexRedundant (
		DBName NVARCHAR(1000),
		[Table] NVARCHAR(255),
		[Ix_Name] NVARCHAR(255),
		[ix_handle] int,
		[KeyCols] NVARCHAR(1000),
		[IncludedCols] NVARCHAR(4000),
		[Redundant_With] NVARCHAR(255)
		)

	INSERT INTO #IndexCreation
	SELECT i.database_id,
		m.[name],
		RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)) AS [Table],
		i.index_handle AS [ix_handle],
		[User_Hits_on_Missing_Index] = (s.user_seeks + s.user_scans),
		s.avg_user_impact, -- Query cost would reduce by this amount in percentage, on average.
		s.avg_total_user_cost, -- Average cost of the user queries that could be reduced by the index in the group.
		s.unique_compiles, -- Number of compilations and recompilations that would benefit from this missing index group.
		(CONVERT(NUMERIC(19,3), s.user_seeks) + CONVERT(NUMERIC(19,3), s.user_scans)) 
			* CONVERT(NUMERIC(19,3), s.avg_total_user_cost) 
			* CONVERT(NUMERIC(19,3), s.avg_user_impact) AS Score, -- The higher the score, higher is the anticipated improvement for user queries.
		CASE WHEN (i.equality_columns IS NOT NULL AND i.inequality_columns IS NULL) THEN i.equality_columns
				WHEN (i.equality_columns IS NULL AND i.inequality_columns IS NOT NULL) THEN i.inequality_columns
				ELSE i.equality_columns + ',' + i.inequality_columns END AS [KeyCols],
		i.included_columns AS [IncludedCols],
		'IX_' + LEFT(RIGHT(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), LEN(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3))) - (CHARINDEX('.', RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), 1)) - 1),
			LEN(RIGHT(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), LEN(RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3))) - (CHARINDEX('.', RIGHT(i.[statement], LEN(i.[statement]) - (LEN(m.[name]) + 3)), 1)) - 1)) - 1) + '_' + CAST(i.index_handle AS NVARCHAR) AS [Ix_Name],
		tempdb.dbo.fn_createindex_allcols(i.index_handle), 
		tempdb.dbo.fn_createindex_keycols(i.index_handle),
		tempdb.dbo.fn_createindex_includecols(i.index_handle)
	FROM sys.dm_db_missing_index_details i
	INNER JOIN master.sys.databases m ON i.database_id = m.database_id
	INNER JOIN sys.dm_db_missing_index_groups g ON i.index_handle = g.index_handle
	INNER JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
	WHERE i.database_id > 4
	
	INSERT INTO #IndexRedundant
	SELECT I.DBName, I.[Table], I.[Ix_Name], I.[ix_handle], I.[KeyCols], I.[IncludedCols], I2.[Ix_Name]
	FROM #IndexCreation I 
	INNER JOIN #IndexCreation I2 ON I.[database_id] = I2.[database_id] AND I.[Table] = I2.[Table] AND I.[Ix_Name] <> I2.[Ix_Name]
		AND (((I.KeyColsOrdered <> I2.KeyColsOrdered OR I.[IncludedColsOrdered] <> I2.[IncludedColsOrdered])
			AND ((CASE WHEN I.[IncludedColsOrdered] IS NULL THEN I.KeyColsOrdered ELSE I.KeyColsOrdered + ',' + I.[IncludedColsOrdered] END) = (CASE WHEN I2.[IncludedColsOrdered] IS NULL THEN I2.KeyColsOrdered ELSE I2.KeyColsOrdered + ',' + I2.[IncludedColsOrdered] END)
				OR I.[AllCols] = I2.[AllCols]))
		OR (I.KeyColsOrdered <> I2.KeyColsOrdered AND I.[IncludedColsOrdered] = I2.[IncludedColsOrdered])
		OR (I.KeyColsOrdered = I2.KeyColsOrdered AND I.[IncludedColsOrdered] <> I2.[IncludedColsOrdered]))
	WHERE I.[Score] >= 100000
		AND I2.[Score] >= 100000
	GROUP BY I.DBName, I.[Table], I.[Ix_Name], I.[ix_handle], I.[KeyCols], I.[IncludedCols], I2.[Ix_Name]
	ORDER BY I.DBName, I.[Table], I.[Ix_Name]

	IF (SELECT COUNT(*) FROM #IndexCreation WHERE [Score] >= 100000) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Check], '[INFORMATION: Potentially missing indexes were found. It may be important to revise these]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Information], IC.DBName AS [Database_Name], IC.[Table] AS [Table_Name], CONVERT(bigint,[Score]) AS [Score], [User_Hits_on_Missing_Index], 
			[Estimated_Improvement_Percent], [Avg_Total_User_Cost], [Unique_Compiles], IC.[KeyCols], IC.[IncludedCols], IC.[Ix_Name] AS [Index_Name],
			SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
				WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
			ORDER BY IR.[Redundant_With]
		FOR XML PATH('')), 2, 8000) AS [Possibly_Redundant_With],
		CASE WHEN IC.[Score] >= 100000 THEN 'Y' ELSE 'N' END AS [Generate_Script]
		FROM #IndexCreation IC
		--WHERE [Score] >= 100000
		--ORDER BY IC.DBName, IC.[Score] DESC, IC.[User_Hits_on_Missing_Index], IC.[Estimated_Improvement_Percent];
		 ORDER BY IC.[Score] DESC;
		
		SELECT DISTINCT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Check], 'Possibly_redundant_IXs_in_list' AS Comments, I.DBName AS [Database_Name], I.[Table] AS [Table_Name], 
			I.[Ix_Name] AS [Index_Name], I.[KeyCols], I.[IncludedCols]
		FROM #IndexRedundant I
		ORDER BY I.DBName, I.[Table], I.[Ix_Name]
		
		IF @gen_scripts = 1
		BEGIN
			PRINT CHAR(10) + '/* Generated on ' + CONVERT (VARCHAR, GETDATE()) + ' in ' + @@SERVERNAME + ' */' + CHAR(10)

			IF (SELECT COUNT(*) FROM #IndexCreation IC
				WHERE IC.[IncludedCols] IS NULL AND IC.[Score] >= 100000
				) > 0
			BEGIN
				PRINT '--############# Indexes creation statements #############' + CHAR(10)
				DECLARE cIC CURSOR FAST_FORWARD FOR
				SELECT '-- User Hits on Missing Index ' + IC.[Ix_Name] + ': ' + CONVERT(VARCHAR(20),IC.[User_Hits_on_Missing_Index]) + CHAR(10) +
					'-- Estimated Improvement Percent: ' + CONVERT(VARCHAR(6),IC.[Estimated_Improvement_Percent]) + CHAR(10) +
					'-- Average Total User Cost: ' + CONVERT(VARCHAR(50),IC.[Avg_Total_User_Cost]) + CHAR(10) +
					'-- Unique Compiles: ' + CONVERT(VARCHAR(50),IC.[Unique_Compiles]) + CHAR(10) +
					'-- Score: ' + CONVERT(VARCHAR(20),CONVERT(bigint,IC.[Score])) + 
					CASE WHEN (SELECT COUNT(IR.[Redundant_With]) FROM #IndexRedundant IR 
						WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]) > 0 
					THEN CHAR(10) + '-- Possibly Redundant with Missing Index(es): ' + SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
						WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
						FOR XML PATH('')), 2, 8000) 
					ELSE '' END +
					CHAR(10) + 'USE ' + QUOTENAME(IC.DBName) + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sysindexes WHERE name = N''' +
					IC.[Ix_Name] + ''') DROP INDEX ' + IC.[Table] + '.' +
					IC.[Ix_Name] + ';' + CHAR(10) + 'GO' + CHAR(10) + 'CREATE INDEX ' +
					IC.[Ix_Name] + ' ON ' + IC.[Table] + ' (' + IC.[KeyCols] + CASE WHEN @editionCheck = 1 THEN ') WITH (ONLINE = ON);' ELSE ');' END + CHAR(10) + 'GO' + CHAR(10)
				FROM #IndexCreation IC
				WHERE IC.[IncludedCols] IS NULL AND IC.[Score] >= 100000
				ORDER BY IC.DBName, IC.[Table], IC.[Ix_Name]
				OPEN cIC
				FETCH NEXT FROM cIC INTO @IC
				WHILE @@FETCH_STATUS = 0
					BEGIN
						PRINT @IC
						FETCH NEXT FROM cIC INTO @IC
					END
				CLOSE cIC
				DEALLOCATE cIC
			END;

			IF (SELECT COUNT(*) FROM #IndexCreation IC
				WHERE IC.[IncludedCols] IS NOT NULL AND IC.[Score] >= 100000
				) > 0
			BEGIN
				PRINT '--############# Covering indexes creation statements #############' + CHAR(10)
				DECLARE cICWI CURSOR FAST_FORWARD FOR
				SELECT '-- User Hits on Missing Index ' + IC.[Ix_Name] + ': ' + CONVERT(VARCHAR(20),IC.[User_Hits_on_Missing_Index]) + CHAR(10) +
					'-- Estimated Improvement Percent: ' + CONVERT(VARCHAR(6),IC.[Estimated_Improvement_Percent]) + CHAR(10) +
					'-- Average Total User Cost: ' + CONVERT(VARCHAR(50),IC.[Avg_Total_User_Cost]) + CHAR(10) +
					'-- Unique Compiles: ' + CONVERT(VARCHAR(50),IC.[Unique_Compiles]) + CHAR(10) +
					'-- Score: ' + CONVERT(VARCHAR(20),CONVERT(bigint,IC.[Score])) + 
					CASE WHEN (SELECT COUNT(IR.[Redundant_With]) FROM #IndexRedundant IR 
						WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]) > 0 
					THEN CHAR(10) + '-- Possibly Redundant with Missing Index(es): ' + SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
						WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
						FOR XML PATH('')), 2, 8000) 
					ELSE '' END + 
					CHAR(10) + 'USE ' + QUOTENAME(IC.DBName) + CHAR(10) + 'GO' + CHAR(10) + 'IF EXISTS (SELECT name FROM sysindexes WHERE name = N''' +
					IC.[Ix_Name] + ''') DROP INDEX ' + IC.[Table] + '.' +
					IC.[Ix_Name] + ';' + CHAR(10) + 'GO' + CHAR(10) + 'CREATE INDEX ' +
					IC.[Ix_Name] + ' ON ' + IC.[Table] + ' (' + IC.[KeyCols] + ')' + CHAR(10) + 'INCLUDE(' + IC.[IncludedCols] + CASE WHEN @editionCheck = 1 THEN ') WITH (ONLINE = ON);' ELSE ');' END + CHAR(10) + 'GO' + CHAR(10)
				FROM #IndexCreation IC
				WHERE IC.[IncludedCols] IS NOT NULL AND IC.[Score] >= 100000
				ORDER BY IC.DBName, IC.[Table], IC.[Ix_Name]
				OPEN cICWI
				FETCH NEXT FROM cICWI INTO @ICWI
				WHILE @@FETCH_STATUS = 0
					BEGIN
						PRINT @ICWI
						FETCH NEXT FROM cICWI INTO @ICWI
					END
				CLOSE cICWI
				DEALLOCATE cICWI
			END;
			
			PRINT '--############# Ended missing indexes creation statements #############' + CHAR(10)
		END;
	END
	ELSE IF (SELECT COUNT(*) FROM #IndexCreation WHERE [Score] < 100000) > 0
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Check], '[INFORMATION: no relevant missing indexes were found, although missing indexes were identified by SQL Server]' AS [Deviation]
		SELECT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Information], IC.DBName AS [Database_Name], IC.[Table] AS [Table_Name], CONVERT(bigint,[Score]) AS [Score], [User_Hits_on_Missing_Index],
			[Estimated_Improvement_Percent], [Avg_Total_User_Cost], [Unique_Compiles], IC.[KeyCols], IC.[IncludedCols], IC.[Ix_Name] AS [Index_Name],
			SUBSTRING((SELECT ',' + IR.[Redundant_With] FROM #IndexRedundant IR 
				WHERE IC.DBName = IR.DBName AND IC.[Table] = IR.[Table] AND IC.[ix_handle] = IR.[ix_handle]
			ORDER BY IR.[Redundant_With]
		FOR XML PATH('')), 2, 8000) AS [Possibly_Redundant_With],
		CASE WHEN IC.[Score] >= 100000 THEN 'Y' ELSE 'N' END AS [Generate_Script]
		FROM #IndexCreation IC
		--WHERE [Score] < 100000
		ORDER BY IC.DBName, IC.[Score] DESC, IC.[User_Hits_on_Missing_Index], IC.[Estimated_Improvement_Percent];
	END
	ELSE
	BEGIN
		SELECT 'Index_and_Stats_checks' AS [Category], 'Missing_Indexes' AS [Check], '[OK]' AS [Deviation]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Objects naming conventions subsection
-- Refer to BOL for more information 
-- https://docs.microsoft.com/previous-versions/visualstudio/visual-studio-2010/dd172115(v=vs.100)
-- https://docs.microsoft.com/previous-versions/visualstudio/visual-studio-2010/dd172134(v=vs.100)
-- https://docs.microsoft.com/sql/t-sql/language-elements/reserved-keywords-transact-sql
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'|-Starting Objects naming conventions Checks', 10, 1) WITH NOWAIT

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpobjectnames'))
DROP TABLE #tmpobjectnames;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpobjectnames'))
CREATE TABLE #tmpobjectnames ([DBName] sysname, [schemaName] NVARCHAR(100), [Object] NVARCHAR(255), [Col] NVARCHAR(255), [type] CHAR(2), type_desc NVARCHAR(60));

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpfinalobjectnames'))
DROP TABLE #tmpfinalobjectnames;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpfinalobjectnames'))
CREATE TABLE #tmpfinalobjectnames ([Deviation] tinyint, [DBName] sysname, [schemaName] NVARCHAR(100), [Object] NVARCHAR(255), [Col] NVARCHAR(255), type_desc NVARCHAR(60), [Comment] NVARCHAR(500) NULL);

UPDATE #tmpdbs1
SET isdone = 0

WHILE (SELECT COUNT(id) FROM #tmpdbs1 WHERE isdone = 0) > 0
BEGIN
	SELECT TOP 1 @dbname = [dbname], @dbid = [dbid] FROM #tmpdbs1 WHERE isdone = 0
	SET @sqlcmd = 'USE ' + QUOTENAME(@dbname) + ';
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], s.name, so.name, NULL, type, type_desc
FROM sys.objects so 
INNER JOIN sys.schemas s ON so.schema_id = s.schema_id
WHERE so.is_ms_shipped = 0
UNION ALL
SELECT ''' + REPLACE(@dbname, CHAR(39), CHAR(95)) + ''' AS [DBName], s.name, so.name, sc.name, ''TC'' AS [type], ''TABLE_COLUMN'' AS [type_desc]
FROM sys.columns sc 
INNER JOIN sys.objects so ON sc.object_id = so.object_id
INNER JOIN sys.schemas s ON so.schema_id = s.schema_id
WHERE so.is_ms_shipped = 0'
	BEGIN TRY
		INSERT INTO #tmpobjectnames
		EXECUTE sp_executesql @sqlcmd
	END TRY
	BEGIN CATCH
		SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
		SELECT @ErrorMessage = 'Object naming conventions subsection - Error raised in TRY block in database ' + @dbname +'. ' + ERROR_MESSAGE()
		RAISERROR (@ErrorMessage, 16, 1);
	END CATCH
		
	UPDATE #tmpdbs1
	SET isdone = 1
	WHERE [dbid] = @dbid
END;

UPDATE #tmpdbs1
SET isdone = 0

CREATE INDEX IX1 ON #tmpobjectnames([type],[Object]);

/* https://docs.microsoft.com/previous-versions/visualstudio/visual-studio-2010/dd172115(v=vs.100) */
INSERT INTO #tmpfinalobjectnames
SELECT 1, [DBName], [schemaName], [Object], [Col], type_desc, NULL
FROM #tmpobjectnames
WHERE [type] = 'P' AND [Object] LIKE 'sp[_]%'
	AND [Object] NOT IN ('sp_alterdiagram','sp_creatediagram','sp_dropdiagram','sp_helpdiagramdefinition','sp_helpdiagrams','sp_renamediagram','sp_upgraddiagrams');

/* https://docs.microsoft.com/previous-versions/visualstudio/visual-studio-2010/dd172134(v=vs.100) */
INSERT INTO #tmpfinalobjectnames
SELECT 2, [DBName], [schemaName], [Object], [Col], type_desc, CASE WHEN [Object] LIKE '% %' THEN 'Space - ' + QUOTENAME([Object]) ELSE NULL END COLLATE database_default AS [Comment]
FROM #tmpobjectnames
WHERE [type] <> 'S' AND [type] <> 'TC'
	AND ([Object] LIKE '% %' --space
	OR [Object] LIKE '%[[]%'
	OR [Object] LIKE '%]%'
	OR [Object] LIKE '%-%'
	OR [Object] LIKE '%.%'
	OR [Object] LIKE '%,%'
	OR [Object] LIKE '%;%'
	OR [Object] LIKE '%' + CHAR(34) + '%' --double quote
	OR [Object] LIKE '%' + CHAR(39) + '%'); --single quote

INSERT INTO #tmpfinalobjectnames
SELECT 3, [DBName], [schemaName], [Object], [Col], type_desc, CASE WHEN [Col] LIKE '% %' THEN 'Space - ' + QUOTENAME([Col]) ELSE NULL END COLLATE database_default AS [Comment]
FROM #tmpobjectnames
WHERE [type] = 'TC'
	AND ([Col] LIKE '% %' --space
	OR [Col] LIKE '%[[]%'
	OR [Col] LIKE '%]%'
	OR [Col] LIKE '%-%'
	OR [Col] LIKE '%.%'
	OR [Col] LIKE '%,%'
	OR [Col] LIKE '%;%'
	OR [Col] LIKE '%' + CHAR(34) + '%' --double quote
	OR [Col] LIKE '%' + CHAR(39) + '%'); --single quote

/* https://docs.microsoft.com/sql/t-sql/language-elements/reserved-keywords-transact-sql */
INSERT INTO #tmpfinalobjectnames
SELECT 4, [DBName], [schemaName], [Object], [Col], type_desc, NULL
FROM #tmpobjectnames
WHERE [type] <> 'S'
AND ([Object] LIKE '% ABSOLUTE %' OR [Object] LIKE '% ABSOLUTE' OR [Object] = 'ABSOLUTE'
	OR [Object] LIKE '% ACTION %' OR [Object] LIKE '% ACTION' OR [Object] = 'ACTION'
	OR [Object] LIKE '% ADA %' OR [Object] LIKE '% ADA' OR [Object] = 'ADA'
	OR [Object] LIKE '% ADD %' OR [Object] LIKE '% ADD' OR [Object] = 'ADD'
	OR [Object] LIKE '% ADMIN %' OR [Object] LIKE '% ADMIN' OR [Object] = 'ADMIN'
	OR [Object] LIKE '% AFTER %' OR [Object] LIKE '% AFTER' OR [Object] = 'AFTER'
	OR [Object] LIKE '% AGGREGATE %' OR [Object] LIKE '% AGGREGATE' OR [Object] = 'AGGREGATE'
	OR [Object] LIKE '% ALIAS %' OR [Object] LIKE '% ALIAS' OR [Object] = 'ALIAS'
	OR [Object] LIKE '% ALL %' OR [Object] LIKE '% ALL' OR [Object] = 'ALL'
	OR [Object] LIKE '% ALLOCATE %' OR [Object] LIKE '% ALLOCATE' OR [Object] = 'ALLOCATE'
	OR [Object] LIKE '% ALTER %' OR [Object] LIKE '% ALTER' OR [Object] = 'ALTER'
	OR [Object] LIKE '% AND %' OR [Object] LIKE '% AND' OR [Object] = 'AND'
	OR [Object] LIKE '% ANY %' OR [Object] LIKE '% ANY' OR [Object] = 'ANY'
	OR [Object] LIKE '% ARE %' OR [Object] LIKE '% ARE' OR [Object] = 'ARE'
	OR [Object] LIKE '% ARRAY %' OR [Object] LIKE '% ARRAY' OR [Object] = 'ARRAY'
	OR [Object] LIKE '% AS %' OR [Object] LIKE '% AS' OR [Object] = 'AS'
	OR [Object] LIKE '% ASC %' OR [Object] LIKE '% ASC' OR [Object] = 'ASC'
	OR [Object] LIKE '% ASSERTION %' OR [Object] LIKE '% ASSERTION' OR [Object] = 'ASSERTION'
	OR [Object] LIKE '% AT %' OR [Object] LIKE '% AT' OR [Object] = 'AT'
	OR [Object] LIKE '% AUTHORIZATION %' OR [Object] LIKE '% AUTHORIZATION' OR [Object] = 'AUTHORIZATION'
	OR [Object] LIKE '% AVG %' OR [Object] LIKE '% AVG' OR [Object] = 'AVG'
	OR [Object] LIKE '% BACKUP %' OR [Object] LIKE '% BACKUP' OR [Object] = 'BACKUP'
	OR [Object] LIKE '% BEFORE %' OR [Object] LIKE '% BEFORE' OR [Object] = 'BEFORE'
	OR [Object] LIKE '% BEGIN %' OR [Object] LIKE '% BEGIN' OR [Object] = 'BEGIN'
	OR [Object] LIKE '% BETWEEN %' OR [Object] LIKE '% BETWEEN' OR [Object] = 'BETWEEN'
	OR [Object] LIKE '% BINARY %' OR [Object] LIKE '% BINARY' OR [Object] = 'BINARY'
	OR [Object] LIKE '% BIT %' OR [Object] LIKE '% BIT' OR [Object] = 'BIT'
	OR [Object] LIKE '% BIT_LENGTH %' OR [Object] LIKE '% BIT_LENGTH' OR [Object] = 'BIT_LENGTH'
	OR [Object] LIKE '% BLOB %' OR [Object] LIKE '% BLOB' OR [Object] = 'BLOB'
	OR [Object] LIKE '% BOOLEAN %' OR [Object] LIKE '% BOOLEAN' OR [Object] = 'BOOLEAN'
	OR [Object] LIKE '% BOTH %' OR [Object] LIKE '% BOTH' OR [Object] = 'BOTH'
	OR [Object] LIKE '% BREADTH %' OR [Object] LIKE '% BREADTH' OR [Object] = 'BREADTH'
	OR [Object] LIKE '% BREAK %' OR [Object] LIKE '% BREAK' OR [Object] = 'BREAK'
	OR [Object] LIKE '% BROWSE %' OR [Object] LIKE '% BROWSE' OR [Object] = 'BROWSE'
	OR [Object] LIKE '% BULK %' OR [Object] LIKE '% BULK' OR [Object] = 'BULK'
	OR [Object] LIKE '% BY %' OR [Object] LIKE '% BY' OR [Object] = 'BY'
	OR [Object] LIKE '% CALL %' OR [Object] LIKE '% CALL' OR [Object] = 'CALL'
	OR [Object] LIKE '% CASCADE %' OR [Object] LIKE '% CASCADE' OR [Object] = 'CASCADE'
	OR [Object] LIKE '% CASCADED %' OR [Object] LIKE '% CASCADED' OR [Object] = 'CASCADED'
	OR [Object] LIKE '% CASE %' OR [Object] LIKE '% CASE' OR [Object] = 'CASE'
	OR [Object] LIKE '% CAST %' OR [Object] LIKE '% CAST' OR [Object] = 'CAST'
	OR [Object] LIKE '% CATALOG %' OR [Object] LIKE '% CATALOG' OR [Object] = 'CATALOG'
	OR [Object] LIKE '% CHAR %' OR [Object] LIKE '% CHAR' OR [Object] = 'CHAR'
	OR [Object] LIKE '% CHAR_LENGTH %' OR [Object] LIKE '% CHAR_LENGTH' OR [Object] = 'CHAR_LENGTH'
	OR [Object] LIKE '% CHARACTER %' OR [Object] LIKE '% CHARACTER' OR [Object] = 'CHARACTER'
	OR [Object] LIKE '% CHARACTER_LENGTH %' OR [Object] LIKE '% CHARACTER_LENGTH' OR [Object] = 'CHARACTER_LENGTH'
	OR [Object] LIKE '% CHECK %' OR [Object] LIKE '% CHECK' OR [Object] = 'CHECK'
	OR [Object] LIKE '% CHECKPOINT %' OR [Object] LIKE '% CHECKPOINT' OR [Object] = 'CHECKPOINT'
	OR [Object] LIKE '% CLASS %' OR [Object] LIKE '% CLASS' OR [Object] = 'CLASS'
	OR [Object] LIKE '% CLOB %' OR [Object] LIKE '% CLOB' OR [Object] = 'CLOB'
	OR [Object] LIKE '% CLOSE %' OR [Object] LIKE '% CLOSE' OR [Object] = 'CLOSE'
	OR [Object] LIKE '% CLUSTERED %' OR [Object] LIKE '% CLUSTERED' OR [Object] = 'CLUSTERED'
	OR [Object] LIKE '% COALESCE %' OR [Object] LIKE '% COALESCE' OR [Object] = 'COALESCE'
	OR [Object] LIKE '% COLLATE %' OR [Object] LIKE '% COLLATE' OR [Object] = 'COLLATE'
	OR [Object] LIKE '% COLLATION %' OR [Object] LIKE '% COLLATION' OR [Object] = 'COLLATION'
	OR [Object] LIKE '% COLUMN %' OR [Object] LIKE '% COLUMN' OR [Object] = 'COLUMN'
	OR [Object] LIKE '% COMMIT %' OR [Object] LIKE '% COMMIT' OR [Object] = 'COMMIT'
	OR [Object] LIKE '% COMPLETION %' OR [Object] LIKE '% COMPLETION' OR [Object] = 'COMPLETION'
	OR [Object] LIKE '% COMPUTE %' OR [Object] LIKE '% COMPUTE' OR [Object] = 'COMPUTE'
	OR [Object] LIKE '% CONNECT %' OR [Object] LIKE '% CONNECT' OR [Object] = 'CONNECT'
	OR [Object] LIKE '% CONNECTION %' OR [Object] LIKE '% CONNECTION' OR [Object] = 'CONNECTION'
	OR [Object] LIKE '% CONSTRAINT %' OR [Object] LIKE '% CONSTRAINT' OR [Object] = 'CONSTRAINT'
	OR [Object] LIKE '% CONSTRAINTS %' OR [Object] LIKE '% CONSTRAINTS' OR [Object] = 'CONSTRAINTS'
	OR [Object] LIKE '% CONSTRUCTOR %' OR [Object] LIKE '% CONSTRUCTOR' OR [Object] = 'CONSTRUCTOR'
	OR [Object] LIKE '% CONTAINS %' OR [Object] LIKE '% CONTAINS' OR [Object] = 'CONTAINS'
	OR [Object] LIKE '% CONTAINSTABLE %' OR [Object] LIKE '% CONTAINSTABLE' OR [Object] = 'CONTAINSTABLE'
	OR [Object] LIKE '% CONTINUE %' OR [Object] LIKE '% CONTINUE' OR [Object] = 'CONTINUE'
	OR [Object] LIKE '% CONVERT %' OR [Object] LIKE '% CONVERT' OR [Object] = 'CONVERT'
	OR [Object] LIKE '% CORRESPONDING %' OR [Object] LIKE '% CORRESPONDING' OR [Object] = 'CORRESPONDING'
	OR [Object] LIKE '% COUNT %' OR [Object] LIKE '% COUNT' OR [Object] = 'COUNT'
	OR [Object] LIKE '% CREATE %' OR [Object] LIKE '% CREATE' OR [Object] = 'CREATE'
	OR [Object] LIKE '% CROSS %' OR [Object] LIKE '% CROSS' OR [Object] = 'CROSS'
	OR [Object] LIKE '% CUBE %' OR [Object] LIKE '% CUBE' OR [Object] = 'CUBE'
	OR [Object] LIKE '% CURRENT %' OR [Object] LIKE '% CURRENT' OR [Object] = 'CURRENT'
	OR [Object] LIKE '% CURRENT_DATE %' OR [Object] LIKE '% CURRENT_DATE' OR [Object] = 'CURRENT_DATE'
	OR [Object] LIKE '% CURRENT_PATH %' OR [Object] LIKE '% CURRENT_PATH' OR [Object] = 'CURRENT_PATH'
	OR [Object] LIKE '% CURRENT_ROLE %' OR [Object] LIKE '% CURRENT_ROLE' OR [Object] = 'CURRENT_ROLE'
	OR [Object] LIKE '% CURRENT_TIME %' OR [Object] LIKE '% CURRENT_TIME' OR [Object] = 'CURRENT_TIME'
	OR [Object] LIKE '% CURRENT_TIMESTAMP %' OR [Object] LIKE '% CURRENT_TIMESTAMP' OR [Object] = 'CURRENT_TIMESTAMP'
	OR [Object] LIKE '% CURRENT_USER %' OR [Object] LIKE '% CURRENT_USER' OR [Object] = 'CURRENT_USER'
	OR [Object] LIKE '% CURSOR %' OR [Object] LIKE '% CURSOR' OR [Object] = 'CURSOR'
	OR [Object] LIKE '% CYCLE %' OR [Object] LIKE '% CYCLE' OR [Object] = 'CYCLE'
	OR [Object] LIKE '% DATA %' OR [Object] LIKE '% DATA' OR [Object] = 'DATA'
	OR [Object] LIKE '% DATABASE %' OR [Object] LIKE '% DATABASE' OR [Object] = 'DATABASE'
	OR [Object] LIKE '% DATE %' OR [Object] LIKE '% DATE' OR [Object] = 'DATE'
	OR [Object] LIKE '% DAY %' OR [Object] LIKE '% DAY' OR [Object] = 'DAY'
	OR [Object] LIKE '% DBCC %' OR [Object] LIKE '% DBCC' OR [Object] = 'DBCC'
	OR [Object] LIKE '% DEALLOCATE %' OR [Object] LIKE '% DEALLOCATE' OR [Object] = 'DEALLOCATE'
	OR [Object] LIKE '% DEC %' OR [Object] LIKE '% DEC' OR [Object] = 'DEC'
	OR [Object] LIKE '% DECIMAL %' OR [Object] LIKE '% DECIMAL' OR [Object] = 'DECIMAL'
	OR [Object] LIKE '% DECLARE %' OR [Object] LIKE '% DECLARE' OR [Object] = 'DECLARE'
	OR [Object] LIKE '% DEFAULT %' OR [Object] LIKE '% DEFAULT' OR [Object] = 'DEFAULT'
	OR [Object] LIKE '% DEFERRABLE %' OR [Object] LIKE '% DEFERRABLE' OR [Object] = 'DEFERRABLE'
	OR [Object] LIKE '% DEFERRED %' OR [Object] LIKE '% DEFERRED' OR [Object] = 'DEFERRED'
	OR [Object] LIKE '% DELETE %' OR [Object] LIKE '% DELETE' OR [Object] = 'DELETE'
	OR [Object] LIKE '% DENY %' OR [Object] LIKE '% DENY' OR [Object] = 'DENY'
	OR [Object] LIKE '% DEPTH %' OR [Object] LIKE '% DEPTH' OR [Object] = 'DEPTH'
	OR [Object] LIKE '% DEREF %' OR [Object] LIKE '% DEREF' OR [Object] = 'DEREF'
	OR [Object] LIKE '% DESC %' OR [Object] LIKE '% DESC' OR [Object] = 'DESC'
	OR [Object] LIKE '% DESCRIBE %' OR [Object] LIKE '% DESCRIBE' OR [Object] = 'DESCRIBE'
	OR [Object] LIKE '% DESCRIPTOR %' OR [Object] LIKE '% DESCRIPTOR' OR [Object] = 'DESCRIPTOR'
	OR [Object] LIKE '% DESTROY %' OR [Object] LIKE '% DESTROY' OR [Object] = 'DESTROY'
	OR [Object] LIKE '% DESTRUCTOR %' OR [Object] LIKE '% DESTRUCTOR' OR [Object] = 'DESTRUCTOR'
	OR [Object] LIKE '% DETERMINISTIC %' OR [Object] LIKE '% DETERMINISTIC' OR [Object] = 'DETERMINISTIC'
	OR [Object] LIKE '% DIAGNOSTICS %' OR [Object] LIKE '% DIAGNOSTICS' OR [Object] = 'DIAGNOSTICS'
	OR [Object] LIKE '% DICTIONARY %' OR [Object] LIKE '% DICTIONARY' OR [Object] = 'DICTIONARY'
	OR [Object] LIKE '% DISCONNECT %' OR [Object] LIKE '% DISCONNECT' OR [Object] = 'DISCONNECT'
	OR [Object] LIKE '% DISK %' OR [Object] LIKE '% DISK' OR [Object] = 'DISK'
	OR [Object] LIKE '% DISTINCT %' OR [Object] LIKE '% DISTINCT' OR [Object] = 'DISTINCT'
	OR [Object] LIKE '% DISTRIBUTED %' OR [Object] LIKE '% DISTRIBUTED' OR [Object] = 'DISTRIBUTED'
	OR [Object] LIKE '% DOMAIN %' OR [Object] LIKE '% DOMAIN' OR [Object] = 'DOMAIN'
	OR [Object] LIKE '% DOUBLE %' OR [Object] LIKE '% DOUBLE' OR [Object] = 'DOUBLE'
	OR [Object] LIKE '% DROP %' OR [Object] LIKE '% DROP' OR [Object] = 'DROP'
	OR [Object] LIKE '% DUMMY %' OR [Object] LIKE '% DUMMY' OR [Object] = 'DUMMY'
	OR [Object] LIKE '% DUMP %' OR [Object] LIKE '% DUMP' OR [Object] = 'DUMP'
	OR [Object] LIKE '% DYNAMIC %' OR [Object] LIKE '% DYNAMIC' OR [Object] = 'DYNAMIC'
	OR [Object] LIKE '% EACH %' OR [Object] LIKE '% EACH' OR [Object] = 'EACH'
	OR [Object] LIKE '% ELSE %' OR [Object] LIKE '% ELSE' OR [Object] = 'ELSE'
	OR [Object] LIKE '% END %' OR [Object] LIKE '% END' OR [Object] = 'END'
	OR [Object] LIKE '% END-EXEC %' OR [Object] LIKE '% END-EXEC' OR [Object] = 'END-EXEC'
	OR [Object] LIKE '% EQUALS %' OR [Object] LIKE '% EQUALS' OR [Object] = 'EQUALS'
	OR [Object] LIKE '% ERRLVL %' OR [Object] LIKE '% ERRLVL' OR [Object] = 'ERRLVL'
	OR [Object] LIKE '% ESCAPE %' OR [Object] LIKE '% ESCAPE' OR [Object] = 'ESCAPE'
	OR [Object] LIKE '% EVERY %' OR [Object] LIKE '% EVERY' OR [Object] = 'EVERY'
	OR [Object] LIKE '% EXCEPT %' OR [Object] LIKE '% EXCEPT' OR [Object] = 'EXCEPT'
	OR [Object] LIKE '% EXCEPTION %' OR [Object] LIKE '% EXCEPTION' OR [Object] = 'EXCEPTION'
	OR [Object] LIKE '% EXEC %' OR [Object] LIKE '% EXEC' OR [Object] = 'EXEC'
	OR [Object] LIKE '% EXECUTE %' OR [Object] LIKE '% EXECUTE' OR [Object] = 'EXECUTE'
	OR [Object] LIKE '% EXISTS %' OR [Object] LIKE '% EXISTS' OR [Object] = 'EXISTS'
	OR [Object] LIKE '% EXIT %' OR [Object] LIKE '% EXIT' OR [Object] = 'EXIT'
	OR [Object] LIKE '% EXTERNAL %' OR [Object] LIKE '% EXTERNAL' OR [Object] = 'EXTERNAL'
	OR [Object] LIKE '% EXTRACT %' OR [Object] LIKE '% EXTRACT' OR [Object] = 'EXTRACT'
	OR [Object] LIKE '% FALSE %' OR [Object] LIKE '% FALSE' OR [Object] = 'FALSE'
	OR [Object] LIKE '% FETCH %' OR [Object] LIKE '% FETCH' OR [Object] = 'FETCH'
	OR [Object] LIKE '% FILE %' OR [Object] LIKE '% FILE' OR [Object] = 'FILE'
	OR [Object] LIKE '% FILLFACTOR %' OR [Object] LIKE '% FILLFACTOR' OR [Object] = 'FILLFACTOR'
	OR [Object] LIKE '% FIRST %' OR [Object] LIKE '% FIRST' OR [Object] = 'FIRST'
	OR [Object] LIKE '% FLOAT %' OR [Object] LIKE '% FLOAT' OR [Object] = 'FLOAT'
	OR [Object] LIKE '% FOR %' OR [Object] LIKE '% FOR' OR [Object] = 'FOR'
	OR [Object] LIKE '% FOREIGN %' OR [Object] LIKE '% FOREIGN' OR [Object] = 'FOREIGN'
	OR [Object] LIKE '% FORTRAN %' OR [Object] LIKE '% FORTRAN' OR [Object] = 'FORTRAN'
	OR [Object] LIKE '% FOUND %' OR [Object] LIKE '% FOUND' OR [Object] = 'FOUND'
	OR [Object] LIKE '% FREE %' OR [Object] LIKE '% FREE' OR [Object] = 'FREE'
	OR [Object] LIKE '% FREETEXT %' OR [Object] LIKE '% FREETEXT' OR [Object] = 'FREETEXT'
	OR [Object] LIKE '% FREETEXTTABLE %' OR [Object] LIKE '% FREETEXTTABLE' OR [Object] = 'FREETEXTTABLE'
	OR [Object] LIKE '% FROM %' OR [Object] LIKE '% FROM' OR [Object] = 'FROM'
	OR [Object] LIKE '% FULL %' OR [Object] LIKE '% FULL' OR [Object] = 'FULL'
	OR [Object] LIKE '% FULLTEXTTABLE %' OR [Object] LIKE '% FULLTEXTTABLE' OR [Object] = 'FULLTEXTTABLE'
	OR [Object] LIKE '% FUNCTION %' OR [Object] LIKE '% FUNCTION' OR [Object] = 'FUNCTION'
	OR [Object] LIKE '% GENERAL %' OR [Object] LIKE '% GENERAL' OR [Object] = 'GENERAL'
	OR [Object] LIKE '% GET %' OR [Object] LIKE '% GET' OR [Object] = 'GET'
	OR [Object] LIKE '% GLOBAL %' OR [Object] LIKE '% GLOBAL' OR [Object] = 'GLOBAL'
	OR [Object] LIKE '% GO %' OR [Object] LIKE '% GO' OR [Object] = 'GO'
	OR [Object] LIKE '% GOTO %' OR [Object] LIKE '% GOTO' OR [Object] = 'GOTO'
	OR [Object] LIKE '% GRANT %' OR [Object] LIKE '% GRANT' OR [Object] = 'GRANT'
	OR [Object] LIKE '% GROUP %' OR [Object] LIKE '% GROUP' OR [Object] = 'GROUP'
	OR [Object] LIKE '% GROUPING %' OR [Object] LIKE '% GROUPING' OR [Object] = 'GROUPING'
	OR [Object] LIKE '% HAVING %' OR [Object] LIKE '% HAVING' OR [Object] = 'HAVING'
	OR [Object] LIKE '% HOLDLOCK %' OR [Object] LIKE '% HOLDLOCK' OR [Object] = 'HOLDLOCK'
	OR [Object] LIKE '% HOST %' OR [Object] LIKE '% HOST' OR [Object] = 'HOST'
	OR [Object] LIKE '% HOUR %' OR [Object] LIKE '% HOUR' OR [Object] = 'HOUR'
	OR [Object] LIKE '% IDENTITY %' OR [Object] LIKE '% IDENTITY' OR [Object] = 'IDENTITY'
	OR [Object] LIKE '% IDENTITY_INSERT %' OR [Object] LIKE '% IDENTITY_INSERT' OR [Object] = 'IDENTITY_INSERT'
	OR [Object] LIKE '% IDENTITYCOL %' OR [Object] LIKE '% IDENTITYCOL' OR [Object] = 'IDENTITYCOL'
	OR [Object] LIKE '% IF %' OR [Object] LIKE '% IF' OR [Object] = 'IF'
	OR [Object] LIKE '% IGNORE %' OR [Object] LIKE '% IGNORE' OR [Object] = 'IGNORE'
	OR [Object] LIKE '% IMMEDIATE %' OR [Object] LIKE '% IMMEDIATE' OR [Object] = 'IMMEDIATE'
	OR [Object] LIKE '% IN %' OR [Object] LIKE '% IN' OR [Object] = 'IN'
	OR [Object] LIKE '% INCLUDE %' OR [Object] LIKE '% INCLUDE' OR [Object] = 'INCLUDE'
	OR [Object] LIKE '% INDEX %' OR [Object] LIKE '% INDEX' OR [Object] = 'INDEX'
	OR [Object] LIKE '% INDICATOR %' OR [Object] LIKE '% INDICATOR' OR [Object] = 'INDICATOR'
	OR [Object] LIKE '% INITIALIZE %' OR [Object] LIKE '% INITIALIZE' OR [Object] = 'INITIALIZE'
	OR [Object] LIKE '% INITIALLY %' OR [Object] LIKE '% INITIALLY' OR [Object] = 'INITIALLY'
	OR [Object] LIKE '% INNER %' OR [Object] LIKE '% INNER' OR [Object] = 'INNER'
	OR [Object] LIKE '% INOUT %' OR [Object] LIKE '% INOUT' OR [Object] = 'INOUT'
	OR [Object] LIKE '% INPUT %' OR [Object] LIKE '% INPUT' OR [Object] = 'INPUT'
	OR [Object] LIKE '% INSENSITIVE %' OR [Object] LIKE '% INSENSITIVE' OR [Object] = 'INSENSITIVE'
	OR [Object] LIKE '% INSERT %' OR [Object] LIKE '% INSERT' OR [Object] = 'INSERT'
	OR [Object] LIKE '% INT %' OR [Object] LIKE '% INT' OR [Object] = 'INT'
	OR [Object] LIKE '% INTEGER %' OR [Object] LIKE '% INTEGER' OR [Object] = 'INTEGER'
	OR [Object] LIKE '% INTERSECT %' OR [Object] LIKE '% INTERSECT' OR [Object] = 'INTERSECT'
	OR [Object] LIKE '% INTERVAL %' OR [Object] LIKE '% INTERVAL' OR [Object] = 'INTERVAL'
	OR [Object] LIKE '% INTO %' OR [Object] LIKE '% INTO' OR [Object] = 'INTO'
	OR [Object] LIKE '% IS %' OR [Object] LIKE '% IS' OR [Object] = 'IS'
	OR [Object] LIKE '% ISOLATION %' OR [Object] LIKE '% ISOLATION' OR [Object] = 'ISOLATION'
	OR [Object] LIKE '% ITERATE %' OR [Object] LIKE '% ITERATE' OR [Object] = 'ITERATE'
	OR [Object] LIKE '% JOIN %' OR [Object] LIKE '% JOIN' OR [Object] = 'JOIN'
	OR [Object] LIKE '% KEY %' OR [Object] LIKE '% KEY' OR [Object] = 'KEY'
	OR [Object] LIKE '% KILL %' OR [Object] LIKE '% KILL' OR [Object] = 'KILL'
	OR [Object] LIKE '% LANGUAGE %' OR [Object] LIKE '% LANGUAGE' OR [Object] = 'LANGUAGE'
	OR [Object] LIKE '% LARGE %' OR [Object] LIKE '% LARGE' OR [Object] = 'LARGE'
	OR [Object] LIKE '% LAST %' OR [Object] LIKE '% LAST' OR [Object] = 'LAST'
	OR [Object] LIKE '% LATERAL %' OR [Object] LIKE '% LATERAL' OR [Object] = 'LATERAL'
	OR [Object] LIKE '% LEADING %' OR [Object] LIKE '% LEADING' OR [Object] = 'LEADING'
	OR [Object] LIKE '% LEFT %' OR [Object] LIKE '% LEFT' OR [Object] = 'LEFT'
	OR [Object] LIKE '% LESS %' OR [Object] LIKE '% LESS' OR [Object] = 'LESS'
	OR [Object] LIKE '% LEVEL %' OR [Object] LIKE '% LEVEL' OR [Object] = 'LEVEL'
	OR [Object] LIKE '% LIKE %' OR [Object] LIKE '% LIKE' OR [Object] = 'LIKE'
	OR [Object] LIKE '% LIMIT %' OR [Object] LIKE '% LIMIT' OR [Object] = 'LIMIT'
	OR [Object] LIKE '% LINENO %' OR [Object] LIKE '% LINENO' OR [Object] = 'LINENO'
	OR [Object] LIKE '% LOAD %' OR [Object] LIKE '% LOAD' OR [Object] = 'LOAD'
	OR [Object] LIKE '% LOCAL %' OR [Object] LIKE '% LOCAL' OR [Object] = 'LOCAL'
	OR [Object] LIKE '% LOCALTIME %' OR [Object] LIKE '% LOCALTIME' OR [Object] = 'LOCALTIME'
	OR [Object] LIKE '% LOCALTIMESTAMP %' OR [Object] LIKE '% LOCALTIMESTAMP' OR [Object] = 'LOCALTIMESTAMP'
	OR [Object] LIKE '% LOCATOR %' OR [Object] LIKE '% LOCATOR' OR [Object] = 'LOCATOR'
	OR [Object] LIKE '% LOWER %' OR [Object] LIKE '% LOWER' OR [Object] = 'LOWER'
	OR [Object] LIKE '% MAP %' OR [Object] LIKE '% MAP' OR [Object] = 'MAP'
	OR [Object] LIKE '% MATCH %' OR [Object] LIKE '% MATCH' OR [Object] = 'MATCH'
	OR [Object] LIKE '% MAX %' OR [Object] LIKE '% MAX' OR [Object] = 'MAX'
	OR [Object] LIKE '% MIN %' OR [Object] LIKE '% MIN' OR [Object] = 'MIN'
	OR [Object] LIKE '% MINUTE %' OR [Object] LIKE '% MINUTE' OR [Object] = 'MINUTE'
	OR [Object] LIKE '% MODIFIES %' OR [Object] LIKE '% MODIFIES' OR [Object] = 'MODIFIES'
	OR [Object] LIKE '% MODIFY %' OR [Object] LIKE '% MODIFY' OR [Object] = 'MODIFY'
	OR [Object] LIKE '% MODULE %' OR [Object] LIKE '% MODULE' OR [Object] = 'MODULE'
	OR [Object] LIKE '% MONTH %' OR [Object] LIKE '% MONTH' OR [Object] = 'MONTH'
	OR [Object] LIKE '% NAMES %' OR [Object] LIKE '% NAMES' OR [Object] = 'NAMES'
	OR [Object] LIKE '% NATIONAL %' OR [Object] LIKE '% NATIONAL' OR [Object] = 'NATIONAL'
	OR [Object] LIKE '% NATURAL %' OR [Object] LIKE '% NATURAL' OR [Object] = 'NATURAL'
	OR [Object] LIKE '% NCHAR %' OR [Object] LIKE '% NCHAR' OR [Object] = 'NCHAR'
	OR [Object] LIKE '% NCLOB %' OR [Object] LIKE '% NCLOB' OR [Object] = 'NCLOB'
	OR [Object] LIKE '% NEW %' OR [Object] LIKE '% NEW' OR [Object] = 'NEW'
	OR [Object] LIKE '% NEXT %' OR [Object] LIKE '% NEXT' OR [Object] = 'NEXT'
	OR [Object] LIKE '% NO %' OR [Object] LIKE '% NO' OR [Object] = 'NO'
	OR [Object] LIKE '% NOCHECK %' OR [Object] LIKE '% NOCHECK' OR [Object] = 'NOCHECK'
	OR [Object] LIKE '% NONCLUSTERED %' OR [Object] LIKE '% NONCLUSTERED' OR [Object] = 'NONCLUSTERED'
	OR [Object] LIKE '% NONE %' OR [Object] LIKE '% NONE' OR [Object] = 'NONE'
	OR [Object] LIKE '% NOT %' OR [Object] LIKE '% NOT' OR [Object] = 'NOT'
	OR [Object] LIKE '% NULL %' OR [Object] LIKE '% NULL' OR [Object] = 'NULL'
	OR [Object] LIKE '% NULLIF %' OR [Object] LIKE '% NULLIF' OR [Object] = 'NULLIF'
	OR [Object] LIKE '% NUMERIC %' OR [Object] LIKE '% NUMERIC' OR [Object] = 'NUMERIC'
	OR [Object] LIKE '% OBJECT %' OR [Object] LIKE '% OBJECT' OR [Object] = 'OBJECT'
	OR [Object] LIKE '% OCTET_LENGTH %' OR [Object] LIKE '% OCTET_LENGTH' OR [Object] = 'OCTET_LENGTH'
	OR [Object] LIKE '% OF %' OR [Object] LIKE '% OF' OR [Object] = 'OF'
	OR [Object] LIKE '% OFF %' OR [Object] LIKE '% OFF' OR [Object] = 'OFF'
	OR [Object] LIKE '% OFFSETS %' OR [Object] LIKE '% OFFSETS' OR [Object] = 'OFFSETS'
	OR [Object] LIKE '% OLD %' OR [Object] LIKE '% OLD' OR [Object] = 'OLD'
	OR [Object] LIKE '% ON %' OR [Object] LIKE '% ON' OR [Object] = 'ON'
	OR [Object] LIKE '% ONLY %' OR [Object] LIKE '% ONLY' OR [Object] = 'ONLY'
	OR [Object] LIKE '% OPEN %' OR [Object] LIKE '% OPEN' OR [Object] = 'OPEN'
	OR [Object] LIKE '% OPENDATASOURCE %' OR [Object] LIKE '% OPENDATASOURCE' OR [Object] = 'OPENDATASOURCE'
	OR [Object] LIKE '% OPENQUERY %' OR [Object] LIKE '% OPENQUERY' OR [Object] = 'OPENQUERY'
	OR [Object] LIKE '% OPENROWSET %' OR [Object] LIKE '% OPENROWSET' OR [Object] = 'OPENROWSET'
	OR [Object] LIKE '% OPENXML %' OR [Object] LIKE '% OPENXML' OR [Object] = 'OPENXML'
	OR [Object] LIKE '% OPERATION %' OR [Object] LIKE '% OPERATION' OR [Object] = 'OPERATION'
	OR [Object] LIKE '% OPTION %' OR [Object] LIKE '% OPTION' OR [Object] = 'OPTION'
	OR [Object] LIKE '% OR %' OR [Object] LIKE '% OR' OR [Object] = 'OR'
	OR [Object] LIKE '% ORDER %' OR [Object] LIKE '% ORDER' OR [Object] = 'ORDER'
	OR [Object] LIKE '% ORDINALITY %' OR [Object] LIKE '% ORDINALITY' OR [Object] = 'ORDINALITY'
	OR [Object] LIKE '% OUT %' OR [Object] LIKE '% OUT' OR [Object] = 'OUT'
	OR [Object] LIKE '% OUTER %' OR [Object] LIKE '% OUTER' OR [Object] = 'OUTER'
	OR [Object] LIKE '% OUTPUT %' OR [Object] LIKE '% OUTPUT' OR [Object] = 'OUTPUT'
	OR [Object] LIKE '% OVER %' OR [Object] LIKE '% OVER' OR [Object] = 'OVER'
	OR [Object] LIKE '% OVERLAPS %' OR [Object] LIKE '% OVERLAPS' OR [Object] = 'OVERLAPS'
	OR [Object] LIKE '% PAD %' OR [Object] LIKE '% PAD' OR [Object] = 'PAD'
	OR [Object] LIKE '% PARAMETER %' OR [Object] LIKE '% PARAMETER' OR [Object] = 'PARAMETER'
	OR [Object] LIKE '% PARAMETERS %' OR [Object] LIKE '% PARAMETERS' OR [Object] = 'PARAMETERS'
	OR [Object] LIKE '% PARTIAL %' OR [Object] LIKE '% PARTIAL' OR [Object] = 'PARTIAL'
	OR [Object] LIKE '% PASCAL %' OR [Object] LIKE '% PASCAL' OR [Object] = 'PASCAL'
	OR [Object] LIKE '% PATH %' OR [Object] LIKE '% PATH' OR [Object] = 'PATH'
	OR [Object] LIKE '% PERCENT %' OR [Object] LIKE '% PERCENT' OR [Object] = 'PERCENT'
	OR [Object] LIKE '% PLAN %' OR [Object] LIKE '% PLAN' OR [Object] = 'PLAN'
	OR [Object] LIKE '% POSITION %' OR [Object] LIKE '% POSITION' OR [Object] = 'POSITION'
	OR [Object] LIKE '% POSTFIX %' OR [Object] LIKE '% POSTFIX' OR [Object] = 'POSTFIX'
	OR [Object] LIKE '% PRECISION %' OR [Object] LIKE '% PRECISION' OR [Object] = 'PRECISION'
	OR [Object] LIKE '% PREFIX %' OR [Object] LIKE '% PREFIX' OR [Object] = 'PREFIX'
	OR [Object] LIKE '% PREORDER %' OR [Object] LIKE '% PREORDER' OR [Object] = 'PREORDER'
	OR [Object] LIKE '% PREPARE %' OR [Object] LIKE '% PREPARE' OR [Object] = 'PREPARE'
	OR [Object] LIKE '% PRESERVE %' OR [Object] LIKE '% PRESERVE' OR [Object] = 'PRESERVE'
	OR [Object] LIKE '% PRIMARY %' OR [Object] LIKE '% PRIMARY' OR [Object] = 'PRIMARY'
	OR [Object] LIKE '% PRINT %' OR [Object] LIKE '% PRINT' OR [Object] = 'PRINT'
	OR [Object] LIKE '% PRIOR %' OR [Object] LIKE '% PRIOR' OR [Object] = 'PRIOR'
	OR [Object] LIKE '% PRIVILEGES %' OR [Object] LIKE '% PRIVILEGES' OR [Object] = 'PRIVILEGES'
	OR [Object] LIKE '% PROC %' OR [Object] LIKE '% PROC' OR [Object] = 'PROC'
	OR [Object] LIKE '% PROCEDURE %' OR [Object] LIKE '% PROCEDURE' OR [Object] = 'PROCEDURE'
	OR [Object] LIKE '% PUBLIC %' OR [Object] LIKE '% PUBLIC' OR [Object] = 'PUBLIC'
	OR [Object] LIKE '% RAISERROR %' OR [Object] LIKE '% RAISERROR' OR [Object] = 'RAISERROR'
	OR [Object] LIKE '% READ %' OR [Object] LIKE '% READ' OR [Object] = 'READ'
	OR [Object] LIKE '% READS %' OR [Object] LIKE '% READS' OR [Object] = 'READS'
	OR [Object] LIKE '% READTEXT %' OR [Object] LIKE '% READTEXT' OR [Object] = 'READTEXT'
	OR [Object] LIKE '% REAL %' OR [Object] LIKE '% REAL' OR [Object] = 'REAL'
	OR [Object] LIKE '% RECONFIGURE %' OR [Object] LIKE '% RECONFIGURE' OR [Object] = 'RECONFIGURE'
	OR [Object] LIKE '% RECURSIVE %' OR [Object] LIKE '% RECURSIVE' OR [Object] = 'RECURSIVE'
	OR [Object] LIKE '% REF %' OR [Object] LIKE '% REF' OR [Object] = 'REF'
	OR [Object] LIKE '% REFERENCES %' OR [Object] LIKE '% REFERENCES' OR [Object] = 'REFERENCES'
	OR [Object] LIKE '% REFERENCING %' OR [Object] LIKE '% REFERENCING' OR [Object] = 'REFERENCING'
	OR [Object] LIKE '% RELATIVE %' OR [Object] LIKE '% RELATIVE' OR [Object] = 'RELATIVE'
	OR [Object] LIKE '% REPLICATION %' OR [Object] LIKE '% REPLICATION' OR [Object] = 'REPLICATION'
	OR [Object] LIKE '% RESTORE %' OR [Object] LIKE '% RESTORE' OR [Object] = 'RESTORE'
	OR [Object] LIKE '% RESTRICT %' OR [Object] LIKE '% RESTRICT' OR [Object] = 'RESTRICT'
	OR [Object] LIKE '% RESULT %' OR [Object] LIKE '% RESULT' OR [Object] = 'RESULT'
	OR [Object] LIKE '% RETURN %' OR [Object] LIKE '% RETURN' OR [Object] = 'RETURN'
	OR [Object] LIKE '% RETURNS %' OR [Object] LIKE '% RETURNS' OR [Object] = 'RETURNS'
	OR [Object] LIKE '% REVOKE %' OR [Object] LIKE '% REVOKE' OR [Object] = 'REVOKE'
	OR [Object] LIKE '% RIGHT %' OR [Object] LIKE '% RIGHT' OR [Object] = 'RIGHT'
	OR [Object] LIKE '% ROLE %' OR [Object] LIKE '% ROLE' OR [Object] = 'ROLE'
	OR [Object] LIKE '% ROLLBACK %' OR [Object] LIKE '% ROLLBACK' OR [Object] = 'ROLLBACK'
	OR [Object] LIKE '% ROLLUP %' OR [Object] LIKE '% ROLLUP' OR [Object] = 'ROLLUP'
	OR [Object] LIKE '% ROUTINE %' OR [Object] LIKE '% ROUTINE' OR [Object] = 'ROUTINE'
	OR [Object] LIKE '% ROW %' OR [Object] LIKE '% ROW' OR [Object] = 'ROW'
	OR [Object] LIKE '% ROWCOUNT %' OR [Object] LIKE '% ROWCOUNT' OR [Object] = 'ROWCOUNT'
	OR [Object] LIKE '% ROWGUIDCOL %' OR [Object] LIKE '% ROWGUIDCOL' OR [Object] = 'ROWGUIDCOL'
	OR [Object] LIKE '% ROWS %' OR [Object] LIKE '% ROWS' OR [Object] = 'ROWS'
	OR [Object] LIKE '% RULE %' OR [Object] LIKE '% RULE' OR [Object] = 'RULE'
	OR [Object] LIKE '% SAVE %' OR [Object] LIKE '% SAVE' OR [Object] = 'SAVE'
	OR [Object] LIKE '% SAVEPOINT %' OR [Object] LIKE '% SAVEPOINT' OR [Object] = 'SAVEPOINT'
	OR [Object] LIKE '% SCHEMA %' OR [Object] LIKE '% SCHEMA' OR [Object] = 'SCHEMA'
	OR [Object] LIKE '% SCOPE %' OR [Object] LIKE '% SCOPE' OR [Object] = 'SCOPE'
	OR [Object] LIKE '% SCROLL %' OR [Object] LIKE '% SCROLL' OR [Object] = 'SCROLL'
	OR [Object] LIKE '% SEARCH %' OR [Object] LIKE '% SEARCH' OR [Object] = 'SEARCH'
	OR [Object] LIKE '% SECOND %' OR [Object] LIKE '% SECOND' OR [Object] = 'SECOND'
	OR [Object] LIKE '% SECTION %' OR [Object] LIKE '% SECTION' OR [Object] = 'SECTION'
	OR [Object] LIKE '% SELECT %' OR [Object] LIKE '% SELECT' OR [Object] = 'SELECT'
	OR [Object] LIKE '% SEQUENCE %' OR [Object] LIKE '% SEQUENCE' OR [Object] = 'SEQUENCE'
	OR [Object] LIKE '% SESSION %' OR [Object] LIKE '% SESSION' OR [Object] = 'SESSION'
	OR [Object] LIKE '% SESSION_USER %' OR [Object] LIKE '% SESSION_USER' OR [Object] = 'SESSION_USER'
	OR [Object] LIKE '% SET %' OR [Object] LIKE '% SET' OR [Object] = 'SET'
	OR [Object] LIKE '% SETS %' OR [Object] LIKE '% SETS' OR [Object] = 'SETS'
	OR [Object] LIKE '% SETUSER %' OR [Object] LIKE '% SETUSER' OR [Object] = 'SETUSER'
	OR [Object] LIKE '% SHUTDOWN %' OR [Object] LIKE '% SHUTDOWN' OR [Object] = 'SHUTDOWN'
	OR [Object] LIKE '% SIZE %' OR [Object] LIKE '% SIZE' OR [Object] = 'SIZE'
	OR [Object] LIKE '% SMALLINT %' OR [Object] LIKE '% SMALLINT' OR [Object] = 'SMALLINT'
	OR [Object] LIKE '% SOME %' OR [Object] LIKE '% SOME' OR [Object] = 'SOME'
	OR [Object] LIKE '% SPACE %' OR [Object] LIKE '% SPACE' OR [Object] = 'SPACE'
	OR [Object] LIKE '% SPECIFIC %' OR [Object] LIKE '% SPECIFIC' OR [Object] = 'SPECIFIC'
	OR [Object] LIKE '% SPECIFICTYPE %' OR [Object] LIKE '% SPECIFICTYPE' OR [Object] = 'SPECIFICTYPE'
	OR [Object] LIKE '% SQL %' OR [Object] LIKE '% SQL' OR [Object] = 'SQL'
	OR [Object] LIKE '% SQLCA %' OR [Object] LIKE '% SQLCA' OR [Object] = 'SQLCA'
	OR [Object] LIKE '% SQLCODE %' OR [Object] LIKE '% SQLCODE' OR [Object] = 'SQLCODE'
	OR [Object] LIKE '% SQLERROR %' OR [Object] LIKE '% SQLERROR' OR [Object] = 'SQLERROR'
	OR [Object] LIKE '% SQLEXCEPTION %' OR [Object] LIKE '% SQLEXCEPTION' OR [Object] = 'SQLEXCEPTION'
	OR [Object] LIKE '% SQLSTATE %' OR [Object] LIKE '% SQLSTATE' OR [Object] = 'SQLSTATE'
	OR [Object] LIKE '% SQLWARNING %' OR [Object] LIKE '% SQLWARNING' OR [Object] = 'SQLWARNING'
	OR [Object] LIKE '% START %' OR [Object] LIKE '% START' OR [Object] = 'START'
	OR [Object] LIKE '% STATE %' OR [Object] LIKE '% STATE' OR [Object] = 'STATE'
	OR [Object] LIKE '% STATEMENT %' OR [Object] LIKE '% STATEMENT' OR [Object] = 'STATEMENT'
	OR [Object] LIKE '% STATIC %' OR [Object] LIKE '% STATIC' OR [Object] = 'STATIC'
	OR [Object] LIKE '% STATISTICS %' OR [Object] LIKE '% STATISTICS' OR [Object] = 'STATISTICS'
	OR [Object] LIKE '% STRUCTURE %' OR [Object] LIKE '% STRUCTURE' OR [Object] = 'STRUCTURE'
	OR [Object] LIKE '% SUBSTRING %' OR [Object] LIKE '% SUBSTRING' OR [Object] = 'SUBSTRING'
	OR [Object] LIKE '% SUM %' OR [Object] LIKE '% SUM' OR [Object] = 'SUM'
	OR [Object] LIKE '% SYSTEM_USER %' OR [Object] LIKE '% SYSTEM_USER' OR [Object] = 'SYSTEM_USER'
	OR [Object] LIKE '% TABLE %' OR [Object] LIKE '% TABLE' OR [Object] = 'TABLE'
	OR [Object] LIKE '% TEMPORARY %' OR [Object] LIKE '% TEMPORARY' OR [Object] = 'TEMPORARY'
	OR [Object] LIKE '% TERMINATE %' OR [Object] LIKE '% TERMINATE' OR [Object] = 'TERMINATE'
	OR [Object] LIKE '% TEXTSIZE %' OR [Object] LIKE '% TEXTSIZE' OR [Object] = 'TEXTSIZE'
	OR [Object] LIKE '% THAN %' OR [Object] LIKE '% THAN' OR [Object] = 'THAN'
	OR [Object] LIKE '% THEN %' OR [Object] LIKE '% THEN' OR [Object] = 'THEN'
	OR [Object] LIKE '% TIME %' OR [Object] LIKE '% TIME' OR [Object] = 'TIME'
	OR [Object] LIKE '% TIMESTAMP %' OR [Object] LIKE '% TIMESTAMP' OR [Object] = 'TIMESTAMP'
	OR [Object] LIKE '% TIMEZONE_HOUR %' OR [Object] LIKE '% TIMEZONE_HOUR' OR [Object] = 'TIMEZONE_HOUR'
	OR [Object] LIKE '% TIMEZONE_MINUTE %' OR [Object] LIKE '% TIMEZONE_MINUTE' OR [Object] = 'TIMEZONE_MINUTE'
	OR [Object] LIKE '% TO %' OR [Object] LIKE '% TO' OR [Object] = 'TO'
	OR [Object] LIKE '% TOP %' OR [Object] LIKE '% TOP' OR [Object] = 'TOP'
	OR [Object] LIKE '% TRAILING %' OR [Object] LIKE '% TRAILING' OR [Object] = 'TRAILING'
	OR [Object] LIKE '% TRAN %' OR [Object] LIKE '% TRAN' OR [Object] = 'TRAN'
	OR [Object] LIKE '% TRANSACTION %' OR [Object] LIKE '% TRANSACTION' OR [Object] = 'TRANSACTION'
	OR [Object] LIKE '% TRANSLATE %' OR [Object] LIKE '% TRANSLATE' OR [Object] = 'TRANSLATE'
	OR [Object] LIKE '% TRANSLATION %' OR [Object] LIKE '% TRANSLATION' OR [Object] = 'TRANSLATION'
	OR [Object] LIKE '% TREAT %' OR [Object] LIKE '% TREAT' OR [Object] = 'TREAT'
	OR [Object] LIKE '% TRIGGER %' OR [Object] LIKE '% TRIGGER' OR [Object] = 'TRIGGER'
	OR [Object] LIKE '% TRIM %' OR [Object] LIKE '% TRIM' OR [Object] = 'TRIM'
	OR [Object] LIKE '% TRUE %' OR [Object] LIKE '% TRUE' OR [Object] = 'TRUE'
	OR [Object] LIKE '% TRUNCATE %' OR [Object] LIKE '% TRUNCATE' OR [Object] = 'TRUNCATE'
	OR [Object] LIKE '% UNDER %' OR [Object] LIKE '% UNDER' OR [Object] = 'UNDER'
	OR [Object] LIKE '% UNION %' OR [Object] LIKE '% UNION' OR [Object] = 'UNION'
	OR [Object] LIKE '% UNIQUE %' OR [Object] LIKE '% UNIQUE' OR [Object] = 'UNIQUE'
	OR [Object] LIKE '% UNKNOWN %' OR [Object] LIKE '% UNKNOWN' OR [Object] = 'UNKNOWN'
	OR [Object] LIKE '% UNNEST %' OR [Object] LIKE '% UNNEST' OR [Object] = 'UNNEST'
	OR [Object] LIKE '% UPDATE %' OR [Object] LIKE '% UPDATE' OR [Object] = 'UPDATE'
	OR [Object] LIKE '% UPDATETEXT %' OR [Object] LIKE '% UPDATETEXT' OR [Object] = 'UPDATETEXT'
	OR [Object] LIKE '% UPPER %' OR [Object] LIKE '% UPPER' OR [Object] = 'UPPER'
	OR [Object] LIKE '% USAGE %' OR [Object] LIKE '% USAGE' OR [Object] = 'USAGE'
	OR [Object] LIKE '% USE %' OR [Object] LIKE '% USE' OR [Object] = 'USE'
	OR [Object] LIKE '% USER %' OR [Object] LIKE '% USER' OR [Object] = 'USER'
	OR [Object] LIKE '% USING %' OR [Object] LIKE '% USING' OR [Object] = 'USING'
	OR [Object] LIKE '% VALUE %' OR [Object] LIKE '% VALUE' OR [Object] = 'VALUE'
	OR [Object] LIKE '% VALUES %' OR [Object] LIKE '% VALUES' OR [Object] = 'VALUES'
	OR [Object] LIKE '% VARCHAR %' OR [Object] LIKE '% VARCHAR' OR [Object] = 'VARCHAR'
	OR [Object] LIKE '% VARIABLE %' OR [Object] LIKE '% VARIABLE' OR [Object] = 'VARIABLE'
	OR [Object] LIKE '% VARYING %' OR [Object] LIKE '% VARYING' OR [Object] = 'VARYING'
	OR [Object] LIKE '% VIEW %' OR [Object] LIKE '% VIEW' OR [Object] = 'VIEW'
	OR [Object] LIKE '% WAITFOR %' OR [Object] LIKE '% WAITFOR' OR [Object] = 'WAITFOR'
	OR [Object] LIKE '% WHEN %' OR [Object] LIKE '% WHEN' OR [Object] = 'WHEN'
	OR [Object] LIKE '% WHENEVER %' OR [Object] LIKE '% WHENEVER' OR [Object] = 'WHENEVER'
	OR [Object] LIKE '% WHERE %' OR [Object] LIKE '% WHERE' OR [Object] = 'WHERE'
	OR [Object] LIKE '% WHILE %' OR [Object] LIKE '% WHILE' OR [Object] = 'WHILE'
	OR [Object] LIKE '% WITH %' OR [Object] LIKE '% WITH' OR [Object] = 'WITH'
	OR [Object] LIKE '% WITHOUT %' OR [Object] LIKE '% WITHOUT' OR [Object] = 'WITHOUT'
	OR [Object] LIKE '% WORK %' OR [Object] LIKE '% WORK' OR [Object] = 'WORK'
	OR [Object] LIKE '% WRITE %' OR [Object] LIKE '% WRITE' OR [Object] = 'WRITE'
	OR [Object] LIKE '% WRITETEXT %' OR [Object] LIKE '% WRITETEXT' OR [Object] = 'WRITETEXT'
	OR [Object] LIKE '% YEAR %' OR [Object] LIKE '% YEAR' OR [Object] = 'YEAR'
	OR [Object] LIKE '% ZONE %' OR [Object] LIKE '% ZONE' OR [Object] = 'ZONE');

/* https://docs.microsoft.com/sql/t-sql/statements/create-function-transact-sql*/
INSERT INTO #tmpfinalobjectnames
SELECT 5, [DBName], [schemaName], [Object], [Col], type_desc, NULL
FROM #tmpobjectnames
WHERE [type] IN ('FN','FS','TF','IF') AND [Object] LIKE 'fn[_]%'
	AND [Object] NOT IN ('fn_diagram_objects');	
	
	
IF (SELECT COUNT(*) FROM #tmpfinalobjectnames) > 0
BEGIN
	SELECT 'Naming_checks' AS [Category], 'Object_Naming_Convention' AS [Check], '[WARNING: Reserved words or special characters have been found in object names]' AS [Deviation]
END
ELSE
BEGIN
	SELECT 'Naming_checks' AS [Category], 'Object_Naming_Convention' AS [Check], '[OK]' AS [Deviation]
END;

IF (SELECT COUNT(*) FROM #tmpfinalobjectnames) > 0
BEGIN
	SELECT 'Naming_checks' AS [Category], 'Object_Naming_Convention' AS [Check], 
		CASE [Deviation] WHEN 1 THEN '[sp_ as prefix for stored procedures]'
			WHEN 2 THEN '[Special character as part of object name]'
			WHEN 3 THEN '[Special character as part of column name]'
			WHEN 4 THEN '[Reserved words as part of object name]'
			WHEN 5 THEN '[fn_ as prefix for user defined functions]'
			END AS [Deviation], 
		[DBName] AS [Database_Name], [schemaName] AS [Schema_Name], [Object] AS [Object_Name], QUOTENAME([Col]) AS [Col], [type_desc] AS [Object_Type] 
	FROM #tmpfinalobjectnames
	ORDER BY [Deviation], type_desc, [DBName], [schemaName], [Object];
END;

RAISERROR (N'|-Starting Security Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- Password check subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Password check', 10, 1) WITH NOWAIT
DECLARE @passwords TABLE ([Deviation] VARCHAR(15), [Name] sysname, [CreateDate] DATETIME)
DECLARE @word TABLE (word NVARCHAR(50))
INSERT INTO @word values (0)
INSERT INTO @word values (1)
INSERT INTO @word values (12)
INSERT INTO @word values (123)
INSERT INTO @word values (1234)
INSERT INTO @word values (12345)
INSERT INTO @word values (123456)
INSERT INTO @word values (1234567)
INSERT INTO @word values (12345678)
INSERT INTO @word values (123456789)
INSERT INTO @word values (1234567890)
INSERT INTO @word values (11111)
INSERT INTO @word values (111111)
INSERT INTO @word values (1111111)
INSERT INTO @word values (11111111)
INSERT INTO @word values (21)
INSERT INTO @word values (321)
INSERT INTO @word values (4321)
INSERT INTO @word values (54321)
INSERT INTO @word values (654321)
INSERT INTO @word values (7654321)
INSERT INTO @word values (87654321)
INSERT INTO @word values (987654321)
INSERT INTO @word values (0987654321)
INSERT INTO @word values ('pwd')
INSERT INTO @word values ('Password')
INSERT INTO @word values ('password')
INSERT INTO @word values ('P@ssw0rd')
INSERT INTO @word values ('p@ssw0rd')
INSERT INTO @word values ('Teste')
INSERT INTO @word values ('teste')
INSERT INTO @word values ('Test')
INSERT INTO @word values ('test')
INSERT INTO @word values ('')
INSERT INTO @word values ('p@wd')

INSERT INTO @passwords
SELECT DISTINCT 'Weak_Password' AS Deviation, RTRIM(s.name) AS [Name], createdate AS [CreateDate] 
FROM @word d
	INNER JOIN master.sys.syslogins s ON PWDCOMPARE(RTRIM(RTRIM(d.word)), s.[password]) = 1
UNION ALL
SELECT 'NULL_Passwords' AS Deviation, RTRIM(name) AS [Name], createdate AS [CreateDate] 
FROM master.sys.syslogins
WHERE [password] IS NULL
	AND isntname = 0 
	AND name NOT IN ('MSCRMSqlClrLogin','##MS_SmoExtendedSigningCertificate##','##MS_PolicySigningCertificate##','##MS_SQLResourceSigningCertificate##','##MS_SQLReplicationSigningCertificate##','##MS_SQLAuthenticatorCertificate##','##MS_AgentSigningCertificate##','##MS_SQLEnableSystemAssemblyLoadingUser##')
UNION ALL
SELECT DISTINCT 'Name=Password' AS Deviation, RTRIM(s.name) AS [Name], createdate AS [CreateDate] 
FROM master.sys.syslogins s 
WHERE PWDCOMPARE(RTRIM(RTRIM(s.name)), s.[password]) = 1
ORDER BY [Deviation], [Name]

IF (SELECT COUNT([Deviation]) FROM @passwords) > 0
BEGIN
	SELECT 'Security_checks' AS [Category], 'Password_checks' AS [Check], '[WARNING: Some user logins have weak passwords. Please review these as soon as possible]' AS [Deviation]
	SELECT 'Security_checks' AS [Category], 'Password_checks' AS [Information], [Deviation], [Name], [CreateDate]
	FROM @passwords
	ORDER BY [Deviation], [Name]
END
ELSE
BEGIN
	SELECT 'Security_checks' AS [Category], 'Password_checks' AS [Check], '[OK]' AS [Deviation]
END;

RAISERROR (N'|-Starting Maintenance and Monitoring Checks', 10, 1) WITH NOWAIT

--------------------------------------------------------------------------------------------------------------------------------
-- SQL Agent alerts for severe errors subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting SQL Agent alerts for severe errors', 10, 1) WITH NOWAIT
IF (SELECT [perm] FROM @permstbl_msdb WHERE [id] = 1) = 0 AND (SELECT [perm] FROM @permstbl_msdb WHERE [id] = 2) = 0
BEGIN
	RAISERROR('[WARNING: If not sysadmin, then you must be a member of MSDB SQLAgentOperatorRole role, or have SELECT permission on the sysalerts table in MSDB. Bypassing check]', 16, 1, N'msdbperms')
	--RETURN
END
ELSE
BEGIN
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_10' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (825,833,855,856,3452,3619,17179,17883,17884,17887,17888,17890,28036) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (825,833,855,856,3452,3619,17179,17883,17884,17887,17888,17890,28036) OR severity = 10
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_16' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (2508,2511,3271,5228,5229,5242,5243,5250,5901,17130,17300) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (610,2508,2511,3271,5228,5229,5242,5243,5250,5901,8621,17065,17066,17067,17130,17300) OR severity = 16
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_17' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (802,845,1101,1105,1121,1214,9002) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (802,845,1101,1105,1121,1214,8642,9002) OR severity = 17
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_19' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (701) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (701) OR severity = 19
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_20' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (3624) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (3624) OR severity = 20
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_21' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (605) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (605) OR severity = 21
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_22' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (5180,8966) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (5180,8966) OR severity = 22
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_23' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (5572,9100) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (5572,9100) OR severity = 23
	UNION ALL
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts_Severity_24' AS [Check], CASE WHEN COUNT([name]) > 0 THEN '[OK]' ELSE '[WARNING: Important errors (823,824,832) are not raising alerts. Please review the need to create these]' END AS [Deviation]
	FROM msdb.dbo.sysalerts
	WHERE [message_id] IN (823,824,832) OR severity = 24
		
	IF (SELECT COUNT([name]) FROM msdb.dbo.sysalerts WHERE ([message_id] IN (825,833,855,856,3452,3619,17179,17883,17884,17887,17888,17890,28036, -- Sev 10
			610,2508,2511,3271,5228,5229,5242,5243,5250,5901,8621,17065,17066,17067,17130,17300, -- Sev 16 
			802,845,1101,1105,1121,1214,8642,9002, -- Sev 17
			701, -- Sev 19
			3624, -- Sev 20
			605, -- Sev 21
			5180,8966, -- Sev 22
			5572,9100, -- Sev 23
			823,824,832 -- Sev 24
			) OR [severity] >= 17)) > 0
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Agent_Alerts' AS [Information], QUOTENAME([name]) AS [Configured_Alert], CASE WHEN [enabled] = 1 THEN 'Enabled' ELSE 'Disabled' END AS [Alert_Status], [event_source] AS [Event_Source], [message_id], [severity]
		FROM msdb.dbo.sysalerts
		WHERE ([message_id] IN (825,833,855,856,3452,3619,17179,17883,17884,17887,17888,17890,28036, -- Sev 10
			610,2508,2511,3271,5228,5229,5242,5243,5250,5901,8621,17065,17066,17067,17130,17300, -- Sev 16 
			802,845,1101,1105,1121,1214,8642,9002, -- Sev 17
			701, -- Sev 19
			3624, -- Sev 20
			605, -- Sev 21
			5180,8966, -- Sev 22
			5572,9100, -- Sev 23
			823,824,832 -- Sev 24
			) OR [severity] >= 17);
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- DBCC CHECKDB, Direct Catalog Updates and Data Purity subsection
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting DBCC CHECKDB, Direct Catalog Updates and Data Purity', 10, 1) WITH NOWAIT
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#output_dbinfo'))
DROP TABLE #output_dbinfo;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#output_dbinfo'))
CREATE TABLE #output_dbinfo (ParentObject NVARCHAR(255), [Object] NVARCHAR(255), Field NVARCHAR(255), [value] NVARCHAR(255))
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbinfo'))
DROP TABLE #dbinfo;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbinfo'))
CREATE TABLE #dbinfo (rowid int IDENTITY(1,1) PRIMARY KEY CLUSTERED, dbname NVARCHAR(255), lst_known_checkdb DATETIME NULL, updSysCatalog DATETIME NULL, dbi_createVersion int NULL, dbi_dbccFlags int NULL) 

IF (ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1)
BEGIN
	--DECLARE @dbname NVARCHAR(255);
	DECLARE @dbcc bit, @catupd bit, @purity bit;
	DECLARE curDBs CURSOR FAST_FORWARD FOR SELECT [name] FROM master.sys.databases (NOLOCK) WHERE is_read_only = 0 AND [state] = 0
	OPEN curDBs
	FETCH NEXT FROM curDBs INTO @dbname
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		IF (SELECT CHARINDEX(CHAR(39), @dbname)) > 0
			OR (SELECT CHARINDEX(CHAR(45), @dbname)) > 0
			OR (SELECT CHARINDEX(CHAR(47), @dbname)) > 0
		BEGIN
			SELECT @ErrorMessage = '    |-Skipping Database ID ' + CONVERT(NVARCHAR, DB_ID(QUOTENAME(@dbname))) + ' due to possible SQL Injection'
			RAISERROR (@ErrorMessage, 10, 1) WITH NOWAIT;
		END
		ELSE
		BEGIN
			SET @dbname = RTRIM(LTRIM(@dbname))
			SET @query = N'DBCC DBINFO(N''' + @dbname + N''') WITH TABLERESULTS, NO_INFOMSGS'

			INSERT INTO #output_dbinfo
			EXEC (@query)
		
			INSERT INTO #dbinfo (dbname, lst_known_checkdb)
			SELECT @dbname, [value] FROM #output_dbinfo WHERE Field LIKE 'dbi_dbccLastKnownGood%';
		
			UPDATE #dbinfo
			SET #dbinfo.updSysCatalog = #output_dbinfo.[value]
			FROM #output_dbinfo 
			WHERE #dbinfo.dbname = @dbname AND #output_dbinfo.Field LIKE 'dbi_updSysCatalog%';
		
			UPDATE #dbinfo
			SET #dbinfo.dbi_createVersion = #output_dbinfo.[value]
			FROM #output_dbinfo 
			WHERE #dbinfo.dbname = @dbname AND #output_dbinfo.Field LIKE 'dbi_createVersion%';
		
			UPDATE #dbinfo
			SET #dbinfo.dbi_dbccFlags = #output_dbinfo.[value]
			FROM #output_dbinfo 
			WHERE #dbinfo.dbname = @dbname AND #output_dbinfo.Field LIKE 'dbi_dbccFlags%';
		END;
		
		TRUNCATE TABLE #output_dbinfo;
		FETCH NEXT FROM curDBs INTO @dbname
	END
	CLOSE curDBs
	DEALLOCATE curDBs;

	;WITH cte_dbcc (name, lst_known_checkdb) AS (SELECT sd.name, tmpdbi.lst_known_checkdb 
		FROM master.sys.databases sd (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON sd.name = tmpdbi.dbname
		WHERE sd.database_id <> 2 AND is_read_only = 0 AND [state] = 0)
	SELECT @dbcc = CASE WHEN COUNT(name) > 0 THEN 1 ELSE 0 END 
	FROM cte_dbcc WHERE DATEDIFF(dd, lst_known_checkdb, GETDATE()) > 7 OR lst_known_checkdb IS NULL;

	;WITH cte_catupd (name, updSysCatalog) AS (SELECT sd.name, tmpdbi.updSysCatalog 
		FROM master.sys.databases sd (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON sd.name = tmpdbi.dbname
		WHERE sd.database_id <> 2 AND is_read_only = 0 AND [state] = 0)
	SELECT @catupd = CASE WHEN COUNT(name) > 0 THEN 1 ELSE 0 END 
	FROM cte_catupd WHERE updSysCatalog > '1900-01-01 00:00:00.000';

	;WITH cte_purity (name, dbi_createVersion, dbi_dbccFlags) AS (SELECT sd.name, tmpdbi.dbi_createVersion, tmpdbi.dbi_dbccFlags 
		FROM master.sys.databases sd (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON sd.name = tmpdbi.dbname
		WHERE sd.database_id > 4 AND is_read_only = 0 AND [state] = 0)
	SELECT @purity = CASE WHEN COUNT(name) > 0 THEN 1 ELSE 0 END 
	FROM cte_purity WHERE dbi_createVersion <= 611 AND dbi_dbccFlags = 0; -- <= SQL Server 2005

	IF @dbcc = 1
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'DBCC_CHECKDB' AS [Check], '[WARNING: database integrity checks have not been executed for over 7 days on some or all databases. It is recommended to run DBCC CHECKDB on these databases as soon as possible]' AS [Deviation]
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'DBCC_CHECKDB' AS [Information], [name] AS [Database_Name], MAX(lst_known_checkdb) AS Last_Known_CHECKDB
		FROM master.sys.databases (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON name = tmpdbi.dbname
		WHERE database_id <> 2 AND is_read_only = 0 AND [state] = 0
		GROUP BY [name]
		HAVING DATEDIFF(dd, MAX(lst_known_checkdb), GETDATE()) > 7 OR MAX(lst_known_checkdb) IS NULL
		ORDER BY [name]
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'DBCC_CHECKDB' AS [Check], '[OK]' AS [Deviation]
	END;

	IF @catupd = 1
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Direct_Catalog_Updates' AS [Check], '[WARNING: Microsoft does not support direct catalog updates to databases.]' AS [Deviation]
		SELECT DISTINCT 'Instance_checks' AS [Category], 'Direct_Catalog_Updates' AS [Information], [name] AS [Database_Name], MAX(updSysCatalog) AS Last_Direct_Catalog_Update
		FROM master.sys.databases (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON name = tmpdbi.dbname
		WHERE database_id <> 2 AND is_read_only = 0 AND [state] = 0
		GROUP BY [name]
		HAVING (MAX(updSysCatalog) > '1900-01-01 00:00:00.000')
		ORDER BY [name]
	END
	ELSE
	BEGIN
		SELECT 'Instance_checks' AS [Category], 'Direct_Catalog_Updates' AS [Check], '[OK]' AS [Deviation]
	END;
	
	-- http://support.microsoft.com/kb/923247/en-us
	-- http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run
	IF @purity = 1
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Databases_need_data_purity_check' AS [Check], '[WARNING: Databases were found that need to run data purity checks.]' AS [Deviation]
		SELECT DISTINCT 'Maintenance_Monitoring_checks' AS [Category], 'Databases_need_data_purity_check' AS [Information], [name] AS [Database_Name], dbi_dbccFlags AS Needs_Data_Purity_Checks
		FROM master.sys.databases (NOLOCK) LEFT JOIN #dbinfo tmpdbi ON name = tmpdbi.dbname
		WHERE database_id > 4 AND dbi_createVersion <= 611 AND dbi_dbccFlags = 0 AND is_read_only = 0 AND [state] = 0
		ORDER BY [name]
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Databases_need_data_purity_check' AS [Check], '[OK]' AS [Deviation]
	END;
END
ELSE
BEGIN
	RAISERROR('[WARNING: Only a sysadmin can run the "DBCC CHECKDB, Direct Catalog Updates and Data Purity" checks. Bypassing check]', 16, 1, N'sysadmin')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- AlwaysOn/Mirroring automatic page repair subsection
-- Refer to "Automatic Page Repair" BOL entry for more information (https://docs.microsoft.com/sql/sql-server/failover-clusters/automatic-page-repair-availability-groups-database-mirroring) 
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 9
BEGIN
	RAISERROR (N'  |-Starting AlwaysOn/Mirroring automatic page repair', 10, 1) WITH NOWAIT
	
	IF @sqlmajorver > 10
	BEGIN
		DECLARE @HadrRep int--, @sqlcmd NVARCHAR(4000), @params NVARCHAR(500)
		SET @sqlcmd = N'SELECT @HadrRepOUT = COUNT(*) FROM sys.dm_hadr_auto_page_repair';
		SET @params = N'@HadrRepOUT int OUTPUT';
		EXECUTE sp_executesql @sqlcmd, @params, @HadrRepOUT=@HadrRep OUTPUT;
	END
	ELSE
	BEGIN
		SET @HadrRep = 0
	END;
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#pagerepair'))
	DROP TABLE #pagerepair;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#pagerepair'))
	CREATE TABLE #pagerepair (rowid int IDENTITY(1,1) PRIMARY KEY CLUSTERED, dbname NVARCHAR(255), [file_id] int NULL, [page_id] bigint NULL, error_type smallint NULL, page_status tinyint NULL, lst_modification_time DATETIME NULL, Repair_Source VARCHAR(20) NULL) 

	IF (SELECT COUNT(*) FROM sys.dm_db_mirroring_auto_page_repair (NOLOCK)) > 0
	BEGIN
		INSERT INTO #pagerepair
		SELECT DB_NAME(database_id) AS [Database_Name], [file_id], [page_id], [error_type], page_status, MAX(modification_time), 'Mirroring' AS [Repair_Source]
		FROM sys.dm_db_mirroring_auto_page_repair (NOLOCK)
		GROUP BY database_id, [file_id], [page_id], [error_type], page_status
	END
	
	IF @HadrRep > 0
	BEGIN
		INSERT INTO #pagerepair
		EXEC ('SELECT DB_NAME(database_id) AS [Database_Name], [file_id], [page_id], [error_type], page_status, MAX(modification_time), ''HADR'' AS [Repair_Source] FROM sys.dm_hadr_auto_page_repair GROUP BY database_id, [file_id], [page_id], [error_type], page_status ORDER BY DB_NAME(database_id), MAX(modification_time) DESC, [file_id], [page_id]')
	END;
	
	IF (SELECT COUNT(*) FROM sys.dm_db_mirroring_auto_page_repair (NOLOCK)) > 0
		OR @HadrRep > 0
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Auto_Page_repairs' AS [Check], '[WARNING: Page repairs have been found. Check for suspect pages]' AS [Deviation]
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Auto_Page_repairs' AS [Information], dbname AS [Database_Name],
			[file_id] AS [File_ID],
			[page_id] AS [Page_ID],
			CASE [error_type]
				WHEN -1 THEN 'Error 823'
				WHEN 1 THEN 'Unspecified Error 824'
				WHEN 2 THEN 'Bad Checksum'
				WHEN 3 THEN 'Torn Page'
				ELSE NULL
			END AS [Error_Type],
			CASE page_status 
				WHEN 2 THEN 'Queued for request from partner'
				WHEN 3 THEN 'Request sent to partner'
				WHEN 4 THEN 'Queued for automatic page repair' 
				WHEN 5 THEN 'Automatic page repair succeeded'
				WHEN 6 THEN 'Irreparable'
			END AS [Page_Status],
			lst_modification_time AS [Last_Modification_Time], [Repair_Source]
		FROM #pagerepair
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Auto_Page_repairs' AS [Check], '[None]' AS [Deviation], '' AS [Source] 
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Suspect pages subsection
-- Refer to "Manage the suspect_pages Table" BOL entry for more information (https://docs.microsoft.com/sql/relational-databases/backup-restore/manage-the-suspect-pages-table-sql-server)
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Suspect pages', 10, 1) WITH NOWAIT
IF (SELECT COUNT(*) FROM msdb.dbo.suspect_pages WHERE (event_type = 1 OR event_type = 2 OR event_type = 3)) > 0
BEGIN
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Suspect_Pages' AS [Check], '[WARNING: Suspect pages have been found. Run DBCC CHECKDB to verify affected databases]' AS [Deviation]
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Suspect_Pages' AS [Information], DB_NAME(database_id) AS [Database_Name],
		[file_id] AS [File_ID],
		[page_id] AS [Page_ID],
		CASE event_type
			WHEN 1 THEN 'Error 823 or unspecified Error 824'
			WHEN 2 THEN 'Bad Checksum'
			WHEN 3 THEN 'Torn Page'
			ELSE NULL
		END AS [Event_Type],
		error_count AS [Error_Count],
		last_update_date AS [Last_Update_Date]
	FROM msdb.dbo.suspect_pages (NOLOCK)
	WHERE (event_type = 1 OR event_type = 2 OR event_type = 3) 
	ORDER BY DB_NAME(database_id), last_update_date DESC, [file_id], [page_id]
END
ELSE
BEGIN
	SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Suspect_Pages' AS [Check], '[None]' AS [Deviation]
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Replication Errors subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @replication = 1 AND (SELECT COUNT(*) FROM master.sys.databases (NOLOCK) WHERE [name] = 'distribution') > 0
BEGIN
	RAISERROR (N'  |-Starting Replication Errors', 10, 1) WITH NOWAIT
	IF (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history AS msh 
		INNER JOIN distribution.dbo.MSrepl_errors AS mse ON mse.id = msh.error_id 
		INNER JOIN distribution.dbo.MSdistribution_agents AS msa ON msh.agent_id = msa.id
		WHERE mse.time >= DATEADD(hh, - 24, GETDATE())) > 0
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Repl_Errors_Lst_24H' AS [Check], '[WARNING: Replication Errors have been found in the last 24 hours]' AS [Deviation]
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Repl_Errors_Lst_24H' AS [Information], 
			msa.[name] AS [Distribution_Agent], msa.publisher_db AS [Publisher_DB], 
			msa.publication AS [Publication], msa.subscriber_db AS [Subscriber_DB], mse.error_code
		FROM distribution.dbo.MSdistribution_history AS msh 
		INNER JOIN distribution.dbo.MSrepl_errors AS mse ON mse.id = msh.error_id 
		INNER JOIN distribution.dbo.MSdistribution_agents AS msa ON msh.agent_id = msa.id
		WHERE mse.time >= DATEADD(hh, - 24, GETDATE())
		GROUP BY msa.[name], msa.publisher_db, msa.publication, msa.subscriber_db, mse.error_code

		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Repl_Errors_Details' AS [Information], msh.time,
			msa.[name] AS [Distribution_Agent], msa.publisher_db AS [Publisher_DB], 
			msa.publication AS [Publication], msa.subscriber_db AS [Subscriber_DB],
			mse.error_code, mse.error_text
		FROM distribution.dbo.MSdistribution_history AS msh (NOLOCK)
		INNER JOIN distribution.dbo.MSrepl_errors AS mse (NOLOCK) ON mse.id = msh.error_id AND mse.time = msh.time 
		INNER JOIN distribution.dbo.MSdistribution_agents AS msa (NOLOCK) ON msh.agent_id = msa.id
		WHERE (mse.time >= DATEADD(hh, - 24, GETDATE()))
		ORDER BY msh.time
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Repl_Errors_Lst_24H' AS [Check], '[None]' AS [Deviation]
	END
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Errorlog based checks subsection
-- Because it is a string based search, add other search conditions as deemed fit.
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'  |-Starting Errorlog based checks', 10, 1) WITH NOWAIT
--DECLARE @lognumber int, @logcount int
DECLARE @langid smallint
SELECT @langid = lcid FROM sys.syslanguages WHERE name = @@LANGUAGE

IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) = 1 -- Is sysadmin
	OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin'), 0) = 1 -- Is securityadmin
	OR ((SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'sp_readerrorlog') > 0
		AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_readerrorlog') > 0
		AND (SELECT COUNT([name]) FROM @permstbl WHERE [name] = 'xp_enumerrorlogs') > 0)
BEGIN
	SET @lognumber = 0 

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbcc'))
	DROP TABLE #dbcc;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbcc'))
	CREATE TABLE #dbcc (rowid int IDENTITY(1,1) PRIMARY KEY, logid int NULL, logdate DATETIME, spid VARCHAR(50), logmsg VARCHAR(4000)) 
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbcc'))
	CREATE INDEX [dbcc_logmsg] ON dbo.[#dbcc](logid) 

	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#avail_logs'))
	DROP TABLE #avail_logs;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#avail_logs'))
	CREATE TABLE #avail_logs (lognum int, logdate DATETIME, logsize int) 

	-- Get the number of available logs 
	INSERT INTO #avail_logs 
	EXEC xp_enumerrorlogs 

	SELECT @logcount = MAX(lognum) FROM #avail_logs 

	WHILE @lognumber < @logcount 
	BEGIN
		-- Cycle thru sql error logs
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''15 seconds'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 1. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''deadlock'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 2. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''stack dump'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 3. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''Error:'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 4. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''A significant part of sql server process memory has been paged out'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 5. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		SELECT @sqlcmd = 'EXEC master..sp_readerrorlog ' + CONVERT(VARCHAR(3),@lognumber) + ', 1, ''cachestore flush'''
		BEGIN TRY
			INSERT INTO #dbcc (logdate, spid, logmsg) 
			EXECUTE (@sqlcmd);
			UPDATE #dbcc SET logid = @lognumber WHERE logid IS NULL;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
			SELECT @ErrorMessage = 'Errorlog based subsection - Error raised in TRY block 6. ' + ERROR_MESSAGE()
			RAISERROR (@ErrorMessage, 16, 1);
		END CATCH
		-- Next log 
		--SET @lognumber = @lognumber + 1 
		SELECT @lognumber = MIN(lognum) FROM #avail_logs WHERE lognum > @lognumber
	END 

	IF (SELECT COUNT([rowid]) FROM #dbcc) > 0
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Errorlog' AS [Check], '[WARNING: Errorlog contains important messages.]' AS [Deviation];

		;WITH cte_dbcc (err, errcnt, logdate, logmsg) 
			AS (SELECT CASE WHEN logmsg LIKE 'Error: [^a-z]%' THEN RIGHT(LEFT(#dbcc.logmsg, CHARINDEX(',', #dbcc.logmsg)-1), CHARINDEX(',', #dbcc.logmsg)-8) 
					WHEN logmsg LIKE 'SQL Server has encountered % longer than 15 seconds %' THEN CONVERT(CHAR(3),833)
					WHEN logmsg LIKE 'A significant part of sql server process memory has been paged out%' THEN CONVERT(CHAR(5),17890)
					ELSE NULL END AS err,
				COUNT(logmsg) AS errcnt, 
				logdate,
				CASE WHEN logmsg LIKE 'SQL Server has encountered % longer than 15 seconds %' THEN 'SQL Server has encountered XXX occurrence(s) of IO requests taking longer than 15 seconds to complete on file YYY'
					WHEN logmsg LIKE 'A significant part of sql server process memory has been paged out%' THEN 'A significant part of sql server process memory has been paged out.'
					ELSE logmsg END AS logmsg
				FROM #dbcc
				GROUP BY logmsg, logdate
				)	
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Errorlog_Summary' AS [Information], 
			err AS [Error_Number],
			SUM(errcnt) AS Error_Count, 
			MIN(logdate) AS [First_Logged_Date], 
			MAX(logdate) AS [Last_Logged_Date],
			logmsg AS [Logged_Message],
			CASE WHEN logmsg LIKE 'Error: 825%' THEN 'IO transient failure. Possible corruption'
				WHEN logmsg LIKE 'Error: 833%' OR logmsg LIKE 'SQL Server has encountered % longer than 15 seconds %' THEN 'Long IO detected: http://support.microsoft.com/kb/897284'
				WHEN logmsg LIKE 'Error: 855%' OR logmsg LIKE 'Error: 856%' THEN 'Hardware memory corruption'
				WHEN logmsg LIKE 'Error: 3452%' THEN 'Metadata inconsistency in DB. Run DBCC CHECKIDENT'
				WHEN logmsg LIKE 'Error: 3619%' THEN 'Chkpoint failed. No Log space available'
				WHEN logmsg LIKE 'Error: 9002%' THEN 'No Log space available'
				WHEN logmsg LIKE 'Error: 17204%' OR logmsg LIKE 'Error: 17207%' THEN 'Error opening file during startup process'
				WHEN logmsg LIKE 'Error: 17179%' THEN 'No AWE - LPIM related'
				WHEN logmsg LIKE 'Error: 17890%' THEN 'sqlservr process paged out'
				WHEN logmsg LIKE 'Error: 2508%' THEN 'Catalog views inaccuracies in DB. Run DBCC UPDATEUSAGE'
				WHEN logmsg LIKE 'Error: 2511%' THEN 'Index Keys errors'
				WHEN logmsg LIKE 'Error: 3271%' THEN 'IO nonrecoverable error'
				WHEN logmsg LIKE 'Error: 5228%' OR logmsg LIKE 'Error: 5229%' THEN 'Online Index operation errors'
				WHEN logmsg LIKE 'Error: 5242%' THEN 'Page structural inconsistency'
				WHEN logmsg LIKE 'Error: 5243%' THEN 'In-memory structural inconsistency'
				WHEN logmsg LIKE 'Error: 5250%' THEN 'Corrupt page. Error cannot be fixed'
				WHEN logmsg LIKE 'Error: 5901%' THEN 'Chkpoint failed. Possible corruption'
				WHEN logmsg LIKE 'Error: 17130%' THEN 'No lock memory'
				WHEN logmsg LIKE 'Error: 17300%' THEN 'Unable to run new system task'
				WHEN logmsg LIKE 'Error: 802%' THEN 'No BP memory'
				WHEN logmsg LIKE 'Error: 845%' OR logmsg LIKE 'Error: 1105%' OR logmsg LIKE 'Error: 1121%' THEN 'No disk space available'
				WHEN logmsg LIKE 'Error: 1214%' THEN 'Internal parallelism error'
				WHEN logmsg LIKE 'Error: 823%' OR logmsg LIKE 'Error: 824%' THEN 'IO failure. Possible corruption'
				WHEN logmsg LIKE 'Error: 832%' THEN 'Page checksum error. Possible corruption'
				WHEN logmsg LIKE 'Error: 3624%' OR logmsg LIKE 'Error: 17065%' OR logmsg LIKE 'Error: 17066%' OR logmsg LIKE 'Error: 17067%' THEN 'System assertion check failed. Possible corruption'
				WHEN logmsg LIKE 'Error: 5572%' THEN 'Possible FILESTREAM corruption'
				WHEN logmsg LIKE 'Error: 9100%' THEN 'Possible index corruption'
				-- How To Diagnose and Correct Errors 17883, 17884, 17887, and 17888 (http://technet.microsoft.com/library/cc917684.aspx)
				WHEN logmsg LIKE 'Error: 17883%' THEN 'Non-yielding scheduler: http://technet.microsoft.com/library/cc917684.aspx'
				WHEN logmsg LIKE 'Error: 17884%' OR logmsg LIKE 'Error: 17888%' THEN 'Deadlocked scheduler: http://technet.microsoft.com/library/cc917684.aspx'
				WHEN logmsg LIKE 'Error: 17887%' THEN 'IO completion error: http://technet.microsoft.com/library/cc917684.aspx'
				WHEN logmsg LIKE 'Error: 1205%' THEN 'Deadlocked transaction'
				WHEN logmsg LIKE 'Error: 610%' THEN 'Page header invalid. Possible corruption'
				WHEN logmsg LIKE 'Error: 8621%' THEN 'QP stack overflow during optimization. Please simplify the query'
				WHEN logmsg LIKE 'Error: 8642%' THEN 'QP insufficient threads for parallelism'
				WHEN logmsg LIKE 'Error: 701%' THEN 'Insufficient memory'
				-- How to troubleshoot SQL Server error 8645 (http://support.microsoft.com/kb/309256)
				WHEN logmsg LIKE 'Error: 8645%' THEN 'Insufficient memory: http://support.microsoft.com/kb/309256'
				WHEN logmsg LIKE 'Error: 605%' THEN 'Page retrieval failed. Possible corruption'
				-- How to troubleshoot Msg 5180 (http://support.microsoft.com/kb/2015747)
				WHEN logmsg LIKE 'Error: 5180%' THEN 'Invalid file ID. Possible corruption: http://support.microsoft.com/kb/2015747'
				WHEN logmsg LIKE 'Error: 8966%' THEN 'Unable to read and latch on a PFS or GAM page'
				WHEN logmsg LIKE 'Error: 9001%' OR logmsg LIKE 'Error: 9002%' THEN 'Transaction log errors.'
				WHEN logmsg LIKE 'Error: 9003%' OR logmsg LIKE 'Error: 9004%' OR logmsg LIKE 'Error: 9015%' THEN 'Transaction log errors. Possible corruption'
				-- How to reduce paging of buffer pool memory in the 64-bit version of SQL Server (http://support.microsoft.com/kb/918483)
				WHEN logmsg LIKE 'A significant part of sql server process memory has been paged out%' THEN 'SQL Server process was trimmed by the OS. Preventable if LPIM is granted'
				WHEN logmsg LIKE '%cachestore flush%' THEN 'CacheStore flush'
			ELSE '' END AS [Comment],
			CASE WHEN logmsg LIKE 'Error: [^a-z]%' THEN (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') 
					FROM sys.messages WHERE message_id = (CONVERT(int, RIGHT(LEFT(cte_dbcc.logmsg, CHARINDEX(',', cte_dbcc.logmsg)-1), CHARINDEX(',', cte_dbcc.logmsg)-8))) AND language_id = @langid) 
				ELSE '' END AS [Look_for_Message_example]
		FROM cte_dbcc
		GROUP BY err, logmsg
		ORDER BY SUM(errcnt) DESC;
	
		IF @logdetail = 1
		BEGIN
			SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Errorlog_Detail' AS [Information], logid AS [Errorlog_Id], logdate AS [Logged_Date], spid AS [Process], logmsg AS [Logged_Message], 
				CASE WHEN logmsg LIKE 'Error: 825%' THEN 'IO transient failure. Possible corruption'
					WHEN logmsg LIKE 'Error: 833%' OR logmsg LIKE 'SQL Server has encountered % longer than 15 seconds %' THEN 'Long IO detected'
					WHEN logmsg LIKE 'Error: 855%' OR logmsg LIKE 'Error: 856%' THEN 'Hardware memory corruption'
					WHEN logmsg LIKE 'Error: 3452%' THEN 'Metadata inconsistency in DB. Run DBCC CHECKIDENT'
					WHEN logmsg LIKE 'Error: 3619%' THEN 'Chkpoint failed. No Log space available'
					WHEN logmsg LIKE 'Error: 9002%' THEN 'No Log space available'
					WHEN logmsg LIKE 'Error: 17179%' THEN 'No AWE - LPIM related'
					WHEN logmsg LIKE 'Error: 17890%' THEN 'sqlservr process paged out'
					WHEN logmsg LIKE 'Error: 17204%' OR logmsg LIKE 'Error: 17207%' THEN 'Error opening file during startup process'
					WHEN logmsg LIKE 'Error: 2508%' THEN 'Catalog views inaccuracies in DB. Run DBCC UPDATEUSAGE'
					WHEN logmsg LIKE 'Error: 2511%' THEN 'Index Keys errors'
					WHEN logmsg LIKE 'Error: 3271%' THEN 'IO nonrecoverable error'
					WHEN logmsg LIKE 'Error: 5228%' OR logmsg LIKE 'Error: 5229%' THEN 'Online Index operation errors'
					WHEN logmsg LIKE 'Error: 5242%' THEN 'Page structural inconsistency'
					WHEN logmsg LIKE 'Error: 5243%' THEN 'In-memory structural inconsistency'
					WHEN logmsg LIKE 'Error: 5250%' THEN 'Corrupt page. Error cannot be fixed'
					WHEN logmsg LIKE 'Error: 5901%' THEN 'Chkpoint failed. Possible corruption'
					WHEN logmsg LIKE 'Error: 17130%' THEN 'No lock memory'
					WHEN logmsg LIKE 'Error: 17300%' THEN 'Unable to run new system task'
					WHEN logmsg LIKE 'Error: 802%' THEN 'No BP memory'
					WHEN logmsg LIKE 'Error: 845%' OR logmsg LIKE 'Error: 1105%' OR logmsg LIKE 'Error: 1121%' THEN 'No disk space available'
					WHEN logmsg LIKE 'Error: 1214%' THEN 'Internal parallelism error'
					WHEN logmsg LIKE 'Error: 823%' OR logmsg LIKE 'Error: 824%' THEN 'IO failure. Possible corruption'
					WHEN logmsg LIKE 'Error: 832%' THEN 'Page checksum error. Possible corruption'
					WHEN logmsg LIKE 'Error: 3624%' OR logmsg LIKE 'Error: 17065%' OR logmsg LIKE 'Error: 17066%' OR logmsg LIKE 'Error: 17067%' THEN 'System assertion check failed. Possible corruption'
					WHEN logmsg LIKE 'Error: 5572%' THEN 'Possible FILESTREAM corruption'
					WHEN logmsg LIKE 'Error: 9100%' THEN 'Possible index corruption'
					-- How To Diagnose and Correct Errors 17883, 17884, 17887, and 17888 (http://technet.microsoft.com/library/cc917684.aspx)
					WHEN logmsg LIKE 'Error: 17883%' THEN 'Non-yielding scheduler'
					WHEN logmsg LIKE 'Error: 17884%' OR logmsg LIKE 'Error: 17888%' THEN 'Deadlocked scheduler'
					WHEN logmsg LIKE 'Error: 17887%' THEN 'IO completion error'
					WHEN logmsg LIKE 'Error: 1205%' THEN 'Deadlocked transaction'
					WHEN logmsg LIKE 'Error: 610%' THEN 'Page header invalid. Possible corruption'
					WHEN logmsg LIKE 'Error: 8621%' THEN 'QP stack overflow during optimization. Please simplify the query'
					WHEN logmsg LIKE 'Error: 8642%' THEN 'QP insufficient threads for parallelism'
					WHEN logmsg LIKE 'Error: 701%' THEN 'Insufficient memory'
					-- How to troubleshoot SQL Server error 8645 (http://support.microsoft.com/kb/309256)
					WHEN logmsg LIKE 'Error: 8645%' THEN 'Insufficient memory'
					WHEN logmsg LIKE 'Error: 605%' THEN 'Page retrieval failed. Possible corruption'
					-- How to troubleshoot Msg 5180 (http://support.microsoft.com/kb/2015747)
					WHEN logmsg LIKE 'Error: 5180%' THEN 'Invalid file ID. Possible corruption'
					WHEN logmsg LIKE 'Error: 8966%' THEN 'Unable to read and latch on a PFS or GAM page'
					WHEN logmsg LIKE 'Error: 9001%' OR logmsg LIKE 'Error: 9002%' THEN 'Transaction log errors.'
					WHEN logmsg LIKE 'Error: 9003%' OR logmsg LIKE 'Error: 9004%' OR logmsg LIKE 'Error: 9015%' THEN 'Transaction log errors. Possible corruption'
					-- How to reduce paging of buffer pool memory in the 64-bit version of SQL Server (http://support.microsoft.com/kb/918483)
					WHEN logmsg LIKE 'A significant part of sql server process memory has been paged out%' THEN 'SQL Server process was trimmed by the OS. Preventable if LPIM is granted'
					WHEN logmsg LIKE '%cachestore flush%' THEN 'CacheStore flush'
				ELSE '' END AS [Comment]
			FROM #dbcc
			ORDER BY logdate DESC
		END
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'Errorlog' AS [Check], '[OK]' AS [Deviation]
	END;
END
ELSE
BEGIN
	RAISERROR('[WARNING: Only a sysadmin or securityadmin can run the "Errorlog" check. Bypassing check]', 16, 1, N'permissions')
	RAISERROR('[WARNING: If not sysadmin or securityadmin, then user must be a granted EXECUTE permissions on the following sprocs to run checks: xp_enumerrorlogs and sp_readerrorlog. Bypassing check]', 16, 1, N'extended_sprocs')
	--RETURN
END;

--------------------------------------------------------------------------------------------------------------------------------
-- System health error checks subsection
--------------------------------------------------------------------------------------------------------------------------------
IF @sqlmajorver > 10
BEGIN
	RAISERROR (N'  |-Starting System health checks', 10, 1) WITH NOWAIT
	
	IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#SystemHealthSessionData'))
	DROP TABLE #SystemHealthSessionData;
	IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#SystemHealthSessionData'))
	CREATE TABLE #SystemHealthSessionData (target_data XML)
		
	-- Store the XML data in a temporary table
	INSERT INTO #SystemHealthSessionData
	SELECT CAST(xet.target_data AS XML)
	FROM sys.dm_xe_session_targets xet
	INNER JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
	WHERE xe.name = 'system_health'
	
	IF (SELECT COUNT(*) FROM #SystemHealthSessionData a WHERE CONVERT(VARCHAR(max), target_data) LIKE '%error_reported%') > 0
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'SystemHealth_Errors' AS [Check], '[WARNING: System Health Session contains important messages.]' AS [Deviation];

		-- Get statistical information about all the errors reported
		;WITH cteHealthSession (EventXML) AS (SELECT C.query('.') EventXML
			FROM #SystemHealthSessionData a
			CROSS APPLY a.target_data.nodes('/RingBufferTarget/event') AS T(C)
		),
		cteErrorReported (EventTime, ErrorNumber) AS (SELECT EventXML.value('(/event/@timestamp)[1]', 'datetime') AS EventTime,
			EventXML.value('(/event/data[@name="error_number"]/value)[1]', 'int') AS ErrorNumber
			FROM cteHealthSession
			WHERE EventXML.value('(/event/@name)[1]', 'VARCHAR(500)') = 'error_reported'
		)
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'SystemHealth_Errors_Summary' AS [Information],
			ErrorNumber AS [Error_Number],
			MIN(EventTime) AS [First_Logged_Date],
			MAX(EventTime) AS [Last_Logged_Date],
			COUNT(ErrorNumber) AS Error_Count,
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(b.text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') AS [Look_for_Message_example] 
		FROM cteErrorReported a
		INNER JOIN sys.messages b ON a.ErrorNumber = b.message_id
		WHERE b.language_id = @langid
		GROUP BY a.ErrorNumber, b.[text]
				
		-- Get detailed information about all the errors reported
		;WITH cteHealthSession AS (SELECT C.query('.').value('(/event/@timestamp)[1]', 'datetime') AS EventTime,
			C.query('.').value('(/event/data[@name="error_number"]/value)[1]', 'int') AS ErrorNumber,
			C.query('.').value('(/event/data[@name="severity"]/value)[1]', 'int') AS ErrorSeverity,
			C.query('.').value('(/event/data[@name="state"]/value)[1]', 'int') AS ErrorState,
			C.query('.').value('(/event/data[@name="message"]/value)[1]', 'VARCHAR(MAX)') AS ErrorText,
			C.query('.').value('(/event/action[@name="session_id"]/value)[1]', 'int') AS SessionID,
			C.query('.').value('(/event/data[@name="category"]/text)[1]', 'VARCHAR(10)') AS ErrorCategory
			FROM #SystemHealthSessionData a
			CROSS APPLY a.target_data.nodes('/RingBufferTarget/event') AS T(C)
			WHERE C.query('.').value('(/event/@name)[1]', 'VARCHAR(500)') = 'error_reported')
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'SystemHealth_Errors_Detail' AS [Information], 
			EventTime AS [Logged_Date],
			ErrorNumber AS [Error_Number],
			ErrorSeverity AS [Error_Sev],
			ErrorState AS [Error_State],
			ErrorText AS [Logged_Message],
			SessionID
		FROM cteHealthSession
		ORDER BY EventTime
	END
	ELSE
	BEGIN
		SELECT 'Maintenance_Monitoring_checks' AS [Category], 'SystemHealth_Errors' AS [Check], '[OK]' AS [Deviation]
	END;
END;

--------------------------------------------------------------------------------------------------------------------------------
-- Clean up temp objects 
--------------------------------------------------------------------------------------------------------------------------------
RAISERROR (N'Clearing up temporary objects', 10, 1) WITH NOWAIT

IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbinfo')) 
DROP TABLE #dbinfo;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#output_dbinfo')) 
DROP TABLE #output_dbinfo;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIOStall')) 
DROP TABLE #tblIOStall;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs1')) 
DROP TABLE #tmpdbs1;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs0')) 
DROP TABLE #tmpdbs0;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerfCount')) 
DROP TABLE #tblPerfCount;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.tblPerfThresholds'))
DROP TABLE tempdb.dbo.tblPerfThresholds;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHypObj')) 
DROP TABLE #tblHypObj;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs1')) 
DROP TABLE #tblIxs1;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs2')) 
DROP TABLE #tblIxs2;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs3')) 
DROP TABLE #tblIxs3;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs4')) 
DROP TABLE #tblIxs4;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs5')) 
DROP TABLE #tblIxs5;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblIxs6')) 
DROP TABLE #tblIxs6;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFK')) 
DROP TABLE #tblFK;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dbcc')) 
DROP TABLE #dbcc;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#avail_logs')) 
DROP TABLE #avail_logs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info1')) 
DROP TABLE #log_info1;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#log_info2')) 
DROP TABLE #log_info2;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpobjectnames'))
DROP TABLE #tmpobjectnames;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpfinalobjectnames'))
DROP TABLE #tmpfinalobjectnames;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWaits'))
DROP TABLE #tblWaits;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalWaits'))
DROP TABLE #tblFinalWaits;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblLatches'))
DROP TABLE #tblLatches;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalLatches'))
DROP TABLE #tblFinalLatches;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexCreation'))
DROP TABLE #IndexCreation;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#IndexRedundant'))
DROP TABLE #IndexRedundant;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblBlkChains'))
DROP TABLE #tblBlkChains;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsSamp'))
DROP TABLE #tblStatsSamp;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksBefore'))
DROP TABLE #tblSpinlocksBefore;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblSpinlocksAfter'))
DROP TABLE #tblSpinlocksAfter;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblFinalSpinlocks'))
DROP TABLE #tblFinalSpinlocks;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#pagerepair'))
DROP TABLE #pagerepair;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_io_virtual_file_stats'))
DROP TABLE #tmp_dm_io_virtual_file_stats;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_exec_query_stats')) 
DROP TABLE #tmp_dm_exec_query_stats;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#dm_exec_query_stats')) 
DROP TABLE #dm_exec_query_stats;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIOReq'))
DROP TABLE #tblPendingIOReq;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPendingIO'))
DROP TABLE #tblPendingIO;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#qpwarnings')) 
DROP TABLE #qpwarnings;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblStatsUpd'))
DROP TABLE #tblStatsUpd;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblPerSku'))
DROP TABLE #tblPerSku;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblColStoreIXs'))
DROP TABLE #tblColStoreIXs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#SystemHealthSessionData'))
DROP TABLE #SystemHealthSessionData;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbfiledetail'))
DROP TABLE #tmpdbfiledetail;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblHints'))
DROP TABLE #tblHints;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTriggers'))
DROP TABLE #tblTriggers;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS'))
DROP TABLE #tmpIPS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblCode'))
DROP TABLE #tblCode;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblWorking'))
DROP TABLE #tblWorking;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpdbs_userchoice'))
DROP TABLE #tmpdbs_userchoice;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluNodesOutput'))
DROP TABLE #xp_cmdshell_CluNodesOutput;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_CluOutput'))
DROP TABLE #xp_cmdshell_CluOutput;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_Nodes'))
DROP TABLE #xp_cmdshell_Nodes;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEOutput'))
DROP TABLE #xp_cmdshell_QFEOutput;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_QFEFinal'))
DROP TABLE #xp_cmdshell_QFEFinal;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#RegResult'))
DROP TABLE #RegResult;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#ServiceStatus'))
DROP TABLE #ServiceStatus;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_AcctSPNoutput'))
DROP TABLE #xp_cmdshell_AcctSPNoutput;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#xp_cmdshell_DupSPNoutput'))
DROP TABLE #xp_cmdshell_DupSPNoutput;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#FinalDupSPN'))
DROP TABLE #FinalDupSPN;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#ScopedDupSPN'))
DROP TABLE #ScopedDupSPN;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDRI'))
DROP TABLE #tblDRI;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblInMemDBs'))
DROP TABLE #tblInMemDBs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXIS'))
DROP TABLE #tmpXIS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpXNCIS'))
DROP TABLE #tmpXNCIS;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmpIPS_CI'))
DROP TABLE #tmpIPS_CI;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tmp_dm_io_virtual_file_stats'))
DROP TABLE #tmp_dm_io_virtual_file_stats;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tmpdbsizes'))
DROP TABLE ##tmpdbsizes;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecated'))
DROP TABLE #tblDeprecated;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblDeprecatedJobs'))
DROP TABLE #tblDeprecatedJobs;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.##tblKeywords'))
DROP TABLE ##tblKeywords;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblQStoreInfo'))
DROP TABLE #tblQStoreInfo;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblAutoTuningInfo'))
DROP TABLE #tblAutoTuningInfo;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendationsCnt'))
DROP TABLE #tblTuningRecommendationsCnt;
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#tblTuningRecommendations'))
DROP TABLE #tblTuningRecommendations;
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_perfctr'')) DROP FUNCTION dbo.fn_perfctr')
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_allcols'')) DROP FUNCTION dbo.fn_createindex_allcols')
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_keycols'')) DROP FUNCTION dbo.fn_createindex_keycols')
EXEC ('USE tempdb; IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(''tempdb.dbo.fn_createindex_includecols'')) DROP FUNCTION dbo.fn_createindex_includecols')
RAISERROR (N'All done!', 10, 1) WITH NOWAIT
END
GO
