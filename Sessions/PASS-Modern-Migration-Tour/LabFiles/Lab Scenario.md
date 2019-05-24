# PASS Modern Migration Tour - Modernization Scenario
You are the lead Database Administrator for Contoso Inc. You and your team of SQL Server DBAs have been tasked with migrating the AdventureWorks application from SQL Server 2008 R2 to SQL Server 2017. Given that the end of support for SQL Server 2008 is rapidly approaching, you need to do this quickly and efficiently. As the AdventureWorks application is the primary revenue-generating application at the company, the business is counting on you to provide a reliable modernization strategy that will allow the application to be migrated in a timely fashion with minimal risk to application performance and stability.

The AdventureWorks application currently includes one database residing on SQL Server 2008 R2 in 100 compatibility level. This database must be upgraded to SQL Server 2017 without any impact to the functionality of the application and at a performance level that is the same or better than SQL Server 2008 R2. Ideally, once the application is functional on SQL Server 2017, the compatibility level of the database should be upgraded to 140 to take advantage of improvements in the query optimizer. In order to achieve this goal, you have the following tools available to you:

- Data Migration Assistant (DMA)
- Database Experimentation Assistant (DEA)
- Query Tuning Assistant (QTA), which is part of SQL Server Management Studio 18.0 (SSMS)
- All the new features of SQL Server 2017 (Query Store, new DMVs, Intelligent Query Processing, new query hints etc.)

The most successful team is the one who is able to migrate the database to SQL Server 2017 and database compatibility level 140 with the largest improvement to the workload as measured by the time to complete the ostress workload. The workload must complete with no errors.
