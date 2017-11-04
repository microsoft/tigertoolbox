
DECLARE @logsincelastbackup int
DECLARE @logbackupthreshold int = 50

WHILE(1=1)
BEGIN
SELECT @logsincelastbackup=log_since_last_log_backup_mb from sys.dm_db_log_stats(DB_ID('PowerConsumption'))
IF (@logsincelastbackup>@logbackupthreshold)
BACKUP LOG [PowerConsumption] to disk = '/var/opt/mssql/data/smartpowerconsumption.trn' WITH FORMAT,COMPRESSION
--ELSE 
--WAITFOR DELAY '00:01:00'
END