# Operations and Support Jupyter Book - SQL Server 2019 Big Data Clusters

This Jupyter Book of executable notebooks (.ipynb) is a companion for SQL Server 2019 to assist in operating and supporting Big Data Clusters.

Each notebook is designed to check for its own dependencies.  A 'run all cells' will either complete successfully, or will error out with a hyperlinked 'SUGGEST' to another notebook to resolve the missing dependency.  Follow the 'SUGGEST' hyperlink to the subsequent notebook, press 'run all cells', and upon success return back to the original notebook, and press 'run all cells' again.

Once all dependencies are installed, but 'run all cells' fails, each notebook will analyze results and where possible, produce a hyperlinked 'SUGGEST' to another notebook to furthe aid in resolving the issue.

NOTE: Currently the intra book hyperlinks do not work if this Jupyter Book is hosted on a file share. To use the intra book hyperlinks please copy the book locally.

## Chapters

1. [Troubleshooters](troubleshooters/readme.md) - notebooks hyper-linked from the `Big Data Cluster Dashboard` in `Azure Data Studio`.
2. [Log Analyzers](log-analyzers/readme.md) - notebooks linked from the troubleshooters, that get and analyze logs for known issues.
3. [Diagnose](diagnose/readme.md) - notebooks for diagnosing situations with a Big Data Cluster.
4. [Repair](repair/readme.md) - notebooks to perform repair actions for known issues in a Big Data Cluster.
5. [Monitor Big Data Cluster](monitor-bdc/readme.md) - notebooks for monitoring the Big Data Cluster using the `azdata` command line tool.
6. [Monitor Kubernetes](monitor-k8s/readme.md) - notebooks for monitoring a the Kubernetes cluster hosting a Big Data Cluster.
7. [Logs](log-files/readme.md) - notebooks for display log files from a Big Data Cluster.
8. [Sample](sample/readme.md) - notebooks demonstrating Big Data Cluster features and functionality.
9. [Install](install/readme.md) - notebooks to install prerequisites for other notebooks.
10. [Common](common/readme.md) - notebooks commonly linked from other notebooks, such as azdata login / logout.
