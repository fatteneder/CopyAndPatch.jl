#include "common.h"

typedef union {
   void *p;
   int8_t v;
} converter_int8_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_int8", F, ip);
   converter_int8_t c;
   c.p = x;
   int8_t v = c.v;
   F->tmps[i-1] = jl_box_int8(v);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
