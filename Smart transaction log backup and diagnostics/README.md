Run DB.sql to create PowerConsumption database 
Run CollectTlogDiagnosticsCollectionJob.sql on SQL 2017 instance to create a Data collection job and start it.
Make sure job is running successfully every 1 min and collecting the data in PowerConsumption database.
Open PowerBI report and change datasource settings to change connection string to SQL 2017 instance and database name to PowerConsumption.
Open Scheduledbackup.sql, DB.sql and Smartbackup.sql in the Management Studio query windows.
Start running Scheduledbackup.sql to start scheduled backups first
Run Smart-iot-grid data generator to start transactional activity
Refresh Power BI dashboard to see Autogrows, VLF count increasing and variable backup size. (Note down the VLF count, total log size and backup size after few mins)
Stop data generator and Scheduledbackup.sql
Run DB.sql again to drop and recreate database to clean up the data.
Refresh Power BI report to ensure data is cleared 
Run Smartbackup.sql to kickoff smart backup
Observe no backups generated when there is no activity
Run Smart-iot-grid data generator to start transactional activity
Note VLF count, total log size and backup size after few mins
You will observe minimal autogrows (only 1), relatively low VLF count (less vlf fragmentation), consistent backup size (~ 25 MB which is the threshold to trigger smart backup in the script)
