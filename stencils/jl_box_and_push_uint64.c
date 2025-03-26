#include "common.h"

typedef union {
   void *p;
   uint64_t v;
} converter_uint64_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_uint64", F, ip);
   converter_uint64_t c;
   c.p = x;
   uint64_t v = c.v;
   F->tmps[i-1] = jl_box_uint64(v);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
