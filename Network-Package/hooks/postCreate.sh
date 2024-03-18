#!/bin/sh

set -e
#unset AWS_ACCESS_KEY_ID
#unset AWS_SECRET_ACCESS_KEY

echo "Testing parameter passing"
#Passing region information and EKS cluster role
echo $EKS_Cluster_Name
echo $currentregion

myRegion=us-west-2
#myEKSClusterRole='$EKS_CLUSTER_ROLE'

echo "Post infra hook"
#Query the cluster name based on tag passed from NSD
# aws resourcegroupstaggingapi get-resources --tag-filters Key="Name",Values=$EKS_Cluster_Name --region $myRegion| jq '.ResourceTagMappingList[0].ResourceARN' | grep -o '[^\/]*$' | tr -d '"'

myEKS=`aws resourcegroupstaggingapi get-resources --tag-filters Key="Name",Values=$EKS_Cluster_Name --region $myRegion | jq '.ResourceTagMappingList[0].ResourceARN' | grep -o '[^\/]*$' | tr -d '"'`

#Update kubeconfig on the target cluster

#Remove role-arn so that it can assume default admin role
#aws eks --region $myRegion update-kubeconfig --name $myEKS --role-arn $myEKSClusterRole
aws eks --region $myRegion update-kubeconfig --name $myEKS

echo "EKS cluster query succeeded"

# cat /root/.kube/config

echo "Getting STS caller Identity"

aws sts get-caller-identity

echo "Describing the cluster"

export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws eks describe-cluster --name $myEKS --region $myRegion --query cluster.status

# Assume admin role that created the cluster, this is the role that logged into the console and created the TNB instance
CREDS=$(aws sts assume-role \
--role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/admin \
--role-session-name $(date '+%Y%m%d%H%M%S%3N') \
--duration-seconds 3600 \
--query '[Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]' \
--output text)
export AWS_DEFAULT_REGION="us-west-2"
export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

aws sts get-caller-identity

# kubectl get pods -n kube-system

# echo "Cluster description succeeded"

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

# deploy EFS on target cluster
# kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.4"

# echo "Step 3 EFS succeeded"
#deploy EBS on target cluster
# aws eks create-addon --cluster-name $myEKS --addon-name aws-ebs-csi-driver --region $myRegion

# echo "Step 4 EBS succeeded"

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
