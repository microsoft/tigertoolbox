-- https://learn.microsoft.com/en-us/previous-versions/sql/sql-server-2008/dd894051(v=sql.100)?redirectedfrom=MSDN
SET NOCOUNT ON;

DECLARE
	@uptime varchar(12)
  , @startdate datetime
  , @sqlmajorver int
  , @sqlcmd nvarchar(500)
  , @params nvarchar(500);
SELECT @sqlmajorver = CONVERT (int, (@@microsoftversion / 0x1000000) & 0xff);

IF @sqlmajorver = 9
	BEGIN
		SET @sqlcmd
			= N'SELECT 
				  @StartDateOUT = login_time
				, @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()) 
				FROM 
				  master..sysprocesses WHERE spid = 1';
	END;
ELSE
	BEGIN
		SET @sqlcmd
			= N'SELECT 
				  @StartDateOUT = sqlserver_start_time
				, @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()) 
				FROM 
				  sys.dm_os_sys_info';
	END;

SET @params = N'@StartDateOUT DATETIME OUTPUT, @UpTimeOUT VARCHAR(12) OUTPUT';

EXECUTE sp_executesql
	@sqlcmd
  , @params
  , @startdateout = @startdate OUTPUT
  , @uptimeout = @uptime OUTPUT;

SELECT
	@startdate AS sq_server_start_date_time
  , CONVERT (varchar(4), @uptime / 60 / 24) + 'd '
	+ CONVERT (varchar(4), @uptime / 60 % 24) + 'h '
	+ CONVERT (varchar(4), @uptime % 60) + 'm' AS uptime;

DROP TABLE IF EXISTS ##compression;
CREATE TABLE ##compression
(
	schema_id int NOT NULL
  , schema_name sysname NOT NULL
  , object_id int NOT NULL
  , object_name sysname NOT NULL
  , partition int NOT NULL
  , index_id int NOT NULL
  , index_name sysname NULL
  , index_type varchar(50) NOT NULL
  , rows bigint NOT NULL
  , current_compression_type nvarchar(60) NOT NULL
  , percent_scan decimal(5, 2) NOT NULL
  , percent_update decimal(5, 2) NOT NULL
  , size_with_current_compression_in_kb bigint NULL
  , size_with_row_compression_in_kb bigint NULL
  , savings_by_row_compression_in_percent decimal(5, 2) NULL
  , size_with_page_compression_in_kb bigint NULL
  , savings_by_page_compression_in_percent decimal(5, 2) NULL
  , recommended_compression_type varchar(50) NULL
  , recommended_compression_command nvarchar(4000) NULL
);

DROP TABLE IF EXISTS ##estimated_row_compression;
CREATE TABLE ##estimated_row_compression
(
	object_name sysname NOT NULL
  , schema_name sysname NOT NULL
  , index_id int NOT NULL
  , partition int NOT NULL
  , size_with_current_compression_setting_in_kb bigint NOT NULL
  , size_with_requested_compression_setting_in_kb bigint NOT NULL
  , sample_size_with_current_compression_setting_in_kb bigint NOT NULL
  , sample_size_with_requested_compression_setting_in_kb bigint NOT NULL
);

DROP TABLE IF EXISTS ##estimated_page_compression;
CREATE TABLE ##estimated_page_compression
(
	object_name sysname NOT NULL
  , schema_name sysname NOT NULL
  , index_id int NOT NULL
  , partition int NOT NULL
  , size_with_current_compression_setting_in_kb bigint NOT NULL
  , size_with_requested_compression_setting_in_kb bigint NOT NULL
  , sample_size_with_current_compression_setting_in_kb bigint NOT NULL
  , sample_size_with_requested_compression_setting_in_kb bigint NOT NULL
);

INSERT ##compression
	(
		schema_id
	  , schema_name
	  , object_id
	  , object_name
	  , partition
	  , index_id
	  , index_name
	  , index_type
	  , rows
	  , current_compression_type
	  , percent_scan
	  , percent_update
	  , size_with_current_compression_in_kb
	  , size_with_row_compression_in_kb
	  , savings_by_row_compression_in_percent
	  , size_with_page_compression_in_kb
	  , savings_by_page_compression_in_percent
	  , recommended_compression_type
	  , recommended_compression_command
	)
SELECT
	sch.schema_id AS schema_id
  , sch.name AS schema_name
  , obj.object_id
  , obj.name AS object_name
  , par.partition_number AS partition
  , ind.index_id
  , ind.name AS index_name
  , ind.type_desc AS index_type
  , par.rows
  , data_compression_desc AS current_compression_type
  , ISNULL (
			   stat.range_scan_count * 100.0
			   / NULLIF (
							(stat.range_scan_count + stat.leaf_insert_count
							 + stat.leaf_delete_count + stat.leaf_update_count
							 + stat.leaf_page_merge_count
							 + stat.singleton_lookup_count
							), 0
						), 0
		   ) AS percent_scan
  , ISNULL (
			   stat.leaf_update_count * 100.0
			   / NULLIF (
							(stat.range_scan_count + stat.leaf_insert_count
							 + stat.leaf_delete_count + stat.leaf_update_count
							 + stat.leaf_page_merge_count
							 + stat.singleton_lookup_count
							), 0
						), 0
		   ) AS percent_update
  , NULL AS size_with_current_compression_in_kb
  , NULL AS size_with_row_compression_in_kb
  , NULL AS savings_by_row_compression_in_percent
  , NULL AS size_with_page_compression_in_kb
  , NULL AS savings_by_page_compression_in_percent
  , NULL AS recommended_compression_type
  , NULL AS recommended_compression_command
FROM
	sys.objects AS obj
INNER JOIN
	sys.schemas AS sch
ON
	obj.schema_id = sch.schema_id
INNER JOIN
	sys.indexes AS ind
ON
	obj.object_id = ind.object_id
INNER JOIN
	sys.partitions AS par
ON
	ind.object_id = par.object_id
	AND ind.index_id = par.index_id
OUTER APPLY sys.dm_db_index_operational_stats (
												  DB_ID (), ind.object_id
												, ind.index_id
												, par.partition_number
											  ) AS stat
WHERE
	OBJECTPROPERTY (obj.object_id, 'IsUserTable') = 1
ORDER BY
	sch.name, obj.name;

DECLARE @number_of_objects int;
SELECT @number_of_objects = COUNT (*)
FROM
	##compression;

DECLARE
	@schema_name sysname
  , @object_name sysname
  , @partition int
  , @index_id int
  , @index_name sysname
  , @counter int = 1;

DECLARE cur CURSOR FAST_FORWARD FOR
SELECT
	schema_name, object_name, partition, index_id, index_name
FROM
	##compression;
OPEN cur;
FETCH NEXT FROM cur
INTO
	@schema_name, @object_name, @partition, @index_id, @index_name;
WHILE @@FETCH_STATUS = 0
	BEGIN
		RAISERROR (
					  '%i out of %i : Estimate compression savings for %s.%s.%s partition %i'
					, 10, 1, @counter, @number_of_objects, @schema_name
					, @object_name, @index_name, @partition
				  ) WITH NOWAIT;

		INSERT INTO ##estimated_row_compression
		EXEC ('sp_estimate_data_compression_savings ''' + @schema_name + ''', ''' + @object_name + ''', ''' + @index_id + ''', ''' + @partition + ''', ''ROW''');
		INSERT INTO ##estimated_page_compression
		EXEC ('sp_estimate_data_compression_savings ''' + @schema_name + ''', ''' + @object_name + ''', ''' + @index_id + ''', ''' + @partition + ''', ''PAGE''');
		FETCH NEXT FROM cur
		INTO
			@schema_name, @object_name, @partition, @index_id, @index_name;
		SELECT @counter = @counter + 1;
	END;
CLOSE cur;
DEALLOCATE cur;

WITH
	cte_compression_savings AS
		(
			SELECT
				tr.object_name
			  , tr.schema_name
			  , tr.index_id
			  , tr.partition
			  , tr.size_with_current_compression_setting_in_kb
			  , tr.size_with_requested_compression_setting_in_kb AS size_with_row_compression_in_kb
			  , CASE
					WHEN tr.size_with_requested_compression_setting_in_kb = 0
						 THEN 0
					ELSE 100
						 - ((tr.size_with_requested_compression_setting_in_kb
							 * 100.0
							)
							/ CASE
								  WHEN tr.size_with_current_compression_setting_in_kb = 0
									   THEN 1
								  ELSE tr.size_with_current_compression_setting_in_kb
							  END
						   )
				END AS savings_by_row_compression_in_percent
			  , tp.size_with_requested_compression_setting_in_kb AS size_with_page_compression_in_kb
			  , CASE
					WHEN tr.size_with_requested_compression_setting_in_kb = 0
						 THEN 0
					ELSE 100
						 - ((tp.size_with_requested_compression_setting_in_kb
							 * 100.0
							)
							/ CASE
								  WHEN tp.size_with_current_compression_setting_in_kb = 0
									   THEN 1
								  ELSE tp.size_with_current_compression_setting_in_kb
							  END
						   )
				END AS savings_by_page_compression_in_percent
			FROM
				##estimated_row_compression AS tr
			INNER JOIN
				##estimated_page_compression AS tp
			ON
				tr.object_name = tp.object_name
				AND tr.schema_name = tp.schema_name
				AND tr.index_id = tp.index_id
				AND tr.partition = tp.partition
		)
UPDATE
	##compression
SET
	size_with_current_compression_in_kb = comp_sav.size_with_current_compression_setting_in_kb
  , size_with_row_compression_in_kb = comp_sav.size_with_row_compression_in_kb
  , savings_by_row_compression_in_percent = comp_sav.savings_by_row_compression_in_percent
  , size_with_page_compression_in_kb = comp_sav.size_with_page_compression_in_kb
  , savings_by_page_compression_in_percent = comp_sav.savings_by_page_compression_in_percent
FROM
	cte_compression_savings AS comp_sav
INNER JOIN
	##compression AS comp
ON
	comp_sav.object_name = comp.object_name
	AND comp_sav.schema_name = comp.schema_name
	AND comp_sav.index_id = comp.index_id
	AND comp_sav.partition = comp.partition;


WITH
	cte_compression_recommendation AS
		(
			SELECT
				object_id
			  , index_id
			  , partition
			  , CONVERT (
							varchar(50)
						  , CASE
								WHEN savings_by_row_compression_in_percent <= 0
									 AND savings_by_page_compression_in_percent <= 0
									 THEN 'none'
								WHEN percent_update >= 10
									 THEN 'row'
								WHEN percent_scan <= 1
									 AND percent_update <= 1
									 AND savings_by_row_compression_in_percent > savings_by_page_compression_in_percent
									 THEN 'row'
								WHEN percent_scan <= 1
									 AND percent_update <= 1
									 AND savings_by_row_compression_in_percent < savings_by_page_compression_in_percent
									 THEN 'page'
								WHEN percent_scan >= 60
									 AND percent_update <= 5
									 THEN 'page'
								WHEN percent_scan <= 35
									 AND percent_update <= 5
									 THEN 'likely row'
								ELSE 'row'
							END
						) AS recommended_compression_type
			FROM
				##compression
			WHERE
				percent_scan > 0
				OR percent_update > 0
		)
UPDATE
	##compression
SET
	recommended_compression_type = ISNULL (
											  com_rec.recommended_compression_type
											, 'no recommendation'
										  )
  , recommended_compression_command = CASE
										  WHEN com_rec.recommended_compression_type IN (
																						   'row'
																						 , 'page'
																						 , 'likely row'
																					   )
											   AND com_rec.recommended_compression_type <> comp.current_compression_type
											   THEN CASE
														WHEN comp.index_id IN (
																				  0
																				, 1
																			  )
															 THEN CONCAT (
																			 'ALTER TABLE '
																		   , QUOTENAME (comp.schema_name)
																		   , '.'
																		   , QUOTENAME (comp.object_name)
																		   , ' REBUILD PARTITION = '
																		   , comp.partition
																		   , ' WITH (DATA_COMPRESSION = '
																		   , UPPER (com_rec.recommended_compression_type)
																		   , ');'
																		 )
														ELSE CONCAT (
																		'ALTER INDEX '
																	  , QUOTENAME (comp.index_name)
																	  , ' ON '
																	  , QUOTENAME (comp.schema_name)
																	  , '.'
																	  , QUOTENAME (comp.object_name)
																	  , ' REBUILD PARTITION = '
																	  , comp.partition
																	  , ' WITH (DATA_COMPRESSION = '
																	  , UPPER (com_rec.recommended_compression_type)
																	  , ');'
																	)
													END
									  END
FROM
	##compression AS comp
LEFT JOIN
	cte_compression_recommendation AS com_rec
ON
	com_rec.object_id = comp.object_id
	AND com_rec.index_id = comp.index_id
	AND com_rec.partition = comp.partition;

SELECT * FROM ##compression;

DROP TABLE IF EXISTS ##compression;
DROP TABLE IF EXISTS ##estimated_row_compression;
DROP TABLE IF EXISTS ##estimated_page_compression;
GO
