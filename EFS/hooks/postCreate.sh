#!/bin/sh

set -e
#unset AWS_ACCESS_KEY_ID
#unset AWS_SECRET_ACCESS_KEY

echo "Testing parameter passing"
# Passing region information and EKS cluster role
echo $EKS_Cluster_Name
echo $currentregion

myRegion=us-west-2

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
        "Federated": "arn:aws:iam::ACCOUNTID:oidc-provider/oidc.eks.region-code.amazonaws.com/id/EXAMPLEOIDC"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "oidc.eks.region-code.amazonaws.com/id/EXAMPLEOIDC:sub": "system:serviceaccount:kube-system:efs-csi-*",
          "oidc.eks.region-code.amazonaws.com/id/EXAMPLEOIDC:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
sed -i "s/ACCOUNTID/$AWS_ACCOUNT_ID/" aws-efs-csi-driver-trust-policy.json
sed -i "s/region-code/$currentregion/" aws-efs-csi-driver-trust-policy.json
sed -i "s/EXAMPLEOIDC/$oidc_id/" aws-efs-csi-driver-trust-policy.json

aws iam create-role --role-name AmazonEKS_EFS_CSI_DriverRole --assume-role-policy-document file://aws-efs-csi-driver-trust-policy.json
aws iam attach-role-policy --role-name AmazonEKS_EFS_CSI_DriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy

aws eks create-addon --cluster-name $myEKS --addon-name aws-efs-csi-driver --addon-version v2.0.1-eksbuild.1 \
    --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EFS_CSI_DriverRole --resolve-conflicts OVERWRITE

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
