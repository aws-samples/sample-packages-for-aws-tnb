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
oidc_id=$(aws eks describe-cluster --name $targetEks --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
if ! aws iam list-open-id-connect-providers | grep -q $oidc_id ; then
  eksctl utils associate-iam-oidc-provider --cluster $targetEks --approve
  echo "OIDC creation succeeded"
else
  echo "OIDC already exists. Skipping creation."
fi

echo "OIDC creation succeeded"

# Create SRIOV Daamon-set on the EKS cluster

cat << EOF | kubectl apply -f - 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sriov-device-plugin
  namespace: kube-system
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: sriovdp
  name: kube-sriov-device-plugin-amd64
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: sriov-device-plugin
  template:
    metadata:
      labels:
        app: sriovdp
        name: sriov-device-plugin
        tier: node
    spec:
      containers:
      - args:
        - --log-dir=sriovdp
        - --log-level=10
        image: ghcr.io/k8snetworkplumbingwg/sriov-network-device-plugin:v3.5.1
        imagePullPolicy: IfNotPresent
        name: kube-sriovdp
        resources:
          limits:
            cpu: "1"
            memory: 200Mi
          requests:
            cpu: 250m
            memory: 40Mi
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kubelet/
          name: devicesock
        - mountPath: /var/log
          name: log
        - mountPath: /etc/pcidp/config.json
          name: config-volume
          readOnly: true
        - mountPath: /var/run/k8s.cni.cncf.io/devinfo/dp
          name: device-info
      dnsPolicy: ClusterFirst
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: amd64
        sriov: enabled
      restartPolicy: Always
      serviceAccount: sriov-device-plugin
      serviceAccountName: sriov-device-plugin
      terminationGracePeriodSeconds: 30
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Exists
      volumes:
      - hostPath:
          path: /var/lib/kubelet/
          type: ""
        name: devicesock
      - hostPath:
          path: /var/log
          type: ""
        name: log
      - hostPath:
          path: /var/run/k8s.cni.cncf.io/devinfo/dp
          type: DirectoryOrCreate
        name: device-info
      - hostPath:
          path: /etc/pcidp/config.json
          type: ""
        name: config-volume
  updateStrategy:
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
    type: RollingUpdate
EOF


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
