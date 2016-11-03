Change log and other information available at http://aka.ms/SQLInsights - SQL Swiss Army Knife Series

**Purpose:** Gets an overview of the current VLF status in all databases of a given instance, and if the number of VLFs are above a pre-determined threshold, also makes a suggestion of how many and how large the VLFs should be for that particular database.

In the output, you will find the following information:
-  The database name;
-  The transaction log current size and the size it will be after applying suggested changes. Both in MB;
-  The current number of VLFs and the number of VLFs that will remain after applying suggested changes;
-  The amount of growth iterations necessary to get to the suggested size;
-  The transaction log initial size and the autogrow size that should be set;

In addition, a script is generated with the typical example steps needed to deal with the issue, depending on whether the database is in Simple recovery model or not.