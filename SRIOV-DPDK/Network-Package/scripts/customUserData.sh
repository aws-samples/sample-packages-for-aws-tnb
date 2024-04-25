#!/bin/bash
set -o xtrace

# Modify this line with the S3 bucket name where all the SRIOV-DPDK scripts are stored
S3BucketName="dpdkfiless3bucket"
# Modify the following variable to indicate the start index for the SRIOV interface
SriovStartingInterfaceIndex=3
interfaceCount=1
# Hugepages config
hugepagesz="1G"
Defaulthugepagesz="1G"
NumOfHugePages=8

# Install library dependencies for DPDK
yum update -y
yum install -y net-tools pciutils numactl-deve libhugetlbfs-utils libpcap-devel kernel kernel-devel kernel-headers

mkdir -p /opt/dpdk/
/bin/aws s3api get-object --bucket $S3BucketName --key dpdk-devbind.py /opt/dpdk/dpdk-devbind.py
chmod +x /opt/dpdk/dpdk-devbind.py

echo "S3BucketName - $S3BucketName"

# Copy the DPDK scripts to the /opt/dpdk directory and systemd directories
/bin/aws s3api get-object --bucket $S3BucketName --key sriov-init.service /usr/lib/systemd/system/sriov-init.service
/bin/aws s3api get-object --bucket $S3BucketName --key sriov-init.sh /opt/dpdk/sriov-init.sh
/bin/aws s3api get-object --bucket $S3BucketName --key sriov-config.service /usr/lib/systemd/system/sriov-config.service
/bin/aws s3api get-object --bucket $S3BucketName --key dpdk-resource-builder.py /opt/dpdk/dpdk-resource-builder.py
/bin/aws s3api get-object --bucket $S3BucketName --key sriov-config.sh /opt/dpdk/sriov-config.sh

sed -i -e "s/S3BucketName/$S3BucketName/g" /opt/dpdk/sriov-init.sh

chmod +x /opt/dpdk/sriov-init.sh

sleep 10

sed -i "s/biosdevname=0/& default_hugepagesz=$Defaulthugepagesz hugepagesz=$hugepagesz hugepages=$NumOfHugePages/g" /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

sed -i -e "s/interfaceCount/$interfaceCount/g" /opt/dpdk/sriov-config.sh
sed -i -e "s/interfaceStartingIndex/$SriovStartingInterfaceIndex/g" /opt/dpdk/sriov-config.sh

chmod +x /opt/dpdk/sriov-config.sh

# For M7i.4xlarge, please take care to modify the following settings for your choice of instance
sudo sed -i "s/^#CPUAffinity.*/CPUAffinity=0-1 8-9/g" /etc/systemd/system.conf
sudo sed -i "s/^#IRQBALANCE_BANNED_CPUS=/IRQBALANCE_BANNED_CPUS=0000ffff,f0fffff0/g" /etc/sysconfig/irqbalance

chmod a+x /opt/dpdk/dpdk-resource-builder.py

cat > /etc/systemd/system/dpdkbuilder.service << EOF
[Unit]
Description=Update system time using chronyc before starting kubelet service
Before=kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "if [ -f "/etc/pcidp/config.json" ]; then exit ; fi"
ExecStart=/bin/bash -c "python3 /opt/dpdk/dpdk-resource-builder.py $SriovStartingInterfaceIndex $interfaceCount"
ExecStart=/bin/bash -c "mkdir -p /etc/pcidp/"
ExecStart=/bin/bash -c "cp /tmp/data.txt /etc/pcidp/config.json"
ExecStart=/bin/bash -c "cp /tmp/data.txt /var/config.json"
ExecStart=/bin/bash -c "systemctl enable sriov-init.service"
ExecStart=/bin/bash -c "systemctl start sriov-init.service"
ExecStart=/bin/bash -c "systemctl start sriov-config.service"
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dpdkbuilder.service

# Change Kubelet Arguments
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
sleep 5

# command to schedule adding multus interface up command to /etc/rc.local
chmod +x /etc/rc.d/rc.local
systemctl enable rc-local --now   
sudo echo "ip link set eth1 up" >> /etc/rc.local
sudo echo "ip link set eth2 up" >> /etc/rc.local
sudo echo "ip link set eth3 up" >> /etc/rc.local