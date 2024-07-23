#!/bin/sh

set -e
#unset AWS_ACCESS_KEY_ID
#unset AWS_SECRET_ACCESS_KEY

echo $EKS_Cluster_Name
echo $currentregion

myRegion=$(echo $currentregion | sed 's/_/-/g')
echo $myRegion

# Query the cluster name based on tag passed from NSD
myEKS=`aws resourcegroupstaggingapi get-resources --tag-filters Key="Name",Values=$EKS_Cluster_Name --region $myRegion | jq '.ResourceTagMappingList[0].ResourceARN' | grep -o '[^\/]*$' | tr -d '"'`

# Update kubeconfig on the target cluster
aws eks --region $myRegion update-kubeconfig --name $myEKS

echo "Getting STS caller Identity"
aws sts get-caller-identity

echo "Describing the cluster"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws eks describe-cluster --name $myEKS --region $myRegion --query cluster.status

# Install Whereabouts
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/daemonset-install.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_ippools.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml

echo "Whereabouts installation succeeded"

# Apply NAD
kubectl apply -f https://raw.githubusercontent.com/aws-samples/sample-packages-for-aws-tnb/main/deployment-files/nad-sample.yaml

echo "NAD creation succeeded"

# Create OIDC 
oidc_id=$(aws eks describe-cluster --name $myEKS --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4
eksctl utils associate-iam-oidc-provider --cluster $myEKS --approve
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4

echo "OIDC creation succeeded"

# Installation of EFS add-on
cat > aws-efs-csi-driver-trust-policy.json << EOF 
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/oidc.eks.$myRegion.amazonaws.com/id/$oidc_id"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "oidc.eks.$myRegion.amazonaws.com/id/$oidc_id:sub": "system:serviceaccount:kube-system:efs-csi-*",
          "oidc.eks.$myRegion.amazonaws.com/id/$oidc_id:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Check if EFS CSI Driver Role exists and then create it, else do nothing
if ! aws iam get-role --role-name AmazonEKS_EFS_CSI_DriverRole >/dev/null 2>&1; then
  echo "Role does not exist. Creating the role..."
  aws iam create-role --role-name AmazonEKS_EFS_CSI_DriverRole --assume-role-policy-document file://aws-efs-csi-driver-trust-policy.json
  aws iam attach-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy
else
    echo "Role already exists. Skipping creation."
fi

# Create EKS EFS CSI add-on
aws eks create-addon --cluster-name $myEKS --addon-name aws-efs-csi-driver --addon-version v2.0.1-eksbuild.1 \
    --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EFS_CSI_DriverRole --resolve-conflicts OVERWRITE


randToken=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)

# Create Amazon EFS filesystem with encryption
efs_filesystem_id=$(aws efs create-file-system \
    --creation-token my-efs-filesystem-$randToken \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=my-efs \
    --encrypted \
    --query 'FileSystemId' \
    --output text)


echo "Created encrypted EFS filesystem with ID: $efs_filesystem_id"

# Create Kubernetes StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-storage-class
provisioner: kubernetes.io/aws-efs
parameters:
  fileSystemId: "$efs_filesystem_id"
  dnsname: "fs-$efs_filesystem_id.efs.us-west-2.amazonaws.com"
EOF

echo "StorageClass 'efs-storage-class' created with encrypted EFS filesystem ID: $efs_filesystem_id"


# Install Helm
export VERIFY_CHECKSUM=false
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Install load balancer controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=$myEKS

echo "load-balancer-controller installation succeeded"

# Check running pods
kubectl get pods -A

echo "get pods succeeded"
