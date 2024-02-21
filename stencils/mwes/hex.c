#include <stdio.h>

union {
    double value;
    unsigned long long bits;
} converter;

int main() {
    converter.value = 1.1;
    printf("x = %16x\n", converter.bits);
    return 0;
}
