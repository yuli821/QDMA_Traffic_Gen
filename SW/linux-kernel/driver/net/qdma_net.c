#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/slab.h>

#include "qdma_net.h"

/* module params for queue selection; reserve QID 0 by default */
static ushort qdma_net_qbase = 0;
module_param(qdma_net_qbase, ushort, 0644);
MODULE_PARM_DESC(qdma_net_qbase, "Base QID for netdev queues");
static ushort qdma_net_qcount = 1;
module_param(qdma_net_qcount, ushort, 0644);
MODULE_PARM_DESC(qdma_net_qcount, "Number of queue pairs for netdev");

static int qdma_net_ndo_open(struct net_device *ndev);
static int qdma_net_ndo_stop(struct net_device *ndev);
static netdev_tx_t qdma_net_ndo_start_xmit(struct sk_buff *skb, struct net_device *ndev);
static int qdma_net_napi_poll(struct napi_struct *napi, int budget);
static void qdma_net_ndo_get_stats64(struct net_device *ndev, struct rtnl_link_stats64 *s);

static const struct net_device_ops qdma_netdev_ops = {
	.ndo_open		= qdma_net_ndo_open,
	.ndo_stop		= qdma_net_ndo_stop,
	.ndo_start_xmit		= qdma_net_ndo_start_xmit,
	.ndo_get_stats64	= qdma_net_ndo_get_stats64,
};

static void qdma_net_napi_schedule(void *q_hndl, void *uld)
{
	struct qdma_net_queue *q = (struct qdma_net_queue *)uld;

	if (likely(q))
		napi_schedule(&q->napi);
}

/* Minimal ethtool (stub for now) */
static const struct ethtool_ops qdma_net_ethtool_ops = {
	/* fill in later */
};

static int qdma_net_setup_one_queue(struct qdma_net_priv *priv, struct qdma_net_queue *q)
{
	struct qdma_queue_conf qconf;
	int rv;

	memset(&qconf, 0, sizeof(qconf));

	/* TX: ST H2C */
	qconf.st = 1;
	qconf.q_type = Q_H2C;
	qconf.qidx = qdma_net_qbase + q->qid;
	qconf.desc_rng_sz_idx = 3;		/* ring size index: moderate */
	qconf.pidx_acc = 8;			/* accumulate pidx updates */

	rv = qdma_queue_add((unsigned long)priv->xdev, &qconf, &q->h2c_qhndl, NULL, 0);
	if (rv < 0)
		return rv;
	rv = qdma_queue_config((unsigned long)priv->xdev, q->h2c_qhndl, &qconf, NULL, 0);
	if (rv < 0)
		return rv;

	/* RX: ST C2H */
	memset(&qconf, 0, sizeof(qconf));
	qconf.st = 1;
	qconf.q_type = Q_C2H;
	qconf.qidx = qdma_net_qbase + q->qid;
	qconf.desc_rng_sz_idx = 3;
	qconf.c2h_buf_sz_idx = 0;		/* default buffer size index */
	qconf.cmpl_en_intr = 1;
	qconf.cmpl_trig_mode = 1;		/* timer */
	qconf.cmpl_timer_idx = 3;
	qconf.cmpl_cnt_th_idx = 3;
	qconf.cmpl_desc_sz = 3;			/* 8 << 3 = 64B */
	qconf.adaptive_rx = 0;
	qconf.fp_descq_isr_top = qdma_net_napi_schedule;
	qconf.quld = q;

	rv = qdma_queue_add((unsigned long)priv->xdev, &qconf, &q->c2h_qhndl, NULL, 0);
	if (rv < 0)
		return rv;
	rv = qdma_queue_config((unsigned long)priv->xdev, q->c2h_qhndl, &qconf, NULL, 0);
	if (rv < 0)
		return rv;

	/* RX CMPT */
	memset(&qconf, 0, sizeof(qconf));
	qconf.st = 0;
	qconf.q_type = Q_CMPT;
	qconf.qidx = qdma_net_qbase + q->qid;
	qconf.cmpl_en_intr = 1;
	qconf.cmpl_trig_mode = 1;
	qconf.cmpl_timer_idx = 3;
	qconf.cmpl_cnt_th_idx = 3;
	qconf.cmpl_desc_sz = 3;

	rv = qdma_queue_add((unsigned long)priv->xdev, &qconf, &q->cmpt_qhndl, NULL, 0);
	if (rv < 0)
		return rv;
	rv = qdma_queue_config((unsigned long)priv->xdev, q->cmpt_qhndl, &qconf, NULL, 0);
	if (rv < 0)
		return rv;

	/* Start in order: CMPT -> C2H -> H2C */
	rv = qdma_queue_start((unsigned long)priv->xdev, q->cmpt_qhndl, NULL, 0);
	if (rv < 0)
		return rv;
	rv = qdma_queue_start((unsigned long)priv->xdev, q->c2h_qhndl, NULL, 0);
	if (rv < 0)
		return rv;
	rv = qdma_queue_start((unsigned long)priv->xdev, q->h2c_qhndl, NULL, 0);
	if (rv < 0)
		return rv;

	return 0;
}

static int qdma_net_ndo_open(struct net_device *ndev)
{
	struct qdma_net_priv *priv = netdev_priv(ndev);
	int rv;

	netif_carrier_off(ndev);

	/* Start one queue for now */
	rv = qdma_net_setup_one_queue(priv, &priv->qs[0]);
	if (rv < 0)
		return rv;

	napi_enable(&priv->qs[0].napi);
	netif_tx_start_all_queues(ndev);
	netif_carrier_on(ndev);

	return 0;
}

static int qdma_net_ndo_stop(struct net_device *ndev)
{
	struct qdma_net_priv *priv = netdev_priv(ndev);

	netif_tx_stop_all_queues(ndev);
	napi_disable(&priv->qs[0].napi);

	/* Stop queues */
	qdma_queue_stop((unsigned long)priv->xdev, priv->qs[0].h2c_qhndl, NULL, 0);
	qdma_queue_stop((unsigned long)priv->xdev, priv->qs[0].c2h_qhndl, NULL, 0);
	qdma_queue_stop((unsigned long)priv->xdev, priv->qs[0].cmpt_qhndl, NULL, 0);

	/* Remove queues */
	qdma_queue_remove((unsigned long)priv->xdev, priv->qs[0].h2c_qhndl, NULL, 0);
	qdma_queue_remove((unsigned long)priv->xdev, priv->qs[0].c2h_qhndl, NULL, 0);
	qdma_queue_remove((unsigned long)priv->xdev, priv->qs[0].cmpt_qhndl, NULL, 0);

	return 0;
}

static netdev_tx_t qdma_net_ndo_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	extern int qdma_net_tx_enqueue_skb(struct qdma_net_priv *priv, struct qdma_net_queue *q, struct sk_buff *skb);
	struct qdma_net_priv *priv = netdev_priv(ndev);
	int rv;

	rv = qdma_net_tx_enqueue_skb(priv, &priv->qs[0], skb);
	if (rv < 0) {
		netif_stop_subqueue(ndev, 0);
		return NETDEV_TX_BUSY;
	}

	return NETDEV_TX_OK;
}

static int qdma_net_napi_poll(struct napi_struct *napi, int budget)
{
	struct qdma_net_queue *q = container_of(napi, struct qdma_net_queue, napi);
	struct qdma_net_priv *priv = netdev_priv(q->napi.dev);
	int work = 0;

	/* Service RX completions; Stage 1: no RX delivery yet, just rearm path */
	work = qdma_queue_service((unsigned long)priv->xdev, q->c2h_qhndl, budget, true);
	if (work < budget) {
		napi_complete_done(napi, work);
	}

	return work;
}

static void qdma_net_ndo_get_stats64(struct net_device *ndev, struct rtnl_link_stats64 *s)
{
	struct qdma_net_priv *priv = netdev_priv(ndev);

	*s = priv->stats;
}

int qdma_net_register(struct pci_dev *pdev, struct xlnx_dma_dev *xdev)
{
	struct net_device *ndev;
	struct qdma_net_priv *priv;

	ndev = alloc_etherdev_mq(sizeof(*priv), QDMA_NET_TXQ_CNT);
	if (!ndev)
		return -ENOMEM;

	SET_NETDEV_DEV(ndev, &pdev->dev);
	priv = netdev_priv(ndev);
	priv->ndev = ndev;
	priv->pdev = pdev;
	priv->xdev = xdev;

	priv->num_txq = QDMA_NET_TXQ_CNT;
	priv->num_rxq = QDMA_NET_RXQ_CNT;

	priv->qs = devm_kcalloc(&pdev->dev, 1, sizeof(*priv->qs), GFP_KERNEL);
	if (!priv->qs) {
		free_netdev(ndev);
		return -ENOMEM;
	}
	priv->qs[0].qid = 0;
	netif_napi_add(ndev, &priv->qs[0].napi, qdma_net_napi_poll, 64);

	ndev->netdev_ops = &qdma_netdev_ops;
	ndev->ethtool_ops = &qdma_net_ethtool_ops;

	/* basic features for now; expand later */
	ndev->features = 0;
	ndev->hw_features = 0;
	//eth_hw_addr_random(ndev);

	netif_set_real_num_tx_queues(ndev, QDMA_NET_TXQ_CNT);
	netif_set_real_num_rx_queues(ndev, QDMA_NET_RXQ_CNT);

	return register_netdev(ndev);
}

void qdma_net_unregister(struct xlnx_dma_dev *xdev)
{
	/* locate the net_device associated with xdev */
	/* For Stage 1, we keep a single device; fetch via pci_get_drvdata */
	/* Better: track ndev pointer from xpdev and pass it here */
	/* Stub for now: no-op if not tracked */
}