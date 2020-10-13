# Step by step Big Data Cluster deployment using Local Persistent Volumes

- A set of ordered notebooks to install a Big Data Cluster with Local Persistent Volumes.
- The notebooks allow for two types of storage, HDD for big data storage, typical for HDFS (hosted in the Storage Pool pods), and SSD typical for relational storage in the Data Pool pods.  Further the SSD storage matches to Persistent Volumes of different sizes.  Where the Data Poool persistent volumes are larger than the general purpose data and logs persistent volumes.
- NOTE: For local peristent volumes, the storage sizes are not enforced, they are effectively just tags for matching Peristent Volume Claims to Persistent Volumes.

[Home](../readme.md)

## Notebooks in this Chapter
