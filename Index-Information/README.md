Change log and other information available at http://aka.ms/SQLInsights - SQL Swiss Army Knife Series

**view_IndexInformation**

**Purpose:** Output index information on all databases, including duplicate, redundant, rarely used and unused indexes.

In the output, you will find the following information:
-  Information on all rowstore and columnstore indexes.
-  Information on all In-Memory Hash and Range indexes.
-  Information on all heaps.
-  Unused indexes (meaning zero reads). These can possibly be dropped or disabled. Only looks at non-clustered and non-clustered columnstore indexes. Excludes primary keys, unique constraints and alternate keys.
  -  Includes unused indexes which have been updated since the server last started. These are adding overhead to the system in the sense they are getting updates, but are never used for reads (and here is why knowing if one or more business cycles executed is important).
  -  Includes unused indexes that also have not been updated since the server last started.
-  Rarely used indexes (Writes to Reads ratio less than 5 percent). These can possibly be dropped or disabled. Only looks at non-clustered and non-clustered columnstore indexes. Excludes primary keys, unique constraints and alternate keys.
-  Duplicate indexes. Looks at clustered, non-clustered, clustered and non-clustered columnstore indexes.
  -  From the Duplicate indexes list, separately output which indexes should be removed. 
     **Note:** It is possible that a clustered index (unique or not) is among the duplicate indexes to be dropped, namely if a non-clustered primary key exists on the table. In this case, make the appropriate changes in the clustered index (making it unique and/or primary key in this case), and drop the non-clustered instead.
  -  From the Duplicate indexes list, look for hard-coded (hinted) references in all sql modules. If you drop such an index your query that explicitely references it will fail unless you change the reference to another index, or remove the reference all together.
-  Redundant Indexes. Excludes unique constraints.
-  Large IX Keys (over 900 bytes in the key).
-  Low Fill Factor (less than 80 percent)
-  Non-Unique Clustered indexes.

In addition, drop scripts are generated for unused, rarely used and duplicate indexes.

**view_IndexInformation_CurrentDB**

**Purpose:** Output index information for current database, including duplicate, redundant, rarely used and unused indexes.

In the output, you will find the following information:
-  Information on all rowstore and columnstore indexes.
-  Information on all In-Memory Hash and Range indexes.
-  Information on all heaps.
-  Unused indexes (meaning zero reads). These can possibly be dropped or disabled. Only looks at non-clustered and non-clustered columnstore indexes. Excludes primary keys, unique constraints and alternate keys.
  -  Includes unused indexes which have been updated since the server last started. These are adding overhead to the system in the sense they are getting updates, but are never used for reads (and here is why knowing if one or more business cycles executed is important).
  -  Includes unused indexes that also have not been updated since the server last started.
-  Rarely used indexes (Writes to Reads ratio less than 5 percent). These can possibly be dropped or disabled. Only looks at non-clustered and non-clustered columnstore indexes. Excludes primary keys, unique constraints and alternate keys.
-  Duplicate indexes. Looks at clustered, non-clustered, clustered and non-clustered columnstore indexes.
  -  From the Duplicate indexes list, separately output which indexes should be removed. 
     **Note:** It is possible that a clustered index (unique or not) is among the duplicate indexes to be dropped, namely if a non-clustered primary key exists on the table. In this case, make the appropriate changes in the clustered index (making it unique and/or primary key in this case), and drop the non-clustered instead.
  -  From the Duplicate indexes list, look for hard-coded (hinted) references in all sql modules. If you drop such an index your query that explicitely references it will fail unless you change the reference to another index, or remove the reference all together.
-  Redundant Indexes. Excludes unique constraints.
-  Large IX Keys (over 900 bytes in the key).
-  Low Fill Factor (less than 80 percent)
-  Non-Unique Clustered indexes.

In addition, drop scripts are generated for unused, rarely used and duplicate indexes.

**view_HypObjects**

**Purpose:** List all Hypothetical objects and generates drop scripts.
