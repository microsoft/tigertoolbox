 
## Latency related Extended Events 
This folder provides the Power BI Desktop file for tracking latency during reactive troubleshooting scenarios.

**CreateXEventsTracingSession.sql** - Extended event session definition to track Always On AG latency

**ExtractXEData.sql** - Extract the data from the Always On AG extended event trace and store the extracted data in a tempdb table

**AG Latency.pbix** - Provides easy to use visualizations using the extracted data from the Latency related Extended Events


A recording of the SQL PASS HADR Virtual Chapter session where this information was presented is available on [YouTube](https://youtu.be/r_nLq---DQg?t=7m4s)
