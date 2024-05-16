#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <julia.h>
#include <ffi.h>

#define PATCH_VALUE(TYPE, NAME, ALIAS)  \
    extern void ALIAS;                  \
    TYPE NAME = (TYPE)(uint64_t)&ALIAS;

#define PATCH_JUMP(ALIAS, IP)      \
do {                               \
    extern void (ALIAS)(int);      \
    __attribute__((musttail))      \
    return (ALIAS)(IP);            \
} while (0);
