## This scipt requires the ADSNotebook module greater version than 0.0.20191119.1 which can be installed with
#  Install-Module ADSNotebook

$RawSql = Get-Content .\BPCheck\Check_BP_Servers.sql -Raw

$SplitSQL = $RawSql -split '--------------------------------------------------------------------------------------------------------------------------------'

$GlobalVariables = @"
-- These are the variables that are required for the Azure Data Studio Notebook to function in the same way as the stored procedure. Unfortunately, it is easier to add them to the beginning of each code block.  

SET NOCOUNT ON;
SET ANSI_WARNINGS ON;
SET QUOTED_IDENTIFIER ON;

-- Declare Global Variables
DECLARE @UpTime VARCHAR(12),@StartDate DATETIME
DECLARE @agt smallint, @ole smallint, @sao smallint, @xcmd smallint
DECLARE @ErrorSeverity int, @ErrorState int, @ErrorMessage NVARCHAR(4000)
DECLARE @CMD NVARCHAR(4000)
DECLARE @path NVARCHAR(2048)
DECLARE @osver VARCHAR(5), @ostype VARCHAR(10), @osdistro VARCHAR(20), @server VARCHAR(128), @instancename NVARCHAR(128), @arch smallint, @ossp VARCHAR(25), @SystemManufacturer VARCHAR(128), @BIOSVendor AS VARCHAR(128), @Processor_Name AS VARCHAR(128)
DECLARE @existout int, @FSO int, @FS int, @OLEResult int, @FileID int
DECLARE @FileName VARCHAR(200), @Text1 VARCHAR(2000), @CMD2 VARCHAR(100)
DECLARE @src VARCHAR(255), @desc VARCHAR(255), @psavail VARCHAR(20), @psver tinyint
DECLARE @dbid int, @dbname NVARCHAR(1000)
DECLARE @sqlcmd NVARCHAR(max), @params NVARCHAR(600)
DECLARE @sqlmajorver int, @sqlminorver int, @sqlbuild int, @masterpid int, @clustered bit
DECLARE @ptochecks int
DECLARE @dbScope VARCHAR(256) 	
DECLARE @port VARCHAR(15), @replication int, @RegKey NVARCHAR(255), @cpuaffin VARCHAR(300), @cpucount int, @numa int
DECLARE @i int, @cpuaffin_fixed VARCHAR(300), @affinitymask NVARCHAR(64), @affinity64mask NVARCHAR(1024)--, @cpuover32 int
DECLARE @bpool_consumer bit
DECLARE @allow_xpcmdshell bit
DECLARE @custompath NVARCHAR(500) = NULL
DECLARE @affined_cpus int
DECLARE @langid smallint
DECLARE @lpim bit, @lognumber int, @logcount int
DECLARE @query NVARCHAR(1000)
DECLARE @diskfrag bit
DECLARE @accntsqlservice NVARCHAR(128)
DECLARE @maxservermem bigint, @systemmem bigint
DECLARE @mwthreads_count int
DECLARE @ifi bit
DECLARE @duration tinyint
DECLARE @adhoc smallint
DECLARE @gen_scripts bit 
DECLARE @ixfrag bit
DECLARE @ixfragscanmode VARCHAR(8) 
DECLARE @logdetail bit 
DECLARE @spn_check bit 
DECLARE @dbcmptlevel int

-- With the variables declared we then set them. You can alter these values for different checks. The instructions will show where you should do this.

-- Set @dbScope to the appropriate list of database IDs if there's a need to have a specific scope for database specific checks.
-- Valid input should be numeric value(s) between single quotes, as follows: '1,6,15,123'
-- Leave NULL for all databases
SELECT @dbScope = NULL -- (NULL = All DBs; '<database_name>')

-- Set @ptochecks to OFF if you want to skip more performance tuning and optimization oriented checks.
SELECT @ptochecks = 1 -- 1 for ON 0 for OFF

-- Set @duration to the number of seconds between data collection points regarding perf counters, waits and latches. -- Duration must be between 10s and 255s (4m 15s), with a default of 90s.
SELECT @duration = 90

-- Set @logdetail to OFF if you want to get just the summary info on issues in the Errorlog, rather than the full detail.
SELECT @logdetail = 0 --(1 = ON; 0 = OFF)

-- Set @diskfrag to ON if you want to check for disk physical fragmentation. 
--	Can take some time in large disks. Requires elevated privileges.
--	See https://support.microsoft.com/help/3195161/defragmenting-sql-server-database-disk-drives
SELECT @diskfrag = 0 --(1 = ON; 0 = OFF)

-- Set @ixfrag to ON if you want to check for index fragmentation. 
--	Can take some time to collect data depending on number of databases and indexes, as well as the scan mode chosen in @ixfragscanmode.
SELECT @ixfrag = 0 --(1 = ON; 0 = OFF)

-- Set @ixfragscanmode to the scanning mode you prefer. 
-- 	More detail on scanning modes available at https://docs.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-index-physical-stats-transact-sql
SELECT @ixfragscanmode = 'LIMITED' --(Valid inputs are DEFAULT, NULL, LIMITED, SAMPLED, or DETAILED. The default (NULL) is LIMITED)

-- Set @bpool_consumer to OFF if you want to list what are the Buffer Pool Consumers from Buffer Descriptors. 
-- Mind that it may take some time in servers with large caches.
SELECT @bpool_consumer = 1 -- 1 for ON 0 for OFF

-- Set @spn_check to OFF if you want to skip SPN checks.
SELECT  @spn_check = 0 --(1 = ON; 0 = OFF)

-- Set @gen_scripts to ON if you want to generate index related scripts.
-- 	These include drops for Duplicate, Redundant, Hypothetical and Rarely Used indexes, as well as creation statements for FK and Missing Indexes.
SELECT @gen_scripts = 0 -- 1 for enable 0 for disable

-- Set @allow_xpcmdshell to OFF if you want to skip checks that are dependant on xp_cmdshell. 
-- Note that original server setting for xp_cmdshell would be left unchanged if tests were allowed.
SELECT @allow_xpcmdshell = 1 -- 1 for enable 0 for disable

-- Set @custompath below and set the custom desired path for .ps1 files. 
-- 	If not, default location for .ps1 files is the Log folder.
SELECT @custompath = NULL

-- These values are gathered for when they are needed
SELECT @langid = lcid FROM sys.syslanguages WHERE name = @@LANGUAGE
SELECT @adhoc = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'optimize for ad hoc workloads';
SELECT @masterpid = principal_id FROM master.sys.database_principals (NOLOCK) WHERE sid = SUSER_SID()
SELECT @instancename = CONVERT(VARCHAR(128),SERVERPROPERTY('InstanceName')) 
SELECT @server = RTRIM(CONVERT(VARCHAR(128), SERVERPROPERTY('MachineName')))
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff)
SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff)
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff)
SELECT @clustered = CONVERT(bit,ISNULL(SERVERPROPERTY('IsClustered'),0))

-- There are some variables that get passed from one check to another. This is easy in the stored procedure but won't work in the Notebook so we have to create a table in tempdb and read them from there

IF NOT EXISTS (SELECT [object_id]
	FROM tempdb.sys.objects (NOLOCK)
	WHERE [object_id] = OBJECT_ID('tempdb.dbo.dbvars'))
	BEGIN
	CREATE TABLE tempdb.dbo.dbvars(VarName VarChar(256),VarValue VarChar(256))
	END

SELECT @ostype = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'ostype');
SELECT @osver = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'osver');
SELECT @affined_cpus = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'affined_cpus');
SELECT @psavail = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'psavail');
SELECT @accntsqlservice = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'accntsqlservice');
SELECT @maxservermem = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'maxservermem');
SELECT @systemmem = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'systemmem');
SELECT @mwthreads_count = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'mwthreads_count');
SELECT @ifi = (SELECT VarValue FROM tempdb.dbo.dbvars WHERE VarName = 'ifi');

IF @sqlmajorver > 10
BEGIN
	DECLARE @IsHadrEnabled tinyint
	SELECT @IsHadrEnabled = CASE WHEN SERVERPROPERTY('EngineEdition') = 8 THEN 1 ELSE CONVERT(tinyint, SERVERPROPERTY('IsHadrEnabled')) END;
END

-- The T-SQL for the Check starts below

"@
# We don't need the first or the last as they are only required for the sp
$Cells = foreach ($Chunk in $SplitSQL[1..($SplitSQL.Length -2)]) {

    if ($Chunk.Trim().StartsWith('--- #sponly#')) { 
        # Ignore this tag
    }
    elseif ($Chunk.trim().StartsWith('---')) {  
        ## This is a text block
        $MarkDown = $Chunk.Trim().Replace('-- ', '').replace('*/','')
        New-ADSWorkBookCell -Type Text -Text $MarkDown
    }
    else {
        ## This is a code block
        try {
            $Code = $GlobalVariables + $Chunk.Trim()
            New-ADSWorkBookCell -Type Code -Text $Code  -Collapse
        }
        catch {
            Write-Warning "Gah it went wrong"
        }
    }
}

# Create the notebook
New-ADSWorkBook -Type SQL -Path .\BPCheck\DynamicBPCheck.ipynb -cells $Cells

# Open the notebook
azuredatastudio.cmd .\BPCheck\DynamicBPCheck.ipynb
