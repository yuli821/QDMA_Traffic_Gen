/*
 * This file is part of the QDMA userspace application
 * to enable the user to execute the QDMA functionality
 *
 * Copyright (c) 2018-2022, Xilinx, Inc. All rights reserved.
 * Copyright (c) 2022-2024, Advanced Micro Devices, Inc. All rights reserved.
 *
 * This source code is licensed under BSD-style license (found in the
 * LICENSE file in the root directory of this source tree)
 */

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500
#include <assert.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include "dma_xfer_utils.c"

#define DEVICE_NAME_DEFAULT "/dev/qdma01000-MM-0"
#define SIZE_DEFAULT (32)
#define COUNT_DEFAULT (1)




static struct option const long_opts[] = {
	{"device", required_argument, NULL, 'd'},
	{"address", required_argument, NULL, 'a'},
	{"size", required_argument, NULL, 's'},
	{"offset", required_argument, NULL, 'o'},
	{"count", required_argument, NULL, 'c'},
	{"file", required_argument, NULL, 'f'},
	{"timeout", required_argument, NULL, 't'},
	{"help", no_argument, NULL, 'h'},
	{"verbose", no_argument, NULL, 'v'},
	{0, 0, 0, 0}
};

static int test_dma(char *devname, uint64_t addr, uint64_t size,
		    uint64_t offset, uint64_t count, char *ofname);
static int test_dma_timed(char *devname, uint64_t addr, uint64_t size, uint64_t offset,
	char *ofname, int timeout_seconds);
static int no_write = 0;

static void usage(const char *name)
{
	int i = 0;
	fprintf(stdout, "%s\n\n", name);
	fprintf(stdout, "usage: %s [OPTIONS]\n\n", name);
	fprintf(stdout, "Read via SGDMA, optionally save output to a file\n\n");

	fprintf(stdout, "  -%c (--%s) device (defaults to %s)\n",
		long_opts[i].val, long_opts[i].name, DEVICE_NAME_DEFAULT);
	i++;
	fprintf(stdout, "  -%c (--%s) the start address on the AXI bus\n",
	       long_opts[i].val, long_opts[i].name);
	i++;
	fprintf(stdout,
		"  -%c (--%s) size of a single transfer in bytes, default %d.\n",
		long_opts[i].val, long_opts[i].name, SIZE_DEFAULT);
	i++;
	fprintf(stdout, "  -%c (--%s) page offset of transfer\n",
		long_opts[i].val, long_opts[i].name);
	i++;
	fprintf(stdout, "  -%c (--%s) number of transfers, default is %d.\n",
	       long_opts[i].val, long_opts[i].name, COUNT_DEFAULT);
	i++;
	fprintf(stdout,
		"  -%c (--%s) file to write the data of the transfers\n",
		long_opts[i].val, long_opts[i].name);
	i++;
	fprintf(stdout, "  -%c (--%s) print usage help and exit\n",
		long_opts[i].val, long_opts[i].name);
	i++;
	fprintf(stdout, "  -%c (--%s) verbose output\n",
		long_opts[i].val, long_opts[i].name);
}

int main(int argc, char *argv[])
{
	int cmd_opt;
	char *device = DEVICE_NAME_DEFAULT;
	uint64_t address = 0;
	uint64_t size = SIZE_DEFAULT;
	uint64_t offset = 0;
	uint64_t count = COUNT_DEFAULT;
	char *ofname = NULL;
	int timeout_seconds = 0;

	while ((cmd_opt = getopt_long(argc, argv, "vhxc:f:d:a:s:o:t:", long_opts,
			    NULL)) != -1) {
		switch (cmd_opt) {
		case 0:
			/* long option */
			break;
		case 'd':
			/* device node name */
			device = strdup(optarg);
			break;
		case 'a':
			/* RAM address on the AXI bus in bytes */
			address = getopt_integer(optarg);
			break;
			/* RAM size in bytes */
		case 's':
			size = getopt_integer(optarg);
			break;
		case 'o':
			offset = getopt_integer(optarg) & 4095;
			break;
			/* count */
		case 'c':
			count = getopt_integer(optarg);
			break;
			/* count */
		case 'f':
			ofname = strdup(optarg);
			break;
			/* print usage help and exit */
		case 't':
			timeout_seconds = getopt_integer(optarg);
			break;
    	case 'x':
			no_write++;
			break;
		case 'v':
			verbose = 1;
			break;
		case 'h':
		default:
			usage(argv[0]);
			exit(0);
			break;
		}
	}
	if (verbose)
	fprintf(stdout,
		"dev %s, addr 0x%lx, size 0x%lx, offset 0x%lx, count %lu\n",
		device, address, size, offset, count);
	if (timeout_seconds) {
		return test_dma_timed(device, address, size, offset, ofname, timeout_seconds);
	} else {
		return test_dma(device, address, size, offset, count, ofname);
	}

	//return test_dma(device, address, size, offset, count, ofname);
}

static int test_dma_timed(char *devname, uint64_t addr, uint64_t size, uint64_t offset,
			char *ofname, int timeout_seconds)
{
	ssize_t rc;
    uint64_t total_packets = 0;
	uint64_t total_bytes = 0;
    uint64_t prev_packets = 0;
    uint64_t packets_this_second = 0;
    char *buffer = NULL;
    char *allocated = NULL;
    struct timespec ts_start, ts_current;
    int out_fd = -1;
    int fpga_fd = open(devname, O_RDWR | O_NONBLOCK);
    time_t start_time, current_time;
    uint64_t start_time_ns, current_time_ns, last_stats_time = 0;
    double total_time = 0;

    if (fpga_fd < 0) {
        fprintf(stderr, "unable to open device %s, %d.\n", devname, fpga_fd);
        perror("open device");
        return -EINVAL;
    }

    /* create file to write data to */
    if (ofname) {
        out_fd = open(ofname, O_RDWR | O_CREAT | O_TRUNC | O_SYNC, 0666);
        if (out_fd < 0) {
            fprintf(stderr, "unable to open output file %s, %d.\n", ofname, out_fd);
            perror("open output file");
            rc = -EINVAL;
            goto out;
        }
    }

    posix_memalign((void **)&allocated, 4096 /*alignment */, size*32);
    if (!allocated) {
        fprintf(stderr, "OOM %lu.\n", size*32);
        rc = -ENOMEM;
        goto out;
    }

    buffer = allocated + offset;
    if (verbose)
        fprintf(stdout, "host buffer 0x%lx, %p.\n", size*32, buffer);

    printf("Starting time-based packet reception for %d seconds...\n", timeout_seconds);
    printf("Packet size: %lu bytes\n", size);
    
    start_time = time(NULL);
    clock_gettime(CLOCK_MONOTONIC, &ts_start);
    start_time_ns = ts_start.tv_sec * 1000000000ULL + ts_start.tv_nsec;
    
    // Time-based reception loop with 1-second statistics
    while (1) {
        current_time = time(NULL);
        
        // Check if timeout reached
        if (current_time - start_time >= timeout_seconds) {
            printf("\nTimeout reached (%d seconds), stopping reception\n", timeout_seconds);
            break;
        }
        
        // Try to read packets
        rc = read_to_buffer(devname, fpga_fd, buffer, size*32, addr);
        if (rc > 0) {
            //total_packets++;
            total_bytes += rc;
            /* file argument given? */
            // if ((out_fd >= 0) && (no_write == 0)) {
            //     rc = write_from_buffer(ofname, out_fd, buffer, size, total_packets * size);
            //     if (rc < 0) {
            //         printf("Error writing to output file\n");
            //         goto out;
            //     }
            // }
        } else if (rc < 0) {
            // Error occurred
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                fprintf(stderr, "Read error: %s\n", strerror(errno));
                break;
            }
            // EAGAIN/EWOULDBLOCK means no data available, continue
        }

		// Get current time in nanoseconds for 1-second intervals
        clock_gettime(CLOCK_MONOTONIC, &ts_current);
        current_time_ns = ts_current.tv_sec * 1000000000ULL + ts_current.tv_nsec;
        uint64_t elapsed_ns = current_time_ns - start_time_ns;
        
        // Print statistics every second
        if (elapsed_ns - last_stats_time >= 1000000000ULL) {  // 1 second
            // packets_this_second = total_packets - prev_packets;
            // prev_packets = total_packets;
            last_stats_time = elapsed_ns;
            
            // Calculate Gbit/sec properly: (packets * bits_per_packet) / time_in_seconds / 1e9
            //uint64_t bits_this_second = packets_this_second * size * 8;  // size in bytes * 8 = bits
            double gbps = (double)(total_bytes*8) / 1000000000.0;  // Convert to Gbit/sec
            
            printf("Rate: %.4f Gbit/sec\n", 
                   //(elapsed_ns / 1000000000ULL), 
                   //total_packets, 
                   gbps
                   //packets_this_second
			);
			total_bytes = 0;
        }
        
        // Small delay to prevent CPU spinning
        //usleep(100);  // 0.1ms
    }
    
    // Calculate final statistics
    clock_gettime(CLOCK_MONOTONIC, &ts_current);
    current_time_ns = ts_current.tv_sec * 1000000000ULL + ts_current.tv_nsec;
    total_time = (double)(current_time_ns - start_time_ns) / 1000000000.0;
    
    //uint64_t total_bits = total_packets * size * 8;
    //double avg_gbps = (double)total_bits / total_time / 1000000000.0;
    
    printf("\n=== Final Statistics ===\n");
    //printf("Total packets received: %lu\n", total_packets);
    //printf("Total bytes received: %lu\n", total_packets * size);
    printf("Test duration: %.2f seconds\n", total_time);
    //printf("Average throughput: %.2f Gbit/sec\n", avg_gbps);
    //printf("Packet rate: %.2f pps\n", (double)total_packets / total_time);
    printf("Packet size: %lu bytes\n", size);
    printf("========================\n");

    //dump_throughput_result(total_packets * size, (avg_gbps * 1000000000.0));

    rc = 0;

out:
    close(fpga_fd);
    if (out_fd >= 0)
        close(out_fd);
    free(allocated);

    return rc;
}

static int test_dma(char *devname, uint64_t addr, uint64_t size,
		    uint64_t offset, uint64_t count, char *ofname)
{
	ssize_t rc;
	uint64_t i;
	char *buffer = NULL;
	char *allocated = NULL;
	struct timespec ts_start, ts_end;
	int out_fd = -1;
	int fpga_fd = open(devname, O_RDWR | O_NONBLOCK);
	double total_time = 0;
	double result;
	double avg_time = 0;

	if (fpga_fd < 0) {
                fprintf(stderr, "unable to open device %s, %d.\n",
                        devname, fpga_fd);
		perror("open device");
                return -EINVAL;
        }

	/* create file to write data to */
	if (ofname) {
		out_fd = open(ofname, O_RDWR | O_CREAT | O_TRUNC | O_SYNC,
				0666);
		if (out_fd < 0) {
                        fprintf(stderr, "unable to open output file %s, %d.\n",
                                ofname, out_fd);
			perror("open output file");
                        rc = -EINVAL;
                        goto out;
                }
	}

	posix_memalign((void **)&allocated, 4096 /*alignment */ , size + 4096);
	if (!allocated) {
		fprintf(stderr, "OOM %lu.\n", size + 4096);
		rc = -ENOMEM;
		goto out;
	}

	buffer = allocated + offset;
	if (verbose)
	fprintf(stdout, "host buffer 0x%lx, %p.\n", size + 4096, buffer);

	for (i = 0; i < count; i++) {
		clock_gettime(CLOCK_MONOTONIC, &ts_start);
		/* lseek & read data from AXI MM into buffer using SGDMA */
		rc = read_to_buffer(devname, fpga_fd, buffer, size, addr);
		if (rc < 0)
			goto out;
		clock_gettime(CLOCK_MONOTONIC, &ts_end);

		/* subtract the start time from the end time */
		timespec_sub(&ts_end, &ts_start);
		total_time += (ts_end.tv_sec + ((double)ts_end.tv_nsec/NSEC_DIV));
		/* a bit less accurate but side-effects are accounted for */
		if (verbose)
		fprintf(stdout,
			"#%lu: CLOCK_MONOTONIC %ld.%09ld sec. read %lu bytes\n",
			i, ts_end.tv_sec, ts_end.tv_nsec, size);

		/* file argument given? */
		if ((out_fd >= 0) & (no_write == 0)) {
			rc = write_from_buffer(ofname, out_fd, buffer,
					 size, i*size);
			if (rc < 0)
				goto out;
		}
	}
	avg_time = (double)total_time/(double)count;
	result = ((double)size)/avg_time;
	if (verbose)
	printf("** Avg time device %s, total time %f nsec, avg_time = %f, size = %lu, BW = %f bytes/sec\n",
		devname, total_time, avg_time, size, result);
	dump_throughput_result(size, result);

	rc = 0;

out:
	close(fpga_fd);
	if (out_fd >= 0)
		close(out_fd);
	free(allocated);

	return rc;
}
