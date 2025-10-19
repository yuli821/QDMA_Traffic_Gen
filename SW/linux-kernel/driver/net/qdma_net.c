#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/ethtool.h>
#include <linux/slab.h>

#include "qdma_net.h"
#include "../libqdma/libqdma_export.h"
#include "../libqdma/qdma_ul_ext.h"
#include "../libqdma/xdev.h"
#include "../src/qdma_mod.h"

/* Forward declarations */
static int qdma_net_ndo_open(struct net_device *ndev);
static int qdma_net_ndo_stop(struct net_device *ndev);
static netdev_tx_t qdma_net_ndo_start_xmit(struct sk_buff *skb, 
                                            struct net_device *ndev);
static void qdma_net_ndo_get_stats64(struct net_device *ndev, 
                                      struct rtnl_link_stats64 *s);

/* Network device operations */
static const struct net_device_ops qdma_netdev_ops = {
	.ndo_open		= qdma_net_ndo_open,
	.ndo_stop		= qdma_net_ndo_stop,
	.ndo_start_xmit		= qdma_net_ndo_start_xmit,
	.ndo_get_stats64	= qdma_net_ndo_get_stats64,
};

/* Read hardware info using DMA driver functions */
static int qdma_net_read_hw_info(struct xlnx_pci_dev *xpdev, 
                                   struct qdma_net_hw_info *info)
{
    u32 val;
    int rv;

    memset(info, 0, sizeof(*info));

    /* Read MAC address - USE DMA DRIVER FUNCTION */
    rv = qdma_device_read_user_register(xpdev, QDMA_NET_MAC_LO, &val);
    if (rv < 0) {
        pr_err("Failed to read MAC_LO: %d\n", rv);
        return rv;
    }
    info->mac[2] = (val >> 24) & 0xFF;
    info->mac[3] = (val >> 16) & 0xFF;
    info->mac[4] = (val >> 8) & 0xFF;
    info->mac[5] = (val >> 0) & 0xFF;
    
    rv = qdma_device_read_user_register(xpdev, QDMA_NET_MAC_HI, &val);
    if (rv < 0) {
        pr_err("Failed to read MAC_HI: %d\n", rv);
        return rv;
    }
    info->mac[0] = (val >> 8) & 0xFF;
    info->mac[1] = (val >> 0) & 0xFF;

    /* Read link status - USE DMA DRIVER FUNCTION */
    rv = qdma_device_read_user_register(xpdev, QDMA_NET_LINK_STATUS, 
                                         &info->link_status);
    if (rv < 0) {
        pr_err("Failed to read link status: %d\n", rv);
        return rv;
    }

    pr_info("Read MAC: %pM, Link: 0x%x\n", info->mac, info->link_status);
    return 0;
}

/* Link monitoring work */
static void qdma_net_link_work(struct work_struct *work)
{
    struct qdma_net_priv *priv = container_of(to_delayed_work(work),
                                               struct qdma_net_priv,
                                               link_work);
    u32 link_status;
    int rv;
    bool link_up;

    /* Read link status using DMA driver function */
    rv = qdma_device_read_user_register(priv->xpdev, QDMA_NET_LINK_STATUS,
                                         &link_status);
    if (rv < 0) {
        pr_err_ratelimited("Failed to read link status: %d\n", rv);
        goto reschedule;
    }

    link_up = !!(link_status & QDMA_NET_LINK_UP);

    if (link_up != priv->link_up) {
        priv->link_up = link_up;
        if (link_up) {
            netif_carrier_on(priv->ndev);
            netdev_info(priv->ndev, "Link is Up\n");
        } else {
            netif_carrier_off(priv->ndev);
            netdev_info(priv->ndev, "Link is Down\n");
        }
    }

reschedule:
    /* Check link every 2 seconds */
    schedule_delayed_work(&priv->link_work, 2 * HZ);
}

/* Minimal ethtool support */
static void qdma_net_get_drvinfo(struct net_device *ndev,
                                  struct ethtool_drvinfo *info)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);
    
    // strlcpy(info->driver, "qdma_net", sizeof(info->driver));
    // strlcpy(info->version, "1.0", sizeof(info->version));
    // strlcpy(info->bus_info, pci_name(priv->pdev), sizeof(info->bus_info));
    strscpy(info->driver, "qdma_net", sizeof(info->driver));
    strscpy(info->version, "1.0", sizeof(info->version));
    strscpy(info->bus_info, pci_name(priv->pdev), sizeof(info->bus_info));
}

static u32 qdma_net_get_link(struct net_device *ndev)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);
    return priv->link_up ? 1 : 0;
}

static const struct ethtool_ops qdma_net_ethtool_ops = {
    .get_drvinfo    = qdma_net_get_drvinfo,
    .get_link       = qdma_net_get_link,
};

static void qdma_net_napi_schedule(unsigned long q_hndl, unsigned long uld)
{
    struct qdma_net_queue *q = (struct qdma_net_queue *)uld;
    
    if (likely(q))
        napi_schedule(&q->napi);
}

static int qdma_net_napi_poll(struct napi_struct *napi, int budget)
{
    struct qdma_net_queue *q = container_of(napi, struct qdma_net_queue, napi);
    struct qdma_net_priv *priv = q->priv;
    int work_done;

    /* Service RX completions */
    work_done = qdma_queue_service((unsigned long)priv->xdev, 
                                    q->c2h_qhndl, budget, true);
    
    if (work_done < budget) {
        napi_complete_done(napi, work_done);
    }

    return work_done;
}

static int qdma_net_setup_one_queue(struct qdma_net_priv *priv, 
    struct qdma_net_queue *q)
{
    struct qdma_queue_conf qconf;
    int rv;

    memset(&qconf, 0, sizeof(qconf));

    /* TX: ST H2C Queue */
    qconf.st = 1;  // Streaming mode
    qconf.q_type = Q_H2C;
    qconf.qidx = q->qid;
    qconf.desc_rng_sz_idx = 3;  // Ring size index
    qconf.pidx_acc = 8;

    rv = qdma_queue_add((unsigned long)priv->xdev, &qconf, 
    &q->h2c_qhndl, NULL, 0);
    if (rv < 0) {
        netdev_err(priv->ndev, "Failed to add H2C queue: %d\n", rv);
        return rv;
    }

    rv = qdma_queue_start((unsigned long)priv->xdev, q->h2c_qhndl, NULL, 0);
    if (rv < 0) {
        netdev_err(priv->ndev, "Failed to start H2C queue: %d\n", rv);
        return rv;
    }

    /* RX: ST C2H Queue */
    //Interupt timer can be tuned.
    memset(&qconf, 0, sizeof(qconf));
    qconf.st = 1;
    qconf.q_type = Q_C2H;
    qconf.qidx = q->qid;
    qconf.desc_rng_sz_idx = 3;
    qconf.c2h_buf_sz_idx = 0;  // Buffer size index
    qconf.cmpl_en_intr = 1;    // Enable completion interrupt
    qconf.cmpl_trig_mode = 1;   // Timer trigger
    qconf.cmpl_timer_idx = 3;
    qconf.cmpl_cnt_th_idx = 3;
    qconf.cmpl_desc_sz = 3;     // 64B completion
    qconf.fp_descq_isr_top = qdma_net_napi_schedule;  // IRQ handler
    qconf.quld = (unsigned long)q;  // User data for callback
    qconf.fp_descq_c2h_packet = qdma_net_rx_packet_cb;

    rv = qdma_queue_add((unsigned long)priv->xdev, &qconf, &q->c2h_qhndl, NULL, 0);
    if (rv < 0) {
        netdev_err(priv->ndev, "Failed to add C2H queue: %d\n", rv);
        goto cleanup_h2c;
    }

    rv = qdma_queue_start((unsigned long)priv->xdev, q->c2h_qhndl, NULL, 0);
    if (rv < 0) {
        netdev_err(priv->ndev, "Failed to start C2H queue: %d\n", rv);
        goto cleanup_h2c;
    }

    netdev_info(priv->ndev, "Queue %u setup complete\n", q->qid);
    return 0;

cleanup_h2c:
    qdma_queue_stop((unsigned long)priv->xdev, q->h2c_qhndl, NULL, 0);
    qdma_queue_remove((unsigned long)priv->xdev, q->h2c_qhndl, NULL, 0);
    return rv;
}

/* Network device operations - stubs for now */
static int qdma_net_ndo_open(struct net_device *ndev)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);
    int rv;

    netdev_info(ndev, "Opening network device\n");
    
    netif_carrier_off(ndev);

    /* Setup and start DMA queue */
    rv = qdma_net_setup_one_queue(priv, &priv->qs[0]);
    if (rv < 0) {
        netdev_err(ndev, "Failed to setup queue: %d\n", rv);
        return rv;
    }

    /* Enable NAPI */
    napi_enable(&priv->qs[0].napi);
    
    /* Start TX queues */
    netif_tx_start_all_queues(ndev);
    
    /* Start link monitoring */
    schedule_delayed_work(&priv->link_work, HZ);
    
    /* Set carrier on if link is up */
    if (priv->link_up)
        netif_carrier_on(ndev);

    netdev_info(ndev, "Network device ready for traffic\n");
    return 0;
}

static int qdma_net_ndo_stop(struct net_device *ndev)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);

    netdev_info(ndev, "Stopping network device\n");
    
    netif_tx_stop_all_queues(ndev);
    netif_carrier_off(ndev);
    
    /* Stop link monitoring */
    cancel_delayed_work_sync(&priv->link_work);
    
    /* Disable NAPI */
    napi_disable(&priv->qs[0].napi);

    /* Stop and remove DMA queues */
    qdma_queue_stop((unsigned long)priv->xdev, priv->qs[0].h2c_qhndl, NULL, 0);
    qdma_queue_stop((unsigned long)priv->xdev, priv->qs[0].c2h_qhndl, NULL, 0);
    
    qdma_queue_remove((unsigned long)priv->xdev, priv->qs[0].h2c_qhndl, NULL, 0);
    qdma_queue_remove((unsigned long)priv->xdev, priv->qs[0].c2h_qhndl, NULL, 0);

    return 0;
}

static netdev_tx_t qdma_net_ndo_start_xmit(struct sk_buff *skb, 
                                            struct net_device *ndev)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);
    struct qdma_net_queue *q = &priv->qs[0];  // Use queue 0
    int rv;
    
    /* Submit packet to QDMA */
    rv = qdma_net_tx_enqueue_skb(priv, q, skb);
    if (rv < 0) {
        priv->stats.tx_dropped++;
        dev_kfree_skb_any(skb);
        return NETDEV_TX_OK;
    }
    
    /* SKB will be freed by completion callback */
    return NETDEV_TX_OK;
}

static void qdma_net_ndo_get_stats64(struct net_device *ndev, 
                                      struct rtnl_link_stats64 *s)
{
    struct qdma_net_priv *priv = netdev_priv(ndev);
    *s = priv->stats;
}

/* Registration function - called from DMA driver probe */
int qdma_net_register(struct pci_dev *pdev, struct xlnx_dma_dev *xdev,
                       struct xlnx_pci_dev *xpdev)
{
    struct net_device *ndev;
    struct qdma_net_priv *priv;
    struct qdma_net_hw_info hw_info;
    int rv;

    pr_info("Registering QDMA network device\n");

    /* Allocate network device */
    ndev = alloc_etherdev_mq(sizeof(*priv), QDMA_NET_TXQ_CNT);
    if (!ndev) {
        pr_err("Failed to allocate netdev\n");
        return -ENOMEM;
    }

    SET_NETDEV_DEV(ndev, &pdev->dev);
    priv = netdev_priv(ndev);
    priv->ndev = ndev;
    priv->pdev = pdev;
    priv->xdev = xdev;
    priv->xpdev = xpdev;  // Store for register access
    priv->num_txq = QDMA_NET_TXQ_CNT;
    priv->num_rxq = QDMA_NET_RXQ_CNT;

    /*Allocate queues*/
    priv->qs = devm_kzalloc(&pdev->dev, sizeof(*priv->qs), GFP_KERNEL);
    if (!priv->qs) {
        pr_err("Failed to allocate queues\n");
        free_netdev(ndev);
        return -ENOMEM;
    }
    priv->qs[0].qid = 0;
    priv->qs[0].priv = priv;

    /*Initialize NAPI for RX*/
    //64: NAPI weight, default budget, maximum pkts to process per poll before returning to the kernel.
    // netif_napi_add(ndev, &priv->qs[0].napi, qdma_net_napi_poll, 64);
    netif_napi_add(ndev, &priv->qs[0].napi, qdma_net_napi_poll);

    /* Read hardware info using DMA driver functions */
    rv = qdma_net_read_hw_info(xpdev, &hw_info);
    if (rv < 0) {
        pr_warn("Failed to read HW MAC, using random MAC\n");
        eth_hw_addr_random(ndev);
    } else {
        /* Check if MAC is valid */
        if (is_valid_ether_addr(hw_info.mac)) {
            eth_hw_addr_set(ndev, hw_info.mac);
            pr_info("Using hardware MAC address: %pM\n", hw_info.mac);
        } else {
            pr_warn("Invalid hardware MAC (all zeros?), using random\n");
            eth_hw_addr_random(ndev);
        }
        
        /* Set initial link state */
        priv->link_up = !!(hw_info.link_status & QDMA_NET_LINK_UP);
    }

    /* Set up network device */
    ndev->netdev_ops = &qdma_netdev_ops;
    ndev->ethtool_ops = &qdma_net_ethtool_ops;

    /* Minimal features for now */
    ndev->features = NETIF_F_SG; //|         // Scatter-gather ✅ you have
                 // NETIF_F_HW_CSUM |       // Hardware checksum (if HW supports)
                 // NETIF_F_TSO |          // TCP Segmentation Offload (advanced)
                 // NETIF_F_TSO6;          // TSO for IPv6 (advanced)
    ndev->hw_features = ndev->features;
    
    /* Set MTU limits */
    ndev->min_mtu = ETH_MIN_MTU;
    ndev->max_mtu = ETH_DATA_LEN;  // Standard 1500 for now

    /* Initialize link work */
    INIT_DELAYED_WORK(&priv->link_work, qdma_net_link_work);

    /* Set TX queue configuration */
    netif_set_real_num_tx_queues(ndev, QDMA_NET_TXQ_CNT);
    netif_set_real_num_rx_queues(ndev, QDMA_NET_RXQ_CNT);

    /* Set initial carrier state based on hardware link status */
    if (priv->link_up) {
        netif_carrier_on(ndev);
        pr_info("Initial link state: UP\n");
    } else {
        netif_carrier_off(ndev);
        pr_info("Initial link state: DOWN\n");
    }

    /* Register network device */
    rv = register_netdev(ndev);
    if (rv < 0) {
        pr_err("Failed to register netdev: %d\n", rv);
        free_netdev(ndev);
        return rv;
    }

    netdev_info(ndev, "QDMA network device registered successfully\n");
    netdev_info(ndev, "MAC Address: %pM\n", ndev->dev_addr);
    
    /* Store netdev in xdev for cleanup */
    xpdev->ndev = ndev;

    return 0;
}

void qdma_net_unregister(struct xlnx_pci_dev *xpdev)
{
    struct net_device *ndev;
    struct qdma_net_priv *priv;

    if (!xpdev || !xpdev->ndev)  // ✅ Get from xpdev
        return;

    ndev = xpdev->ndev;  // ✅ Get from xpdev
    priv = netdev_priv(ndev);
    
    /* Cancel any pending work */
    cancel_delayed_work_sync(&priv->link_work);
    
    unregister_netdev(ndev);
    free_netdev(ndev);
    
    pr_info("QDMA network device unregistered\n");
}