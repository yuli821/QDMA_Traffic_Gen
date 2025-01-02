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
#include <time.h>
#include "../../../drivers/net/qdma/rte_pmd_qdma.h"
#include "test.h"
#include "pcierw.h"
#include "qdma_regs.h"

// #define RTE_LIBRTE_QDMA_PMD 1

int num_ports;
struct port_info pinfo[QDMA_MAX_PORTS];
#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16
unsigned int num_lcores;
int* recv_pkts;

struct lcore_queue_conf {
	unsigned n_rx_port;
	unsigned rx_port_list[MAX_RX_QUEUE_PER_LCORE];
} __rte_cache_aligned;
struct lcore_queue_conf lcore_queue_conf[RTE_MAX_LCORE];

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
    rte_pmd_qdma_set_c2h_descriptor_prefetch(portid, 0, 1);
    // rte_pmd_qdma_set_cmpt_trigger_mode(portid, 0, RTE_PMD_QDMA_TRIG_MODE_EVERY);

    diag = rte_eth_dev_start(portid);
    if (diag < 0)
        rte_exit(EXIT_FAILURE, "Cannot start port %d (err=%d)\n", portid, diag);

    return 0;
}
typedef struct input_arg {
    int** core_to_q;
    int numpkts;
    int portid;
} input_arg_t;

static int recv_pkt_single_core(input_arg_t* inputs) { // for each lcore
    int recvpkts = 0;
    int nb_rx, count_pkt;
    int idx2, idx = rte_lcore_id();
    int** core_to_q = inputs->core_to_q;
    int numpkts = inputs->numpkts;
    int portid = inputs->portid;
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    struct rte_mbuf *mb, *nxtmb;
    // char * buffer = (char*)malloc(numpkts * pinfo[portid].buff_size);
    uint64_t prev_tsc, cur_tsc;
    double rate = 0.0, elapsed_time = 0.0;
    // prev_tsc = rte_rdtsc_precise();
    while(recvpkts < numpkts){
        count_pkt = 0;
        idx2 = 0;
        while(core_to_q[idx][idx2] != -1) {
            // rte_delay_us(1);
            nb_rx = rte_eth_rx_burst(portid, core_to_q[idx][idx2], pkts, NUM_RX_PKTS);
            if (nb_rx > 0) {
                // cur_tsc = rte_rdtsc_precise();
                // elapsed_time = (cur_tsc - prev_tsc)*1.0 / rte_get_tsc_hz();
                // // printf("%ld\n", cur_tsc - prev_tsc);
                // rate = nb_rx * pinfo[portid].buff_size * 8 / (elapsed_time * 1000000000); //gbps
                // prev_tsc = cur_tsc;
                printf("recv_count: %d, total_recv_pkts: %d, queueid: %d, lcoreid: %d, rate: %lf Gbps\n", nb_rx, recvpkts, core_to_q[idx][idx2], idx, rate);
            }
            // printf("recv_count: %d, total_recv_pkts: %d, queueid: %d, lcoreid: %d, rate: %lf Gbps\n", nb_rx, recvpkts, core_to_q[idx][idx2], idx, rate);
            count_pkt += nb_rx;
            for (int i = 0; i < nb_rx; i++) {
                mb = pkts[i];
                rte_pktmbuf_free(mb);
            }
            idx2++;
        }
        recv_pkts[idx] += count_pkt;
        recvpkts = 0;
        for (int i = 0 ; i < num_lcores; i++) {
            recvpkts += recv_pkts[i];
        }
    }
    // free(buffer);
    return 0;
}

int main(int argc, char* argv[]) {
    //measure the latency of QDMA read of different loads, start from 2Bytes to 512kB
    //need test data accuracy?

    const struct rte_memzone *mz = 0;
    int ret = 0;
    int numdescs = NUM_DESC_PER_RING; //self-defined parameter
    uint64_t prev_tsc, cur_tsc, temp_tsc, temp_tsc1, diff_tsc, diff_tsc2, test_tsc; //measure latency
    struct rte_mbuf *mb[NUM_TX_PKTS] = { NULL };
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    struct rte_mempool *mp;
    int portid, num_queues, stqueues, buffsize, numpkts, cycles;
    if (argc == 10) {
        portid = atoi(argv[5]);
        num_queues = atoi(argv[6]); //self-defined parameter
        stqueues = atoi(argv[6]); //self-defined parameter
        buffsize = atoi(argv[7]); //self-defined parameter
        numpkts = atoi(argv[8]);
        cycles = atoi(argv[9]);
    } else if (argc == 11) {
        portid = atoi(argv[6]);
        num_queues = atoi(argv[7]); //self-defined parameter
        stqueues = atoi(argv[7]); //self-defined parameter
        buffsize = atoi(argv[8]); //self-defined parameter
        numpkts = atoi(argv[9]);
        cycles = atoi(argv[10]);
    } else {
        printf("./build/test -c 0xf -n 4 portid num_queues buffsize numpkts cycles_per_pkt\n");
        printf("./build/test --log-level=pmd:debug -c 0xf -n 4 portid num_queues buffsize numpkts cycles_per_pkt\n");
        return 0;
    }
    long int recvpkts = 0;
    int i, j, nb_tx, nb_rx;
    unsigned int q_data_size = 0;
    uint64_t dst_addr = 0, src_addr = 0;
    //streaming
    unsigned int max_completion_size, last_pkt_size = 0, only_pkt = 0;
    unsigned int max_rx_retry, rcv_count = 0, num_pkts_recv = 0, total_rcv_pkts = 0;
    int user_bar_idx;
    int reg_val, loopback_en;
    int qbase, diag;
    struct rte_mbuf *nxtmb;

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

    num_lcores = rte_lcore_count();
    recv_pkts = (int*)malloc(num_lcores * sizeof(int));
    memset(recv_pkts, 0, num_lcores * sizeof(int));
    int** lcore_q_map = (int**)malloc(num_lcores * sizeof(int*));  //index 0: core id, rest: queueid
    int q_per_core = num_queues / num_lcores;
    int q_count = pinfo[portid].queue_base;
    if (num_queues % num_lcores != 0) {
        q_per_core++;
    } 
    int idx = 0;
    RTE_LCORE_FOREACH(i) {
        int* pp = (int*)malloc(sizeof(int)*(q_per_core+1));
        pp[q_per_core] = -1;
        lcore_q_map[i] = pp;
    }
    for (int x = 0 ; x < q_per_core ; x++) {
        for (idx = 0 ; idx < num_lcores ; idx++) {
            if (q_count < (num_queues+pinfo[portid].queue_base)) {
                lcore_q_map[idx][x] = q_count;
                q_count++;
            } else {
                lcore_q_map[idx][x] = -1;
            }
        }
    }

    qbase = pinfo[portid].queue_base;
    
    int size;
    double tot_time = 0;
    double time;
    double pkts_per_second, throughput_gbps;
    user_bar_idx = pinfo[portid].user_bar_idx;

    // reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
    // reg_val &= C2H_CONTROL_REG_MASK;
    // loopback_en = reg_val & ST_LOOPBACK_EN;

    int qid = 0;
    for (i = 0 ; i < 128 ; i++) {
        PciWrite(user_bar_idx, RSS_START + (i*4), qid+qbase, portid);
        qid = (qid + 1) % num_queues;
    }

    // reg_val &= C2H_CONTROL_REG_MASK;

    max_completion_size = pinfo[portid].buff_size;
    printf("max_completion_size: %d\n", max_completion_size);
    PciWrite(user_bar_idx, C2H_PACKET_COUNT_REG, numpkts, portid);
    PciWrite(user_bar_idx, C2H_ST_LEN_REG, max_completion_size, portid);
    PciWrite(user_bar_idx, CYCLES_PER_PKT, cycles, portid);
    PciWrite(user_bar_idx, C2H_NUM_QUEUES, num_queues, portid);

    /* Start the C2H Engine */
    PciWrite(user_bar_idx, C2H_ST_QID_REG, qbase, portid);
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
    reg_val |= ST_C2H_START_VAL;
    // reg_val |= ST_C2H_PERF_ENABLE;
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, portid);

    // reg_val = PciRead(user_bar_idx, C2H_PACKET_COUNT_REG, portid);
    // printf("BAR-%d is the QDMA C2H number of packets:0x%x,\n", user_bar_idx, reg_val);
    // reg_val = PciRead(user_bar_idx, CYCLES_PER_PKT, portid);
    // printf("Cycles per packet is : %d\n", reg_val);
    qid = 0;
    // clock_t begin,end;
    double time_elapsed = 0.0, time_elapsed2 = 0.0;
    double rate = 0.0;
    // bool a = true;
    // begin = clock();
    prev_tsc = rte_rdtsc_precise();
    // input_arg_t* temp = (input_arg_t*)malloc(sizeof(input_arg_t));
    // temp->core_to_q = lcore_q_map;
    // temp->numpkts = numpkts;
    // temp->portid = portid;
    // rte_eal_mp_remote_launch((lcore_function_t*)&recv_pkt_single_core, temp, CALL_MAIN);
    // rte_eal_mp_wait_lcore();
    double arr[10000];
    int arr_idx = 0, number_pkts = 0;
    // temp_tsc = prev_tsc;
    test_tsc = prev_tsc;
    while(time_elapsed < 1.0){
        // while (recvpkts < 100) {
        // count_pkt = 0;
        // max_rx_retry = RX_TX_MAX_RETRY;
        /* try to receive RX_BURST_SZ packets */
        // rte_pmd_qdma_dbg_qinfo(portid, 0);
        // rte_delay_us(2);
        // test_tsc = rte_rdtsc_precise();
        // printf("First: %ld\n", test_tsc);
        nb_rx = rte_eth_rx_burst(portid, qid+qbase, pkts, NUM_RX_PKTS);
        // end = clock();
        temp_tsc1 = rte_rdtsc_precise();
        diff_tsc = temp_tsc1 - prev_tsc;
        diff_tsc2 = temp_tsc1 - test_tsc;
        time_elapsed = diff_tsc*1.0 / rte_get_tsc_hz();
        time_elapsed2 = diff_tsc2*1.0 / rte_get_tsc_hz();
        number_pkts += nb_rx;
        // temp_tsc =  temp_tsc1;
        // rate = nb_rx * pinfo[portid].buff_size * 8 / (time_elapsed * 1000000000); //gbps
        if (time_elapsed2 >= 0.0001) {
            // printf("time_elapsed: %lf, number of packets: %d\n", time_elapsed, number_pkts);
            test_tsc = temp_tsc1;
            rate = number_pkts * pinfo[portid].buff_size * 8.0 / (time_elapsed2 * 1000000000.0);
            arr[arr_idx] = rate;
            arr_idx++;
            number_pkts = 0;
            // rte_pmd_qdma_dbg_qinfo(portid, 0);
            // rte_pmd_qdma_dbg_qinfo(portid, 1);
            // rte_pmd_qdma_dbg_qdesc(0, 0, 0, NUM_DESC_PER_RING, RTE_PMD_QDMA_XDEBUG_DESC_C2H);
            // rte_pmd_qdma_dbg_qdesc(0, 1, 0, NUM_DESC_PER_RING, RTE_PMD_QDMA_XDEBUG_DESC_C2H);
            
            // reg_val = PciRead(user_bar_idx, 0x88, portid);
            // printf("Packet droped : 0x%x\n", reg_val);
            // reg_val = PciRead(user_bar_idx, 0x8C, portid);
            // printf("Packet accepted : 0x%x\n", reg_val);
        }
        for (i = 0; i < nb_rx; i++) {
            // rte_delay_ms(1);
            struct rte_mbuf *mb = pkts[i];
            rte_pktmbuf_free(mb);
            // count += ret;
            // ret = 0;
        }
        recvpkts += nb_rx;
        qid = (qid + 1) % num_queues;
    }
    cur_tsc = rte_rdtsc_precise();
    /* Stop the C2H Engine */
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid); 
    // reg_val &= C2H_CONTROL_REG_MASK;
    // printf("%d\n", reg_val);
    reg_val |= ST_C2H_END_VAL;
    // printf("%d\n", reg_val);
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val,portid);

    diff_tsc = cur_tsc - prev_tsc;
    printf("diff_tsc: %ld\n", diff_tsc);
    // tot_time = diff_tsc*1.0 / rte_get_tsc_hz();
    printf("DMA received number of packets: %ld\n",recvpkts);
    rte_spinlock_unlock(&pinfo[portid].port_update_lock);

    // pkts_per_second = ((double)recvpkts / time_elapsed);

    /* Calculate average throughput (Gbps) in bits per second */
    throughput_gbps = pinfo[portid].buff_size * 8.0 * recvpkts/ (time_elapsed * 1000000000.0);

    printf("Throughput Gbps %lf ", throughput_gbps);
    printf("Number of bytes: %ld ", pinfo[portid].buff_size * recvpkts);
    printf("total latency: %lf\n", time_elapsed);
    //print rate 
    printf("rate arr:\n");
    for (int r = 0 ; r < arr_idx ; r++) {
        printf("%lf ", arr[r]);
    }
    printf("\n");
    // rte_log_dump(fd);
    // // rte_pmd_qdma_dbg_qinfo(portid, 0);
    // fclose(fd);
    rte_eth_dev_stop(portid);

    rte_pmd_qdma_dev_close(portid);
    mp = rte_mempool_lookup(pinfo[portid].mem_pool);

    if (mp != NULL)
        rte_mempool_free(mp);
    rte_eal_cleanup();

    for (idx = 0 ; idx < num_lcores ; idx++) {
        free(lcore_q_map[idx]);
    }
    free(lcore_q_map);
    // free(temp);
    free(recv_pkts);
}

