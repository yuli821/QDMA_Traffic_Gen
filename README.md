# Installation manual

## Hardware setup:

1. Clone the repo.
2. Move the qdma_2_ex.tcl to the desired project path.
3. Open vivado
4. In the vivado terminal, type the following command:
```tcl
set origin_dir_loc [/path/to/QDMA_Traffic_Gen]
source qdma_2_ex.tcl
```
This will create the project folder under the current directory, e.g. ./qdma_2_ex.


## Software setup:

DPDK setup:<br>
<p>Github: Xillinx/dma_ip_drivers/QDMA/DPDK.<br>
1. Following the tutorial until step 4, Compile Test application;<br>
2. Replace the example/qdma_testapp with SW/qdma_testapp, cd example/qdma_testapp;<br>
3. Run make -f Makefile_test RTE_SDK=`pwd`/../.. RTE_TARGET=build;<br>
4. Continue to tutorial's step 5, Step 5 iv can be ignored (enable vf);<br>
5. By default, only 1 PCIe PF is used (Likely to be 02:00.0 when I run it).<br>
6. sudo ../../usertools/dpdk-devbind.py -b igb_uio 02:00.0;<br>
7. Run the executable: sudo ./build/test -c 0xf -n 4 [portid] [number of queues] [pkt size] [num_pkt] [cycles_per_pkt]<br>
        num_pkt <- ignored for now<br>
        cycles_per_pkt <- if lowered than the minimum required cycles per pkt, will be replaced by the minimum cycles_per_pkt<br>
        e.g. sudo ./build/test -c 0xf -n 4 0 4 4096 0 0 : 4 c2h queues are used to receive pkts, each pkt contains 4kB, will run the recv function for 0.5s, each pkt takes 4096/64 + 3 hardware cycles to generate (the +3 is hardware logic to update credit), each cycle is 4ns. Therefore, the target throughput should theoretically be 122 Gbps.</p>

Linux driver setup:<br>

1. git clone this repository.
2. cd ./QDMA_Traffic_Gen/SW/linux-kernel
3. sudo make
4. sudo make install-mods
5. Place a config file "qdma.conf" under /etc/modprobe.d directory. The specific instruction for composing the config file is in step 1.3 under this github directory: https://github.com/Xilinx/dma_ip_drivers/tree/master/QDMA/linux-kernel <br>
An example qdma.conf file is provided, which is verified to be working, use this one right now.
6. Check if there's an existing driver binding to the device. If there is, need to remove the driver before loading the qdma-pf driver.
7. sudo modprobe qdma-pf

Check if driver is successfully loaded:<br>
Command: lspci -vvv -s 99:00.0 
Check kernel driver in use. If it's qdma-pf, then the driver is correctly loaded. If it's empty, then the driver is not loaded.

Unloading the driver: <br>
Command: sudo rmmod qdma-pf

Check kernel message in case of debugging:<br>
sudo dmesg

## File specification:

test.c: Throughput measurement. Output files: result/result_\[num_queue\]_rx_only.txt<br>
test_RR.c: Forwarding timestamp. Output files: result/result_\[num_queue\].txt<br>
Output files are incremental.<br>
Makefile_test: Makefile to compile the code, i.e. make -f Makefile_test RTE_TARGET=build; make -f Makefile_test RR RTE_TARGET=build<br>
run.sh: Run experiment with different packet size and processor mask configuration.<br>
Notice: the --main-lcoreid needs to be the last lcore id, i.e. if running with 12 lcores, the main lcoreid needs to be 11.<br>


