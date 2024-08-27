#include <rte_eal.h> /**> rte_eal_init */
#include <rte_debug.h> /**> for rte_panic */
#include <rte_ethdev.h> /**> rte_eth_rx_burst */
#include <rte_errno.h> /**> rte_errno global var */
#include <rte_memzone.h> /**> rte_memzone_dump */
#include <rte_memcpy.h>
#include <rte_malloc.h>
#include <rte_cycles.h>
#include <rte_log.h>
#include <rte_string_fns.h>
#include <rte_spinlock.h>
#include <rte_mbuf.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include "../../drivers/net/qdma/rte_pmd_qdma.h"
#include "test.h"
#include "pcierw.h"
#include "qdma_regs.h"

#define RTE_LIBRTE_QDMA_PMD 1

int num_ports;
struct port_info pinfo[QDMA_MAX_PORTS];

int port_init(int portid, int num_queues, int st_queues, int nb_descs, int buff_size)
{
    struct rte_mempool *mbuf_pool;
    struct rte_eth_conf port_conf;
    struct rte_eth_txconf tx_conf;
    struct rte_eth_rxconf rx_conf;
    int diag, x;
    uint32_t queue_base, nb_buff;

    printf("Setting up port :%d.\n", portid);

    if (rte_pmd_qdma_get_device(portid) == NULL) {
    printf("Port id %d already removed. Relaunch application to use the port again\n", portid);
    return -1;
    }

    snprintf(pinfo[portid].mem_pool, RTE_MEMPOOL_NAMESIZE, MBUF_POOL_NAME_PORT, portid);

    /* Mbuf packet pool */
    nb_buff = ((nb_descs) * num_queues * 2);

    /* NUM_TX_PKTS should be added to every queue as that many descriptors
    * can be pending with application after Rx processing but before
    * consumed by application or sent to Tx
    */
    nb_buff += ((NUM_TX_PKTS) * num_queues);

    /*
    * rte_mempool_create_empty() has sanity check to refuse large cache
    * size compared to the number of elements.
    * CACHE_FLUSHTHRESH_MULTIPLIER (1.5) is defined in a C file, so using a
    * constant number 2 instead.
    */
    nb_buff = RTE_MAX(nb_buff, MP_CACHE_SZ * 2);

    mbuf_pool = rte_pktmbuf_pool_create(pinfo[portid].mem_pool, nb_buff, MP_CACHE_SZ, 0, buff_size + RTE_PKTMBUF_HEADROOM, rte_socket_id());

    if (mbuf_pool == NULL)
    rte_exit(EXIT_FAILURE, " Cannot create mbuf pkt-pool\n");

    /*
    * Make sure the port is configured. Zero everything and
    * hope for sane defaults
    */
    memset(&port_conf, 0x0, sizeof(struct rte_eth_conf));
    memset(&tx_conf, 0x0, sizeof(struct rte_eth_txconf));
    memset(&rx_conf, 0x0, sizeof(struct rte_eth_rxconf));
    diag = rte_pmd_qdma_get_bar_details(portid, &(pinfo[portid].config_bar_idx), &(pinfo[portid].user_bar_idx), &(pinfo[portid].bypass_bar_idx));

    if (diag < 0)
    rte_exit(EXIT_FAILURE, "rte_pmd_qdma_get_bar_details failed\n");

    printf("QDMA Config bar idx: %d\n", pinfo[portid].config_bar_idx);
    printf("QDMA AXI Master Lite bar idx: %d\n", pinfo[portid].user_bar_idx);
    printf("QDMA AXI Bridge Master bar idx: %d\n", pinfo[portid].bypass_bar_idx);

    /* configure the device to use # queues */
    diag = rte_eth_dev_configure(portid, num_queues, num_queues, &port_conf);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "Cannot configure port %d (err=%d)\n", portid, diag);

    diag = rte_pmd_qdma_get_queue_base(portid, &queue_base);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "rte_pmd_qdma_get_queue_base : Querying of QUEUE_BASE failed\n");
    pinfo[portid].queue_base = queue_base;
    pinfo[portid].num_queues = num_queues;
    pinfo[portid].st_queues = st_queues;
    pinfo[portid].buff_size = buff_size;
    pinfo[portid].nb_descs = nb_descs;

    for (x = 0; x < num_queues; x++) {
    if (x < st_queues) {
    diag = rte_pmd_qdma_set_queue_mode(portid, x, RTE_PMD_QDMA_STREAMING_MODE);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "rte_pmd_qdma_set_queue_mode : Passing of QUEUE_MODE failed\n");
    } else {
    diag = rte_pmd_qdma_set_queue_mode(portid, x, RTE_PMD_QDMA_MEMORY_MAPPED_MODE);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "rte_pmd_qdma_set_queue_mode : Passing of QUEUE_MODE failed\n");
    }

    diag = rte_eth_tx_queue_setup(portid, x, nb_descs, 0, &tx_conf);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "Cannot setup port %d TX Queue id:%d (err=%d)\n", portid, x, diag);
    rx_conf.rx_thresh.wthresh = DEFAULT_RX_WRITEBACK_THRESH;
    diag = rte_eth_rx_queue_setup(portid, x, nb_descs, 0, &rx_conf, mbuf_pool);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "Cannot setup port %d RX Queue 0 (err=%d)\n", portid, diag);
    }

    diag = rte_eth_dev_start(portid);
    if (diag < 0)
    rte_exit(EXIT_FAILURE, "Cannot start port %d (err=%d)\n", portid, diag);

    return 0;
    }

int main(int argc, char* argv[]) {
    //measure the latency of QDMA read of different loads, start from 2Bytes to 512kB
    //need test data accuracy?
    if(argc != 10) {
        printf("./build/test -c 0xf -n 4 portid num_queues buffsize numpkts cycles_per_pkt\n");
        return 0;
    }

    const struct rte_memzone *mz = 0;
    int ret = 0;
    int portid = atoi(argv[5]);
    int num_queues = atoi(argv[6]); //self-defined parameter
    int stqueues = 1; //self-defined parameter
    int numdescs = NUM_DESC_PER_RING; //self-defined parameter
    int buffsize = atoi(argv[7]); //self-defined parameter
    uint64_t prev_tsc, cur_tsc, diff_tsc; //measure latency
    struct rte_mbuf *mb[NUM_TX_PKTS] = { NULL };
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    struct rte_mempool *mp;
    int numpkts = atoi(argv[8]);
    int cycles = atoi(argv[9]);
    int recvpkts = 0;
    int i, j, nb_tx, nb_rx;
    unsigned int q_data_size = 0;
    uint64_t dst_addr = 0, src_addr = 0;
    //streaming
    unsigned int max_completion_size, last_pkt_size = 0, only_pkt = 0;
    unsigned int max_rx_retry, rcv_count = 0, num_pkts_recv = 0, total_rcv_pkts = 0;
    int user_bar_idx;
    int reg_val, loopback_en;
    int qbase, queueid, diag;
    struct rte_mbuf *nxtmb;
    queueid = 0;

    ret = rte_eal_init(argc, argv);
    if (ret < 0)
        rte_exit(EXIT_FAILURE, "Error with EAL initialization\n");
    rte_log_set_global_level(RTE_LOG_DEBUG);

    printf("Ethernet Device Count: %d\n", (int)rte_eth_dev_count_avail());
    printf("Logical Core Count: %d\n", rte_lcore_count());

    num_ports = rte_eth_dev_count_avail();
    if (num_ports < 1)
        rte_exit(EXIT_FAILURE, "No Ethernet devices found. Try updating the FPGA image.\n");

    for (int portid = 0; portid < num_ports; portid++)
        rte_spinlock_init(&pinfo[portid].port_update_lock);

    /* Allocate aligned mezone */
    rte_pmd_qdma_compat_memzone_reserve_aligned();

    ret = port_init(portid, num_queues, stqueues, numdescs, buffsize);

    mp = rte_mempool_lookup(pinfo[portid].mem_pool);

    if (mp == NULL) {
        printf("Could not find mempool with name %s\n",
        pinfo[portid].mem_pool);
        // rte_spinlock_unlock(&pinfo[portid].port_update_lock);
        return -1;
    }

    qbase = pinfo[portid].queue_base;
    int count = 0;
    int tmp = numpkts, nb_pkts, tmp_pkts, count_pkt;
    // int tmp = 100, nb_pkts, tmp_pkts, count_pkt;
    // int max_tx_retry;
    int fd;
    // fd = open("output.txt", O_RDWR | O_CREAT | O_TRUNC | O_SYNC, 0666);
    int r_size = 0;
    int size, total_size = 0;
    int offset, ld_size = 0;
    double tot_time = 0;
    double time;
    double pkts_per_second, throughput_gbps;
    user_bar_idx = pinfo[portid].user_bar_idx;
    PciWrite(user_bar_idx, C2H_ST_QID_REG, (queueid + qbase), portid);
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
    reg_val &= C2H_CONTROL_REG_MASK;
    loopback_en = reg_val & ST_LOOPBACK_EN;
    // if (!loopback_en) {
    // /* As per hardware design a single completion will point to atmost
    // * 7 descriptors. So If the size of the buffer in descriptor is 4KB ,
    // * then a single completion which corresponds a packet can give you
    // * atmost 28KB data.
    // *
    // * As per this when testing sizes beyond 28KB, one needs to split it
    // * up in chunks of 28KB, example : to test 56KB data size, set 28KB
    // * as packet length in AXI Master Lite BAR(user bar) 0x04 register and no of packets as 2
    // * in AXI Master Lite BAR(user bar) 0x20 register this would give you completions or
    // * packets, which needs to be combined as one in application.
    // */
    // max_completion_size = pinfo[portid].buff_size * 7;
    // } else {
    // /* For loopback case, each packet handles 4KB only,
    // * so limiting to buffer size.
    // */
    // max_completion_size = pinfo[portid].buff_size;
    // }
    max_completion_size = pinfo[portid].buff_size;
    printf("max_completion_size: %d\n", max_completion_size);
    PciWrite(user_bar_idx, C2H_PACKET_COUNT_REG, numpkts, portid);
    PciWrite(user_bar_idx, C2H_ST_LEN_REG, max_completion_size, portid);
    PciWrite(user_bar_idx, CYCLES_PER_PKT, cycles, portid);
    /* Start the C2H Engine */
    reg_val |= ST_C2H_START_VAL;
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, portid);
    reg_val = PciRead(user_bar_idx, C2H_PACKET_COUNT_REG, portid);
    printf("BAR-%d is the QDMA C2H number of packets:0x%x,\n", user_bar_idx, reg_val);
    reg_val = PciRead(user_bar_idx, CYCLES_PER_PKT, portid);
    printf("Cycles per packet is : %d\n", reg_val);
    prev_tsc = rte_rdtsc_precise();
    while(recvpkts < numpkts){
        // while (recvpkts < 100) {
        count_pkt = 0;
        if (tmp > NUM_RX_PKTS) {
            nb_pkts = NUM_RX_PKTS;
        } else {
            nb_pkts = tmp;
        }
        max_rx_retry = RX_TX_MAX_RETRY;
        /* try to receive RX_BURST_SZ packets */
        // rte_pmd_qdma_dbg_qinfo(portid, 0);
        nb_rx = rte_eth_rx_burst(portid, queueid, pkts, nb_pkts);
        // if (nb_rx > 0) {
            // rte_pmd_qdma_dbg_reg_info_dump(portid, 2, 0xb44);
            // rte_pmd_qdma_dbg_qinfo(portid, 0);
        // printf("recv_count: %d, total_recv_pkts: %d, intend to recv: %d\n", nb_rx, recvpkts, nb_pkts);
        // }
        recvpkts += nb_rx;
        tmp -= nb_rx;
        count_pkt += nb_rx;
        tmp_pkts = nb_pkts;
        while ((nb_rx < tmp_pkts) && max_rx_retry) {
            // rte_delay_us(1);
            tmp_pkts -= nb_rx;
            nb_rx = rte_eth_rx_burst(portid, queueid, &pkts[count_pkt], tmp_pkts);
            // if (nb_rx > 0) {
            //     printf("recv_count: %d, total_recv_pkts: %d\n", nb_rx, recvpkts);
            // }
            recvpkts += nb_rx;
            max_rx_retry--;
            tmp -= nb_rx;
            count_pkt += nb_rx;
        }
        for (i = 0; i < count_pkt; i++) {
            // rte_delay_ms(1);
            struct rte_mbuf *mb = pkts[i];
            // while (mb != NULL) {
            //     ret += write(fd, rte_pktmbuf_mtod(mb, void*),rte_pktmbuf_data_len(mb));
            //     printf("Number of bytes send: %d\n", ret);
            //     nxtmb = mb->next;
            //     mb = nxtmb;
            // }
            // mb = pkts[i];
            rte_pktmbuf_free(mb);
            // count += ret;
            // ret = 0;
        }
    }
    /* Stop the C2H Engine */
    // if (!loopback_en) {
    //     reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
    //     reg_val &= C2H_CONTROL_REG_MASK;
    //     reg_val |= ST_C2H_END_VAL;
    //     PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val,portid);
    // }
    cur_tsc = rte_rdtsc_precise();
    diff_tsc = cur_tsc - prev_tsc;
    printf("diff_tsc: %ld\n", diff_tsc);
    tot_time = diff_tsc*1.0 / rte_get_tsc_hz();
    printf("DMA received number of packets: %u, on queue-id:%d\n",recvpkts, queueid);
    rte_spinlock_unlock(&pinfo[portid].port_update_lock);

    pkts_per_second = ((double)recvpkts / tot_time);

    /* Calculate average throughput (Gbps) in bits per second */
    throughput_gbps = (pinfo[portid].buff_size * 8.0/ (1000000000.0)) * pkts_per_second;

    printf("Throughput Gbps %lf ", throughput_gbps);
    printf("Number of bytes: %d ", pinfo[portid].buff_size * recvpkts);
    printf("total latency: %lf\n", tot_time);
    // rte_pmd_qdma_dbg_qinfo(portid, 0);
    // close(fd);
    rte_eth_dev_stop(portid);

    rte_pmd_qdma_dev_close(portid);
    mp = rte_mempool_lookup(pinfo[portid].mem_pool);

    if (mp != NULL)
        rte_mempool_free(mp);
}

