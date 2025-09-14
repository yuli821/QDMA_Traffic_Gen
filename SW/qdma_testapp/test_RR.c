#include "test.h"

// #define RTE_LIBRTE_QDMA_PMD 1
#define MAX_RX_QUEUE_PER_LCORE 16
#define MAX_TX_QUEUE_PER_PORT 16

/* Input option initialization */
int port = 0;
int num_queues = 1;
int stqueues = 1;
int pktsize = 1024;
int numpkts = 0;
int cycles = 0;
int interval = 10;

int test_finished = 0;
int num_ports;
struct port_info pinfo[QDMA_MAX_PORTS];
uint64_t packet_recv_per_core[16];
unsigned int table[100][512];

unsigned int num_lcores;

struct lcore_queue_conf {
	unsigned n_rx_port;
	unsigned rx_port_list[MAX_RX_QUEUE_PER_LCORE];
} __rte_cache_aligned;
struct lcore_queue_conf lcore_queue_conf[RTE_MAX_LCORE];


static int recv_pkt_single_core(input_arg_t* inputs) { // for each lcore
    int idx2, idx = rte_lcore_id();
    int** core_to_q = inputs->core_to_q;
    int numpkts = inputs->numpkts;
    int portid = inputs->portid;
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    int nb_rx, nb_tx;

    printf("start test on core %d\n", idx);
    size_t offset = sizeof(struct rte_ether_hdr) + sizeof(struct rte_ipv4_hdr) + sizeof(struct rte_udp_hdr);
    uint32_t input_data = 0;

    while(!test_finished) {
        idx2 = 0;
        while(core_to_q[idx][idx2] != -1) {
            // rte_delay_us(1);
            nb_rx = rte_eth_rx_burst(portid, core_to_q[idx][idx2], pkts, BURST_SIZE);
            // for (int i = 0; i < nb_rx; i++) {
            //     uint32_t *data = rte_pktmbuf_mtod_offset(pkts[i], uint32_t *, offset);
            //     input_data += data[0];
            // }
            nb_tx = rte_eth_tx_burst(portid, core_to_q[idx][idx2], pkts, nb_rx);

            packet_recv_per_core[idx] += nb_rx;

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
    
    long int recvpkts = 0;
    int i, j, nb_tx, nb_rx;
    unsigned int q_data_size = 0;
    uint64_t dst_addr = 0, src_addr = 0;
    //streaming
    unsigned int max_completion_size = 0, last_pkt_size = 0, only_pkt = 0;
    unsigned int max_rx_retry, rcv_count = 0, num_pkts_recv = 0, total_rcv_pkts = 0;
    int user_bar_idx;
    unsigned int reg_val, loopback_en;
    int qbase, diag;
    struct rte_mbuf *nxtmb;

    ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        rte_exit(EXIT_FAILURE, "Invalid EAL arguments\n");
    }
    rte_log_set_global_level(RTE_LOG_ERR);

    argc -= ret;
    argv += ret;

   ret =  parse_args(argc, argv);
    if (ret < 0) {
        rte_exit(EXIT_FAILURE, "Invalid application arguments\n");
    }

    printf("Ethernet Device Count: %d\n", (int)rte_eth_dev_count_avail());
    printf("Logical Core Count: %d\n", rte_lcore_count());

    num_ports = rte_eth_dev_count_avail();
    if (num_ports < 1)
        rte_exit(EXIT_FAILURE, "No Ethernet devices found. Try updating the FPGA image.\n");

    for (int portid = 0; portid < num_ports; portid++)
        rte_spinlock_init(&pinfo[portid].port_update_lock);

    /* Allocate aligned mezone */
    rte_pmd_qdma_compat_memzone_reserve_aligned();

    ret = port_init(port, num_queues, stqueues, numdescs, MBUF_SIZE);

    mp = rte_mempool_lookup(pinfo[port].mem_pool);

    if (mp == NULL) {
        printf("Could not find mempool with name %s\n",
        pinfo[port].mem_pool);
        // rte_spinlock_unlock(&pinfo[port].port_update_lock);
        return -1;
    }

    num_lcores = rte_lcore_count();
    int** lcore_q_map = (int**)malloc(num_lcores * sizeof(int*));  //index 0: core id, rest: queueid
    int q_per_core = num_queues / (num_lcores-1);
    if (num_queues % (num_lcores-1) != 0) {
        q_per_core++;
    } 
    int q_count = pinfo[port].queue_base;

    int idx = 0;
    RTE_LCORE_FOREACH(i) {
        int* pp = (int*)malloc(sizeof(int)*(q_per_core+1));
        pp[q_per_core] = -1;
        lcore_q_map[i] = pp;
    }
    for (int x = 0 ; x < q_per_core ; x++) {
        for (idx = 0 ; idx < num_lcores-1 ; idx++) {
            if (q_count < (num_queues+pinfo[port].queue_base)) {
                lcore_q_map[idx][x] = q_count;
                q_count++;
            } else {
                lcore_q_map[idx][x] = -1;
            }
        }
    }

    qbase = pinfo[port].queue_base;
    
    int size;
    double pkts_per_second, throughput_gbps;
    user_bar_idx = pinfo[port].user_bar_idx;

    int qid = 0;
    for (i = 0 ; i < 16 ; i++) {
        PciWrite(user_bar_idx, RSS_START + (i*4), qid+qbase, port);
        qid = (qid + 1) % num_queues;
    }

    double arr[10];
    int index = 0;
    uint64_t hz = rte_get_timer_hz();
    uint64_t ms = 0.1 * hz;
    uint64_t interval_cycles = interval * hz;

    max_completion_size = pktsize; //datasize + headersize
    printf("max_completion_size: %d\n", max_completion_size);
    PciWrite(user_bar_idx, C2H_PACKET_COUNT_REG, numpkts, port);
    PciWrite(user_bar_idx, C2H_ST_LEN_REG, max_completion_size, port);
    PciWrite(user_bar_idx, CYCLES_PER_PKT, cycles, port);
    PciWrite(user_bar_idx, C2H_NUM_QUEUES, num_queues, port);

    qid = 0;
    double time_elapsed = 0.0, time_elapsed2 = 0.0;
    double rate = 0.0;

    printf("num_lcore is %d, num_queue is %d\n", num_lcores-1, num_queues);

    input_arg_t* temp = (input_arg_t*)malloc(sizeof(input_arg_t));
    temp->core_to_q = lcore_q_map;
    temp->numpkts = numpkts;
    temp->portid = port;

    /* Start the C2H Engine */
    PciWrite(user_bar_idx, C2H_ST_QID_REG, qbase, port);
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, port);
    reg_val |= ST_C2H_START_VAL;
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, port);

    prev_tsc = rte_rdtsc_precise();
    test_tsc = prev_tsc;

    rte_eal_mp_remote_launch((lcore_function_t*)&recv_pkt_single_core, temp, SKIP_MAIN);

    // Monitor and print
    while(1){
        cur_tsc = rte_rdtsc_precise();
        diff_tsc = cur_tsc - prev_tsc;

        // print tput every 1s
        if (diff_tsc > ms) {
            for (i = 0 ; i < 512 ; i++) {
                table[index][i] = PciRead(user_bar_idx, DATA_START+i*4,port);
            }
            prev_tsc = cur_tsc;
            index++;
            // if (cur_tsc - test_tsc < 5*hz) {
            //     for (i = 0 ; i < 16 ; i++) {
            //         PciWrite(user_bar_idx, RSS_START + (i*4), qid1+qbase, portid);
            //     }
            //     qid1 = (qid1 + 1) % num_queues;
            // }
        }
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

    /* Stop the C2H Engine */
    reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, port); 
    reg_val |= ST_C2H_END_VAL;
    PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val,port);

    /* Calculate average throughput (Gbps) in bits per second */
    // throughput_gbps = pinfo[port].buff_size * 8.0 * number_pkts_prev / (double)diff_tsc * (double)hz / 1000000000.0;
    // printf("Throughput Gbps %lf ", throughput_gbps);
    // printf("Number of bytes: %ld ", pinfo[port].buff_size * recvpkts);
    // printf("total latency: %lf\n", (double)diff_tsc/ (double)hz);

    char filename[100];
    sprintf(filename, "./result/round_trip_%d.txt", max_completion_size);
    FILE* file1 = fopen(filename, "w");
    for (i = 0 ; i < 99 ; i++) {
        for (j = 0 ; j < 512 ; j++) {
            fprintf(file1, "%d\n", table[i][j]);
        }
    }
    fclose(file1);

    rte_eth_dev_stop(port);

    rte_pmd_qdma_dev_close(port);
    mp = rte_mempool_lookup(pinfo[port].mem_pool);

    if (mp != NULL)
        rte_mempool_free(mp);
    rte_eal_cleanup();

    for (idx = 0 ; idx < num_lcores ; idx++) {
        free(lcore_q_map[idx]);
    }
    free(lcore_q_map);
    free(temp);
}