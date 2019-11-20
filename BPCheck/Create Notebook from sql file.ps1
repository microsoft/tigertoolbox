$RawSql = Get-Content .\BPCheck\Check_BP_Servers.sql -Raw

$SplitSQL = $RawSql -split '--------------------------------------------------------------------------------------------------------------------------------'

$GlobalVariables = @"
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
DECLARE @permstbl TABLE ([name] sysname)
DECLARE @permstbl_msdb TABLE ([id] tinyint IDENTITY(1,1), [perm] tinyint)
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
-- Does not include reserved memory in the memory manager
DECLARE @mwthreads_count int
DECLARE @ifi bit
DECLARE @duration tinyint
DECLARE @adhoc smallint
DECLARE @gen_scripts bit 
DECLARE @ixfrag bit = 1 --(1 = ON; 0 = OFF)
DECLARE @ixfragscanmode VARCHAR(8) = 'LIMITED' --(Valid inputs are DEFAULT, NULL, LIMITED, SAMPLED, or DETAILED. The default (NULL) is LIMITED)
DECLARE @logdetail bit = 0 --(1 = ON; 0 = OFF)

SELECT @masterpid = principal_id FROM master.sys.database_principals (NOLOCK) WHERE sid = SUSER_SID()

INSERT INTO @permstbl
SELECT a.name
FROM master.sys.all_objects a (NOLOCK) INNER JOIN master.sys.database_permissions b (NOLOCK) ON a.[OBJECT_ID] = b.major_id
WHERE a.type IN ('P', 'X') AND b.grantee_principal_id <>0 
AND b.grantee_principal_id <> 2
AND b.grantee_principal_id = @masterpid;

SELECT @instancename = CONVERT(VARCHAR(128),SERVERPROPERTY('InstanceName')) 
SELECT @server = RTRIM(CONVERT(VARCHAR(128), SERVERPROPERTY('MachineName')))
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff)
SELECT @sqlminorver = CONVERT(int, (@@microsoftversion / 0x10000) & 0xff)
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff)
SELECT @clustered = CONVERT(bit,ISNULL(SERVERPROPERTY('IsClustered'),0))
SELECT @dbScope = NULL -- (NULL = All DBs; '<database_name>')
SELECT @ptochecks = 1 -- 1 for enable 0 for disable
SELECT @bpool_consumer = 1 -- 1 for enable 0 for disable
SELECT @allow_xpcmdshell = 1 -- 1 for enable 0 for disable
SELECT @custompath = NULL
SELECT @langid = lcid FROM sys.syslanguages WHERE name = @@LANGUAGE
SELECT @diskfrag = 1
SELECT @duration = 90
SELECT @adhoc = CONVERT(bit, [value]) FROM sys.configurations WHERE [Name] = 'optimize for ad hoc workloads';
SELECT @gen_scripts = 0 -- 1 for enable 0 for disable
DECLARE @dbcmptlevel int
SELECT @ixfrag = 1 --(1 = ON; 0 = OFF)
SELECT @ixfragscanmode = 'LIMITED' --(Valid inputs are DEFAULT, NULL, LIMITED, SAMPLED, or DETAILED. The default (NULL) is LIMITED)
SELECT @logdetail = 0 --(1 = ON; 0 = OFF)

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


"@
# We don't need the first or the last as they are only required for the sp
$Cells = foreach ($Chunk in $SplitSQL[1..($SplitSQL.Length -2)]) {

    if ($Chunk.Trim().StartsWith('#sponly#') -or $Chunk.Trim().StartsWith('-- #sponly#')) { 
        # Ignore this tag
    }
    elseif ($Chunk.trim().StartsWith('--')) {  
        ## This is a text block
        $MarkDown = $Chunk.Trim().Replace('--', '').replace('*/','')
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

New-ADSWorkBook -Type SQL -Path .\BPCheck\DynamicBPCheck.ipynb -cells $Cells

azuredatastudio.cmd .\BPCheck\DynamicBPCheck.ipynb
