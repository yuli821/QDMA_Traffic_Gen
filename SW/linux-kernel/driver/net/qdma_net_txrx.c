#include <linux/skbuff.h>
#include <linux/mm.h>
#include <linux/highmem.h>

#include "qdma_net.h"
#include "../libqdma/qdma_ul_ext.h"

/* Translate skb into libqdma qdma_request and submit. Stage 1: simple SG. */

static int qdma_net_tx_done_cb(struct qdma_request *req, unsigned int done, int error)
{
	struct sk_buff *skb = (struct sk_buff *)req->uld_data;
	/* Free SKB on completion */
	dev_kfree_skb_any(skb);
	return 0;
}

static int qdma_net_build_req_from_skb(struct qdma_net_priv *priv, struct sk_buff *skb,
				       struct qdma_request *req,
				       struct qdma_sw_sg *sgl, unsigned int *sgcnt)
{
	unsigned int cnt = 0;
	unsigned int head_len = skb_headlen(skb);
	unsigned int offset;
	struct skb_shared_info *sh = skb_shinfo(skb);
	int i;

	memset(req, 0, sizeof(*req));

	/* Head */
	if (head_len) {
		void *va = skb->data;
		struct page *pg = virt_to_page(va);
		offset = offset_in_page(va);

		sgl[cnt].pg = pg;
		sgl[cnt].offset = offset;
		sgl[cnt].len = head_len;
		sgl[cnt].dma_addr = 0; /* mapped by libqdma if needed */
		cnt++;
	}

	/* Frags */
	for (i = 0; i < sh->nr_frags; i++) {
		const skb_frag_t *f = &sh->frags[i];

		sgl[cnt].pg = skb_frag_page(f);
		sgl[cnt].offset = skb_frag_off(f);
		sgl[cnt].len = skb_frag_size(f);
		sgl[cnt].dma_addr = 0;
		cnt++;
	}

	req->sgl = sgl;
	req->sgcnt = cnt;
	req->count = skb->len;
	req->fp_done = qdma_net_tx_done_cb;
	req->uld_data = (unsigned long)skb;	/* recover skb in cb */
	req->dma_mapped = 0;			/* let libqdma map */

	*sgcnt = cnt;
	return 0;
}

int qdma_net_tx_enqueue_skb(struct qdma_net_priv *priv, struct qdma_net_queue *q, struct sk_buff *skb)
{
	struct qdma_request req;
	/* enough for head + max frags */
	struct qdma_sw_sg sgl[MAX_SKB_FRAGS + 1];
	int rv;

	if (unlikely(skb_shinfo(skb)->nr_frags + 1 > ARRAY_SIZE(sgl)))
		return -EINVAL;

	qdma_net_build_req_from_skb(priv, skb, &req, sgl, &(unsigned int){0});

	rv = qdma_queue_packet_write((unsigned long)priv->xdev, q->h2c_qhndl, &req);
	if (rv < 0)
		return rv;

	/* Account TX on submit (Stage 1) */
	priv->stats.tx_packets++;
	priv->stats.tx_bytes += skb->len;

	return 0;
}

/* RX: Build SKB from QDMA scatter-gather list */
int qdma_net_rx_packet_cb(unsigned long qhndl, unsigned long quld,
	unsigned int len, unsigned int sgcnt,
	struct qdma_sw_sg *sgl, void *udd)
{
	struct qdma_net_queue *q = (struct qdma_net_queue *)quld;
	struct qdma_net_priv *priv = q->priv;
	struct sk_buff *skb;
	struct qdma_sw_sg *sg = sgl;
	unsigned int copied = 0;
	int i;

	if (!len) {
		/* Empty packet, just return */
		return 0;
	}

	/* Allocate SKB with headroom for protocol headers */
	skb = napi_alloc_skb(&q->napi, 256);  // 256 bytes for headers
	if (!skb) {
		priv->stats.rx_dropped++;
		return -ENOMEM;
	}

	/* Copy or add pages as fragments */
	for (i = 0; i < sgcnt && sg && copied < len; i++, sg = sg->next) {
		unsigned int copy_len = min(sg->len, len - copied);
		unsigned char *page_addr;

		if (!sg->pg) {
			dev_kfree_skb_any(skb);
			priv->stats.rx_dropped++;
			return -EINVAL;
		}

		/* For small packets or first chunk, copy to linear area */
		if (skb->len == 0 && copy_len <= 256) {
			page_addr = page_address(sg->pg) + sg->offset;
			skb_put_data(skb, page_addr, copy_len);
		} else {
			/* Add as page fragment (zero-copy) */
			get_page(sg->pg);  // Increase page refcount
			skb_add_rx_frag(skb, skb_shinfo(skb)->nr_frags,
				sg->pg, sg->offset, copy_len, PAGE_SIZE);
		}

		copied += copy_len;
	}

	if (copied != len) {
		pr_warn("RX: copied %u != expected %u\n", copied, len);
		dev_kfree_skb_any(skb);
		priv->stats.rx_dropped++;
		return -EINVAL;
	}

	/* Set protocol type (this enables TCP/IP processing!) */
	skb->protocol = eth_type_trans(skb, priv->ndev);
	skb->ip_summed = CHECKSUM_NONE;  // Let stack verify checksum, can be offload to hardware if set to CHECKSUM_UNNECESSARY

	/* Update stats */
	priv->stats.rx_packets++;
	priv->stats.rx_bytes += len;

	/* Pass to network stack - THIS ENABLES TCP/IP! */
	napi_gro_receive(&q->napi, skb);

	return 0;
}