#include <rte_eal.h> /**> rte_eal_init */
#include <rte_debug.h> /**> for rte_panic */
#include <rte_ethdev.h> /**> rte_eth_rx_burst */
#include <rte_errno.h> /**> rte_errno global var */
#include <rte_memzone.h> /**> rte_memzone_dump */
#include <rte_memcpy.h>
#include <rte_malloc.h>
#include <rte_cycles.h>
#include <rte_log.h>
#include <rte_string_fns.h>
#include <rte_spinlock.h>
#include <rte_mbuf.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include "../../drivers/net/qdma/rte_pmd_qdma.h"
#include "test.h"
#include "pcierw.h"
#include "qdma_regs.h"

#define RTE_LIBRTE_QDMA_PMD 1

int num_ports;
struct port_info pinfo[QDMA_MAX_PORTS];

int port_init(int portid, int num_queues, int st_queues, int nb_descs, int buff_size)
{
	struct rte_mempool *mbuf_pool;
	struct rte_eth_conf	    port_conf;
	struct rte_eth_txconf   tx_conf;
	struct rte_eth_rxconf   rx_conf;
	int                     diag, x;
	uint32_t                queue_base, nb_buff;

	printf("Setting up port :%d.\n", portid);

	if (rte_pmd_qdma_get_device(portid) == NULL) {
		printf("Port id %d already removed. Relaunch application to use the port again\n", portid);
		return -1;
	}

	snprintf(pinfo[portid].mem_pool, RTE_MEMPOOL_NAMESIZE, MBUF_POOL_NAME_PORT, portid);

	/* Mbuf packet pool */
	nb_buff = ((nb_descs) * num_queues * 2);

	/* NUM_TX_PKTS should be added to every queue as that many descriptors
	 * can be pending with application after Rx processing but before
	 * consumed by application or sent to Tx
	 */
	nb_buff += ((NUM_TX_PKTS) * num_queues);

	/*
	* rte_mempool_create_empty() has sanity check to refuse large cache
	* size compared to the number of elements.
	* CACHE_FLUSHTHRESH_MULTIPLIER (1.5) is defined in a C file, so using a
	* constant number 2 instead.
	*/
	nb_buff = RTE_MAX(nb_buff, MP_CACHE_SZ * 2);

	mbuf_pool = rte_pktmbuf_pool_create(pinfo[portid].mem_pool, nb_buff, MP_CACHE_SZ, 0, buff_size + RTE_PKTMBUF_HEADROOM, rte_socket_id());

	if (mbuf_pool == NULL)
		rte_exit(EXIT_FAILURE, " Cannot create mbuf pkt-pool\n");

	/*
	 * Make sure the port is configured.  Zero everything and
	 * hope for sane defaults
	 */
	memset(&port_conf, 0x0, sizeof(struct rte_eth_conf));
	memset(&tx_conf, 0x0, sizeof(struct rte_eth_txconf));
	memset(&rx_conf, 0x0, sizeof(struct rte_eth_rxconf));
	diag = rte_pmd_qdma_get_bar_details(portid, &(pinfo[portid].config_bar_idx), &(pinfo[portid].user_bar_idx), &(pinfo[portid].bypass_bar_idx));

	if (diag < 0)
		rte_exit(EXIT_FAILURE, "rte_pmd_qdma_get_bar_details failed\n");

	printf("QDMA Config bar idx: %d\n", pinfo[portid].config_bar_idx);
	printf("QDMA AXI Master Lite bar idx: %d\n", pinfo[portid].user_bar_idx);
	printf("QDMA AXI Bridge Master bar idx: %d\n", pinfo[portid].bypass_bar_idx);

	/* configure the device to use # queues */
	diag = rte_eth_dev_configure(portid, num_queues, num_queues, &port_conf);
	if (diag < 0)
		rte_exit(EXIT_FAILURE, "Cannot configure port %d (err=%d)\n", portid, diag);

	diag = rte_pmd_qdma_get_queue_base(portid, &queue_base);
	if (diag < 0)
		rte_exit(EXIT_FAILURE, "rte_pmd_qdma_get_queue_base : Querying of QUEUE_BASE failed\n");
	pinfo[portid].queue_base = queue_base;
	pinfo[portid].num_queues = num_queues;
	pinfo[portid].st_queues = st_queues;
	pinfo[portid].buff_size = buff_size;
	pinfo[portid].nb_descs = nb_descs;

	for (x = 0; x < num_queues; x++) {
		if (x < st_queues) {
			diag = rte_pmd_qdma_set_queue_mode(portid, x, RTE_PMD_QDMA_STREAMING_MODE);
			if (diag < 0)
				rte_exit(EXIT_FAILURE, "rte_pmd_qdma_set_queue_mode : Passing of QUEUE_MODE failed\n");
		} else {
			diag = rte_pmd_qdma_set_queue_mode(portid, x, RTE_PMD_QDMA_MEMORY_MAPPED_MODE);
			if (diag < 0)
				rte_exit(EXIT_FAILURE, "rte_pmd_qdma_set_queue_mode : Passing of QUEUE_MODE failed\n");
		}

		diag = rte_eth_tx_queue_setup(portid, x, nb_descs, 0, &tx_conf);
		if (diag < 0)
			rte_exit(EXIT_FAILURE, "Cannot setup port %d TX Queue id:%d (err=%d)\n", portid, x, diag);
		rx_conf.rx_thresh.wthresh = DEFAULT_RX_WRITEBACK_THRESH;
		diag = rte_eth_rx_queue_setup(portid, x, nb_descs, 0, &rx_conf, mbuf_pool);
		if (diag < 0)
			rte_exit(EXIT_FAILURE, "Cannot setup port %d RX Queue 0 (err=%d)\n", portid, diag);
	}

	diag = rte_eth_dev_start(portid);
	if (diag < 0)
		rte_exit(EXIT_FAILURE, "Cannot start port %d (err=%d)\n", portid, diag);

	return 0;
}

int main(int argc, char* argv[]) {
    //measure the latency of QDMA read of different loads, start from 2Bytes to 512kB
    //need test data accuracy?
	if(argc != 9) {
		printf("./build/test -c 0xf -n 4 portid num_queues buffsize inputsize (st/mm)\n");
		return 0;
	}

    const struct rte_memzone *mz = 0;
    int ret = 0;
    int portid = atoi(argv[5]);
    int num_queues = atoi(argv[6]);   //self-defined parameter
    int stqueues = 0;    //self-defined parameter
    int numdescs = NUM_DESC_PER_RING; //self-defined parameter
    int buffsize = atoi(argv[7]); //self-defined parameter, 256Bytes - 63KB (not 64KB)
    uint64_t prev_tsc, cur_tsc, diff_tsc;  //measure latency
    struct rte_mbuf *mb[NUM_TX_PKTS] = { NULL };
    struct rte_mbuf *pkts[NUM_RX_PKTS] = { NULL };
    struct rte_mempool *mp;
    size_t tot_size = atoi(argv[8]), input_size;
    int i, j, nb_tx, nb_rx;
	unsigned int q_data_size = 0;
	uint64_t dst_addr = 0, src_addr = 0;
	//streaming
	unsigned int max_completion_size, last_pkt_size = 0, only_pkt = 0;
	unsigned int max_rx_retry, rcv_count = 0, num_pkts_recv = 0, total_rcv_pkts = 0;
	int user_bar_idx;
	int reg_val, loopback_en;
	int qbase = pinfo[portid].queue_base, queueid, diag;
	struct rte_mbuf *nxtmb;
	queueid = 0;

    ret = rte_eal_init(argc, argv);
    if (ret < 0)
		rte_exit(EXIT_FAILURE, "Error with EAL initialization\n");
    rte_log_set_global_level(RTE_LOG_DEBUG);

    printf("Ethernet Device Count: %d\n", (int)rte_eth_dev_count_avail());
    printf("Logical Core Count: %d\n", rte_lcore_count());

    num_ports = rte_eth_dev_count_avail();
    if (num_ports < 1)
	rte_exit(EXIT_FAILURE, "No Ethernet devices found. Try updating the FPGA image.\n");

    for (int portid = 0; portid < num_ports; portid++)
	rte_spinlock_init(&pinfo[portid].port_update_lock);

    /* Allocate aligned mezone */
	rte_pmd_qdma_compat_memzone_reserve_aligned();

	ret = port_init(portid, num_queues, stqueues, numdescs, buffsize);

	mp = rte_mempool_lookup(pinfo[portid].mem_pool);

	if (mp == NULL) {
		printf("Could not find mempool with name %s\n",
				pinfo[portid].mem_pool);
		// rte_spinlock_unlock(&pinfo[portid].port_update_lock);
		return -1;
	}

	int totpkts = 0, numpkts = 0;
	char* buf;
	buf = (char*)malloc(buffsize);
	memset(buf, 'B', buffsize-1);
	buf[buffsize-1] = '\n';

	// ret = rte_pmd_qdma_set_mm_endpoint_addr( portid, 0, RTE_PMD_QDMA_RX, 0);
	// if (ret < 0)
	// 	return -1;
	// ret = rte_pmd_qdma_set_mm_endpoint_addr( portid, 0, RTE_PMD_QDMA_TX, 0);
	// if (ret < 0)
	//	return -1;
	int count = 0;
	int tmp;
    int max_tx_retry;
	int fd;
	fd = open("output.txt", O_RDWR | O_CREAT | O_TRUNC | O_SYNC, 0666);
	int r_size = 0;
	int size, total_size = 0;
	int offset, ld_size = 0;
	input_size = tot_size;
	while(input_size <= tot_size) {
		if (input_size % num_queues) {
			size = input_size / num_queues;
			r_size = input_size % num_queues;
		} else
			size = input_size / num_queues;
		dst_addr = 0;
		q_data_size = 0;
		total_size = input_size;
        //count = 0;
        //write
		// for (queueid = 0, j = 0; queueid < num_queues; queueid++, j++) {
		// 	dst_addr += q_data_size;
		// 	dst_addr %= BRAM_SIZE;

		// 	if ((unsigned int)queueid >= pinfo[portid].st_queues) {
		// 		ret = rte_pmd_qdma_set_mm_endpoint_addr( portid, i, RTE_PMD_QDMA_TX, dst_addr);
		// 		if (ret < 0) {
		// 			close(fd);
		// 			return 0;
		// 		}
		// 	}

		// 	if (total_size == 0)
		// 		q_data_size = pinfo[portid].buff_size;
		// 	else if (total_size == (r_size + size)) {
		// 		q_data_size = total_size;
		// 		total_size = 0;
		// 	} else {
		// 		q_data_size = size;
		// 		total_size -= size;
		// 	}

		// 	if (q_data_size >= pinfo[portid].buff_size) {
		// 		if (q_data_size % pinfo[portid].buff_size) {
		// 			totpkts = (q_data_size /pinfo[portid].buff_size) + 1;
		// 			ld_size = q_data_size % pinfo[portid].buff_size;
		// 		} else
		// 			totpkts = (q_data_size / pinfo[portid].buff_size);
		// 	} else {
		// 		totpkts = 1;
		// 		ld_size = q_data_size % pinfo[portid].buff_size;
		// 	}
		// 	while(totpkts > 0) {
		// 		max_tx_retry = 1500;
		// 		if (totpkts > NUM_TX_PKTS) {
		// 			numpkts = NUM_TX_PKTS;
		// 		} else {
		// 			numpkts = totpkts;
		// 		}
		// 		printf("%s(): %d: queue id %d, mbuf_avail_count = %d, mbuf_in_use_count = %d\n",
		// 		__func__, __LINE__, 0,
		// 		rte_mempool_avail_count(mp),
		// 		rte_mempool_in_use_count(mp));
		// 		for (i = 0; i < numpkts; i++) {
		// 			mb[i] = rte_pktmbuf_alloc(mp);
		// 			if (mb[i] == NULL) {
		// 				printf(" #####Cannot allocate mbuf packet\n");
		// 				rte_spinlock_unlock(&pinfo[portid].port_update_lock);
		// 				return -1;
		// 			}

		// 			memcpy(rte_pktmbuf_mtod(mb[i], void *), buf, pinfo[portid].buff_size);
		// 			mb[i]->nb_segs = 1;
		// 			mb[i]->next = NULL;
		// 			rte_pktmbuf_data_len(mb[i]) = (uint16_t)pinfo[portid].buff_size;
		// 			rte_pktmbuf_pkt_len(mb[i])  = (uint16_t)pinfo[portid].buff_size;
		// 		}
		// 		nb_tx = rte_eth_tx_burst(portid, queueid, mb, numpkts);
		// 		tmp = nb_tx;
		// 		while ((nb_tx < numpkts) && max_tx_retry) {
		// 			rte_delay_us(1);
		// 			numpkts -= nb_tx;
		// 			nb_tx = rte_eth_tx_burst(portid, queueid, &mb[tmp], numpkts);
		// 			tmp += nb_tx;
		// 			max_tx_retry--;
		// 		}

		// 		if ((max_tx_retry == 0)) {
		// 			for (i = tmp; i < numpkts; i++)
		// 				rte_pktmbuf_free(mb[i]);
		// 			if (tmp == 0) {
		// 				printf("ERROR: rte_eth_tx_burst failed for port %d queue %d\n",portid, 0);
		// 				break;
		// 			}
		// 		}
		// 		count += tmp;
		// 		totpkts -= tmp;
		// 	}
		// }

        //read

		//streaming
		count = 0;
		double tot_time = 0;
		double time;
		src_addr = 0;
		q_data_size = 0;
		total_size = input_size;
		for (queueid = 0, j = 0; queueid < num_queues; queueid++, j++) {
			src_addr += q_data_size;
			src_addr %= BRAM_SIZE;

			if ((unsigned int)queueid >= pinfo[portid].st_queues) {
				ret = rte_pmd_qdma_set_mm_endpoint_addr( portid, queueid, RTE_PMD_QDMA_RX, src_addr);
				if (ret < 0) {
					close(fd);
					return 0;
				}
			}

			if (total_size == (r_size + size)) {
				q_data_size = total_size;
				total_size = 0;
			} else {
				q_data_size = size;
				total_size -= size;
			}
			if (portid)
				offset = (input_size/num_queues) * j;
			else
				offset = (input_size/num_queues) * queueid;

			lseek(fd, offset, SEEK_SET);

			user_bar_idx = pinfo[portid].user_bar_idx;
			PciWrite(user_bar_idx, C2H_ST_QID_REG, (queueid + qbase), portid);
			reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
			reg_val &= C2H_CONTROL_REG_MASK;
			loopback_en = reg_val & ST_LOOPBACK_EN;
			if (!loopback_en) {
				/* As per  hardware design a single completion will point to atmost
				* 7 descriptors. So If the size of the buffer in descriptor is 4KB ,
				* then a single completion which corresponds a packet can  give you
				* atmost 28KB data.
				*
				* As per this when testing sizes beyond 28KB, one needs to split it
				* up in chunks of 28KB, example : to test 56KB data size, set 28KB
				* as packet length in AXI Master Lite BAR(user bar) 0x04 register and no of packets as 2
				* in AXI Master Lite BAR(user bar) 0x20 register this would give you completions or
				* packets, which needs to be combined as one in application.
				*/
				max_completion_size = pinfo[portid].buff_size * 7;
			} else {
				/* For loopback case, each packet handles 4KB only,
				* so limiting to buffer size.
				*/
				max_completion_size = pinfo[portid].buff_size;
			}
			/* Calculate number of packets to receive and programming AXI Master Lite bar(user bar) */
			if (q_data_size == 0) /* zerobyte support uses one descriptor */
				totpkts = 1;
			else if (q_data_size % max_completion_size != 0) {
				totpkts = input_size / max_completion_size;
				last_pkt_size = q_data_size % max_completion_size;
			} else
				totpkts = q_data_size / max_completion_size;
			if ((totpkts == 0) && last_pkt_size) {
				totpkts = 1;
				only_pkt = 1;
			}

			if (!loopback_en) {
				PciWrite(user_bar_idx, C2H_PACKET_COUNT_REG, totpkts, portid);
				if (totpkts > 1)
					PciWrite(user_bar_idx, C2H_ST_LEN_REG, max_completion_size, portid);
				else if ((only_pkt == 1) && (last_pkt_size))
					PciWrite(user_bar_idx, C2H_ST_LEN_REG, last_pkt_size, portid);
				else if (q_data_size == 0)
					PciWrite(user_bar_idx, C2H_ST_LEN_REG, q_data_size, portid);
				else if (totpkts == 1)
					PciWrite(user_bar_idx, C2H_ST_LEN_REG, max_completion_size, portid);

				/* Start the C2H Engine */
				reg_val |= ST_C2H_START_VAL;
				PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, portid);
				int regval;
				regval = PciRead(user_bar_idx, C2H_PACKET_COUNT_REG, portid);
				printf("BAR-%d is the QDMA C2H number of packets:0x%x,\n", user_bar_idx, regval);
			
			}
			while (totpkts) {
				if (totpkts > NUM_RX_PKTS)
					numpkts = NUM_RX_PKTS;
				else
					numpkts = totpkts;
				max_rx_retry = RX_TX_MAX_RETRY;
				if ((only_pkt == 1) && (last_pkt_size))
					last_pkt_size = 0;
				/* Immediate data Enabled*/
				if ((reg_val & ST_C2H_IMMEDIATE_DATA_EN)) {
					/* payload received is zero for the immediate data case.
					* Therefore, no need to call the rx_burst function
					* again in this case and set the num_pkts to nb_rx
					* which is always Zero.
					*/
					diag = rte_pmd_qdma_set_immediate_data_state(portid, queueid, 1);
					if (diag < 0) {
						printf("rte_pmd_qdma_set_immediate_data_state : failed\n");
						rte_spinlock_unlock(&pinfo[portid].port_update_lock);
						return -1;
					}
					prev_tsc = rte_rdtsc_precise();
					nb_rx = rte_eth_rx_burst(portid, queueid, pkts, numpkts);
					cur_tsc = rte_rdtsc_precise();
					diff_tsc = cur_tsc - prev_tsc;
					time = diff_tsc*1.0 / rte_get_tsc_hz();
					tot_time += time;
					printf("nb_rx at line 411: %d\n", nb_rx);
					totpkts = num_pkts_recv = nb_rx;

					/* Reset the queue's DUMP_IMMEDIATE_DATA mode */
					diag = rte_pmd_qdma_set_immediate_data_state(portid, queueid, 0);
					if (diag < 0) {
						printf("rte_pmd_qdma_set_immediate_data_state : failed\n");
						rte_spinlock_unlock(&pinfo[portid].port_update_lock);
						return -1;
					}
				} else {
					/* try to receive RX_BURST_SZ packets */
					prev_tsc = rte_rdtsc_precise();
					nb_rx = rte_eth_rx_burst(portid, queueid, pkts, numpkts);
					cur_tsc = rte_rdtsc_precise();
					diff_tsc = cur_tsc - prev_tsc;
					time = diff_tsc*1.0 / rte_get_tsc_hz();
					tot_time += time;
					printf("nb_rx at line 429: %d\n", nb_rx);
					/* For zero byte packets, do not continue looping */
					if (q_data_size == 0)
						break;

					tmp = nb_rx;
					while ((nb_rx < numpkts) && max_rx_retry) {
						rte_delay_us(1);
						numpkts -= nb_rx;
						prev_tsc = rte_rdtsc_precise();
						nb_rx = rte_eth_rx_burst(portid, queueid, &pkts[tmp], numpkts);
						cur_tsc = rte_rdtsc_precise();
						diff_tsc = cur_tsc - prev_tsc;
						time = diff_tsc*1.0 / rte_get_tsc_hz();
						tot_time += time;
						printf("nb_rx at line 444: %d\n", nb_rx);
						tmp += nb_rx;
						max_rx_retry--;
					}
					num_pkts_recv = tmp;
					if ((max_rx_retry == 0) && (num_pkts_recv == 0)) {
						printf("ERROR: rte_eth_rx_burst failed for "
							"port %d queue id %d, Expected pkts = %d "
							"Received pkts = %u\n",
							portid, queueid,
							numpkts, num_pkts_recv);
						break;
					}
				}
				for (i = 0; i < num_pkts_recv; i++) {
					struct rte_mbuf *mb = pkts[i];
					while (mb != NULL) {
						ret += write(fd, rte_pktmbuf_mtod(mb, void*),rte_pktmbuf_data_len(mb));
						printf("rte_pktmbuf_data_len: %d\n", rte_pktmbuf_data_len(mb));
						printf("ret: %d\n", ret);
						nxtmb = mb->next;
						mb = nxtmb;
					}
					mb = pkts[i];
					rte_pktmbuf_free(mb);
					printf("recv count: %u, with data-len: %d\n", i + rcv_count, ret);
					count += ret;
					ret = 0;
				}
				rcv_count += i;
				totpkts = totpkts - num_pkts_recv;
				total_rcv_pkts += num_pkts_recv;

				if ((totpkts == 0) && last_pkt_size) {
					totpkts = 1;
					if (!loopback_en) {
						/* Stop the C2H Engine */
						reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
						reg_val &= C2H_CONTROL_REG_MASK;
						reg_val &= ~(ST_C2H_START_VAL);
						PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, portid);

						/* Update number of packets as 1 and
						* packet size as last packet length
						*/
						PciWrite(user_bar_idx, C2H_PACKET_COUNT_REG, totpkts, portid);

						PciWrite(user_bar_idx, C2H_ST_LEN_REG,
						last_pkt_size, portid);

						/* Start the C2H Engine */
						reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
						reg_val &= C2H_CONTROL_REG_MASK;
						reg_val |= ST_C2H_START_VAL;
						PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val, portid);
					}
					last_pkt_size = 0;
					continue;
				}
			}
			/* Stop the C2H Engine */
			if (!loopback_en) {
				reg_val = PciRead(user_bar_idx, C2H_CONTROL_REG, portid);
				reg_val &= C2H_CONTROL_REG_MASK;
				reg_val &= ~(ST_C2H_START_VAL);
				PciWrite(user_bar_idx, C2H_CONTROL_REG, reg_val,portid);
			}
			printf("DMA received number of packets: %u, on queue-id:%d\n",total_rcv_pkts, queueid);
			rte_spinlock_unlock(&pinfo[portid].port_update_lock);

			double pkts_per_second = ((double)total_rcv_pkts / tot_time);

			/* Calculate average throughput (Gbps) in bits per second */
			double throughput_gbps = (count * 8.0/ (1.0*1024*1024*1024));

			printf("Throughput GBps %lf   ", throughput_gbps);
			printf("Number of bytes: %d   ", count);
			printf("total latency: %lf\n", tot_time);
			input_size *= 2;
		}
			//streaming part end	

		//// memory mapped
        // count = 0;
        // totpkts = q_data_size / buffsize;
		// if(q_data_size%totpkts) {
		// 	totpkts += 1;
		// }
		// printf("totpkts: %d\n", totpkts);
		// double tot_time = 0;
		// double time;
		// while(totpkts > 0) {
        //     if (totpkts > NUM_RX_PKTS) {
        //         numpkts = NUM_RX_PKTS;
        //     } else {
        //         numpkts = totpkts;
        //     }

        //     prev_tsc = rte_rdtsc_precise();
        //     nb_rx = rte_eth_rx_burst(portid, 0, pkts, numpkts);
		// 	cur_tsc = rte_rdtsc_precise();
        //     diff_tsc = cur_tsc - prev_tsc;

		// 	time = diff_tsc*1.0 / rte_get_tsc_hz();
		// 	tot_time += time;
		// 	printf("nb_rx: %d\n", nb_rx);

        //     for (i = 0; i < nb_rx; i++) {
		// 		struct rte_mbuf *mb = pkts[i];
		// 		write(fd, rte_pktmbuf_mtod(mb, void*), pinfo[portid].buff_size);
		// 		rte_pktmbuf_free(mb);
		// 		//printf("recv count: %d, with data-len: %d\n", i, ret);
		// 	}
		// 	//printf("aa\n");
		// 	totpkts -= nb_rx;
        //     count += nb_rx;
        // }
		// double pkts_per_second = ((double)count / tot_time);

        //         /* Calculate average throughput (Gbps) in bits per second */
        // double throughput_gbps = ((pkts_per_second * (pinfo[portid].buff_size+RTE_PKTMBUF_HEADROOM)) / (1.0*1024*1024*1024));

        // printf("Throughput GBps %lf   ", throughput_gbps);
        // printf("Number of bytes: %d   ", count*pinfo[portid].buff_size);
        // printf("total latency: %lf\n", tot_time);
		// input_size *= 2;
	}
	fsync(fd);
	free(buf);
	close(fd);
}
