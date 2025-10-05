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