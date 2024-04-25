#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>/var/log/userdata-sriov-log.out 2>&1
echo "#####################################################"
echo "Echo from sriov-config.sh."
echo "#####################################################"
modprobe vfio_pci
echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
startIndex=interfaceStartingIndex
intfCount=interfaceCount
while [ "$intfCount" -gt 0 ]; do
  pci_id=`ls -l /sys/class/net/eth"$startIndex"/ | grep device | cut -d '/' -f 4`
  echo "$pci_id"
  /opt/dpdk/dpdk-devbind.py -u "$pci_id"
  /opt/dpdk/dpdk-devbind.py -b vfio-pci "$pci_id"
  startIndex=$((startIndex + 1))
  intfCount=$((intfCount - 1))
done