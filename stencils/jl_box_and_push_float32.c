#include "common.h"

typedef union {
   void *p;
   float v;
} converter_float;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_float32", F, ip);
   converter_float c;
   c.p = x;
   float v = c.v;
   F->tmps[i-1] = jl_box_float32(v);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
