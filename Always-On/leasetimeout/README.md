## Least Timeouts
This folder provides the Power BI Desktop file along with the T-SQL queries for creating and extracting relevant information from Extended Event traces for tracking lease timeouts for Availability Groups.

**CreateXEventsTracingSession.sql** - Extended event session definition to track AlwaysOn latency

**ExtractXEData.sql** - Extract the data from the AlwaysOn extended event trace and store the extracted data in a tempdb table

**AG Latency.pbix** - Provides easy to use visualizations using the extracted data from the Latency related Extended Events

SQL Server improvements for lease timeout are documented in [KB3112363](https://support.microsoft.com/en-us/kb/3112363)

A recording of the SQL PASS HADR Virtual Chapter session where this information was presented is available on [YouTube](https://youtu.be/r_nLq---DQg?t=7m4s)
