**ReadTrace and SQL Nexus Analysis Queries**

Using [RML Utilities](https://www.microsoft.com/en-us/download/details.aspx?id=4511) (ReadTrace) to analyze your workloads?

Using [SQL Nexus](https://github.com/Microsoft/SqlNexus) to make sense of all the information collected by [PSSDiag](https://github.com/Microsoft/DiagManager) or SQLDiag?

Did you know the database that supports these tools holds much more infromation than the UI Reports provide?

The queries in the two scripts here allow you to tap into that rich information - be sure to check them out!

The scripts are:
-  **ReadTrace_Queries**: can be used in the database created by ReadTrace or SQLNexus alike. These tools normalize the queries as they're being processed into the datbase so that reports can be renedered. This also means that sometimes the normalized query can't be used for repro purposes directly.
-  **PerfStats_Queries**: can be used to collected information that is somewhat equivalent to the INteresting Events report in ReadTrace, but the source if the PerfStats script executed by PSSDiag/SQLDiag which is based on DMV collection.
