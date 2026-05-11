def toeplitz_hash(src_ip, dst_ip, src_port, dst_port, protocol):
    key = 0x6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa
    input_hs = (src_ip << 72) | (dst_ip << 40) | (src_port << 24) | (dst_port << 8) | protocol
    result = 0
    for i in range(104):
        if (input_hs >> i) & 1:
            key_slice = (key >> (288 - i)) & 0xFFFFFFFF
            result ^= key_slice
    return result & 0xFFFFFFFF

# Fixed values (from your hardware)
dst_ip = 0xC0A8640A  # 192.168.100.10
dst_port = 0x1234
protocol = 0x06

# Find IPs/ports that map to RSS index 0 and 1
for src_port in range(1000, 2000):
    src_ip = 0x0A000001  # Try 10.0.0.1
    h = toeplitz_hash(src_ip, dst_ip, src_port, dst_port, protocol)
    if (h & 0xF) == 0:
        print(f"RSS[0]: src_ip=0x{src_ip:08X}, src_port={src_port}, hash=0x{h:08X}")
        break

for src_port in range(1000, 2000):
    src_ip = 0x0A000002  # Try 10.0.0.2
    h = toeplitz_hash(src_ip, dst_ip, src_port, dst_port, protocol)
    if (h & 0xF) == 1:
        print(f"RSS[1]: src_ip=0x{src_ip:08X}, src_port={src_port}, hash=0x{h:08X}")
        break