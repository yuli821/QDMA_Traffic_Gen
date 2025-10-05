#include <linux/skbuff.h>
#include <linux/mm.h>
#include <linux/highmem.h>

#include "qdma_net.h"
#include "libqdma/qdma_ul_ext.h"

/* Translate skb into libqdma qdma_request and submit. Stage 1: simple SG. */

static void qdma_net_tx_done_cb(struct qdma_request *req, unsigned int done, int error)
{
	struct sk_buff *skb = (struct sk_buff *)req->opaque;
	/* Free SKB on completion */
	dev_kfree_skb_any(skb);
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
		sgl[cnt].offset = f->page_offset;
		sgl[cnt].len = skb_frag_size(f);
		sgl[cnt].dma_addr = 0;
		cnt++;
	}

	req->sgl = sgl;
	req->sgcnt = cnt;
	req->count = skb->len;
	req->fp_done = qdma_net_tx_done_cb;
	req->opaque = (unsigned long)skb;	/* recover skb in cb */
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