restore filelistonly from disk = 'c:\temp\wideworldimporters-full.bak'
go
restore database wideworldimporters from disk = 'c:\temp\wideworldimporters-full.bak'
with move 'wwi_primary' to 'c:\temp\wideworldimporters.mdf',
move 'wwi_userdata' to 'c:\temp\wideworldimporters_userdata.ndf',
move 'wwi_log' to 'c:\temp\wideworldimporters.ldf',
move 'wwi_inmemory_data_1' to 'c:\temp\wideworldimporters_inmemory_data_1'
go