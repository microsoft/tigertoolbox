# Canary notebooks

This chapter contains a set of notebooks that app-deploy a series of 'canary notebooks' and sets up Kubernetes cronjobs to run the 'canary notebooks' on a schedule.

- A 'canary notebook' exercises an end-to-end scenario in the Big Data Cluster in the manner a user of the Big Data Cluster would.
- The goal of the 'canary notebook' is to provide a failure signal should the end-to-end scenario that it performs fail to succeed, this gives the cluster administrator early warning there may be an issue to troubleshoot.
- The notebooks in this chapter ensure the failure (and success) signals are stored in a database called 'runner' in the master and data pool.
- The notebooks in this chapter ensure the output results of each canary notebook execution are stored in the Storage Pool.
- The notebooks in this chapter deploy a Grafana dashboard that visualizes the status of all the canaries and generates an alert should several canary failure signals occur over a window of time.
- To receive notifications of these alerts, configure a 'Notification Channel' in Grafana.

[Home](../readme.md)

## Notebooks in this Chapter
