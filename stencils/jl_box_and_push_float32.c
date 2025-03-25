#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(float , x, _JIT_X);
   DEBUGSTMT("jl_box_float32", F, ip);
   F->tmps[i-1] = jl_box_float32(x);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
