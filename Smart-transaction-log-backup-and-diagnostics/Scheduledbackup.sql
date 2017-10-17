SET NOCOUNT ON
WHILE(1=1)
BEGIN

BACKUP LOG [PowerConsumption] to disk = '/var/opt/mssql/data/powerconsumption.trn' WITH FORMAT,COMPRESSION
WAITFOR DELAY '00:01:00'
END

