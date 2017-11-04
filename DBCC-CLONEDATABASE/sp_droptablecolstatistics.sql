CREATE PROCEDURE Usp_droptablecolstatistics(@TableName  SYSNAME, 
                                            @ColumnName SYSNAME = NULL) 
AS 
  BEGIN 
      SET nocount ON 
      DECLARE @Sql NVARCHAR(max) 
      DECLARE @StatsName SYSNAME 
      DECLARE @Error INT 

      IF ( @TableName IS NULL 
            OR Object_id(@TableName) IS NULL ) 
        PRINT 'Table name doesnt exist in the database' 
      ELSE IF ( @ColumnName IS NOT NULL ) 
         AND (SELECT NAME 
              FROM   sys.columns 
              WHERE  object_id = Object_id(@Tablename) 
                     AND NAME = @ColumnName) IS NULL 
        PRINT 'Column name doesnt exist in the table ' 
              + @TableName 

      IF @ColumnName IS NULL 
        BEGIN 
            DECLARE cur CURSOR local FOR 
              SELECT @TableName AS 'TableName', 
                     s.NAME     AS 'StatsName' 
              FROM   sys.stats s 
                     JOIN sys.tables t 
                       ON s.object_id = t.object_id 
              WHERE  s.object_id > 100 
                     AND t.object_id = Object_id(@TableName) 
        END 
      ELSE 
        BEGIN 
            DECLARE cur CURSOR local FOR 
              SELECT @TableName AS 'TableName', 
                     s.NAME     AS 'StatsName' 
              FROM   sys.stats s 
                     INNER JOIN sys.stats_columns AS sc 
                             ON s.object_id = sc.object_id 
                                AND s.stats_id = sc.stats_id 
                     INNER JOIN sys.columns AS c 
                             ON sc.object_id = c.object_id 
                                AND c.column_id = sc.column_id 
              WHERE  s.object_id > 100 
                     AND s.object_id = Object_id(@TableName) 
                     AND c.NAME = @ColumnName 
        END 
      OPEN cur 
      FETCH next FROM cur INTO @TableName, @StatsName 

      WHILE @@FETCH_STATUS = 0 
        BEGIN 
            SET @Sql = 'DROP STATISTICS ' + @TableName + '.' 
                       + Quotename(@StatsName) 
            BEGIN try 
                EXEC Sp_executesql @Sql 
                PRINT 'Executed ' + @Sql + '..' 
            END try 
            BEGIN catch 
                SELECT @ERROR = Error_number() 
                IF @ERROR = 3739 
                  BEGIN try 
                      SET @Sql = 'DROP INDEX ' + @TableName + '.' + Quotename(@StatsName) 
                      EXEC Sp_executesql @Sql 
                      PRINT 'Executed ' + @Sql + '..' 
                  END try 
                BEGIN catch 
                    SELECT @ERROR = Error_number() 
                    IF @Error = 3723 
                      SET @Sql = 'ALTER TABLE ' + @TableName + ' drop constraint ' + Quotename(@StatsName) 
                    PRINT 'Executing ' + @Sql + '..' 
                    EXEC Sp_executesql @Sql 
                END catch 
            END catch 
            FETCH next FROM cur INTO @TableName, @StatsName 
        END 
      CLOSE cur 
      DEALLOCATE cur 
  END  
