import glob
import re
import csv

desired_cycles = "0"
desired_pkt_size = "128"

# Desired ddio_mask order for the CSV columns
# desired_order = [
#     "0", "c0000", "e0000", "f0000", "f8000", "fc000", "fe000", "ff000",
#     "ff800", "ffc00", "ffe00", "fff00", "fff80", "fffc0", "fffe0", "ffff0",
#     "ffff8", "ffffc", "ffffe", "fffff"
# ]

desired_order = [
    "0", "c0000", "f0000", "ff000", "fff00", "ffff0", "fffff"
]

desired_order = [
    "0", "c0000"
]

# ========================================================
# Part 1: Parse round_trip log files from the result folder.
# ========================================================
file_pattern = "result_change_ways/round_trip_*_*.txt"
files = glob.glob(file_pattern)
files.sort()  # for consistent ordering

# Regular expression to extract packet_size, ddio_mask, and cycles.
pattern = re.compile(r"round_trip_(\d+)_([0-9a-fA-F]+)_(\d+)\.txt")

# Dictionary to store round_trip data by ddio_mask.
# Each key is a ddio_mask string and its value is a list of 512 timestamp strings.
round_trip_data = {}

for filepath in files:
    filename = filepath.split('/')[-1]
    match = pattern.match(filename)
    if not match:
        print(f"File {filepath} does not match the expected pattern; skipping.")
        continue

    packet_size = match.group(1)
    ddio_mask = match.group(2).lower()
    cycles = match.group(3)
    if cycles != desired_cycles or packet_size != desired_pkt_size:
        continue

    with open(filepath, 'r') as file_obj:
        # Read non-empty lines.
        lines = [line.strip() for line in file_obj if line.strip()]
        if len(lines) != 512:
            print(f"Warning: File '{filepath}' has {len(lines)} lines (expected 512).")
        round_trip_data[ddio_mask] = lines

# Build the 512-row matrix of round_trip timestamps.
num_rows = 512
round_trip_rows = []
for i in range(num_rows):
    row = []
    for ddio in desired_order:
        timestamps = round_trip_data.get(ddio, [])
        row.append(timestamps[i] if i < len(timestamps) else "")
    round_trip_rows.append(row)

# ========================================================
# Part 2: Parse PCM CSV outputs for memory bandwidth.
# ========================================================
# We'll compute the average overall Memory Read and Write bandwidth.
# The PCM CSV file has two header rows. The second header row’s last three columns are:
# "Read", "Write", "Memory" (at indices 26, 27, and 28 respectively).
# We'll average columns 26 ("Read") and 27 ("Write") over all rows.
pcm_read_avg = {}   # key: ddio_mask, value: average Memory Read bandwidth (MB/s)
pcm_write_avg = {}  # key: ddio_mask, value: average Memory Write bandwidth (MB/s)

for ddio in desired_order:
    if ddio == "0":
        pcm_file = "result_change_ways/pcm_ddio_disabled.csv"
    else:
        pcm_file = f"result_change_ways/pcm_{desired_pkt_size}_{ddio}_{desired_cycles}.csv"

    try:
        with open(pcm_file, 'r') as f:
            reader = csv.reader(f)
            # Skip the first header row.
            try:
                header1 = next(reader)
                header2 = next(reader)
            except StopIteration:
                print(f"PCM file {pcm_file} does not have enough header rows.")
                pcm_read_avg[ddio] = ""
                pcm_write_avg[ddio] = ""
                continue

            # In our PCM CSV, we expect:
            # header2[26] -> "Read" and header2[27] -> "Write"
            # (Indexing is 0-based.)
            read_idx = 10
            write_idx = 11

            read_sum = 0.0
            write_sum = 0.0
            count = 0
            #skip first row
            first_row = next(reader)
            for row in reader:
                if len(row) < 28:
                    continue
                try:
                    read_val = float(row[read_idx])
                    write_val = float(row[write_idx])
                    read_sum += read_val
                    write_sum += write_val
                    count += 1
                except ValueError:
                    continue
            if count > 0:
                pcm_read_avg[ddio] = read_sum / count * 8 / 1000
                pcm_write_avg[ddio] = write_sum / count * 8 / 1000
            else:
                pcm_read_avg[ddio] = ""
                pcm_write_avg[ddio] = ""
    except FileNotFoundError:
        print(f"PCM file {pcm_file} not found for ddio_mask {ddio}.")
        pcm_read_avg[ddio] = ""
        pcm_write_avg[ddio] = ""

# ========================================================
# Part 3: Compute average round_trip timestamp per ddio_mask.
# ========================================================
round_trip_avg = {}
for ddio in desired_order:
    values = round_trip_data.get(ddio, [])
    total = 0.0
    count = 0
    for val in values:
        try:
            total += float(val)
            count += 1
        except ValueError:
            continue
    round_trip_avg[ddio] = (total / count) if count > 0 else ""

# ========================================================
# Part 4: Write the combined CSV.
# ========================================================
output_file = "combined_timestamps_with_pcm.csv"
with open(output_file, "w", newline='') as csvfile:
    writer = csv.writer(csvfile)

    # Write the header row: ddio_mask names.
    writer.writerow(desired_order)

    # Insert a summary row for PCM Memory Read bandwidth averages.
    read_row = []
    for ddio in desired_order:
        val = pcm_read_avg.get(ddio, "")
        if isinstance(val, float):
            val = f"{val:.8f}"
        read_row.append(val)
    writer.writerow(["PCM MemRead Avg"] + [""] * (len(desired_order) - 1))
    writer.writerow(read_row)

    # Insert a summary row for PCM Memory Write bandwidth averages.
    write_row = []
    for ddio in desired_order:
        val = pcm_write_avg.get(ddio, "")
        if isinstance(val, float):
            val = f"{val:.8f}"
        write_row.append(val)
    writer.writerow(["PCM MemWrite Avg"] + [""] * (len(desired_order) - 1))
    writer.writerow(write_row)

    # Insert a summary row for round_trip average values.
    avg_row = []
    for ddio in desired_order:
        val = round_trip_avg.get(ddio, "")
        if isinstance(val, float):
            val = f"{val:.2f}"
        avg_row.append(val)
    writer.writerow(["RoundTrip Avg"] + [""] * (len(desired_order) - 1))
    writer.writerow(avg_row)

    # Optionally add a blank row.
    writer.writerow([])

    # Write the 512 rows of detailed round_trip timestamps.
    for row in round_trip_rows:
        writer.writerow(row)

print(f"CSV file '{output_file}' has been created successfully.")
