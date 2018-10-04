use wideworldimporters
go
DROP procedure [dbo].[initialize]
go
CREATE   procedure [dbo].[initialize]
as begin
DBCC FREEPROCCACHE;
ALTER DATABASE current SET QUERY_STORE CLEAR ALL;
ALTER DATABASE current SET AUTOMATIC_TUNING ( FORCE_LAST_GOOD_PLAN = OFF);
end
GO

DROP procedure [dbo].[fix]
go
CREATE   procedure [dbo].[fix]
as begin
ALTER DATABASE current SET AUTOMATIC_TUNING ( FORCE_LAST_GOOD_PLAN = ON);
DBCC FREEPROCCACHE;
ALTER DATABASE current SET QUERY_STORE CLEAR ALL;
end
GO

DROP PROCEDURE [dbo].[report]
go
CREATE PROCEDURE [dbo].[report] ( @packagetypeid INT )
AS
    BEGIN

        SELECT  AVG([UnitPrice] * [Quantity] - [TaxRate])
        FROM    [Sales].[OrderLines]
        WHERE   [PackageTypeID] = @packagetypeid;

    END;
GO

DROP PROCEDURE [dbo].[regression]
go
CREATE PROCEDURE [dbo].[regression]
AS
    BEGIN
        DBCC FREEPROCCACHE;
        BEGIN
            DECLARE @packagetypeid INT = 1;
            EXEC [report] @packagetypeid;
        END;
    END;
GO