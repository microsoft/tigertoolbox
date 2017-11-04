USE [master];
GO

IF (DB_ID(N'PowerConsumption') IS NOT NULL) 
BEGIN
    ALTER DATABASE [PowerConsumption]
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PowerConsumption];
END

GO
PRINT N'Creating PowerConsumption...'
GO
CREATE DATABASE [PowerConsumption]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'PowerConsumption', FILENAME = N'/var/opt/mssql/data/PowerConsumption.mdf' , SIZE = 204800KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'PowerConsumption_log', FILENAME = N'/var/opt/mssql/data/PowerConsumption_log.ldf' , SIZE = 80MB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO


IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET ANSI_NULLS OFF,
                ANSI_PADDING OFF,
                ANSI_WARNINGS OFF,
                ARITHABORT OFF,
                CONCAT_NULL_YIELDS_NULL OFF,
                NUMERIC_ROUNDABORT OFF,
                QUOTED_IDENTIFIER OFF,
                ANSI_NULL_DEFAULT OFF,
                CURSOR_DEFAULT GLOBAL,
                RECOVERY FULL,
                CURSOR_CLOSE_ON_COMMIT OFF,
                AUTO_CREATE_STATISTICS ON,
                AUTO_SHRINK OFF,
                AUTO_UPDATE_STATISTICS ON,
                RECURSIVE_TRIGGERS OFF 
            WITH ROLLBACK IMMEDIATE;
        ALTER DATABASE [PowerConsumption]
            SET AUTO_CLOSE OFF 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET ALLOW_SNAPSHOT_ISOLATION ON;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET READ_COMMITTED_SNAPSHOT OFF 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET AUTO_UPDATE_STATISTICS_ASYNC OFF,
                PAGE_VERIFY CHECKSUM,
                DATE_CORRELATION_OPTIMIZATION OFF,
                DISABLE_BROKER,
                PARAMETERIZATION SIMPLE,
                SUPPLEMENTAL_LOGGING OFF 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF IS_SRVROLEMEMBER(N'sysadmin') = 1
    BEGIN
        IF EXISTS (SELECT 1
                   FROM   [master].[dbo].[sysdatabases]
                   WHERE  [name] = N'PowerConsumption')
            BEGIN
                EXECUTE sp_executesql N'ALTER DATABASE [PowerConsumption]
    SET TRUSTWORTHY OFF,
        DB_CHAINING OFF 
    WITH ROLLBACK IMMEDIATE';
            END
    END
ELSE
    BEGIN
        PRINT N'The database settings cannot be modified. You must be a SysAdmin to apply these settings.';
    END


GO
IF IS_SRVROLEMEMBER(N'sysadmin') = 1
    BEGIN
        IF EXISTS (SELECT 1
                   FROM   [master].[dbo].[sysdatabases]
                   WHERE  [name] = N'PowerConsumption')
            BEGIN
                EXECUTE sp_executesql N'ALTER DATABASE [PowerConsumption]
    SET HONOR_BROKER_PRIORITY OFF 
    WITH ROLLBACK IMMEDIATE';
            END
    END
ELSE
    BEGIN
        PRINT N'The database settings cannot be modified. You must be a SysAdmin to apply these settings.';
    END


GO
ALTER DATABASE [PowerConsumption]
    SET TARGET_RECOVERY_TIME = 60 SECONDS 
    WITH ROLLBACK IMMEDIATE;


GO

IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET AUTO_CREATE_STATISTICS ON(INCREMENTAL = OFF),
                MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT = OFF,
                DELAYED_DURABILITY = DISABLED 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET QUERY_STORE (QUERY_CAPTURE_MODE = ALL, FLUSH_INTERVAL_SECONDS = 900, INTERVAL_LENGTH_MINUTES = 60, MAX_PLANS_PER_QUERY = 200, CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 367), MAX_STORAGE_SIZE_MB = 100) 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE [PowerConsumption]
            SET QUERY_STORE = OFF 
            WITH ROLLBACK IMMEDIATE;
    END


GO
IF EXISTS (SELECT 1
           FROM   [master].[dbo].[sysdatabases]
           WHERE  [name] = N'PowerConsumption')
    BEGIN
        ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
        ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET MAXDOP = PRIMARY;
        ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
        ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET LEGACY_CARDINALITY_ESTIMATION = PRIMARY;
        ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
        ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET PARAMETER_SNIFFING = PRIMARY;
        ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = OFF;
        ALTER DATABASE SCOPED CONFIGURATION FOR SECONDARY SET QUERY_OPTIMIZER_HOTFIXES = PRIMARY;
    END


GO
USE [PowerConsumption];


GO
IF fulltextserviceproperty(N'IsFulltextInstalled') = 1
    EXECUTE sp_fulltext_database 'enable';


GO
PRINT N'Creating [dbo].[udtMeterMeasurement]...';


GO
CREATE TYPE [dbo].[udtMeterMeasurement] AS TABLE (
    [RowID]            INT            NOT NULL,
    [MeterID]          INT            NOT NULL,
    [MeasurementInkWh] DECIMAL (9, 4) NOT NULL,
    [PostalCode]       NVARCHAR (10)  NOT NULL,
    [MeasurementDate]  DATETIME2 (7)  NOT NULL,
    INDEX [IX_RowID] NONCLUSTERED  ([RowID]) 
	)

GO
PRINT N'Creating [dbo].[MeterMeasurementHistory]...';


GO
CREATE TABLE [dbo].[MeterMeasurementHistory] (
    [MeterID]          INT            NOT NULL,
    [MeasurementInkWh] DECIMAL (9, 4) NOT NULL,
    [PostalCode]       NVARCHAR (10)  NOT NULL,
    [MeasurementDate]  DATETIME2 (7)  NOT NULL,
    [SysStartTime]     DATETIME2 (7)  NOT NULL,
    [SysEndTime]       DATETIME2 (7)  NOT NULL
);
GO
PRINT N'Creating [dbo].[MeterMeasurementHistory].[ix_MeterMeasurementHistory]...';


GO
CREATE CLUSTERED INDEX [ix_MeterMeasurementHistory]
    ON [dbo].[MeterMeasurementHistory]([MeterID]);

CREATE CLUSTERED COLUMNSTORE INDEX [ix_MeterMeasurementHistory]
    ON [dbo].[MeterMeasurementHistory] WITH (DROP_EXISTING = ON);


GO
PRINT N'Creating [dbo].[MeterMeasurement]...';


GO

CREATE TABLE [dbo].[MeterMeasurement] (
    [MeterID]          INT                                         NOT NULL,
    [MeasurementInkWh] DECIMAL (9, 4)                              NOT NULL,
    [PostalCode]       NVARCHAR (10)                               NOT NULL,
    [MeasurementDate]  DATETIME2 (7)                               NOT NULL,
    [SysStartTime]     DATETIME2 (7) GENERATED ALWAYS AS ROW START NOT NULL,
    [SysEndTime]       DATETIME2 (7) GENERATED ALWAYS AS ROW END   NOT NULL,
    PRIMARY KEY NONCLUSTERED ([MeterID] ASC),
    PERIOD FOR SYSTEM_TIME ([SysStartTime], [SysEndTime])
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE=[dbo].[MeterMeasurementHistory], DATA_CONSISTENCY_CHECK=ON));


GO
PRINT N'Creating [dbo].[vwMeterMeasurement]...';


GO
CREATE VIEW vwMeterMeasurement
AS
SELECT	PostalCode,
		DATETIMEFROMPARTS(
			YEAR(MeasurementDate), 
			MONTH(MeasurementDate), 
			DAY(MeasurementDate), 
			DATEPART(HOUR,MeasurementDate), 
			DATEPART(MINUTE,MeasurementDate), 
			DATEPART(ss,MeasurementDate)/1,
			0
		) AS MeasurementDate,
		count(*) AS MeterCount,
		AVG(MeasurementInkWh) AS AvgMeasurementInkWh
FROM	[dbo].[MeterMeasurement] FOR SYSTEM_TIME ALL WITH (NOLOCK)
GROUP BY
		PostalCode,
		DATETIMEFROMPARTS(
		YEAR(MeasurementDate), 
		MONTH(MeasurementDate), 
		DAY(MeasurementDate), 
		DATEPART(HOUR,MeasurementDate), 
		DATEPART(MINUTE,MeasurementDate), 
		DATEPART(ss,MeasurementDate)/1,0)
GO
PRINT N'Creating [dbo].[InsertMeterMeasurement]...';


GO


CREATE PROCEDURE [dbo].[InsertMeterMeasurement] 
	@Batch AS dbo.udtMeterMeasurement READONLY,
	@BatchSize INT
AS
BEGIN
SET TRANSACTION ISOLATION LEVEL SNAPSHOT
	DECLARE @i INT = 1
	DECLARE @MeterID INT
	DECLARE @MeasurementInkWh DECIMAL(9, 4)
	DECLARE @PostalCode NVARCHAR(10)
	DECLARE @MeasurementDate DATETIME2(7) 
	
	WHILE (@i <= @BatchSize)
	BEGIN	
	
		SELECT	@MeterID = MeterID,
				@MeasurementInkWh = MeasurementInkWh, 
				@MeasurementDate = MeasurementDate,
				@PostalCode = PostalCode
		FROM	@Batch
		WHERE	RowID = @i
		
		UPDATE	dbo.MeterMeasurement 
		SET		MeasurementInkWh += @MeasurementInkWh,
				MeasurementDate = @MeasurementDate,
				PostalCode = @PostalCode
		WHERE	MeterID = @MeterID							
		
		IF(@@ROWCOUNT = 0)
		BEGIN
			INSERT INTO dbo.MeterMeasurement (MeterID, MeasurementInkWh, PostalCode, MeasurementDate)
			VALUES (@MeterID, @MeasurementInkWh, @PostalCode, @MeasurementDate);			
		END 

		SET @i += 1
	END	
END
GO
DECLARE @VarDecimalSupported AS BIT;

SELECT @VarDecimalSupported = 0;

IF ((ServerProperty(N'EngineEdition') = 3)
    AND (((@@microsoftversion / power(2, 24) = 9)
          AND (@@microsoftversion & 0xffff >= 3024))
         OR ((@@microsoftversion / power(2, 24) = 10)
             AND (@@microsoftversion & 0xffff >= 1600))))
    SELECT @VarDecimalSupported = 1;

IF (@VarDecimalSupported > 0)
    BEGIN
        EXECUTE sp_db_vardecimal_storage_format N'PowerConsumption', 'ON';
    END


GO
PRINT N'Update complete.';

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[dm_db_log_stats_history](
	[Date] [datetime] NOT NULL,
	[Database] [nvarchar](128) NULL,
	[database_id] [int] NULL,
	[recovery_model] [nvarchar](60) NULL,
	[log_min_lsn] [nvarchar](24) NULL,
	[log_end_lsn] [nvarchar](24) NULL,
	[current_vlf_sequence_number] [bigint] NULL,
	[current_vlf_size_mb] [float] NULL,
	[total_vlf_count] [bigint] NULL,
	[total_log_size_mb] [float] NULL,
	[active_vlf_count] [bigint] NULL,
	[active_log_size_mb] [float] NULL,
	[log_truncation_holdup_reason] [nvarchar](60) NULL,
	[log_backup_time] [datetime] NULL,
	[log_backup_lsn] [nvarchar](24) NULL,
	[log_since_last_log_backup_mb] [float] NULL,
	[log_checkpoint_lsn] [nvarchar](24) NULL,
	[log_since_last_checkpoint_mb] [float] NULL,
	[log_recovery_lsn] [nvarchar](24) NULL,
	[log_recovery_size_mb] [float] NULL,
	[recovery_vlf_count] [bigint] NULL
) ON [PRIMARY]
GO

PRINT 'Table dm_db_log_stats_history created for monitoring'
GO


ALTER DATABASE PowerConsumption SET RECOVERY FULL
GO
PRINT N'Set Database Recovery model to full';

BACKUP DATABASE PowerConsumption TO disk = '/var/opt/mssql/data/powerconsumption.bak' WITH FORMAT,COMPRESSION
BACKUP LOG PowerConsumption TO disk = '/var/opt/mssql/data/powerconsumption.bak' WITH COMPRESSION
PRINT N'Full database completed';
GO

--deletes backupfile info
truncate table msdb.dbo.backupfile  
--deletes backupfilegroup info
truncate table msdb.dbo.backupfilegroup
--deletes restorefile info
truncate table msdb.dbo.restorefile 
--deletes restorefilegroup info
truncate table msdb.dbo.restorefilegroup
--deletes restorehistory info
delete from msdb.dbo.restorehistory 
--delete backupset info
delete from msdb.dbo.backupset
--deletes backupmedia info
delete from msdb.dbo.backupmediafamily 
--deletes backupmediaset info
delete from msdb.dbo.backupmediaset 


Print 'Backup Information deleted'

