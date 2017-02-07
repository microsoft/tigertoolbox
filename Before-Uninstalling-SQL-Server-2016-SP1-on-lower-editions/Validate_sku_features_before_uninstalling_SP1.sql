SET NOCOUNT ON
DECLARE @cnt int;
DECLARE @edition int; 
SELECT @edition= CONVERT(int,SERVERPROPERTY('EngineEdition'))
IF @edition <> 3
BEGIN
DROP TABLE IF EXISTS tempdb.dbo.tbl;
CREATE TABLE tempdb.dbo.tbl(db sysname, feature_name nvarchar(4000), features_in_use bit)
insert INTO tempdb.dbo.tbl select 'server','IsPolybaseInstalled',CAST(SERVERPROPERTY ('IsPolybaseInstalled') as int);
EXEC master.sys.sp_MSforeachdb 'USE [?];
			  DECLARE @features_in_use int;
			  SELECT @features_in_use=count(1) from sys.dm_db_persisted_sku_features;
			  IF (@features_in_use > 0)
			  INSERT INTO tempdb.dbo.tbl SELECT DB_name(),feature_name,1 from sys.dm_db_persisted_sku_features;
			  SELECT @features_in_use=count(1) from sys.column_master_keys;
			  IF (@features_in_use > 0)
			  INSERT INTO tempdb.dbo.tbl VALUES(DB_NAME(),''Always Encrypted'',1);
			  SELECT @features_in_use=count(1) from sys.security_policies;
			  IF @features_in_use > 0
			  INSERT INTO tempdb.dbo.tbl VALUES(DB_NAME(),''Row-level security'',1);
			  SELECT @features_in_use=count(1) from sys.masked_columns;
			  IF @features_in_use > 0
			  INSERT INTO tempdb.dbo.tbl VALUES(DB_NAME(),''Dynamic Data Masking'',1);
			  SELECT @features_in_use=count(1) from sys.database_audit_specifications;
			  IF @features_in_use > 0
			  INSERT INTO tempdb.dbo.tbl VALUES(DB_NAME(),''Database Auditing'',1);'
SELECT @cnt=count(1) FROM tempdb.dbo.tbl WHERE features_in_use=1
IF @cnt>0
BEGIN
SELECT * from tempdb.dbo.tbl where features_in_use = 1;
THROW 60000, 'The instance cannot be downgraded from SP1 as it contains atleast 1 database mentioned above with SKU features not available in SQL Server 2016 RTM. If downgrade is attempted, it can leave the database in suspect mode. DROP or DISABLE the feature and rerun the script to confirm before you downgrade',0
END
ELSE 
THROW 60000,'The instance can be downgraded as it doesnt contain any database leveraging new features enabled in SP1 on lower editions',0
DROP TABLE tempdb.dbo.tbl
END
ELSE
PRINT 'The instance can be downgraded as Enterprise Edition is not impacted in SP1'
