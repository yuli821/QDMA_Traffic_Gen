#!/bin/bash

# Program to run
program="sudo ./build/test -c"
command1="--main-lcore"
command2="-n 4 0"
suffix="0 0"

# Arguments to use
arguments=("0x3" "0x7" "0x1f" "0x1ff" "0x7ff" "0x1fff")
arguments1=("1" "2" "4" "8" "10" "12")
# arguments=("0x7ff")
# arguments1=("10")
arguments2=("10" "74" "138" "202" "266" "330" "394" "458" "522" "586" "650" "714" "778" "842" "906" "970" "1034" "1098" "1162" "1226" "1290" "1354" "1418" "1482" "1546" "1610" "1674" "1738" "1802" "1866" "1930" "1994" "2058" "2122" "2186" "2250" "2314" "2379" "2442" "2506" "2570" "2634" "2698" "2762" "2826" "2890" "2954" "3018" "3082" "3146" "3210" "3274" "3338" "3402" "3466" "3530" "3594" "3658" "3722" "3786" "3850" "3914" "3978" "4042")

# Loop through arguments and run the program
for arg_index in "${!arguments[@]}"; do
    proc_mask=${arguments[$arg_index]} 
    numqueues=${arguments1[$arg_index]}
    for arg1 in "${arguments2[@]}"; do
        echo "Running $program with processor mask $proc_mask, $numqueues queues, and pktsize $arg1"
        $program $proc_mask $command1 $numqueues $command2 $numqueues $arg1 $suffix
        echo "-------------------------"
    done
done