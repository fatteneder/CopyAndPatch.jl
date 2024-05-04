#include "common.h"

void
_JIT_ENTRY(int ip) {
   PATCH_JUMP(_JIT_CONT, ip+1);
}
