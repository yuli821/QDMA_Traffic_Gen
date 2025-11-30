// test_tcp_connection.c - Updated version
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <net/if.h>
#include <errno.h>

int main(int argc, char *argv[]) {
    int sock;
    struct sockaddr_in addr;
    const char *ifname = "enp153s0";  // Change to your interface name
    const char *fpga_ip = "192.168.100.11";  // FPGA's IP address
    
    // Allow interface name and FPGA IP as arguments
    if (argc >= 2) {
        ifname = argv[1];
    }
    if (argc >= 3) {
        fpga_ip = argv[2];
    }
    
    // Create socket
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }
    
    // Bind socket to specific interface
    if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, ifname, strlen(ifname)) < 0) {
        perror("setsockopt SO_BINDTODEVICE");
        close(sock);
        return 1;
    }
    printf("Bound socket to interface: %s\n", ifname);
    
    // Configure destination address (FPGA's IP)
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(7777);
    if (inet_pton(AF_INET, fpga_ip, &addr.sin_addr) <= 0) {
        perror("inet_pton");
        close(sock);
        return 1;
    }
    
    printf("Connecting to FPGA at %s:7777 via interface %s...\n", fpga_ip, ifname);
    
    // Connect
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
        printf("Connected!\n");
        
        // Send data
        char *msg = "Hello FPGA!";
        if (send(sock, msg, strlen(msg), 0) < 0) {
            perror("send");
        } else {
            printf("Sent: %s\n", msg);
        }
        
        sleep(1);
        close(sock);
        printf("Closed!\n");
        return 0;
    }
    
    printf("Connection failed: %s\n", strerror(errno));
    close(sock);
    return 1;
}