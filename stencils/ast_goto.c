#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_JUMP(_JIT_CONT, ip);
}
