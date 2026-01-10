#include <time.h>
#include <unistd.h>
#include <stdio.h>

int main() {
    struct timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 1000; // 1 microsecond sleep

    printf("Generating massive wakeups... (Ctrl+C to stop)\n");
    while(1) {
        nanosleep(&ts, NULL);
    }
    return 0;
}

