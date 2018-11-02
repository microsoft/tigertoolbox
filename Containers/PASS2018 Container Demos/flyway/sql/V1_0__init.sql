WAITFOR DELAY '00:00:03'

CREATE LOGIN AppLogin WITH PASSWORD = 'yourStrongPassw0rd!'
GO

DROP USER IF EXISTS AppUser
CREATE USER AppUser FROM LOGIN AppLogin
GO

DROP ROLE IF EXISTS AppUserRole
CREATE ROLE AppUserRole
GO

GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE TO AppUserRole
EXEC sp_addrolemember N'AppUserRole', N'AppUser' 
GO

Create database rest_api_example
GO

USE rest_api_example
GO 

if not exists (select * from sysobjects where name='users' and xtype='U')
create table users (
    id INT IDENTITY PRIMARY KEY,
    firstName VARCHAR(50) NOT NULL,
    lastName VARCHAR(50) NOT NULL,
    memberID UNIQUEIDENTIFIER NOT NULL DEFAULT newid(),
    phoneNumber BIGINT NOT NULL,
    email VARCHAR(50) NOT NULL,
    nextFlight VARCHAR(50) NOT NULL,
    previousFlight VARCHAR(50) NOT NULL)
GO

--create user in this database context

DROP USER IF EXISTS AppUser
CREATE USER AppUser FROM LOGIN AppLogin
GO

DROP ROLE IF EXISTS AppUserRole
CREATE ROLE AppUserRole
GO

GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE TO AppUserRole
EXEC sp_addrolemember N'AppUserRole', N'AppUser' 
GO