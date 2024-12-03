Installation manual
Hardware setup: 
Files needed: HW/hdl/traffic_gen.sv, HW/hdl/imports.
Vivado version: v2021.2
Board: xcvc1902-vsva2197-2MP-e-S
QDMA IP setting: 
  Queue DMA Subsystem for PCI Express (4.0); Mode: Advanced; PCIe Block Location: X0Y1; AXI Data Width: 512 bit; DMA Interface Selection: AXI Stream with Completion; 
  PCIe: BARs: AXI Lite Master - 64 bit - Prefetchable - 4K;
  PCIe: DMA: Descriptor Bypass - None; Prefetch cache depth - 16; CMPT Coalesce Max buffer - 16;
  Other parameters are default.
Step 1: Setup QDMA IP;
Step 2: Generate QDMA example design;
Step 3: Replace imports folder with HW/hdl/imports;
Step 4: Add HW/hdl/traffic_gen.sv into design files;
Step 5: Run synthesis & implementation, generate device image.

Software setup:
Github: Xillinx/dma_ip_drivers/QDMA/DPDK.
Step 1: Following the tutorial until step 4, Compile Test application;
Step 2: Replace the example/qdma_testapp with SW/qdma_testapp, cd example/qdma_testapp;
Step 3: Run make -f Makefile_test RTE_SDK=`pwd`/../.. RTE_TARGET=build;
Step 4: Continue to tutorial's step 5, Step 5 iv can be ignored (enable vf);
Step 5: By default, only 1 PCIe PF is used (Likely to be 02:00.0 when I run it).
Step 6: sudo ../../usertools/dpdk-devbind.py -b igb_uio 02:00.0;
Step 7: Run the executable: sudo ./build/test -c 0xf -n 4 [portid] [number of queues] [pkt size] [num_pkt] [cycles_per_pkt]
        num_pkt <- ignored for now
        cycles_per_pkt <- if lowered than the minimum required cycles per pkt, will be replaced by the minimum cycles_per_pkt
        e.g. sudo ./build/test -c 0xf -n 4 0 4 4096 0 0 : 4 c2h queues are used to receive pkts, each pkt contains 4kB, will run the recv function for 0.5s, each pkt takes 4096/64 + 3 hardware cycles to generate (the +3 is hardware logic to update credit), each cycle is 4ns. Therefore, the target throughput should theoretically be 122 Gbps.
