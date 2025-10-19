/*
 * QDMA Network Driver
 * 
 * Based on Intel e1000 driver structure
 * Adapted for Xilinx QDMA PCIe DMA device acting as a network interface
 *
 * Copyright (c) 2025
 */

#include <linux/module.h>
#include <linux/types.h>
#include <linux/init.h>
#include <linux/pci.h>
#include <linux/vmalloc.h>
#include <linux/pagemap.h>
#include <linux/delay.h>
#include <linux/netdevice.h>
#include <linux/interrupt.h>
#include <linux/tcp.h>
#include <linux/ipv6.h>
#include <linux/slab.h>
#include <net/checksum.h>
#include <net/ip6_checksum.h>
#include <linux/ethtool.h>
#include <linux/if_vlan.h>
#include <linux/etherdevice.h>

#include "qdma_net.h"
#include "../libqdma/libqdma_export.h"
#include "../libqdma/qdma_ul_ext.h"
#include "../libqdma/xdev.h"
#include "../src/qdma_mod.h"

char qdma_net_driver_name[] = "qdma_net";
char qdma_net_driver_string[] = "QDMA Network Driver";
#define DRV_VERSION "1.0.0"
char qdma_net_driver_version[] = DRV_VERSION;

/* ============================================================================
 * FORWARD DECLARATIONS
 * ============================================================================ */

/* Network Device Operations */
static int qdma_net_open(struct net_device *netdev);
static int qdma_net_close(struct net_device *netdev);
static netdev_tx_t qdma_net_xmit_frame(struct sk_buff *skb,
                                        struct net_device *netdev);
static void qdma_net_tx_timeout(struct net_device *netdev, unsigned int txqueue);
static void qdma_net_get_stats64(struct net_device *netdev,
                                  struct rtnl_link_stats64 *stats);
static int qdma_net_change_mtu(struct net_device *netdev, int new_mtu);
static int qdma_net_set_mac(struct net_device *netdev, void *p);
static void qdma_net_set_rx_mode(struct net_device *netdev);

/* Ethtool Operations */
static void qdma_net_get_drvinfo(struct net_device *netdev,
                                  struct ethtool_drvinfo *drvinfo);
static int qdma_net_get_link_ksettings(struct net_device *netdev,
                                        struct ethtool_link_ksettings *cmd);
static int qdma_net_set_link_ksettings(struct net_device *netdev,
                                        const struct ethtool_link_ksettings *cmd);
static u32 qdma_net_get_link(struct net_device *netdev);
static int qdma_net_get_regs_len(struct net_device *netdev);
static void qdma_net_get_regs(struct net_device *netdev,
                               struct ethtool_regs *regs, void *p);
static void qdma_net_get_ringparam(struct net_device *netdev,
                                    struct ethtool_ringparam *ring,
                                    struct kernel_ethtool_ringparam *kernel_ring,
                                    struct netlink_ext_ack *extack);
static int qdma_net_set_ringparam(struct net_device *netdev,
                                   struct ethtool_ringparam *ring,
                                   struct kernel_ethtool_ringparam *kernel_ring,
                                   struct netlink_ext_ack *extack);
static void qdma_net_get_pauseparam(struct net_device *netdev,
                                     struct ethtool_pauseparam *pause);
static int qdma_net_set_pauseparam(struct net_device *netdev,
                                    struct ethtool_pauseparam *pause);
static u32 qdma_net_get_msglevel(struct net_device *netdev);
static void qdma_net_set_msglevel(struct net_device *netdev, u32 data);
static int qdma_net_nway_reset(struct net_device *netdev);
static void qdma_net_get_strings(struct net_device *netdev, u32 stringset,
                                  u8 *data);
static int qdma_net_get_sset_count(struct net_device *netdev, int sset);
static void qdma_net_get_ethtool_stats(struct net_device *netdev,
                                        struct ethtool_stats *stats,
                                        u64 *data);

/* Hardware Access Functions */
static int qdma_net_hw_reset(struct qdma_net_priv *priv);
static void qdma_net_hw_configure(struct qdma_net_priv *priv);
static int qdma_net_hw_init(struct qdma_net_priv *priv);
static void qdma_net_hw_setup_link(struct qdma_net_priv *priv);
static void qdma_net_hw_get_link_status(struct qdma_net_priv *priv);

/* Queue Management Functions */
static int qdma_net_setup_tx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *txq);
static int qdma_net_setup_rx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *rxq);
static void qdma_net_free_tx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *txq);
static void qdma_net_free_rx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *rxq);
static int qdma_net_setup_all_tx_resources(struct qdma_net_priv *priv);
static int qdma_net_setup_all_rx_resources(struct qdma_net_priv *priv);
static void qdma_net_free_all_tx_resources(struct qdma_net_priv *priv);
static void qdma_net_free_all_rx_resources(struct qdma_net_priv *priv);

/* Interrupt and NAPI Functions */
static void qdma_net_napi_enable_all(struct qdma_net_priv *priv);
static void qdma_net_napi_disable_all(struct qdma_net_priv *priv);
static int qdma_net_napi_poll(struct napi_struct *napi, int budget);
static void qdma_net_napi_schedule(unsigned long q_hndl, unsigned long uld);

/* Link Management Functions */
static void qdma_net_watchdog_task(struct work_struct *work);
static void qdma_net_update_stats(struct qdma_net_priv *priv);
static void qdma_net_check_link(struct qdma_net_priv *priv);

/* Utility Functions */
static int qdma_net_up(struct qdma_net_priv *priv);
static void qdma_net_down(struct qdma_net_priv *priv);
static void qdma_net_reset(struct qdma_net_priv *priv);

/* ============================================================================
 * NETWORK DEVICE OPERATIONS STRUCTURE
 * ============================================================================ */

static const struct net_device_ops qdma_net_netdev_ops = {
	.ndo_open               = qdma_net_open,
	.ndo_stop               = qdma_net_close,
	.ndo_start_xmit         = qdma_net_xmit_frame,
	.ndo_get_stats64        = qdma_net_get_stats64,
	.ndo_set_rx_mode        = qdma_net_set_rx_mode,
	.ndo_set_mac_address    = qdma_net_set_mac,
	.ndo_tx_timeout         = qdma_net_tx_timeout,
	.ndo_change_mtu         = qdma_net_change_mtu,
	.ndo_validate_addr      = eth_validate_addr,
};

/* ============================================================================
 * ETHTOOL OPERATIONS STRUCTURE
 * ============================================================================ */

static const struct ethtool_ops qdma_net_ethtool_ops = {
	.get_drvinfo            = qdma_net_get_drvinfo,
	.get_regs_len           = qdma_net_get_regs_len,
	.get_regs               = qdma_net_get_regs,
	.get_link               = qdma_net_get_link,
	.get_link_ksettings     = qdma_net_get_link_ksettings,
	.set_link_ksettings     = qdma_net_set_link_ksettings,
	.get_ringparam          = qdma_net_get_ringparam,
	.set_ringparam          = qdma_net_set_ringparam,
	.get_pauseparam         = qdma_net_get_pauseparam,
	.set_pauseparam         = qdma_net_set_pauseparam,
	.get_msglevel           = qdma_net_get_msglevel,
	.set_msglevel           = qdma_net_set_msglevel,
	.nway_reset             = qdma_net_nway_reset,
	.get_strings            = qdma_net_get_strings,
	.get_sset_count         = qdma_net_get_sset_count,
	.get_ethtool_stats      = qdma_net_get_ethtool_stats,
};

/* ============================================================================
 * HARDWARE ACCESS FUNCTIONS
 * ============================================================================ */

/**
 * qdma_net_hw_read_mac_addr - Read MAC address from hardware
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_hw_read_mac_addr(struct qdma_net_priv *priv)
{
	u32 val;
	int rv;
    u8 mac[ETH_ALEN];

	/* Read MAC address from hardware registers */
	rv = qdma_device_read_user_register(priv->xpdev, QDMA_NET_MAC_LO, &val);
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to read MAC_LO: %d\n", rv);
		return rv;
	}
	mac[2] = (val >> 24) & 0xFF;
	mac[3] = (val >> 16) & 0xFF;
	mac[4] = (val >> 8) & 0xFF;
	mac[5] = (val >> 0) & 0xFF;

	rv = qdma_device_read_user_register(priv->xpdev, QDMA_NET_MAC_HI, &val);
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to read MAC_HI: %d\n", rv);
		return rv;
	}
	mac[0] = (val >> 8) & 0xFF;
	mac[1] = (val >> 0) & 0xFF;

    eth_hw_addr_set(priv->ndev, mac);

	netdev_dbg(priv->ndev, "Read MAC address: %pM\n", priv->ndev->dev_addr);
	return 0;
}

/**
 * qdma_net_hw_reset - Reset hardware
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_hw_reset(struct qdma_net_priv *priv)
{
	netdev_dbg(priv->ndev, "Hardware reset (placeholder)\n");
	/* TODO: Implement hardware reset if needed */
	return 0;
}

/**
 * qdma_net_hw_init - Initialize hardware
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_hw_init(struct qdma_net_priv *priv)
{
	netdev_dbg(priv->ndev, "Hardware init (placeholder)\n");
	/* TODO: Implement hardware initialization if needed */
	return 0;
}

/**
 * qdma_net_hw_configure - Configure hardware settings
 * @priv: private driver data
 */
static void qdma_net_hw_configure(struct qdma_net_priv *priv)
{
	netdev_dbg(priv->ndev, "Hardware configure (placeholder)\n");
	/* TODO: Configure hardware registers (flow control, etc.) */
}

/**
 * qdma_net_hw_setup_link - Setup link parameters
 * @priv: private driver data
 */
static void qdma_net_hw_setup_link(struct qdma_net_priv *priv)
{
	netdev_dbg(priv->ndev, "Setup link (placeholder)\n");
	/* TODO: Configure link speed, duplex if needed */
}

/**
 * qdma_net_hw_get_link_status - Get link status from hardware
 * @priv: private driver data
 */
static void qdma_net_hw_get_link_status(struct qdma_net_priv *priv)
{
	u32 link_status;
	int rv;
	bool link_up;

	rv = qdma_device_read_user_register(priv->xpdev, QDMA_NET_LINK_STATUS,
	                                     &link_status);
	if (rv < 0) {
		netdev_dbg(priv->ndev, "Failed to read link status: %d\n", rv);
		return;
	}

	link_up = !!(link_status & QDMA_NET_LINK_UP);

	if (link_up != netif_carrier_ok(priv->ndev)) {
		if (link_up) {
			netif_carrier_on(priv->ndev);
			netdev_info(priv->ndev, "NIC Link is Up\n");
		} else {
			netif_carrier_off(priv->ndev);
			netdev_info(priv->ndev, "NIC Link is Down\n");
		}
	}
}

/* ============================================================================
 * QUEUE MANAGEMENT FUNCTIONS
 * ============================================================================ */

/**
 * qdma_net_setup_tx_resources - Allocate TX queue resources
 * @priv: private driver data
 * @txq: TX queue
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_setup_tx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *txq)
{
	struct qdma_queue_conf qconf;
    char err_buf[100];
	int rv;

	netdev_dbg(priv->ndev, "Setting up TX queue %u\n", txq->qid);

	memset(&qconf, 0, sizeof(qconf));

	/* TX: ST H2C Queue Configuration */
	qconf.st = 1;  /* Streaming mode */
	qconf.q_type = Q_H2C;
	qconf.qidx = txq->qid;
	qconf.desc_rng_sz_idx = 0;  /* Ring size index */
	qconf.pidx_acc = 8;

	rv = qdma_queue_add(priv->xpdev->dev_hndl, &qconf, &txq->h2c_qhndl, err_buf, sizeof(err_buf));
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to add H2C queue: %d\n", rv);
		return rv;
	}

	rv = qdma_queue_start(priv->xpdev->dev_hndl, txq->h2c_qhndl, err_buf, sizeof(err_buf));
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to start H2C queue: %d\n", rv);
		qdma_queue_remove(priv->xpdev->dev_hndl, txq->h2c_qhndl, err_buf, sizeof(err_buf));
		return rv;
	}

	netdev_dbg(priv->ndev, "TX queue %u setup complete\n", txq->qid);
	return 0;
}

/**
 * qdma_net_setup_rx_resources - Allocate RX queue resources
 * @priv: private driver data
 * @rxq: RX queue
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_setup_rx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *rxq)
{
	struct qdma_queue_conf qconf;
    char err_buf[100];
	int rv;

	netdev_dbg(priv->ndev, "Setting up RX queue %u\n", rxq->qid);

	memset(&qconf, 0, sizeof(qconf));

	/* RX: ST C2H Queue Configuration */
	qconf.st = 1;
	qconf.q_type = Q_C2H;
	qconf.qidx = rxq->qid;
	qconf.desc_rng_sz_idx = 0;
	qconf.c2h_buf_sz_idx = 0;       /* Buffer size index */
	qconf.cmpl_en_intr = 1;         /* Enable completion interrupt */
	qconf.cmpl_trig_mode = 1;       /* Timer trigger */
	qconf.cmpl_timer_idx = 3;
	qconf.cmpl_cnt_th_idx = 3;
	qconf.cmpl_desc_sz = 3;         /* 64B completion */
	qconf.fp_descq_isr_top = qdma_net_napi_schedule;  /* IRQ handler */
	qconf.quld = (unsigned long)rxq;  /* User data for callback */
	qconf.fp_descq_c2h_packet = qdma_net_rx_packet_cb;

	rv = qdma_queue_add(priv->xpdev->dev_hndl, &qconf, &rxq->c2h_qhndl, err_buf, sizeof(err_buf));
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to add C2H queue: %d\n", rv);
		return rv;
	}

	rv = qdma_queue_start(priv->xpdev->dev_hndl, rxq->c2h_qhndl, err_buf, sizeof(err_buf));
	if (rv < 0) {
		netdev_err(priv->ndev, "Failed to start C2H queue: %d\n", rv);
		qdma_queue_remove(priv->xpdev->dev_hndl, rxq->c2h_qhndl, err_buf, sizeof(err_buf));
		return rv;
	}

	netdev_dbg(priv->ndev, "RX queue %u setup complete\n", rxq->qid);
	return 0;
}

/**
 * qdma_net_free_tx_resources - Free TX queue resources
 * @priv: private driver data
 * @txq: TX queue
 */
static void qdma_net_free_tx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *txq)
{
	netdev_dbg(priv->ndev, "Freeing TX queue %u\n", txq->qid);

	if (txq->h2c_qhndl) {
		qdma_queue_stop(priv->xpdev->dev_hndl, txq->h2c_qhndl, NULL, 0);
		qdma_queue_remove(priv->xpdev->dev_hndl, txq->h2c_qhndl, NULL, 0);
		txq->h2c_qhndl = 0;
	}
}

/**
 * qdma_net_free_rx_resources - Free RX queue resources
 * @priv: private driver data
 * @rxq: RX queue
 */
static void qdma_net_free_rx_resources(struct qdma_net_priv *priv,
                                        struct qdma_net_queue *rxq)
{
	netdev_dbg(priv->ndev, "Freeing RX queue %u\n", rxq->qid);

	if (rxq->c2h_qhndl) {
		qdma_queue_stop(priv->xpdev->dev_hndl, rxq->c2h_qhndl, NULL, 0);
		qdma_queue_remove(priv->xpdev->dev_hndl, rxq->c2h_qhndl, NULL, 0);
		rxq->c2h_qhndl = 0;
	}
}

/**
 * qdma_net_setup_all_tx_resources - Allocate all TX queues
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_setup_all_tx_resources(struct qdma_net_priv *priv)
{
	int i, err = 0;

	for (i = 0; i < priv->num_txq; i++) {
		err = qdma_net_setup_tx_resources(priv, &priv->qs[i]);
		if (err)
			goto err_setup_tx;
	}

	return 0;

err_setup_tx:
	/* Free already allocated resources */
	while (i--)
		qdma_net_free_tx_resources(priv, &priv->qs[i]);

	return err;
}

/**
 * qdma_net_setup_all_rx_resources - Allocate all RX queues
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_setup_all_rx_resources(struct qdma_net_priv *priv)
{
	int i, err = 0;

	for (i = 0; i < priv->num_rxq; i++) {
		err = qdma_net_setup_rx_resources(priv, &priv->qs[i]);
		if (err)
			goto err_setup_rx;
	}

	return 0;

err_setup_rx:
	/* Free already allocated resources */
	while (i--)
		qdma_net_free_rx_resources(priv, &priv->qs[i]);

	return err;
}

/**
 * qdma_net_free_all_tx_resources - Free all TX queues
 * @priv: private driver data
 */
static void qdma_net_free_all_tx_resources(struct qdma_net_priv *priv)
{
	int i;

	for (i = 0; i < priv->num_txq; i++)
		qdma_net_free_tx_resources(priv, &priv->qs[i]);
}

/**
 * qdma_net_free_all_rx_resources - Free all RX queues
 * @priv: private driver data
 */
static void qdma_net_free_all_rx_resources(struct qdma_net_priv *priv)
{
	int i;

	for (i = 0; i < priv->num_rxq; i++)
		qdma_net_free_rx_resources(priv, &priv->qs[i]);
}

/* ============================================================================
 * INTERRUPT AND NAPI FUNCTIONS
 * ============================================================================ */

/**
 * qdma_net_napi_schedule - Schedule NAPI (called from interrupt)
 * @q_hndl: queue handle
 * @uld: user data (queue pointer)
 */
static void qdma_net_napi_schedule(unsigned long q_hndl, unsigned long uld)
{
	struct qdma_net_queue *q = (struct qdma_net_queue *)uld;

	if (likely(q && q->priv && q->priv->ndev))
		napi_schedule(&q->napi);
}

/**
 * qdma_net_napi_poll - NAPI poll handler
 * @napi: NAPI structure
 * @budget: maximum number of packets to process
 *
 * Returns number of packets processed
 */
static int qdma_net_napi_poll(struct napi_struct *napi, int budget)
{
	struct qdma_net_queue *q = container_of(napi, struct qdma_net_queue, napi);
	struct qdma_net_priv *priv = q->priv;
	int work_done;

	/* Service RX completions from QDMA */
	work_done = qdma_queue_service(priv->xpdev->dev_hndl,
	                                q->c2h_qhndl, budget, true);

	if (work_done < budget) {
		napi_complete_done(napi, work_done);
		/* Re-enable interrupts if needed */
	}

	return work_done;
}

/**
 * qdma_net_napi_enable_all - Enable NAPI on all queues
 * @priv: private driver data
 */
static void qdma_net_napi_enable_all(struct qdma_net_priv *priv)
{
	int i;

	for (i = 0; i < priv->num_rxq; i++)
		napi_enable(&priv->qs[i].napi);
}

/**
 * qdma_net_napi_disable_all - Disable NAPI on all queues
 * @priv: private driver data
 */
static void qdma_net_napi_disable_all(struct qdma_net_priv *priv)
{
	int i;

	for (i = 0; i < priv->num_rxq; i++)
		napi_disable(&priv->qs[i].napi);
}

/* ============================================================================
 * LINK AND WATCHDOG FUNCTIONS
 * ============================================================================ */

/**
 * qdma_net_update_stats - Update device statistics
 * @priv: private driver data
 */
static void qdma_net_update_stats(struct qdma_net_priv *priv)
{
	/* TODO: Read hardware statistics registers if available */
	netdev_dbg(priv->ndev, "Update stats (placeholder)\n");
}

/**
 * qdma_net_check_link - Check link status
 * @priv: private driver data
 */
static void qdma_net_check_link(struct qdma_net_priv *priv)
{
	qdma_net_hw_get_link_status(priv);
}

/**
 * qdma_net_watchdog_task - Periodic watchdog task
 * @work: work structure
 */
static void qdma_net_watchdog_task(struct work_struct *work)
{
	struct qdma_net_priv *priv = container_of(to_delayed_work(work),
	                                           struct qdma_net_priv,
	                                           watchdog_task);

	qdma_net_update_stats(priv);
	qdma_net_check_link(priv);

	/* Reschedule watchdog every 2 seconds */
	schedule_delayed_work(&priv->watchdog_task, 2 * HZ);
}

/* ============================================================================
 * DEVICE UP/DOWN FUNCTIONS
 * ============================================================================ */

/**
 * qdma_net_up - Bring device up
 * @priv: private driver data
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_up(struct qdma_net_priv *priv)
{
	int err;

	netdev_dbg(priv->ndev, "Bringing device up\n");

	/* Configure hardware */
	qdma_net_hw_configure(priv);

	/* Setup TX resources */
	err = qdma_net_setup_all_tx_resources(priv);
	if (err) {
		netdev_err(priv->ndev, "Failed to setup TX resources: %d\n", err);
		goto err_setup_tx;
	}

	/* Setup RX resources */
	err = qdma_net_setup_all_rx_resources(priv);
	if (err) {
		netdev_err(priv->ndev, "Failed to setup RX resources: %d\n", err);
		goto err_setup_rx;
	}

	/* Enable NAPI */
	qdma_net_napi_enable_all(priv);

	/* Check link */
	qdma_net_check_link(priv);

	/* Start watchdog */
	schedule_delayed_work(&priv->watchdog_task, HZ);

	netdev_info(priv->ndev, "Device is up\n");
	return 0;

err_setup_rx:
	qdma_net_free_all_tx_resources(priv);
err_setup_tx:
	qdma_net_hw_reset(priv);
	return err;
}

/**
 * qdma_net_down - Bring device down
 * @priv: private driver data
 */
static void qdma_net_down(struct qdma_net_priv *priv)
{
	netdev_dbg(priv->ndev, "Bringing device down\n");

	/* Cancel watchdog */
	cancel_delayed_work_sync(&priv->watchdog_task);

	/* Disable carrier */
	netif_carrier_off(priv->ndev);

	/* Disable NAPI */
	qdma_net_napi_disable_all(priv);

	/* Free resources */
	qdma_net_free_all_tx_resources(priv);
	qdma_net_free_all_rx_resources(priv);

	netdev_info(priv->ndev, "Device is down\n");
}

/**
 * qdma_net_reset - Reset device
 * @priv: private driver data
 */
static void qdma_net_reset(struct qdma_net_priv *priv)
{
	netdev_info(priv->ndev, "Resetting device\n");

	/* Bring down */
	qdma_net_down(priv);

	/* Reset hardware */
	qdma_net_hw_reset(priv);

	/* Bring up */
	qdma_net_up(priv);
}

/* ============================================================================
 * NETWORK DEVICE OPERATIONS IMPLEMENTATION
 * ============================================================================ */

/**
 * qdma_net_open - Called when network interface is enabled
 * @netdev: network interface device structure
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_open(struct net_device *netdev)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);
	int err;

	netdev_info(netdev, "Opening network interface\n");

	/* Bring device up */
	err = qdma_net_up(priv);
	if (err)
		return err;

	/* Start TX queue */
	netif_tx_start_all_queues(netdev);

	return 0;
}

/**
 * qdma_net_close - Called when network interface is disabled
 * @netdev: network interface device structure
 *
 * Returns 0 on success
 */
static int qdma_net_close(struct net_device *netdev)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	netdev_info(netdev, "Closing network interface\n");

	/* Stop TX queue */
	netif_tx_stop_all_queues(netdev);

	/* Bring device down */
	qdma_net_down(priv);

	return 0;
}

/**
 * qdma_net_xmit_frame - Transmit a packet
 * @skb: socket buffer containing packet
 * @netdev: network interface device structure
 *
 * Returns NETDEV_TX_OK on success
 */
static netdev_tx_t qdma_net_xmit_frame(struct sk_buff *skb,
                                        struct net_device *netdev)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);
	struct qdma_net_queue *txq = &priv->qs[0];  /* Use first queue */
	int err;

	/* Transmit packet via QDMA */
	err = qdma_net_tx_enqueue_skb(priv, txq, skb);
	if (err) {
		priv->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	/* SKB will be freed by completion callback */
	return NETDEV_TX_OK;
}

/**
 * qdma_net_tx_timeout - Handle TX timeout
 * @netdev: network interface device structure
 * @txqueue: queue that timed out
 */
static void qdma_net_tx_timeout(struct net_device *netdev, unsigned int txqueue)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	netdev_err(netdev, "TX timeout on queue %u\n", txqueue);

	priv->stats.tx_errors++;

	/* Reset device */
	schedule_work(&priv->reset_task);
}

/**
 * qdma_net_get_stats64 - Get device statistics
 * @netdev: network interface device structure
 * @stats: storage for statistics
 */
static void qdma_net_get_stats64(struct net_device *netdev,
                                  struct rtnl_link_stats64 *stats)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	qdma_net_update_stats(priv);
	*stats = priv->stats;
}

/**
 * qdma_net_set_rx_mode - Set RX mode (multicast, promiscuous, etc.)
 * @netdev: network interface device structure
 */
static void qdma_net_set_rx_mode(struct net_device *netdev)
{
	//struct qdma_net_priv *priv = netdev_priv(netdev);

	netdev_dbg(netdev, "Set RX mode (placeholder)\n");
	/* TODO: Configure multicast filter, promiscuous mode */
}

/**
 * qdma_net_set_mac - Set MAC address
 * @netdev: network interface device structure
 * @p: pointer to sockaddr containing new MAC
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_set_mac(struct net_device *netdev, void *p)
{
	//struct qdma_net_priv *priv = netdev_priv(netdev);
	struct sockaddr *addr = p;

	if (!is_valid_ether_addr(addr->sa_data))
		return -EADDRNOTAVAIL;

    eth_hw_addr_set(netdev, addr->sa_data);

	netdev_info(netdev, "MAC address changed to %pM\n", netdev->dev_addr);
	/* TODO: Write new MAC to hardware if supported */

	return 0;
}

/**
 * qdma_net_change_mtu - Change MTU
 * @netdev: network interface device structure
 * @new_mtu: new MTU value
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_change_mtu(struct net_device *netdev, int new_mtu)
{
	//struct qdma_net_priv *priv = netdev_priv(netdev);

	netdev_info(netdev, "Changing MTU from %d to %d\n", netdev->mtu, new_mtu);

	netdev->mtu = new_mtu;

	/* TODO: Reconfigure hardware if needed */

	return 0;
}

/* ============================================================================
 * ETHTOOL OPERATIONS IMPLEMENTATION
 * ============================================================================ */

/**
 * qdma_net_get_drvinfo - Get driver information
 * @netdev: network interface device structure
 * @drvinfo: driver information structure
 */
static void qdma_net_get_drvinfo(struct net_device *netdev,
                                  struct ethtool_drvinfo *drvinfo)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	strscpy(drvinfo->driver, qdma_net_driver_name, sizeof(drvinfo->driver));
	strscpy(drvinfo->version, qdma_net_driver_version, sizeof(drvinfo->version));
	strscpy(drvinfo->bus_info, pci_name(priv->pdev), sizeof(drvinfo->bus_info));
}

/**
 * qdma_net_get_link - Get link status
 * @netdev: network interface device structure
 *
 * Returns 1 if link is up, 0 otherwise
 */
static u32 qdma_net_get_link(struct net_device *netdev)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	qdma_net_check_link(priv);
	return netif_carrier_ok(netdev) ? 1 : 0;
}

/**
 * qdma_net_get_link_ksettings - Get link settings
 * @netdev: network interface device structure
 * @cmd: settings structure
 *
 * Returns 0 on success
 */
static int qdma_net_get_link_ksettings(struct net_device *netdev,
                                        struct ethtool_link_ksettings *cmd)
{
	netdev_dbg(netdev, "Get link settings (placeholder)\n");

	/* Set defaults for now */
	cmd->base.speed = SPEED_10000;  /* 10 Gbps */
	cmd->base.duplex = DUPLEX_FULL;
	cmd->base.port = PORT_OTHER;
	cmd->base.autoneg = AUTONEG_DISABLE;

	return 0;
}

/**
 * qdma_net_set_link_ksettings - Set link settings
 * @netdev: network interface device structure
 * @cmd: settings structure
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_set_link_ksettings(struct net_device *netdev,
                                        const struct ethtool_link_ksettings *cmd)
{
	netdev_dbg(netdev, "Set link settings (placeholder)\n");
	/* TODO: Configure link speed/duplex if supported */
	return -EOPNOTSUPP;
}

/**
 * qdma_net_get_regs_len - Get register dump length
 * @netdev: network interface device structure
 *
 * Returns size of register dump
 */
static int qdma_net_get_regs_len(struct net_device *netdev)
{
	/* Return size for register dump - placeholder */
	return 256;
}

/**
 * qdma_net_get_regs - Get register dump
 * @netdev: network interface device structure
 * @regs: register info structure
 * @p: buffer for register data
 */
static void qdma_net_get_regs(struct net_device *netdev,
                               struct ethtool_regs *regs, void *p)
{
	netdev_dbg(netdev, "Get registers (placeholder)\n");
	/* TODO: Read and dump hardware registers */
	memset(p, 0, qdma_net_get_regs_len(netdev));
}

/**
 * qdma_net_get_ringparam - Get ring parameters
 * @netdev: network interface device structure
 * @ring: ring parameters structure
 * @kernel_ring: kernel ring parameters
 * @extack: netlink extended ack
 */
static void qdma_net_get_ringparam(struct net_device *netdev,
                                    struct ethtool_ringparam *ring,
                                    struct kernel_ethtool_ringparam *kernel_ring,
                                    struct netlink_ext_ack *extack)
{
	//struct qdma_net_priv *priv = netdev_priv(netdev);

	/* Report current ring sizes - placeholder values */
	ring->rx_max_pending = 4096;
	ring->tx_max_pending = 4096;
	ring->rx_pending = 512;
	ring->tx_pending = 512;
}

/**
 * qdma_net_set_ringparam - Set ring parameters
 * @netdev: network interface device structure
 * @ring: ring parameters structure
 * @kernel_ring: kernel ring parameters
 * @extack: netlink extended ack
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_set_ringparam(struct net_device *netdev,
                                   struct ethtool_ringparam *ring,
                                   struct kernel_ethtool_ringparam *kernel_ring,
                                   struct netlink_ext_ack *extack)
{
	netdev_dbg(netdev, "Set ring parameters (placeholder)\n");
	/* TODO: Reconfigure ring sizes */
	return -EOPNOTSUPP;
}

/**
 * qdma_net_get_pauseparam - Get pause parameters
 * @netdev: network interface device structure
 * @pause: pause parameters structure
 */
static void qdma_net_get_pauseparam(struct net_device *netdev,
                                     struct ethtool_pauseparam *pause)
{
	netdev_dbg(netdev, "Get pause parameters (placeholder)\n");
	pause->autoneg = 0;
	pause->rx_pause = 0;
	pause->tx_pause = 0;
}

/**
 * qdma_net_set_pauseparam - Set pause parameters
 * @netdev: network interface device structure
 * @pause: pause parameters structure
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_set_pauseparam(struct net_device *netdev,
                                    struct ethtool_pauseparam *pause)
{
	netdev_dbg(netdev, "Set pause parameters (placeholder)\n");
	/* TODO: Configure flow control */
	return -EOPNOTSUPP;
}

/**
 * qdma_net_get_msglevel - Get message level
 * @netdev: network interface device structure
 *
 * Returns current message level
 */
static u32 qdma_net_get_msglevel(struct net_device *netdev)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);
	return priv->msg_enable;
}

/**
 * qdma_net_set_msglevel - Set message level
 * @netdev: network interface device structure
 * @data: new message level
 */
static void qdma_net_set_msglevel(struct net_device *netdev, u32 data)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);
	priv->msg_enable = data;
}

/**
 * qdma_net_nway_reset - Restart autonegotiation
 * @netdev: network interface device structure
 *
 * Returns 0 on success, negative on failure
 */
static int qdma_net_nway_reset(struct net_device *netdev)
{
	netdev_dbg(netdev, "Restart autoneg (placeholder)\n");
	/* TODO: Restart link autonegotiation if supported */
	return -EOPNOTSUPP;
}

/**
 * qdma_net_get_strings - Get statistic strings
 * @netdev: network interface device structure
 * @stringset: string set ID
 * @data: buffer for strings
 */
static void qdma_net_get_strings(struct net_device *netdev, u32 stringset,
                                  u8 *data)
{
	netdev_dbg(netdev, "Get strings (placeholder)\n");
	/* TODO: Fill in statistics strings */
}

/**
 * qdma_net_get_sset_count - Get statistics set count
 * @netdev: network interface device structure
 * @sset: statistics set ID
 *
 * Returns number of statistics
 */
static int qdma_net_get_sset_count(struct net_device *netdev, int sset)
{
	netdev_dbg(netdev, "Get stats count (placeholder)\n");
	/* TODO: Return actual statistics count */
	return 0;
}

/**
 * qdma_net_get_ethtool_stats - Get statistics values
 * @netdev: network interface device structure
 * @stats: statistics structure
 * @data: buffer for statistics data
 */
static void qdma_net_get_ethtool_stats(struct net_device *netdev,
                                        struct ethtool_stats *stats,
                                        u64 *data)
{
	struct qdma_net_priv *priv = netdev_priv(netdev);

	qdma_net_update_stats(priv);
	netdev_dbg(netdev, "Get ethtool stats (placeholder)\n");
	/* TODO: Fill in statistics data */
}

/* ============================================================================
 * RESET TASK
 * ============================================================================ */

/**
 * qdma_net_reset_task - Reset task work function
 * @work: work structure
 */
static void qdma_net_reset_task(struct work_struct *work)
{
	struct qdma_net_priv *priv = container_of(work, struct qdma_net_priv,
	                                           reset_task);

	netdev_info(priv->ndev, "Reset task executing\n");

	rtnl_lock();
	if (netif_running(priv->ndev))
		qdma_net_reset(priv);
	rtnl_unlock();
}

/* ============================================================================
 * DEVICE REGISTRATION AND UNREGISTRATION
 * ============================================================================ */

/**
 * qdma_net_register - Register network device
 * @pdev: PCI device structure
 * @xdev: QDMA device handle
 * @xpdev: QDMA PCI device structure
 *
 * Returns 0 on success, negative on failure
 */
int qdma_net_register(struct pci_dev *pdev, struct xlnx_dma_dev *xdev,
                       struct xlnx_pci_dev *xpdev)
{
	struct net_device *netdev;
	struct qdma_net_priv *priv;
	int i, err;

	netdev_info(NULL, "Registering QDMA network device\n");

	/* Allocate network device */
	netdev = alloc_etherdev_mq(sizeof(struct qdma_net_priv),
	                            QDMA_NET_TXQ_CNT);
	if (!netdev) {
		dev_err(&pdev->dev, "Failed to allocate netdev\n");
		return -ENOMEM;
	}

	SET_NETDEV_DEV(netdev, &pdev->dev);

	priv = netdev_priv(netdev);
	priv->ndev = netdev;
	priv->pdev = pdev;
	priv->xdev = xdev;
	priv->xpdev = xpdev;
	priv->msg_enable = netif_msg_init(-1, QDMA_NET_DEFAULT_MSG_ENABLE);
	priv->num_txq = QDMA_NET_TXQ_CNT;
	priv->num_rxq = QDMA_NET_RXQ_CNT;

	/* Allocate queue structures */
	priv->qs = devm_kcalloc(&pdev->dev, priv->num_txq,
	                         sizeof(struct qdma_net_queue), GFP_KERNEL);
	if (!priv->qs) {
		dev_err(&pdev->dev, "Failed to allocate queue structures\n");
		err = -ENOMEM;
		goto err_alloc_queues;
	}

	/* Initialize queues */
	for (i = 0; i < priv->num_txq; i++) {
		priv->qs[i].qid = i;
		priv->qs[i].priv = priv;
		netif_napi_add(netdev, &priv->qs[i].napi, qdma_net_napi_poll);
	}

	/* Setup network device */
	netdev->netdev_ops = &qdma_net_netdev_ops;
	netdev->ethtool_ops = &qdma_net_ethtool_ops;
	netdev->watchdog_timeo = 5 * HZ;

	/* Set features */
	netdev->features = NETIF_F_SG | NETIF_F_HIGHDMA;
	netdev->hw_features = netdev->features;

	/* Set MTU limits */
	netdev->min_mtu = ETH_MIN_MTU;
	netdev->max_mtu = ETH_DATA_LEN;  /* 1500 */

	/* Initialize work structures */
	INIT_DELAYED_WORK(&priv->watchdog_task, qdma_net_watchdog_task);
	INIT_WORK(&priv->reset_task, qdma_net_reset_task);

	/* Hardware initialization */
	err = qdma_net_hw_init(priv);
	if (err) {
		dev_err(&pdev->dev, "Hardware initialization failed: %d\n", err);
		goto err_hw_init;
	}

	/* Read MAC address from hardware */
	err = qdma_net_hw_read_mac_addr(priv);
	if (err || !is_valid_ether_addr(netdev->dev_addr)) {
		dev_warn(&pdev->dev, "Invalid MAC address, using random\n");
		eth_hw_addr_random(netdev);
	}

	/* Setup link */
	qdma_net_hw_setup_link(priv);

	/* Set real number of queues */
	netif_set_real_num_tx_queues(netdev, priv->num_txq);
	netif_set_real_num_rx_queues(netdev, priv->num_rxq);

	/* Initial carrier off */
	netif_carrier_off(netdev);

	/* Register network device */
	err = register_netdev(netdev);
	if (err) {
		dev_err(&pdev->dev, "Failed to register netdev: %d\n", err);
		goto err_register;
	}

	/* Store netdev in xpdev for cleanup */
	xpdev->ndev = netdev;

	netdev_info(netdev, "%s: QDMA Network Device\n", netdev->name);
	netdev_info(netdev, "Address: %pM\n", netdev->dev_addr);
	netdev_info(netdev, "Driver: %s Version: %s\n",
	            qdma_net_driver_string, qdma_net_driver_version);

	return 0;

err_register:
err_hw_init:
	for (i = 0; i < priv->num_txq; i++)
		netif_napi_del(&priv->qs[i].napi);
err_alloc_queues:
	free_netdev(netdev);
	return err;
}

/**
 * qdma_net_unregister - Unregister network device
 * @xpdev: QDMA PCI device structure
 */
void qdma_net_unregister(struct xlnx_pci_dev *xpdev)
{
	struct net_device *netdev;
	struct qdma_net_priv *priv;
	int i;

	if (!xpdev || !xpdev->ndev)
		return;

	netdev = xpdev->ndev;
	priv = netdev_priv(netdev);

	netdev_info(netdev, "Unregistering QDMA network device\n");

	/* Cancel work */
	cancel_delayed_work_sync(&priv->watchdog_task);
	cancel_work_sync(&priv->reset_task);

	/* Unregister network device */
	unregister_netdev(netdev);

	/* Remove NAPI */
	for (i = 0; i < priv->num_txq; i++)
		netif_napi_del(&priv->qs[i].napi);

	/* Free network device */
	free_netdev(netdev);

	xpdev->ndev = NULL;

	pr_info("QDMA network device unregistered\n");
}

