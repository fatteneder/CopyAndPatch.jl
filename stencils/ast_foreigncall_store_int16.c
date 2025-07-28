#include "common.h"

typedef union {
   uint64_t p;
   int16_t v;
} converter_int16_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT("ast_foreigncall_store_int16", F, ip);
   converter_int16_t c;
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   c.p = (uint64_t)*rc;
   // printf("c.p = %p\n", c.p);
   // 
   F->ssas[ip-1] = jl_box_int16(c.v);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
