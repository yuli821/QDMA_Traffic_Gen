
#define QDMA_MAX_PORTS	256

#define PORT_0 0

#define NUM_DESC_PER_RING 1024

#define NUM_RX_PKTS (NUM_DESC_PER_RING-2)
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
#define ST_C2H_IMMEDIATE_DATA_EN     0x4
#define C2H_CONTROL_REG_MASK         0xF
#define H2C_CONTROL_REG    0xC
#define H2C_STATUS_REG    0x10
#define C2H_PACKET_COUNT_REG    0x20
#define C2H_STATUS_REG                    0x18
#define C2H_STREAM_MARKER_PKT_GEN_VAL     0x22
#define MARKER_RESPONSE_COMPLETION_BIT    0x1

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

extern struct port_info pinfo[QDMA_MAX_PORTS];

