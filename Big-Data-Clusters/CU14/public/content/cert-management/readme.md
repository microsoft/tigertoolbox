# A set of notebooks used for Certificate Management

The notebooks in this chapter can be used to create a self-signed root certificate authority (or allow for one to be uploaded), and then use that root CA to create and sign certificates for each external endpoint in a Big Data Cluster.

After running the notebook in this chapter, and installing the Root CA certificate locally, all connections to the Big Data Cluster can be made securely (i.e. the internet browser will indicate "This Connection is Secure").  The following notebook can be used to install the Root CA certificate locally on this machine.

- CER010 - Install generated Root CA locally

## Run the notebooks in a sequence

These two notebooks run the required notebooks in this chapter in a sequence in a single 'run all cells' button press.

- CER100 - Configure Cluster with Self Signed Certificates
- CER101 - Configure Cluster with Self Signed Certificates using existing Root CA

The first notebook (CER100) will first generate a Root CA certificate.  The 2nd notebook (CER101) will use an already existing Root CA downloaded and upload using:

- CER002 - Download existing Root CA certificate
- CER003 - Upload existing Root CA certificate

## Details

- By default, the Big Data Cluster cluster generates its own Root CA certificate and all the certificates used inside the cluster are signed with this Root CA certificate. External clients connecting to cluster endpoints will not have this internal Root CA installed and this leads to the certificate verification related warnings on clients (internet browsers etc.) and the need to use the --insecure option with tools like CURL.

- It is better if the certificates for the external endpoints in the Big Data Cluster can be provided and installed in the containers hosting the endpoint services, most preferably using your own trusted CA to sign these certificates and then install the CA chain inside the cluster.  The notebooks in this chapter aid in this process by creating a self-signed Root CA certificate and then creating certificates for each external endpoint signed by the self-signed Root CA certificate.

- The openssl certificate tracking database is created in the `controller` in the `/var/opt/secrets/test-certificates` folder.  Here a record is maintained of each certificate that has been issued for tracking purposes.



[Home](../readme.md)

## Notebooks in this Chapter

 - [CER001 - Generate a Root CA certificate](../cert-management/cer001-create-root-ca.ipynb)
 - [CER002 - Download existing Root CA certificate](../cert-management/cer002-download-existing-root-ca.ipynb)
 - [CER003 - Upload existing Root CA certificate](../cert-management/cer003-upload-existing-root-ca.ipynb)
 - [CER004 - Download and Upload existing Root CA certificate](../cert-management/cer004-download-upload-existing-root-ca.ipynb)
 - [CER005 - Install new Root CA certificate](../cert-management/cer005-install-existing-root-ca.ipynb)
 - [CER010 - Install generated Root CA locally](../cert-management/cer010-install-generated-root-ca-locally.ipynb)
 - [CER020 - Create Management Proxy certificate](../cert-management/cer020-create-management-service-proxy-cert.ipynb)
 - [CER021 - Create Knox certificate](../cert-management/cer021-create-knox-cert.ipynb)
 - [CER022 - Create App Proxy certificate](../cert-management/cer022-create-app-proxy-cert.ipynb)
 - [CER023 - Create Master certificates](../cert-management/cer023-create-master-certs.ipynb)
 - [CER024 - Create Controller certificate](../cert-management/cer024-create-controller-cert.ipynb)
 - [CER025 - Upload existing Management Proxy certificate](../cert-management/cer025-upload-management-service-proxy-cert.ipynb)
 - [CER026 - Upload existing Gateway certificate](../cert-management/cer026-upload-knox-cert.ipynb)
 - [CER027 - Upload existing App Service Proxy certificate](../cert-management/cer027-upload-app-proxy-cert.ipynb)
 - [CER028 - Upload existing Master certificates](../cert-management/cer028-upload-master-certs.ipynb)
 - [CER028 - Upload existing Contoller certificate](../cert-management/cer029-upload-controller-cert.ipynb)
 - [CER030 - Sign Management Proxy certificate with generated CA](../cert-management/cer030-sign-service-proxy-generated-cert.ipynb)
 - [CER031 - Sign Knox certificate with generated CA](../cert-management/cer031-sign-knox-generated-cert.ipynb)
 - [CER032 - Sign App-Proxy certificate with generated CA](../cert-management/cer032-sign-app-proxy-generated-cert.ipynb)
 - [CER033 - Sign Master certificates with generated CA](../cert-management/cer033-sign-master-generated-certs.ipynb)
 - [CER034 - Sign Controller certificate with cluster Root CA](../cert-management/cer034-sign-controller-generated-cert.ipynb)
 - [CER040 - Install signed Management Proxy certificate](../cert-management/cer040-install-service-proxy-cert.ipynb)
 - [CER041 - Install signed Knox certificate](../cert-management/cer041-install-knox-cert.ipynb)
 - [CER042 - Install signed App-Proxy certificate](../cert-management/cer042-install-app-proxy-cert.ipynb)
 - [CER043 - Install signed Master certificates](../cert-management/cer043-install-master-certs.ipynb)
 - [CER044 - Install signed Controller certificate](../cert-management/cer044-install-controller-cert.ipynb)
 - [CER050 - Wait for BDC to be Healthy](../cert-management/cer050-wait-cluster-healthy.ipynb)
 - [CER100 - Configure Cluster with Self Signed Certificates](../cert-management/cer100-create-root-ca-install-certs.ipynb)
 - [CER101 - Configure Cluster with Self Signed Certificates using existing Root CA](../cert-management/cer101-use-root-ca-install-certs.ipynb)
 - [CER102 - Configure Cluster with Self Signed Certificates using existing Big Data Cluster CA](../cert-management/cer102-use-bdc-ca-install-certs.ipynb)
 - [CER103 - Configure Cluster with externally signed certificates](../cert-management/cer103-upload-install-certs.ipynb)
