#include "common.h"

#define PATCH_JUMP(ALIAS, IP)      \
do {                               \
    extern void (ALIAS)(int);     \
    __attribute__((musttail))      \
    return (ALIAS)(IP); \
} while (0)

void
_JIT_ENTRY(int ip) {
   PATCH_JUMP(_JIT_CONT, ip+1);
}
