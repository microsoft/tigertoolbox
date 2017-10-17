This is a sample powerbi dashboard to understand top queries using resources in a SQL Server. To use this:

1. Create and start an extended events session on your SQL Server instance to collect sample data using QPExtendedEvents.sql
2. Import the Extended Events file into a table.
  1. Open the XEL file from step 1 in SSMS
  2. from Extended Events menu, select Export to-> Table.
3. Change the Data Source in the Power BI dashboard to point to your table and import the data.
