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
#include "/home/yuli9/qdma_ip_driver/QDMA/DPDK/drivers/net/qdma/rte_pmd_qdma.h"
#include "test.h"
#include "pcierw.h"
#include "qdma_regs.h"

// #define RTE_LIBRTE_QDMA_PMD 1
#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16

int test_finished = 0;
int num_ports;
struct port_info pinfo[QDMA_MAX_PORTS];
uint64_t packet_recv_per_core[16];
unsigned int table[100][512];

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
    // nb_buff = RTE_MAX(nb_buff, MP_CACHE_SZ * 2);

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
    int nb_rx, nb_tx, count_pkt;
    int idx2, idx = rte_lcore_id();
    int** core_to_q = inputs->core_to_q;
    int numpkts = inputs->numpkts;
    int portid = inputs->portid;
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    uint64_t prev_tsc, cur_tsc;
    double rate = 0.0, elapsed_time = 0.0;

    printf("start test on core %d\n", idx);

    while(!test_finished) {
        idx2 = 0;
        while(core_to_q[idx][idx2] != -1) {
            // rte_delay_us(1);
            nb_rx = rte_eth_rx_burst(portid, core_to_q[idx][idx2], pkts, 1);
            nb_tx = rte_eth_tx_burst(portid, core_to_q[idx][idx2], pkts, nb_rx);
            packet_recv_per_core[idx] += nb_rx;
            // for (int i = 0; i < nb_rx; i++) {
            for (int i = nb_tx; i < nb_rx; i++) {
                rte_pktmbuf_free(pkts[i]);
            }
            idx2++;
        }
    }
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
    if (argc == 12) {
        portid = atoi(argv[7]);
        num_queues = atoi(argv[8]); //self-defined parameter
        stqueues = atoi(argv[8]); //self-defined parameter
        buffsize = atoi(argv[9]); //self-defined parameter
        numpkts = atoi(argv[10]);
        cycles = atoi(argv[11]);
    } else if (argc == 13) {
        portid = atoi(argv[8]);
        num_queues = atoi(argv[9]); //self-defined parameter
        stqueues = atoi(argv[9]); //self-defined parameter
        buffsize = atoi(argv[10]); //self-defined parameter
        numpkts = atoi(argv[11]);
        cycles = atoi(argv[12]);
    } else {
        printf("./build/test -c 0xf --main-lcore [lcoreid] -n 4 portid num_queues buffsize numpkts cycles_per_pkt\n");
        printf("./build/test --log-level=pmd:debug -c 0xf --main-lcore [lcoreid] -n 4 portid num_queues buffsize numpkts cycles_per_pkt\n");
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
    unsigned int reg_val, loopback_en;
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

    ret = port_init(portid, num_queues, stqueues, numdescs, 2048);

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
        for (idx = 0 ; idx < num_lcores-1 ; idx++) {
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
    double pkts_per_second, throughput_gbps;
    user_bar_idx = pinfo[portid].user_bar_idx;

    // reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
    // reg_val &= C2H_CONTROL_REG_MASK;
    // loopback_en = reg_val & ST_LOOPBACK_EN;

    int qid = 0, qid1=0;
    for (i = 0 ; i < 16 ; i++) {
        // if (i < 8) {
        //     PciWrite(user_bar_idx, RSS_START + (i*4), qbase, portid);
        // } else if (i < 12) {
        //     PciWrite(user_bar_idx, RSS_START + (i*4), 1+qbase, portid);
        // } else if (i < 15) {
        //     PciWrite(user_bar_idx, RSS_START + (i*4), 2+qbase, portid);
        // } else {
        //     PciWrite(user_bar_idx, RSS_START + (i*4), 3+qbase, portid);
        // }
        PciWrite(user_bar_idx, RSS_START + (i*4), qbase, portid);
        // qid = rand() % num_queues;
        qid = (qid + 1) % num_queues;
    }

    // reg_val &= C2H_CONTROL_REG_MASK;

    max_completion_size = buffsize + 54; //datasize + headersize
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

    input_arg_t* temp = (input_arg_t*)malloc(sizeof(input_arg_t));
    temp->core_to_q = lcore_q_map;
    temp->numpkts = numpkts;
    temp->portid = portid;

    rte_eal_mp_remote_launch((lcore_function_t*)&recv_pkt_single_core, temp, SKIP_MAIN);
    
    double arr[10];
    int index = 0;
    uint64_t number_pkts = 0, number_pkts_prev = 0;
    uint64_t hz = rte_get_timer_hz();
    uint64_t interval_cycles = 10 * hz;
    // printf("%ld\n", hz);
    uint64_t ms = 0.1*hz; //1ms 
    bool first = true;
    prev_tsc = rte_rdtsc_precise();
    test_tsc = prev_tsc;
    // Monitor and print
    while(1){
        cur_tsc = rte_rdtsc_precise();
        diff_tsc = cur_tsc - prev_tsc;

        // print tput every 1ms
        // if (diff_tsc > ms) {
        //     for (i = 0; i < 512; i++) {
        //         // number_pkts += packet_recv_per_core[i];
        //         // printf("c%d %ld\n", i, packet_recv_per_core[i]);
        //         table[index][i] = PciRead(user_bar_idx, DATA_START+i*4, portid);
                
        //         // table[index][i] = reg_val;
        //     }
        //     // number_pkts = 0;
        //     // for (i = qbase ; i < (qbase + num_lcores-1) ; i++) {
        //     //     number_pkts += packet_recv_per_core[i];
        //     //     // printf("c%d %ld\n", i, packet_recv_per_core[i]);
        //     // }
        //     // rate = (double)(number_pkts - number_pkts_prev) * max_completion_size * 8.0 / (double)diff_tsc * (double)hz / 1000000000.0;
        //     // printf("Throughput is %lf Gbps\n", rate);
        //     // number_pkts_prev = number_pkts;
        //     // arr[index] = rate;
        //     prev_tsc = cur_tsc;
        //     index++;
        //     // if (cur_tsc - test_tsc < 5*hz) {
        //     //     for (i = 0 ; i < 16 ; i++) {
        //     //         PciWrite(user_bar_idx, RSS_START + (i*4), qid1+qbase, portid);
        //     //     }
        //     //     qid1 = (qid1 + 1) % num_queues;
        //     // }
        // }
        // if ((cur_tsc - test_tsc >= 5 * hz) && first) {
        //     first = false;
        //     for (i = 0 ; i < 16 ; i++) {
        //         PciWrite(user_bar_idx, RSS_START + (i*4), qid+qbase, portid);
        //         qid = (qid + 1) % num_queues;
        //     }
        // }
        if (cur_tsc - test_tsc >= interval_cycles) {
            test_finished = 1;
            break;
        }
    }

    // cur_tsc = rte_rdtsc_precise();
    /* Stop the C2H Engine */
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid); 
    // reg_val &= C2H_CONTROL_REG_MASK;
    // printf("%d\n", reg_val);
    reg_val |= ST_C2H_END_VAL;
    // printf("%d\n", reg_val);
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val,portid);

    // diff_tsc = cur_tsc - test_tsc;
    // printf("diff_tsc: %ld\n", diff_tsc);

    // for (int i = 0; i < num_lcores-1; i++) {
    //     recvpkts += packet_recv_per_core[i];
    // }
    printf("DMA received number of packets: %ld\n",number_pkts_prev);
    rte_spinlock_unlock(&pinfo[portid].port_update_lock);

    /* Calculate average throughput (Gbps) in bits per second */
    // throughput_gbps = pinfo[portid].buff_size * 8.0 * number_pkts_prev / (double)diff_tsc * (double)hz / 1000000000.0;

    // printf("Throughput Gbps %lf ", throughput_gbps);
    // printf("Number of bytes: %ld ", pinfo[portid].buff_size * recvpkts);
    // printf("total latency: %lf\n", (double)diff_tsc/ (double)hz);
    char filename[100];
    // sprintf(filename, "./result/result_%d.txt", num_queues);
    // FILE* file = fopen(filename, "a");
    // double average;
    // for (i = 0 ; i < index ; i++) {
    //     average += arr[i];
    // }
    // average = average/(1.0*index);
    // fprintf(file, "%lf\n", average);
    // fclose(file);
    sprintf(filename, "./result/round_trip_%d.txt", max_completion_size);
    FILE* file1 = fopen(filename, "w");
    int max1, max2, max3, max4, max5, max6;
    // for (i = 0 ; i < 99 ; i++) {
        // reg_val = PciRead(user_bar_idx, DATA_START+i*4, portid);
        // max1 = 0;
        // max2 = 0;
        // max3 = 0;
        // max4 = 0;
        // max5 = 0;
        // max6 = 0;
        for (j = 0 ; j < 512 ; j++) {
            // if (max1 < table[i][j]) {
            //     max6 = max5;
            //     max5 = max4;
            //     max4 = max3;
            //     max3 = max2;
            //     max2 = max1;
            //     max1 = table[i][j];
            // }
            reg_val = PciRead(user_bar_idx, DATA_START+j*4,portid);
            fprintf(file1, "%d\n", reg_val);
        }
        // if (max6 != 0) {
        //     fprintf(file1, "%d\n", max6);
        // } else if (max5 != 0) {
        //     fprintf(file1, "%d\n", max5);
        // } else if (max4 != 0) {
        //     fprintf(file1, "%d\n", max4);
        // } else if (max3 != 0) {
        //     fprintf(file1, "%d\n", max3);
        // } else if (max2 != 0) {
        //     fprintf(file1, "%d\n", max2);
        // } else {
        //     fprintf(file1, "%d\n", max1);
        // }
    // }
    fclose(file1);

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
    free(temp);
    free(recv_pkts);
}