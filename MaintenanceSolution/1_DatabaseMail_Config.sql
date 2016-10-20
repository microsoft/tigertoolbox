sp_configure 'show advanced options', 1
RECONFIGURE WITH OVERRIDE
GO
sp_configure 'Database Mail XPs', 1
RECONFIGURE WITH OVERRIDE
GO

USE [msdb]
GO

-------------------------------------------------------------
--  Database Mail Simple Configuration Template.
--
--  This template creates a Database Mail profile, an SMTP account and
--  associates the account to the profile.
--  The template does not grant access to the new profile for
--  any database principals.  Use msdb.dbo.sysmail_add_principalprofile
--  to grant access to the new profile for users who are not
--  members of sysadmin.
-------------------------------------------------------------

DECLARE @profile_name sysname,
        @account_name sysname,
        @SMTP_servername sysname,
        @email_address NVARCHAR(128),
		@display_name NVARCHAR(128),
		@port_number int,
		@desc_p NVARCHAR(128),
		@desc_a NVARCHAR(128),
		@customoper sysname;

-- Profile name. Replace with the name for your profile
    SET @profile_name = 'Database Administration Profile';

-- Account and SQL Operator information. Replace with the information for your account.
	SET @account_name = 'Database Administration Profile';
	SET @SMTP_servername = 'SERVER_FQDN';
	SET @email_address = 'user@domain';
    SET @display_name = 'user';
	SET @port_number = 25;
	SET @desc_p = 'Mail account used by DBA staff';
	SET @desc_a = 'Mail account used by DBA staff';
	SET @customoper = 'SQLAdmins'

-- Verify the specified account and profile do not already exist.
IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profile WHERE name = @profile_name)
BEGIN
  RAISERROR('The specified Database Mail profile (Database Administration Profile) already exists.', 16, 1);
  GOTO done;
END;

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_account WHERE name = @account_name )
BEGIN
 RAISERROR('The specified Database Mail account (Database Administration Profile) already exists.', 16, 1) ;
 GOTO done;
END;

-- Start a transaction before adding the account and the profile
BEGIN TRANSACTION ;

DECLARE @rv int;

-- Add the account
EXECUTE @rv=msdb.dbo.sysmail_add_account_sp
    @account_name = @account_name,
    @email_address = @email_address,
    @replyto_address = NULL,
    @display_name = @display_name,
    @mailserver_name = @SMTP_servername,
    @mailserver_type = 'SMTP',
    @port = @port_number,
    @description = @desc_a,
    @username = NULL,
    @password = NULL,
    @use_default_credentials = 0,
    @enable_ssl = 0;

IF @rv<>0
BEGIN
    RAISERROR('Failed to create the specified Database Mail account (Database Administration Profile).', 16, 1) ;
    GOTO done;
END

-- Add the profile
EXECUTE @rv=msdb.dbo.sysmail_add_profile_sp
    @profile_name = @profile_name,
    @description = @desc_p;

IF @rv<>0
BEGIN
    RAISERROR('Failed to create the specified Database Mail profile (Database Administration Profile).', 16, 1);
	ROLLBACK TRANSACTION;
    GOTO done;
END;

-- Associate the account with the profile.
EXECUTE @rv=msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = @profile_name,
    @account_name = @account_name,
    @sequence_number = 1 ;

IF @rv<>0
BEGIN
    RAISERROR('Failed to associate the speficied profile with the specified account (Database Administration Profile).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

-- Grant permission to public.
EXECUTE @rv=msdb.dbo.sysmail_add_principalprofile_sp
    @principal_id = 0,
    @profile_name = @profile_name,
    @is_default = 1;

IF @rv<>0
BEGIN
    RAISERROR('Failed to grant permission for [public] role to use Database Mail profile (Database Administration Profile).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

EXECUTE @rv=master.dbo.sp_MSsetalertinfo @failsafeoperator=N'Administrator', @notificationmethod=1
IF @rv<>0
BEGIN
    RAISERROR('Failed to set default operator (Administrator).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

EXECUTE @rv=msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1
IF @rv<>0
BEGIN
    RAISERROR('Failed to set SQL Agent property (email_save_in_sent_folder).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

EXECUTE @rv=master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'UseDatabaseMail', N'REG_DWORD', 1
IF @rv<>0
BEGIN
    RAISERROR('Failed to set SQL Agent property (UseDatabaseMail).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

EXECUTE @rv=master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile', N'REG_SZ', N'Database Administration Profile'
IF @rv<>0
BEGIN
    RAISERROR('Failed to set SQL Agent property (DatabaseMailProfile).', 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

--Create operator
IF EXISTS (SELECT name FROM msdb.dbo.sysoperators WHERE name = @customoper)
EXEC msdb.dbo.sp_delete_operator @name=@customoper

EXEC msdb.dbo.sp_add_operator @name=@customoper, 
		@enabled=1, 
		@weekday_pager_start_time=90000, 
		@weekday_pager_end_time=180000, 
		@saturday_pager_start_time=90000, 
		@saturday_pager_end_time=180000, 
		@sunday_pager_start_time=90000, 
		@sunday_pager_end_time=180000, 
		@pager_days=0, 
		@email_address=@email_address, 
		@category_name=N'[Uncategorized]'

COMMIT TRANSACTION;

done:

GO

--To check service broker status for MSDB.
DECLARE @BROSTAT int
SELECT @BROSTAT = is_broker_enabled FROM sys.databases WHERE name='msdb'
--If the above query returns 1, the service broker is enabled in MSDB. If not run the below query to enable service broker in MSDB, we need to enable this because database mail works with this.
IF @BROSTAT <> 1 
BEGIN
	EXEC sp_executesql N'ALTER DATABASE msdb SET enable_broker'
END
--Once its done, run the below query in MSDB to enable the queue ExternalMailQueue
EXEC msdb..sysmail_start_sp
ALTER QUEUE ExternalMailQueue WITH status = on
GO
