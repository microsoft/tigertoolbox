USE AdventureWorks
GO
--DROP TABLE #SalesPerson
--GO
--DROP PROCEDURE dbo.usp_SalesAnalysis_Optimized
--GO
CREATE PROCEDURE dbo.usp_SalesAnalysis_Optimized
AS
BEGIN

CREATE TABLE #SalesPerson(
	[BusinessEntityID] [int] NOT NULL PRIMARY KEY CLUSTERED,
	[TerritoryID] [int] NULL,
	[SalesQuota] [money] NULL,
	[Bonus] [money] NOT NULL,
	[CommissionPct] [smallmoney] NOT NULL,
	[SalesYTD] [money] NOT NULL,
	[SalesLastYear] [money] NOT NULL,
	[rowguid] [uniqueidentifier] ROWGUIDCOL  NOT NULL UNIQUE NONCLUSTERED,
	[ModifiedDate] [datetime] NOT NULL
) 

INSERT INTO #SalesPerson VALUES 
(274,NULL,NULL,0.00,0.00,559697.5639,0.00,'48754992-9EE0-4C0E-8C94-9451604E3E02','2010-12-28 00:00:00.000'),
(275,2,300000.00,4100.00,0.012,3763178.1787,1750406.4785,'1E0A7274-3064-4F58-88EE-4C6586C87169','2011-05-24 00:00:00.000'),
(276,4,250000.00,2000.00,0.015,4251368.5497,1439156.0291,'4DD9EEE4-8E81-4F8C-AF97-683394C1F7C0','2011-05-24 00:00:00.000'),
(277,3,250000.00,2500.00,0.015,3189418.3662,1997186.2037,'39012928-BFEC-4242-874D-423162C3F567','2011-05-24 00:00:00.000'),
(278,6,250000.00,500.00,0.01,1453719.4653,1620276.8966,'7A0AE1AB-B283-40F9-91D1-167ABF06D720','2011-05-24 00:00:00.000'),
(279,5,300000.00,6700.00,0.01,2315185.611,1849640.9418,'52A5179D-3239-4157-AE29-17E868296DC0','2011-05-24 00:00:00.000'),
(280,1,250000.00,5000.00,0.01,1352577.1325,1927059.178,'BE941A4A-FB50-4947-BDA4-BB8972365B08','2011-05-24 00:00:00.000'),
(281,4,250000.00,3550.00,0.01,2458535.6169,2073505.9999,'35326DDB-7278-4FEF-B3BA-EA137B69094E','2011-05-24 00:00:00.000'),
(282,6,250000.00,5000.00,0.015,2604540.7172,2038234.6549,'31FD7FC1-DC84-4F05-B9A0-762519EACACC','2011-05-24 00:00:00.000'),
(283,1,250000.00,3500.00,0.012,1573012.9383,1371635.3158,'6BAC15B2-8FFB-45A9-B6D5-040E16C2073F','2011-05-24 00:00:00.000'),
(284,1,300000.00,3900.00,0.019,1576562.1966,0.00,'AC94EC04-A2DC-43E3-8654-DD0C546ABC17','2012-09-23 00:00:00.000'),
(285,NULL,NULL,0.00,0.00,172524.4512,0.00,'CFDBEF27-B1F7-4A56-A878-0221C73BAE67	2013-03-07','00:00:00.000'),
(286,9,250000.00,5650.00,0.018,1421810.9242,2278548.9776,'9B968777-75DC-45BD-A8DF-9CDAA72839E1','2013-05-23 00:00:00.000'),
(287,NULL,NULL,0.00,0.00,519905.932,0.00,'1DD1F689-DF74-4149-8600-59555EEF154B','2012-04-09 00:00:00.000'),
(288,8,250000.00,75.00,0.018,1827066.7118,1307949.7917,'224BB25A-62E3-493E-ACAF-4F8F5C72396A','2013-05-23 00:00:00.000'),
(289,10,250000.00,5150.00,0.02,4116871.2277,1635823.3967,'25F6838D-9DB4-4833-9DDC-7A24283AF1BA','2012-05-23 00:00:00.000'),
(290,7,250000.00,985.00,0.016,3121616.3202,2396539.7601,'F509E3D4-76C8-42AA-B353-90B7B8DB08DE','2012-05-23 00:00:00.000')

SELECT 
    s.[BusinessEntityID]
    ,p.[Title]
    ,p.[FirstName]
    ,p.[MiddleName]
    ,p.[LastName]
    ,p.[Suffix]
    ,e.[JobTitle]
    ,pp.[PhoneNumber]
	,pnt.[Name] AS [PhoneNumberType]
    ,ea.[EmailAddress]
    ,p.[EmailPromotion]
    ,a.[AddressLine1]
    ,a.[AddressLine2]
    ,a.[City]
    ,[StateProvinceName] = sp.[Name]
    ,a.[PostalCode]
    ,[CountryRegionName] = cr.[Name]
    ,[TerritoryName] = st.[Name]
    ,[TerritoryGroup] = st.[Group]
    ,s.[SalesQuota]
    ,s.[SalesYTD]
    ,s.[SalesLastYear]
FROM #SalesPerson s
    INNER JOIN [HumanResources].[Employee] e 
    ON e.[BusinessEntityID] = s.[BusinessEntityID]
	INNER JOIN [Person].[Person] p
	ON p.[BusinessEntityID] = s.[BusinessEntityID]
    INNER JOIN [Person].[BusinessEntityAddress] bea 
    ON bea.[BusinessEntityID] = s.[BusinessEntityID] 
    INNER JOIN [Person].[Address] a 
    ON a.[AddressID] = bea.[AddressID]
    INNER JOIN [Person].[StateProvince] sp 
    ON sp.[StateProvinceID] = a.[StateProvinceID]
    INNER JOIN [Person].[CountryRegion] cr 
    ON cr.[CountryRegionCode] = sp.[CountryRegionCode]
    LEFT OUTER JOIN [Sales].[SalesTerritory] st 
    ON st.[TerritoryID] = s.[TerritoryID]
	LEFT OUTER JOIN [Person].[EmailAddress] ea
	ON ea.[BusinessEntityID] = p.[BusinessEntityID]
	LEFT OUTER JOIN [Person].[PersonPhone] pp
	ON pp.[BusinessEntityID] = p.[BusinessEntityID]
	LEFT OUTER JOIN [Person].[PhoneNumberType] pnt
	ON pnt.[PhoneNumberTypeID] = pp.[PhoneNumberTypeID]

SELECT 
    pvt.[SalesPersonID]
    ,pvt.[FullName]
    ,pvt.[JobTitle]
    ,pvt.[SalesTerritory]
    ,pvt.[2010]
    ,pvt.[2011]
    ,pvt.[2012] 
FROM (SELECT 
        soh.[SalesPersonID]
        ,p.[FirstName] + ' ' + COALESCE(p.[MiddleName], '') + ' ' + p.[LastName] AS [FullName]
        ,e.[JobTitle]
        ,st.[Name] AS [SalesTerritory]
        ,soh.[SubTotal]
        ,YEAR(DATEADD(m, 6, soh.[OrderDate])) AS [FiscalYear] 
    FROM #SalesPerson sp 
        INNER JOIN [Sales].[SalesOrderHeader] soh 
        ON sp.[BusinessEntityID] = soh.[SalesPersonID]
        INNER JOIN [Sales].[SalesTerritory] st 
        ON sp.[TerritoryID] = st.[TerritoryID] 
        INNER JOIN [HumanResources].[Employee] e 
        ON soh.[SalesPersonID] = e.[BusinessEntityID] 
		INNER JOIN [Person].[Person] p
		ON p.[BusinessEntityID] = sp.[BusinessEntityID]
	 ) AS soh 
PIVOT 
(
    SUM([SubTotal]) 
    FOR [FiscalYear] 
    IN ([2010], [2011], [2012])
) AS pvt

END
GO

EXEC dbo.usp_SalesAnalysis_Optimized
GO
