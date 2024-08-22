# Telco Network Builder (TNB) deployment test procedure

This repo contains sample packages for **Telco Network Builder (TNB)** tests and procedures to deploy some demo NFs (with multus networks) using TNB. Following architecture is being implemented and tested in this setup using Telco Network Builder ([TNB](https://console.aws.amazon.com/tnb/)). In this test procedure, we shall deploy 2 Demo Network Functions (NF's) on a EKS cluster containing 2 EKS Managed NodeGroup (with 1 Multus subnet) in each Availability zone.

![Test-Architecture](images/TNB-Sample-Config.png)

## Pre-Requisite

Using Cloudformation - please create IAM roles needed for TNB using the CloudFormation template [tnb-iam-roles.yaml](tnb-iam-roles/tnb-iam-roles.yaml)..
This CloudFormation template creates IAM roles for EKS Cluster, EKS Node Role for EKS Managed Node Group, Multus Role and LifecycleHook role.
Please note these artifacts use AWS "us-west-2" region, kindly update the NSD file with the desired region of your choice, Availability Zones (two) and your [SSH Keypair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html) name.
Additionally the [hook scripts](./Network-Package/hooks/postCreate.sh) must be adjusted to your environment (e.g. region) to execute the appropriate post steps.

## Test Procedure

1. Create a zip archive of the content of [Function-Package-NF1 folder](./Function-Package-NF1/) to a zip file e.g. Function-Package-CSAR-NF1.zip. Similarly create a zip archive of the content of [Function-Package-NF2 folder](./Function-Package-NF2/) to a zip file e.g. Function-Package-CSAR-NF2.zip and then create a zip archive of the content of [Network-Package folder](./Network-Package/) to a zip file e.g. Network-Package.zip. Please ensure while creating the zip files - the vnfd.yaml/Artifacts and nsd.yaml/Artifacts are in the root directory of the corresponding Function-Package and Network-Package zip files.

2. Create 2 Function Packages on TNB using ***Function-Package-CSAR-NF1.zip*** and ***Function-Package-CSAR-NF2.zip*** zip archives created in the previous step.
   To create the Function Package using AWS Console, navigate to Telco Network Builder -> Function Packages -> Create Function Package   -> Select the CSAR zip file -> Next and then Create.

   To create the Function packages using AWS CLI (e.g from Cloud9) - please use the following CLI commands -

   ```sh
   AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
   fp1_id=$(aws tnb create-sol-function-package | jq -r '.id')

   aws tnb put-sol-function-package-content \
   --vnf-pkg-id ${fp1_id} \
   --content-type application/zip \
   --file "fileb://Function-Package-NF1.zip" \
   --endpoint-url "https://tnb.${AWS_REGION}.amazonaws.com" \
   --region ${AWS_REGION}
   ```

   ```sh
   fp2_id=$(aws tnb create-sol-function-package | jq -r '.id')

   aws tnb put-sol-function-package-content \
   --vnf-pkg-id ${fp2_id} \
   --content-type application/zip \
   --file "fileb://Function-Package-NF2.zip" \
   --endpoint-url "https://tnb.${AWS_REGION}.amazonaws.com" \
   --region ${AWS_REGION}
   ```

3. Create Network Package on TNB using ***Network-Package-CSAR.zip*** (created in Step 1) that contains the Network Service Descriptor (NSD) containing the AWS Infra and NF Helm deployment. To create the Network package using AWS console, navigate to Telco Network Builder -> Network Packages -> Create Network Package -> Select the CSAR zip file -> Next -> validate the parameter values and then select Create.

   To create the Network package using AWS CLI (e.g from Cloud9) - please use the following CLI commands -

   ```sh
   np_id=$(aws tnb create-sol-network-package  | jq -r '.id')
   aws tnb put-sol-network-package-content --nsd-info-id $np_id --content-type application/zip --file "fileb://Network-Package.zip" --region ${AWS_REGION} --endpoint-url  "https://tnb.${AWS_REGION}.amazonaws.com"
   ```

4. Select the created Network Package and "Create Network Instance"

   To create a Network instance using AWS CLI (e.g from Cloud9) - please use the following CLI commands -

   ```sh
   ni_id=$(aws tnb create-sol-network-instance --nsd-info-id $np_id --ns-name "My-Network1" --ns-description "Network Instance1 for the Sample NF" | jq -r '.id')
   ```

5. Select the created Network Instance and select "Actions -> Instantiate" to start deployment of the Network Instance, i.e. creation of AWS infra (can be seen in CloudFormation), execute post-steps defined in the hook scripts in the Network package -  WhereAbouts installation, NAD creation & LB controller installation and finally the corresponding NF deployments (helm install of NF packages). At this step - ensure the Availability Zones are per your AWS region and SSH Keypair name is one created in the Pre-requisites module.

   To instantiate the Network instance using AWS CLI (e.g from Cloud9) - please use the following CLI commands -

   ```sh
   aws tnb instantiate-sol-network-instance --ns-instance-id $ni_id
   ```

6. Connect to the Cloudshell/Cloud9 and then install the kubectl, helm and other tools using the following commands -

   ```sh
   sudo curl --silent --location -o installK8sTools.sh https://raw.githubusercontent.com/sudhshet/myAwsRepo/main/installK8sTools.sh
   sudo chmod +x installK8sTools.sh
   ./installK8sTools.sh
   ```

   ```sh
   eksCluster=`eksctl get cluster |grep tnbEksClusterni| awk '{print $1}'`
   aws eks update-kubeconfig --region ${AWS_REGION} --name $eksCluster
   ```

7. Check if NF pods are running on the cluster after the Network Instance instantiation is completed -

   ```sh
   kubectl get pods -A
   ```

   Output of the command should be as follows -

   ```sh
   [cloudshell-user@ip-10-130-40-1 ~]$ kubectl get pods -A
   NAMESPACE     NAME                                                        READY   STATUS    RESTARTS      AGE
   default       tnbdemonf1ni0a14b11e0c7a6a064-multitool-89cb5bcb9-889tb     1/1     Running   0             12m
   default       tnbdemonf1ni0a14b11e0c7a6a064-multitool-89cb5bcb9-mkvmz     1/1     Running   0             12m
   default       tnbdemonf1ni0a14b11e0c7a6a064-nginx-759c78675c-pmpvr        1/1     Running   0             12m
   default       tnbdemonf1ni0a14b11e0c7a6a064-nginx-759c78675c-rvz2q        1/1     Running   0             12m
   default       tnbdemonf1ni0a14b11e0c7a6a064-sctpserver-5f4d9585b5-dmqdx   1/1     Running   0             12m
   default       tnbdemonf1ni0a14b11e0c7a6a064-sctpserver-5f4d9585b5-mpqgl   1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-multitool-697c97f5f4-gktsv    1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-multitool-697c97f5f4-k4m5v    1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-nginx-5cccc896d9-5mst9        1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-nginx-5cccc896d9-khpgd        1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-sctpserver-59dc7bb966-7ktk9   1/1     Running   0             12m
   default       tnbdemonf2ni0a14b11e0c7a6a064-sctpserver-59dc7bb966-b84v5   1/1     Running   0             12m
   kube-system   aws-load-balancer-controller-79d779594c-b6n5z               1/1     Running   0             12m
   kube-system   aws-load-balancer-controller-79d779594c-k8cld               1/1     Running   0             12m
   kube-system   aws-node-fgbbd                                              2/2     Running   0             16m
   kube-system   aws-node-vjbdv                                              2/2     Running   0             15m
   kube-system   coredns-8fd5d4478-hzm7j                                     1/1     Running   0             21m
   kube-system   coredns-8fd5d4478-lnszn                                     1/1     Running   0             21m
   kube-system   ebs-csi-controller-56ccf94676-wbtkx                         6/6     Running   0             18m
   kube-system   ebs-csi-controller-56ccf94676-xzgzg                         6/6     Running   0             18m
   kube-system   ebs-csi-node-7954t                                          3/3     Running   0             15m
   kube-system   ebs-csi-node-m89nc                                          3/3     Running   0             16m
   kube-system   kube-multus-ds-nw8dg                                        1/1     Running   1 (13m ago)   13m
   kube-system   kube-multus-ds-rstkk                                        1/1     Running   1 (13m ago)   13m
   kube-system   kube-proxy-255kk                                            1/1     Running   0             16m
   kube-system   kube-proxy-njmfm                                            1/1     Running   0             15m
   kube-system   whereabouts-7ntkh                                           1/1     Running   0             12m
   kube-system   whereabouts-wgv87                                           1/1     Running   0             12m
   ```

8. Validate if Multus interfaces are configured correctly on the pods -

   ```sh
   [cloudshell-user@ip-10-130-40-1 ~]$ kubectl exec -ti tnbdemonf1ni0a14b11e0c7a6a064-multitool-89cb5bcb9-889tb  -- ip a
   1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
      link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
      inet 127.0.0.1/8 scope host lo
         valid_lft forever preferred_lft forever
      inet6 ::1/128 scope host 
         valid_lft forever preferred_lft forever
   3: eth0@if11: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc noqueue state UP group default 
      link/ether 02:a9:23:a6:82:bb brd ff:ff:ff:ff:ff:ff link-netnsid 0
      inet 10.0.2.193/32 scope global eth0
         valid_lft forever preferred_lft forever
      inet6 fe80::a9:23ff:fea6:82bb/64 scope link 
         valid_lft forever preferred_lft forever
   4: net1@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default 
      link/ether 06:5a:f6:d2:ae:1d brd ff:ff:ff:ff:ff:ff link-netnsid 0
      inet 10.0.4.11/24 brd 10.0.4.255 scope global net1
         valid_lft forever preferred_lft forever
      inet6 fe80::65a:f600:4d2:ae1d/64 scope link 
         valid_lft forever preferred_lft forever
   [cloudshell-user@ip-10-130-40-1 ~]$ 
   ```

Please follow the [link](./IPv6/README.md) for artifacts and test procedure to validate IPv6 capabilites (multus) with TNB.

Please follow the [link](./SRIOV-DPDK/README.md) for artifacts and test procedure to validate SRIOV DPDK interface configuration with TNB.

Here is [hook script example](./EFS/hooks/postCreate.sh#L47) that shows installation of EKS EFS CSI Driver add-on with TNB.

## Cleanup

To cleanup the environment via AWS Console, go to Telco Network Builder

1. Navigate to Networks, select the Network Instance ID -> Actions -> Terminate. Confirm by copying the Network instance id.
2. Once the termination is complete, delete the Network Instance by selecting Actions -> Delete
3. To delete the Network package, it has to be disabled first, select Network Packages -> Select the Network Package ID -> Actions -> Disable
4. Delete the Network package by selecting Network Packages -> Select the Network Package ID -> Actions -> Delete
5. To delete each of the Function packages, it has to be disabled first, select Function Packages -> Select the Function Package ID -> Actions -> Disable
6. Delete the Function packages by selecting Function Packages -> Select the Function Package ID -> Actions -> Delete

To cleanup the environment using AWS CLI - use the following commands -

```sh
# Terminate Network Instance
aws tnb terminate-sol-network-instance --ns-instance-id $ni_id

# Delete Network Instance
aws tnb delete-sol-network-instance --ns-instance-id $ni_id

# Disable Network Package
aws tnb update-sol-network-package --nsd-info-id $np_id --nsd-operational-state DISABLED

# Delete Network Package
aws tnb delete-sol-network-package \
--nsd-info-id $np_id \
--endpoint-url "https://tnb.${AWS_REGION}.amazonaws.com" \
--region ${AWS_REGION}

# Disable Function Package1
aws tnb update-sol-function-package --vnf-pkg-id $fp1_id --operational-state DISABLED

# Delete Function Package1
aws tnb delete-sol-function-package \
--vnf-pkg-id $fp1_id \
--endpoint-url "https://tnb.${AWS_REGION}.amazonaws.com" \
--region ${AWS_REGION}

# Disable Function Package2
aws tnb update-sol-function-package --vnf-pkg-id $fp2_id --operational-state DISABLED

# Delete Function Package2
aws tnb delete-sol-function-package \
--vnf-pkg-id $fp2_id \
--endpoint-url "https://tnb.${AWS_REGION}.amazonaws.com" \
--region ${AWS_REGION}
```

Delete the CloudFormation stack that created the IAM roles needed for TNB.
