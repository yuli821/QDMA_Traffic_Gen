#!/bin/bash
# setup_fpga_tcp.sh - Configure host for FPGA TCP endpoint
#disable ipv6 in /etc/sysctl.conf for enp161s0
#exclude avahi for enp161s0 in /etc/avahi/avahi-daemon.conf

QDMA_IFACE="enp161s0"
HOST_IP="192.168.100.10"
FPGA_IP="192.168.100.11"
FPGA_MAC="00:AA:BB:CC:DD:EE"  #


sudo sysctl -w net.ipv6.conf.{$QDMA_IFACE}.disable_ipv6=1

sudo ip link set $QDMA_IFACE up
sudo ip addr add ${HOST_IP}/24 dev $QDMA_IFACE

echo "Configuring host for FPGA TCP endpoint..."
# # 1. Bring up interface
# echo "[1] Bringing up $QDMA_IFACE..."
# sudo ip link set $QDMA_IFACE up

# # 2. Assign IP
# echo "[2] Assigning IP $HOST_IP to $QDMA_IFACE..."
# sudo ip addr flush dev $QDMA_IFACE
# sudo ip addr add ${HOST_IP}/24 dev $QDMA_IFACE

# 3. Add ARP entry
sudo ip link set $QDMA_IFACE arp off
echo "[3] Adding static ARP entry for FPGA..."
sudo arp -d $FPGA_IP 2>/dev/null  # Remove old entry
sudo arp -s $FPGA_IP $FPGA_MAC

# 4. Disable offloading
echo "[4] Disabling TCP offload features..."
sudo ethtool -K $QDMA_IFACE tx off rx off tso off gso off gro off lro off 2>/dev/null

# 5. Verify
echo ""
echo "Configuration Summary:"
echo "  Interface: $QDMA_IFACE"
ip addr show $QDMA_IFACE | grep inet
echo ""
echo "  ARP Entry:"
arp -n | grep $FPGA_IP
echo ""
echo "  Route:"
ip route | grep 192.168.100
echo ""