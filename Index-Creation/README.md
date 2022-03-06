**Purpose:** Looks for relevant missing indexes in SQL Server. Results are relevant if one or more business cycles have been executed.

In the output, you will find the following information:
-  Missing indexes with the highest user impact. The higher the score, higher is the anticipated improvement for user queries.
-  Possibly redundant indexes in above list, whcih provides an opportunity to do some index consolidation.
-  Index creation scripts.
