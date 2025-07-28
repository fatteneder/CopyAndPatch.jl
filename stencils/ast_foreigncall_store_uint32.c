#include "common.h"

typedef union {
   uint64_t p;
   uint32_t v;
} converter_uint32_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT("ast_foreigncall_store_uint32", F, ip);
   converter_uint32_t c;
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   c.p = (uint64_t)*rc;
   // printf("c.p = %p\n", c.p);
   // 
   F->ssas[ip-1] = jl_box_uint32(c.v);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
