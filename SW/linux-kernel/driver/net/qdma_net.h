#ifndef __QDMA_NET_H__
#define __QDMA_NET_H__

#include <linux/netdevice.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#include <linux/etherdevice.h>

#include "../libqdma/libqdma_export.h"
#include "../libqdma/qdma_ul_ext.h"
#include "../libqdma/xdev.h"
#include "../src/qdma_mod.h"

/* Queue Configuration */
#define QDMA_NET_TXQ_CNT            1
#define QDMA_NET_RXQ_CNT            1

/* Default Message Enable Flags */
#define QDMA_NET_DEFAULT_MSG_ENABLE \
	(NETIF_MSG_DRV | NETIF_MSG_PROBE | NETIF_MSG_LINK)

/* Network-specific registers in user BAR */
#define QDMA_NET_MAC_LO             0x08E8  /* MAC address low 32 bits */
#define QDMA_NET_MAC_HI             0x08EC  /* MAC address high 16 bits */
#define QDMA_NET_LINK_STATUS        0x08F0  /* Link status register */

/* Link status bits */
#define QDMA_NET_LINK_UP            BIT(0)

#define QDMA_NET_TX_RING_SIZE 512
#define QDMA_NET_RX_RING_SIZE 512
#define QDMA_NET_TX_CTX_POOL_SIZE 2048 // Number of pre-allocated TX contexts

struct qdma_net_meminfo {
	void *memptr;
	unsigned int num_blks;
};

struct qdma_net_mempool {
	void *mempool;
	unsigned int mempool_blkidx;
	unsigned int mempool_blksz;
	unsigned int total_memblks;
	struct qdma_net_meminfo *mempool_info;
};

/* TX context structure */
struct qdma_net_tx_context {
	struct qdma_request req;
	struct qdma_sw_sg sgl[MAX_SKB_FRAGS + 1];
	struct sk_buff *skb;
	struct qdma_net_queue *q;
};

/**
 * struct qdma_net_queue - Per-queue data structure
 * @h2c_qhndl: TX (H2C) queue handle from QDMA driver
 * @c2h_qhndl: RX (C2H) queue handle from QDMA driver
 * @cmpt_qhndl: Completion queue handle (if used)
 * @napi: NAPI structure for interrupt handling
 * @qid: Queue ID
 * @priv: Back pointer to private driver data
 */
struct qdma_net_queue {
	unsigned long h2c_qhndl;
	unsigned long c2h_qhndl;
	unsigned long cmpt_qhndl;

	struct napi_struct napi;
	u16 qid;
	struct qdma_net_priv *priv;

	struct qdma_net_mempool tx_ctx_pool;
};

/**
 * struct qdma_net_priv - Private driver data structure
 * @ndev: Network device structure
 * @pdev: PCI device structure
 * @xdev: QDMA device handle
 * @xpdev: QDMA PCI device structure (for register access)
 * @num_txq: Number of TX queues
 * @num_rxq: Number of RX queues
 * @qs: Array of queue structures
 * @stats: Network device statistics
 * @watchdog_task: Periodic watchdog work
 * @reset_task: Device reset work
 * @msg_enable: Message enable flags for netif_msg_*
 */
struct qdma_net_priv {
	struct net_device *ndev;
	struct pci_dev *pdev;

	/* QDMA device handles */
	struct xlnx_dma_dev *xdev;
	struct xlnx_pci_dev *xpdev;

	/* Queue configuration */
	u16 num_txq;
	u16 num_rxq;
	struct qdma_net_queue *qs;

	/* Statistics */
	struct rtnl_link_stats64 stats;

	/* Work structures */
	struct delayed_work watchdog_task;
	struct work_struct reset_task;

	/* Message enable */
	u32 msg_enable;
};

/* Function Prototypes */

/* Registration functions - called from QDMA driver */
int qdma_net_register(struct pci_dev *pdev, struct xlnx_dma_dev *xdev,
                       struct xlnx_pci_dev *xpdev);
void qdma_net_unregister(struct xlnx_pci_dev *xpdev);

/* TX/RX functions - implemented in qdma_net_txrx.c */
int qdma_net_rx_packet_cb(unsigned long qhndl, unsigned long quld,
                           unsigned int len, unsigned int sgcnt,
                           struct qdma_sw_sg *sgl, void *udd);

int qdma_net_tx_enqueue_skb(struct qdma_net_priv *priv,
                             struct qdma_net_queue *q,
                             struct sk_buff *skb);

/* Memory Pool Management Functions */
int qdma_net_mempool_create(struct qdma_net_mempool *mpool,
	unsigned int entry_size,
	unsigned int max_entries);
void qdma_net_mempool_destroy(struct qdma_net_mempool *mpool);
void *qdma_net_mempool_alloc(struct qdma_net_mempool *mpool,
	unsigned int num_blks);
void qdma_net_mempool_free(struct qdma_net_mempool *mpool,
	void *memptr);

#endif /* __QDMA_NET_H__ */
