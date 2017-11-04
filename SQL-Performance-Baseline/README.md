
# SQL Performance Baseline

A recording of the webinar which talks about this solution is available on [YouTube](https://www.youtube.com/watch?v=bx_NGNEz94k)

### Data Collection
1. T-SQL Scripts
2. CREATEDATABASE, CREATEOBJECTS & CREATECOLLECTIONJOB -> these t-SQL script creates the database dba_local & schema & SQL Agent Jobs required for performance data collection. These SQL scripts needs to be ran on all the sql instance which needs to be monitored
3. Powershell  Scripts 
4. Get-SQLPerfCounters, Out-DataTable, Write-DataTable -> These Powershell scripts needs to be copied to location C:\Scripts\ which is used for Perfmon data collection. These script needs to be copied  on all the target server which needs to be monitored & should be copied to the folder C:\Scripts

### SQL Performance baselining Reports & Xevent Reports (SSRS Reports)

	The SSRS Reports should be deployed on the central SSRS server which should be greater than SQL 2012.

You can follow the steps mentioned below  to set it up in your environment. 

### Data Collection Steps for each SQL Instance to Monitor

1.	Connect to SQL instance to monitor
2.	Run CREATEDATABASE.sql
3.	Run CREATEOBJECTS.sql
4.	Run CREATECOLLECTIONJOB.sql
5.	Check SQL Agent JOBs History to see if it runs successfully
6.	Repeat for each SQL Instance you want to monitor

### Setting up & Deploying Reporting  

1.	Deploy the SSRS Reports & see if data populates in the reports.

_DISCLAIMER_: © 2016 Microsoft Corporation. All rights reserved. Sample scripts in this guide are not supported under any Microsoft standard support program or service. The sample scripts are provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

### Change Notes

Date: 2017/05/12
Author: Dirk Hondong
Affected script: CreateSystemhealthDBandSchema.sql
Affected proc: dbo.spLoadSchedulerMonitor
Change: data type change from int to bigint 
c1.value('(./event/data[@name="id"])[1]', 'int') as [id]  
to 
c1.value('(./event/data[@name="id"])[1]', 'bigint') as [id]
to avoid overflow error
