#!/bin/bash
set -o xtrace
KubeletExtraArguments="--cpu-manager-policy=static"
cat << EOF > /etc/systemd/system/kubelet.service.d/90-kubelet-extra-args.conf
[Service]
Environment='USERDATA_EXTRA_ARGS=$KubeletExtraArguments'
EOF
# this kubelet.service update is for the version below than EKS 1.24 (e.g. up to 1.23)
# but still you can keep the line even if you use EKS 1.24 or higher
sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/systemd/system/kubelet.service
# this update is for the EKS 1.24 or higher.
sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/eks/containerd/kubelet-containerd.service
echo "net.ipv4.conf.default.rp_filter = 0" | tee -a /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter = 0" | tee -a /etc/sysctl.conf
sudo sysctl -p
sleep 45
# command to schedule adding multus interface up command to /etc/rc.local
sudo echo "ip link set eth1 up" >> /etc/rc.local
sudo echo "ip link set eth2 up" >> /etc/rc.local
sudo echo "ip link set eth3 up" >> /etc/rc.local
