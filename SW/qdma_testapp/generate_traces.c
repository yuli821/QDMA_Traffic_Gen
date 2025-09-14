#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

double generate_normal_random(double mean, double std_dev) {
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    return mean + z0 * std_dev;
}

// Function to generate a log-normal distributed random number
double generate_lognormal_random(double mean, double std_dev) {
    double normal_mean = log(mean * mean / sqrt(std_dev * std_dev + mean * mean));
    double normal_std_dev = sqrt(log(1 + (std_dev * std_dev) / (mean * mean)));
    double normal_random = generate_normal_random(normal_mean, normal_std_dev);
    return exp(normal_random);
}

// Function to generate a set of log-normal distributed numbers and write to a file
void generate_lognormal_distribution(const char *filename, int count, double mean, double std_dev) {
    FILE *file = fopen(filename, "w");
    if (!file) {
        perror("Failed to open file");
        exit(EXIT_FAILURE);
    }

    for (int i = 0; i < count; i++) {
        double value = generate_lognormal_random(mean, std_dev);
        fprintf(file, "%.6f\n", value);
    }

    fclose(file);
    printf("Log-normal distribution written to %s\n", filename);
}

int main(int argc, char *argv) {
    const char * outputfile = "web.txt";
    int count = 600;
    double mean = -1.37;
    double std_dev = 1.97;
    srand(time(NULL));
    generate_lognormal_distribution(outputfile, count, mean, std_dev);
    return 0;
}