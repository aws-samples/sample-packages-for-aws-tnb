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

echo "Describing the cluster"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws eks describe-cluster --name $myEKS --region $myRegion --query cluster.status

# Install Whereabouts
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/daemonset-install.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_ippools.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/master/doc/crds/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml

echo "Whereabouts installation succeeded"

# Copy the NAD, update the CIDR and apply it
curl -O https://raw.githubusercontent.com/aws-samples/sample-packages-for-aws-tnb/main/IPv6/deployment-files/nad-sample-ipv6.yaml

multusSubnet2Az1Ipv6CidrPrefix=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=MultusSubnet2Az1" --query "Subnets[*].Ipv6CidrBlockAssociationSet[*].Ipv6CidrBlock" --output text | cut -d "/" -f1)
multusSubnet2Az2Ipv6CidrPrefix=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=MultusSubnet2Az2" --query "Subnets[*].Ipv6CidrBlockAssociationSet[*].Ipv6CidrBlock" --output text | cut -d "/" -f1)
sed -i "s/##multusSubnet2Az1Ipv6Cidr##/$multusSubnet2Az1Ipv6CidrPrefix/g" nad-sample-ipv6.yaml
sed -i "s/##multusSubnet2Az2Ipv6Cidr##/$multusSubnet2Az2Ipv6CidrPrefix/g" nad-sample-ipv6.yaml

kubectl apply -f nad-sample-ipv6.yaml

echo "NAD creation succeeded"

# Create OIDC 
oidc_id=$(aws eks describe-cluster --name $myEKS --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4
eksctl utils associate-iam-oidc-provider --cluster $myEKS --approve
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4

echo "OIDC creation succeeded"

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
