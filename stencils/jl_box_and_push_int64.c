#include "common.h"

typedef union {
   void *p;
   int64_t v;
} converter_int64_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_and_push_int64", F, ip);
   converter_int64_t c;
   c.p = x;
   int64_t v = c.v;
   F->tmps[i-1] = jl_box_int64(v);
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
