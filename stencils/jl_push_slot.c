#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(int, n, _JIT_N); // 1-based
   DEBUGSTMT("jl_push_slot", F, ip);
   F->tmps[i-1] = F->slots[n-1];
   PATCH_JUMP(_JIT_CONT, F, ip);
}
