IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[dbo].[usp_SecurCreation]') AND OBJECTPROPERTY(id, N'IsProcedure') = 1)
DROP PROCEDURE [dbo].[usp_SecurCreation]
GO

CREATE PROCEDURE usp_SecurCreation @user_name sysname = NULL, @dbname sysname = NULL
--WITH ENCRYPTION
AS
--  Generates all database logins and their respective securables.
--
--  2012-09-20 Pedro Lopes (Microsoft) pedro.lopes@microsoft.com (http://aka.ms/sqlinsights/)
--  2013-01-11 - Fixed issue with generating all logins even when single database was chosen.
--  11/17/2016 - Fixed issue with permissions being repeated.
--
--  Does not deal with CERTIFICATE_MAPPED_LOGIN and ASYMMETRIC_KEY_MAPPED_LOGIN types 
-- 
--  All users: EXEC usp_SecurCreation 
--  One user, All DBs: EXEC usp_SecurCreation '<User>'
--  One user, One DBs: EXEC usp_SecurCreation '<User>', '<DBName>'
--  All users, One DBs: EXEC usp_SecurCreation NULL, '<DBName>'
-- 

SET NOCOUNT ON;

DECLARE @SC NVARCHAR(4000), @SCUser NVARCHAR(4000), @SCDB NVARCHAR(4000)
CREATE TABLE #TempSecurables ([State] VARCHAR(100),
            [State2] VARCHAR(100),
            [PermName] VARCHAR(100),
            [Type] NVARCHAR(60),
            [Grantor] VARCHAR(100),
            [User] VARCHAR(100)
            )    
CREATE TABLE #TempSecurables2 ([DBName] sysname,
                [State] VARCHAR(1000)
                )    

IF @user_name IS NULL AND @dbname IS NULL
BEGIN
    --Server level Privileges to User or User Group
    INSERT INTO #TempSecurables
    SELECT CASE CAST(p.state AS VARCHAR(100)) WHEN 'D' THEN 'DENY' WHEN 'R' THEN 'REVOKE' WHEN 'G' THEN 'GRANT' WHEN 'W' THEN 'GRANT' END, 
    CASE CAST(p.state AS VARCHAR(100)) WHEN 'W' THEN 'WITH GRANT OPTION' ELSE '' END, CAST(p.permission_name AS VARCHAR(100)), RTRIM(p.class_desc),
    (SELECT [name] FROM sys.server_principals WHERE principal_id = p.grantor_principal_id), CAST(l.name AS VARCHAR(100))
    FROM sys.server_permissions p INNER JOIN sys.server_principals l ON p.grantee_principal_id = l.principal_id
	WHERE l.is_disabled = 0 AND l.type IN ('S', 'U', 'G', 'R')
    ORDER BY CAST(l.name AS VARCHAR(100))

    INSERT INTO #TempSecurables2
    EXEC master.dbo.sp_MSforeachdb @command1='USE [?] 
    --Privileges for Procedures/Functions/CLR/Views to the User
    SELECT ''[?]'', CASE WHEN (b.state_desc COLLATE database_default) = ''GRANT_WITH_GRANT_OPTION'' THEN ''GRANT'' ELSE (b.state_desc COLLATE database_default) + '' '' END + + b.permission_name + ''ON ['' + c.name + ''].['' + a.name + ''] TO '' + QUOTENAME(USER_NAME(b.grantee_principal_id)) +
    CASE STATE WHEN ''W'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].sys.all_objects a, [?].sys.database_permissions b, [?].sys.schemas c 
    WHERE a.OBJECT_ID = b.major_id AND a.type IN (''X'',''P'',''FN'',''AF'',''FS'',''FT'') AND b.grantee_principal_id <>0 
    AND b.grantee_principal_id <>2 AND a.schema_id = c.schema_id
    ORDER BY c.name

    --Table and View Level Privileges to the User
    SELECT ''[?]'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].INFORMATION_SCHEMA.TABLE_PRIVILEGES
    WHERE GRANTEE <> ''public''

    --Column Level Privileges to the User 
    SELECT ''[?]'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] ('' + column_name + '') TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].INFORMATION_SCHEMA.COLUMN_PRIVILEGES
    WHERE GRANTEE <> ''public'''
END
ELSE IF @user_name IS NULL AND @dbname IS NOT NULL
BEGIN
    --Server level Privileges to User or User Group
    SET @SCDB='SELECT DISTINCT CASE CAST(p.state AS VARCHAR(100)) WHEN ''D'' THEN ''DENY'' WHEN ''R'' THEN ''REVOKE'' WHEN ''G'' THEN ''GRANT'' WHEN ''W'' THEN ''GRANT'' END, 
    CASE CAST(p.state AS VARCHAR(100)) WHEN ''W'' THEN ''WITH GRANT OPTION'' ELSE '''' END, CAST(p.permission_name AS VARCHAR(100)), RTRIM(p.class_desc),
    (SELECT [name] FROM sys.server_principals WHERE principal_id = p.grantor_principal_id), CAST(l.name AS VARCHAR(100))
    FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS l ON p.grantee_principal_id = l.principal_id
	WHERE l.is_disabled = 0 
		AND l.type IN (''S'', ''U'', ''G'', ''R'')
		AND l.sid IN (SELECT DISTINCT sid FROM [' + @dbname + '].sys.database_principals 
		WHERE type IN (''S'', ''U'', ''G'', ''R'') AND sid IS NOT NULL AND name <> ''guest'')
    ORDER BY CAST(l.name AS VARCHAR(100))'
    
    INSERT INTO #TempSecurables
    EXEC master..sp_executesql @SCDB
    
    SET @SCDB='USE [' + @dbname + '] 
    --Privileges for Procedures/Functions/CLR/Views to the User
    SELECT ''[' + @dbname + ']'', CASE WHEN (b.state_desc COLLATE database_default) = ''GRANT_WITH_GRANT_OPTION '' THEN ''GRANT '' ELSE (b.state_desc COLLATE database_default) + '' '' END + b.permission_name + '' ON ['' + c.name + ''].['' + a.name + ''] TO '' + QUOTENAME(USER_NAME(b.grantee_principal_id)) +
    CASE STATE WHEN ''W'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].sys.all_objects a, [' + @dbname + '].sys.database_permissions b, [' + @dbname + '].sys.schemas c 
    WHERE a.OBJECT_ID = b.major_id AND a.type IN (''X'',''P'',''FN'',''AF'',''FS'',''FT'') AND b.grantee_principal_id <>0 
    AND b.grantee_principal_id <>2 AND a.schema_id = c.schema_id
    ORDER BY c.name

    --Table and View Level Privileges to the User
    SELECT ''[' + @dbname + ']'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].INFORMATION_SCHEMA.TABLE_PRIVILEGES
    WHERE GRANTEE <> ''public''

    --Column Level Privileges to the User 
    SELECT ''[' + @dbname + ']'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] ('' + column_name + '') TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].INFORMATION_SCHEMA.COLUMN_PRIVILEGES
    WHERE GRANTEE <> ''public'''

    INSERT INTO #TempSecurables2
    EXEC master..sp_executesql @SCDB
END
ELSE IF @user_name IS NOT NULL AND @dbname IS NULL
BEGIN
    --Server level Privileges to User or User Group
    INSERT INTO #TempSecurables
    SELECT CASE CAST(p.state AS VARCHAR(100)) WHEN 'D' THEN 'DENY' WHEN 'R' THEN 'REVOKE' WHEN 'G' THEN 'GRANT' WHEN 'W' THEN 'GRANT' END, 
    CASE CAST(p.state AS VARCHAR(100)) WHEN 'W' THEN 'WITH GRANT OPTION' ELSE '' END, CAST(p.[permission_name] AS VARCHAR(100)), RTRIM(p.class_desc),
    (SELECT [name] FROM sys.server_principals WHERE principal_id = p.grantor_principal_id), CAST(l.name AS VARCHAR(100))
    FROM sys.server_permissions p INNER JOIN sys.server_principals l ON p.grantee_principal_id = l.principal_id
    WHERE l.is_disabled = 0
		AND l.type IN ('S', 'U', 'G', 'R')
		AND QUOTENAME(l.name) = QUOTENAME(@user_name)

    SET @SCUser = 'USE [?] 
    --Privileges for Procedures/Functions/CLR/Views to the User
    SELECT ''[?]'', CASE WHEN (b.state_desc COLLATE database_default) = ''GRANT_WITH_GRANT_OPTION '' THEN ''GRANT '' ELSE (b.state_desc COLLATE database_default) + '' '' END + b.permission_name + '' ON ['' + c.name + ''].['' + a.name + ''] TO '' + QUOTENAME(USER_NAME(b.grantee_principal_id)) +
    CASE STATE WHEN ''W'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].sys.all_objects a, [?].sys.database_permissions b, [?].sys.schemas c 
    WHERE a.OBJECT_ID = b.major_id AND a.type IN (''X'',''P'',''FN'',''AF'',''FS'',''FT'') AND b.grantee_principal_id <>0 
    AND b.grantee_principal_id <>2 AND a.schema_id = c.schema_id
    AND QUOTENAME(USER_NAME(b.grantee_principal_id)) = ''[' + @user_name + ']''
    ORDER BY c.name

    --Table and View Level Privileges to the User
    SELECT ''[?]'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].INFORMATION_SCHEMA.TABLE_PRIVILEGES
    WHERE grantee <> ''public''
    AND grantee = ''[' + @user_name + ']''

    --Column Level Privileges to the User 
    SELECT ''[?]'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] ('' + column_name + '') TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [?].INFORMATION_SCHEMA.COLUMN_PRIVILEGES
    WHERE grantee <> ''public''
    AND grantee = ''[' + @user_name + ']'''

    INSERT INTO #TempSecurables2
    EXEC master.dbo.sp_MSforeachdb @command1=@SCUser
END
ELSE IF @user_name IS NOT NULL AND @dbname IS NOT NULL
BEGIN
    --Server level Privileges to User or User Group

    SET @SCDB='SELECT DISTINCT CASE CAST(p.state AS VARCHAR(100)) WHEN ''D'' THEN ''DENY'' WHEN ''R'' THEN ''REVOKE'' WHEN ''G'' THEN ''GRANT'' WHEN ''W'' THEN ''GRANT'' END, 
    CASE CAST(p.state AS VARCHAR(100)) WHEN ''W'' THEN ''WITH GRANT OPTION'' ELSE '''' END, CAST(p.permission_name AS VARCHAR(100)), RTRIM(p.class_desc),
    (SELECT [name] FROM sys.server_principals WHERE principal_id = p.grantor_principal_id), CAST(l.name AS VARCHAR(100))
    FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS l ON p.grantee_principal_id = l.principal_id
	WHERE l.is_disabled = 0 
		AND l.type IN (''S'', ''U'', ''G'', ''R'')
		AND QUOTENAME(l.name) = ''' + QUOTENAME(@user_name) + '''
		AND l.sid IN (SELECT DISTINCT sid FROM [' + @dbname + '].sys.database_principals 
		WHERE type IN (''S'', ''U'', ''G'', ''R'') AND sid IS NOT NULL AND name <> ''guest'')
    ORDER BY CAST(l.name AS VARCHAR(100))'
    
    INSERT INTO #TempSecurables
    EXEC master..sp_executesql @SCDB
    
    SET @SCDB='USE [' + @dbname + '] 
    --Privileges for Procedures/Functions/CLR/Views to the User
    SELECT ''[' + @dbname + ']'', CASE WHEN (b.state_desc COLLATE database_default) = ''GRANT_WITH_GRANT_OPTION '' THEN ''GRANT '' ELSE (b.state_desc COLLATE database_default) + '' '' END + b.permission_name + '' ON ['' + c.name + ''].['' + a.name + ''] TO '' + QUOTENAME(USER_NAME(b.grantee_principal_id)) +
    CASE STATE WHEN ''W'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].sys.all_objects a, [' + @dbname + '].sys.database_permissions b, [' + @dbname + '].sys.schemas c 
    WHERE a.OBJECT_ID = b.major_id AND a.type IN (''X'',''P'',''FN'',''AF'',''FS'',''FT'') AND b.grantee_principal_id <>0 
    AND b.grantee_principal_id <>2 AND a.schema_id = c.schema_id
    AND QUOTENAME(USER_NAME(b.grantee_principal_id)) = ''[' + @user_name + ']''
    ORDER BY c.name

    --Table and View Level Privileges to the User
    SELECT ''[' + @dbname + ']'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].INFORMATION_SCHEMA.TABLE_PRIVILEGES
    WHERE grantee <> ''public''
    AND grantee = ''[' + @user_name + ']''

    --Column Level Privileges to the User 
    SELECT ''[' + @dbname + ']'', ''GRANT '' + privilege_type + '' ON ['' + table_schema + ''].['' + table_name + ''] ('' + column_name + '') TO ['' + grantee + '']'' +
    CASE IS_GRANTABLE WHEN ''YES'' THEN '' WITH GRANT OPTION'' 
    ELSE '''' END FROM [' + @dbname + '].INFORMATION_SCHEMA.COLUMN_PRIVILEGES
    WHERE grantee <> ''public''
    AND grantee = ''[' + @user_name + ']'''
    
    INSERT INTO #TempSecurables2
    EXEC master..sp_executesql @SCDB
END

PRINT '/* usp_SecurCreation script '
PRINT '** Generated ' + CONVERT (VARCHAR, GETDATE()) + ' on ' + @@SERVERNAME + ' */' + CHAR(10)

PRINT CHAR(13) + '--##### Server level Privileges to User or User Group #####' + CHAR(13)

DECLARE cSC CURSOR FAST_FORWARD FOR SELECT 'USE [master];' + CHAR(10) + RTRIM(ts.[State]) + ' ' + RTRIM(ts.[PermName]) + ' TO ' + QUOTENAME(RTRIM(ts.[User])) + ' ' + RTRIM(ts.[State2]) + ';' + CHAR(10) + 'GO' FROM #TempSecurables ts WHERE RTRIM([Type]) = 'SERVER'
OPEN cSC  
FETCH NEXT FROM cSC INTO @SC
WHILE @@FETCH_STATUS = 0 
    BEGIN 
        PRINT @SC
        FETCH NEXT FROM cSC INTO @SC
    END
CLOSE cSC 
DEALLOCATE cSC

DECLARE cSC CURSOR FAST_FORWARD FOR SELECT 'USE [master];' + CHAR(10) + RTRIM(ts.[State]) + ' ' + RTRIM(ts.[PermName]) + ' ON ' + CASE WHEN RTRIM(ts.[Type]) = 'SERVER_PRINCIPAL' THEN 'LOGIN' ELSE 'ENDPOINT' END + '::' + QUOTENAME(RTRIM(ts.[Grantor])) + ' TO ' + QUOTENAME(RTRIM(ts.[User])) + ' ' +RTRIM(ts.[State2]) + ';' + CHAR(10) + 'GO' FROM #TempSecurables ts WHERE RTRIM([Type]) <> 'SERVER'
OPEN cSC  
FETCH NEXT FROM cSC INTO @SC
WHILE @@FETCH_STATUS = 0 
    BEGIN 
        PRINT @SC
        FETCH NEXT FROM cSC INTO @SC
    END
CLOSE cSC 
DEALLOCATE cSC
DROP TABLE #TempSecurables

PRINT CHAR(13) + '--##### Procedures/Functions/CLR/Views, Table and Column Level Privileges to the User #####' + CHAR(13)

DECLARE cSC CURSOR FAST_FORWARD FOR SELECT 'USE ' + ts2.DBName +';' + CHAR(10) + RTRIM(ts2.[State]) + ';' + CHAR(10) + 'GO' FROM #TempSecurables2 ts2
OPEN cSC  
FETCH NEXT FROM cSC INTO @SC
WHILE @@FETCH_STATUS = 0 
    BEGIN 
        PRINT @SC
        FETCH NEXT FROM cSC INTO @SC
    END
CLOSE cSC 
DEALLOCATE cSC

DROP TABLE #TempSecurables2
GO
