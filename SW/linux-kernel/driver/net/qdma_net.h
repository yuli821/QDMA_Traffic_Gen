#ifndef __QDMA_NET_H__
#define __QDMA_NET_H__

#include <linux/netdevice.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#include <linux/etherdevice.h>

#include "libqdma/libqdma_export.h"
#include "libqdma/qdma_ul_ext.h"

#define QDMA_NET_TXQ_CNT	1
#define QDMA_NET_RXQ_CNT	1

// Network-specific registers in user BAR
#define QDMA_NET_MAC_LO          0x08E8  // MAC address low 32 bits
#define QDMA_NET_MAC_HI          0x08EC  // MAC address high 16 bits  
#define QDMA_NET_LINK_STATUS     0x08F0  // Link status register
#define QDMA_NET_CAPABILITIES    0x08F4  // Network capabilities
#define QDMA_NET_FEATURES        0x08F8  // Hardware features
#define QDMA_NET_STATS_BASE      0x0900  // Base for network statistics

struct qdma_net_hw_info {
    u8 mac[ETH_ALEN];
    u32 link_status;
    u32 capabilities;
    u32 features;
};

struct qdma_net_queue {
	unsigned long h2c_qhndl;	/* TX queue handle */
	unsigned long c2h_qhndl;	/* RX queue handle */
	unsigned long cmpt_qhndl;	/* RX completion queue handle */

	struct napi_struct napi;
	u16 qid;
};

struct qdma_net_priv {
	struct net_device *ndev;
	struct pci_dev *pdev;

	/* libqdma device */
	struct xlnx_dma_dev *xdev;

	u16 num_txq;
	u16 num_rxq;
	struct qdma_net_queue *qs;

	/* simple sw stats, expand later */
	struct rtnl_link_stats64 stats;
};

int qdma_net_register(struct pci_dev *pdev, struct xlnx_dma_dev *xdev);
void qdma_net_unregister(struct xlnx_dma_dev *xdev);

#endif /* ifndef __QDMA_NET_H__ */