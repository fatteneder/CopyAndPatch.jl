#include "common.h"

typedef union {
   void *p;
   double v;
} converter_double;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(void *, x, _JIT_X);
   DEBUGSTMT("jl_box_float64", F, ip);
   converter_double c;
   c.p = x;
   double v = c.v;
   F->tmps[i-1] = jl_box_float64(v);
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
