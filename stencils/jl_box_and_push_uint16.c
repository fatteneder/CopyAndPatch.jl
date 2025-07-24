#include "common.h"

typedef union {
   void *p;
   uint16_t v;
} converter_uint16_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_and_push_uint16", F, ip);
   converter_uint16_t c;
   c.p = x;
   uint16_t v = c.v;
   F->tmps[i-1] = jl_box_uint16(v);
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
