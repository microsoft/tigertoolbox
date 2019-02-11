---
Title: "SQL Server High Availability on Kubernetes"
Date: "2/9/2019"
Author: Sourabh Agarwal
Purpose: In this lab you will deploy multiple SQL Server pods along with Availability Groups on a Kubernetes Cluster in Azure using Azure Kubernetes Services
---
## SQL Server High Availability On Kubernetes Lab

1. Connecting to the kubernetes Kubernetes Cluster

2. Deploying SQL Server pods using kubectl and the SQL manifest file. For this deployment you'll be using the `SQl_Server_Deployment.yaml` file, which is available under `C:\Labs`. 
 
    1. Create Kubernetes secret for SQL Server SA password and Master Key Password. All SQL Server Pods use these passwords. In the following commands replace "YourStrongPassword" with a valid Strong Password within double quotes "":
  
        `kubectl create namespace ag1`   
          
        `kubectl create secret generic sql-secrets --from-literal=sapassword= <YourStrongPassword> --from-literal=masterkeypassword=<YourStrongPassword> -n ag1`
      
        > **Note:** This deployment uses Namespace ag1. If you'd like to use a different namespace, replace the namespace name "ag1" with a name of your choosing. 
  
    2. Deploy SQL Server pods using the `SQL_Server_Deployment.yaml` file. Deploy the SQL Server pods in the same namespace as the previous step. The default deployment uses namespace *ag1*. If you are using a different namespace, open the `SQL_Server_Deployment.yaml` file and replace **ALL** occurrences of "ag1".

        `Kubectl apply -f <"Localtion of SQL Server Deployment YAML file"> -n ag1`
  
        > **Note:** The script creates the SQL Server operator along with 3 SQL Server Pods with an Availability Group.     
        > The script also creates 5 kubernetes service (3 for the SQL Server pods, 1 for AG Primary Replica and 1 for AG Secondary Replica).    
        > The Primary Replica Service provides the same functionality as an AG listener, while the secondary replica service provides load balancing capability across the readable secondaries.    
        > It may take a few minutes (generally less than 5 minutes) for the entire deployment to finish.

    3. Execute the below command to get a list of all the deployments in your namespace: 
    
        `kubectl get all -n ag1`
        
     ![Kubectl_Get_all_output.jpg](./media/Kubectl_Get_all_output.jpg)
    
3. Connect to the SQL Server Primary Replica to create a database and add the database to the Availability Group.

    From the output of above command, identify the External IP address associated with the AG primary relica service.    
    The Service has the following naming convention - **svc/AGName-primary**.    
    Connect to the external IP and the password from step 2.1, using SSMS or Azure Data Studio.
  
    Open a new query window and run the following commands:
    
    ```SQL
    CREATE DATABASE TestDB1
    GO
    ALTER DATABASE TestDB1 SET RECOVERY FULL
    GO
    BACKUP DATABASE TestDB1 TO DISK = 'Nul'
    GO
    ALTER AVAILABILITY GROUP <AG_Name> ADD DATABASE TestDB1
    GO
    ```

    > **Note:** Replace the <AG_Name> in the script above with the name of your Availability Group.
 
4. Initiate Automatic Failover of the AG by crashing the Primary Replica of the AG. 
 
    Connect to the Primary Replica of the AG using the primary service IP and execute the below query:

    ```SQL
    SELECT @@SERVERNAME
    GO
    ```
 
    From a cmd window, execute the below command to crash the primary replica pod:
 
    `kubectl delete pod <primary_replica_pod_name> -n <namespace_name>`
    
    > **Note:** Please replace the Primary Replica Name from the output of the previous command. Also replace the <namespace_name> with the name of your namespace. 
    
    Killing the primary replica pod will initiate an automatic Failover of the AG to one of the synchronous secondary replicas. Reconnect to the Primary Replica IP and execute the below command again: 
    
    ```SQL
    SELECT @@SERVERNAME
    GO
    ```
