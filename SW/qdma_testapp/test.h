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
#include <rte_timer.h>

#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include <time.h>

#include "/home/yuli9/dpdk_test_area/dpdk-stable/drivers/net/qdma/rte_pmd_qdma.h"
#include "pcierw.h"
#include "qdma_regs.h"

#define QDMA_MAX_PORTS	256

#define PORT_0 0

#define NUM_DESC_PER_RING 2048

#define NUM_RX_PKTS (NUM_DESC_PER_RING-1)
//#define NUM_RX_PKTS 32
#define NUM_TX_PKTS 64

#define MAX_NUM_QUEUES  2048
#define DEFAULT_NUM_QUEUES 64
#define RX_TX_MAX_RETRY			1500
#define DEFAULT_RX_WRITEBACK_THRESH	(64)

#define MP_CACHE_SZ     512
#define MBUF_POOL_NAME_PORT   "mbuf_pool_%d"

/* AXI Master Lite bar(user bar) registers */
#define C2H_ST_QID_REG    0x0
#define C2H_ST_LEN_REG    0x4
#define C2H_CONTROL_REG              0x8
#define ST_LOOPBACK_EN               0x1
#define ST_C2H_START_VAL             0x2
#define ST_C2H_END_VAL             0x40
#define ST_C2H_PERF_ENABLE         0x80
#define ST_C2H_IMMEDIATE_DATA_EN     0x4
#define C2H_CONTROL_REG_MASK         0xF
#define H2C_CONTROL_REG    0xC
#define H2C_STATUS_REG    0x10
#define CYCLES_PER_PKT    0x1C
#define C2H_NUM_QUEUES    0x28
#define C2H_PACKET_COUNT_REG    0x20
#define C2H_STATUS_REG                    0x18
#define C2H_STREAM_MARKER_PKT_GEN_VAL     0x22
#define MARKER_RESPONSE_COMPLETION_BIT    0x1
#define RSS_START 		0xA8 //128 entries
// #define RSS_END 		0x2A4
#define DATA_START      0xE8

#define BURST_SIZE 128
#define MBUF_SIZE 2048
#define CHANGE_INDRECT_TABLE 1

extern int num_ports;

struct port_info {
	int config_bar_idx;
	int user_bar_idx;
	int bypass_bar_idx;
	unsigned int queue_base;
	unsigned int num_queues;
	unsigned int nb_descs;
	unsigned int st_queues;
	unsigned int buff_size;
	rte_spinlock_t port_update_lock;
	char mem_pool[RTE_MEMPOOL_NAMESIZE];
};

typedef struct input_arg {
    int** core_to_q;
    int numpkts;
    int portid;
} input_arg_t;

extern struct port_info pinfo[QDMA_MAX_PORTS];

int comp (const void * elem1, const void * elem2) {
    int f = *((int*)elem1);
    int s = *((int*)elem2);
    return ((f>s) - (f<s));
}

int port_init(int portid, int num_queues, int st_queues, uint16_t nb_descs, int buff_size)
{
    struct rte_mempool *mbuf_pool;
    struct rte_eth_conf port_conf;
    struct rte_eth_txconf tx_conf;
    struct rte_eth_rxconf rx_conf;
    int diag, x;
    uint32_t queue_base, nb_buff;

    printf("Setting up port :%d.\n", portid);
    int socket_id = rte_eth_dev_socket_id(portid);

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

    // Adjust number of descriptors
    diag = rte_eth_dev_adjust_nb_rx_tx_desc(portid, &nb_descs, &nb_descs);
    if (diag != 0) {
        fprintf(stderr, "rte_eth_dev_adjust_nb_rx_tx_desc failed\n");
        return diag;
    }

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

        diag = rte_eth_tx_queue_setup(portid, x, nb_descs, socket_id, &tx_conf);
        if (diag < 0)
            rte_exit(EXIT_FAILURE, "Cannot setup port %d TX Queue id:%d (err=%d)\n", portid, x, diag);
        rx_conf.rx_thresh.wthresh = DEFAULT_RX_WRITEBACK_THRESH;
        diag = rte_eth_rx_queue_setup(portid, x, nb_descs, socket_id, &rx_conf, mbuf_pool);
        if (diag < 0)
            rte_exit(EXIT_FAILURE, "Cannot setup port %d RX Queue 0 (err=%d)\n", portid, diag);
    }
    // rte_pmd_qdma_set_c2h_descriptor_prefetch(portid, 0, 1);
    // rte_pmd_qdma_set_cmpt_trigger_mode(portid, 0, RTE_PMD_QDMA_TRIG_MODE_EVERY);

    diag = rte_eth_dev_start(portid);
    if (diag < 0)
        rte_exit(EXIT_FAILURE, "Cannot start port %d (err=%d)\n", portid, diag);

    return 0;
}

extern int port, num_queues, stqueues, pktsize, numpkts, cycles, interval;


struct option long_options[] = {
    {"port",        required_argument,  0,  'p'},
    {"num_queues",  required_argument,  0,  'q'},
    {"stqueues",    required_argument,  0,  'Q'},
    {"pktsize",     required_argument,  0,  's'},
    {"numpkts",     required_argument,  0,  'n'},
    {"cycles",  	required_argument,  0,  'c'},
    {"interval",  	required_argument,  0,  'i'},
    {"help",        no_argument,        0,  'h'},
    {0,             0,                  0,  0  }
};

static int parse_args(int argc, char **argv) {
    char short_options[] = "p:q:Q:s:n:c:i:h";
    char *prgname = argv[0];
    int nb_required_args = 0;
    int retval;

    while (1) {
        int c = getopt_long(argc, argv, short_options, long_options, NULL);
        if (c == -1) {
            break;
        }
		char **endptr;

        switch (c) {
        case 'p':
    		port = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'q':
			num_queues = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'Q':
			stqueues = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 's':
			pktsize = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'n':
			numpkts = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'c':
			cycles = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'i':
			interval = (uint32_t)strtol(optarg, endptr, 10);
            break;

        case 'h':
        default:
            // print_usage(prgname);
            return -1;
        }
    }

    if (optind >= 0) {
        argv[optind - 1] = prgname;
    }
    optind = 1;

    return 0;
}
