#!/bin/bash

# DPDK program parameters
interval=10
cycles=0
pkt_size=128
num_cores=1

# PCM binary location (update the path if necessary)
PCM_BIN="/home/jiaqi/tools/pcm/build/bin/pcm-memory"

# List of DDIO ddio_masks (you can modify this list as needed)
# ddio_masks=(c0000 e0000 f0000 f8000 fc000 fe000 ff000 ff800 ffc00 ffe00 fff00 fff80 fffc0 fffe0 ffff0 ffff8 ffffc ffffe fffff)
# ddio_masks=(f0000 ff000 fff00 ffff0 fffff)
ddio_masks=(c0000 f0000 ff000 fff00 ffff0 fffff)
ddio_masks=(c0000)

# Function to run PCM concurrently with a test command
run_with_pcm() {
    local pcm_csv_file="$1"
    shift
    echo "Starting PCM measurement, outputting to ${pcm_csv_file} ..."
    # Start PCM measurement in the background.
    # (This command will run until it is killed, so we capture its PID.)
    sudo ${PCM_BIN} 1 -csv=${pcm_csv_file} &
    PCM_PID=$!
    
    # Run the test command (passed as arguments)
    "$@"

    # Kill the entire process group for PCM.
    sudo kill -$PCM_PID
    CHILDREN=$(pgrep -P $PCM_PID)
    if [ -n "$CHILDREN" ]; then
        echo "Killing PCM child processes: $CHILDREN"
        sudo kill $CHILDREN
    fi

    # Give PCM time to flush its final data
    sleep 2
}

echo "----------------------------------------------------"
echo "Experiment: DDIO Disabled (PCM measurement)"
echo "----------------------------------------------------"
# Disable DDIO
sudo /home/jiaqi/tools/ddio-bench/change-ddio 0
sleep 2
# Run test_RR with PCM measurement (output file: pcm_ddio_disabled.csv)
run_with_pcm "result_change_ways/pcm_ddio_disabled.csv" sudo ./build/test_RR -c 0x3 --main-lcore ${num_cores} -- -p 0 -q ${num_cores} -Q ${num_cores} -s ${pkt_size} -n 0 -c ${cycles} -d 0x00000 -i ${interval}
# run_with_pcm "result_change_ways/pcm_ddio_disabled.csv" sudo ./build/test_RR -c 0x1f --main-lcore ${num_cores} -- -p 0 -q ${num_cores} -Q ${num_cores} -s ${pkt_size} -n 0 -c ${cycles} -d 0x00000 -i ${interval}

echo "----------------------------------------------------"
echo "Enabling DDIO for further experiments..."
# Enable DDIO
sudo /home/jiaqi/tools/ddio-bench/change-ddio 1
sleep 2

# Iterate over each ddio_mask experiment with PCM measurement
for ddio_mask in "${ddio_masks[@]}"; do
    echo "----------------------------------------------------"
    echo "Experiment: DDIO ddio_mask 0x${ddio_mask}"
    echo "Setting DDIO ways to 0x${ddio_mask}..."
    sudo wrmsr 0xc8b 0x${ddio_mask}
    sleep 2

    # Run test_RR with PCM measurement (output file: pcm_${ddio_mask}.csv)
    run_with_pcm "result_change_ways/pcm_${pkt_size}_${ddio_mask}_${cycles}.csv" sudo ./build/test_RR -c 0x3 --main-lcore ${num_cores} -- -p 0 -q ${num_cores} -Q ${num_cores} -s ${pkt_size} -n 0 -c ${cycles} -d 0x${ddio_mask} -i ${interval}

    echo "Experiment with DDIO ddio_mask 0x${ddio_mask} completed."
done

echo "All experiments completed."
