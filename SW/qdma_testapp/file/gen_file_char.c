#include <stdio.h>
#include <stdlib.h>
#include <string.h>


int main (int argc, char** argv) {
    FILE* fp;
    int numKB;
    unsigned char buf[1024];
    fp = fopen("test.txt", "wb");
    if (fp == NULL) {
        printf("Could not open file to send.");
        exit(1);
    }
    if (argc > 1) {
        numKB = atoi(argv[1]);
    } else {
        numKB = 1;
    }
    for (int i = 0 ; i < numKB ; i++) {
        for (int j = 0 ; j < 1024 ; j++) {
            buf[j] = 'A' + (random() % 26);
        }
        fwrite(buf, sizeof(unsigned char), 1024, fp);
    }
    fclose(fp);
}
