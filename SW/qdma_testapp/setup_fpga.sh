sudo mount -t hugetlbfs nodev /mnt/huge
sudo modprobe uio
sudo insmod /home/yuli9/dpdk_test_area/dpdk-stable/dpdk-kmods/linux/igb_uio/igb_uio.ko

sudo /home/yuli9/dpdk_test_area/dpdk-stable/usertools/dpdk-devbind.py -b igb_uio a1:00.0

