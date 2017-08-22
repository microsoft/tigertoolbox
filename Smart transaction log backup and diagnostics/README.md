1.	Run DB.sql to create PowerConsumption database 
2.	Run CollectTlogDiagnosticsCollectionJob.sql on SQL 2017 instance to create a Data collection job and start it.
3.	Make sure job is running successfully every 1 min and collecting the data in PowerConsumption database.
4.	Open PowerBI report and change datasource settings to change connection string to SQL 2017 instance and database name to PowerConsumption.
5.	Open Scheduledbackup.sql, DB.sql and Smartbackup.sql in the Management Studio query windows.
6.	Start running Scheduledbackup.sql to start scheduled backups first
7.	Run Smart-iot-grid data generator (Client.exe) to start transactional activity.
8.	Refresh Power BI dashboard to see Autogrows, VLF count increasing and variable backup size. (Note down the VLF count, total log size and backup size after few mins).
9.	Stop data generator and Scheduledbackup.sql.
10.	Run DB.sql again to drop and recreate database to clean up the data.
11.	Refresh Power BI report to ensure data is cleared.
12.	Run Smartbackup.sql to kickoff smart backup.
13.	Observe no backups generated when there is no activity.
14.	Run Smart-iot-grid data generator to start transactional activity.
15.	Note VLF count, total log size and backup size after few mins.
16.	You will observe minimal autogrows (only 1), relatively low VLF count (less vlf fragmentation), consistent backup size (~ 25 MB which is the threshold to trigger smart backup in the script).
