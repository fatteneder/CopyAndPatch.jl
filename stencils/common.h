#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <julia.h>

#define PATCH_VALUE(TYPE, NAME, ALIAS)  \
    extern void ALIAS;                  \
    TYPE NAME = (TYPE)(uint64_t)&ALIAS;

#define PATCH_VALUE_AND_CONVERT(RECTYPE, TYPE, NAME, ALIAS)  \
    extern void ALIAS;                              \
    RECTYPE ALIAS##_ = (RECTYPE)(uint64_t)&ALIAS;   \
    TYPE NAME;                                      \
    memcpy(&NAME, &ALIAS##_, sizeof(TYPE));

#define PATCH_JUMP(ALIAS, IP)      \
do {                               \
    extern void (ALIAS)(int);     \
    __attribute__((musttail))      \
    return (ALIAS)(IP); \
} while (0)
