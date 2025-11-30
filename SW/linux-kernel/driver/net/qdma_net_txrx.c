/*
 * QDMA Network Driver - TX/RX Path Implementation
 *
 * Handles packet transmission and reception via QDMA queues
 */

#include <linux/skbuff.h>
#include <linux/netdevice.h>
#include <linux/dma-mapping.h>

#include "qdma_net.h"

/**
 * qdma_net_tx_complete_cb - TX completion callback
 * @req: QDMA request that completed
 * @bytes_done: number of bytes transferred
 * @err: error code (0 on success)
 *
 * Called when a TX DMA transfer completes
 */
static int qdma_net_tx_complete_cb(struct qdma_request *req,
                                    unsigned int bytes_done, int err)
{
	struct qdma_net_tx_context *tx_ctx;
	struct qdma_net_priv *priv;
	struct sk_buff *skb;
	unsigned int i;

	if (!req || !req->uld_data)
		return -EINVAL;

	tx_ctx = (struct qdma_net_tx_context *)req->uld_data;
	skb = tx_ctx->skb;
	
	if (!tx_ctx->q || !tx_ctx->q->priv) {
		pr_err("qdma_net: TX complete cb - invalid queue or priv\n");
		if (skb)
			dev_kfree_skb_any(skb);
		return -EINVAL;
	}
	
	priv = tx_ctx->q->priv;

	pr_info("qdma_net: TX complete cb - bytes_done=%u, err=%d\n", bytes_done, err);

	/* Unmap DMA buffers using sgcnt from the request */
	for (i = 0; i < tx_ctx->req.sgcnt; i++) {
		if (tx_ctx->sgl[i].dma_addr) {
			dma_unmap_single(&priv->pdev->dev, tx_ctx->sgl[i].dma_addr,
			                 tx_ctx->sgl[i].len, DMA_TO_DEVICE);
		}
	}

	/* Update statistics */
	if (err) {
		priv->stats.tx_errors++;
	} else {
		priv->stats.tx_packets++;
		priv->stats.tx_bytes += bytes_done;
	}

	/* Free SKB */
	if (skb)
		dev_kfree_skb_any(skb);

	/* Free TX context back to pool */
	qdma_net_mempool_free(&tx_ctx->q->tx_ctx_pool, tx_ctx);

	return 0;
}

/**
 * qdma_net_build_req_from_skb - Build QDMA request from SKB
 * @priv: private driver data
 * @skb: socket buffer to transmit
 * @req: QDMA request to fill
 * @sgl: scatter-gather list to fill
 * @sgcnt: output - number of SG entries used
 *
 * Maps SKB data to DMA addresses and fills the scatter-gather list
 */
static int qdma_net_build_req_from_skb(struct qdma_net_priv *priv,
                                        struct sk_buff *skb,
                                        struct qdma_request *req,
                                        struct qdma_sw_sg *sgl,
                                        unsigned int *sgcnt)
{
	unsigned int nr_frags = skb_shinfo(skb)->nr_frags;
	unsigned int headlen = skb_headlen(skb);
	dma_addr_t dma_addr;
	unsigned int i;
	unsigned int sg_idx = 0;

	/* Map SKB head (linear data) */
	if (headlen > 0) {
		dma_addr = dma_map_single(&priv->pdev->dev, skb->data,
		                          headlen, DMA_TO_DEVICE);
		if (dma_mapping_error(&priv->pdev->dev, dma_addr)) {
			pr_err("qdma_net: Failed to map SKB head\n");
			return -ENOMEM;
		}

		sgl[sg_idx].next = (sg_idx + 1 < nr_frags + 1) ? &sgl[sg_idx + 1] : NULL;
		sgl[sg_idx].pg = virt_to_page(skb->data);
		sgl[sg_idx].offset = offset_in_page(skb->data);
		sgl[sg_idx].len = headlen;
		sgl[sg_idx].dma_addr = dma_addr;
		sg_idx++;
	}

	/* Map SKB fragments */
	for (i = 0; i < nr_frags; i++) {
		skb_frag_t *frag = &skb_shinfo(skb)->frags[i];
		unsigned int frag_len = skb_frag_size(frag);

		dma_addr = skb_frag_dma_map(&priv->pdev->dev, frag, 0,
		                            frag_len, DMA_TO_DEVICE);
		if (dma_mapping_error(&priv->pdev->dev, dma_addr)) {
			pr_err("qdma_net: Failed to map SKB frag %u\n", i);
			/* Unmap previously mapped buffers */
			while (sg_idx--) {
				if (sgl[sg_idx].dma_addr)
					dma_unmap_single(&priv->pdev->dev, sgl[sg_idx].dma_addr,
					                 sgl[sg_idx].len, DMA_TO_DEVICE);
			}
			return -ENOMEM;
		}

		sgl[sg_idx].next = (i + 1 < nr_frags) ? &sgl[sg_idx + 1] : NULL;
		sgl[sg_idx].pg = skb_frag_page(frag);
		sgl[sg_idx].offset = skb_frag_off(frag);
		sgl[sg_idx].len = frag_len;
		sgl[sg_idx].dma_addr = dma_addr;
		sg_idx++;
	}

	*sgcnt = sg_idx;

	/* Fill QDMA request */
	req->count = skb->len;
	req->sgcnt = sg_idx;
	req->sgl = sgl;
	req->write = 1;  /* H2C (Host to Card) */
	req->dma_mapped = 1;  /* We've already mapped the buffers */
	req->h2c_eot = 1;  /* End of transfer */
	req->fp_done = qdma_net_tx_complete_cb;

	return 0;
}

/**
 * qdma_net_tx_enqueue_skb - Enqueue SKB for transmission
 * @priv: private driver data
 * @q: TX queue
 * @skb: socket buffer to transmit
 *
 * Returns 0 on success, negative on failure
 */
int qdma_net_tx_enqueue_skb(struct qdma_net_priv *priv,
                             struct qdma_net_queue *q,
                             struct sk_buff *skb)
{
	struct qdma_net_tx_context *tx_ctx;
	unsigned int sgcnt = 0;
	int rv;

	pr_info("qdma_net: TX enqueue start - skb len=%u, nr_frags=%d\n",
		skb->len, skb_shinfo(skb)->nr_frags);

	/* Allocate TX context from memory pool */
	tx_ctx = qdma_net_mempool_alloc(&q->tx_ctx_pool, 1);
	if (!tx_ctx) {
		pr_err("qdma_net: Failed to allocate TX context\n");
		return -ENOMEM;
	}

	memset(tx_ctx, 0, sizeof(*tx_ctx));
	tx_ctx->skb = skb;
	tx_ctx->q = q;  /* Store queue pointer for completion callback */

	/* Build QDMA request from SKB */
	rv = qdma_net_build_req_from_skb(priv, skb, &tx_ctx->req, tx_ctx->sgl, &sgcnt);
	if (rv < 0) {
		pr_err("qdma_net: Failed to build request from SKB: %d\n", rv);
		qdma_net_mempool_free(&q->tx_ctx_pool, tx_ctx);
		return rv;
	}

	tx_ctx->req.uld_data = (unsigned long)tx_ctx;

	pr_info("qdma_net: TX req built - count=%u, sgcnt=%u, dev_hndl=0x%lx, qhndl=0x%lx\n",
		tx_ctx->req.count, tx_ctx->req.sgcnt,
		priv->xpdev->dev_hndl, q->h2c_qhndl);

	/* Submit to QDMA */
	//rv = qdma_queue_packet_write(priv->xpdev->dev_hndl, q->h2c_qhndl, &tx_ctx->req);
	rv = qdma_request_submit(priv->xpdev->dev_hndl, q->h2c_qhndl, &tx_ctx->req);
	
	pr_info("qdma_net: TX qdma_queue_packet_write returned %d (expected: %u)\n",
		rv, tx_ctx->req.count);

	if (rv < 0) {
		pr_err("qdma_net: qdma_queue_packet_write failed: %d\n", rv);
		/* Unmap DMA buffers */
		for (sgcnt = 0; sgcnt < tx_ctx->req.sgcnt; sgcnt++) {
			if (tx_ctx->sgl[sgcnt].dma_addr)
				dma_unmap_single(&priv->pdev->dev, tx_ctx->sgl[sgcnt].dma_addr,
				                 tx_ctx->sgl[sgcnt].len, DMA_TO_DEVICE);
		}
		qdma_net_mempool_free(&q->tx_ctx_pool, tx_ctx);
		return rv;
	}

	return 0;
}

/**
 * qdma_net_rx_packet_cb - RX packet callback
 * @q_hndl: queue handle
 * @q_hndl_uld: user data (queue pointer)
 * @pkt_len: packet length
 * @sgcnt: scatter-gather count
 * @sgl: scatter-gather list
 * @udd: user-defined data from completion
 *
 * Called when a packet is received from the FPGA
 */
int qdma_net_rx_packet_cb(unsigned long q_hndl, unsigned long q_hndl_uld,
                           unsigned int pkt_len, unsigned int sgcnt,
                           struct qdma_sw_sg *sgl, void *udd)
{
	struct qdma_net_queue *rxq = (struct qdma_net_queue *)q_hndl_uld;
	struct qdma_net_priv *priv;
	struct net_device *netdev;
	struct sk_buff *skb;
	struct qdma_sw_sg *sg;
	unsigned int i;
	unsigned int copied = 0;

	if (!rxq || !rxq->priv || !rxq->priv->ndev) {
		pr_err("qdma_net: RX callback with invalid queue\n");
		return -EINVAL;
	}

	priv = rxq->priv;
	netdev = priv->ndev;

	pr_info("qdma_net: RX packet - len=%u, sgcnt=%u\n", pkt_len, sgcnt);

	/* Allocate SKB for received packet */
	skb = netdev_alloc_skb_ip_align(netdev, pkt_len);
	if (!skb) {
		pr_err("qdma_net: Failed to allocate RX SKB\n");
		priv->stats.rx_dropped++;
		return -ENOMEM;
	}

	/* Copy data from scatter-gather list to SKB */
	for (i = 0, sg = sgl; i < sgcnt && sg && copied < pkt_len; i++, sg = sg->next) {
		unsigned int copy_len = min(sg->len, pkt_len - copied);
		void *data;

		if (sg->pg) {
			data = kmap_atomic(sg->pg) + sg->offset;
			skb_put_data(skb, data, copy_len);
			kunmap_atomic(data - sg->offset);
		}
		copied += copy_len;
	}

	/* Set up SKB metadata */
	skb->protocol = eth_type_trans(skb, netdev);
	skb->ip_summed = CHECKSUM_NONE;  /* TODO: HW checksum offload */

	/* Update statistics */
	priv->stats.rx_packets++;
	priv->stats.rx_bytes += pkt_len;

	/* Pass to network stack */
	napi_gro_receive(&rxq->napi, skb);

	return 0;
}
