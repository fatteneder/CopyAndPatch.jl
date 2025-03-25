#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(int, id, _JIT_ID); // 1-based
   DEBUGSTMT("jl_push_ssa", F, ip);
   F->tmps[i-1] = F->ssas[id-1];
   PATCH_JUMP(_JIT_CONT, F, ip);
}
