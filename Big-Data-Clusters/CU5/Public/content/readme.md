# Operations and Support Jupyter Book - SQL Server 2019 Big Data Clusters (CU5)

This `Jupyter Book` of executable notebooks (.ipynb) is a companion for `SQL Server 2019` to assist in operating and supporting `Big Data Clusters`.

Each notebook is designed to check for its own dependencies.  A 'run all cells' will either complete successfully or will raise an exception with a hyperlinked 'HINT' to another notebook to resolve the missing dependency.  Follow the 'HINT' hyperlink to the subsequent notebook, press 'run all cells', and upon success return back to the original notebook, and 'run all cells'.

Once all dependencies are installed, but 'run all cells' fails, each notebook will analyze results and where possible, produce a hyperlinked 'HINT' to another notebook to further aid in resolving the issue.

## Coping with environmental change

The notebooks in this book are designed to abstract away environmental aspects:

    1. Running outside or inside the Big Data Cluster - The overlay network addresses will be used when a notebook is run inside the cluster, and when run outside the cluster, the addresses returned from `azdata bdc endpoint list` will be used.
    2. AZDATA_OPENSHIFT: Using Openshift - set the environment variable AZDATA_OPENSHIFT, to ensure the `oc` command is used instead of `kubectl`, and this will automatically workaround other compatibility issues.
    3. AZDATA_NAMESPACE: Using multiple Big Data Clusters in the same Kubernetes cluster - set AZDATA_NAMESPACE to target the correct cluster.  By default these notebooks will target the cluster whose Kubernetes namespace comes alphabetically first.

## Number convention for notebooks in a chapter

Some chapters are effectively self-contained applications.  These chapters use the following numbering convention for the contained notebooks.

The '100' notebook, i.e. NTB100, is usually the goto notebook to run in a chapter.

NTB000: Setup notebook
NTB001 - NTB499: The notebooks
NTB100 - NTB110: Notebooks that run other notebooks in chapter.  i.e. NTB100 is usually the notebok to run
NTB500 - NTB599: Tests.  Notebooks to test the (001 - 499) notebooks 
NTB600 - NTB699: Montioring.  Notebooks to monitor the (001 - 499) notebooks
NTB900 - NTB998: Troubleshooting.  Notebooks to troubleshoot the (001 - 499) notebooks
NTB999: Cleanup notebook

## Chapters

1. [Troubleshooters](troubleshooters/readme.md) - notebooks hyper-linked from the `Big Data Cluster Dashboard` in `Azure Data Studio`.
2. [Log Analyzers](log-analyzers/readme.md) - notebooks linked from the troubleshooters, that get and analyze logs for known issues.
3. [Diagnose](diagnose/readme.md) - notebooks for diagnosing situations with a `Big Data Cluster`.
4. [Repair](repair/readme.md) - notebooks to perform repair actions for known issues in a `Big Data Cluster`.
5. [Monitor Big Data Cluster](monitor-bdc/readme.md) - notebooks for monitoring the `Big Data Cluster` using the `azdata` command line tool.
6. [Monitor Kubernetes](monitor-k8s/readme.md) - notebooks for monitoring a the `Kubernetes` cluster hosting a `Big Data Cluster`.
7. [Logs](log-files/readme.md) - notebooks for display log files from a `Big Data Cluster`.
8. [Sample](sample/readme.md) - notebooks demonstrating `Big Data Cluster` features and functionality.
9. [Install](install/readme.md) - notebooks to install prerequisites for other notebooks.
10. [Certificate Management](cert-management/readme.md) - notebooks to manage certificates on `Big Data Cluster` endpoints.
11. [Common](common/readme.md) - notebooks commonly linked from other notebooks, such as `azdata login / logout`.
