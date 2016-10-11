-- Extended event definition to track down lease expiry
-- Extended event target can be modified to change storage, rollover, buffer or target specifications
CREATE EVENT SESSION [AG_XE_Demo] ON SERVER 
ADD EVENT sqlserver.availability_group_lease_expired,
ADD EVENT sqlserver.hadr_ag_lease_renewal
ADD TARGET package0.event_file(SET filename=N'AG_XE_Demo',max_file_size=(25))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO

