# A set of notebooks used for Certificate Management

The notebooks in this chapter can be used to create a self-signed root certificate authority (or allow for one to be uploaded), and then use that root CA to create and sign certificates for each external endpoint in a Big Data Cluster.

After running the notebook in this chapter, and installing the Root CA certificate locally, all connections to the Big Data Cluster can be made securely (i.e. the internet browser will indicate "This Connection is Secure").  The following notebook can be used to install the Root CA certificate locally on this machine.

- [CER010]()

## Run the notebooks in a sequence

These two notebooks run the required notebooks in this chapter in a sequence in a single 'run all cells' button press.

- [CER100]()
- [CER101]()

The first notebook (CER100) will first generate a Root CA certificate.  The 2nd notebook (CER101) will use an already existing Root CA downloaded and upload using:

- [CER002]()
- [CER003]()

## Details

- By default, the Big Data Cluster cluster generates its own Root CA certificate and all the certificates used inside the cluster are signed with this Root CA certificate. External clients connecting to cluster endpoints will not have this internal Root CA installed and this leads to the certificate verification related warnings on clients (internet browsers etc.) and the need to use the --insecure option with tools like CURL.

- It is better if the certificates for the external endpoints in the Big Data Cluster can be provided and installed in the containers hosting the endpoint services, most preferably using your own trusted CA to sign these certificates and then install the CA chain inside the cluster.  The notebooks in this chapter aid in this process by creating a self-signed Root CA certificate and then creating certificates for each external endpoint signed by the self-signed Root CA certificate.

- The openssl certificate tracking database is created in the `controller` in the `/var/opt/secrets/test-certificates` folder.  Here a record is maintained of each certificate that has been issued for tracking purposes.

[Home](../readme.md)

## Notebooks in this Chapter
- [CER001 - Generate a Root CA certificate](cer001-create-root-ca.ipynb)

- [CER002 - Download existing Root CA certificate](cer002-download-existing-root-ca.ipynb)

- [CER003 - Upload existing Root CA certificate](cer003-upload-existing-root-ca.ipynb)

- [CER004 - Download and Upload existing Root CA certificate](cer004-download-upload-existing-root-ca.ipynb)

- [CER010 - Install generated Root CA locally](cer010-install-generated-root-ca-locally.ipynb)

- [CER020 - Create Management Proxy certificate](cer020-create-management-service-proxy-cert.ipynb)

- [CER021 - Create Knox certificate](cer021-create-knox-cert.ipynb)

- [CER022 - Create App Proxy certificate](cer022-create-app-proxy-cert.ipynb)

- [CER023 - Create Controller certificate](cer023-create-controller-cert.ipynb)

- [CER030 - Sign Management Proxy certificate with generated CA](cer030-sign-service-proxy-generated-cert.ipynb)

- [CER031 - Sign Knox certificate with generated CA](cer031-sign-knox-generated-cert.ipynb)

- [CER032 - Sign App-Proxy certificate with generated CA](cer032-sign-app-proxy-generated-cert.ipynb)

- [CER033 - Sign Controller certificate with cluster Root CA](cer033-sign-controller-generated-cert.ipynb)

- [CER040 - Install signed Management Proxy certificate](cer040-install-service-proxy-cert.ipynb)

- [CER041 - Install signed Knox certificate](cer041-install-knox-cert.ipynb)

- [CER042 - Install signed App-Proxy certificate](cer042-install-app-proxy-cert.ipynb)

- [CER043 - Install signed Controller certificate](cer043-install-controller-cert.ipynb)

- [CER050 - Wait for BDC to be Healthy](cer050-wait-cluster-healthly.ipynb)

- [CER100 - Configure Cluster with Self Signed Certificates](cer100-create-root-ca-install-certs.ipynb)

- [CER101 - Configure Cluster with Self Signed Certificates using existing Root CA](cer101-use-root-ca-install-certs.ipynb)

