// /*
//  * This file is part of the QDMA userspace application
//  * to enable the user to execute the QDMA functionality
//  *
//  * Copyright (c) 2018-2022, Xilinx, Inc. All rights reserved.
//  * Copyright (c) 2022-2024, Advanced Micro Devices, Inc. All rights reserved.
//  *
//  * This source code is licensed under BSD-style license (found in the
//  * LICENSE file in the root directory of this source tree)
//  */
// #define _GNU_SOURCE
// #include <sys/types.h>
// #include <sys/stat.h>
// #include <sys/shm.h>
// #include <fcntl.h>
// #include <stdbool.h>
// #include <linux/types.h>
// #include <getopt.h>
// #include <stdint.h>
// #include <stdio.h>
// #include <stdlib.h>
// #include <string.h>
// #include <unistd.h>
// #include <stddef.h>
// #include <ctype.h>
// #include <errno.h>
// #include <error.h>
// #include <sys/stat.h>
// #include <sys/mman.h>
// #include <sys/time.h>
// #include <sys/ioctl.h>
// #include <sys/sysinfo.h>
// // #include <linux/ktime.h>
// //#include <linux/time64.h>
// //added
// #include <stdatomic.h>
// #include <sched.h>
// #include <pthread.h>
// #include <time.h>
// #include <signal.h>

// #include "version.h"
// #include "dmautils.h"
// #include "qdma_nl.h"
// #include "dmaxfer.h"

// #define QDMA_Q_NAME_LEN     100
// #define QDMA_ST_MAX_PKT_SIZE 0x7000
// #define QDMA_RW_MAX_SIZE	0x7ffff000
// #define QDMA_GLBL_MAX_ENTRIES  (16)

// static struct queue_info *q_info;
// static int q_count;

// enum qdma_q_dir {
// 	QDMA_Q_DIR_H2C,
// 	QDMA_Q_DIR_C2H,
// 	QDMA_Q_DIR_BIDI
// };

// enum qdma_q_mode {
// 	QDMA_Q_MODE_MM,
// 	QDMA_Q_MODE_ST
// };

// struct queue_info {
// 	char q_name[32];
// 	int qid;
// 	int pf;
// 	enum qdmautils_io_dir dir;
// 	int core_id;
// 	atomic_uint_fast64_t packets_received;
// 	//pthread_mutex_t packet_mutex;
// 	pthread_t thread;
// };
// //added
// static unsigned int cycles_per_pkt;       // rate of packets
// static unsigned int traffic_pattern = 0;  // Default traffic pattern
// //static unsigned int user_bar = 0;        // User BAR number
// //static unsigned int qbase = 0;           // Queue base
// static unsigned int num_cores = 0;       // Number of cores
// static volatile sig_atomic_t shutdown_threads = 0;
// //original
// enum qdma_q_mode mode;
// enum qdma_q_dir dir;
// static char cfg_name[64];
// static unsigned int pkt_sz;
// static unsigned int pci_bus;
// static unsigned int pci_dev;
// static int fun_id = -1;
// static int is_vf;
// static unsigned int q_start;
// static unsigned int num_q; //equal to num_cores
// static unsigned int idx_rngsz;
// static unsigned int idx_tmr;
// static unsigned int idx_cnt;
// static unsigned int pfetch_en;
// static unsigned int cmptsz;
// // static char input_file[128];
// // static char output_file[128];
// static int io_type;
// static char trigmode_str[10];
// static unsigned char trig_mode;

// static struct option const long_opts[] = {
// 	{"config", required_argument, NULL, 'c'},
// 	{0, 0, 0, 0}
// };

// static void prep_reg_dump(void);

// static void usage(const char *name)
// {
// 	fprintf(stdout, "%s\n\n", name);
// 	fprintf(stdout, "usage: %s [OPTIONS]\n\n", name);

// 	fprintf(stdout, "  -%c (--%s) config file that has configration for IO\n",
// 			long_opts[0].val, long_opts[0].name);
// 	fprintf(stdout, "  -v (--version), to print version name\n");
// }

// static unsigned int num_trailing_blanks(char *word)
// {
// 	unsigned int i = 0;
// 	unsigned int slen = strlen(word);

// 	if (!slen) return 0;
// 	while (isspace(word[slen - i - 1])) {
// 		i++;
// 	}

// 	return i;
// }

// static char * strip_blanks(char *word, long unsigned int *banlks)
// {
// 	char *p = word;
// 	unsigned int i = 0;

// 	while (isblank(p[0])) {
// 		p++;
// 		i++;
// 	}
// 	if (banlks)
// 		*banlks = i;

// 	return p;
// }

// static unsigned int copy_value(char *src, char *dst, unsigned int max_len)
// {
// 	char *p = src;
// 	unsigned int i = 0;

// 	while (max_len && !isspace(p[0])) {
// 		dst[i] = p[0];
// 		p++;
// 		i++;
// 		max_len--;
// 	}

// 	return i;
// }

// static char * strip_comments(char *word)
// {
// 	size_t numblanks;
// 	char *p = strip_blanks(word, &numblanks);

// 	if (p[0] == '#')
// 		return NULL;
// 	else
// 		p = strtok(word, "#");

// 	return p;
// }

// static int arg_read_int(char *s, uint32_t *v)
// {
// 	char *p = NULL;


// 	*v = strtoul(s, &p, 0);
// 	if (*p && (*p != '\n') && !isblank(*p)) {
// 		printf("Error:something not right%s %s %s",
// 				s, p, isblank(*p)? "true": "false");
// 		return -EINVAL;
// 	}
// 	return 0;
// }

// static int arg_read_int_array(char *s, unsigned int *v, unsigned int max_arr_size)
// {
// 	unsigned int slen = strlen(s);
// 	unsigned int trail_blanks = num_trailing_blanks(s);
// 	char *str = (char *)malloc(slen - trail_blanks + 1);
// 	char *elem;
// 	int cnt = 0;
// 	int ret;

// 	memset(str, '\0', slen + 1);
// 	strncpy(str, s + 1, slen - trail_blanks - 2);
// 	str[slen] = '\0';

// 	elem = strtok(str, " ,");/* space or comma separated */
// 	while (elem != NULL) {
// 		ret = arg_read_int(elem, &v[cnt]);
// 		if (ret < 0) {
// 			printf("ERROR: Invalid array element %sin %s\n", elem, s);
// 			exit(0);
// 		}
// 		cnt++;
// 		elem = strtok(NULL, " ,");
// 		if (cnt > (int)max_arr_size) { /* to avoid out of bounds */
// 			printf("ERROR: More than expected number of elements in %s - expected = %u\n",
// 					str, max_arr_size);
// 			exit(0);
// 		}
// 	}
// 	free(str);

// 	return cnt;
// }

// static int get_array_len(char *s)
// {
// 	int i, len = 0;

// 	if (strlen(s) < 2)
// 		return -EINVAL;
// 	if ((s[0] != '(') && (s[strlen(s) - 1] != ')'))
// 		return -EINVAL;
// 	if ((s[0] == '(') && (s[1] == ')'))
// 		return 0;
// 	for (i = 0; i < (int)strlen(s); i++) {
// 		if ((s[i] == ' ') || (s[i] == ',')) /* space or comma separated */
// 			len++;
// 		if (s[i] == ')')
// 			break;
// 	}

// 	return (len + 1);

// }

// static ssize_t read_to_buffer(char *fname, int fd, char *buffer,
// 		uint64_t size, uint64_t base)
// {
// 	ssize_t rc;
// 	uint64_t count = 0;
// 	char *buf = buffer;
// 	off_t offset = base;

// 	do { /* Support zero byte transfer */
// 		uint64_t bytes = size - count;

// 		if (bytes > QDMA_RW_MAX_SIZE)
// 			bytes = QDMA_RW_MAX_SIZE;

// 		if (offset) {
// 			rc = lseek(fd, offset, SEEK_SET);
// 			if (rc < 0) {
// 				printf("Error: %s, seek off 0x%lx failed %zd\n",
// 						fname, offset, rc);
// 				return -EIO;
// 			}
// 			if (rc != offset) {
// 				printf("Error: %s, seek off 0x%lx != 0x%lx\n",
// 						fname, rc, offset);
// 				return -EIO;
// 			}
// 		}

// 		/* read data from file into memory buffer */
// 		rc = read(fd, buf, bytes);
// 		if (rc < 0) {
// 			printf("Failed to Read %s, read off 0x%lx + 0x%lx failed %zd\n",
// 					fname, offset, bytes, rc);
// 			return -EIO;
// 		}
// 		if (rc != bytes) {
// 			printf("Failed to read %lx bytes from file %s, curr read:%lx\n",
// 					bytes, fname, rc);
// 			return -EIO;
// 		}

// 		count += bytes;
// 		buf += bytes;
// 		offset += bytes;

// 	} while (count < size);

// 	if (count != size) {
// 		printf("Failed to read %lx bytes from %s 0x%lx != 0x%lx.\n",
// 				size, fname, count, size);
// 		return -EIO;
// 	}

// 	return count;
// }

// static ssize_t write_from_buffer(char *fname, int fd, char *buffer,
// 		uint64_t size, uint64_t base)
// {
// 	ssize_t rc;
// 	uint64_t count = 0;
// 	char *buf = buffer;
// 	off_t offset = base;

// 	do { /* Support zero byte transfer */
// 		uint64_t bytes = size - count;

// 		if (bytes > QDMA_RW_MAX_SIZE)
// 			bytes = QDMA_RW_MAX_SIZE;

// 		if (offset) {
// 			rc = lseek(fd, offset, SEEK_SET);
// 			if (rc < 0) {
// 				printf("Error: %s, seek off 0x%lx failed %zd\n",
// 						fname, offset, rc);
// 				return -EIO;
// 			}
// 			if (rc != offset) {
// 				printf("Error: %s, seek off 0x%lx != 0x%lx\n",
// 						fname, rc, offset);
// 				return -EIO;
// 			}
// 		}

// 		/* write data to file from memory buffer */
// 		rc = write(fd, buf, bytes);
// 		if (rc < 0) {
// 			printf("Failed to Read %s, read off 0x%lx + 0x%lx failed %zd\n",
// 					fname, offset, bytes, rc);
// 			return -EIO;
// 		}
// 		if (rc != bytes) {
// 			printf("Failed to read %lx bytes from file %s, curr read:%lx\n",
// 					bytes, fname, rc);
// 			return -EIO;
// 		}

// 		count += bytes;
// 		buf += bytes;
// 		offset += bytes;

// 	} while (count < size);

// 	if (count != size) {
// 		printf("Failed to read %lx bytes from %s 0x%lx != 0x%lx\n",
// 				size, fname, count, size);
// 		return -EIO;
// 	}

// 	return count;
// }

// static int parse_config_file(const char *cfg_fname)
// {
// 	char *linebuf = NULL;
// 	char *realbuf;
// 	FILE *fp;
// 	size_t linelen = 0;
// 	size_t numread;
// 	size_t numblanks;
// 	unsigned int linenum = 0;
// 	char *config, *value;
// 	unsigned int dir_factor = 1;
// 	char rng_sz[100] = {'\0'};
// 	char rng_sz_path[200] = {'\0'};
// 	int rng_sz_fd, ret = 0;
// 	//int input_file_provided = 0;
// 	//int output_file_provided = 0;
// 	struct stat st;

// 	fp = fopen(cfg_fname, "r");
// 	if (fp == NULL) {
// 		printf("Failed to open Config File [%s]\n", cfg_fname);
// 		return -EINVAL;
// 	}

// 	while ((numread = getline(&linebuf, &linelen, fp)) != -1) {
// 		numread--;
// 		linenum++;
// 		linebuf = strip_comments(linebuf);
// 		if (linebuf == NULL)
// 			continue;
// 		realbuf = strip_blanks(linebuf, &numblanks);
// 		linelen -= numblanks;
// 		if (0 == linelen)
// 			continue;
// 		config = strtok(realbuf, "=");
// 		value = strtok(NULL, "=");
// 		if (!strncmp(config, "mode", 4)) {
// 			if (!strncmp(value, "mm", 2))
// 				mode = QDMA_Q_MODE_MM;
// 			else if(!strncmp(value, "st", 2))
// 				mode = QDMA_Q_MODE_ST;
// 			else {
// 				printf("Error: Unknown mode\n");
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "dir", 3)) {
// 			if (!strncmp(value, "h2c", 3))
// 				dir = QDMA_Q_DIR_H2C;
// 			else if(!strncmp(value, "c2h", 3))
// 				dir = QDMA_Q_DIR_C2H;
// 			else if(!strncmp(value, "bi", 2))
// 				dir = QDMA_Q_DIR_BIDI;
// 			else if(!strncmp(value, "cmpt", 4)) {
// 				printf("Error: cmpt type queue validation is not supported\n");
// 				goto prase_cleanup;
// 			} else {
// 				printf("Error: Unknown direction\n");
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "name", 3)) {
// 			copy_value(value, cfg_name, 64);
// 		} else if (!strncmp(config, "function", 8)) {
// 			if (arg_read_int(value, &fun_id)) {
// 				printf("Error: Invalid function:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "is_vf", 5)) {
// 			if (arg_read_int(value, &is_vf)) {
// 				printf("Error: Invalid is_vf param:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 			if (is_vf > 1) {
// 				printf("Error: is_vf value is %d, expected 0 or 1\n",
// 						is_vf);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "q_range", 7)) {
// 			char *q_range_start = strtok(value, ":");
// 			char *q_range_end = strtok(NULL, ":");
// 			unsigned int start;
// 			unsigned int end;
// 			if (arg_read_int(q_range_start, &start)) {
// 				printf("Error: Invalid q range start:%s\n", q_range_start);
// 				goto prase_cleanup;
// 			}
// 			if (arg_read_int(q_range_end, &end)) {
// 				printf("Error: Invalid q range end:%s\n", q_range_end);
// 				goto prase_cleanup;
// 			}

// 			q_start = start;
// 			num_q = end - start + 1;
// 		} else if (!strncmp(config, "rngidx", 6)) {
// 			if (arg_read_int(value, &idx_rngsz)) {
// 				printf("Error: Invalid idx_rngsz:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "tmr_idx", 7)) {
// 			if (arg_read_int(value, &idx_tmr)) {
// 				printf("Error: Invalid idx_tmr:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		}
// 		if (!strncmp(config, "cntr_idx", 8)) {
// 			if (arg_read_int(value, &idx_cnt)) {
// 				printf("Error: Invalid idx_cnt:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "pfetch_en", 9)) {
// 			if (arg_read_int(value, &pfetch_en)) {
// 				printf("Error: Invalid pfetch_en:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "cmptsz", 5)) {
// 			if (arg_read_int(value, &cmptsz)) {
// 				printf("Error: Invalid cmptsz:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		}  else if (!strncmp(config, "trig_mode", 9)) {
// 			copy_value(value, trigmode_str, 10);
// 		}  else if (!strncmp(config, "pkt_sz", 6)) {
// 			if (arg_read_int(value, &pkt_sz)) {
// 				printf("Error: Invalid pkt_sz:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "pci_bus", 7)) {
// 			char *p;

// 			pci_bus = strtoul(value, &p, 16);
// 			if (*p && (*p != '\n')) {
// 				printf("Error: bad parameter \"%s\", integer expected", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "pci_dev", 7)) {
// 			char *p;

// 			pci_dev = strtoul(value, &p, 16);
// 			if (*p && (*p != '\n')) {
// 				printf("Error: bad parameter \"%s\", integer expected", value);
// 				goto prase_cleanup;
// 			}
// 		} 
// 		// else if (!strncmp(config, "inputfile", 7)) {
// 		// 	copy_value(value, input_file, 128);
// 		// 	input_file_provided = 1;
// 		// } 
// 		// else if (!strncmp(config, "outputfile", 7)) {
// 		// 	copy_value(value, output_file, 128);
// 		// 	output_file_provided = 1;
// 		// } 
// 		else if (!strncmp(config, "io_type", 6)) {
// 			if (!strncmp(value, "io_sync", 6))
// 				io_type = 0;
// 			else if (!strncmp(value, "io_async", 6))
// 				io_type = 1;
// 			else {
// 				printf("Error: Unknown io_type\n");
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "num_cores", 9)) {  //added
// 			if (arg_read_int(value, &num_cores)) {
// 				printf("Error: Invalid num_cores:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 			if (num_cores == 0) {
// 				num_cores = get_nprocs(); //Default to all cores
// 				printf("Warning: Using all available cores: %d\n", num_cores);
// 			}
// 		} else if (!strncmp(config, "cycles_per_pkt", 14)) {  //added
// 			if (arg_read_int(value, &cycles_per_pkt)) {
// 				printf("Error: Invalid cycles_per_pkt:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		} else if (!strncmp(config, "traffic_pattern", 14)) {  //added
// 			if (arg_read_int(value, &traffic_pattern)) {
// 				printf("Error: Invalid traffic_pattern:%s\n", value);
// 				goto prase_cleanup;
// 			}
// 		}
// 	}
// 	fclose(fp);

// 	if (!pci_bus && !pci_dev) {
// 		printf("Error: PCI bus information not provided\n");
// 		return -EINVAL;
// 	}

// 	if (fun_id < 0) {
// 		printf("Error: Valid function required\n");
// 		return -EINVAL;
// 	}

// 	if (fun_id <= 3 && is_vf) {
// 		printf("Error: invalid is_vf and fun_id values."
// 				"Fun_id for vf must be higer than 3\n");
// 		return -EINVAL;
// 	}

// 	if (mode == QDMA_Q_MODE_ST && pkt_sz > QDMA_ST_MAX_PKT_SIZE) {
// 		printf("Error: Pkt size [%u] larger than supported size [%d]\n",
// 				pkt_sz, QDMA_ST_MAX_PKT_SIZE);
// 		return -EINVAL;
// 	}

// 	// if ((dir == QDMA_Q_DIR_H2C) || (dir == QDMA_Q_DIR_BIDI)) {
// 		// if (!input_file_provided) {
// 		// 	printf("Error: Input File required for Host to Card transfers\n");
// 		// 	return -EINVAL;
// 		// }

// 		// ret = stat(input_file, &st);
// 		// if (ret < 0) {
// 		// 	printf("Error: Failed to read input file [%s] length\n",
// 		// 			input_file);
// 		// 	return ret;
// 		// }

// 		// if (pkt_sz > st.st_size) {
// 		// 	printf("Error: File [%s] length is lesser than pkt_sz %u\n",
// 		// 			input_file, pkt_sz);
// 		// 	return -EINVAL;
// 		// }
// 	// }

// 	// if (((dir == QDMA_Q_DIR_C2H) || (dir == QDMA_Q_DIR_BIDI)) &&
// 	// 		!output_file_provided) {
// 	// 	printf("Error: Data output file was not provided\n");
// 	// 	return -EINVAL;
// 	// }

// 	if (!strcmp(trigmode_str, "every"))
// 		trig_mode = 1;
// 	else if (!strcmp(trigmode_str, "usr_cnt"))
// 		trig_mode = 2;
// 	else if (!strcmp(trigmode_str, "usr"))
// 		trig_mode = 3;
// 	else if (!strcmp(trigmode_str, "usr_tmr"))
// 		trig_mode=4;
// 	else if (!strcmp(trigmode_str, "cntr_tmr"))
// 		trig_mode=5;
// 	else if (!strcmp(trigmode_str, "dis"))
// 		trig_mode = 0;
// 	else {
// 		printf("Error: unknown q trigmode %s.\n", trigmode_str);
// 		return -EINVAL;
// 	}

// 	return 0;

// prase_cleanup:
// 	fclose(fp);
// 	return -EINVAL;
// }

// static inline void qdma_q_prep_name(struct queue_info *q_info, int qid, int pf)
// {
// 	char *temp_name = calloc(QDMA_Q_NAME_LEN, 1);
// 	snprintf(temp_name, QDMA_Q_NAME_LEN, "/dev/qdma%s%05x-%s-%d",
// 			(is_vf) ? "vf" : "",
// 			(pci_bus << 12) | (pci_dev << 4) | pf,
// 			(mode == QDMA_Q_MODE_MM) ? "MM" : "ST",
// 			qid);
// 	strncpy(q_info->q_name, temp_name, sizeof(q_info->q_name) - 1);
// 	q_info->q_name[sizeof(q_info->q_name) - 1] = '\0';
// 	free(temp_name);
// 	// q_info->q_name = temp_name;
// 	// snprintf(q_info->q_name, QDMA_Q_NAME_LEN, "/dev/qdma%s%05x-%s-%d",
// 	// 		(is_vf) ? "vf" : "",
// 	// 		(pci_bus << 12) | (pci_dev << 4) | pf,
// 	// 		(mode == QDMA_Q_MODE_MM) ? "MM" : "ST",
// 	// 		qid);
// }

// static int qdma_validate_qrange(void)
// {
// 	struct xcmd_info xcmd;
// 	int ret;

// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	xcmd.op = XNL_CMD_DEV_INFO;
// 	xcmd.vf = is_vf;
// 	xcmd.if_bdf = (pci_bus << 12) | (pci_dev << 4) | fun_id;

// 	/* Get dev info from qdma driver */
// 	ret = qdma_dev_info(&xcmd);
// 	if (ret < 0) {
// 		printf("Failed to read qmax for PF: %d\n", fun_id);
// 		return ret;
// 	}

// 	if (!xcmd.resp.dev_info.qmax) {
// 		printf("Error: invalid qmax assigned to function :%d qmax :%u\n",
// 				fun_id, xcmd.resp.dev_info.qmax);
// 		return -EINVAL;
// 	}

// 	if (xcmd.resp.dev_info.qmax <  num_q) {
// 		printf("Error: Q Range is beyond QMAX %u "
// 				"Funtion: %x Q start :%u Q Range End :%u\n",
// 				xcmd.resp.dev_info.qmax, fun_id, q_start, q_start + num_q);
// 		return -EINVAL;
// 	}

// 	return 0;
// }

// static int qdma_prepare_q_stop(struct xcmd_info *xcmd,
// 		enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_q_parm *qparm;

// 	if (!xcmd)
// 		return -EINVAL;

// 	qparm = &xcmd->req.qparm;

// 	xcmd->op = XNL_CMD_Q_STOP;
// 	xcmd->vf = is_vf;
// 	xcmd->if_bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
// 	qparm->idx = qid;
// 	qparm->num_q = 1;

// 	if (mode == QDMA_Q_MODE_MM)
// 		qparm->flags |= XNL_F_QMODE_MM;
// 	else if (mode == QDMA_Q_MODE_ST)
// 		qparm->flags |= XNL_F_QMODE_ST;
// 	else
// 		return -EINVAL;

// 	if (dir == DMAXFER_IO_WRITE)
// 		qparm->flags |= XNL_F_QDIR_H2C;
// 	else if (dir == DMAXFER_IO_READ)
// 		qparm->flags |= XNL_F_QDIR_C2H;
// 	else
// 		return -EINVAL;


// 	return 0;
// }

// static int qdma_prepare_q_start(struct xcmd_info *xcmd,
// 		enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_q_parm *qparm;


// 	if (!xcmd) {
// 		printf("Error: Invalid Input Param\n");
// 		return -EINVAL;
// 	}
// 	qparm = &xcmd->req.qparm;

// 	xcmd->op = XNL_CMD_Q_START;
// 	xcmd->vf = is_vf;
// 	xcmd->if_bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
// 	qparm->idx = qid;
// 	qparm->num_q = 1;

// 	if (mode == QDMA_Q_MODE_MM)
// 		qparm->flags |= XNL_F_QMODE_MM;
// 	else if (mode == QDMA_Q_MODE_ST)
// 		qparm->flags |= XNL_F_QMODE_ST;
// 	else {
// 		printf("Error: Invalid mode\n");
// 		return -EINVAL;
// 	}

// 	if (dir == DMAXFER_IO_WRITE)
// 		qparm->flags |= XNL_F_QDIR_H2C;
// 	else if (dir == DMAXFER_IO_READ)
// 		qparm->flags |= XNL_F_QDIR_C2H;
// 	else {
// 		printf("Error: Invalid Direction\n");
// 		return -EINVAL;
// 	}

// 	qparm->qrngsz_idx = idx_rngsz;

// 	if ((dir == QDMA_Q_DIR_C2H) && (mode == QDMA_Q_MODE_ST)) {
// 		if (cmptsz)
// 			qparm->cmpt_entry_size = cmptsz;
// 		else
// 			qparm->cmpt_entry_size = XNL_ST_C2H_CMPT_DESC_SIZE_8B;
// 		qparm->cmpt_tmr_idx = idx_tmr;
// 		qparm->cmpt_cntr_idx = idx_cnt;
// 		qparm->cmpt_trig_mode = trig_mode;
// 		if (pfetch_en)
// 			qparm->flags |= XNL_F_PFETCH_EN;
// 	}

// 	// qparm->flags |= (XNL_F_CMPL_STATUS_EN | XNL_F_CMPL_STATUS_ACC_EN |
// 	// 		XNL_F_CMPL_STATUS_PEND_CHK | XNL_F_CMPL_STATUS_DESC_EN |
// 	// 		XNL_F_FETCH_CREDIT);

// 	return 0;
// }

// static int qdma_prepare_q_del(struct xcmd_info *xcmd,
// 		enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_q_parm *qparm;

// 	if (!xcmd) {
// 		printf("Error: Invalid Input Param\n");
// 		return -EINVAL;
// 	}

// 	qparm = &xcmd->req.qparm;

// 	xcmd->op = XNL_CMD_Q_DEL;
// 	xcmd->vf = is_vf;
// 	xcmd->if_bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
// 	qparm->idx = qid;
// 	qparm->num_q = 1;

// 	if (mode == QDMA_Q_MODE_MM)
// 		qparm->flags |= XNL_F_QMODE_MM;
// 	else if (mode == QDMA_Q_MODE_ST)
// 		qparm->flags |= XNL_F_QMODE_ST;
// 	else {
// 		printf("Error: Invalid mode\n");
// 		return -EINVAL;
// 	}

// 	if (dir == DMAXFER_IO_WRITE)
// 		qparm->flags |= XNL_F_QDIR_H2C;
// 	else if (dir == DMAXFER_IO_READ)
// 		qparm->flags |= XNL_F_QDIR_C2H;
// 	else {
// 		printf("Error: Invalid Direction\n");
// 		return -EINVAL;
// 	}

// 	return 0;
// }

// static int qdma_prepare_q_add(struct xcmd_info *xcmd,
// 		enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_q_parm *qparm;

// 	if (!xcmd) {
// 		printf("Error: Invalid Input Param\n");
// 		return -EINVAL;
// 	}

// 	qparm = &xcmd->req.qparm;

// 	xcmd->op = XNL_CMD_Q_ADD;
// 	xcmd->vf = is_vf;
// 	xcmd->if_bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
// 	qparm->idx = qid;
// 	qparm->num_q = 1;

// 	if (mode == QDMA_Q_MODE_MM)
// 		qparm->flags |= XNL_F_QMODE_MM;
// 	else if (mode == QDMA_Q_MODE_ST)
// 		qparm->flags |= XNL_F_QMODE_ST;
// 	else {
// 		printf("Error: Invalid mode\n");
// 		return -EINVAL;
// 	}
// 	if (dir == DMAXFER_IO_WRITE)
// 		qparm->flags |= XNL_F_QDIR_H2C;
// 	else if (dir == DMAXFER_IO_READ)
// 		qparm->flags |= XNL_F_QDIR_C2H;
// 	else {
// 		printf("Error: Invalid Direction\n");
// 		return -EINVAL;
// 	}
// 	qparm->sflags = qparm->flags;

// 	return 0;
// }

// static int qdma_destroy_queue(enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_info xcmd;
// 	int ret;

// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	ret = qdma_prepare_q_stop(&xcmd, dir, qid, pf);
// 	if (ret < 0)
// 		printf("Q_PREP_STOP failed, ret :%d\n", ret);

// 	ret = qdma_q_stop(&xcmd);
// 	if (ret < 0)
// 		printf("Q_STOP failed, ret :%d\n", ret);

// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	ret = qdma_prepare_q_del(&xcmd, dir, qid, pf);
// 	if (ret < 0)
// 		printf("Q_PREP_DEL failed, ret :%d\n", ret);

// 	ret = qdma_q_del(&xcmd);
// 	if (ret < 0)
// 		printf("Q_DEL failed, ret :%d\n", ret);

// 	return ret;
// }

// static int qdma_create_queue(enum qdmautils_io_dir dir,
// 		int qid, int pf)
// {
// 	struct xcmd_info xcmd;
// 	int ret;

// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	ret = qdma_prepare_q_add(&xcmd, dir, qid, pf);
// 	if (ret < 0)
// 		return ret;

// 	ret = qdma_q_add(&xcmd);
// 	if (ret < 0) {
// 		printf("Q_ADD failed, ret :%d\n", ret);
// 		return ret;
// 	}

// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	ret = qdma_prepare_q_start(&xcmd, dir, qid, pf);
// 	if (ret < 0)
// 		return ret;

// 	ret = qdma_q_start(&xcmd);
// 	if (ret < 0) {
// 		printf("Q_START failed, ret :%d\n", ret);
// 		qdma_prepare_q_del(&xcmd, dir, qid, pf);
// 		qdma_q_del(&xcmd);
// 	}

// 	return ret;
// }

// static int qdma_prepare_queue(struct queue_info *q_info,
// 		enum qdmautils_io_dir dir, int qid, int pf)
// {
// 	int ret;

// 	if (!q_info) {
// 		printf("Error: Invalid queue info\n");
// 		return -EINVAL;
// 	}

// 	qdma_q_prep_name(q_info, qid, pf);
// 	q_info->dir = dir;
// 	ret = qdma_create_queue(q_info->dir, qid, pf);
// 	if (ret < 0) {
// 		printf("Q creation Failed PF:%d QID:%d\n",
// 				pf, qid);
// 		return ret;
// 	}
// 	q_info->qid = qid;
// 	q_info->pf = pf;

// 	//Assign core ID based on qid and num_cores
// 	if (num_cores == 0) {
// 		printf("Warning: num_cores is not set, using all available cores\n");
// 		num_cores = get_nprocs();
// 	}
// 	q_info->core_id = qid % num_cores;
// 	// q_info->packets_received = 0;
// 	atomic_init(&q_info->packets_received, 0);

// 	// ret = pthread_mutex_init(&q_info->packet_mutex, NULL);
// 	// if (ret != 0) {
// 	// 	printf("Error: Failed to initialize mutex for queue %d: %s\n", qid, strerror(ret));
// 	// 	return ret;
// 	// }

// 	q_info->thread = (pthread_t)NULL;
// 	printf("Queue %d Direction: %d assigned to core %d (PF %d)\n", qid, q_info->dir, q_info->core_id, pf);

// 	return 0;
// }

// static int qdma_register_write(unsigned int pf, int bar,
// 		unsigned long reg, unsigned long value)
// {
// 	struct xcmd_info xcmd;
// 	struct xcmd_reg *regcmd;
// 	int ret;
// 	regcmd = &xcmd.req.reg;
// 	xcmd.op = XNL_CMD_REG_WRT;
// 	xcmd.vf = is_vf;
// 	xcmd.if_bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
// 	regcmd->bar = bar;
// 	regcmd->reg = reg;
// 	regcmd->val = value;
// 	regcmd->sflags = XCMD_REG_F_BAR_SET |
// 		XCMD_REG_F_REG_SET |
// 		XCMD_REG_F_VAL_SET;
// 	printf("Writing register %lx to PF %d bar %d value %lx\n", reg, pf, bar, value);

// 	ret = qdma_reg_write(&xcmd);
// 	if (ret < 0)
// 		printf("QDMA_REG_WRITE Failed, ret :%d\n", ret);

// 	return ret;
// }

// static void qdma_queues_cleanup(struct queue_info *q_info, int q_count)
// {
// 	unsigned int q_index;

// 	if (!q_info || q_count < 0)
// 		return;

// 	for (q_index = 0; q_index < q_count; q_index++) {
// 		// Clean up the queue
// 		qdma_destroy_queue(q_info[q_index].dir,
// 				q_info[q_index].qid,
// 				q_info[q_index].pf);
// 		// free(q_info[q_index].q_name);
// 	}
// 	free(q_info);
// 	q_info = NULL;
// }

// static int qdma_setup_queues(struct queue_info **pq_info)
// {
// 	struct queue_info *q_info;
// 	unsigned int qid;
// 	unsigned int q_count;
// 	unsigned int q_index;
// 	int ret;

// 	if (!pq_info) {
// 		printf("Error: Invalid queue info\n");
// 		return -EINVAL;
// 	}

// 	if (dir == QDMA_Q_DIR_BIDI)
// 		q_count = num_q * 2;
// 	else
// 		q_count = num_q;

// 	*pq_info = q_info = (struct queue_info *)calloc(q_count, sizeof(struct queue_info));
// 	if (!q_info) {
// 		printf("Error: OOM\n");
// 		return -ENOMEM;
// 	}

// 	q_index = 0;
// 	for (qid = 0; qid < num_q; qid++) {
// 		if ((dir == QDMA_Q_DIR_BIDI) ||
// 				(dir == QDMA_Q_DIR_H2C)) {
// 			ret = qdma_prepare_queue(q_info + q_index,
// 					DMAXFER_IO_WRITE,
// 					qid + q_start,
// 					fun_id);
// 			if (ret < 0)
// 				break;
// 			q_index++;
// 		}
// 		if ((dir == QDMA_Q_DIR_BIDI) ||
// 				(dir == QDMA_Q_DIR_C2H)) {
// 			ret = qdma_prepare_queue(q_info + q_index,
// 					DMAXFER_IO_READ,
// 					qid + q_start,
// 					fun_id);
// 			if (ret < 0)
// 				break;
// 			q_index++;
// 		}
// 	}
// 	if (ret < 0) {
// 		qdma_queues_cleanup(q_info, q_index);
// 		return ret;
// 	}

// 	return q_count;
// }


// // static void qdma_env_cleanup()
// // {
// // 	qdma_queues_cleanup(q_info, q_count);

// // 	// if (q_info)
// // 	// 	free(q_info);
// // 	// q_info = NULL;
// // 	// q_count = 0;
// // }

// static int qdma_setup_fpga_generator(struct queue_info *q_info, int num_queues, unsigned char user_bar, unsigned int qbase)
// {
// 	int ret;

// 	/* Disable DMA Bypass */
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x90, 0);
// 	if (ret < 0) {
// 		printf("Failed to disable DMA Bypass PF :%d\n", q_info->pf);
// 		return ret;
// 	}

// 	/* Program RSS table*/
// 	int qid = 0;
// 	for (int i = 0; i < 128; i++) {
// 		ret = qdma_register_write(q_info->pf, user_bar, 0xA8 + i * 4, qid+qbase);
// 		if (ret < 0) {
// 			printf("Failed to program RSS table PF :%d QID :%d\n", q_info->pf, q_info->qid);
// 		}
// 		qid = (qid+1)%num_queues;
// 	}
// 	/* Program transfer size */
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x04, pkt_sz);
// 	if (ret < 0) {
// 		printf("Failed to set transfer size PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	/* Program cycles per packet*/
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x1C, cycles_per_pkt);
// 	if (ret < 0) {
// 		printf("Failed to set cycles_per_pkt PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	/* Program num queues to generate*/
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x28, num_queues);
// 	if (ret < 0) {
// 		printf("Failed to set cycles_per_pkt PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	/* Porgram traffic pattern */
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x20, traffic_pattern);
// 	if (ret < 0) {
// 		printf("Failed to set traffic pattern PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	/* Program HW QID */
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x0, qbase);
// 	if (ret < 0) {
// 		printf("Failed to program base HWQID PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	printf("Setup FPGA generator done\n");
//     /* Start C2H generator*/
// 	// ret = qdma_register_write(q_info->pf, user_bar, 0x08, 0x2);
// 	// if (ret < 0) {
// 	// 	printf("Failed to set start C2H generator PF :%d\n", q_info->pf);
// 	// 	return ret;
// 	// }
// 	return 0;
// }

// static int qdma_start_generator(struct queue_info *q_info, unsigned char user_bar) {
// 	int ret = 0;
// 	ret = qdma_register_write(q_info->pf, user_bar, 0x08, 0x2);
// 	if (ret < 0) {
// 		printf("Failed to set start C2H generator PF :%d\n", q_info->pf);
// 		return ret;
// 	}
// 	return 0;
// }

// static int qdma_stop_generator(struct queue_info *q_info, unsigned char user_bar) {
// 	// int ret = 0;
// 	// ret = qdma_register_write(q_info->pf, user_bar, 0x08, 0x40);
// 	// if (ret < 0) {
// 	// 	printf("Failed to set end C2H generator PF :%d\n", q_info->pf);
// 	// }
// 	// return ret;
// 	int ret = 0;
//     uint32_t status = 0;
//     int attempts = 0;
//     const int MAX_ATTEMPTS = 5;  // Up to 5 seconds
    
//     printf("Stopping hardware packet generator...\n");
    
//     // 1. Send stop command
//     ret = qdma_register_write(q_info->pf, user_bar, 0x08, 0x40);
//     if (ret < 0) {
//         printf("Failed to write stop command to C2H generator PF :%d\n", q_info->pf);
//         return ret;
//     }
    
//     // 2. Poll status register 0x18 to verify generator stopped
//     // Register 0x18 bit 0 = 1 means generator is idle/stopped
//     while (attempts < MAX_ATTEMPTS) {
//         usleep(200000);  // Wait 200ms before checking
        
//         ret = qdma_register_read(q_info->pf, user_bar, 0x18, &status);
//         if (ret < 0) {
//             printf("Warning: Failed to read generator status register\n");
//             break;
//         }
        
//         // Check if generator stopped (bit 0 == 1)
//         if ((status & 0x1) == 0x1) {
//             printf("Generator stopped successfully (status=0x%x) after %d attempts\n", 
//                    status, attempts + 1);
//             break;
//         }
        
//         printf("Waiting for generator to stop (status=0x%x, attempt %d/%d)...\n", 
//                status, attempts + 1, MAX_ATTEMPTS);
//         attempts++;
//         sleep(1);  // Wait 1 second between polls
//     }
    
//     if (attempts >= MAX_ATTEMPTS) {
//         printf("WARNING: Generator may not have stopped cleanly (final status=0x%x)\n", status);
//         // Give extra time for hardware to drain
//         sleep(2);
//     } else {
//         // Even after status shows stopped, give hardware time to fully drain
//         usleep(500000);  // Wait 500ms for pipeline to drain
//     }
    
//     printf("Hardware drain complete, safe to cleanup queues\n");
//     return 0;
// }

// static void *qdma_packet_receiver(void *arg)
// {
// 	struct queue_info *q_info = (struct queue_info*)arg;
// 	cpu_set_t cpuset;
// 	int ret;
// 	char *buffer = NULL;
// 	char *allocated = NULL;
// 	unsigned int size = pkt_sz;
// 	unsigned int offset = 0;
// 	uint64_t local_packet_count = 0;
	
// 	//Set CPU affinity to pin this thread to specific core
// 	CPU_ZERO(&cpuset);
// 	CPU_SET(q_info->core_id, &cpuset);
// 	ret = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
// 	if (ret != 0) {
// 		printf("Error: Failed to set CPU affinity for thread %d to core %d: %s\n", 
// 			q_info->qid, q_info->core_id, strerror(ret));
// 	}

// 	//allocate aligned buffer
// 	posix_memalign((void **)&allocated, 4096 /*alignment */ , size + 4096);
// 	if (!allocated) {
// 		printf("Error: OOM for queue %d buffer size %u.\n", q_info->qid, size + 4096);
// 		//free(allocated);
// 		return NULL;
// 	}
// 	buffer = allocated + offset;

// 	printf("Thread/Queue %d started on core %d\n", q_info->qid, q_info->core_id);

// 	//Main packet reception loop
// 	while(!shutdown_threads) {
// 		ret = qdmautils_async_xfer(q_info->q_name, q_info->dir, buffer, pkt_sz);
// 		if (ret > 0) {
// 			local_packet_count++;
// 			atomic_fetch_add(&q_info->packets_received, (ret/pkt_sz));
// 		} else if (ret < 0) {
// 			printf("Queue %d: packet reception error: %d\n", q_info->qid, ret);
// 			usleep(100);
// 		} else {
// 			usleep(100);
// 		}
// 		//check for thread cancellation
// 		//pthread_testcancel();
// 	}
// 	free(allocated);
// 	printf("Thread/Queue %d terminated gracefully after %lu packets\n", q_info->qid, local_packet_count);
// 	return NULL;
// }

// static int qdma_create_receiver_thread(struct queue_info *q_info, int q_count)
// {
// 	int ret;
// 	int i;

// 	printf("Creating receiver threads for %d queues\n", q_count);
// 	for (i = 0; i < q_count; i++) {
// 		if (q_info[i].dir == DMAXFER_IO_READ) {
// 			ret = pthread_create(&q_info[i].thread, NULL, qdma_packet_receiver, &q_info[i]);
// 			if (ret != 0) {
// 				printf("Error: Failed to create receiver thread for queue %d: %s\n", q_info[i].qid, strerror(ret));
// 				for (int j = 0; j < i; j++) {
// 					if (q_info[j].thread != (pthread_t)NULL) {
// 						pthread_cancel(q_info[j].thread);
// 						pthread_join(q_info[j].thread, NULL);
// 					}
// 				}
// 				return ret;
// 			}
// 			printf("Receiver thread for queue %d created on core %d\n", q_info[i].qid, q_info[i].core_id);
// 		}
// 	}
// 	return 0;
// }

// static void qdma_terminate_receiver_threads(struct queue_info *q_info, int q_count) {
// 	int i;
// 	struct timespec timeout;
// 	int ret;
// 	if (!q_info || q_count <= 0)
// 		return;
// 	printf("Terminating receiver threads for %d queues\n", q_count);
// 	//Step 1: Signal all threads to stop
// 	shutdown_threads = 1;
// 	printf("Shutdown signal sent to all receiver threads\n");
// 	//Step 2: Give threads time to see the shutdown signal
// 	usleep(200000); //200ms for threads to process the signal
// 	//Step 3: Wait for each thread to terminate gracefully
// 	for (i = 0; i < q_count;i++) {
// 		if (q_info[i].dir == DMAXFER_IO_READ && q_info[i].thread != (pthread_t)NULL) {
// 			printf("Waiting for thread %d to terminate gracefully\n", q_info[i].qid);
// 			//Set timeout for graceful termination
// 			clock_gettime(CLOCK_REALTIME, &timeout);
// 			timeout.tv_sec += 2;

// 			ret = pthread_timedjoin_np(q_info[i].thread, NULL, &timeout);
// 			if (ret == 0) {
// 				printf("Receiver thread %d terminated gracefully\n", q_info[i].qid);
// 				q_info[i].thread = (pthread_t)NULL;
// 			} else if (ret == ETIMEDOUT) {
// 				pthread_cancel(q_info[i].thread);
// 				pthread_join(q_info[i].thread, NULL);
// 				q_info[i].thread = (pthread_t)NULL;
// 				printf("Warning: Receiver thread %d timed out, terminating forcefully\n", q_info[i].qid);
// 			} else {
// 				pthread_cancel(q_info[i].thread);
// 				pthread_join(q_info[i].thread, NULL);
// 				q_info[i].thread - (pthread_t)NULL;
// 				printf("Warning: Failed to join receiver thread %d: %s\n", q_info[i].qid, strerror(ret));
// 			}
// 		}
// 	}
// 	printf("All receiver threads terminated\n");
// }

// static int qdmautils_xfer(struct queue_info *q_info,
// 		unsigned int count, unsigned char user_bar, unsigned int qbase, int io_type)
// {
// 	int ret;
// 	uint64_t total_packets = 0;
// 	uint64_t prev_total = 0;
// 	uint64_t packets_per_sec = 0;
// 	int i;
// 	time_t start_time = time(NULL);
// 	time_t current_time;
// 	double bits_per_sec = 0.0;

// 	//packet reception variables
// 	char *buffer = NULL;
// 	char *allocated = NULL;
// 	unsigned int size = pkt_sz;

// 	if (!q_info || count == 0) {
// 		printf("Error: Invalid input params\n");
// 		return -EINVAL;
// 	}
// 	//shutdown_threads = 0;

// 	//Allocate aligned buffer
// 	unsigned int batch_size = size * 8;
// 	posix_memalign((void **)&allocated, 4096 /*alignment */ , batch_size + 4096);
// 	if (!allocated) {
// 		printf("Error: OOM for queue %d buffer size %u.\n", q_info->qid, size + 4096);
// 		return -ENOMEM;
// 	}
// 	buffer = allocated;
// 	//start the packet generator
// 	// ret = qdma_trigger_data_generator(q_info, count, user_bar, qbase);
// 	// if (ret < 0) {
// 	// 	printf("Failed to trigger data generator\n");
// 	// 	return ret;
// 	// }
// 	ret = qdma_start_generator(q_info, user_bar);
// 	if (ret < 0) {
// 		printf("Failed to start packet generator\n");
// 		free(allocated);
// 		return ret;
// 	}

// 	printf("Packet generator started. Monitoring %d queues...\n", count);

// 	uint64_t hz = 1000000000;
// 	// uint64_t prev_time = ktime_get_ns();
// 	struct timespec ts;
// 	clock_gettime(CLOCK_MONOTONIC, &ts);
// 	uint64_t prev_time = ts.tv_sec * 1000000000ULL + ts.tv_nsec;
// 	uint64_t curr_time = prev_time;
// 	uint64_t diff_time = 0;

// 	while(1) {
// 		//Receive packets from the card
// 		for (i = 0; i < count; i++) {
// 			if (q_info[i].dir == DMAXFER_IO_READ) {
// 				unsigned int batch_size = pkt_sz * 8;
// 				ret = qdmautils_sync_xfer(q_info[i].q_name, q_info[i].dir, buffer, batch_size);
// 				if (ret > 0) {
// 					total_packets += (ret/pkt_sz);
// 				}
// 				else if (ret < 0) {
// 					printf("Queue %d: packet reception error: %d\n", q_info[i].qid, ret);
// 					usleep(100);
// 				} else {
// 					usleep(100);
// 				}
// 			}
// 		}
// 		// curr_time = ktime_get_ns();
// 		clock_gettime(CLOCK_MONOTONIC, &ts);
// 		curr_time = ts.tv_sec * 1000000000ULL + ts.tv_nsec;
// 		diff_time = curr_time - prev_time;
		
// 		if (diff_time > hz) {
// 			// total_packets = 0;
// 			// //Sum up packets from all threads - atomic_fetch_add
// 			// for (i = 0; i < count; i++) {
// 			// 	if (q_info[i].dir == DMAXFER_IO_READ) {
// 			// 		total_packets += atomic_load(&q_info[i].packets_received);
// 			// 	}
// 			// }

// 			//Caclulate packets per second
// 			packets_per_sec = total_packets - prev_total;
// 			prev_total = total_packets;
// 			bits_per_sec = packets_per_sec * 8 * pkt_sz;
// 			printf("Total packets: %lu, Rate: %lu pps, %f Gbps\n",
// 				total_packets, packets_per_sec, bits_per_sec/1000000000.0);

// 			prev_time = curr_time;

// 		}
// 		current_time = time(NULL);
// 		if (current_time - start_time >= 10) {
// 			printf("10 seconds elapsed. Stopping packet generator...\n");
// 			//qdma_terminate_receiver_threads(q_info, count);
// 			break;
// 		}
// 		//usleep(10000); //10ms
// 	}
// 	//Stop the generator
// 	ret = qdma_stop_generator(q_info, user_bar);
// 	if (ret < 0) {
// 		printf("Failed to stop packet generator\n");
// 	}
// 	//qdma_terminate_receiver_threads(q_info, count);
// 	//Final statistics
// 	// Final statistics
//     printf("\n=== Final Statistics ===\n");
//     printf("Total packets received: %lu\n", total_packets);
//     printf("Test duration: %ld seconds\n", current_time - start_time);
//     if (current_time > start_time) {
//         uint64_t avg_pps = total_packets / (current_time - start_time);
//         uint64_t avg_bps = avg_pps * pkt_sz * 8;
//         printf("Average rate: %lu pps, %.2f Mbps (%.2f Gbps)\n",
//             avg_pps,
//             (double)avg_bps / 1000000.0,
//             (double)avg_bps / 1000000000.0);
//     }
//     printf("Packet size: %u bytes\n", pkt_sz);
//     printf("========================\n");

//     // Clean up buffer
//     free(allocated);
// 	return ret;
// 	// for (i = 0; i < count; i++) {
// 	// 	if (q_info[i].dir == DMAXFER_IO_WRITE) {
// 	// 		/* Transfer DATA from inputfile to Device */
// 	// 		ret = qdmautils_write(q_info + i, input_file, io_type);
// 	// 		if (ret < 0)
// 	// 			printf("qdmautils_write failed, ret :%d\n", ret);
// 	// 	} else {
// 	// 		if (mode == QDMA_Q_MODE_ST) {
// 	// 			/* Generate ST - C2H Data before trying to read from Card */
// 	// 			ret = qdma_trigger_data_generator(q_info + i);
// 	// 			if (ret < 0) {
// 	// 				printf("Failed to trigger data generator\n");
// 	// 				return ret;
// 	// 			}
// 	// 		}
// 	// 		/* Reads data from Device and writes into output file */
// 	// 		ret = qdmautils_read(q_info + i, output_file, io_type);
// 	// 		if (ret < 0)
// 	// 			printf("qdmautils_read failed, ret :%d\n", ret);
// 	// 	}

// 	// 	if (ret < 0)
// 	// 		break;
// 	// }

// 	//qdma_stop_generator(q_info, user_bar);
// 	//return ret;
// }

// int main(int argc, char *argv[])
// {
// 	char *cfg_fname;
// 	int cmd_opt;
// 	int ret;
// 	if (argc == 2) {
// 		if (!strcmp(argv[1], "-v") || !strcmp(argv[1], "--version")) {
// 			printf("%s version %s\n", PROGNAME, VERSION);
// 			printf("%s\n", COPYRIGHT);
// 			return 0;
// 		}
// 	}
// 	cfg_fname = NULL;
// 	while ((cmd_opt = getopt_long(argc, argv, "vhxc:c:", long_opts, NULL)) != -1) {
// 		switch (cmd_opt) {
// 			case 0:
// 				/* long option */
// 				break;
// 			case 'c':
// 				/* config file name */
// 				cfg_fname = strdup(optarg);
// 				break;
// 			default:
// 				usage(argv[0]);
//                 printf("Invalid option\n");
// 				exit(0);
// 				break;
// 		}
// 	}
// 	if (cfg_fname == NULL) {
// 		printf("Config file required.\n");
// 		usage(argv[0]);
// 		return -EINVAL;
// 	}
// 	ret = parse_config_file(cfg_fname);
// 	if (ret < 0) {
// 		printf("Config File has invalid parameters\n");
// 		return ret;
// 	}
// 	ret = qdma_validate_qrange();
// 	if (ret < 0) {
//         printf("Failed to validate qrange\n");
// 		return ret;
//     }
// 	q_count = 0;
// 	/* Addition and Starting of queues handled here */
// 	q_count = qdma_setup_queues(&q_info);
// 	if (q_count < 0) {
// 		printf("qdma_setup_queues failed, ret:%d\n", q_count);
// 		return q_count;
// 	}
// 	/* queues has to be deleted upon termination */
// 	//atexit(qdma_env_cleanup);

// 	/* setup qdma dev*/
// 	struct xcmd_info xcmd;
// 	unsigned char user_bar;
// 	unsigned int qbase;

// 	if (!q_info) {
// 		printf("Error: Invalid queue info\n");
// 		return -EINVAL;
// 	}
// 	memset(&xcmd, 0, sizeof(struct xcmd_info));
// 	xcmd.op = XNL_CMD_DEV_INFO;
// 	xcmd.vf = is_vf;
// 	xcmd.if_bdf = (pci_bus << 12) | (pci_dev << 4) | q_info->pf;

// 	ret = qdma_dev_info(&xcmd);
// 	if (ret < 0) {
// 		printf("Failed to read qmax for PF: %d\n", q_info->pf);
// 		return ret;
// 	}
// 	user_bar = xcmd.resp.dev_info.user_bar;
// 	qbase = xcmd.resp.dev_info.qbase;

// 	// ret = qdma_create_receiver_thread(q_info, q_count);
// 	// if (ret < 0) {
// 	// 	printf("Failed to create receiver threads\n");
// 	// 	qdma_queues_cleanup(q_info, q_count);
// 	// 	return ret;
// 	// }
	
// 	//start the packet generator
// 	//ret = qdma_setup_fpga_generator(q_info, q_count, user_bar, qbase);
// 	ret = qdma_setup_fpga_generator(q_info, num_q, user_bar, qbase);
// 	if (ret < 0) {
// 		printf("Failed to trigger data generator\n");
// 		qdma_queues_cleanup(q_info, q_count);
// 		return ret;
// 	}
// 	printf("Starting DMA transfers on %d queues\n", q_count);

// 	/* Perform DMA transfers on each Queue */
// 	ret = qdmautils_xfer(q_info, q_count, user_bar, qbase, io_type);
// 	if (ret < 0)
// 		printf("Qdmautils Transfer Failed, ret :%d\n", ret);

// 	// Give extra time for all pending operations to complete
// 	printf("Waiting for hardware to fully settle before cleanup...\n");
// 	usleep(500000);  // 500ms extra safety margin
	
// 	free(cfg_fname);
// 	qdma_queues_cleanup(q_info, q_count);
// 	return ret;
// }


// // static int qdmautils_read(struct queue_info *q_info,
// // 		char *output_file, int io_type)
// // {
// // 	int outfile_fd = -1;
// // 	char *buffer = NULL;
// // 	char *allocated = NULL;
// // 	unsigned int size;
// // 	unsigned int offset;
// // 	int ret;

// // 	//if (!q_info || !input_file) {
// // 	if (!q_info) {
// // 		printf("Error: Invalid input params\n");
// // 		return -EINVAL;
// // 	}

// // 	size = pkt_sz;

// // 	outfile_fd = open(output_file, O_WRONLY | O_CREAT | O_TRUNC | O_SYNC);
// // 	if (outfile_fd < 0) {
// // 		printf("Error: unable to open/create output file %s, ret :%d\n",
// // 				output_file, outfile_fd);
// // 		perror("open/create output file");
// // 		return outfile_fd;
// // 	}

// // 	offset = 0;
// // 	posix_memalign((void **)&allocated, 4096 /*alignment */ , size + 4096);
// // 	if (!allocated) {
// // 		printf("Error: OOM %u.\n", size + 4096);
// // 		ret = -ENOMEM;
// // 		goto out;
// // 	}
// // 	buffer = allocated + offset;

// // 	if (io_type == 0) {
// // 		ret = qdmautils_sync_xfer(q_info->q_name,
// // 				q_info->dir, buffer, size);
// // 		if (ret < 0)
// // 			printf("Error: QDMA SYNC transfer Failed, ret :%d\n", ret);
// // 		else
// // 			printf("PF :%d Queue :%d C2H Sync transfer success\n", q_info->pf, q_info->qid);
// // 	} else {
// // 		ret = qdmautils_async_xfer(q_info->q_name,
// // 				q_info->dir, buffer, size);
// // 		if (ret < 0)
// // 			printf("Error: QDMA ASYNC transfer Failed, ret :%d\n", ret);
// // 		else
// // 			printf("PF :%d Queue :%d C2H ASync transfer success\n", q_info->pf, q_info->qid);
// // 	}
// // 	if (ret < 0)
// // 		goto out;

// // 	ret = write_from_buffer(output_file, outfile_fd, buffer, size, offset);
// // 	if (ret < 0)
// // 		printf("Error: Write from buffer to %s failed\n", output_file);
// // out:
// // 	free(allocated);
// // 	close(outfile_fd);

// // 	return ret;
// // }

// // static int qdmautils_write(struct queue_info *q_info,
// // 		char *input_file, int io_type)
// // {
// // 	int infile_fd = -1;
// // 	int outfile_fd = -1;
// // 	char *buffer = NULL;
// // 	char *allocated = NULL;
// // 	unsigned int size;
// // 	unsigned int offset;
// // 	int ret;
// // 	enum qdmautils_io_dir dir;

// // 	if (!q_info || !input_file) {
// // 		printf("Error: Invalid input params\n");
// // 		return -EINVAL;
// // 	}

// // 	size = pkt_sz;

// // 	infile_fd = open(input_file, O_RDONLY | O_NONBLOCK);
// // 	if (infile_fd < 0) {
// // 		printf("Error: unable to open input file %s, ret :%d\n",
// // 				input_file, infile_fd);
// // 		return infile_fd;
// // 	}

// // 	offset = 0;
// // 	posix_memalign((void **)&allocated, 4096 /*alignment */ , size + 4096);
// // 	if (!allocated) {
// // 		printf("Error: OOM %u.\n", size + 4096);
// // 		ret = -ENOMEM;
// // 		goto out;
// // 	}

// // 	buffer = allocated + offset;
// // 	ret = read_to_buffer(input_file, infile_fd, buffer, size, 0);
// // 	if (ret < 0)
// // 		goto out;

// // 	if (io_type == 0) {
// // 		ret = qdmautils_sync_xfer(q_info->q_name,
// // 				q_info->dir, buffer, size);
// // 		if (ret < 0)
// // 			printf("Error: QDMA SYNC transfer Failed, ret :%d\n", ret);
// // 		else
// // 			printf("PF :%d Queue :%d H2C Sync transfer success\n", q_info->pf, q_info->qid);
// // 	} else {
// // 		ret = qdmautils_async_xfer(q_info->q_name,
// // 				q_info->dir, buffer, size);
// // 		if (ret < 0)
// // 			printf("Error: QDMA ASYNC transfer Failed, ret :%d\n", ret);
// // 		else
// // 			printf("PF :%d Queue :%d H2C Async transfer success\n", q_info->pf, q_info->qid);
// // 	}

// // out:
// // 	free(allocated);
// // 	close(infile_fd);

// // 	return ret;
// // }

/*
 * ============================================================================
 * NEW IMPLEMENTATION - Following qdma_run_test_pf.sh C2H test logic
 * Pure C implementation tracing actual C code invoked by the script
 * ============================================================================
 */

/* Additional includes needed for new implementation */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <semaphore.h>
#include <sched.h>
#include <libaio.h>
#include <sys/uio.h>
#include <sys/mman.h>
#include <endian.h>
#include "version.h"
#include "dmautils.h"
#include "qdma_nl.h"
#include "dmaxfer.h"
#include "dmactl_internal.h"

#define MAX_AIO_EVENTS 65536  // Match dmaperf.c line 1136
#define DEFAULT_PAGE_SIZE 4096
#define PAGE_SHIFT 12

/* Memory pool for efficient allocation (from dmaperf.c/dmaxfer.c in dma-utils) */
struct dma_meminfo {
    void *memptr;
    unsigned int num_blks;
};

struct mempool_handle {
    void *mempool;
    unsigned int mempool_blkidx;
    unsigned int mempool_blksz;
    unsigned int total_memblks;
    struct dma_meminfo *mempool_info;
};

/* List node for AIO contexts */
struct aio_list_head {
    struct aio_list_head *next;
    unsigned int max_events;
    unsigned int completed_events;
    io_context_t ctxt;
};

/* Per-queue thread information (two threads per queue) */
struct queue_thread_info {
    // Thread handles
    pthread_t submit_thread;     // Submits I/O requests
    pthread_t completion_thread;  // Polls for completions
    
    // Queue info
    unsigned int qid;
    unsigned int bdf;
    char dev_name[64];
    int fd;
    
    // Configuration
    unsigned int pkt_size;
    unsigned int pkt_burst;       // Packets per I/O request
    
    // Statistics (atomic for thread-safety)
    unsigned int num_req_submitted;
    unsigned int num_req_completed;
    unsigned long long bytes_received;
    
    // Control
    volatile int running;
    volatile int io_exit;
    
    // Memory pools
    struct mempool_handle ctxhandle;
    struct mempool_handle iocbhandle;
    struct mempool_handle datahandle;
    
    // AIO list management
    struct aio_list_head *head;
    struct aio_list_head *tail;
    sem_t llock;
};

/* Memory pool functions (from dmaxfer.c in dma-utils) */
static int mempool_create(struct mempool_handle *mpool, unsigned int entry_size,
                          unsigned int max_entries)
{
    if (posix_memalign((void **)&mpool->mempool, DEFAULT_PAGE_SIZE,
                       max_entries * (entry_size + sizeof(struct dma_meminfo)))) {
        printf("OOM Mempool\n");
        return -ENOMEM;
    }
    mpool->mempool_info = (struct dma_meminfo *)(((char *)mpool->mempool) + 
                                                  (max_entries * entry_size));
    mpool->mempool_blksz = entry_size;
    mpool->total_memblks = max_entries;
    mpool->mempool_blkidx = 0;
    return 0;
}

static void mempool_free(struct mempool_handle *mpool)
{
    if (mpool->mempool) {
        free(mpool->mempool);
        mpool->mempool = NULL;
    }
}

static void *dma_memalloc(struct mempool_handle *mpool, unsigned int num_blks)
{
    unsigned int tmp_blkidx = mpool->mempool_blkidx;
    unsigned int max_blkcnt = tmp_blkidx + num_blks;
    unsigned int i, avail = 0;
    void *memptr = NULL;
    struct dma_meminfo *_mempool_info = mpool->mempool_info;
    
    if (max_blkcnt > mpool->total_memblks) {
        tmp_blkidx = 0;
        max_blkcnt = num_blks;
    }
    
    for (i = tmp_blkidx; (i < mpool->total_memblks) && (i < max_blkcnt); i++) {
        if (_mempool_info[i].memptr) {
            i += _mempool_info[i].num_blks;
            max_blkcnt = i + num_blks;
            avail = 0;
            tmp_blkidx = i;
        } else {
            avail++;
        }
        if (max_blkcnt > mpool->total_memblks) {
            if (num_blks > mpool->mempool_blkidx) return NULL;
            i = 0;
            avail = 0;
            max_blkcnt = num_blks;
            tmp_blkidx = i;
        }
        if (avail == num_blks) {
            _mempool_info[tmp_blkidx].memptr = &_mempool_info[tmp_blkidx];
            _mempool_info[tmp_blkidx].num_blks = num_blks;
            mpool->mempool_blkidx = i + 1;
            memptr = (char *)mpool->mempool + (tmp_blkidx * mpool->mempool_blksz);
            break;
        }
    }
    return memptr;
}

static void dma_free(struct mempool_handle *mpool, void *memptr)
{
    struct dma_meminfo *_meminfo = mpool->mempool_info;
    unsigned int idx;
    
    if (!memptr) return;
    
    idx = (memptr - mpool->mempool) / mpool->mempool_blksz;
    if (idx >= mpool->total_memblks) return;
    
    _meminfo[idx].num_blks = 0;
    _meminfo[idx].memptr = NULL;
}

/* AIO list management */
static void list_add_tail(struct queue_thread_info *qinfo, struct aio_list_head *node)
{
    sem_wait(&qinfo->llock);
    node->next = NULL;
    if (!qinfo->head) {
        qinfo->head = node;
        qinfo->tail = node;
    } else {
        qinfo->tail->next = node;
        qinfo->tail = node;
    }
    sem_post(&qinfo->llock);
}

static struct aio_list_head *list_pop(struct queue_thread_info *qinfo)
{
    struct aio_list_head *node = NULL;
    sem_wait(&qinfo->llock);
    if (qinfo->head) {
        node = qinfo->head;
        qinfo->head = node->next;
        if (!qinfo->head)
            qinfo->tail = NULL;
    }
    sem_post(&qinfo->llock);
    return node;
}

/* Helper function to read register via mmap (from dmactl_reg.c) */
static int read_user_register(unsigned int pci_bus, unsigned int pci_dev, 
                               unsigned int func, unsigned int reg, uint32_t *value)
{
    char fname[256];
    int fd;
    uint32_t *bar;
    
    // Path: /sys/bus/pci/devices/0000:BB:DD.F/resource2 (user BAR)
    snprintf(fname, sizeof(fname), 
             "/sys/bus/pci/devices/0000:%02x:%02x.%x/resource2",
             pci_bus, pci_dev, func);
    
    fd = open(fname, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Failed to open %s: %s\n", fname, strerror(errno));
        return -1;
    }
    
    // mmap the register region
    bar = mmap(NULL, reg + 4, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    
    if (bar == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap register region\n");
        return -1;
    }
    
    *value = le32toh(bar[reg / 4]);
    munmap(bar, reg + 4);
    
    return 0;
}

/* Helper function to write register via mmap (from dmactl_reg.c) */
static int write_user_register(unsigned int pci_bus, unsigned int pci_dev,
                                unsigned int func, unsigned int reg, uint32_t value)
{
    char fname[256];
    int fd;
    uint32_t *bar;
    
    snprintf(fname, sizeof(fname),
             "/sys/bus/pci/devices/0000:%02x:%02x.%x/resource2",
             pci_bus, pci_dev, func);
    
    fd = open(fname, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "Failed to open %s: %s\n", fname, strerror(errno));
        return -1;
    }
    
    bar = mmap(NULL, reg + 4, PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    
    if (bar == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap register region\n");
        return -1;
    }
    
    bar[reg / 4] = htole32(value);
    munmap(bar, reg + 4);
    
    return 0;
}

/* Queue management via netlink (from dmactl.c and cmd_parse.c) */
static int queue_add(unsigned int bdf, unsigned int qid, int is_vf)
{
    struct xcmd_info xcmd;
    struct xcmd_q_parm *qparm;
    uint32_t attrs[XNL_ATTR_MAX] = {0};
    
    memset(&xcmd, 0, sizeof(xcmd));
    qparm = &xcmd.req.qparm;
    
    xcmd.op = XNL_CMD_Q_ADD;
    xcmd.vf = is_vf;
    xcmd.if_bdf = bdf;
    qparm->idx = qid;
    qparm->num_q = 1;
    qparm->flags = XNL_F_QMODE_ST | XNL_F_QDIR_C2H;
    qparm->sflags = qparm->flags;
    
    return xnl_common_msg_send(&xcmd, attrs);
}

static int queue_start(unsigned int bdf, unsigned int qid, int is_vf)
{
    struct xcmd_info xcmd;
    struct xcmd_q_parm *qparm;
    uint32_t attrs[XNL_ATTR_MAX] = {0};
    
    memset(&xcmd, 0, sizeof(xcmd));
    qparm = &xcmd.req.qparm;
    
    xcmd.op = XNL_CMD_Q_START;
    xcmd.vf = is_vf;
    xcmd.if_bdf = bdf;
    qparm->idx = qid;
    qparm->num_q = 1;
    qparm->fetch_credit = Q_ENABLE_C2H_FETCH_CREDIT;
    qparm->qrngsz_idx = 9;  // Ring size index 9 = 2048 descriptors (default)
    
    // Flags from cmd_parse.c line 1058-1060
    qparm->flags = XNL_F_QMODE_ST | XNL_F_QDIR_C2H |
                   XNL_F_CMPL_STATUS_EN | XNL_F_CMPL_STATUS_ACC_EN |
                   XNL_F_CMPL_STATUS_PEND_CHK | XNL_F_CMPL_STATUS_DESC_EN |
                   XNL_F_FETCH_CREDIT;
    
    // Default completion entry size for ST C2H
    qparm->cmpt_entry_size = XNL_ST_C2H_CMPT_DESC_SIZE_8B;
    
    return xnl_common_msg_send(&xcmd, attrs);
}

static int queue_stop(unsigned int bdf, unsigned int qid, int is_vf)
{
    struct xcmd_info xcmd;
    struct xcmd_q_parm *qparm;
    uint32_t attrs[XNL_ATTR_MAX] = {0};
    
    memset(&xcmd, 0, sizeof(xcmd));
    qparm = &xcmd.req.qparm;
    
    xcmd.op = XNL_CMD_Q_STOP;
    xcmd.vf = is_vf;
    xcmd.if_bdf = bdf;
    qparm->idx = qid;
    qparm->num_q = 1;
    qparm->flags = XNL_F_QMODE_ST | XNL_F_QDIR_C2H;
    
    return xnl_common_msg_send(&xcmd, attrs);
}

static int queue_del(unsigned int bdf, unsigned int qid, int is_vf)
{
    struct xcmd_info xcmd;
    struct xcmd_q_parm *qparm;
    uint32_t attrs[XNL_ATTR_MAX] = {0};
    
    memset(&xcmd, 0, sizeof(xcmd));
    qparm = &xcmd.req.qparm;
    
    xcmd.op = XNL_CMD_Q_DEL;
    xcmd.vf = is_vf;
    xcmd.if_bdf = bdf;
    qparm->idx = qid;
    qparm->num_q = 1;
    qparm->flags = XNL_F_QMODE_ST | XNL_F_QDIR_C2H;
    
    return xnl_common_msg_send(&xcmd, attrs);
}

/* Completion thread - polls for completed I/O events (like event_mon in dmaperf) */
static void *completion_thread(void *arg)
{
    struct queue_thread_info *qinfo = (struct queue_thread_info *)arg;
    struct io_event *events = NULL;
    int num_events;
    struct timespec ts_cur = {0, 0};
    
    events = calloc(MAX_AIO_EVENTS, sizeof(struct io_event));
    if (!events) {
        fprintf(stderr, "Q%u completion: OOM for events\n", qinfo->qid);
        return NULL;
    }
    
    printf("Q%u: Completion thread started\n", qinfo->qid);
    
    while (!qinfo->io_exit) {
        struct aio_list_head *node = list_pop(qinfo);
        if (!node) {
            // Don't sleep - just yield CPU to avoid busy wait burning CPU cycles
            sched_yield();
            continue;
        }
        
        memset(events, 0, MAX_AIO_EVENTS * sizeof(struct io_event));
        do {
            num_events = io_getevents(node->ctxt, 1,
                                       node->max_events - node->completed_events,
                                       events, &ts_cur);
            
            for (int j = 0; (num_events > 0) && (j < num_events); j++) {
                struct iocb *iocb = (struct iocb *)events[j].obj;
                if (!iocb) continue;
                
                // Update completion counter and bytes
                qinfo->num_req_completed++;
                qinfo->bytes_received += events[j].res;
                
                // Free buffers
                struct iovec *iov = (struct iovec *)(iocb->u.c.buf);
                if (iov) {
                    for (unsigned int bufcnt = 0; bufcnt < iocb->u.c.nbytes; bufcnt++) {
                        dma_free(&qinfo->datahandle, iov[bufcnt].iov_base);
                    }
                }
                dma_free(&qinfo->iocbhandle, iocb);
            }
            
            if (num_events > 0)
                node->completed_events += num_events;
            
            if (node->completed_events >= node->max_events) {
                io_destroy(node->ctxt);
                dma_free(&qinfo->ctxhandle, node);
                break;
            }
        } while (!qinfo->io_exit);
        
        if (node->completed_events < node->max_events) {
            sem_wait(&qinfo->llock);
            node->next = qinfo->head;
            qinfo->head = node;
            sem_post(&qinfo->llock);
        }
    }
    
    free(events);
    printf("Q%u: Completion thread stopped\n", qinfo->qid);
    return NULL;
}

/* Submit thread - submits async I/O requests (like io_thread in dmaperf) */
static void *submit_thread(void *arg)
{
    struct queue_thread_info *qinfo = (struct queue_thread_info *)arg;
    // Ring size - should match glbl_rng_sz[rngidx] from hardware
    // For rngidx=0, this is typically 2048
    unsigned int max_reqs = 2048;
    
    // For ST C2H: io_sz = pkt_burst * pkt_size, burst_cnt = 1 (like dmaperf.c lines 1871-1873)
    unsigned int io_sz = qinfo->pkt_burst * qinfo->pkt_size;
    unsigned int burst_cnt = 1;  // Only 1 iovec for ST C2H
    unsigned int num_desc = (io_sz + DEFAULT_PAGE_SIZE - 1) >> PAGE_SHIFT;
    unsigned int cnt;
    int ret;
    struct iocb *io_list[1];
    
    // Create memory pools (matching dmaperf.c lines 1877-1879)
    mempool_create(&qinfo->datahandle, num_desc * DEFAULT_PAGE_SIZE,
                   max_reqs + (burst_cnt * num_desc));
    mempool_create(&qinfo->ctxhandle, sizeof(struct aio_list_head), max_reqs);
    mempool_create(&qinfo->iocbhandle, 
                   sizeof(struct iocb) + (burst_cnt * sizeof(struct iovec)),
                   max_reqs + (burst_cnt * num_desc));
    
    // Create completion thread
    if (pthread_create(&qinfo->completion_thread, NULL, completion_thread, qinfo)) {
        fprintf(stderr, "Q%u: Failed to create completion thread\n", qinfo->qid);
        return NULL;
    }
    
    printf("Q%u: Submit thread started (io_sz=%u, burst_cnt=%u, num_desc=%u)\n", 
           qinfo->qid, io_sz, burst_cnt, num_desc);
    
    while (qinfo->running) {
        struct aio_list_head *node = dma_memalloc(&qinfo->ctxhandle, 1);
        if (!node) {
            sched_yield();
            continue;
        }
        
        ret = io_queue_init(MAX_AIO_EVENTS, &node->ctxt);
        if (ret != 0) {
            fprintf(stderr, "Q%u: io_queue_init failed: %d\n", qinfo->qid, ret);
            dma_free(&qinfo->ctxhandle, node);
            sched_yield();
            continue;
        }
        
        cnt = 0;
        node->max_events = MAX_AIO_EVENTS;
        list_add_tail(qinfo, node);
        
        while (qinfo->running && cnt < MAX_AIO_EVENTS) {
            // Check if we have too many outstanding requests
            unsigned int submitted = qinfo->num_req_submitted;
            unsigned int completed = qinfo->num_req_completed;
            if ((submitted - completed) * num_desc > max_reqs) {
                sched_yield();
                continue;
            }
            
            // Allocate I/O control block
            io_list[0] = dma_memalloc(&qinfo->iocbhandle, 1);
            if (!io_list[0]) {
                if (cnt) {
                    node->max_events = cnt;
                    break;
                }
                sched_yield();
                continue;
            }
            
            // Allocate data buffer(s) - for ST C2H, burst_cnt = 1
            struct iovec *iov = (struct iovec *)(io_list[0] + 1);
            unsigned int iovcnt = 0;
            for (iovcnt = 0; iovcnt < burst_cnt; iovcnt++) {
                iov[iovcnt].iov_base = dma_memalloc(&qinfo->datahandle, 1);
                if (!iov[iovcnt].iov_base)
                    break;
                iov[iovcnt].iov_len = io_sz;  // Full burst size (pkt_burst * pkt_size)
            }
            
            if (iovcnt == 0) {
                dma_free(&qinfo->iocbhandle, io_list[0]);
                continue;
            }
            
            // Prepare async read (C2H)
            io_prep_preadv(io_list[0], qinfo->fd, iov, iovcnt, 0);
            
            // Submit I/O
            ret = io_submit(node->ctxt, 1, io_list);
            if (ret != 1) {
                fprintf(stderr, "Q%u: io_submit failed: %d (errno=%d)\n", qinfo->qid, ret, errno);
                for (; iovcnt > 0; iovcnt--)
                    dma_free(&qinfo->datahandle, iov[iovcnt - 1].iov_base);
                dma_free(&qinfo->iocbhandle, io_list[0]);
                node->max_events = cnt;
                break;
            }
            
            qinfo->num_req_submitted++;
            cnt++;
        }
    }
    
    // Signal completion thread to exit
    qinfo->io_exit = 1;
    pthread_join(qinfo->completion_thread, NULL);
    
    // Clean up memory pools
    mempool_free(&qinfo->datahandle);
    mempool_free(&qinfo->iocbhandle);
    mempool_free(&qinfo->ctxhandle);
    
    printf("Q%u: Submit thread stopped\n", qinfo->qid);
    return NULL;
}

/* Main test function following script logic with multi-threading */
int main(int argc, char *argv[])
{
    struct queue_thread_info *qthreads = NULL;
    time_t start_time, current_time;
    struct timespec ts_start, ts_current;
    uint64_t start_time_ns, current_time_ns, last_stats_time = 0;
    int ret = 0;
    uint32_t status_reg;
    
    // Configuration - can be read from config file or command line
    unsigned int pci_bus = 0x99;
    unsigned int pci_dev = 0x00;
    unsigned int pf = 0;
    unsigned int q_start = 0;  // Starting queue ID
    unsigned int num_queues = 2;  // Number of queues to use
    unsigned int pkt_size = 1024;
    unsigned int bdf = (pci_bus << 12) | (pci_dev << 4) | pf;
    int is_vf = 0;
    unsigned int test_duration = 10;  // seconds
    
    printf("==============================================\n");
    printf("QDMA Multi-Queue C2H Test\n");
    printf("PCI: %02x:%02x.%x, Queues: %u-%u, Packet Size: %u bytes\n", 
           pci_bus, pci_dev, pf, q_start, q_start + num_queues - 1, pkt_size);
    printf("Number of worker threads: %u\n", num_queues);
    printf("==============================================\n\n");
    
    // Allocate thread info array
    qthreads = calloc(num_queues, sizeof(struct queue_thread_info));
    if (!qthreads) {
        fprintf(stderr, "ERROR: Failed to allocate thread info\n");
        return -1;
    }
    
    // Step 1: Cleanup any existing queues
    printf("Step 1: Cleaning up existing queues...\n");
    for (unsigned int i = 0; i < num_queues; i++) {
        unsigned int qid = q_start + i;
        queue_stop(bdf, qid, is_vf);  // Ignore errors
        usleep(50000);
        queue_del(bdf, qid, is_vf);  // Ignore errors
    }
    usleep(500000);  // Wait for cleanup
    
    // Step 2: Add and start all queues
    printf("Step 2: Adding %u C2H queues...\n", num_queues);
    for (unsigned int i = 0; i < num_queues; i++) {
        unsigned int qid = q_start + i;
        
        ret = queue_add(bdf, qid, is_vf);
        if (ret < 0) {
            printf("ERROR: queue_add failed for Q%u: %d\n", qid, ret);
            goto cleanup;
        }
        
        ret = queue_start(bdf, qid, is_vf);
        if (ret < 0) {
            printf("ERROR: queue_start failed for Q%u: %d\n", qid, ret);
            goto cleanup;
        }
        
        // Open device file for this queue
        snprintf(qthreads[i].dev_name, sizeof(qthreads[i].dev_name),
                 "/dev/qdma%05x-ST-%u", bdf, qid);
        
        // Open with O_RDWR like dmaperf.c (line 2017), no O_NONBLOCK for AIO
        qthreads[i].fd = open(qthreads[i].dev_name, O_RDWR);
        if (qthreads[i].fd < 0) {
            fprintf(stderr, "ERROR: Failed to open %s: %s\n", 
                    qthreads[i].dev_name, strerror(errno));
            ret = -1;
            goto cleanup;
        }
        
        // Initialize thread info
        qthreads[i].qid = qid;
        qthreads[i].bdf = bdf;
        qthreads[i].pkt_size = pkt_size;
        atomic_init(&qthreads[i].bytes_received, 0);
        qthreads[i].running = 0;  // Not started yet
        
        printf("Queue %u ready: %s\n", qid, qthreads[i].dev_name);
    }
    
    usleep(200000);  // Wait for all queues to be ready
    
    // Step 3: Program RSS table (distribute across queues)
    printf("Step 3: Programming RSS table (distributing to %u queues)...\n", num_queues);
    for (int i = 0; i < 128; i++) {
        unsigned int target_qid = q_start + (i % num_queues);  // Round-robin distribution
        write_user_register(pci_bus, pci_dev, pf, 0xA8 + (i * 4), target_qid);
    }
    
    // Step 4: Program hardware generator parameters
    printf("Step 4: Programming hardware generator...\n");
    write_user_register(pci_bus, pci_dev, pf, 0x04, pkt_size);      // Transfer size
    write_user_register(pci_bus, pci_dev, pf, 0x1C, 0);             // Cycles/pkt = 0 (max rate)
    write_user_register(pci_bus, pci_dev, pf, 0x28, num_queues);    // Num queues
    write_user_register(pci_bus, pci_dev, pf, 0x20, 0);             // Traffic pattern
    write_user_register(pci_bus, pci_dev, pf, 0x00, q_start);       // HW QID base
    
    // Step 5: Start C2H generator
    printf("Step 5: Starting C2H generator...\n");
    ret = write_user_register(pci_bus, pci_dev, pf, 0x08, 0x2);
    if (ret < 0) {
        printf("ERROR: Failed to start generator\n");
        goto cleanup;
    }
    
    usleep(100000);  // Wait for generator to start
    
    // Step 6: Initialize and create worker threads (submit threads)
    printf("Step 6: Starting %u worker threads (2 threads/queue: submit + completion)...\n", num_queues);
    for (unsigned int i = 0; i < num_queues; i++) {
        // Initialize semaphore for AIO list
        sem_init(&qthreads[i].llock, 0, 1);
        qthreads[i].head = NULL;
        qthreads[i].tail = NULL;
        qthreads[i].pkt_burst = 64;  // Match dmaperf config (num_pkt=64)
        qthreads[i].num_req_submitted = 0;
        qthreads[i].num_req_completed = 0;
        qthreads[i].bytes_received = 0;
        qthreads[i].running = 1;
        qthreads[i].io_exit = 0;
        
        // Create submit thread (which will create completion thread)
        if (pthread_create(&qthreads[i].submit_thread, NULL, submit_thread, &qthreads[i]) != 0) {
            fprintf(stderr, "ERROR: Failed to create submit thread for Q%u\n", qthreads[i].qid);
            ret = -1;
            goto stop_threads;
        }
    }
    
    printf("All threads started. Beginning statistics collection...\n\n");
    
    // Step 7: Main thread monitors and accumulates stats
    start_time = time(NULL);
    clock_gettime(CLOCK_MONOTONIC, &ts_start);
    start_time_ns = ts_start.tv_sec * 1000000000ULL + ts_start.tv_nsec;
    last_stats_time = 0;
    uint64_t last_total_bytes = 0;
    
    while (1) {
        current_time = time(NULL);
        
        if (current_time - start_time >= test_duration) {
            printf("\nTest duration reached (%u seconds)\n", test_duration);
            break;
        }
        
        // Accumulate bytes from all queue threads (atomic reads)
        uint64_t current_total_bytes = 0;
        for (unsigned int i = 0; i < num_queues; i++) {
            current_total_bytes += qthreads[i].bytes_received;
        }
        
        // Print aggregate stats every second
        clock_gettime(CLOCK_MONOTONIC, &ts_current);
        current_time_ns = ts_current.tv_sec * 1000000000ULL + ts_current.tv_nsec;
        uint64_t elapsed_ns = current_time_ns - start_time_ns;
        
        if (elapsed_ns - last_stats_time >= 1000000000ULL) {  // 1 second
            uint64_t bytes_this_sec = current_total_bytes - last_total_bytes;
            double gbps = (double)(bytes_this_sec * 8) / 1000000000.0;
            
            // Show per-queue breakdown
            printf("Rate: %.4f Gbit/sec [", gbps);
            for (unsigned int i = 0; i < num_queues; i++) {
                uint64_t q_bytes = atomic_load(&qthreads[i].bytes_received);
                if (i > 0) printf(", ");
                printf("Q%u: %.2f", qthreads[i].qid, (double)(q_bytes * 8) / 1000000000.0);
            }
            printf(" Gbit cumulative]\n");
            
            last_total_bytes = current_total_bytes;
            last_stats_time = elapsed_ns;
        }
        
        usleep(10000);  // Small delay for main thread (10ms)
    }
    
    // Step 8: Stop threads
stop_threads:
    printf("\nStopping worker threads...\n");
    for (unsigned int i = 0; i < num_queues; i++) {
        qthreads[i].running = 0;  // Signal submit thread to stop
    }
    
    // Wait for all submit threads to finish (they will wait for completion threads)
    for (unsigned int i = 0; i < num_queues; i++) {
        if (qthreads[i].submit_thread) {
            pthread_join(qthreads[i].submit_thread, NULL);
        }
        sem_destroy(&qthreads[i].llock);
    }
    
    printf("All threads stopped.\n");
    
    // Step 9: Stop generator
    printf("Stopping hardware generator...\n");
    write_user_register(pci_bus, pci_dev, pf, 0x08, 0x40);
    
    // Step 10: Wait for generator to stop (poll register 0x18)
    printf("Waiting for generator to stop...\n");
    for (int wait = 0; wait < 3; wait++) {
        sleep(1);
        if (read_user_register(pci_bus, pci_dev, pf, 0x18, &status_reg) == 0) {
            if ((status_reg & 0x1) == 0x1) {
                printf("Generator stopped (status=0x%x)\n", status_reg);
                break;
            }
        }
    }
    
    usleep(500000);  // Extra settling time
    
    // Step 11: Close device files
    for (unsigned int i = 0; i < num_queues; i++) {
        if (qthreads[i].fd >= 0) {
            close(qthreads[i].fd);
            qthreads[i].fd = -1;
        }
    }
    
    // Step 12: Stop and delete all queues
    printf("Cleaning up queues...\n");
cleanup:
    for (unsigned int i = 0; i < num_queues; i++) {
        unsigned int qid = q_start + i;
        queue_stop(bdf, qid, is_vf);
        usleep(50000);
    }
    usleep(200000);
    
    for (unsigned int i = 0; i < num_queues; i++) {
        unsigned int qid = q_start + i;
        queue_del(bdf, qid, is_vf);
    }
    
    // Step 13: Calculate final statistics
    clock_gettime(CLOCK_MONOTONIC, &ts_current);
    current_time_ns = ts_current.tv_sec * 1000000000ULL + ts_current.tv_nsec;
    double total_time = (double)(current_time_ns - start_time_ns) / 1000000000.0;
    
    // Get final byte counts from all queues
    uint64_t total_bytes = 0;
    for (unsigned int i = 0; i < num_queues; i++) {
        total_bytes += atomic_load(&qthreads[i].bytes_received);
    }
    
    double avg_gbps = (double)(total_bytes * 8) / total_time / 1000000000.0;
    
    printf("\n=== Final Statistics ===\n");
    printf("Total bytes received: %lu\n", total_bytes);
    printf("Test duration: %.2f seconds\n", total_time);
    printf("Average throughput: %.4f Gbit/sec\n", avg_gbps);
    printf("Packet size: %u bytes\n", pkt_size);
    
    // Per-queue breakdown
    printf("\nPer-Queue Statistics:\n");
    for (unsigned int i = 0; i < num_queues; i++) {
        uint64_t q_bytes = atomic_load(&qthreads[i].bytes_received);
        double q_gbps = (double)(q_bytes * 8) / total_time / 1000000000.0;
        printf("  Queue %u: %lu bytes (%.4f Gbit/sec)\n", 
               qthreads[i].qid, q_bytes, q_gbps);
    }
    printf("========================\n");
    
    if (qthreads)
        free(qthreads);
    
    printf("\nTest completed successfully.\n");
    return ret;
}
