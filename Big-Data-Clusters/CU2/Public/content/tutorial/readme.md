![](graphics/microsoftlogo.png)

# Lab: Big Data Clusters for SQL Server - Architecture (CTP 3.2)

#### <i>A Microsoft Course from the SQL Server team</i>

<p style="border-bottom: 1px solid lightgrey;"></p>

<img style="float: left; margin: 0px 15px 15px 0px;" src="https://github.com/Microsoft/sqlworkshops/blob/master/graphics/textbubble.png?raw=true"> <h2><a name="about">About this Lab</a></h2>

Welcome to this Microsoft solutions Lab  on the architecture on Big Data Clusters for SQL Server. As part of <a href="https://github.com/Microsoft/sqlworkshops/tree/master/sqlserver2019bigdataclusters" target="_blank">a larger complete Workshop</a>, you'll experiment with Big Data Clusters for SQL Server (BDC), and how you can use it to implement large-scale data processing and machine learning.

This Lab assumes you have a full understanding the concepts of big data analytics, the technologies (such as containers, Kubernetes, Spark and HDFS, machine learning, and other technologies) that you will use throughout the Lab, the architecture of a BDC. <a href="https://github.com/microsoft/sqlworkshops/tree/master/sqlserver2019bigdataclusters" target="_blank">If you are familiar with these topics, you can take a complete course here</a>.

In this Lab you'll learn how to create external tables over other data sources to unify your data, and how to use Spark to run big queries over your data in HDFS or do data preparation. You'll review a complete solution for an end-to-end scenario, with a focus on how to extrapolate what you have learned to create other solutions for your organization.

<p style="border-bottom: 1px solid lightgrey;"></p>

<img style="float: left; margin: 0px 15px 15px 0px;" src="https://github.com/Microsoft/sqlworkshops/blob/master/graphics/owl.png?raw=true"> <h2><a name="prereqs">Before Taking this Lab</a></h2>

This Lab expects that you understand data structures and working with SQL Server and computer networks. This Lab does not expect you to have any prior data science knowledge, but a basic knowledge of statistics and data science is helpful in the Data Science sections. Knowledge of SQL Server, Azure Data and AI services, Python, and Jupyter Notebooks is recommended. AI techniques are implemented in Python packages. Solution templates are implemented using Azure services, development tools, and SDKs. You should have a basic understanding of working with the Microsoft Azure Platform.

<b>▶</b> You need to have all of the <a href="https://github.com/microsoft/sqlworkshops/blob/master/sqlserver2019bigdataclusters/SQL2019BDC/00%20-%20Prerequisites.md" target="_blank">prerequisites completed</a> before taking this Lab. 

<b>▶</b> You need a full Big Data Cluster for SQL Server up and running, and have identified the connection endpoints, with all security parameters. <a href="https://docs.microsoft.com/en-us/sql/big-data-cluster/deployment-guidance?view=sqlallproducts-allversions" target="_blank">You find out how to do that here</a>.

<p style="border-bottom: 1px solid lightgrey;"></p>

<img style="float: left; margin: 0px 15px 15px 0px;" src="https://github.com/Microsoft/sqlworkshops/blob/master/graphics/bookpencil.png?raw=true"> <h2><a name="modules">Lab Notebooks</a></h2>

<p>You will work through six Jupyter Notebooks using the Azure Data Studio tool. Download them and open them in Azure Data Studio, running only one cell at a time.</p> 

## Notebooks in this Chapter
